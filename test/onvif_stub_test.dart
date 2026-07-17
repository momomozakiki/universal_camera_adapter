import 'package:flutter_test/flutter_test.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

void main() {
  group('ONVIFCameraAdapter (scaffolding)', () {
    test('registers under "onvif" and is a CameraAdapter', () {
      final registry = CameraAdapterRegistry()
        ..register('onvif', ONVIFCameraAdapter.new);
      expect(registry.isRegistered('onvif'), isTrue);
      expect(registry.create('onvif'), isA<CameraAdapter>());
    });

    test('is not open and close() is a safe no-op', () async {
      final adapter = ONVIFCameraAdapter();
      expect(adapter.isOpen, isFalse);
      await adapter.close(); // must not throw
    });

    test('functional methods throw UnimplementedError (planned v1.1)', () async {
      final adapter = ONVIFCameraAdapter(
        credentials: const OnvifCredentials(host: '192.168.1.100'),
      );
      await expectLater(adapter.listDevices(), throwsUnimplementedError);
      await expectLater(
        adapter.open(const CameraDevice(id: 'x', name: 'x')),
        throwsUnimplementedError,
      );
      expect(() => adapter.capabilities, throwsUnimplementedError);
      expect(adapter.buildPreview, throwsUnimplementedError);
    });

    test('credentials redact the password in toString', () {
      const creds = OnvifCredentials(
        host: 'cam.local',
        username: 'admin',
        password: 'hunter2',
      );
      expect(creds.toString(), isNot(contains('hunter2')));
      expect(creds.toString(), contains('redacted'));
    });
  });
}
