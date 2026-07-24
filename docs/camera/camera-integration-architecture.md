---
title: Camera Integration Architecture
version: 1.1
last_validated: 2026-07-24
official: true
source: project-internal
tags: [camera, architecture, adapter, registry, onvif]
applies_when: "Editing the CameraAdapter contract, the registry, or any backend."
estimated_tokens: 900
---

# Camera integration architecture

**Version 1.0** — *the hardware-access layer: what ships today, the extension point for tomorrow.*

## Revision History
| Version | Date       | Change   |
|---------|------------|----------|
| 1.0     | 2026-07-18 | Initial. |
| 1.1     | 2026-07-24 | ONVIF connect + RTSP preview now implemented (no longer blanket scaffolding); dependency note corrected; feature-matrix / profiles / wizard / EZVIZ moved from planned to shipped. |

This is the hardware-access layer. For rules on editing it, see the `camera-adapter-authoring`
skill; for the untrusted-network-input lens on the ONVIF path, see `input-hardening`.

## What ships today

`universal_camera_adapter` is a single Flutter package (not pure Dart — a camera preview must expose
a `Widget`) that abstracts camera hardware behind one contract:

- **`CameraAdapter`** (`lib/src/camera_adapter.dart`) — the contract: `listDevices()`, `open(device)`,
  `close()`, `isOpen`, `capabilities`, `buildPreview()`, `captureFrame()`, `setZoom()`, and optional
  `setPan`/`setTilt` (default to `UnsupportedError`). **One adapter instance manages at most one open
  device at a time**: `open()` always closes any previously open device first.
- **`CameraAdapterRegistry`** (`lib/src/camera_adapter_registry.dart`) — instance-based (not a
  singleton), string-keyed factory map: `register(type, factory, {asDefault})`, `create(type)`,
  `createDefault()`. A default exists only if explicitly registered with `asDefault: true`.
- **`FlutterCameraAdapter`** (`lib/src/flutter_camera_adapter.dart`) — the one shipped backend,
  wrapping the federated `camera` plugin (`camera_android` + `camera_windows`). Notable behavior:
  triggers the Android camera-permission prompt inside `open()`; reports zoom capability from the
  controller's *actual* min/max zoom (never assumed); reports `hasPan`/`hasTilt` as `false` (no PTZ
  API); guards `captureFrame()` against a hung native `takePicture()` with a short internal timeout +
  a `_capturing` flag, because a stuck native call can wedge the plugin's own busy flag forever.
- **`CameraCapabilities` / `CameraDevice` / `CameraLensFacing`** (`lib/src/camera_types.dart`) —
  backend-agnostic value types. `CameraLensFacing` is deliberately our own enum, not the plugin's, so
  the contract doesn't force a future non-plugin backend to depend on the `camera` plugin.

Capabilities are always **queried from the opened device**, never hardcoded — e.g.
`FlutterCameraAdapter.open()` reads `getMinZoomLevel()`/`getMaxZoomLevel()` and only reports
`hasZoom: true` if the range is non-trivial.

**Platform support:** Android and Windows. macOS/Linux are not implemented (no
`camera_macos`/`camera_linux` dependency).

## Extension point: adding a backend

The contract anticipates backends beyond the local device camera — a network/IP camera, a PTZ vendor
SDK. Adding one requires **no change to any consumer**:

1. Implement `CameraAdapter` for the new backend.
2. Register it in a `CameraAdapterRegistry` under a new string type — `asDefault: true` only if the
   app should use it by default.
3. Report `capabilities` from whatever the device/SDK actually supports post-connect.
4. Map SDK/network exceptions to the typed surface
   (`StateError`/`UnsupportedError`/`TimeoutException`/`FormatException`).

## ONVIF / IP-camera backend (partially implemented)

`ONVIFCameraAdapter` (`lib/src/onvif/`) registers under `'onvif'` and is **partially implemented and
hardware-verified**:

- **Implemented:** `open()` (WS-UsernameToken PasswordDigest auth with an RFC 2617 HTTP Digest
  fallback → `GetDeviceInformation` → `GetProfiles` → `GetStreamUri`), `close()`, `isOpen`,
  `buildPreview()` (live RTSP via `media_kit`, forced `rtsp-transport=tcp`), and a hand-built
  `featureMatrix`. The service seams `onvif_soap.dart`, `onvif_http_client.dart`,
  `onvif_media_service.dart`, and `rtsp_preview.dart` carry real code plus input-hardening (1 MB
  response cap, ReDoS-guarded Digest parsing, anti-redirect host check, credential redaction).
- **Still `UnimplementedError`:** `listDevices()` (WS-Discovery), `capabilities`, `captureFrame()`
  (snapshot), and PTZ `setZoom`/`setPan`/`setTilt`.

**Dependency note:** the RTSP stack (`media_kit`, `media_kit_video`, `media_kit_libs_video`) and the
SOAP libraries (`http`, `xml`, `crypto`) **are now declared** in `pubspec.yaml`. See
[`onvif-setup-guide.md`](onvif-setup-guide.md) for the network-permission requirements.

## The Golden Rule

Consumers depend only on `CameraAdapter` + `CameraAdapterRegistry`, never a concrete backend; they
check `capabilities` at runtime to drive UI, always pair `open()` with `close()`, and handle the
typed errors. This is what keeps every backend swappable and testable via `MockCameraAdapter`.

## Shipped since v1.0 (not yet released)

The following foundational features are implemented in code (post-1.0, unreleased):

- **Feature matrix** ([`feature-matrix.md`](feature-matrix.md)) — tri-state feature support model
  (`unsupported` / `unvalidated` / `supported`) alongside the flat boolean flags. Adds
  `CameraFeature`, `CameraFeatureStatus`, and `CameraFeatureMatrix` as an additive `featureMatrix`
  getter on `CameraAdapter`; `CameraCapabilities` remains the backward-compatible view.

- **Camera profiles** ([`camera-profiles.md`](camera-profiles.md)) — user-saved camera list with
  secure-storage-backed secrets. `CameraProfile` (backend-agnostic metadata) + `CameraProfileStore`
  (shared preferences, injectable) + `CameraSecretStore` (flutter_secure_storage, injectable), in
  `lib/src/persistence/`. Secrets never persist in plaintext.

- **Modular add-camera wizard** ([`add-camera-wizard.md`](add-camera-wizard.md)) —
  `CameraSetupWizardRegistry` (`lib/src/setup/`) parallel to `CameraAdapterRegistry`, decoupling
  setup UI from backend logic. The example app's Cameras tab renders wizard tiles automatically as
  backends are registered, with zero per-brand branching, and `CameraSession.switchTo()` handles
  camera switching.

- **EzvizCameraAdapter (per-user, native login)** — EZVIZ backend using native SDK-hosted login (not
  bridge-based) with per-user tokens ([`ezviz-setup-guide.md`](ezviz-setup-guide.md)). **Lives in the
  example app (`example/lib/`), not the published `lib/`.** Uses a vendored, patched `ezviz_flutter`
  (4 upstream bugs fixed on real hardware); connect + playback work, frame capture is still a stub.

## Still planned

- **Discovery pipeline** ([`discovery-pipeline.md`](discovery-pipeline.md)) — three-stage staged
  discovery (OS filtering → local hardware → network/cloud probes) with per-stage observable
  status. Enables multi-backend discovery without blocking local results on slow network probes.
  Introduces the optional `NetworkDiscoverable` mixin for backends supporting live-network
  discovery (e.g., ONVIF WS-Discovery). **Not yet implemented** — `CameraDiscoveryPipeline` /
  `NetworkDiscoverable` do not exist and `ONVIFCameraAdapter.listDevices()` still throws.
