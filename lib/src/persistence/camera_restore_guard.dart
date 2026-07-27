import 'package:shared_preferences/shared_preferences.dart';

/// A crash-loop breaker for the "open my saved camera at startup" path.
///
/// ## Why this exists
///
/// A `CameraAdapter` backend is free to fail in ways the contract's typed error
/// surface can describe — and the session handles those. But a backend built on
/// a native SDK can also **kill the process**: the vendored EZVIZ plugin
/// dereferenced an uninitialised `EZGlobalSDK` on a Kotlin coroutine, throwing a
/// `NullPointerException` past a `catch (e: BaseException)` that could not hold
/// it. That is a `FATAL EXCEPTION`, not a Dart exception, and **no `try`/`catch`
/// in Dart can intercept it.**
///
/// Because auto-restore runs before any UI exists, the result was an app that
/// could not be launched at all, with no screen from which to remove the camera
/// that was killing it — recoverable only by clearing app data (losing every
/// saved camera and credential) or by editing preferences over `adb`.
///
/// This guard is the generic answer, and deliberately knows nothing about EZVIZ:
/// mark before the risky work, clear after it. A launch that finds the mark
/// already set knows the previous launch did not survive, and can skip the
/// auto-open to land the user on the camera list instead. It therefore protects
/// against **any** backend that can take the process down, including ones not
/// written yet — which is the only kind of protection available when the failure
/// is unreachable from Dart.
///
/// It is not a general "did we crash" detector: it is scoped to the restore
/// window only, so an unrelated crash elsewhere in the app never suppresses a
/// perfectly good camera at next launch.
abstract class CameraRestoreGuard {
  /// Whether a previous [beginRestore] was never followed by [endRestore] —
  /// i.e. the last launch died mid-restore.
  Future<bool> wasRestoreInterrupted();

  /// Marks a restore as in progress. Must complete **before** the first call
  /// into the backend, or the mark will not be on disk when the process dies.
  Future<void> beginRestore();

  /// Clears the mark. Safe to call when no restore is in progress.
  Future<void> endRestore();
}

/// [CameraRestoreGuard] backed by `shared_preferences`.
///
/// A single boolean key alongside the profile store. On Android the platform
/// implementation commits the write before the returned future completes, so an
/// awaited [beginRestore] is durable by the time the risky call is made — which
/// is the entire requirement here.
class SharedPreferencesCameraRestoreGuard implements CameraRestoreGuard {
  /// The `shared_preferences` key holding the in-progress flag.
  static const String storageKey = 'uca.restore_in_progress';

  @override
  Future<bool> wasRestoreInterrupted() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(storageKey) ?? false;
  }

  @override
  Future<void> beginRestore() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(storageKey, true);
  }

  @override
  Future<void> endRestore() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey);
  }
}
