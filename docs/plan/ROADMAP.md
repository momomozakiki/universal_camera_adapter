# Universal Camera Adapter — Roadmap

The canonical, checkable "where are we" tracker. Follow it top-down; update the status boxes and
commit note as each item is verified and committed. This supersedes ad-hoc status notes.

**Next action:** Epic 2 (v1.1) — implement the real ONVIF backend: WS-UsernameToken auth, Media
service (GetProfiles/GetStreamUri), and RTSP preview via `media_kit` (add the deferred
`http`/`xml`/`media_kit` deps then), following the `input-hardening` rules.

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
- [x] Minimal `example/` app.
- [x] CI (`.github/workflows/test.yml`); `flutter analyze --fatal-infos` + `flutter test` green.

## Epic 2 — v1.1: ONVIF backend (network/IP cameras)

- [x] Scaffolding: `lib/src/onvif/` stubs (adapter, SOAP, media service, RTSP preview) that compile
      and register but throw `UnimplementedError`. **(done — v1.0 + scaffolding pass)**
- [ ] WS-UsernameToken (PasswordDigest) + HTTP Digest auth.
- [ ] Media service (GetProfiles, GetStreamUri) + RTSP preview via `media_kit` (TCP).
- [ ] PTZ AbsoluteMove (pan/tilt/zoom); snapshot via GetSnapshotUri.
- [ ] WS-Discovery (optional auto-discovery) + manual IP input.
- [ ] Input-hardening pass on all SOAP/XML/RTSP parsing.

## Epic 3 — v1.2 / v1.3 (future)

- [ ] v1.2: two-way audio (intercom) for capable ONVIF cameras.
- [ ] v1.3: motion/event streams (ONVIF events).

## Epic 4 — v2.0 (if demand arises)

- [ ] macOS/Linux support via `camera_macos` / `camera_linux`.

---

## Completed Epics

_(none yet)_
