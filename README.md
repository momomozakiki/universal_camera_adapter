# Universal Camera Adapter

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

**A modular, pluggable camera abstraction for Flutter** – unify local device cameras (Android,
Windows webcams) and external network/IP cameras (ONVIF/RTSP) behind a single, testable interface.

---

## Overview

`universal_camera_adapter` abstracts camera hardware behind one `CameraAdapter` contract, whether
it's:

- **Built-in phone cameras** (Android via `camera_android`)
- **Laptop webcams** (Windows via `camera_windows`, using the federated `camera` plugin)
- **External network/IP cameras** (ONVIF/RTSP — *planned, v1.1*)

It uses the **Adapter Pattern** + **Registry Pattern** so consumers code against the interface, not
concrete backends.

> **Platform support today:** Android and Windows are fully supported. macOS and Linux are not
> implemented. The ONVIF/IP-camera backend is currently **scaffolding** (see the [Roadmap](#roadmap)).

## Architecture

```mermaid
flowchart TD
    App["Consuming application"]
    subgraph Package["universal_camera_adapter"]
        Interface["CameraAdapter (abstract contract)"]
        Registry["CameraAdapterRegistry (instance-based factory)"]
        Flutter["FlutterCameraAdapter (Android / Windows)"]
        ONVIF["ONVIFCameraAdapter (network / IP — planned)"]
    end
    App -->|depends on| Interface
    App -->|creates via| Registry
    Registry -->|returns| Interface
    Interface --- Flutter
    Interface --- ONVIF
```

## Core design principles

1. **Interface-first** — consumers code against `CameraAdapter`, never a concrete backend.
2. **Capabilities are queried at runtime** — never assume PTZ/zoom/focus; ask the adapter *after* `open()`.
3. **Lazy initialisation** — backends touch their SDK/plugin only inside `open()`.
4. **Map, don't leak** — backend exceptions map to a small typed surface
   (`StateError`, `UnsupportedError`, `TimeoutException`, `FormatException`).
5. **One active device per instance** — `open()` auto-`close()`s the previous device.
6. **Explicit timeouts** — every network-bound method accepts an optional `Duration timeout` (default 15s).

## The contract

```dart
abstract class CameraAdapter {
  Future<List<CameraDevice>> listDevices();

  Future<void> open(CameraDevice device, {Duration timeout});
  Future<void> close();
  bool get isOpen;

  CameraCapabilities get capabilities;         // throws StateError if not open

  Widget buildPreview();                        // throws StateError if not open
  Future<Uint8List> captureFrame({Duration timeout});

  Future<void> setZoom(double factor, {Duration timeout});
  Future<void> setPan(double angle, {Duration timeout});   // UnsupportedError if no PTZ
  Future<void> setTilt(double angle, {Duration timeout});  // UnsupportedError if no PTZ
}
```

`captureFrame()` returns raw image bytes (usually JPEG). `buildPreview()` returns a live-feed
widget — **the consumer must call `close()`** (e.g. in `dispose()`) to release resources.

## Registry (pluggable backends)

The `CameraAdapterRegistry` is **instance-based** (not a singleton), so each app or test builds its
own isolated registry.

```dart
void main() {
  final registry = CameraAdapterRegistry();
  registry.register('builtin', FlutterCameraAdapter.new, asDefault: true);
  // Future: registry.register('onvif', ONVIFCameraAdapter.new);
  runApp(MyApp(registry: registry));
}

// In a widget/controller:
final adapter = registry.hasDefault() ? registry.createDefault() : registry.create('builtin');
```

## Error handling (the typed surface)

| Backend condition | Mapped Dart error |
| :--- | :--- |
| Device disconnected / open or capture failure / permission denied | `StateError` |
| Feature not supported by hardware | `UnsupportedError` |
| Timeout / network failure | `TimeoutException` |
| Invalid SOAP response / malformed XML | `FormatException` |

```dart
try {
  await adapter.open(device);
} on StateError catch (e) {
  showUserMessage('Camera error: ${e.message}');
} on TimeoutException catch (_) {
  showUserMessage('Camera took too long to respond.');
} on UnsupportedError catch (_) {
  // Feature not available — hide the control.
}
```

## The Golden Rule for consumers

> **Never import a concrete adapter in your UI or business logic. Always go through
> `CameraAdapterRegistry` and always check `capabilities` at runtime.**

1. **Depend on the interface** — `CameraAdapter`, not `FlutterCameraAdapter`.
2. **Capabilities drive the UI** — query `capabilities` after `open()`; show/hide controls dynamically.
3. **Lifecycle is strict** — always pair `open()` with `close()`.
4. **Errors are expected** — handle `StateError`, `UnsupportedError`, `TimeoutException`.

## Testing

Use the provided `MockCameraAdapter` (in `test/`) to simulate every return type and exception, so
you can test business logic without hardware. Run:

```bash
flutter test
```

No live-hardware tests run in CI. Integration against a real Android device or Windows webcam is
manual — see [`example/`](example/).

## Backends

| Backend | Purpose | Platforms | Status |
| :--- | :--- | :--- | :--- |
| **FlutterCameraAdapter** | Local cameras (phone, webcam) via the `camera` plugin | Android, Windows | **Production-ready** |
| **ONVIFCameraAdapter** | External IP cameras via ONVIF/RTSP | Cross-platform (network) | **Planned (v1.1)** — scaffolding registers under `'onvif'` and throws `UnimplementedError` |

See [`docs/camera/camera-integration-architecture.md`](docs/camera/camera-integration-architecture.md)
for the full architecture and the [ONVIF setup guide](docs/camera/onvif-setup-guide.md) for the
planned network-permission requirements.

## Roadmap

- **v1.0** — core interface, registry, `FlutterCameraAdapter`, mock, tests, CI. *(this release)*
- **v1.1** — `ONVIFCameraAdapter`: Media/PTZ/snapshot, RTSP preview, WS-Discovery.
- **v1.2** — two-way audio (intercom) for ONVIF.
- **v1.3** — motion/event streams (ONVIF events).
- **v2.0** — macOS/Linux via `camera_macos` / `camera_linux`, if demand arises.

Tracked in [`docs/plan/ROADMAP.md`](docs/plan/ROADMAP.md).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [SECURITY.md](SECURITY.md). New backends must implement
the `CameraAdapter` contract, map exceptions to the typed surface, and ship with mock-based unit
tests.

## License

MIT — see [LICENSE](LICENSE).
