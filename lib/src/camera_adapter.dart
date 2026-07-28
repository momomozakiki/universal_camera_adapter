import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import 'camera_feature.dart';
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

  /// What this backend *claims* about each [CameraFeature], independent of any
  /// open device.
  ///
  /// This is the integration checklist for a new camera plugin: state a status
  /// for every [CameraFeature] you have looked at. It is readable without
  /// hardware — no `open()`, no permissions — which is what lets
  /// `camera_feature_checklist_test.dart` enforce that a registered backend has
  /// declared all of them rather than silently inheriting defaults.
  ///
  /// Concrete with an empty default so adding this never broke an existing
  /// implementer; the checklist test is what makes leaving it empty visible.
  /// Entries here are layered over the queried derivation in [featureMatrix],
  /// so this stays the single place a claim is written.
  ///
  /// Declare `supported` **only** for what has been exercised on real hardware.
  /// Anything wired but unproven is [CameraFeatureStatus.unvalidated], which
  /// reads as "Under development" in the UI and stays non-interactive.
  Map<CameraFeature, CameraFeatureStatus> get declaredFeatures =>
      const <CameraFeature, CameraFeatureStatus>{};

  /// The tri-state support of every [CameraFeature] for the opened device.
  ///
  /// This is the feature surface consumers should prefer: a feature queries its
  /// [CameraFeature] here and degrades to "not supported" when the answer isn't
  /// [CameraFeatureStatus.supported], so adding a feature never forces an edit
  /// to this contract or to every backend (Open/Closed).
  ///
  /// The default derivation maps [capabilities] onto zoom/pan/tilt — which are
  /// genuinely *queried* — and **fails safe** for everything else.
  ///
  /// This derivation used to be optimistic: `frameCapture` and the scanning
  /// features defaulted to [CameraFeatureStatus.supported] on the reasoning that
  /// [captureFrame] is a required contract method, with a doc note telling
  /// authors they "MUST override" to downgrade. That is opt-out, and it fails
  /// open — a backend that simply forgot inherited a claim its hardware could
  /// not honour, and the user was told the *camera* lacked a feature the *app*
  /// had not finished wiring.
  ///
  /// They now default to [CameraFeatureStatus.unvalidated] instead: an
  /// undeclared feature is unknown, not proven. Nothing is enabled on an
  /// unproven claim, because `isSupported` remains `false` for `unvalidated`
  /// — but the UI can say "Under development" rather than "Not supported".
  ///
  /// **A backend that has verified a feature on real hardware must therefore
  /// declare it explicitly** — see [FlutterCameraAdapter], which promotes the
  /// three primitives it has tested. Reuse this base result and adjust entries
  /// via [CameraFeatureMatrix.withStatuses] (see `EzvizCameraAdapter`), or build
  /// a matrix outright when [capabilities] is unreadable (see
  /// `ONVIFCameraAdapter`).
  ///
  /// Like [capabilities], this is a post-open query — the default derivation
  /// reads [capabilities] and therefore throws [StateError] if not open.
  CameraFeatureMatrix get featureMatrix {
    final caps = capabilities; // throws StateError if not open — intentional.
    return CameraFeatureMatrix.fromStatuses(<CameraFeature, CameraFeatureStatus>{
      CameraFeature.zoom: caps.hasZoom
          ? CameraFeatureStatus.supported
          : CameraFeatureStatus.unsupported,
      CameraFeature.pan: caps.hasPan
          ? CameraFeatureStatus.supported
          : CameraFeatureStatus.unsupported,
      CameraFeature.tilt: caps.hasTilt
          ? CameraFeatureStatus.supported
          : CameraFeatureStatus.unsupported,
      CameraFeature.frameCapture: CameraFeatureStatus.unvalidated,
      CameraFeature.qrScanning: CameraFeatureStatus.unvalidated,
      CameraFeature.barcodeScanning: CameraFeatureStatus.unvalidated,
      CameraFeature.textRecognitionOcr: CameraFeatureStatus.unvalidated,
      CameraFeature.twoWayAudio: CameraFeatureStatus.unvalidated,
      CameraFeature.motionEvents: CameraFeatureStatus.unvalidated,
      // Layered last so a backend's declaration wins over the fail-safe
      // defaults — and so [declaredFeatures] stays the one place a claim lives.
    }).withStatuses(declaredFeatures);
  }

  // --- Video ---

  /// A widget that renders the live feed. Throws [StateError] if not open.
  ///
  /// The consumer **must** ensure [close] is called (e.g. in `dispose()`) to
  /// release the underlying controller/player.
  ///
  /// **Sizing is not guaranteed — the caller must impose bounded constraints.**
  /// Backends differ and are both within their rights: `FlutterCameraAdapter`
  /// returns a `CameraPreview`, which self-sizes from the device's aspect ratio,
  /// while `ONVIFCameraAdapter` returns a `media_kit` `Video`, which expands to
  /// fill whatever it is given. Placing the latter somewhere with an unbounded
  /// height — a `Column` inside a `SingleChildScrollView`, say — throws
  /// "BoxConstraints forces an infinite height" during layout. The consequence
  /// is far worse than a broken preview: the render box is left with no size,
  /// so **every subsequent hit test in the entire app** throws "Cannot hit test
  /// a render box that has never been laid out", and the whole UI stops
  /// responding to input. Wrap the result in an [AspectRatio], a `SizedBox`, or
  /// an `Expanded`/`StackFit.expand` parent (see `example/lib/tabs/`).
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
