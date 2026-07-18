# dist/ — built app binaries

Landing spot for built APKs so they're in one predictable place for fast access.

- **`universal_camera_adapter-debug.apk`** — latest debug build of the `example/` app.
- **`universal_camera_adapter-release.apk`** — latest release build (when built).

## How they get here

Run the helper from the repo root; it builds the `example/` app and copies the APK here
(overwriting the same-mode file, so the path stays stable):

```powershell
scripts/build-apk.ps1              # debug (default)
scripts/build-apk.ps1 -Mode release
```

The APK binaries themselves are **git-ignored** (they're large and reproducible) — only this README
is tracked. Install with `adb install dist/universal_camera_adapter-debug.apk` or
`cd example && flutter install`.
