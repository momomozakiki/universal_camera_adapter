import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:xml/xml.dart';

import '../camera_adapter.dart';
import '../camera_types.dart';
import 'onvif_http_client.dart';
import 'onvif_soap.dart';

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
/// [open]/[close]/[isOpen] are real: [open] authenticates against the
/// device's ONVIF service (WS-UsernameToken PasswordDigest, with an RFC 2617
/// HTTP Digest fallback) by issuing `GetDeviceInformation`. Media/discovery/
/// PTZ remain scaffolding and throw [UnimplementedError] until later roadmap
/// items land.
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
  })  : _soap = soap ?? const OnvifSoap(),
        _httpClientFactory = httpClientFactory ?? OnvifHttpClient.new;

  /// Connection details. When constructed via a zero-arg factory (registry
  /// tear-off), this is `null` and must be supplied before [open].
  final OnvifCredentials? credentials;

  final OnvifSoap _soap;

  /// Builds a fresh [OnvifHttpClient] per [open] — the underlying
  /// `http.Client` is disposed on [close] (socket hygiene) and cannot be
  /// reused, so a later [open] needs a new one. Overridable for tests.
  final OnvifHttpClient Function() _httpClientFactory;

  OnvifHttpClient? _httpClient;
  bool _isOpen = false;

  static Never _planned() => throw UnimplementedError(
        'This ONVIF capability is planned — see ROADMAP v1.1. '
        'Auth (open/close) is implemented; media/discovery/PTZ are not yet.',
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
      _isOpen = true;
    } catch (_) {
      // open() failed: don't leave a dangling client behind.
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
    _httpClient?.close();
    _httpClient = null;
    _isOpen = false;
  }

  @override
  bool get isOpen => _isOpen;

  @override
  CameraCapabilities get capabilities => _planned();

  @override
  Widget buildPreview() => _planned();

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
