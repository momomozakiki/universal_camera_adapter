---
title: Camera Discovery Pipeline
version: 1.0
last_validated: 2026-07-22
official: false
source: project-internal
tags: [discovery, pipeline, onvif, ezviz, architecture]
applies_when: "Implementing or extending multi-backend discovery (local → external → cloud)."
---

# Camera discovery pipeline

**Version 1.0** — *three-stage observation: OS → local hardware → external/network.*

> **Status: design spec, not implemented.** Unlike its three sibling Epic 2.5 specs, nothing here has
> been built. `CameraDiscoveryPipeline` and `NetworkDiscoverable` do not exist, and
> `ONVIFCameraAdapter.listDevices()` still throws `UnimplementedError` — WS-Discovery was
> deliberately deferred out of the Epic 2.5 slice, with manual "add by IP" covering ONVIF instead
> (see `docs/plan/ROADMAP.md`). This file therefore stays `official: false`: it describes an intended
> design, not shipped behaviour. Two consequences are already load-bearing elsewhere: profile
> re-validation is **two-mode** (a backend that cannot enumerate is validated by `open()` instead,
> detected by catching `UnimplementedError` rather than by naming the backend), and the Cameras tab
> shows saved profiles only — there is no live-discovery list to merge with them yet.

## Revision History
| Version | Date       | Change   |
|---------|------------|----------|
| 1.0     | 2026-07-22 | Initial. |
| 1.0a    | 2026-07-23 | No design change. Added the status banner above recording that this spec remains unimplemented after Epic 2.5, and the two places the deferral is already visible in shipped code. |

## Problem

`CameraAdapter.listDevices()` works well for a single backend at a time, but with multiple
coexisting backends (local device camera, ONVIF/RTSP, EZVIZ cloud, future), discovery needs to be
staged and observable:

- **Local device enumeration** (Stage 1) must never block on a slow network probe.
- **Network discovery** (Stage 2a, e.g. WS-Discovery UDP multicast) is inherently "wait up to N
  seconds for replies" — not an instant list, so it should run in parallel with/after Stage 1.
- **Cloud discovery** (Stage 2b, e.g. EZVIZ's account device list) depends on prior login — should
  surface "not connected" with an affordance to log in if the user hasn't authenticated yet.
- **Backend availability** varies by platform — a Windows app has no `ezviz_flutter` plugin, so
  probing for EZVIZ cameras would be pointless.

A naive "call `listDevices()` on each adapter" approach conflates these concerns. The discovery
pipeline separates them.

## Three-stage design

### Stage 0: OS/platform filtering

Determine the current platform (`Platform.isAndroid`, `kIsWeb`, `defaultTargetPlatform`, etc.) at
the app composition layer. Each registered backend declares its `supportedPlatforms` (e.g.
`['android', 'ios']` for EZVIZ, `['android', 'windows', 'ios', 'macos']` for the local `flutter`
backend). Filter the registry to only backends eligible on this platform.

**Output:** a subset of registered types eligible for discovery.

### Stage 1: Built-in device camera discovery

For each eligible **local** backend type (today: `builtin`), call `listDevices()`. This is assumed
fast—no network round trip, just device enumeration—and results should reach the UI immediately.

**Output:** list of `CameraDevice` objects (local cameras), or empty if none present.

**Observable status:** `pending` (not started) → `inProgress` (enumerating) → `done` (finished).

### Stage 2: External / Network / Cloud discovery

Run after Stage 1 completes (or in parallel, but report results only after Stage 1 is done, so a
slow probe never blocks local results from reaching the UI first).

#### Stage 2a: Live network probe (ONVIF WS-Discovery)

Some backends (like ONVIF cameras) support optional live-network discovery via UDP multicast or
similar probes. Rather than hardcoding this as a new required method on `CameraAdapter`, expose it
via an optional mixin:

```dart
mixin NetworkDiscoverable {
  /// Discover devices on the local network with a bounded timeout.
  Future<List<CameraDevice>> discover({Duration timeout = const Duration(seconds: 5)});
}
```

An ONVIF adapter implements this; a local `FlutterCameraAdapter` does not. The pipeline checks
`adapter is NetworkDiscoverable` before attempting a discovery call.

**Output:** list of discovered devices, or empty if the timeout expires before replies arrive.

**Observable status:** `pending` → `inProgress` → `done` (timeout expired, or replies received).

**Note:** WS-Discovery is best-effort. Devices may not answer, firewalls may block UDP 3702, and
an empty result does not mean no cameras exist on the network — a manual "add by IP" path is
always required.

#### Stage 2b: Account-bound cloud list (EZVIZ)

For backends requiring authentication (like EZVIZ), the cloud device list is gated on login state:

- **If the user is logged in:** call the backend's account API (e.g. EZVIZ's `device/list`) and
  return the user's devices.
