# Universal Camera Adapter — Roadmap

The canonical, checkable "where are we" tracker. Follow it top-down; update the status boxes and
commit note as each item is verified and committed. This supersedes ad-hoc status notes.

**Next action:** Epic 2.6 (EZVIZ) — `EzvizCameraAdapter` now exists (2026-07-22,
`example/lib/ezviz/ezviz_camera_adapter.dart`), implementing the full `CameraAdapter` contract on
top of the native per-user login already verified on real hardware. It deliberately lives in the
**example app**, not the main `lib/` package: `pub publish` rejects path/git dependencies, and
`ezviz_flutter` is only usable via the vendored, patched copy today (see the vendor-now decision
below). It's registered in the example registry as `'ezviz'` but not yet selectable from the
bottom-nav toolkit. Remaining work, in order: (1) build `EzvizSetupWizard` + wire session-switching
so `EzvizCameraAdapter` is actually reachable from the UI; (2) patch the vendored `capturePicture`
so `captureFrame()` starts returning real bytes instead of its current clear `StateError`; (3)
retire `example/lib/tabs/ezviz_tab.dart` once the wizard fully replaces it; (4) file the upstream
`ezviz_flutter` PR (non-blocking); (5) decide bridge/doc retirement timing for
`scripts/ezviz_bridge.py`/`ezviz-integration-notes.md` — unblocked (native flow fully confirmed)
but needs your sign-off, not unilateral action. Epic 2 (ONVIF) remains on the roadmap — a
different, complementary problem (open-standard access to *any* ONVIF-compliant IP camera, no
cloud dependency) — at lower priority in parallel. Epic 2.5 (discovery/feature-matrix/profiles/
wizard foundation) can proceed alongside either, and is now a hard prerequisite for making
`EzvizCameraAdapter` UI-reachable.

---

## Epic 0 — Adopt the self-correcting workflow & repo practices  *(done)*

- [x] Vendor workflow-core (`.claude/hooks/workflow_hook.py`, config, schemas, hook tests).
- [x] Fix plan-mode permission prompts (`.claude/settings.json` → `permissions.allow`).
- [x] Import the four skills (`adaptive-workflow`, `camera-adapter-authoring`,
      `dart-solid-principles`, `input-hardening`).
- [x] Documentation conventions (docs tree + index, provenance, weekly ledger, this roadmap).
- [x] Root `CLAUDE.md`, agents, `.gitignore`, CI, `CONTRIBUTING.md`, `SECURITY.md`.
- [x] Commit Section A on `feat/adopt-workflow`.

## Epic 1 — v1.0: core contract + local backend  *(done)*

- [x] Package skeleton: `pubspec.yaml`, `analysis_options.yaml` (strict-casts), `LICENSE`,
      `CHANGELOG.md`, `README.md`.
- [x] Core contract & value types (`lib/src/camera_adapter.dart`,
      `camera_adapter_registry.dart`, `camera_types.dart`).
- [x] `FlutterCameraAdapter` (Android + Windows) with queried zoom capability and the
      `captureFrame()` hung-driver safeguard.
- [x] Barrel export (`lib/universal_camera_adapter.dart`).
- [x] `MockCameraAdapter` + unit tests (registry, contract-via-mock).
- [x] Minimal `example/` app — since expanded into a bottom-nav **camera testing toolkit**
      (Preview/Capture, QR scanner, 1D barcode scanner, capture gallery, PTZ/zoom), all on one
      shared `CameraAdapter`; scanners poll `captureFrame()` + decode via `flutter_zxing` (no
      contract change). Builds for Android (`app-debug.apk`).
- [x] CI (`.github/workflows/test.yml`); `flutter analyze --fatal-infos` + `flutter test` green.

## Epic 2 — v1.1: ONVIF backend (network/IP cameras)

- [x] Scaffolding: `lib/src/onvif/` stubs (adapter, SOAP, media service, RTSP preview) that compile
      and register but throw `UnimplementedError`. **(done — v1.0 + scaffolding pass)**
- [ ] WS-UsernameToken (PasswordDigest) + HTTP Digest auth.
- [ ] Media service (GetProfiles, GetStreamUri) + RTSP preview via `media_kit` (TCP).
- [ ] PTZ AbsoluteMove (pan/tilt/zoom); snapshot via GetSnapshotUri.
- [ ] WS-Discovery (optional auto-discovery) + manual IP input.
- [ ] Input-hardening pass on all SOAP/XML/RTSP parsing.

