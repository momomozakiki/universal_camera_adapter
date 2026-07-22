---
title: Camera Feature Matrix Model
version: 1.0
last_validated: 2026-07-22
official: false
source: project-internal
tags: [features, capabilities, matrix, ptz, zoom, ocr, qr, barcode]
applies_when: "Building a UI to display/query camera capabilities or implementing feature support in a backend."
---

# Camera feature matrix model

**Version 1.0** — *extensible, tri-state feature support without breaking existing code.*

## Revision History
| Version | Date       | Change   |
|---------|------------|----------|
| 1.0     | 2026-07-22 | Initial. |

## Problem with today's `CameraCapabilities`

The current model is a flat struct of booleans plus a few range fields:

```dart
class CameraCapabilities {
  final bool hasZoom;
  final double minZoomLevel;
  final double maxZoomLevel;
  final bool hasPan;
  final bool hasTilt;
  // Expansion nightmare:
  // final bool hasQrScanning;
  // final bool hasOcr;
  // final bool has...?
}
```

Problems:
1. **Closed set** — adding a feature (QR, OCR, face detection) means editing this class and every
   backend that constructs it.
2. **No feature-specific metadata** — if OCR needs to know "supported languages," where does that
   live? As an ad hoc field on `CameraCapabilities`? Violation of Open/Closed.
3. **No distinction between "can't do" and "not yet tested"** — a `bool` can't express "this
   backend probably supports zoom, but we haven't manually verified it on real hardware yet."

## Proposed model: types only (no code changes yet)

### `CameraFeature` enum

A closed set of features the UI can exhaustively render:

```dart
enum CameraFeature {
  zoom,
  pan,
  tilt,
  frameCapture,
  qrScanning,
  barcodeScanning,
  textRecognitionOcr,
  // Placeholders for future epics, marked unsupported for now:
  twoWayAudio,
  motionEvents,
}
```

No new features are added on the fly; each addition is explicit and requires a release. Placeholders
for known-future work (two-way audio, motion events) are seeded now to allow backends to declare
them `unsupported` rather than leaving them out entirely, keeping the set stable across time.

### `CameraFeatureStatus` tri-state enum

Rather than a boolean, each feature can report one of three states:

```dart
enum CameraFeatureStatus {
  /// Genuinely not available on this camera (e.g., no PTZ on a fixed-lens webcam).
  unsupported,
  
  /// Wired up and believed supported, but not yet manually tested on real hardware
  /// for this backend. Default for every feature on a brand-new backend.
  unvalidated,
  
  /// Manually tested and confirmed working.
  supported,
}
```

This satisfies the distinction: "phone webcam doesn't support pan" (unsupported) vs. "ONVIF adapter
has a pan method wired but hasn't been tested against a real PTZ dome" (unvalidated).

### `CameraFeatureSupport` value type

Pairs a feature with its status plus optional feature-specific metadata:

```dart
@immutable
class CameraFeatureSupport {
  final CameraFeature feature;
  final CameraFeatureStatus status;
  
  /// Optional feature-specific metadata (zoom range, languages, etc).
  /// Unmarshalled by consumers that know about a specific feature.
  final Map<String, dynamic>? metadata;
  
  const CameraFeatureSupport({
    required this.feature,
    required this.status,
    this.metadata,
  });
}
```

Example: zoom support with range:
```dart
CameraFeatureSupport(
  feature: CameraFeature.zoom,
  status: CameraFeatureStatus.supported,
  metadata: {'minLevel': 1.0, 'maxLevel': 5.0},
)
```

### `CameraFeatureMatrix` immutable wrapper

