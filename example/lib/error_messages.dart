/// The app's single translation point from a contract error to a sentence a
/// user can act on.
///
/// Every UI surface routes through [describeCameraError] instead of
/// interpolating `'$e'`. That interpolation is what put a 30-line Java stack
/// trace on the "Built-in camera" screen: `PlatformException.toString()` prints
/// its `details`, which on Android carries the full `at androidx.camera.core…`
/// dump.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

/// Shown whenever enumeration succeeds but finds nothing.
///
/// One constant rather than the three copies this string used to have
/// (`camera_session.dart`, and twice in `builtin_camera_setup_wizard.dart`).
const String kNoBuiltinCameraFound = 'No built-in camera found';

/// A short, user-facing sentence for [error].
///
/// [action] is an infinitive phrase naming what failed — `'looking for
/// cameras'`, `'capturing a frame'` — used only by the generic fallback, so an
/// unrecognised error still says *what* went wrong without saying *how*.
///
/// The typed cases below are the [CameraAdapter] contract's error surface; by
/// the time an error reaches here the adapter has already replaced any platform
/// text with a written message, so `StateError.message` is safe to show.
String describeCameraError(Object error, {required String action}) {
  if (error is StateError) return error.message;
  if (error is TimeoutException) {
    return 'The camera took too long to respond.';
  }
  if (error is UnsupportedError) {
    return error.message ?? 'This camera does not support that action.';
  }
  if (error is FormatException) {
    return 'The camera sent a response the app could not read.';
  }
  // Anything else is off-contract — most likely a platform exception that
  // escaped a backend. Log it, show nothing of it.
  if (kDebugMode) {
    debugPrint('[CameraSession] unmapped error while $action — $error');
  }
  return 'Something went wrong while $action. Please try again.';
}
