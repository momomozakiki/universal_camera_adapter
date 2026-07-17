import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/widgets.dart';

import 'camera_adapter.dart';
import 'camera_types.dart';

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
    } on CameraException catch (e) {
      throw StateError('Failed to list cameras: ${e.code} ${e.description ?? ''}'.trim());
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
    } on CameraException catch (e) {
      throw StateError('Capture failed: ${e.code} ${e.description ?? ''}'.trim());
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
    } on CameraException catch (e) {
      throw StateError('Set zoom failed: ${e.code} ${e.description ?? ''}'.trim());
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
    } on CameraException catch (e) {
      throw StateError('Failed to enumerate cameras: ${e.code}');
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

  String _openErrorMessage(CameraException e) {
    final base = 'Failed to open camera: ${e.code} ${e.description ?? ''}'.trim();
    final denied = e.code.toLowerCase().contains('denied') ||
        e.code.toLowerCase().contains('permission');
    if (denied && Platform.isWindows) {
      return '$base\nIf the camera is disabled in Windows privacy settings, enable it under '
          'Settings → Privacy & security → Camera → "Let desktop apps access your camera".';
    }
    return base;
  }

  Future<void> _safeDispose(CameraController controller) async {
    try {
      await controller.dispose();
    } on CameraException {
      // Disposing a wedged controller can throw; nothing more we can do.
    }
  }
}
