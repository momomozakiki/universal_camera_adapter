# Contributing to `universal_camera_adapter`

We welcome contributions! This package follows the
[Adaptive Self-Correcting Workflow](https://github.com/momomozakiki/ai-self-correcting-workflow)
(vendored under `.claude/`) — read `CLAUDE.md` and the `adaptive-workflow` skill before starting.

## How to contribute

1. **Fork** and create a feature branch (`feat/<desc>` or `fix/<desc>`).
2. **Load the governing skill** for the area you're touching (see `.claude/skills/`):
   `camera-adapter-authoring` for backends/contract, `dart-solid-principles` for structure,
   `input-hardening` for any ONVIF/network parsing.
3. **Write tests** for new functionality or bug fixes — unit tests with `MockCameraAdapter`
   (`test/mock_camera_adapter.dart`) are required for all new logic. No live hardware in CI.
4. **Ensure all tests pass:** `flutter test`. Hook tests: `python -m unittest discover -s tests/hook`.
5. **Run the analyzer:** `flutter analyze --fatal-infos` and fix all warnings. `dart format .`.
6. **Update docs** (README and `docs/**`) for any public API change, with provenance frontmatter per
   [`docs/DOC-PROVENANCE.md`](docs/DOC-PROVENANCE.md).
7. **Log the change** in the weekly ledger `history/YYYY-Www.md` (see `history/FORMAT.md`).
8. **Open a pull request** against `main` with a clear description.

## Code style

- Follow the [official Dart style guide](https://dart.dev/guides/language/effective-dart) and
  `dart format`.
- Prefer explicit typing where the type is not obvious.

## Principles for new backends

Every new camera source is a `CameraAdapter` implementation — never a fork of a consumer or a
separate service. Per `camera-adapter-authoring`:

- Implement the `CameraAdapter` contract; register it via `CameraAdapterRegistry.register(type,
  factory, {asDefault})`.
- One device open at a time (`open()` closes any previous device first).
- Query `capabilities` from the opened device — never assume `hasZoom`/`hasPan`/`hasTilt`.
- Lazy acquisition — touch the plugin/SDK/socket only inside `open()`.
- Map all platform/SDK/network exceptions to the typed surface
  (`StateError`/`UnsupportedError`/`TimeoutException`/`FormatException`).
- All network-bound methods take an optional `Duration timeout`.
- For any ONVIF/RTSP/network parsing, apply the `input-hardening` rules (size caps, no bare casts,
  ReDoS-safe regex, no secrets in code) — see `SECURITY.md`.

## Reporting issues

Use the GitHub issue tracker; provide a minimal reproducible example where possible.
