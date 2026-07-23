# Universal Camera Adapter — Roadmap

The canonical, checkable "where are we" tracker. Follow it top-down; update the status boxes and
commit note as each item is verified and committed. This supersedes ad-hoc status notes.

**Next action:** Epic 2.5 **Phase C** — the `ONVIFCameraAdapter.credentials` final-field fix. Epic 2.5
is being delivered as a lettered phase sequence (see the plan archived under `plans/`); **Phase A
(feature matrix) and Phase B (profile/secret persistence) have landed** in `8a390ee` and `21fc728`
respectively, on top of the guardrail codification in `5303f85`. Phase C adds
`OnvifCredentials.fromMetadata()` so credentials flow through `open(device)` like every other
adapter, and registers `'onvif'` as a first-class camera type in the example registry. Remaining
after that: **Phase D** (`CameraSetupWizard` + registry, per-type wizards), **Phase E** (`CamerasTab`,
session restore, removal of the `onvif_tab.*`/`ezviz_tab.*` raw-prefs hacks), **Phase F** (tests,
doc frontmatter flips, review gates, push). WS-Discovery / `CameraDiscoveryPipeline` is
**deliberately deferred** out of this slice — manual "add by IP" covers ONVIF for now.

Epic 2.6 (EZVIZ) is paused mid-flight, not abandoned: `EzvizSetupWizard`
(`example/lib/ezviz/ezviz_setup_wizard.dart`) already drives sign-in → device list → verification
code → handoff into the shared `CameraSession`, and `example/lib/tabs/ezviz_tab.dart` is retired.
Its remaining work, in order: (1) patch the vendored `capturePicture` so `captureFrame()` returns
real bytes instead of its current clear `StateError`; (2) file the upstream `ezviz_flutter` PR
(non-blocking); (3) decide bridge/doc retirement timing for
`scripts/ezviz_bridge.py`/`ezviz-integration-notes.md` — unblocked (native flow fully confirmed) but
needs sign-off, not unilateral action. Note that Epic 2.5 Phase D **refactors** `EzvizSetupWizard` to
write through `CameraSecretStore`, so 2.5 should land first to avoid reworking it twice.

**Epic 2 update (2026-07-22):** WS-UsernameToken (PasswordDigest) + HTTP Digest auth landed —
`ONVIFCameraAdapter.open()`/`close()`/`isOpen` are real (hand-rolled SOAP via `http`+`xml`, not the
pub.dev `onvif` package; validated with a `GetDeviceInformation` probe). Media service
(`GetProfiles`/`GetStreamUri`) + RTSP preview via `media_kit` landed the same day: `open()` now also
resolves the first media profile's RTSP URI and opens a `media_kit`-backed preview player, so
`buildPreview()` is real too. `listDevices()`, `capabilities`, `captureFrame()`, and PTZ remain
`_planned()`. An external
"zero-assumption ONVIF" integration guide was reviewed and rejected everywhere it conflicted with
already-shipped decisions (EZVIZ's cloud-account auth is not admin+verification-code; RTSP preview
is `media_kit`, not `flutter_vlc_player`; caching belongs in Epic 2.5's `CameraProfileStore`/
`CameraSecretStore`, not raw `SharedPreferences`) — only its WS-UsernameToken/HTTP-Digest auth shape
was adopted, translated to this project's typed-error/`OnvifCredentials` conventions. A follow-up
3-mode setup wizard (Cloud/ONVIF/AP-camera-WiFi) was requested but deliberately deferred to a
separate, later plan.

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
- [x] WS-UsernameToken (PasswordDigest) + HTTP Digest auth. **(done 2026-07-22 —
      `lib/src/onvif/onvif_soap.dart`, `onvif_http_client.dart`,
      `onvif_camera_adapter.dart`; `open()`/`close()`/`isOpen` are real.)**
