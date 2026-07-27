# Changelog

All notable changes to this package are documented here. This project adheres to
[Semantic Versioning](https://semver.org).

## Unreleased

### Fixed
- **Android: `listDevices()` no longer leaks a raw `PlatformException`.**
  `camera_android_camerax`'s `availableCameras()` has no `try`/`catch` of its own, so a CameraX
  `InitializationException` arrived at consumers untouched — its `toString()` prints a ~30-line Java
  stack trace, which is what reached the screen. The device-reports-no-camera case now returns an
  **empty list** (CameraX's own advice for it is to retry, which a refresh does); everything else
  becomes a `StateError` carrying a written message. `open()`, `captureFrame()` and `setZoom()` are
  wrapped the same way.
  This is a behaviour change, but the old behaviour was undocumented and contradicted the contract's
  published promise that failures "never" surface as a raw platform exception — so it is filed as a
  fix, not a breaking change. Windows was already unaffected (`camera_windows` wraps into
  `CameraException` itself).
- **Permission detection uses the platform's exact error code** (`CameraAccessDenied` /
  `AudioAccessDenied` — the same constant on both Android and Windows) instead of searching the
  message for "denied"/"permission", which both missed real failures and matched unrelated ones.

### Changed
- **`CameraAdapter.featureMatrix` now fails safe.** `frameCapture`, `qrScanning` and
  `barcodeScanning` previously defaulted to `CameraFeatureStatus.supported`, relying on a doc note
  telling backends they "MUST override" to downgrade. A backend that forgot inherited a claim its
  hardware could not honour. Undeclared features are now `unvalidated`.
  `CameraFeatureMatrix.fromStatuses`'s `fallback` default changes from `unsupported` to
  `unvalidated` for the same reason: undeclared means *unknown*, not *proven absent*.
  **A backend that has verified a feature on real hardware must now declare it explicitly** —
  `FlutterCameraAdapter` does. Consumers gating on `isSupported`/`supports` are unaffected:
  `unvalidated` was already, and remains, not-supported for gating purposes.

### Added
- **`CameraAdapter.declaredFeatures`** — a concrete (non-breaking, empty-by-default) getter where a
  backend states a status for every `CameraFeature`, readable without opening a device.
  `featureMatrix` layers it over the queried derivation, so a claim lives in exactly one place.
  `example/test/camera_feature_checklist_test.dart` walks the registry and fails by name for
  anything undeclared.
- `docs/camera/feature-support.md` — generated backend × feature table, regenerated and drift-checked
  by `example/test/feature_support_doc_test.dart`.

## 1.0.0

Initial release — core contract and the local-device backend.

### Added
- **`CameraAdapter`** contract: `listDevices`, `open`/`close`/`isOpen`, `capabilities`,
  `buildPreview`, `captureFrame`, and optional `setZoom`/`setPan`/`setTilt`. All network-bound
  methods take an optional `Duration timeout` (default 15s).
- **`CameraAdapterRegistry`** — instance-based, string-keyed factory registry with an optional
  default backend.
- **Value types** — `CameraDevice`, `CameraCapabilities`, `CameraLensFacing` (backend-agnostic).
- **`FlutterCameraAdapter`** — production backend for Android and Windows via the federated
  `camera` plugin; zoom capability queried from the device, `captureFrame` guarded against a hung
  native call.
- **`ONVIFCameraAdapter`** — scaffolding for the planned network/IP-camera backend (registers under
  `'onvif'`, throws `UnimplementedError` pending v1.1). No heavy dependencies pulled in yet.
- **`MockCameraAdapter`** (in `test/`) for consumer unit tests.
- Example app, CI (analyze + test), and documentation.

### Not yet supported
- ONVIF/RTSP live implementation (planned v1.1), audio (v1.2), events (v1.3), macOS/Linux (v2.0).