## Epic 2.5 — v1.2: Discovery pipeline + feature matrix + camera profiles + modular add-camera

Foundation for multi-backend discovery, capabilities, and setup UI (all backends benefit; can proceed
in parallel with Epic 2's completion).

- [ ] **`CameraFeature` enum** (zoom, pan, tilt, frameCapture, qrScanning, barcodeScanning,
      textRecognitionOcr, twoWayAudio, motionEvents as `unvalidated` placeholders for future epics).
- [ ] **`CameraFeatureStatus`** tri-state (unsupported, unvalidated, supported) and
      **`CameraFeatureSupport`** + **`CameraFeatureMatrix`** types (`lib/src/camera_feature.dart`).
- [ ] **`CameraAdapter.featureMatrix`** additive getter; `CameraCapabilities` derived from matrix
      (backward compatible). All backends (`FlutterCameraAdapter`, `ONVIFCameraAdapter`,
      `EzvizCameraAdapter` once implemented) gain `featureMatrix` together.
- [ ] **`CameraDiscoveryPipeline`** + **`NetworkDiscoverable` mixin** (`lib/src/discovery/`); three-stage
      observable discovery (OS filtering → local enumeration → external probes/cloud list).
      ONVIF WS-Discovery updated to implement `NetworkDiscoverable`.
- [ ] **`CameraProfile`** + **`CameraProfileStore`** (injectable, default: shared_preferences) +
      **`CameraSecretStore`** (injectable, default: flutter_secure_storage) (`lib/src/persistence/`).
      Default-camera selection rules, fallback to live discovery.
- [ ] **`CameraSetupWizard`** abstract + **`CameraSetupWizardRegistry`** (`lib/src/setup/`), parallel
      registry for modular setup UI.
- [ ] Example app **`CamerasTab`** (discovery results + saved profiles + "Add camera" wizard chooser).
- [ ] Example app **`CameraSession.switchTo()`** for seamless camera switching.
- [ ] New documentation: [`discovery-pipeline.md`](../camera/discovery-pipeline.md),
      [`feature-matrix.md`](../camera/feature-matrix.md),
      [`camera-profiles.md`](../camera/camera-profiles.md),
      [`add-camera-wizard.md`](../camera/add-camera-wizard.md).
- [ ] **TODO:** update `camera-adapter-authoring` skill with `CameraFeature` guidance once `CameraFeatureMatrix`
      lands (currently only documents `CameraCapabilities` boolean flags).

## Epic 2.6 — v1.3: EzvizCameraAdapter (per-user, native login)  *(in progress — current priority)*

Native SDK-hosted login with per-user tokens (not bridge-based) — **proven end-to-end on real
hardware**: sign-in, device list, and sign-out all confirmed working (`history/2026-W30.md`).
Requires vendored, patched `ezviz_flutter` (4 upstream bugs confirmed on real hardware; patches
pending upstream porting or long-term vendoring decision). Does not strictly depend on Epic 2.5
landing first — the profile/wizard scaffolding can be retrofitted once 2.5 exists, but the adapter
and its verification work can proceed now.

- [x] Native per-user login (`EzvizAuthManager.openLoginPage()`) working on real hardware.
- [x] Device list retrieval working on real hardware (post `getDeviceList` flat-shape fix).
- [x] Sign-out flow working on real hardware (returns to sign-in, triggers fresh login).
- [x] Playback re-verified on real hardware post native-login rewrite (2026-07-22, test phone
      CPH2113): `_EzvizNativePlayer` reached `Player state: playing` with live video from "Scale
      Tech Cam" (serial BK0381480).
- [x] Force-quit/relaunch token persistence re-verified on real hardware (2026-07-22): `adb shell
      am force-stop` followed by a cold relaunch landed directly on the device list (no re-login
      prompt) — confirms the token-clobbering fix holds under a real process kill, not just an app
      backgrounding.
- [x] **Decided (2026-07-22):** vendor now, upstream later, non-blocking. Ship on the vendored,
      patched `ezviz_flutter` copy indefinitely (already working, zero extra cost); separately file
      the plugin-side fixes (token clobbering, `getDeviceList` shape, and the `capturePicture` wiring
      once patched) as a PR against upstream `ezviz_flutter`, with no expectation of a merge
      timeline and no implementation work blocked on it landing. If it merges, the vendored copy can
      be dropped later; if not, no worse off than committing to vendoring outright.
- [ ] File the upstream PR (token-clobbering + `getDeviceList` shape fixes; add the `capturePicture`
      fix once done) — non-blocking, can happen any time.
- [x] Frame-capture spike: confirmed via native source inspection (vendored `EzvizPlayerView.kt`/
      `EzvizView.kt` + decompiled `com.videogo.openapi.EZPlayer`) that `capturePicture` is a real,
      working method-channel call, but the vendored plugin's implementation is a stub that always
      returns `null` on both platforms — the real native SDK (`EZPlayer.capturePicture(int):
      Bitmap`) supports it, it's just not wired up. Not a platform-view dead end after all — see
      [`feature-matrix.md`](../camera/feature-matrix.md).
- [ ] Patch vendored `EzvizPlayerView.kt` (+ iOS `EzvizPlayer.swift`) to call the real
      `capturePicture`, encode the returned bitmap, and return bytes/a file path — unblocks
      `frameCapture` → `supported`, then `qrScanning`/`barcodeScanning`/`textRecognitionOcr`.
- [ ] **BLOCKING:** Decide when to retire `scripts/ezviz_bridge.py` and update
      `docs/camera/ezviz-integration-notes.md` with supersession note (deferred until native flow fully confirmed).
- [x] **`EzvizCameraAdapter` implementation** (2026-07-22) — lives in
      `example/lib/ezviz/ezviz_camera_adapter.dart`, **not** in the main `lib/` package: `pub publish`
      rejects path/git dependencies, and `ezviz_flutter` is only usable today via the vendored,
      patched copy (a `path:` dep) — see the "vendor now, upstream later" decision above. Implements
      `listDevices()` (maps `EzvizDeviceInfo` → `CameraDevice`), `open()`/`close()` (reads the
      natively-cached token via `EzvizAuthManager.getAccessToken()`; verification code passed via
      `device.metadata['verificationCode']`, since the contract has no dedicated parameter),
      `buildPreview()` (same un-awaited `initPlayerByDevice → setPlayVerifyCode → startRealPlay`
      sequence proven in `ezviz_tab.dart`), and `captureFrame()` (calls the real `capturePicture()` —
      throws a clear `StateError` today since the native stub still returns `null`; will start
      working once the `capturePicture` patch below lands). `setZoom` throws `UnsupportedError`
      (not implemented); `setPan`/`setTilt` inherit the base class default throw. Registered in
      `example/lib/main.dart`'s `buildRegistry()` as `'ezviz'` (not default, not yet selectable from
      the bottom-nav toolkit — see below). `flutter analyze --fatal-infos` clean.
