import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_camera_adapter/universal_camera_adapter.dart';

/// Characterisation test for the Android enumeration path.
///
/// Every other gate in this repo is host-side, and the mock adapters never
/// produce a realistically-shaped platform failure — so the classification in
/// `plugin_error_mapping.dart` had only ever been exercised against synthetic
/// errors. This drives a **camerax-shaped** [PlatformException] through the real
/// [FlutterCameraAdapter.listDevices] and records what actually happens.
///
/// The shape matters. Pigeon's `wrapError` builds the exception as
/// `code = exception.javaClass.simpleName` (so always a Java class name, never a
/// semantic code), `message = exception.toString()`, `details = the stack
/// frames`. That is why classification reads the *message* rather than the code.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/camera');

  /// What CameraX actually sends when it cannot hand over a camera. The cause
  /// is *not* distinguishable from this payload — see the test below.
  PlatformException cameraxError(String message) => PlatformException(
        code: 'ExecutionException',
        message: message,
        details: 'Cause: …, Stacktrace: at androidx.camera.core.…',
      );

  void mockAvailableCamerasThrowing(PlatformException error) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'availableCameras') throw error;
      return null;
    });
  }

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  group('FlutterCameraAdapter.listDevices — raw platform failures', () {
    test('a genuine no-camera report becomes an empty list, not a throw',
        () async {
      mockAvailableCamerasThrowing(
        cameraxError('java.lang.RuntimeException: Available cameras: 0'),
      );

      expect(await FlutterCameraAdapter().listDevices(), isEmpty);
    });

    test('no raw PlatformException escapes to the caller', () async {
      // The contract's central promise: whatever the plugin throws, the caller
      // sees the typed surface. This is the defect 36f6e06 fixed.
      mockAvailableCamerasThrowing(
        cameraxError('java.lang.SecurityException: something unexpected'),
      );

      await expectLater(
        FlutterCameraAdapter().listDevices(),
        throwsA(isA<StateError>()),
      );
    });

    test('no thrown message carries platform text or stack frames', () async {
      mockAvailableCamerasThrowing(
        cameraxError('java.lang.SecurityException: something unexpected'),
      );

      try {
        await FlutterCameraAdapter().listDevices();
        fail('expected a StateError');
      } on StateError catch (e) {
        expect(e.message, isNot(contains('androidx')));
        expect(e.message, isNot(contains('Stacktrace')));
        expect(e.message, isNot(contains('java.lang')));
      }
    });

    test(
      'CHARACTERISATION: an InitializationException is classified as '
      '"no camera" whatever its underlying cause',
      () async {
        // Recording current behaviour, NOT endorsing it. CameraX raises
        // InitializationException for several distinct conditions — permission
        // not granted, camera already in use, transient HAL failure — and this
        // payload cannot tell them apart, so all of them land here as "no
        // cameras" rather than as a recoverable error.
        //
        // The trade-off is deliberate: the alternative, matching on message
        // text for words like "denied", is what 36f6e06 removed for both
        // missing real failures and matching unrelated ones. Narrowing this
        // needs a real logcat payload from an affected device to narrow it
        // *against* — until then, changing it would trade a known behaviour for
        // a guessed one, and risks putting the Java stack trace back on screen.
        mockAvailableCamerasThrowing(
          cameraxError(
            'java.util.concurrent.ExecutionException: '
            'androidx.camera.core.InitializationException: '
            'java.lang.SecurityException: Camera permission denied',
          ),
        );

        expect(
          await FlutterCameraAdapter().listDevices(),
          isEmpty,
          reason: 'a permission denial currently reads as "no camera found"',
        );
      },
    );
  });
}
