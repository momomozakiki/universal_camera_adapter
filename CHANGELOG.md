# Changelog

All notable changes to this package are documented here. This project adheres to
[Semantic Versioning](https://semver.org).

## 1.0.0

Initial release — core contract and the local-device backend.

### Added
- **`CameraAdapter`** contract: `listDevices`, `open`/`close`/`isOpen`, `capabilities`,
  `buildPreview`, `captureFrame`, and optional `setZoom`/`setPan`/`setTilt`. All network-bound
  methods take an optional `Duration timeout` (default 15s).
- **`CameraAdapterRegistry`** — instance-based, string-keyed factory registry with an optional
  default backend.
- **Value types** — `CameraDevice`, `CameraCapabilities`, `CameraLensFacing` (backend-agnostic).
- **`FlutterCameraAdapter`** — production backend for Android and Windows via the federated
  `camera` plugin; zoom capability queried from the device, `captureFrame` guarded against a hung
  native call.
- **`ONVIFCameraAdapter`** — scaffolding for the planned network/IP-camera backend (registers under
  `'onvif'`, throws `UnimplementedError` pending v1.1). No heavy dependencies pulled in yet.
- **`MockCameraAdapter`** (in `test/`) for consumer unit tests.
- Example app, CI (analyze + test), and documentation.

### Not yet supported
- ONVIF/RTSP live implementation (planned v1.1), audio (v1.2), events (v1.3), macOS/Linux (v2.0).
