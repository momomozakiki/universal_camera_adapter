import 'package:flutter/foundation.dart';

/// A single camera-facing capability that a feature can ask an adapter about.
///
/// This enum is a **closed, exhaustively-renderable set** on purpose: adding a
/// value is a deliberate, versioned change (a new release), which is what lets
/// UI switch over it without a `default` fall-through. Contrast with an
/// open-ended string key, which would let capabilities drift silently.
///
/// [twoWayAudio] and [motionEvents] are seeded now as placeholders (reported
/// [CameraFeatureStatus.unvalidated] everywhere today) so backends *declare*
/// them rather than omit them — keeping the set stable as they come online.
///
/// See `docs/camera/feature-matrix.md` for the design rationale.
enum CameraFeature {
  /// Optical/digital zoom (`CameraAdapter.setZoom`).
  zoom,

  /// Horizontal PTZ movement (`CameraAdapter.setPan`).
  pan,

  /// Vertical PTZ movement (`CameraAdapter.setTilt`).
  tilt,

  /// Single-frame grab (`CameraAdapter.captureFrame`) — the primitive every
  /// app-level scanning feature is built on.
  frameCapture,

  /// QR-code scanning (app-level, built on [frameCapture]).
  qrScanning,

  /// 1D/2D barcode scanning (app-level, built on [frameCapture]).
  barcodeScanning,

  /// Text recognition / OCR (app-level, built on [frameCapture]).
  textRecognitionOcr,

  /// Two-way audio. Placeholder — unvalidated everywhere today.
  twoWayAudio,

  /// Motion-event notifications. Placeholder — unvalidated everywhere today.
  motionEvents,
}

/// Tri-state support level for a [CameraFeature] on a given backend.
///
/// The middle state matters: it distinguishes "the hardware genuinely cannot do
/// this" from "we believe this is wired but haven't confirmed it on real
/// hardware yet". A brand-new backend should report [unvalidated] rather than an
/// optimistic [supported].
enum CameraFeatureStatus {
  /// Genuinely not available (e.g. no PTZ on a fixed webcam).
  unsupported,

  /// Wired and believed supported, but not yet manually tested on real
  /// hardware. The safe default for a new backend/feature.
  unvalidated,

  /// Manually tested and confirmed working.
  supported,
}

/// The support of one [CameraFeature], with optional backend-supplied metadata
/// (e.g. a zoom range `{'minZoomLevel': 1.0, 'maxZoomLevel': 5.0}`).
@immutable
class CameraFeatureSupport {
  const CameraFeatureSupport({
    required this.feature,
    required this.status,
    this.metadata,
  });

  final CameraFeature feature;
  final CameraFeatureStatus status;

  /// Free-form, feature-specific extra information. Treat as advisory.
  final Map<String, dynamic>? metadata;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraFeatureSupport &&
          other.feature == feature &&
          other.status == status &&
          mapEquals(other.metadata, metadata);

  @override
  int get hashCode => Object.hash(
        feature,
        status,
        metadata == null ? null : Object.hashAll(metadata!.values),
      );

  @override
  String toString() =>
      'CameraFeatureSupport(${feature.name}: ${status.name})';
}

/// Named groupings of features, purely for UI/documentation.
///
/// A bundle is **not** an all-or-nothing promise: a camera can be "zoom-only"
/// (zoom supported, pan/tilt unsupported) and still be a valid member of the
/// `ptz` bundle. Consumers render per-feature status via
/// [CameraFeatureMatrix.bundleStatus]. Adding a bundle later is a one-line change.
const Map<String, Set<CameraFeature>> kFeatureBundles = <String, Set<CameraFeature>>{
  'ptz': <CameraFeature>{CameraFeature.pan, CameraFeature.tilt, CameraFeature.zoom},
  'scanning': <CameraFeature>{
    CameraFeature.qrScanning,
    CameraFeature.barcodeScanning,
    CameraFeature.textRecognitionOcr,
  },
};

