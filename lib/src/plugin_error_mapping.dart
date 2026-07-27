/// Maps raw `camera` plugin / platform-channel failures onto the contract's
/// typed error surface, without ever leaking platform text to a user.
///
/// ## Why this file exists
///
/// `CameraAdapter` promises that "failures surface as [StateError] /
/// [UnsupportedError] / [TimeoutException] / [FormatException] — never a raw
/// platform exception". The Android backend breaks that promise on its own:
/// `camera_android_camerax`'s `availableCameras()` has **no `try`/`catch` at
/// all** (`android_camera_camerax.dart:291-331` in 0.7.4+1), so a CameraX
/// failure arrives as a bare [PlatformException].
///
/// What that exception actually contains is the reason nothing here reads
/// `message`. Pigeon's `wrapError` (`android/…/CameraXLibrary.g.kt:29-38`)
/// builds it as:
///
/// ```kotlin
/// listOf(exception.javaClass.simpleName,   // -> code, e.g. "ExecutionException"
///        exception.toString(),             // -> message: nested Java class names
///        "Cause: …, Stacktrace: " + Log.getStackTraceString(exception)) // -> details
/// ```
///
/// So `code` is a Java class name (no semantic value), `message` is a
/// multi-line Java `toString()`, and `details` carries the `at androidx.…`
/// frames. Rendering any of them is how a full stack trace ends up on screen.
/// **This module reads them only to classify, and only ever returns strings it
/// wrote itself.**
///
/// Package-internal: `lib/src/` is not exported from
/// `package:universal_camera_adapter/universal_camera_adapter.dart`, so these
/// helpers are visible to sibling backends and to tests, but never to a
/// consumer.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;

/// androidx class names that mean "CameraX could not give us a camera".
///
/// The stable half of the signal: these are public CameraX API types
/// (`androidx.camera.core.CameraUnavailableException`,
/// `androidx.camera.core.InitializationException`), so they survive wording
/// changes in the plugin's English text.
const List<String> kNoCameraTypeSignals = <String>[
  'CameraUnavailableException',
  'InitializationException',
];

/// CameraX's English explanation for the same condition.
///
/// Secondary and deliberately best-effort: this prose is not API and may change
/// between CameraX versions. If it ever stops matching, classification falls
/// back to a generic friendly failure — degraded, but never a stack trace.
const List<String> kNoCameraTextSignals = <String>[
  'Device reporting less cameras',
  'Available cameras: 0',
];

/// Exact `code` values meaning "the user has not granted camera access".
///
/// Both supported platforms emit the *same* constant, which is why this is an
/// exact match rather than a substring search for "denied":
/// - Android: `CameraPermissionsManager.java:36`
///   `CAMERA_ACCESS_DENIED = "CameraAccessDenied"` (and `:38` for audio).
/// - Windows: `camera_windows/windows/camera.cpp:10`
///   `kCameraAccessDenied[] = "CameraAccessDenied"`.
const Set<String> kPermissionDeniedCodes = <String>{
  'CameraAccessDenied',
  'AudioAccessDenied',
};

/// Whether [error] means the device reported no usable camera.
///
/// Matches on the message text because `code` carries no signal here — it is
/// always the Java class name `"ExecutionException"` for this path (see the
/// library doc above).
bool meansNoCamera(Object error) {
  final message = messageOf(error);
  if (message == null) return false;
  return kNoCameraTypeSignals.any(message.contains) ||
      kNoCameraTextSignals.any(message.contains);
}

/// Whether [error] means camera permission was denied.
///
/// Exact match on the platform's own error code — see [kPermissionDeniedCodes].
bool meansPermissionDenied(Object error) {
  final code = codeOf(error);
  return code != null && kPermissionDeniedCodes.contains(code);
}

/// The platform error code of [error], or `null` when it has none.
///
/// `CameraException` and [PlatformException] are unrelated types that both
/// expose a `String code`, so this reads it without importing the plugin.
String? codeOf(Object error) {
  if (error is PlatformException) return error.code;
  return _readString(error, (dynamic e) => e.code);
}

/// The platform message of [error], or `null` when it has none.
///
/// Used **only** for classification — never for display. Reads exactly two
/// shapes: [PlatformException.message] and `CameraException.description`.
///
/// Deliberately does **not** fall back to a generic `.message`: Dart's own
/// errors ([StateError], [ArgumentError]) expose one, so a looser read would
/// let an unrelated error be classified as a camera condition on nothing more
/// than a coincidental word in its text.
String? messageOf(Object error) {
  if (error is PlatformException) return error.message;
  return _readString(error, (dynamic e) => e.description);
}

/// Reads a `String` field via [get], returning `null` if the object has no such
/// member or it is not a `String`.
String? _readString(Object error, Object? Function(dynamic) get) {
  try {
    final value = get(error);
    return value is String ? value : null;
  } on Object {
    // Catches more than NoSuchMethodError on purpose: this reads an arbitrary
    // getter off an untyped object, and a getter that throws must degrade to
    // "no code/message" rather than replace the failure being reported with a
    // second one.
    return null;
  }
}

/// A short, user-safe sentence describing a failed [action] (an infinitive
/// phrase such as `'list cameras'` or `'open the camera'`).
///
/// **Never** includes `message`/`description` or `details` from the underlying
/// exception — those carry Java stack traces (see the library doc). The raw
/// object goes to [logPluginFailure] instead.
String describePluginFailure(Object error, String action) {
  logPluginFailure(error, action);
  if (meansPermissionDenied(error)) {
    return 'Camera access is blocked. Allow the camera permission in your '
        'system settings, then try again.';
  }
  return 'Could not $action. Please try again.';
}

/// Sends the untouched platform error to the debug console.
///
/// Debug-only: the fields logged here are exactly the ones that must never
/// reach the UI, so they stay out of release builds.
void logPluginFailure(Object error, String action) {
  if (!kDebugMode) return;
  if (error is PlatformException) {
    debugPrint(
      '[CameraAdapter] failed to $action — code=${error.code} '
      'message=${error.message} details=${error.details}',
    );
  } else {
    debugPrint('[CameraAdapter] failed to $action — $error');
  }
}
