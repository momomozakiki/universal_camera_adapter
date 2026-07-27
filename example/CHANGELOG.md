# Changelog — example app

Tracks the `universal_camera_adapter_example` test-harness app, versioned independently of the
root package. This app is never published (`publish_to: none`); its version exists to name the
APKs staged into `dist/` by `scripts/build-apk.ps1`. Keep-a-Changelog style; newest on top.

## [1.0.1+2] - 2026-07-27

### Fixed
- Rebuilt for on-device Android testing of the rename-dialog `_dependents.isEmpty` crash fix and
  the EZVIZ preview builder `KeyedSubtree` parity fix.

## [1.0.0+1] - 2026-07-19

### Added
- Initial tracked version for the example camera-testing toolkit APK. Establishes the
  version-per-distributable-build discipline (versioned `dist/` copies + `.sha256` sidecars).
