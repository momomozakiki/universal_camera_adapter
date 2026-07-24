# Changelog

All notable changes to this package are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to
[Semantic Versioning](https://semver.org).

## [Unreleased]

Post-1.0 work that has landed in code but is not yet cut as a release. `pubspec.yaml` remains at
`1.0.0` — the ONVIF v1.1 milestone is only partially complete (PTZ, snapshot, and WS-Discovery are
still pending), so no version has been bumped.

### Added
- **`ONVIFCameraAdapter` — authenticated connect + live RTSP preview** (hardware-verified). `open()`
  performs WS-UsernameToken (PasswordDigest) auth with an RFC 2617 HTTP Digest fallback,
  `GetDeviceInformation` → `GetProfiles` → `GetStreamUri`, then opens a live RTSP preview via
  `media_kit` (forced `rtsp-transport=tcp`). `close()`/`isOpen`/`buildPreview()` implemented, with a
  hand-built `featureMatrix`. Input-hardened: 1 MB response cap, ReDoS-guarded Digest parsing,
  anti-redirect host check on the returned stream URI, credential redaction in errors.
- **`featureMatrix` getter on `CameraAdapter`** — tri-state (`supported` / `unvalidated` /
  `unsupported`) capability discovery, with a default derivation from `CameraCapabilities`.
- **Saved-camera profiles** — `CameraProfile` (backend-agnostic metadata) + `CameraProfileStore`
  (`shared_preferences`) + `CameraSecretStore` (`flutter_secure_storage`), so credentials never
  persist in plaintext.
- **Modular add-camera wizard** — `CameraSetupWizardRegistry` parallel to `CameraAdapterRegistry`,
  letting the example app render setup UI per registered backend with no per-brand branching.
- **EZVIZ example backend** (in `example/lib/`, not the published `lib/`) — native SDK-hosted
  per-user login with per-user tokens; connect + playback work, frame capture is still a stub.

### Changed
- **`pubspec.yaml` now declares the ONVIF/RTSP stack** — `http`, `xml`, `crypto`, `media_kit`,
  `media_kit_video`, `media_kit_libs_video` — plus persistence deps `shared_preferences` and
  `flutter_secure_storage`. (Previously the ONVIF backend was dependency-free scaffolding.)
- Windows webcam support now requires an explicit `camera_windows` dependency (not endorsed
  transitively by `camera 0.12.0`).

### Still planned
- ONVIF WS-Discovery (`listDevices`), `capabilities`, snapshot capture (`captureFrame`), and PTZ
  (`setZoom`/`setPan`/`setTilt`) — these still throw `UnimplementedError`.

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
