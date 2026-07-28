import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_camera_adapter/src/plugin_error_mapping.dart';

/// The exception from the bug report, reproduced field-for-field.
///
/// Built the way Pigeon's `wrapError` does on Android
/// (`camera_android_camerax/android/…/CameraXLibrary.g.kt:29-38`):
/// `code` = the Java class's simple name, `message` = `exception.toString()`,
/// `details` = the cause plus `Log.getStackTraceString(exception)`. Getting
/// these three fields right is what makes the test meaningful — the stack
/// frames live in `details`, and `PlatformException.toString()` prints all
/// three, which is how the whole dump reached the screen.
PlatformException _cameraXNoCameraException() {
  return PlatformException(
    code: 'ExecutionException',
    message: 'java.util.concurrent.ExecutionException: '
        'androidx.camera.core.InitializationException: '
        'androidx.camera.core.CameraUnavailableException: Device reporting '
        'less cameras than anticipated. On real devices: Retrying '
        'initialization might resolve temporary camera errors. On emulators: '
        'Ensure virtual camera configuration matches supported camera '
        'features as reported by PackageManager#hasSystemFeature. '
        'Available cameras: 0',
    details: 'Cause: androidx.camera.core.InitializationException, '
        'Stacktrace: java.util.concurrent.ExecutionException\n'
        '\tat androidx.concurrent.futures.AbstractResolvableFuture.'
        'getDoneValue(AbstractResolvableFuture.java:518)\n'
        '\tat androidx.camera.core.CameraX.lambda\$initAndRetryRecursively\$3'
        '\$androidx-camera-core-CameraX(CameraX.java:527)',
  );
}

/// Substrings that must never appear in anything shown to a user.
const List<String> _forbidden = <String>[
  'at androidx.',
  'PlatformException',
  'java.util.concurrent',
  'ExecutionException',
  'Stacktrace',
];

void main() {
  group('meansNoCamera', () {
    test('classifies the CameraX failure from the bug report', () {
      expect(meansNoCamera(_cameraXNoCameraException()), isTrue);
    });

    test('matches on the androidx class name alone', () {
      // The stable half of the signal: if CameraX rewords its English prose,
      // the public type name still identifies the condition.
      expect(
        meansNoCamera(
          PlatformException(
            code: 'ExecutionException',
            message: 'androidx.camera.core.CameraUnavailableException: '
                'some future rewording',
          ),
        ),
        isTrue,
      );
    });

    test('matches on the English text alone', () {
      expect(
        meansNoCamera(
          PlatformException(code: 'x', message: 'Available cameras: 0'),
        ),
        isTrue,
      );
    });

    test('does not classify an unrelated platform failure', () {
      expect(
        meansNoCamera(
          PlatformException(code: 'error', message: 'Disk full'),
        ),
        isFalse,
      );
    });

    test('does not classify a non-platform error', () {
      expect(meansNoCamera(StateError('nope')), isFalse);
      expect(meansNoCamera(ArgumentError('nope')), isFalse);
    });
  });

  group('meansPermissionDenied', () {
    test('matches the exact code both platforms emit', () {
      // Android: CameraPermissionsManager.java:36.
      // Windows: camera_windows/windows/camera.cpp:10. Same constant.
      expect(
        meansPermissionDenied(PlatformException(code: 'CameraAccessDenied')),
        isTrue,
      );
      expect(
        meansPermissionDenied(PlatformException(code: 'AudioAccessDenied')),
        isTrue,
      );
    });

    test('does NOT match a message that merely mentions denial', () {
      // The regression this replaced: `code.contains('denied')` matched
      // unrelated failures and missed differently-worded real ones.
      expect(
        meansPermissionDenied(
          PlatformException(
            code: 'ExecutionException',
            message: 'the request was denied by the permission service',
          ),
        ),
        isFalse,
      );
    });
  });

  group('describePluginFailure', () {
    test('never leaks platform text, however verbose the exception', () {
      final message =
          describePluginFailure(_cameraXNoCameraException(), 'list cameras');

      for (final needle in _forbidden) {
        expect(
          message.contains(needle),
          isFalse,
          reason: 'user-facing message must not contain "$needle": $message',
        );
      }
    });

    test('names the action so the sentence is specific', () {
      expect(
        describePluginFailure(
          PlatformException(code: 'error'),
          'list cameras',
        ),
        contains('list cameras'),
      );
    });

    test('produces a complete sentence even with null code and message', () {
      final message = describePluginFailure(
        PlatformException(code: ''),
        'open the camera',
      );
      expect(message, isNotEmpty);
      expect(message, endsWith('.'));
    });

    test('gives permission failures their own actionable wording', () {
      final message = describePluginFailure(
        PlatformException(code: 'CameraAccessDenied'),
        'open the camera',
      );
      expect(message.toLowerCase(), contains('permission'));
    });
  });

  group('codeOf / messageOf', () {
    test('reads a CameraException-shaped object without importing the plugin',
        () {
      // CameraException exposes `code` + `description`; PlatformException
      // exposes `code` + `message`. Both are read structurally.
      expect(codeOf(_FakeCameraException('CameraAccessDenied', 'denied')),
          'CameraAccessDenied');
      expect(messageOf(_FakeCameraException('c', 'the description')),
          'the description');
    });

    test('returns null for an object with neither', () {
      expect(codeOf(StateError('x')), isNull);
      expect(codeOf(ArgumentError('x')), isNull);
    });

    test('ignores a Dart core error\'s own `message` property', () {
      // StateError/ArgumentError both expose `.message`. Reading it would let
      // an unrelated error be classified as a camera condition purely on a
      // coincidental word, so only PlatformException.message and
      // CameraException.description are read.
      expect(messageOf(StateError('x')), isNull);
      expect(
        meansNoCamera(StateError('CameraUnavailableException in some log')),
        isFalse,
      );
    });

    test('a CameraException-shaped no-camera failure is still classified', () {
      expect(
        meansNoCamera(
          _FakeCameraException('x', 'CameraUnavailableException: none'),
        ),
        isTrue,
      );
    });
  });
}

/// Structurally identical to the plugin's `CameraException` (`code` +
/// `description`) without depending on the plugin.
class _FakeCameraException {
  _FakeCameraException(this.code, this.description);
  final String code;
  final String description;
}