```dart
@immutable
class CameraFeatureMatrix {
  /// Always fully populated; every CameraFeature enum value is present.
  final Map<CameraFeature, CameraFeatureSupport> _matrix;
  
  const CameraFeatureMatrix(this._matrix);
  
  /// Query the status of a single feature.
  CameraFeatureStatus statusOf(CameraFeature feature) => _matrix[feature]!.status;
  
  /// Convenience: true iff status is [CameraFeatureStatus.supported].
  bool isSupported(CameraFeature feature) => statusOf(feature) == CameraFeatureStatus.supported;
  
  /// Get support info for all features in a bundle (e.g., 'ptz').
  Map<CameraFeature, CameraFeatureStatus> bundleStatus(String bundleName) {
    final features = kFeatureBundles[bundleName] ?? {};
    return {for (var f in features) f: statusOf(f)};
  }
}
```

The matrix is always fully populated—every enum value present, never a missing key—so the UI never
has to guess whether a missing key means "not supported" or "not yet wired."

### `CameraFeatureBundle` const lookup table

Purely a UI/documentation grouping, not an all-or-nothing promise:

```dart
const Map<String, Set<CameraFeature>> kFeatureBundles = {
  'ptz': {CameraFeature.pan, CameraFeature.tilt, CameraFeature.zoom},
  'scanning': {
    CameraFeature.qrScanning,
    CameraFeature.barcodeScanning,
    CameraFeature.textRecognitionOcr,
  },
};
```

A camera can have `zoom: supported` while `pan` and `tilt` are `unsupported`—a valid "zoom-only"
member of the PTZ bundle. Adding a new bundle later (e.g., `'audio': {twoWayAudio}`) is a one-line
addition; existing backends' matrices need no change (Open/Closed).

## Migration: `CameraCapabilities` stays, becomes derived view

**`CameraAdapter.capabilities` stays unchanged.** Existing consumers reading `capabilities.hasZoom`
never break. The class is recomputed from the new `featureMatrix` on demand:

```dart
extension CameraAdapterMigration on CameraAdapter {
  /// New in v1.2. Returns the feature matrix for this device.
  CameraFeatureMatrix get featureMatrix => _computeFeatureMatrix();
  
  /// Existing behavior, kept for backward compatibility.
  /// Computed from featureMatrix.
  CameraCapabilities get capabilities => _deriveCapabilitiesFromMatrix();
}
```

New consumers wanting bundles or tri-state read `featureMatrix` directly. Existing consumers read
`capabilities` as before, with no code changes.

**Contract change:** adding `featureMatrix` as a required getter means every backend
(`FlutterCameraAdapter`, `ONVIFCameraAdapter`, `EzvizCameraAdapter`) must implement it. The
ROADMAP should state this lands in **v1.2** and that all three gain `featureMatrix` together, not
piecemeal.

## Per-backend matrices (design-time reference)

### `FlutterCameraAdapter` (local device camera)

```
zoom             → supported (queried min/max, as today) or unsupported (trivial range)
pan              → unsupported (no PTZ API on the camera plugin)
tilt             → unsupported (no PTZ API on the camera plugin)
frameCapture     → supported (proven; backs QR/barcode tabs today)
qrScanning       → supported (via frameCapture + flutter_zxing)
barcodeScanning  → supported (via frameCapture + flutter_zxing)
textRecognitionOcr → unvalidated (enum value present, but no OCR wired yet; gated on google_mlkit_text_recognition)
twoWayAudio      → unvalidated (placeholder for future)
motionEvents     → unvalidated (placeholder for future)
```

### `ONVIFCameraAdapter` (IP cameras)

Currently scaffolding (all throw `UnimplementedError`). At v1.1 implementation time:

```
zoom             → supported (once AbsoluteMove with zoom is proven live)
pan              → supported (once AbsoluteMove confirmed)
tilt             → supported (once AbsoluteMove confirmed)
frameCapture     → supported (via GetSnapshotUri or RTSP frame grab)
qrScanning       → supported (via frameCapture + flutter_zxing)
barcodeScanning  → supported (via frameCapture + flutter_zxing)
textRecognitionOcr → supported (via frameCapture + google_mlkit_text_recognition)
twoWayAudio      → unvalidated (placeholder; ONVIF spec defines a two-way audio service, not yet implemented)
motionEvents     → unvalidated (placeholder; ONVIF spec defines events, not yet implemented)
```

