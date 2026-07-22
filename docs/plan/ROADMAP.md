# Universal Camera Adapter — Roadmap

The canonical, checkable "where are we" tracker. Follow it top-down; update the status boxes and
commit note as each item is verified and committed. This supersedes ad-hoc status notes.

**Next action:** Epic 2 (v1.1) — implement the real ONVIF backend: WS-UsernameToken auth, Media
service (GetProfiles/GetStreamUri), and RTSP preview via `media_kit` (add the deferred
`http`/`xml`/`media_kit` deps then), following the `input-hardening` rules. Epic 2.5
(discovery/feature-matrix/profiles/wizard foundation) can proceed in parallel once Epic 2's core
auth/media is proven; Epic 2.6 (EZVIZ, per-user, depends on 2.5) depends on verifying the native
login flow is production-ready.

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

## Epic 2.6 — v1.3: EzvizCameraAdapter (per-user, native login; depends on 2.5)

Native SDK-hosted login with per-user tokens (not bridge-based). Requires vendored, patched
`ezviz_flutter` (4 upstream bugs confirmed on real hardware; patches pending upstream porting or
long-term vendoring decision).

- [ ] **BLOCKING:** Confirm playback, token persistence, and sign-out fully working post-native-login
      rewrite on real hardware; formally decide on upstream patch contribution vs. long-term vendoring.
- [ ] **BLOCKING:** Verify frame-capture capability via `capturePicture` spike; resolve platform-view
      frame-capture gap (determines `frameCapture` status for EZVIZ).
- [ ] **BLOCKING:** Decide when to retire `scripts/ezviz_bridge.py` and update
      `docs/camera/ezviz-integration-notes.md` with supersession note (deferred until native flow fully confirmed).
- [ ] `EzvizCameraAdapter` implementation (Dart `http` calls to EZVIZ Open Platform, replacing bridge).
- [ ] **`EzvizSetupWizard`** implementing per-user onboarding flow (Steps 1–5 per
      [`ezviz-setup-guide.md`](../camera/ezviz-setup-guide.md)).
- [ ] Feature matrix: zoom/pan/tilt queried per-device post-open; frameCapture resolved via spike;
      scanning features gated by frameCapture.
- [ ] Retire `example/lib/tabs/ezviz_tab.dart` (diagnostic bridge tab); migrate proven sequencing
      into `EzvizCameraAdapter.buildPreview()`.
- [ ] Update `ezviz-setup-guide.md`: move from "planned" to "validated" once end-to-end tested.

## Epic 3 — v1.2 / v1.3 (future)

- [ ] v1.2: two-way audio (intercom) for capable ONVIF cameras.
- [ ] v1.3: motion/event streams (ONVIF events).

## Epic 4 — v2.0 (if demand arises)

- [ ] macOS/Linux support via `camera_macos` / `camera_linux`.

---

## Completed Epics

_(none yet)_