- [ ] Move `EzvizCameraAdapter` into the main `lib/` package once either (a) the upstream PR merges
      and `ezviz_flutter` is usable straight from pub.dev, or (b) a deliberate decision to vendor
      permanently is made (e.g. via a separate companion pub package) — tracked as a follow-up, not
      blocking.
- [ ] **`EzvizSetupWizard`** implementing per-user onboarding flow (Steps 1–5 per
      [`ezviz-setup-guide.md`](../camera/ezviz-setup-guide.md)) — needed before `EzvizCameraAdapter`
      can be selected from the bottom-nav toolkit (requires `CameraSession.switchTo()` from Epic 2.5
      too, or an equivalent).
- [ ] Feature matrix: zoom/pan/tilt queried per-device post-open; frameCapture resolved via spike;
      scanning features gated by frameCapture.
- [ ] Retire `example/lib/tabs/ezviz_tab.dart` (diagnostic bridge tab) once the setup wizard +
      session-switching UI can fully replace its sign-in/device-list/playback flow.
- [ ] Update `ezviz-setup-guide.md`: move from "planned" to "validated" once end-to-end tested.

## Epic 3 — v1.2 / v1.3 (future)

- [ ] v1.2: two-way audio (intercom) for capable ONVIF cameras.
- [ ] v1.3: motion/event streams (ONVIF events).

## Epic 4 — v2.0 (if demand arises)

- [ ] macOS/Linux support via `camera_macos` / `camera_linux`.

---

## Completed Epics

_(none yet)_
