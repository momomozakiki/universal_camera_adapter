---
title: Camera Feature Matrix Model
version: 1.2
last_validated: 2026-07-23
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
| 1.1     | 2026-07-23 | Implemented in Epic 2.5 Phase A (`8a390ee`). Recorded the actual derivation direction (matrix derived *from* `CameraCapabilities`, for backward compatibility) and the future `frameStream` throughput ceiling for scanning. |
| 1.2     | 2026-07-23 | Two as-built corrections found by spec review. (1) "Contract change" claimed `featureMatrix` is a **required** getter every backend must implement — it is concrete and optional to override. (2) The EZVIZ entry claimed PTZ is **queried at runtime**; the shipped adapter deliberately reports all-false and refuses to read `isSupportPTZ`. Also added a `withStatuses` override example, a note that `unvalidated` is transitional, and this versioning note. |

> **Spec version vs. code version.** This document is versioned independently of the package. Each
> revision row names the commit whose behaviour it describes: **v1.1 and v1.2 both describe
> `8a390ee`** (Epic 2.5 Phase A) — v1.2 changed no code, it only corrected two places where this
> document contradicted what Phase A actually shipped. When code and spec disagree, the code is the
> source of truth and this file is the bug.

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

> **`unvalidated` is a transitional state, not a resting place.** It exists so a backend can be
> honest about what it has not yet proven, but every feature left there shows the user a permanent
> "unknown" — the UI can neither offer the feature confidently nor hide it. Once a feature has been
> exercised against real hardware, promote it to `supported` or demote it to `unsupported` in that
> backend's override, and record the verification in the weekly ledger. Treat a long-lived
> `unvalidated` as outstanding work, the same way a long-lived `TODO` is.

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

## Migration: `featureMatrix` is derived *from* `CameraCapabilities`

> **Corrected in v1.1 (as-built).** The v1.0 draft of this section proposed the reverse — making
> `capabilities` a derived view recomputed from `featureMatrix`. The shipped implementation
> (`8a390ee`) deliberately went the **other** direction, because re-basing `capabilities` on the
> matrix would have meant editing every existing backend in lockstep. The text below describes what
> is actually in `lib/src/camera_adapter.dart`.

**`CameraCapabilities` remains the primary post-open struct, unchanged.** Nothing that reads
`capabilities.hasZoom` had to change — that is what makes this backward compatible. `featureMatrix`
is added as a **concrete** getter on the base `CameraAdapter` that *derives* the matrix from
`capabilities` plus static defaults:

```dart
// lib/src/camera_adapter.dart — concrete, not abstract.
CameraFeatureMatrix get featureMatrix {
  final caps = capabilities; // throws StateError if not open — intentional.
  return CameraFeatureMatrix.fromStatuses(<CameraFeature, CameraFeatureStatus>{
    CameraFeature.zoom: caps.hasZoom ? supported : unsupported,
    CameraFeature.pan:  caps.hasPan  ? supported : unsupported,
    CameraFeature.tilt: caps.hasTilt ? supported : unsupported,
    CameraFeature.frameCapture: supported,   // required contract method
    CameraFeature.qrScanning: supported,     // follows from frameCapture
    CameraFeature.barcodeScanning: supported,
    CameraFeature.textRecognitionOcr: unvalidated,
    CameraFeature.twoWayAudio: unvalidated,
    CameraFeature.motionEvents: unvalidated,
  });
}
```

**Why concrete rather than abstract — the Open/Closed win.** Adding an app-level feature is one enum
value plus one line in this mapping, with **no per-adapter change**. Making `featureMatrix` a
*required* getter would have forced a lockstep edit across every backend on every new feature, which
is precisely the problem this model exists to remove.

Backends override `featureMatrix` **only where reality differs**:

| Backend | Override? | Why |
| :--- | :--- | :--- |
| `FlutterCameraAdapter` | No | The base derivation is already correct. |
| `ONVIFCameraAdapter` | **Must** | Its `capabilities` getter still throws `UnimplementedError`, so the base getter cannot read it. Returns an explicit all-`unsupported`/`unvalidated` matrix, gated on `isOpen`. |
| `EzvizCameraAdapter` | Yes | Reuses `super.featureMatrix.withStatuses({...})` to downgrade `frameCapture`/scanning to `unvalidated` (the vendored `capturePicture` is still a stub). |

