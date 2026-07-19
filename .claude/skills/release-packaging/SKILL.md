---
name: release-packaging
description: >-
  Use whenever building, packaging, or versioning a distributable artifact from this package —
  publishing the `universal_camera_adapter` pub package, or building the example app's Android APK
  via `scripts/build-apk.ps1`. Trigger whenever the request mentions building an APK, staging into
  `dist/`, `pub publish` / `flutter pub publish`, cutting a release, bumping a version, a CHANGELOG
  entry, SHA256 checksums, code-signing / keystore, `dist/` folder hygiene, or "make this
  release-ready" — even if the word "release" never appears. Encodes: a shipped artifact's filename
  carries a version derived from a `pubspec.yaml` (never hand-typed), bumped on every distributable
  build (never reused — the build script refuses to overwrite an existing versioned file), every
  artifact stays inside the gitignored `dist/`, a `.sha256` sidecar ships alongside each, and each
  version bump has a matching git-tracked CHANGELOG entry. This is the build → version → stage →
  verify pipeline; for class-level design read [[dart-solid-principles]] and for the adapter contract
  itself [[camera-adapter-authoring]].
---

# Release packaging (universal_camera_adapter)

This package has **two distinct distributable surfaces**. They version **independently** — do not
sync their versions:

- **A — the pub package** `universal_camera_adapter` (the real product, shipped to pub.dev).
- **B — the example APK** (`example/`, a local camera-testing toolkit; `publish_to: none`, never
  published — built only for on-device testing).

Keep this skill concrete and true to the repo. If a path below moves, update this skill.

## Surface A — the pub package

- **Version is the root [`pubspec.yaml`](../../../pubspec.yaml) `version:`** (currently `1.0.0`), and
  it follows [Semantic Versioning](https://semver.org): patch for fixes, minor for backward-compatible
  additions (e.g. the v1.1 ONVIF backend), major for breaking contract changes.
- **Every shipped change needs a matching [`CHANGELOG.md`](../../../CHANGELOG.md) entry in the same
  commit as the version bump.** The repo's CHANGELOG is already Keep-a-Changelog style (`### Added` /
  `### Changed` / `### Fixed` / `### Removed`, newest on top). A version bump without a changelog entry
  (or vice-versa) is incomplete.
- **This is a library, so `pubspec.lock` is intentionally *not* committed** — see
  [`.gitignore`](../../../.gitignore). Don't add it back.
- **Publish flow:** `flutter pub publish --dry-run` first (must be clean — expect only the known
  benign `docs`→`doc` convention warnings), then `flutter pub publish`, then tag the commit
  `v<version>` (e.g. `git tag v1.1.0`). `.pubignore` (not `.gitignore`) governs the tarball contents —
  it **replaces** `.gitignore` rather than stacking, so build/dev dirs must be listed there explicitly.

## Surface B — the example APK (full discipline)

Built by [`scripts/build-apk.ps1`](../../../scripts/build-apk.ps1) from `example/`, staged into
`dist/`. The discipline mirrors the pub package but on the **example app's own** version.

1. **Bump `example/pubspec.yaml`'s `version:` before every distributable build** — even a one-off
   local test build (e.g. `1.0.0+1` → `1.0.1+2`). Two different builds must never be able to produce
   the same versioned filename; that's how you (or a future session) can tell which build a given APK
   actually is. The example versions independently of the root package — it has `publish_to: none` and
   its own `version:`.
2. **Add a matching `example/CHANGELOG.md` entry in the same commit** (Keep-a-Changelog style, same
   as the root CHANGELOG). The bump and its entry are not independently valid.
3. **Run the script** from the repo root:
   ```powershell
   scripts/build-apk.ps1                    # debug (default)
   scripts/build-apk.ps1 -Mode release
   scripts/build-apk.ps1 -Mode debug -AllowSameVersion   # deliberate re-stage, no bump
   ```
   It stages, per build, **both**:
   - the **stable name** `dist/universal_camera_adapter-<mode>.apk` (the predictable "latest" pointer
     the `dist/README.md` install commands reference — keep emitting it), and
   - a **versioned copy** `dist/universal_camera_adapter-<version>-<mode>.apk` (traceability),
   each with a `.sha256` sidecar (`Get-FileHash -Algorithm SHA256`). The script **throws if the
   versioned file already exists** — that's the signal you forgot to bump the version. `-AllowSameVersion`
   is the only escape hatch, and only for deliberately re-staging the identical build; never as a
   workaround after a real code change.
4. **Verify `dist/`** holds, per built mode: the stable name, the versioned name matching
   `example/pubspec.yaml`, and a `.sha256` for each.

### `dist/` hygiene

- `dist/*.apk`, `*.aab`, and `*.sha256` are **git-ignored** — only [`dist/README.md`](../../../dist/README.md)
  is tracked. Versioned copies accumulate locally across builds; that's fine (cheap, local-only history
  of what was built). Pruning old copies is manual.
- Keep `dist/README.md`'s file table in sync with what the script stages.
- Never treat `example/build/app/outputs/flutter-apk/app-<mode>.apk` as the delivered copy — stage into
  `dist/` first.

## Signing (Android) — a known gap, verify before claiming otherwise

As read in [`example/android/app/build.gradle.kts`](../../../example/android/app/build.gradle.kts)
(the `release` block): `signingConfig = signingConfigs.getByName("debug")`. **Every `--release` APK
this script produces today is debug-signed, not release-signed** — fine for internal/on-device testing,
but a blocker before any real distribution: debug-signed APKs use a well-known insecure key and can't
receive signed updates safely. Wiring a real `signingConfigs.release` (keystore + a `key.properties`
kept out of git) is a separate, not-yet-done task. **Verify by reading `build.gradle.kts`** before
telling anyone an APK is distribution-ready — don't assume it was fixed.

## Versioning implementation notes (for whoever edits the script)

- Read the version anchored at line start (`^version:\s*(\S+)`) so an indented `version:` inside a
  dependency block is never mistaken for the package's own version.
- If the `pubspec.yaml` is missing or has no top-level `version:`, **throw** — don't stage unversioned.
- Validate against `^\d+\.\d+\.\d+(\+\d+)?$` and throw on mismatch rather than stamping a malformed
  string into a filename. The `+` build-number separator is a valid Windows filename character
  (`1.0.0+1` passes straight through).

## References

- [`pubspec.yaml`](../../../pubspec.yaml) / [`CHANGELOG.md`](../../../CHANGELOG.md) — the pub package's version + changelog.
- [`example/pubspec.yaml`](../../../example/pubspec.yaml) / `example/CHANGELOG.md` — the example APK's independent version + changelog.
- [`scripts/build-apk.ps1`](../../../scripts/build-apk.ps1) — the build → version → stage → checksum pipeline.
- [`dist/README.md`](../../../dist/README.md) — what lands in `dist/` and how to install it.
- [`example/android/app/build.gradle.kts`](../../../example/android/app/build.gradle.kts) — the (currently debug) signing config.
