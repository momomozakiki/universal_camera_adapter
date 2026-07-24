# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

`universal_camera_adapter` is a **modular, pluggable camera abstraction for Flutter**. It unifies
local device cameras (Android via `camera_android`, Windows webcams via `camera_windows`) and
external network/IP cameras (ONVIF/RTSP) behind a single, testable `CameraAdapter` contract, using
the **Adapter + Registry** patterns. Consumers code against the interface, never a concrete backend.

**Target platforms:** Android and Windows are fully supported today; macOS/Linux are not implemented
(no `camera_macos`/`camera_linux` deps). Networked ONVIF cameras are cross-platform (network-based)
and **partially implemented** — authenticated connect (WS-UsernameToken + HTTP Digest) and live RTSP
preview work and are hardware-verified; `listDevices` (WS-Discovery), `capabilities`, `captureFrame`
(snapshot), and PTZ still throw `UnimplementedError` (see the roadmap for exact per-method status).

## Architecture (the contract)

- **`CameraAdapter`** (`lib/src/camera_adapter.dart`) — the abstract contract: `listDevices()`,
  `open(device, {timeout})`, `close()`, `isOpen`, `capabilities`, `featureMatrix`, `buildPreview()`,
  `captureFrame({timeout})`, `setZoom/setPan/setTilt({timeout})`. **One adapter instance manages at
  most one open device** — `open()` closes any previous device first. Capabilities are **queried
  from the opened device, never assumed**; `featureMatrix` exposes tri-state
  (`supported`/`unvalidated`/`unsupported`) capability discovery. Failures map to a typed surface
  (`StateError`/`UnsupportedError`/`TimeoutException`/`FormatException`) — no raw plugin/SDK
  exception leaks through.
- **`CameraAdapterRegistry`** (`lib/src/camera_adapter_registry.dart`) — **instance-based** (not a
  singleton), string-keyed factory map: `register(type, factory, {asDefault})`, `create(type)`,
  `createDefault()`. A default exists only if registered with `asDefault: true`.
- **`FlutterCameraAdapter`** (`lib/src/flutter_camera_adapter.dart`) — the shipped local backend.
- **`ONVIFCameraAdapter`** (`lib/src/onvif/`) — the network backend, **partially implemented**:
  authenticated connect + live RTSP preview work; discovery, snapshot, and PTZ still throw
  `UnimplementedError`.
- **Persistence + setup** (`lib/src/persistence/`, `lib/src/setup/`) — saved-camera profiles with
  secure-storage secrets (`CameraProfile`/`CameraProfileStore`/`CameraSecretStore`) and a modular
  `CameraSetupWizardRegistry` (Epic 2.5), so consumers can persist and add cameras generically.

**The Golden Rule (consumers):** depend only on `CameraAdapter` + `CameraAdapterRegistry`; check
`capabilities` at runtime to drive UI; always pair `open()` with `close()`; expect and handle the
typed errors.

## Active roadmap (FOLLOW THIS)

[`docs/plan/ROADMAP.md`](docs/plan/ROADMAP.md) is the canonical, checkable "where are we" tracker.
Its `**Next action:**` line is auto-surfaced into context at the start of every session by
`.claude/hooks/workflow_hook.py`. Follow it top-down; keep it current as each item is verified and
committed.

## Skills-first workflow (do this BEFORE any plan or change)

Before starting **any** task (planning, coding, refactoring, docs, debugging), decide which skill
governs the area and load it. Available skills (`.claude/skills/`):

- **`adaptive-workflow`** — the Phase 0–3 operating manual (invariants, ledger, provenance, closure).
- **`camera-adapter-authoring`** — the concrete checklist for the `CameraAdapter` contract and any
  backend (local, ONVIF/RTSP/PTZ).
- **`dart-solid-principles`** — SOLID + everyday Dart practices (the *why* behind the design).
- **`input-hardening`** — treat all external input (ONVIF SOAP/XML, RTSP, discovery) as untrusted.
- **`state-management`** — any UI/state-bearing change must decide in-memory vs. persisted and
  say so; don't let app state silently reset across rebuilds/restarts.
- **`release-packaging`** — build → version → stage → verify for the pub package (`pub publish`,
  CHANGELOG) and the example APK (`scripts/build-apk.ps1`, versioned `dist/` copies + checksums).

Review gates: the `code-reviewer` and `security-reviewer` agents (`.claude/agents/`) review an
assembled diff before commit; `doc-writer` keeps docs accurate.

<!-- ==================================================================== -->
<!-- BEGIN adaptive-workflow fragment (managed by workflow-core, vendored) -->
<!-- Included verbatim; project-specific notes go OUTSIDE this block.      -->
<!-- ==================================================================== -->

## Adaptive Self-Correcting Workflow

This project follows the Adaptive Self-Correcting Workflow (vendored from
[`ai-self-correcting-workflow`](https://github.com/momomozakiki/ai-self-correcting-workflow) — the
hook lives at `.claude/hooks/workflow_hook.py`, config at `.claude/workflow_config.json`). The agent
operating manual is the `adaptive-workflow` skill
(`.claude/skills/adaptive-workflow/SKILL.md`). Hooks provide ambient reminders — treat them as
helpful nudges, not blockers.

### Fixed invariants — always do first (Phase 0)
- **F1 Git sync:** `git fetch && git pull --rebase`. If the tree is dirty, ask the user how to
  proceed before changing anything.
- **F2 Environment:** verify the tools in `workflow_config.json → env_check` (dart, flutter, python).
- **F3 Living docs:** load configured docs; flag any missing doc frontmatter (provenance + version).
- **F4 Unfinished plan / roadmap:** if `plans/UNFINISHED.md` exists, surface it immediately; note
  the next unchecked roadmap item.
- **F5 Daily workflow update check:** N/A here — the workflow is vendored (no submodule).

### Per-task discipline
- **Plan (Phase 1):** design a task-specific checklist covering tests, doc updates, ledger entries,
  provenance, and roadmap impact.
- **Execute (Phase 2):** implement → run linter/tests → apply conditional triggers. **Log every
  intentional change** to the weekly ledger `history/YYYY-Www.md` (skip only trivial
  typo/whitespace-only edits). Add doc frontmatter (provenance + version) to any new/updated document.
- **Close (Phase 3):** archive the plan, write the final ledger entry, update the roadmap, then
  commit & push. You are **not done** until `UNFINISHED.md` is cleared, the ledger entry is written,
  and the commit is pushed.

<!-- END adaptive-workflow fragment -->

## Project-specific notes

- **Hook tests are stdlib-only.** Run them with `python -m unittest discover -s tests/hook`. They
  live under `tests/hook/` (not the Dart `test/` tree) so `flutter test` doesn't pick them up.
- **Dart tests need no hardware.** Use `MockCameraAdapter` (`test/mock_camera_adapter.dart`);
  CI runs `flutter analyze --fatal-infos` + `flutter test`. Live-hardware smoke tests are
  manual/local via `example/` — a profile-driven multi-tab toolkit (Cameras, Preview, QR, Barcode,
  Gallery, PTZ/Zoom) where ONVIF and EZVIZ are first-class cameras added through setup wizards.
