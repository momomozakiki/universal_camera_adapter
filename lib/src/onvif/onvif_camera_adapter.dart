import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:xml/xml.dart';

import '../camera_adapter.dart';
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

/// Credentials + endpoint for an ONVIF camera.
///
/// **Secrets come from runtime config, never code** (see the `input-hardening`
/// skill / `SECURITY.md`). Do not log [password] or interpolate it into errors.
@immutable
class OnvifCredentials {
  const OnvifCredentials({
    required this.host,
    this.port = 80,
    this.username,
    this.password,
  });

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
    OnvifSoap? soap,
    OnvifHttpClient Function()? httpClientFactory,
    OnvifMediaServiceFactory? mediaServiceFactory,
    OnvifPreviewController Function()? previewFactory,
  })  : _soap = soap ?? const OnvifSoap(),
        _httpClientFactory = httpClientFactory ?? OnvifHttpClient.new,
        _mediaServiceFactory = mediaServiceFactory ?? OnvifMediaService.new,
        _previewFactory = previewFactory ?? RtspPreview.new;

  /// Connection details. When constructed via a zero-arg factory (registry
  /// tear-off), this is `null` and must be supplied before [open].
  final OnvifCredentials? credentials;

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
    final creds = credentials;
    if (creds == null) {
      throw StateError('ONVIFCameraAdapter.credentials must be supplied before open().');
    }

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
      await preview.open(streamUri, timeout: timeout);
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