- [x] Media service (GetProfiles, GetStreamUri) + RTSP preview via `media_kit` (TCP).
      **(done 2026-07-22 — `onvif_media_service.dart` (real `GetProfiles`/`GetStreamUri`, with an
      `OnvifMediaServiceBase` seam for tests) + `rtsp_preview.dart` (`media_kit`/`media_kit_video`,
      forces `rtsp-transport=tcp`, behind an `OnvifPreviewController` seam); `open()` now resolves
      the main profile's stream URI and opens the preview player, `buildPreview()` is real.
      **Verified on real hardware 2026-07-23** (Windows, example app) against an EZVIZ
      `CS-H6c-R200-8H8WFL` at `192.168.0.217`: port fallback `:8000` → `:80`, `GetDeviceInformation`
      200, `GetProfiles` → `Profile_1`/`mainStream`, `GetStreamUri` →
      `rtsp://…/Streaming/Channels/101`, and a `media_kit` H/W-rendered 3840×2160 preview
      (`Direct3D Feature Level: 11_0`).)**
- [ ] PTZ AbsoluteMove (pan/tilt/zoom); snapshot via GetSnapshotUri.
- [ ] WS-Discovery (optional auto-discovery) + manual IP input.
- [ ] Input-hardening pass on all SOAP/XML/RTSP parsing.

## Epic 2.5 — v1.2: Discovery pipeline + feature matrix + camera profiles + modular add-camera

