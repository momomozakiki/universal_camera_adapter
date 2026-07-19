# dist/ — built app binaries

Landing spot for built APKs so they're in one predictable place for fast access.

## What lands here (per build)

`scripts/build-apk.ps1` stages, for each mode it builds:

- **`universal_camera_adapter-<mode>.apk`** — the *stable* "latest" name, overwritten every build.
  This is what install commands below reference.
- **`universal_camera_adapter-<version>-<mode>.apk`** — a *versioned* copy for traceability, where
  `<version>` is `example/pubspec.yaml`'s `version:` (e.g. `1.0.0+1`). Versioned copies accumulate
  across builds so you can tell which build a given APK actually is.
- **`<file>.sha256`** — a checksum sidecar next to each of the above (`Get-FileHash -Algorithm SHA256`).

## How they get here

Run the helper from the repo root; it builds the `example/` app and stages the APKs here:

```powershell
scripts/build-apk.ps1                          # debug (default)
scripts/build-apk.ps1 -Mode release
scripts/build-apk.ps1 -Mode debug -AllowSameVersion   # re-stage same build, no version bump
```

**Bump `example/pubspec.yaml`'s version (and add an `example/CHANGELOG.md` entry) before each
distributable build** — the script *refuses to overwrite* an existing versioned file, which is the
signal you forgot to bump. `-AllowSameVersion` is the only override, for deliberately re-staging the
identical build. See `.claude/skills/release-packaging/SKILL.md`.

## Git & signing notes

- The APK binaries **and** their `.sha256` sidecars are **git-ignored** (large & reproducible) — only
  this README is tracked.
- `release` builds are currently **debug-signed** (`example/android/app/build.gradle.kts`) — fine for
  on-device testing, not for real distribution.

Install with `adb install dist/universal_camera_adapter-debug.apk` or `cd example && flutter install`.
