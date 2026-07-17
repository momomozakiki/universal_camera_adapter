import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

import 'mock_camera_adapter.dart';

const _device = CameraDevice(id: '0', name: 'Mock Cam');
const _device2 = CameraDevice(id: '1', name: 'Mock Cam 2');

void main() {
  group('CameraAdapter contract (via MockCameraAdapter)', () {
    test('capabilities before open throws StateError', () {
      final adapter = MockCameraAdapter();
      expect(() => adapter.capabilities, throwsStateError);
    });

    test('buildPreview before open throws StateError', () {
      final adapter = MockCameraAdapter();
      expect(adapter.buildPreview, throwsStateError);
    });

    test('captureFrame before open throws StateError', () {
      final adapter = MockCameraAdapter();
      expect(adapter.captureFrame, throwsStateError);
    });

    test('open then capabilities/capture works', () async {
      final adapter = MockCameraAdapter(
        capabilities: const CameraCapabilities(hasZoom: true, maxZoomLevel: 4),
      );
      await adapter.open(_device);
      expect(adapter.isOpen, isTrue);
      expect(adapter.capabilities.hasZoom, isTrue);
      expect(await adapter.captureFrame(), isNotEmpty);
    });

    test('setPan / setTilt default to UnsupportedError', () async {
      final adapter = MockCameraAdapter();
      await adapter.open(_device);
      expect(() => adapter.setPan(10), throwsUnsupportedError);
      expect(() => adapter.setTilt(10), throwsUnsupportedError);
    });

    test('setZoom without zoom throws UnsupportedError', () async {
      final adapter = MockCameraAdapter();
      await adapter.open(_device);
      expect(() => adapter.setZoom(2), throwsUnsupportedError);
    });

    test('one device open at a time: reopening closes the previous', () async {
      final adapter = MockCameraAdapter();
      await adapter.open(_device);
      await adapter.open(_device2);
      expect(adapter.openCount, 2);
      expect(adapter.closeCount, 1); // previous device auto-closed
      expect(adapter.openedDevice, _device2);
    });

    test('injected StateError on open propagates', () async {
      final adapter = MockCameraAdapter()..errorOnOpen = StateError('denied');
      await expectLater(adapter.open(_device), throwsStateError);
      expect(adapter.isOpen, isFalse);
    });

    test('injected TimeoutException on capture propagates', () async {
      final adapter = MockCameraAdapter()..errorOnCapture = TimeoutException('slow');
      await adapter.open(_device);
      await expectLater(adapter.captureFrame(), throwsA(isA<TimeoutException>()));
    });

    test('close is idempotent and safe when not open', () async {
      final adapter = MockCameraAdapter();
      await adapter.close();
      expect(adapter.isOpen, isFalse);
      expect(adapter.closeCount, 0);
    });
  });

  group('Value types', () {
    test('CameraCapabilities equality & copyWith', () {
      const a = CameraCapabilities(hasZoom: true, maxZoomLevel: 4);
      final b = a.copyWith();
      expect(a, b);
      expect(a.copyWith(hasZoom: false), isNot(a));
    });

    test('CameraDevice equality & copyWith', () {
      const a = CameraDevice(id: '0', name: 'Cam');
      expect(a.copyWith(name: 'Cam'), a);
      expect(a.copyWith(name: 'Other'), isNot(a));
    });
  });
}
