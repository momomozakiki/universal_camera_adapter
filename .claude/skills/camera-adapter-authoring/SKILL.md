---
name: camera-adapter-authoring
description: >-
  Use when editing the `CameraAdapter` contract, the registry, or a concrete backend in this
  package — the shipped `FlutterCameraAdapter`, the planned `ONVIFCameraAdapter`, a PTZ SDK, a
  network/IP camera, or any camera hardware source. Trigger whenever a request mentions the
  `CameraAdapter` contract, `CameraAdapterRegistry`, camera capabilities/zoom/pan/tilt, "add a
  camera backend", PTZ, ONVIF, RTSP, WS-Discovery, snapshot/GetStreamUri, network/IP camera
  integration, or touches `camera_adapter.dart` / `camera_adapter_registry.dart` /
  `flutter_camera_adapter.dart` / anything under `lib/src/onvif/` — even if the word "adapter"
  isn't used. This is the *hardware-access layer*. For untrusted network parsing (SOAP/XML/RTSP)
  reach for [[input-hardening]] as the security lens; for the design *why* behind registry/factory
  and interface segregation, read [[dart-solid-principles]].
---

# Authoring a `CameraAdapter` backend

`universal_camera_adapter` is a single Flutter package that abstracts camera hardware behind one
contract. It is a Flutter package (not pure Dart) because a camera preview must expose a `Widget`.
See [`docs/camera/camera-integration-architecture.md`](../../../docs/camera/camera-integration-architecture.md)
for the full picture. This skill is the concrete checklist for touching that layer. The **why**
behind registry/factory and interface-segregation choices lives in [[dart-solid-principles]] —
read it for the principles; don't restate them here.

## The `CameraAdapter` contract (the part people get wrong)

### 1. One device open at a time
`open(device)` must `close()` any previously open device first — never leave two devices open
under one adapter instance. `FlutterCameraAdapter.open()` does this today; any new backend must
match it.

### 2. Capabilities are queried, never assumed
Query the real device/SDK state **after** a successful open and report it through
`CameraCapabilities` — e.g. `FlutterCameraAdapter` calls `getMinZoomLevel()`/`getMaxZoomLevel()`
rather than hardcoding `hasZoom: true`. A capability the backend can't report comes back `false`,
not an optimistic guess. This applies to `hasPan`/`hasTilt` too: only report `true` once the
backend actually implements `setPan`/`setTilt` — don't flip the flag ahead of the implementation.
Reading `capabilities` before `open()` throws `StateError`.

### 3. Lazy acquisition
Touch the backend's own plugin/SDK/socket only inside `open()`, not in the constructor — mirrors
`FlutterCameraAdapter` requesting Android camera permission inside `open()`, and (for ONVIF) means
no network connection until `open()`. Construction/registration must stay cheap and
side-effect-free even for a device that's never opened.

### 4. Map backend exceptions to the typed surface
`CameraAdapter` communicates failure through a small typed error surface — never leak a raw
platform/SDK/socket exception through the contract into a consumer widget:

| Backend condition | Mapped Dart error |
|-------------------|-------------------|
| Device disconnected / open or capture failure / permission denied | `StateError` (user-facing message) |
| Feature not supported by hardware (e.g. PTZ on a fixed lens) | `UnsupportedError` |
| Timeout / network failure | `TimeoutException` |
| Invalid SOAP response / malformed XML | `FormatException` (wrapped, with context) |

Every network-bound method (`open`, `captureFrame`, `setZoom`, `setPan`, `setTilt`) takes an
optional `Duration timeout` (default 15s) — honor it.

### 5. Register through `CameraAdapterRegistry`, not ad hoc wiring
New backends register under a new string type via `CameraAdapterRegistry.register(type, factory,
{asDefault})`. The registry is **instance-based, not a singleton** — each app/test builds its own.
`asDefault: true` only when the app should genuinely prefer this backend by default — registering
is never implicitly "first one wins".

### 6. Features are queried, never embedded

A camera *feature* (zoom, pan/tilt, QR, barcode, OCR, two-way audio — anything camera-facing, now or
future) is consumer/app-level code that asks an adapter "can you do X?" and degrades to "not
supported" when the answer is no. It is **never** adapter-embedded feature logic, and **never**
camera-type-branched. This is the [[dart-solid-principles]] Open/Closed + Interface-Segregation rules
made concrete for features: a new feature must not force an edit to the contract or to every backend.

The reference-correct example already in the tree: QR/barcode scanning
(`example/lib/scanning/frame_scanner.dart`) is built entirely on the generic `captureFrame()`
contract method. It never touches adapter internals and never branches per backend — any adapter that
can capture a frame gets scanning for free.

Two failure directions, **both forbidden**:

- **Adapter-embedded feature logic** — a concrete adapter file (`flutter_camera_adapter.dart`,
  anything under `lib/src/onvif/`, an EZVIZ adapter) grows a method or field that exists only to
  serve one named feature (e.g. a `decodeBarcode()` method, a `qrOverlayColor` field) instead of a
  generic capability primitive (`captureFrame()`) the feature builds on.
- **Feature-code camera-type branching** — feature code does `if (adapter is ONVIFCameraAdapter)`, a
  `switch` on the registry type string, or a backend-name compare to special-case behavior per
  backend, instead of querying `capabilities` (today) / `featureMatrix` (once Epic 2.5 lands).

