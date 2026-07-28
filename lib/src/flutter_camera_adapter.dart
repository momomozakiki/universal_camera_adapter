import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter/widgets.dart';

import 'camera_adapter.dart';
import 'camera_feature.dart';
import 'camera_types.dart';
import 'plugin_error_mapping.dart';

/// Local-device camera backend, wrapping the federated `camera` plugin
/// (`camera_android` on Android, `camera_windows` on Windows).
///
/// Reference implementation of the [CameraAdapter] contract:
/// - opens exactly one device at a time ([open] closes any previous one);
/// - reports [CameraCapabilities.hasZoom] from the device's *actual* min/max
///   zoom, never assumed;
/// - reports `hasPan`/`hasTilt` as `false` (the plugin has no PTZ API) and
///   inherits the default [UnsupportedError]-throwing [setPan]/[setTilt];
/// - guards [captureFrame] against a hung native `takePicture()` call.
///
/// macOS/Linux are not supported (no `camera_macos`/`camera_linux` dependency).
class FlutterCameraAdapter extends CameraAdapter {
  FlutterCameraAdapter({
    ResolutionPreset resolutionPreset = ResolutionPreset.high,
  }) : _resolutionPreset = resolutionPreset;

  final ResolutionPreset _resolutionPreset;

  /// Defensive cap for a native `takePicture()` that never returns — some
  /// Windows camera drivers hang, which would otherwise wedge the plugin's own
  /// busy flag forever. Kept short and independent of the caller's timeout.
  static const Duration _captureHangGuard = Duration(seconds: 3);

  CameraController? _controller;
  CameraCapabilities _capabilities = const CameraCapabilities();
  bool _capturing = false;

  @override
  Future<List<CameraDevice>> listDevices() async {
    try {
      final cameras = await availableCameras();
      return cameras
          .map((c) => CameraDevice(
                id: c.name,
                name: c.name,
                lensFacing: _mapLensFacing(c.lensDirection),
                metadata: <String, dynamic>{
                  'sensorOrientation': c.sensorOrientation,
                  'lensDirection': c.lensDirection.name,
                },
              ))
          .toList(growable: false);
    } on TimeoutException {
      // Part of the documented typed surface — pass it through untouched
      // rather than flattening it into a StateError.
      rethrow;
    } on CameraException catch (e) {
      if (meansNoCamera(e)) return const <CameraDevice>[];
      throw StateError(describePluginFailure(e, 'list cameras'));
    } on PlatformException catch (e) {
      // Android only: camera_android_camerax's availableCameras() has no
      // try/catch, so a CameraX failure arrives raw here. "No camera" is an
      // empty list, not an error — CameraX's own advice for this state is to
      // retry, which is exactly what a Refresh does.
      if (meansNoCamera(e)) return const <CameraDevice>[];
      throw StateError(describePluginFailure(e, 'list cameras'));
    } on Object catch (e) {
      // Nothing untyped escapes the contract, whatever the plugin throws.
      throw StateError(describePluginFailure(e, 'list cameras'));
    }
  }

  @override
  Future<void> open(
    CameraDevice device, {
    Duration timeout = kDefaultCameraTimeout,
  }) async {
    // Invariant: one device open at a time.
    await close();

    final description = await _describe(device);
    final controller = CameraController(
      description,
      _resolutionPreset,
      enableAudio: false,
    );

    try {
      // On Android this triggers the runtime camera-permission prompt.
      await controller.initialize().timeout(timeout);
    } on TimeoutException {
      await _safeDispose(controller);
      rethrow;
    } on CameraException catch (e) {
      await _safeDispose(controller);
      throw StateError(_openErrorMessage(e));
    } on PlatformException catch (e) {
      await _safeDispose(controller);
      throw StateError(_openErrorMessage(e));
    } on Object catch (e) {
      await _safeDispose(controller);
      throw StateError(describePluginFailure(e, 'open the camera'));
    }

    _controller = controller;
    _capabilities = await _queryCapabilities(controller);
  }

  @override
  Future<void> close() async {
    final controller = _controller;
    _controller = null;
    _capabilities = const CameraCapabilities();
    _capturing = false;
    if (controller != null) {
      await _safeDispose(controller);
    }
  }

  @override
  bool get isOpen => _controller != null;

  @override
  CameraCapabilities get capabilities {
    _requireOpen();
    return _capabilities;
  }

  @override
  Widget buildPreview() {
    final controller = _requireOpen();
    return CameraPreview(controller);
  }

  /// The integration checklist for this backend — every [CameraFeature] stated.
  ///
  /// The base derivation fails safe (undeclared ⇒ `unvalidated`), so a working
  /// feature has to be *claimed*. `frameCapture` is a real `takePicture()` call
  /// exercised on both supported platforms and the scanning features are built
  /// on it, so those three are `supported`. Zoom is listed as `unvalidated`
  /// here only as a floor: [featureMatrix] overlays the *queried* min/max from
  /// [capabilities], which is the real answer and may raise or lower it.
  /// Pan/tilt are `unsupported` — the plugin has no PTZ API at all.
  @override
  Map<CameraFeature, CameraFeatureStatus> get declaredFeatures =>
      const <CameraFeature, CameraFeatureStatus>{
        CameraFeature.zoom: CameraFeatureStatus.unvalidated,
        CameraFeature.pan: CameraFeatureStatus.unsupported,
        CameraFeature.tilt: CameraFeatureStatus.unsupported,
        CameraFeature.frameCapture: CameraFeatureStatus.supported,
        CameraFeature.qrScanning: CameraFeatureStatus.supported,
        CameraFeature.barcodeScanning: CameraFeatureStatus.supported,
        CameraFeature.textRecognitionOcr: CameraFeatureStatus.unvalidated,
        CameraFeature.twoWayAudio: CameraFeatureStatus.unsupported,
        CameraFeature.motionEvents: CameraFeatureStatus.unsupported,
      };

