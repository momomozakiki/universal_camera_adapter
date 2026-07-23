import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:xml/xml.dart';

import '../camera_adapter.dart';
import '../camera_feature.dart';
import '../camera_types.dart';
import 'onvif_http_client.dart';
import 'onvif_media_service.dart';
import 'onvif_soap.dart';
import 'rtsp_preview.dart';

/// Factory signature for building an [OnvifMediaServiceBase] against an
/// already-authenticated [OnvifHttpClient]. Overridable for tests so they
/// never have to touch a real [OnvifMediaService]/HTTP client.
typedef OnvifMediaServiceFactory = OnvifMediaServiceBase Function({
  required String host,
  required int port,
  String? username,
  String? password,
  required OnvifHttpClient httpClient,
});

/// Port assumed for an ONVIF device service when none is configured.
///
/// ONVIF rides on plain HTTP, so `80` is the conventional default. Devices that
/// expose the service elsewhere (EZVIZ commonly uses `8000`) must say so via
/// `port`.
const int kDefaultOnvifPort = 80;

/// Credentials + endpoint for an ONVIF camera.
///
/// **Secrets come from runtime config, never code** (see the `input-hardening`
/// skill / `SECURITY.md`). Do not log [password] or interpolate it into errors.
@immutable
class OnvifCredentials {
  const OnvifCredentials({
    required this.host,
    this.port = kDefaultOnvifPort,
    this.username,
    this.password,
  });

  /// Builds credentials from a [CameraDevice.metadata] map.
  ///
  /// Keys are the **brand-neutral ONVIF vocabulary** — `host`, `port`,
  /// `username`, `password` — so any ONVIF-compliant camera (Hikvision, Dahua,
  /// Reolink, Axis, EZVIZ, …) is configured the same way; that interoperability
  /// is the entire point of the standard. Brand-specific extras may ride in the
  /// same map under their own keys and are ignored here. `port` defaults to
  /// [kDefaultOnvifPort] when absent.
  ///
  /// This is how a registry-created adapter receives per-camera configuration:
  /// a `CameraProfile` persists the non-secret `host`/`port`/`username` in
  /// `device.metadata`, and the session merges the secret in from
  /// `CameraSecretStore` just before [ONVIFCameraAdapter.open]. Many cameras of
  /// mixed brands can therefore be connected at once — one profile and one
  /// adapter instance each.
  ///
  /// **The map is untrusted input** (`input-hardening` Rule 1): it round-trips
  /// through persisted JSON, so every field is type-checked with `is!` before it
  /// is read — never a bare `as`, which would turn a hand-edited preferences
  /// file into an uncaught `TypeError`. All problems are collected and reported
  /// together instead of failing on the first one.
  ///
  /// Throws [FormatException] when a key is present but malformed (wrong type,
  /// unparseable or out-of-range port, blank or over-long host), and
  /// [StateError] when `host` is simply absent — matching the adapter's typed
  /// error surface. Never leaks a raw `TypeError`.
  ///
  /// Problem messages name the offending key and its runtime type, **never its
  /// value**, so a malformed-password error cannot echo the password.
  factory OnvifCredentials.fromMetadata(Map<String, dynamic> metadata) {
    final problems = <String>[];

    // --- host: required, non-blank, length-capped ---
    final rawHost = metadata['host'];
    String? host;
    if (rawHost == null) {
      // Absent is a *missing config* case, not a malformed one — it maps to
      // StateError below, after any malformed sibling keys are reported.
    } else if (rawHost is! String) {
      problems.add("'host' must be a String (got ${rawHost.runtimeType})");
    } else if (rawHost.trim().isEmpty) {
      problems.add("'host' must not be blank");
    } else if (rawHost.length > _maxHostLength) {
      // Bounded before it ever reaches a URI builder or the network stack.
      problems.add("'host' exceeds $_maxHostLength characters");
    } else {
      host = rawHost.trim();
    }

    // --- port: optional; int or a numeric String; must be a valid TCP port ---
    var port = kDefaultOnvifPort;
    final rawPort = metadata['port'];
    if (rawPort != null) {
      int? parsed;
      if (rawPort is int) {
        parsed = rawPort;
      } else if (rawPort is String) {
        // JSON round-trips and text fields both produce Strings here.
        parsed = int.tryParse(rawPort.trim());
        if (parsed == null) {
          problems.add("'port' is not a number");
        }
      } else {
        problems.add("'port' must be an int or a numeric String "
            '(got ${rawPort.runtimeType})');
      }
      if (parsed != null) {
        if (parsed < _minPort || parsed > _maxPort) {
          problems.add("'port' must be between $_minPort and $_maxPort");
        } else {
          port = parsed;
        }
      }
    }

    final username = _optionalString(metadata, 'username', problems);
    final password = _optionalString(metadata, 'password', problems);

    if (problems.isNotEmpty) {
      throw FormatException(
        'Malformed ONVIF connection metadata: ${problems.join('; ')}.',
      );
    }
    if (host == null) {
      throw StateError(
        'ONVIF connection metadata has no "host" entry. Either pass '
        'OnvifCredentials to the ONVIFCameraAdapter constructor, or set '
        'device.metadata["host"] on the CameraDevice passed to open().',
      );
    }

    return OnvifCredentials(
      host: host,
      port: port,
      username: username,
      password: password,
    );
  }