/// The support level of every [CameraFeature] for one opened device.
///
/// **Invariant: always fully populated.** Every [CameraFeature] value has an
/// entry, so a query never has to handle a missing key. Build instances through
/// [CameraFeatureMatrix.fromStatuses] (which fills every feature, defaulting the
/// unlisted ones), and [statusOf] additionally falls back to
/// [CameraFeatureStatus.unsupported] rather than throwing, so a hand-built map
/// with a gap degrades safely instead of crashing.
@immutable
class CameraFeatureMatrix {
  /// Wraps an already-complete map. Prefer [fromStatuses] unless you are
  /// certain every [CameraFeature] is present.
  const CameraFeatureMatrix(this._supports);

  /// Builds a fully-populated matrix from a partial status map: every
  /// [CameraFeature] not present in [statuses] is filled with [fallback].
  ///
  /// [fallback] defaults to [CameraFeatureStatus.unvalidated] — an *undeclared*
  /// feature is unknown, not proven absent. Claiming `unsupported` would blame
  /// the hardware for something nobody has checked; `unvalidated` still gates
  /// interaction (`isSupported` is `false`) while letting the UI say "Under
  /// development". Pass `unsupported` explicitly when a backend genuinely knows
  /// the remaining features are absent.
  factory CameraFeatureMatrix.fromStatuses(
    Map<CameraFeature, CameraFeatureStatus> statuses, {
    CameraFeatureStatus fallback = CameraFeatureStatus.unvalidated,
  }) {
    return CameraFeatureMatrix(<CameraFeature, CameraFeatureSupport>{
      for (final feature in CameraFeature.values)
        feature: CameraFeatureSupport(
          feature: feature,
          status: statuses[feature] ?? fallback,
        ),
    });
  }

  final Map<CameraFeature, CameraFeatureSupport> _supports;

  /// The full support record for [feature]. Falls back to an [unsupported]
  /// record if (against the invariant) the entry is missing.
  CameraFeatureSupport supportOf(CameraFeature feature) =>
      _supports[feature] ??
      CameraFeatureSupport(
        feature: feature,
        status: CameraFeatureStatus.unsupported,
      );

  /// The status of [feature].
  CameraFeatureStatus statusOf(CameraFeature feature) => supportOf(feature).status;

  /// Whether [feature] is confirmed [CameraFeatureStatus.supported].
  ///
  /// Note: [CameraFeatureStatus.unvalidated] returns `false` here — callers that
  /// want to *offer* an unvalidated feature should check [statusOf] explicitly.
  bool isSupported(CameraFeature feature) =>
      statusOf(feature) == CameraFeatureStatus.supported;

  /// The per-feature status for a named bundle in [kFeatureBundles]. An unknown
  /// bundle name yields an empty map.
  Map<CameraFeature, CameraFeatureStatus> bundleStatus(String bundleName) {
    final features = kFeatureBundles[bundleName] ?? const <CameraFeature>{};
    return <CameraFeature, CameraFeatureStatus>{
      for (final feature in features) feature: statusOf(feature),
    };
  }

  /// Returns a copy with the given features' statuses replaced. Used by a
  /// backend to reuse a derived base matrix and downgrade the few features it
  /// hasn't wired yet (e.g. `frameCapture`). Preserves the full-population
  /// invariant.
  ///
  /// (Named `withStatuses` rather than `override` so the identifier doesn't
  /// shadow the `@override` annotation within this class.)
  CameraFeatureMatrix withStatuses(Map<CameraFeature, CameraFeatureStatus> overrides) {
    return CameraFeatureMatrix(<CameraFeature, CameraFeatureSupport>{
      for (final entry in _supports.entries)
        entry.key: overrides.containsKey(entry.key)
            ? CameraFeatureSupport(
                feature: entry.key,
                status: overrides[entry.key]!,
                metadata: entry.value.metadata,
              )
            : entry.value,
    });
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CameraFeatureMatrix && mapEquals(other._supports, _supports);

  @override
  int get hashCode => Object.hashAll(_supports.values);

  @override
  String toString() {
    final parts = CameraFeature.values
        .map((f) => '${f.name}=${statusOf(f).name}')
        .join(', ');
    return 'CameraFeatureMatrix($parts)';
  }
}
