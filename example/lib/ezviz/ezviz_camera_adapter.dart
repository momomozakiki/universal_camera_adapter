import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ezviz_flutter/ezviz_flutter.dart';
import 'package:flutter/widgets.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

/// This project's registered EZVIZ Open Platform AppKey — a public app
/// identifier, not a secret (see `tabs/ezviz_tab.dart` for the full
/// rationale). Shared by [EzvizCameraAdapter] and the standalone test tab.
const kEzvizAppKey = '59c8ee7cf07e45c3bec8978950c3d484';

/// [CameraAdapter] backend for EZVIZ cloud cameras, built on the vendored,
/// patched `ezviz_flutter` (see `example/third_party/ezviz_flutter` and
/// `docs/camera/ezviz-setup-guide.md`).
///
/// Sign-in is **not** this adapter's responsibility: per-user auth happens
/// once via [EzvizAuthManager.openLoginPage] (EZVIZ's own hosted login page),
/// and the native SDK persists the resulting token itself. [open] simply
/// reads that cached token — call it only after a successful sign-in.
/// Encrypted devices need a verification code; pass it via
/// `device.metadata['verificationCode']` on the [CameraDevice] given to
/// [open] (obtained from [listDevices] then `copyWith`), since the contract
/// has no dedicated parameter for it.
class EzvizCameraAdapter extends CameraAdapter {
  EzvizCameraAdapter({this.appKey = kEzvizAppKey});

  final String appKey;

  CameraDevice? _device;
  String? _accessToken;
  String? _verificationCode;
  EzvizPlayerController? _controller;

  @override
  bool get isOpen => _device != null;

  @override
  Future<List<CameraDevice>> listDevices() async {
    final devices = await EzvizDeviceManager.getDeviceList();
    return devices.map(_toCameraDevice).toList(growable: false);
  }

  CameraDevice _toCameraDevice(EzvizDeviceInfo info) => CameraDevice(
    id: info.deviceSerial,
    name: info.deviceName,
    lensFacing: CameraLensFacing.external,
    metadata: <String, dynamic>{
      'brand': 'ezviz',
      'isSupportPTZ': info.isSupportPTZ,
      'cameraNum': info.cameraNum,
    },
  );

  @override
  Future<void> open(
    CameraDevice device, {
    Duration timeout = kDefaultCameraTimeout,
  }) async {
    await close();
    final token = await EzvizAuthManager.getAccessToken().timeout(timeout);
    if (token == null) {
      throw StateError(
        'No signed-in EZVIZ account. Call EzvizAuthManager.openLoginPage() '
        'and complete sign-in before opening an EZVIZ device.',
      );
    }
    await EzvizManager.shared()
        .initSDK(EzvizInitOptions(appKey: appKey, accessToken: token.accessToken))
        .timeout(timeout);
    _accessToken = token.accessToken;
    _verificationCode = device.metadata['verificationCode'] as String?;
    _device = device;
  }

  @override
  Future<void> close() async {
    final controller = _controller;
    _controller = null;
    _device = null;
    _accessToken = null;
    _verificationCode = null;
    if (controller == null) return;
    controller.removePlayerEventHandler();
    await controller.stopRealPlay();
    await controller.release();
  }

  @override
  CameraCapabilities get capabilities {
    if (!isOpen) {
      throw StateError('EzvizCameraAdapter: no device is open.');
    }
    // Zoom/pan/tilt control is not implemented yet — playback and (once the
    // native capturePicture patch lands) frame capture only. Reported false
    // rather than read from EzvizDeviceInfo.isSupportPTZ: the contract
    // requires hasPan/hasTilt to reflect a wired setPan/setTilt, not raw
    // device support. See docs/camera/feature-matrix.md.
    return const CameraCapabilities();
  }

  @override
  Widget buildPreview() {
    final device = _device;
    final accessToken = _accessToken;
    if (device == null || accessToken == null) {
      throw StateError('EzvizCameraAdapter: no device is open.');
    }
    return EzvizPlayer(onCreated: (controller) => _onPlayerCreated(controller, device));
  }

  /// Mirrors `tabs/ezviz_tab.dart`'s `_EzvizNativePlayerState._onPlayerCreated`:
  /// `initPlayerByDevice`/`setPlayVerifyCode`/`startRealPlay` never resolve
  /// their method-channel future in this plugin version (confirmed via adb
  /// logcat during hardware verification — see `history/2026-W30.md`), so
  /// they're fired without awaiting; actual state changes/errors would need
  /// to come from `setPlayerEventHandler`, which the [CameraAdapter] contract
  /// has no channel for, so this adapter only wires the handler to keep the
  /// event stream drained (required by the native side), not to surface
  /// events — callers observe playback health via [captureFrame] failures.
  Future<void> _onPlayerCreated(
    EzvizPlayerController controller,
    CameraDevice device,
  ) async {
    _controller = controller;
    controller.setPlayerEventHandler((_) {}, (_) {});
    controller.initPlayerByDevice(device.id, 1);
    final code = _verificationCode;
    if (code != null && code.isNotEmpty) {
      controller.setPlayVerifyCode(code);
    }
    controller.startRealPlay();
  }

  @override
  Future<Uint8List> captureFrame({
    Duration timeout = kDefaultCameraTimeout,
  }) async {
    final controller = _controller;
    if (controller == null) {
      throw StateError('EzvizCameraAdapter: no active player to capture from.');
    }
    final path = await controller.capturePicture().timeout(timeout);
    if (path == null) {
      // The vendored ezviz_flutter's native capturePicture is currently a
      // stub that always returns null on both platforms — see
      // docs/camera/feature-matrix.md, "EZVIZ platform-view frame-capture
      // question — spiked, resolved". Once that native patch lands, this
      // will return a real file path.
      throw StateError(
        'EZVIZ frame capture is not yet wired up in the vendored plugin '
        '(native capturePicture is a stub). See docs/camera/feature-matrix.md.',
      );
    }
    return Uint8List.fromList(await File(path).readAsBytes());
  }

  @override
  Future<void> setZoom(
    double factor, {
    Duration timeout = kDefaultCameraTimeout,
  }) {
    throw UnsupportedError('EzvizCameraAdapter does not yet implement zoom control.');
  }
}