  /// Reads an optional `String` field, recording a problem for a wrong type.
  /// An empty string is normalized to `null` (an unset field, not a blank one).
  static String? _optionalString(
    Map<String, dynamic> metadata,
    String key,
    List<String> problems,
  ) {
    final raw = metadata[key];
    if (raw == null) return null;
    if (raw is! String) {
      // Report the type only — `raw` may be a secret.
      problems.add("'$key' must be a String (got ${raw.runtimeType})");
      return null;
    }
    return raw.isEmpty ? null : raw;
  }

  /// Longest accepted [host]; a fully-qualified domain name maxes out at 253
  /// octets, so anything beyond this is malformed rather than merely unusual.
  static const int _maxHostLength = 255;
  static const int _minPort = 1;
  static const int _maxPort = 65535;

  final String host;
  final int port;
  final String? username;
  final String? password;

  @override
  String toString() => 'OnvifCredentials(host: $host, port: $port, '
      'username: ${username == null ? '<none>' : '<set>'}, password: <redacted>)';
}

/// **Partially implemented** network/IP-camera backend (ROADMAP v1.1).
///
/// [open]/[close]/[isOpen]/[buildPreview] are real: [open] authenticates
/// against the device's ONVIF service (WS-UsernameToken PasswordDigest, with
/// an RFC 2617 HTTP Digest fallback) via `GetDeviceInformation`, then
/// resolves the main media profile's RTSP URI (`GetProfiles`/`GetStreamUri`)
/// and opens it in a `media_kit`-backed preview player. `captureFrame`, PTZ,
/// and discovery remain scaffolding and throw [UnimplementedError] until
/// later roadmap items land.
///
/// Failures map to the typed surface ([StateError] / [TimeoutException] /
/// [FormatException] / [UnsupportedError]) per the `camera-adapter-authoring`
/// skill — never a raw plugin/SDK/HTTP exception.
///
/// See `docs/camera/onvif-setup-guide.md` for the network-permission
/// requirements and `lib/src/onvif/` for the service seams.
class ONVIFCameraAdapter extends CameraAdapter {
  ONVIFCameraAdapter({
    this.credentials,
    this.verboseLogging = false,
    OnvifSoap? soap,
    OnvifHttpClient Function()? httpClientFactory,
    OnvifMediaServiceFactory? mediaServiceFactory,
    OnvifPreviewController Function()? previewFactory,
  })  : _soap = soap ?? const OnvifSoap(),
        _httpClientFactory =
            httpClientFactory ?? (() => OnvifHttpClient(verboseLogging: verboseLogging)),
        _mediaServiceFactory = mediaServiceFactory ?? OnvifMediaService.new,
        _previewFactory = previewFactory ?? RtspPreview.new;

  /// Connection details supplied at construction, for callers that build the
  /// adapter directly.
  ///
  /// `null` when constructed via a zero-arg factory (a registry tear-off) —
  /// which is the normal path. In that case [open] reads the connection details
  /// from `device.metadata` via [OnvifCredentials.fromMetadata], so setup flows
  /// through `open(device)` exactly like every other backend. When both are
  /// present, this field wins.
  final OnvifCredentials? credentials;

  /// When true (and no [httpClientFactory] override is supplied), the
  /// default [OnvifHttpClient] logs each request/response to the console.
  /// Off by default — intended for manual hardware debugging.
  final bool verboseLogging;

  final OnvifSoap _soap;

  /// Builds a fresh [OnvifHttpClient] per [open] — the underlying
  /// `http.Client` is disposed on [close] (socket hygiene) and cannot be
  /// reused, so a later [open] needs a new one. Overridable for tests.
  final OnvifHttpClient Function() _httpClientFactory;

  /// Builds the [OnvifMediaService] used to resolve the RTSP stream URI.
  /// Overridable for tests.
  final OnvifMediaServiceFactory _mediaServiceFactory;

  /// Builds the preview player. Overridable for tests, so unit tests never
  /// have to touch a real media_kit/native player.
  final OnvifPreviewController Function() _previewFactory;

  OnvifHttpClient? _httpClient;
  OnvifPreviewController? _preview;
  bool _isOpen = false;

  static Never _planned() => throw UnimplementedError(
        'This ONVIF capability is planned — see ROADMAP v1.1. '
        'Auth, media service, and RTSP preview are implemented; '
        'capture/PTZ/discovery are not yet.',
      );

  @override
  Future<List<CameraDevice>> listDevices() async => _planned();