**The base defaults are deliberately optimistic.** `frameCapture` is reported `supported` because it
is a required contract method, and scanning follows from it. Any backend whose `captureFrame()` is
not actually wired — i.e. throws — **must** override to downgrade `frameCapture` and the scanning
features, or it inherits a false positive. This is stated in the getter's doc-comment so future
adapter authors hit it at the point of use.

**Naming trap, recorded so it isn't reintroduced:** the matrix copy helper is `withStatuses(...)`,
**not** `override(...)`. A method named `override` shadows the `@override` annotation inside the same
class, silently breaking `==`, `hashCode`, and `toString`.

New consumers wanting bundles or tri-state read `featureMatrix` directly. Existing consumers read
`capabilities` as before, with no code changes.

**Not a breaking contract change** *(corrected in v1.2 — the v1.0 draft said the opposite)*. The base
`CameraAdapter` provides a **concrete** `featureMatrix` getter with a working default derivation, so
**no backend is forced to implement it**. Backends override **only** when that default would be wrong
— which is why the three did *not* have to gain it together, and why adding a tenth backend or a
tenth feature does not touch the other nine.

The as-built proof: `FlutterCameraAdapter` and `test/mock_camera_adapter.dart` contain **zero**
occurrences of `featureMatrix` and compile and pass the suite unchanged. Only `ONVIFCameraAdapter`
(whose `capabilities` throws, so the default cannot read it) and `EzvizCameraAdapter` (downgrading
`frameCapture`/scanning) override.

Overriding does **not** mean rebuilding the whole matrix. Start from the inherited one and change
only what differs — this is what `withStatuses` exists for:

```dart
// example/lib/ezviz/ezviz_camera_adapter.dart — the real override.
@override
CameraFeatureMatrix get featureMatrix {
  return super.featureMatrix.withStatuses(
    const <CameraFeature, CameraFeatureStatus>{
      CameraFeature.frameCapture: CameraFeatureStatus.unvalidated,
      CameraFeature.qrScanning: CameraFeatureStatus.unvalidated,
      CameraFeature.barcodeScanning: CameraFeatureStatus.unvalidated,
    },
  );
}
```

Build the matrix explicitly (via `CameraFeatureMatrix.fromStatuses`) only when the inherited value is
unusable — as in `ONVIFCameraAdapter`, where reading `super.featureMatrix` would throw.

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

**No longer all scaffolding** (this line said so at v1.0): `open()`/`close()`/`isOpen`/`buildPreview()`
are real and verified against hardware, while `listDevices()`, `capabilities`, `captureFrame()`, and
PTZ still throw `UnimplementedError`. Because `capabilities` throws, this backend **cannot** use the
base derivation and ships an explicit matrix instead — see the override table above. **As shipped
today** everything is `unsupported`/`unvalidated`. The target state, once the remaining Epic 2 items
land:

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

**Shipped 2026-07-22** in `example/lib/ezviz/ezviz_camera_adapter.dart` (not in `lib/` — see the
ROADMAP for why the vendored `ezviz_flutter` path dep keeps it out of the published package).

**As built today** — `capabilities` returns a plain `const CameraCapabilities()` and the override
downgrades capture/scanning:

```
zoom             → unsupported (setZoom throws UnsupportedError — not implemented)
pan              → unsupported (setPan not implemented; base-class default throw)
tilt             → unsupported (setTilt not implemented; base-class default throw)
frameCapture     → unvalidated (resolvable, not yet wired — see the spike below: the native SDK
                   supports capturePicture, the vendored plugin's implementation returns null)
qrScanning       → unvalidated (gated behind frameCapture)
barcodeScanning  → unvalidated (gated behind frameCapture)
textRecognitionOcr → unvalidated (gated behind frameCapture)
twoWayAudio      → unvalidated (placeholder)
motionEvents     → unvalidated (placeholder)
```

