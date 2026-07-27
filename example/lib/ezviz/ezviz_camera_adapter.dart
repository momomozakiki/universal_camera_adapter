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

  /// Fetches the cached access token and initialises the native SDK, returning
  /// the token.
  ///
  /// **Every entry point that touches the native SDK must call this first.**
  /// `EZGlobalSDK.getInstance()` is null until `initSDK` has run, and the
  /// native `getDeviceList` dereferences it on a background Kotlin coroutine
  /// whose only `catch` is the EZVIZ SDK's own `BaseException` — so a
  /// `NullPointerException` there is not caught, escapes the coroutine and
  /// kills the process as a `FATAL EXCEPTION`. No Dart `try`/`catch` can
  /// intercept it. This method existing is what keeps that unreachable.
  ///
  /// Was previously inline in [open] only, which is exactly how [listDevices]
  /// came to reach the SDK uninitialised: restoring a saved EZVIZ camera at
  /// startup enumerates before it opens, so the app died before any UI
  /// existed. Confirmed on device (CPH2113, Android 12), and reproduced
  /// identically on the parent commit — this was never a regression, it was
  /// latent from the day `listDevices` was written.
  Future<String> _ensureSdk({Duration timeout = kDefaultCameraTimeout}) async {
    final token = await EzvizAuthManager.getAccessToken().timeout(timeout);
    if (token == null) {
      throw StateError(
        'No signed-in EZVIZ account. Sign in from the camera setup screen '
        'before using this camera.',
      );
    }
    await EzvizManager.shared()
        .initSDK(EzvizInitOptions(appKey: appKey, accessToken: token.accessToken))
        .timeout(timeout);
    return token.accessToken;
  }

  @override
  Future<List<CameraDevice>> listDevices() async {
    try {
      await _ensureSdk();
      final devices = await EzvizDeviceManager.getDeviceList().timeout(
        kDefaultCameraTimeout,
      );
      return devices.map(_toCameraDevice).toList(growable: false);
    } on StateError {
      // Already on the documented typed surface, carrying a written message
      // (the no-account case above) — pass it through rather than flattening.
      rethrow;
    } on TimeoutException {
      rethrow;
    } on Object {
      // Nothing untyped escapes the contract, whatever the plugin throws —
      // including the native SDK_NOT_INITIALIZED PlatformException. Mirrors
      // the ladder in FlutterCameraAdapter.listDevices. The message is
      // authored here and never reads platform text, so no stack trace can
      // reach a screen.
      throw StateError('Could not list EZVIZ cameras. Please try again.');
    }
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
    _accessToken = await _ensureSdk(timeout: timeout);
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
    // NOT awaited: like initPlayerByDevice/setPlayVerifyCode/startRealPlay,
    // the vendored native stopRealPlay handler (EzvizView.kt) never calls
    // result.success()/result.error() — awaiting it here hangs this Future
    // forever, which wedges CameraSession's serialized call queue for the
    // rest of the session (every later open/close/capture stalls in "busy").
    // Confirmed via the same class of bug already documented for the other
    // three calls in ezviz-setup-guide.md.
    unawaited(controller.stopRealPlay());
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

  /// The integration checklist for the EZVIZ backend.
  ///
  /// The vendored plugin's native `capturePicture` is a stub (see
  /// [captureFrame]), so frame capture — and the scanning features built on it
  /// — are `unvalidated`, not `supported`, until that native patch lands. This
  /// is the live "Under development" case the tri-state messaging exists for:
  /// the app has wired these, the camera is not at fault.
  @override
  Map<CameraFeature, CameraFeatureStatus> get declaredFeatures =>
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
      };

  @override
  Widget buildPreview() {
    final device = _device;
    final accessToken = _accessToken;
    if (device == null || accessToken == null) {
      throw StateError('EzvizCameraAdapter: no device is open.');
    }
    // Unlike package:camera's CameraPreview (which wraps itself in an
    // AspectRatio internally), EzvizPlayer is a bare platform view with no
    // intrinsic size — given unbounded constraints (e.g. inside PreviewTab's
    // scrollable Column), it renders with a nonsensical size and overlays
    // other widgets instead of showing video. Wrap it here so every caller
    // gets a self-contained, properly sized widget, matching what the
    // retired ezviz_tab.dart did manually.
    //
    // Keyed on the open device's id so switching to a different EZVIZ device
    // forces a clean remount of this platform view instead of Flutter
    // reusing the old EzvizPlayer element across the swap. (A same-device
    // reconnect that only recreates the controller isn't covered by this key
    // — that would need keying on the controller itself, which isn't
    // available synchronously here since EzvizPlayer only hands it back via
    // its `onCreated` callback.)
    return KeyedSubtree(
      key: ValueKey(device.id),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: EzvizPlayer(onCreated: (controller) => _onPlayerCreated(controller, device)),
      ),
    );
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