  /// Zoom/pan/tilt come from the *queried* device, so they must win over the
  /// static [declaredFeatures] floor — the base getter applies the declaration
  /// last, which would pin zoom to `unvalidated` even on a camera that reports
  /// a real range.
  @override
  CameraFeatureMatrix get featureMatrix {
    final caps = capabilities; // throws StateError if not open — intentional.
    return super.featureMatrix.withStatuses(<CameraFeature, CameraFeatureStatus>{
      CameraFeature.zoom: caps.hasZoom
          ? CameraFeatureStatus.supported
          : CameraFeatureStatus.unsupported,
    });
  }

  @override
  Future<Uint8List> captureFrame({
    Duration timeout = kDefaultCameraTimeout,
  }) async {
    final controller = _requireOpen();
    if (_capturing) {
      throw StateError('A capture is already in progress.');
    }
    _capturing = true;
    try {
      // Guard against a hung native call with the shorter of the two budgets.
      final budget = timeout < _captureHangGuard ? timeout : _captureHangGuard;
      final XFile file = await controller.takePicture().timeout(budget);
      return await file.readAsBytes();
    } on TimeoutException {
      rethrow;
    } on Object catch (e) {
      throw StateError(describePluginFailure(e, 'capture a frame'));
    } finally {
      _capturing = false;
    }
  }

  @override
  Future<void> setZoom(
    double factor, {
    Duration timeout = kDefaultCameraTimeout,
  }) async {
    final controller = _requireOpen();
    if (!_capabilities.hasZoom) {
      throw UnsupportedError('This camera does not support zoom.');
    }
    final clamped =
        factor.clamp(_capabilities.minZoomLevel, _capabilities.maxZoomLevel).toDouble();
    try {
      await controller.setZoomLevel(clamped).timeout(timeout);
    } on TimeoutException {
      rethrow;
    } on Object catch (e) {
      throw StateError(describePluginFailure(e, 'set the zoom level'));
    }
  }

  // Pan/tilt inherit the default UnsupportedError-throwing implementations —
  // the plugin has no PTZ API, and capabilities report hasPan/hasTilt = false.

  // --- internals ---

  CameraController _requireOpen() {
    final controller = _controller;
    if (controller == null) {
      throw StateError('Camera is not open. Call open(device) first.');
    }
    return controller;
  }

  Future<CameraDescription> _describe(CameraDevice device) async {
    final List<CameraDescription> cameras;
    try {
      cameras = await availableCameras();
    } on TimeoutException {
      rethrow;
    } on Object catch (e) {
      // Covers CameraException, the bare PlatformException the Android backend
      // can throw here, and anything else. A "no camera at all" result is not
      // special-cased: the requested device is gone either way, and the message
      // below already says so precisely.
      throw StateError(describePluginFailure(e, 'find that camera'));
    }
    for (final c in cameras) {
      if (c.name == device.id) return c;
    }
    throw StateError('Camera "${device.id}" is no longer available.');
  }

  Future<CameraCapabilities> _queryCapabilities(CameraController controller) async {
    // Zoom is best-effort: some drivers throw here. If they do, report no zoom.
    try {
      final minZoom = await controller.getMinZoomLevel();
      final maxZoom = await controller.getMaxZoomLevel();
      final hasZoom = maxZoom > minZoom;
      return CameraCapabilities(
        hasZoom: hasZoom,
        minZoomLevel: minZoom,
        maxZoomLevel: maxZoom,
        // No PTZ on the local plugin.
        hasPan: false,
        hasTilt: false,
      );
    } on CameraException {
      return const CameraCapabilities();
    }
  }

  static CameraLensFacing _mapLensFacing(CameraLensDirection direction) {
    switch (direction) {
      case CameraLensDirection.back:
        return CameraLensFacing.back;
      case CameraLensDirection.front:
        return CameraLensFacing.front;
      case CameraLensDirection.external:
        return CameraLensFacing.external;
    }
  }

  /// A user-safe message for a failed [open].
  ///
  /// Permission is detected by an **exact** platform error code, not by
  /// searching the text for "denied" — both platforms emit the same
  /// `CameraAccessDenied` constant (see [kPermissionDeniedCodes]), and the
  /// message itself is never user-safe to echo.
  String _openErrorMessage(Object e) {
    if (!meansPermissionDenied(e)) {
      return describePluginFailure(e, 'open the camera');
    }
    logPluginFailure(e, 'open the camera');
    const base = 'Camera access is blocked.';
    if (Platform.isWindows) {
      return '$base Enable it under Settings → Privacy & security → Camera → '
          '"Let desktop apps access your camera", then try again.';
    }
    if (Platform.isAndroid) {
      return '$base Allow the camera permission in Settings → Apps → '
          'this app → Permissions, then try again.';
    }
    return '$base Allow the camera permission in your system settings, then '
        'try again.';
  }

  Future<void> _safeDispose(CameraController controller) async {
    try {
      await controller.dispose();
    } on CameraException {
      // Disposing a wedged controller can throw; nothing more we can do.
    }
  }
}