> **Corrected in v1.2.** The v1.0 draft claimed *"PTZ capabilities are **queried at runtime**
> post-open (from the SDK's device-capability response), not assumed by backend type."* The shipped
> adapter does the opposite, **deliberately**: it reports `hasPan`/`hasTilt` as `false` and its
> code-comment states it will *not* read `EzvizDeviceInfo.isSupportPTZ`, because
> `camera-adapter-authoring` §2 requires those flags to reflect a **wired** `setPan`/`setTilt`, not
> raw device support. Advertising `hasPan: true` for a PTZ dome whose `setPan` throws
> `UnsupportedError` would be exactly the optimistic guess the contract forbids. `isSupportPTZ` is
> still carried in `device.metadata` as **advisory** information for the UI.

**Target state**, once `setPan`/`setTilt`/`setZoom` are actually implemented: query the SDK's
device-capability response post-open and report per model — a CS-H6c reports no PTZ, a dome does.
At that point the flags become genuinely dynamic, which is the reason the matrix is computed rather
than hardcoded per backend name. Until then, "queried at runtime" describes the plan, not the code.

## The EZVIZ platform-view frame-capture question — spiked, resolved

`ezviz_flutter`'s player is a **platform view** (an embedded native Android/iOS view compositing
the SDK's own decoded video), unlike the `camera` plugin's **texture-based** preview which exposes
readable frame bytes. This was flagged as a genuine open question — verified by reading the
vendored plugin's native source (`example/third_party/ezviz_flutter/android/.../EzvizPlayerView.kt`,
`EzvizView.kt`) and the decompiled real EZVIZ Android SDK (`com.videogo.openapi.EZPlayer`):

- The method channel **does** expose `capturePicture` (`EzvizView.kt` calls
  `result.success(player.capturePicture())` — confirmed as one of the handful of calls that
  actually resolves the Dart future, unlike `initPlayerByDevice`/`setPlayVerifyCode`/`startRealPlay`).
- However, the vendored plugin's `EzvizPlayerView.kt::capturePicture()` is currently a **stub**:
  `Log.w(TAG, "Capture picture not implemented in current SDK version"); return null` — same stub
  on iOS (`EzvizPlayer.swift::capturePicture()`).
- The **real underlying native SDK does support it**: `com.videogo.openapi.EZPlayer` has a genuine
  `capturePicture(int): android.graphics.Bitmap` method (confirmed via decompiled class inspection)
  the vendored plugin simply never calls.

**Conclusion: frame capture is possible, it's a plugin-wiring gap, not an SDK limitation.**
`EzvizCameraAdapter.captureFrame()` can become `supported` once the vendored `EzvizPlayerView.kt`
(and iOS equivalent) is patched to call the real `player.capturePicture(...)`, encode the returned
`Bitmap` (e.g. PNG-compress to a `ByteArrayOutputStream`), and return the bytes (or a saved file
path) over the method channel instead of the current `null` stub. Until that patch lands,
`frameCapture` stays `unvalidated` (not `unsupported` — the capability is confirmed reachable, just
not yet wired), and `qrScanning`/`barcodeScanning`/`textRecognitionOcr` stay gated behind it per the
existing "scanning decoupled from capture" design below.

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

### Throughput ceiling — a future `frameStream` (out of scope for Epic 2.5)

The polling model above **works today** — the example app's QR and 1D-barcode tabs decode live via
repeated `captureFrame()` calls (Epic 1, shipped). What it cannot do is *sustain* a high frame rate:
each call re-captures and re-encodes a full frame, costing tens of milliseconds, so the achievable
decode rate is well under video frame rate.

If real-time (~30 fps) scanning is ever required, the fix is an **additive** contract extension —
a `Stream<Uint8List> frameStream` (or a typed `VideoFrame` equivalent) on `CameraAdapter`, letting a
decoder consume frames as the pipeline produces them instead of paying capture+encode per attempt.
Deliberately **not** part of Epic 2.5.

This model needs no change to accommodate it. `qrScanning`/`barcodeScanning`/`textRecognitionOcr`
already carry a tri-state status and are gated behind `frameCapture`; a backend that gains a frame
stream simply reports them `supported`, and one that lacks it keeps reporting `unvalidated`. Recorded
here so the limitation is a known design boundary rather than a surprise discovered during scanner
performance work.

## Risks and open questions

- **Feature-specific metadata schema** — the `metadata` field on `CameraFeatureSupport` is a
  free-form map. This works for simple key-value pairs but becomes unwieldy if a feature's
  metadata grows complex. The design assumes metadata stays simple (e.g., zoom min/max, supported
  languages as a list). If a backend ever needs a complex nested structure, consider a sealed type
  hierarchy for metadata per feature.
- **Frame-capture for platform views** — EZVIZ specifically (see above). May not be solvable
  without upstream `ezviz_flutter` changes if the native SDK doesn't expose a capture call.
