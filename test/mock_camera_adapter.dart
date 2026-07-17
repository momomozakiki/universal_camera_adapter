import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

/// A contract-faithful [CameraAdapter] fake for unit-testing consumer logic
/// without hardware.
///
/// Configure the devices it lists and the capabilities it reports; inject an
/// exception into any method to exercise a consumer's error handling. It honors
/// the real contract invariants: one device open at a time, [capabilities] and
/// [buildPreview] throw [StateError] before [open], and [captureFrame] returns
/// the configured bytes.
class MockCameraAdapter extends CameraAdapter {
  MockCameraAdapter({
    List<CameraDevice> devices = const <CameraDevice>[],
    CameraCapabilities capabilities = const CameraCapabilities(),
    Uint8List? frameBytes,
  })  : _devices = devices,
        _capabilities = capabilities,
        _frameBytes = frameBytes ?? Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xD9]);

  final List<CameraDevice> _devices;
  final CameraCapabilities _capabilities;
  final Uint8List _frameBytes;

  bool _open = false;
  CameraDevice? openedDevice;
  int openCount = 0;
  int closeCount = 0;

  /// Inject exceptions to exercise consumer error paths. If set, the method
  /// throws instead of performing its normal behavior.
  Object? errorOnOpen;
  Object? errorOnCapture;
  Object? errorOnSetZoom;

  @override
  Future<List<CameraDevice>> listDevices() async => _devices;

  @override
  Future<void> open(CameraDevice device, {Duration timeout = kDefaultCameraTimeout}) async {
    // Invariant: opening closes any previously-open device first.
    if (_open) {
      await close();
    }
    if (errorOnOpen != null) {
      throw errorOnOpen!;
    }
    _open = true;
    openedDevice = device;
    openCount++;
  }

  @override
  Future<void> close() async {
    if (_open) {
      closeCount++;
    }
    _open = false;
    openedDevice = null;
  }

  @override
  bool get isOpen => _open;

  @override
  CameraCapabilities get capabilities {
    _requireOpen();
    return _capabilities;
  }

  @override
  Widget buildPreview() {
    _requireOpen();
    return const SizedBox.shrink();
  }

  @override
  Future<Uint8List> captureFrame({Duration timeout = kDefaultCameraTimeout}) async {
    _requireOpen();
    if (errorOnCapture != null) {
      throw errorOnCapture!;
    }
    return _frameBytes;
  }

  @override
  Future<void> setZoom(double factor, {Duration timeout = kDefaultCameraTimeout}) async {
    _requireOpen();
    if (errorOnSetZoom != null) {
      throw errorOnSetZoom!;
    }
    if (!_capabilities.hasZoom) {
      throw UnsupportedError('Mock camera has no zoom.');
    }
  }

  // setPan / setTilt inherit the default UnsupportedError-throwing behavior.

  void _requireOpen() {
    if (!_open) {
      throw StateError('Camera is not open. Call open(device) first.');
    }
  }
}
