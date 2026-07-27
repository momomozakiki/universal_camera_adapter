import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_camera_adapter_example/error_messages.dart';

void main() {
  group('describeCameraError', () {
    test('passes a StateError message through', () {
      // By the time an error reaches the UI the adapter has already replaced
      // any platform text, so its message is the user-facing sentence.
      expect(
        describeCameraError(StateError('Camera access is blocked.'),
            action: 'x'),
        'Camera access is blocked.',
      );
    });

    test('maps each contract error type to its own sentence', () {
      final messages = <String>{
        describeCameraError(TimeoutException('t'), action: 'x'),
        describeCameraError(UnsupportedError('u'), action: 'x'),
        describeCameraError(const FormatException('f'), action: 'x'),
        describeCameraError(Exception('unmapped'), action: 'x'),
      };
      // Four distinct types must not collapse into one vague message.
      expect(messages, hasLength(4));
    });

    test('names the action in the generic fallback', () {
      expect(
        describeCameraError(Exception('boom'), action: 'looking for cameras'),
        contains('looking for cameras'),
      );
    });

    test('never renders a raw PlatformException, stack trace and all', () {
      // The exact regression: PlatformException.toString() prints code,
      // message AND details — and details carries the androidx frames.
      final error = PlatformException(
        code: 'ExecutionException',
        message: 'java.util.concurrent.ExecutionException: '
            'androidx.camera.core.CameraUnavailableException',
        details: 'Stacktrace: \tat androidx.camera.core.CameraX.lambda(...)',
      );

      final message = describeCameraError(error, action: 'looking for cameras');

      for (final needle in const <String>[
        'at androidx.',
        'PlatformException',
        'java.util.concurrent',
        'Stacktrace',
      ]) {
        expect(message.contains(needle), isFalse, reason: needle);
      }
    });

    test('every message is a complete sentence', () {
      for (final error in <Object>[
        TimeoutException('t'),
        UnsupportedError('This camera does not support that action.'),
        const FormatException('f'),
        Exception('unmapped'),
      ]) {
        final message = describeCameraError(error, action: 'testing');
        expect(message, isNotEmpty);
        expect(message.trim(), endsWith('.'), reason: '$error -> $message');
      }
    });
  });
}
