import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../camera_adapter.dart';
import '../camera_types.dart';

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

/// **Planned** network/IP-camera backend (ROADMAP v1.1).
///
/// This is scaffolding: it registers under the `'onvif'` type and satisfies the
/// [CameraAdapter] contract so consumers compile against it, but every method
/// throws [UnimplementedError] until v1.1 lands the real SOAP/RTSP client.
///
/// When implemented, it must follow the `input-hardening` rules for every byte
/// off the wire (size-cap responses before parsing, no bare casts on parsed
/// XML, ReDoS-safe regex, scheme/host-validate returned URIs, RTSP over TCP,
/// no secrets in code or diagnostics) and map failures to the typed surface
/// ([StateError] / [TimeoutException] / [FormatException] / [UnsupportedError]).
///
/// See `docs/camera/onvif-setup-guide.md` for the network-permission
/// requirements and `lib/src/onvif/` for the service seams.
class ONVIFCameraAdapter extends CameraAdapter {
  ONVIFCameraAdapter({this.credentials});

  /// Connection details. When constructed via a zero-arg factory (registry
  /// tear-off), this is `null` and must be supplied before [open] in v1.1.
  final OnvifCredentials? credentials;

  static Never _planned() => throw UnimplementedError(
        'ONVIF backend is planned — see ROADMAP v1.1. '
        'This scaffolding registers the contract but is not yet functional.',
      );

  @override
  Future<List<CameraDevice>> listDevices() async => _planned();

  @override
  Future<void> open(CameraDevice device, {Duration timeout = kDefaultCameraTimeout}) async =>
      _planned();

  @override
  Future<void> close() async {
    // No-op: nothing is ever acquired in the scaffolding.
  }

  @override
  bool get isOpen => false;

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
