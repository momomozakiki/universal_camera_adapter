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
