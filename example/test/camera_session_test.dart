import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';
import 'package:universal_camera_adapter_example/camera_session.dart';

/// Minimal in-memory fake — `MockCameraAdapter` lives in the root package's
/// `test/` folder, which isn't exported from `lib/`, so it can't be imported
/// across the package boundary from here.
class _FakeAdapter extends CameraAdapter {
  _FakeAdapter(this._devices);

  final List<CameraDevice> _devices;
  bool _open = false;
  int closeCount = 0;

  @override
  Future<List<CameraDevice>> listDevices() async => _devices;

  @override
  Future<void> open(
    CameraDevice device, {
    Duration timeout = kDefaultCameraTimeout,
  }) async {
    _open = true;
  }

  @override
  Future<void> close() async {
    closeCount++;
    _open = false;
  }

  @override
  bool get isOpen => _open;

  @override
  CameraCapabilities get capabilities {
    if (!_open) throw StateError('_FakeAdapter: no device is open.');
    return const CameraCapabilities();
  }

  @override
  Widget buildPreview() => const SizedBox.shrink();

  @override
  Future<Uint8List> captureFrame({
    Duration timeout = kDefaultCameraTimeout,
  }) async => Uint8List(0);

  @override
  Future<void> setZoom(
    double factor, {
    Duration timeout = kDefaultCameraTimeout,
  }) async {}
}

void main() {
  group('CameraSession', () {
    late CameraAdapterRegistry registry;
    late _FakeAdapter adapterA;
    late _FakeAdapter adapterB;

    setUp(() {
      adapterA = _FakeAdapter(const [CameraDevice(id: 'a1', name: 'A one')]);
      adapterB = _FakeAdapter(const [CameraDevice(id: 'b1', name: 'B one')]);
      registry = CameraAdapterRegistry()
        ..register('a', () => adapterA, asDefault: true)
        ..register('b', () => adapterB);
    });

    test('starts on the registered default', () {
      final session = CameraSession(registry);
      expect(session.adapterType, 'a');
    });

    test('switchTo swaps the adapter, closes the old one, and resets state', () async {
      final session = CameraSession(registry);
      await session.refreshDevices();
      await session.open('a1');
      expect(session.isOpen, isTrue);

      await session.switchTo('b');

      expect(session.adapterType, 'b');
      expect(adapterA.closeCount, 1);
      expect(session.devices.map((d) => d.id), ['b1']);
      expect(session.selectedId, 'b1');
      expect(session.zoom, 1);
      expect(session.isOpen, isFalse);
    });

    test('switchTo is a no-op when already on the target type', () async {
      final session = CameraSession(registry);
      await session.switchTo('a');
      expect(adapterA.closeCount, 0);
      expect(session.adapterType, 'a');
    });

    test('switchTo an unknown type surfaces StateError', () {
      final session = CameraSession(registry);
      expect(() => session.switchTo('nope'), throwsStateError);
    });

    test('openDevice merges extra metadata and a later open(id) reuses it', () async {
      final session = CameraSession(registry);
      await session.switchTo('b');

      const withCode = CameraDevice(
        id: 'b1',
        name: 'B one',
        metadata: {'verificationCode': '1234'},
      );
      await session.openDevice(withCode);

      expect(session.selectedDevice?.metadata['verificationCode'], '1234');

      await session.close();
      await session.open('b1');
      expect(session.selectedDevice?.metadata['verificationCode'], '1234');
    });
  });
}