Foundation for multi-backend discovery, capabilities, and setup UI (all backends benefit; can proceed
in parallel with Epic 2's completion).

> **Note (2026-07-22):** a minimal, in-memory `CameraSession.switchTo(type)` +
> `CameraSession.openDevice(device)` already landed as part of Epic 2.6 (registry-based backend
> switching only — no `CameraProfile`/`CameraProfileStore`/`CameraSecretStore`). The
> `CameraSetupWizard` item below and any future profile/persistence work should extend that
> mechanism rather than re-inventing adapter switching.

- [x] **Guardrail docs/skills (prerequisite — doc-only, no Dart code).** **(done 2026-07-22 —
      `5303f85`.)** Codify the two enforcement
      rules *before* the implementation bullets below (and before further ONVIF/EZVIZ feature work):
      (1) per-camera-type setup/connection state flows through one generic mechanism, never a
      per-type `SharedPreferences` namespace; (2) camera features query capability and degrade to
      "not supported" — never adapter-embedded feature logic, never feature-code camera-type
      branching. Landed as additions to `camera-adapter-authoring` (§6 features-queried, §7
      setup-state-generic), `state-management` (Rule 6), `dart-solid-principles` (ISP both-ways), and
      the `code-reviewer` agent (hard must-fix row 6). Checkable today against the current
      boolean-`CameraCapabilities`/`CameraSession` code; the implementation bullets below inherit it.
- [x] **`CameraFeature` enum** (zoom, pan, tilt, frameCapture, qrScanning, barcodeScanning,
      textRecognitionOcr, twoWayAudio, motionEvents as `unvalidated` placeholders for future epics).
      **(done 2026-07-23 — Phase A, `8a390ee`, `lib/src/camera_feature.dart`.)**
- [x] **`CameraFeatureStatus`** tri-state (unsupported, unvalidated, supported) and
      **`CameraFeatureSupport`** + **`CameraFeatureMatrix`** types (`lib/src/camera_feature.dart`).
      **(done 2026-07-23 — Phase A, `8a390ee`. `CameraFeatureMatrix` is always fully populated via
      `fromStatuses`; `kFeatureBundles` groups `ptz`/`scanning`. The copy helper is named
      `withStatuses`, deliberately **not** `override` — a method named `override` shadows the
      `@override` annotation inside the class and breaks `==`/`hashCode`/`toString`.)**
- [x] **`CameraAdapter.featureMatrix`** additive getter. **(done 2026-07-23 — Phase A, `8a390ee`.)**
      **Derivation direction, deliberately chosen:** the **matrix is derived from
      `CameraCapabilities`**, not the reverse. `CameraCapabilities` stays the primary post-open
      struct, so nothing existing had to change — that is what makes this backward compatible. The
      base getter is *concrete*, so adding a feature is one enum value + one mapping edit in
      `camera_adapter.dart` with **no per-adapter lockstep change** (the OCP win). Backends override
      only where reality differs: `ONVIFCameraAdapter` must (its `capabilities` still throws
      `UnimplementedError`), `EzvizCameraAdapter` downgrades frameCapture/scanning via
      `super.featureMatrix.withStatuses(...)`, `FlutterCameraAdapter` needs no override. The base
      defaults are deliberately optimistic — any backend whose `captureFrame()` is not actually
      wired **must** override to downgrade `frameCapture`/scanning.
      > **Future contract extension — `frameStream` (out of scope for Epic 2.5).** The scanning
      > features are wired to `captureFrame()`, and the example app's QR/1D-barcode tabs already
      > work that way today (Epic 1): poll `captureFrame()`, decode via `flutter_zxing`. What polling
      > cannot do is *sustain* a high frame rate — every call re-captures and re-encodes, so each
      > iteration costs tens of milliseconds. A real-time (~30 fps) scanner would want a
      > `Stream<Uint8List> frameStream` added to the `CameraAdapter` contract, feeding the decoder
      > without per-frame capture overhead. That is an **additive** extension (no breaking change),
      > and the feature matrix needs no modification to accommodate it: `qrScanning`/
      > `barcodeScanning` already carry a tri-state status and are gated behind `frameCapture`.
      > Tracked here so it is not rediscovered as a surprise when scanner performance work starts.
- [ ] **`CameraDiscoveryPipeline`** + **`NetworkDiscoverable` mixin** (`lib/src/discovery/`); three-stage
      observable discovery (OS filtering → local enumeration → external probes/cloud list).
      ONVIF WS-Discovery updated to implement `NetworkDiscoverable`.
- [x] **`CameraProfile`** + **`CameraProfileStore`** (injectable, default: shared_preferences) +
      **`CameraSecretStore`** (injectable, default: flutter_secure_storage) (`lib/src/persistence/`).
      **(done 2026-07-23 — Phase B, `21fc728`.)** Profiles persist under one versioned envelope
      (`uca.camera_profiles`, `{"version":1,"profiles":[…]}`); `loadAll()` never throws and skips
      malformed entries; exactly one `isDefault`, and deleting the default promotes the most-recent
      survivor. An empty store never fabricates a profile — the session falls back to live discovery.
      Secrets live separately in `flutter_secure_storage` under `uca_secret.<profileId>.<key>`;
      **`CameraProfile` never holds a secret** and is safe to log or export. `CameraProfile.id` is a
      save-time v4 UUID (hand-rolled via `Random.secure()`, no `uuid` dep), deliberately distinct from
      the ephemeral `CameraDevice.id`. Multi-camera support falls out of this directly: N cameras of
      any brand mix = N profiles, each with its own `displayName`, endpoint metadata, and secret.
      **The `ONVIFCameraAdapter.credentials` final-field fix that this unblocks is Epic 2.5 Phase C
      (in progress)** — it is the structural root that *forces* the out-of-band
      `example/lib/onvif/onvif_connect_view.dart` persistence (the documented exception in
      `camera-adapter-authoring` §7 / `state-management` Rule 6). Once credentials flow through
      `open(device)` via `OnvifCredentials.fromMetadata()`, that exception is **removed** in Phase E
      rather than perpetuated.
- [ ] **`CameraSetupWizard`** abstract + **`CameraSetupWizardRegistry`** (`lib/src/setup/`), parallel
      registry for modular setup UI.
- [ ] Example app **`CamerasTab`** (discovery results + saved profiles + "Add camera" wizard chooser).
- [ ] Example app **`CameraSession.switchTo()`** for seamless camera switching.
- [ ] New documentation: [`discovery-pipeline.md`](../camera/discovery-pipeline.md),
      [`feature-matrix.md`](../camera/feature-matrix.md),
      [`camera-profiles.md`](../camera/camera-profiles.md),
      [`add-camera-wizard.md`](../camera/add-camera-wizard.md).
- [ ] **TODO (second, narrower pass):** once `CameraFeatureMatrix`/`CameraProfile` land in code, add
      concrete API-usage examples to the skills (how to declare a `CameraFeature`, how to write
      through `CameraProfileStore`) on top of the guardrail rule already in place from the prerequisite
      step above. This is additive polish — the decoupling *rule* is already codified and enforced;
      this pass just swaps the "once landed" placeholders for real `featureMatrix`/`CameraProfile`
      snippets.

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
- [x] **`EzvizSetupWizard`** (2026-07-22, `example/lib/ezviz/ezviz_setup_wizard.dart`) implementing
      per-user onboarding (sign-in → device list → verification code → handoff) — reachable from the
      bottom-nav toolkit via a new minimal, registry-based `CameraSession.switchTo()`/`openDevice()`
      (`example/lib/camera_session.dart`; no `CameraProfile`/persistence stack — that's Epic 2.5's
      job). Playback itself stays owned by `EzvizCameraAdapter.buildPreview()`; once connected, the
      wizard renders the same `PreviewTab` every other backend uses.
- [ ] Feature matrix: zoom/pan/tilt queried per-device post-open; frameCapture resolved via spike;
      scanning features gated by frameCapture.
- [x] Retire `example/lib/tabs/ezviz_tab.dart` (diagnostic bridge tab) (2026-07-22) — fully replaced
      by `EzvizSetupWizard` + session-switching.
- [ ] Update `ezviz-setup-guide.md`: move from "planned" to "validated" once end-to-end tested.

## Epic 2.7 — PTZ latency & Imaging Service integration  *(future)*

Quality/latency pass on top of Epic 2's PTZ + snapshot work. **Epic 2's "PTZ AbsoluteMove; snapshot
via GetSnapshotUri" bullet is the prerequisite** — this epic is not a duplicate of it. These are the
areas where a naive ONVIF implementation feels sluggish or produces unusable frames in practice, so
they are recorded now rather than rediscovered later.

- [ ] **Continuous PTZ** — `ContinuousMove` + `Stop` (press-and-hold), instead of only the one-shot
      `AbsoluteMove` from Epic 2. Absolute moves make a held button feel stepped and laggy.
- [ ] **HTTP Keep-Alive on the ONVIF client** (`lib/src/onvif/onvif_http_client.dart`) — PTZ sends a
      SOAP request per command; re-establishing a TCP connection (and re-running Digest auth) on
      every command dominates perceived latency.
- [ ] **Imaging Service: shutter/exposure control** — motion blur on a moving PTZ camera is an
      exposure-time problem, not a decoder problem; needs `GetImagingSettings`/`SetImagingSettings`.
- [ ] **Autofocus triggering** — `Move`/`Stop` on the imaging focus interface after a PTZ move.
- [ ] **Further low-latency RTSP tuning** — beyond the `profile=low-latency` + `cache=no` fix already
      shipped in `lib/src/onvif/rtsp_preview.dart` (deliberately avoiding `untimed`/`no-correct-pts`,
      which cause frame pacing artifacts).

## Epic 3 — v1.2 / v1.3 (future)

- [ ] v1.2: two-way audio (intercom) for capable ONVIF cameras.
- [ ] v1.3: motion/event streams (ONVIF events).

## Epic 4 — v2.0 (if demand arises)

- [ ] macOS/Linux support via `camera_macos` / `camera_linux`.

---

## Completed Epics

_(none yet)_
