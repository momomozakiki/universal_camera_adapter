import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'camera_types.dart';

/// The default timeout applied to network-bound camera operations.
const Duration kDefaultCameraTimeout = Duration(seconds: 15);

/// The core camera abstraction: one contract for every camera source.
///
/// Consumers depend on this interface (and [CameraAdapterRegistry]), never a
/// concrete backend — see the "Golden Rule" in the README.
///
/// ## Invariants every backend must honor
///
/// 1. **One device open at a time.** [open] closes any previously-open device
///    first, so a caller never has to remember to [close] before opening the next.
/// 2. **Capabilities are queried, never assumed.** [capabilities] reflects the
///    real opened device; reading it before [open] throws [StateError].
/// 3. **Lazy acquisition.** A backend touches its plugin/SDK/socket only inside
///    [open], never in its constructor.
/// 4. **Typed error surface.** Failures surface as [StateError] (open/capture
///    failure, permission denied, used-before-open), [UnsupportedError] (a
///    capability the hardware lacks), [TimeoutException] (network/timeout), or
///    [FormatException] (malformed response) — never a raw platform exception.
///
/// All network-bound methods take an optional [Duration] `timeout`
/// (default [kDefaultCameraTimeout]); adding it was a non-breaking change.
abstract class CameraAdapter {
  // --- Discovery ---

  /// Lists the camera devices this backend can see. Cheap and side-effect-free
  /// enough to call before [open].
  Future<List<CameraDevice>> listDevices();

  // --- Lifecycle ---

  /// Opens [device], closing any previously-open device first.
  ///
  /// This is the only method that touches the underlying SDK/plugin/socket.
  /// Throws [StateError] on failure (including permission denied) and
  /// [TimeoutException] if the backend does not respond within [timeout].
  Future<void> open(
    CameraDevice device, {
    Duration timeout = kDefaultCameraTimeout,
  });

  /// Releases all resources for the current device. Safe to call when not open.
  Future<void> close();

  /// Whether a device is currently open.
  bool get isOpen;

  // --- Capabilities (queried post-open) ---

  /// What the *opened* device can do. Throws [StateError] if not open.
  CameraCapabilities get capabilities;

  // --- Video ---

  /// A widget that renders the live feed. Throws [StateError] if not open.
  ///
  /// The consumer **must** ensure [close] is called (e.g. in `dispose()`) to
  /// release the underlying controller/player.
  Widget buildPreview();

  /// Captures a single frame as raw image bytes (usually JPEG).
  ///
  /// Throws [StateError] if not open and [TimeoutException] on timeout.
  Future<Uint8List> captureFrame({
    Duration timeout = kDefaultCameraTimeout,
  });

  // --- Optional controls (may throw UnsupportedError) ---

  /// Sets the zoom factor. Throws [UnsupportedError] if the device has no zoom,
  /// [StateError] if not open.
  Future<void> setZoom(
    double factor, {
    Duration timeout = kDefaultCameraTimeout,
  });

  /// Pans the camera (PTZ). Defaults to throwing [UnsupportedError]; a backend
  /// overrides this only once it genuinely supports pan.
  Future<void> setPan(
    double angle, {
    Duration timeout = kDefaultCameraTimeout,
  }) {
    throw UnsupportedError('This camera backend does not support pan.');
  }

  /// Tilts the camera (PTZ). Defaults to throwing [UnsupportedError]; a backend
  /// overrides this only once it genuinely supports tilt.
  Future<void> setTilt(
    double angle, {
    Duration timeout = kDefaultCameraTimeout,
  }) {
    throw UnsupportedError('This camera backend does not support tilt.');
  }
}