This is the worked example for a **full-featured PTZ + frame-capture backend**.

### `EzvizCameraAdapter` (EZVIZ cloud cameras)

Planned for v1.3. Feature support depends on the specific EZVIZ model queried post-open:

```
zoom             → depends on model (fixed-lens: unsupported; PTZ dome: supported; some cameras have digital zoom only—must be flagged as a distinct concern)
pan              → depends on model (queried from device capability response post-open)
tilt             → depends on model (queried from device capability response post-open)
frameCapture     → unresolved (see 3.5 below; flagged for v1.3 implementation)
qrScanning       → unresolved (depends on frameCapture resolution)
barcodeScanning  → unresolved (depends on frameCapture resolution)
textRecognitionOcr → unresolved (depends on frameCapture resolution)
twoWayAudio      → unvalidated (placeholder)
motionEvents     → unvalidated (placeholder)
```

Notably, PTZ capabilities are **queried at runtime** post-open (from the SDK's device-capability
response), not assumed by backend type—a CS-H6c reports none, while a PTZ dome would. This is why
the matrix must be computed dynamically, not hardcoded per backend name.

## The EZVIZ platform-view frame-capture question (flagged, not resolved)

`ezviz_flutter`'s player is a **platform view** (an embedded native Android/iOS view compositing
the SDK's own decoded video), unlike the `camera` plugin's **texture-based** preview which exposes
readable frame bytes. Two possibilities, to be verified against `ezviz_flutter`'s real API surface
**before finalizing**:

1. **Separate capture method:** The plugin may expose a native `capturePicture` method-channel
   call. If so, `EzvizCameraAdapter.captureFrame()` shells out to that call and reads the resulting
   file's bytes back. This is the most promising path and should be the first v1.3 implementation
   spike. If confirmed present and working, EZVIZ's `frameCapture` status becomes `supported`.

2. **No capture API exists:** `captureFrame()` must throw `UnsupportedError` — legitimate and
   contract-compliant. This raises an architecture question: does `captureFrame()` need to become
   an optional contract method for platform-view-only backends? Or should it be declared up front
   via `featureMatrix`'s `frameCapture` status (`unsupported`), allowing the UI to disable tabs
   before a caller tries and gets an error? Recommend the latter (feature-matrix-based gating), to
   keep `captureFrame()` a hard contract method all backends must implement (even if it's "throw
   UnsupportedError").

This is a **genuine open architecture question**, not a guess. The design is sound either way;
implementation must verify which `ezviz_flutter` call signature actually exists.

## Scanning decoupled from capture

**Design decision:** QR/barcode/OCR scanning are **app-level features gated by generic
`frameCapture` capability**, not adapter-implemented scanning logic. This matches what the example
app already does (`scanning/frame_scanner.dart` + `barcode_decoder.dart` work off any adapter's
`captureFrame()`, brand-agnostic) and keeps `CameraAdapter` from depending on `flutter_zxing` or
OCR packages (Interface Segregation) — a backend that can't produce frames simply reports
`frameCapture: unsupported` and the app hides those tabs.

A backend that needs smart frame selection (e.g., "wait for good lighting before encoding the QR
frame") can optimize within its own `captureFrame()` implementation, but the scanning logic itself
lives in the app.

## Risks and open questions

- **Feature-specific metadata schema** — the `metadata` field on `CameraFeatureSupport` is a
  free-form map. This works for simple key-value pairs but becomes unwieldy if a feature's
  metadata grows complex. The design assumes metadata stays simple (e.g., zoom min/max, supported
  languages as a list). If a backend ever needs a complex nested structure, consider a sealed type
  hierarchy for metadata per feature.
- **Frame-capture for platform views** — EZVIZ specifically (see above). May not be solvable
  without upstream `ezviz_flutter` changes if the native SDK doesn't expose a capture call.