**Diff checklist:**

- Does this diff add or change a feature (QR, PTZ, OCR, anything camera-facing)? If yes: does it touch
  any file under `lib/src/*_adapter.dart`, `lib/src/onvif/`, or a concrete adapter in `example/`? If
  yes, **stop** — that's the wrong layer. Feature logic belongs in consumer/example code built on the
  generic primitives (`captureFrame`, `capabilities`/`featureMatrix`). If the primitive it needs is
  missing, that's a *contract* change to discuss first — not a feature-specific method bolted onto one
  backend.
- Does this diff add a camera-type check (`is SomeCameraAdapter`, a `switch` on registry type, a
  backend-name string compare) inside feature code (anything outside `lib/src/*_adapter.dart` and
  `lib/src/onvif/`)? If yes, **stop** — replace it with a capability / feature-matrix query.

### 7. Setup/connection state flows through a generic mechanism, never a one-off store

Camera *selection/setup* is legitimately camera-type-specific: a built-in camera is auto-detected and
needs no setup; ONVIF needs host/port/username/password; EZVIZ needs an account + verification code.
That per-type UI and per-type field set is expected — it does **not** have to be identical across
adapters. What must be generic is *where the resulting state lives and how it is persisted*: one
mechanism every setup flow writes through (`CameraSession` today; `CameraProfile`/`CameraProfileStore`
once Epic 2.5 lands), **not** a fresh `SharedPreferences` key namespace invented per camera type.

`example/lib/onvif/onvif_connect_view.dart` is today's counter-example, and is explicitly documented
in that file as a deliberate, temporary exception — `ONVIFCameraAdapter.credentials` is a `final`
constructor-only field, so its setup state can't yet flow through `CameraSession`. It is **not** a
pattern to copy for the next camera type. See [[state-management]] Rule 6 for the persistence side.

**Diff checklist:**

- Does this diff add a new persisted setup/credential field for a camera type (host, port, token,
  verification code, serial number)? If yes: does it write through `CameraSession` / the generic
  profile mechanism, or does it call `SharedPreferences`/secure storage directly with a bespoke key?
  If the latter, **stop** and flag it — cite [[state-management]] Rule 6.
- Does this diff make a concrete adapter's credentials/config `final`-constructor-only in a way that
  *forces* a caller around `CameraSession`/the registry to persist and re-supply them out-of-band (as
  `ONVIFCameraAdapter` does today)? If yes, that's a structural smell worth a ROADMAP note even if not
  fixed in this diff — an adapter's setup fields should be settable/updatable through the same
  `open(device)` path every other adapter uses.

## Package placement (single-package layout)

Backends live under `lib/src/` — the shipped one directly (`lib/src/flutter_camera_adapter.dart`),
a networked one in its own subfolder (`lib/src/onvif/`). Two dependency rules:

- **Keep heavy/optional backend dependencies out of the critical path.** A backend that needs a
  large plugin (e.g. `media_kit` for RTSP) must not make every consumer of the local-camera path
  pull it in unnecessarily — isolate it and document the dependency in that backend's setup guide.
- **Never bolt a backend onto a consumer** or hardcode a concrete adapter in UI/business logic.
  Consumers depend on the `CameraAdapter` interface + `CameraAdapterRegistry` only (the Golden
  Rule), so a backend stays swappable.

## Networked backends (ONVIF / RTSP / PTZ) — in scope, with a security lens

Unlike the origin repo, networked IP cameras **are in scope** here (`ONVIFCameraAdapter`, ROADMAP
v1.1). When implementing any of SOAP auth, XML parsing, RTSP negotiation, snapshot download, or
WS-Discovery, treat every byte off the wire as untrusted and apply [[input-hardening]]:

- Size-cap SOAP/HTTP responses before parsing; reject oversized frames.
- No bare `as` casts on parsed XML — validate the shape, then read; wrap malformed input in
  `FormatException` with context.
- Any regex over device/network text gets a length cap **and** a time budget (ReDoS-safe).
- Recoverable problems degrade gracefully; unrecoverable ones map to the typed surface above.
- RTSP prefers TCP transport (avoid UDP packet loss); the preview player is created in `open()`
  and disposed in `close()` — the consumer **must** call `close()`.

A networked backend is still a plain `CameraAdapter` implementation following rules 1–5 above —
not a separate service. Adding one requires **no change** to any consumer.

## References

- `lib/src/camera_adapter.dart` — the contract.
- `lib/src/camera_adapter_registry.dart` — the instance-based registry.
- `lib/src/flutter_camera_adapter.dart` — the shipped backend; reference implementation for rules 1–5.
- `lib/src/onvif/` — the planned networked backend (scaffolding today).
- `test/mock_camera_adapter.dart` — the mock consumers unit-test against; keep it contract-faithful.
- [`docs/camera/camera-integration-architecture.md`](../../../docs/camera/camera-integration-architecture.md)
  — full architecture and the extension point.
- [[input-hardening]] — the untrusted-input rules for the ONVIF/RTSP path.
- [[dart-solid-principles]] — interface segregation for the `setPan`/`setTilt` default-throw
  pattern, and the registry/factory rationale.
