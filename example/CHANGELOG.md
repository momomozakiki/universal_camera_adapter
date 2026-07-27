# Changelog — example app

Tracks the `universal_camera_adapter_example` test-harness app, versioned independently of the
root package. This app is never published (`publish_to: none`); its version exists to name the
APKs staged into `dist/` by `scripts/build-apk.ps1`. Keep-a-Changelog style; newest on top.

## [1.0.3+4] - 2026-07-27

### Fixed
- **A saved EZVIZ camera could make the app impossible to launch.** `EzvizCameraAdapter.listDevices()`
  called the native `getDeviceList` without `initSDK` having run — init only happened in `open()`.
  Restoring a saved EZVIZ camera at startup enumerates *before* it opens, so the native
  `EZGlobalSDK.getInstance()` was null and the plugin dereferenced it on a Kotlin coroutine whose
  only `catch` is the EZVIZ SDK's `BaseException`. The resulting `NullPointerException` was a
  `FATAL EXCEPTION` that killed the process — no Dart `try`/`catch` could intercept it — during
  startup restore, before any UI existed from which to remove the offending camera. A shared
  `_ensureSdk()` now initialises the SDK on every path that touches it.
  Latent since the adapter was written, not a regression: reproduced identically on 1.0.1+2.
- **Adding a camera no longer changes what opens at the next launch.** With no profile marked
  default, startup restore fell back to "most recently created wins", so adding a camera silently
  promoted it into the launch path. Auto-open now requires an explicit default (set from the
  Cameras tab); the first camera saved on a fresh install becomes it.

### Added
- **Crash-loop breaker for startup restore.** A flag is persisted before the camera is opened and
  cleared afterwards; a launch that finds it still set knows the previous launch did not survive,
  skips the auto-open, and lands on the Cameras tab explaining why. Backend-agnostic on purpose —
  it is the only defence available when a backend kills the process rather than throwing.

## [1.0.2+3] - 2026-07-27

### Fixed
- Built for on-device testing of the no-camera error page. A device reporting no usable built-in
  camera previously filled the "Built-in camera" setup screen with a ~30-line CameraX Java stack
  trace; it now shows a "No built-in camera found" empty state with a cause-specific hint and the
  Refresh / Cancel row.

### Added
- **Features tab** — every `CameraFeature` for the connected camera with its tri-state status
  (Available / Under development / Not supported). Doubles as the on-hardware verification surface
  for promoting a backend's declaration from `unvalidated` to `supported`.
- Tri-state status chips on the PTZ and scanner tabs, replacing the previous binary
  supported/not-supported note. A feature the app has wired but not yet confirmed now reads
  "Under development" instead of blaming the camera.

## [1.0.1+2] - 2026-07-27

### Fixed
- Rebuilt for on-device Android testing of the rename-dialog `_dependents.isEmpty` crash fix and
  the EZVIZ preview builder `KeyedSubtree` parity fix.

## [1.0.0+1] - 2026-07-19

### Added
- Initial tracked version for the example camera-testing toolkit APK. Establishes the
  version-per-distributable-build discipline (versioned `dist/` copies + `.sha256` sidecars).