  @override
  Future<void> open(CameraDevice device, {Duration timeout = kDefaultCameraTimeout}) async {
    // Constructor-supplied credentials win; otherwise read them off the device
    // being opened. This is what lets a registry-created instance connect at
    // all — see [credentials].
    //
    // SECURITY: never log `device.metadata` from here. The caller merges the
    // secret into a transient copy of the device just before open(), so at this
    // point the map carries the plaintext password. Log `creds` instead —
    // [OnvifCredentials.toString] redacts it.
    final creds = credentials ?? OnvifCredentials.fromMetadata(device.metadata);

    final token = (creds.username != null && creds.password != null)
        ? _soap.wsUsernameToken(creds.username!, creds.password!)
        : null;
    final envelope = _soap.buildEnvelope('GetDeviceInformation', token: token);

    // A prior open() that was never closed still holds a live client; the
    // contract requires open() to close any previous device first.
    await close();
    final httpClient = _httpClientFactory();
    _httpClient = httpClient;

    try {
      final responseBody = await httpClient.post(
        creds.host,
        creds.port,
        envelope,
        username: creds.username,
        password: creds.password,
        timeout: timeout,
      );
      _validateDeviceInformationResponse(responseBody);

      final mediaService = _mediaServiceFactory(
        host: creds.host,
        port: creds.port,
        username: creds.username,
        password: creds.password,
        httpClient: httpClient,
      );
      final profiles = await mediaService.getProfiles(timeout: timeout);
      if (profiles.isEmpty) {
        throw StateError('ONVIF device reported no media profiles.');
      }
      final streamUri = await mediaService.getStreamUri(
        profiles.first.token,
        timeout: timeout,
      );

      final preview = _previewFactory();
      await preview.open(
        streamUri,
        username: creds.username,
        password: creds.password,
        timeout: timeout,
      );
      _preview = preview;

      _isOpen = true;
    } catch (_) {
      // open() failed: don't leave a dangling client/preview behind.
      await close();
      rethrow;
    }
  }

  void _validateDeviceInformationResponse(String body) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(body);
    } on XmlException catch (e) {
      throw FormatException('Malformed ONVIF response: ${e.message}');
    }

    // Match by local name: SOAP elements are namespace-qualified (e.g.
    // `soap:Fault`), and the prefix isn't guaranteed across devices.
    final elementLocalNames =
        document.descendants.whereType<XmlElement>().map((e) => e.name.local).toSet();
    if (elementLocalNames.contains('Fault')) {
      throw StateError('ONVIF device returned a SOAP Fault for GetDeviceInformation.');
    }
    if (!elementLocalNames.contains('GetDeviceInformationResponse')) {
      throw const FormatException(
        'ONVIF response did not contain a GetDeviceInformationResponse element.',
      );
    }
  }

  @override
  Future<void> close() async {
    final preview = _preview;
    _preview = null;
    if (preview != null) {
      await preview.dispose();
    }
    _httpClient?.close();
    _httpClient = null;
    _isOpen = false;
  }

  @override
  bool get isOpen => _isOpen;

  @override
  CameraCapabilities get capabilities => _planned();

  @override
  CameraFeatureMatrix get featureMatrix {
    if (!_isOpen) {
      throw StateError('ONVIFCameraAdapter is not open. Call open(device) first.');
    }
    // Built explicitly rather than via the base derivation: [capabilities]
    // still throws UnimplementedError here (ROADMAP v1.1), so the base getter
    // can't read it. Zoom/PTZ are not yet wired (AbsoluteMove pending), and
    // frame capture / scanning are unvalidated until GetSnapshotUri lands —
    // reported unvalidated, not supported, so scanning features stay gated.
    return CameraFeatureMatrix.fromStatuses(
      const <CameraFeature, CameraFeatureStatus>{
        CameraFeature.zoom: CameraFeatureStatus.unsupported,
        CameraFeature.pan: CameraFeatureStatus.unsupported,
        CameraFeature.tilt: CameraFeatureStatus.unsupported,
        CameraFeature.frameCapture: CameraFeatureStatus.unvalidated,
        CameraFeature.qrScanning: CameraFeatureStatus.unvalidated,
        CameraFeature.barcodeScanning: CameraFeatureStatus.unvalidated,
        CameraFeature.textRecognitionOcr: CameraFeatureStatus.unvalidated,
        CameraFeature.twoWayAudio: CameraFeatureStatus.unvalidated,
        CameraFeature.motionEvents: CameraFeatureStatus.unvalidated,
      },
    );
  }

  @override
  Widget buildPreview() {
    if (!_isOpen) {
      throw StateError('ONVIFCameraAdapter is not open. Call open(device) first.');
    }
    final preview = _preview;
    if (preview == null) {
      throw StateError('ONVIFCameraAdapter has no active preview.');
    }
    return preview.buildWidget();
  }

  @override
  Future<Uint8List> captureFrame({Duration timeout = kDefaultCameraTimeout}) async => _planned();

  @override
  Future<void> setZoom(double factor, {Duration timeout = kDefaultCameraTimeout}) async =>
      _planned();

  @override
  Future<void> setPan(double angle, {Duration timeout = kDefaultCameraTimeout}) async => _planned();

  @override
  Future<void> setTilt(double angle, {Duration timeout = kDefaultCameraTimeout}) async =>
      _planned();
}