- **If the user is not logged in:** don't attempt a call. Instead, report the stage as `unavailable`
  with a reason message, and surface an affordance (e.g. "Add EZVIZ account") so the user can
  initiate login.

**Output:** list of user's cloud-stored cameras, or empty/unavailable if not authenticated.

**Observable status:** `unavailable(reason: "not logged in")` / `inProgress` / `done`.

## Implementation: `CameraDiscoveryPipeline`

Location: `lib/src/discovery/camera_discovery_pipeline.dart` (new package-level type, not app-specific).

### Constructor and inputs

```dart
class CameraDiscoveryPipeline {
  CameraDiscoveryPipeline({
    required CameraAdapterRegistry registry,
    required List<(String type, List<String> supportedPlatforms)> backendDeclarations,
  });
}
```

- `registry` — the source of adapter instances.
- `backendDeclarations` — additive: `('onvif', ['android', 'windows', 'ios', 'macos'])`, etc. —
  allows the app to declare platform support per backend without hardcoding it in the package.

### Outputs: incremental results + per-stage status

Rather than one big `Future<List<CameraDevice>>`, the pipeline reports incrementally:

```dart
/// Starts discovery. Yields partial results as each stage completes.
Stream<DiscoveryResult> discover();
```

```dart
@immutable
class DiscoveryResult {
  /// Logical stage: Stage1BuiltIn, Stage2a_NetworkDiscovery, Stage2b_CloudList, etc.
  final String stage;
  
  /// Current status: pending, inProgress, done, or unavailable(reason).
  final DiscoveryStatus status;
  
  /// Devices found so far in this stage. Empty if status != done.
  final List<CameraDevice> devices;
  
  /// Optional reason (e.g. "not logged in").
  final String? reason;
}

enum DiscoveryStatus { pending, inProgress, done, unavailable }
```

### Consumer (example app Cameras tab)

The Cameras tab listens to the stream and renders results grouped by stage as they arrive:

```
This device (Stage 1)
  📷 Back Camera
  📷 Front Camera

Network cameras found (Stage 2a)
  [spinning] Searching via WS-Discovery...

Your EZVIZ cameras (Stage 2b)
  [card] Log in to see your cameras | Add account
  — or —
  📷 Driveway Cam
  📷 Garage Cam
```

As results arrive, each stage's UI updates without blocking the others.

## Relationship to the registry and existing backends

The pipeline is **purely a composition** of the existing `CameraAdapter.listDevices()` method plus
the `CameraAdapterRegistry`. It does not change the contract — `FlutterCameraAdapter` and
`ONVIFCameraAdapter` need no modification to work with it. Future backends register normally
via `registry.register()`, declare their `supportedPlatforms`, and optionally implement
`NetworkDiscoverable` if they support live probing. The pipeline picks them up automatically.

## Cross-backend sorting / prioritization

The pipeline returns devices grouped by stage/type but does not impose a hard "list all local
devices first, then all EZVIZ cameras." If the app wants to show "recommended: your default
camera" or "recently used," that's a Cameras tab concern (see [`camera-profiles.md`](camera-profiles.md)),
not the pipeline's responsibility.

## Risks and open questions

- **WS-Discovery unreliability** — empirically observed to not work on some networks/devices (see
  [`ezviz-integration-notes.md`](ezviz-integration-notes.md)). Stage 2a results are best-effort;
  a "manual add by IP" path is always required.
- **Rate limiting on Stage 2b** — EZVIZ's `device/list` is rate-limited per AppKey. The Cameras
  tab should cache results with a short TTL and refetch only on explicit user refresh, not on
  every app resume.
- **Timeout tuning** — a 5-second WS-Discovery timeout is a guess; real networks may need 10–30
  seconds. Left configurable per call, not hardcoded.
