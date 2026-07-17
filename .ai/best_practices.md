# Best practices & gotchas

Project-specific patterns and traps discovered during development. Append as you find them (per the
`adaptive-workflow` "new pattern/rule/gotcha" trigger).

## `.pubignore` replaces `.gitignore` — it does not stack

When a `.pubignore` file exists, `flutter pub publish` uses it **instead of** `.gitignore` for that
directory — the two do not combine. If you add a `.pubignore` to exclude dev tooling, you must also
repeat the build-artifact entries (`build/`, `.dart_tool/`, `coverage/`, `pubspec.lock`, …), or those
artifacts get re-included in the published tarball.

**Symptom:** `flutter pub publish --dry-run` reports a multi-MB archive (e.g. 14 MB) after adding a
`.pubignore`; the file tree shows `build/` included even though it's in `.gitignore`.

**Fix:** mirror the `.gitignore` build-artifact lines into `.pubignore`. See this repo's
`.pubignore` header comment. (Verified: 14 MB → 20 KB once `build/`/`.dart_tool/` were re-added.)

## Windows `.bat` tool shims need full paths in `workflow_config.json → env_check`

The SessionStart hook invokes tools via `subprocess` without a shell, so on Windows a bare `dart`/
`flutter` (which are `.bat` shims, here under puro) resolves to NOT FOUND. Pin the absolute
`...\dart.bat` / `...\flutter.bat` path in `env_check.tool_paths`. These paths are machine-specific
(that's inherent to env_check) and live only in dev tooling, never shipped to pub.dev.

## Python hook tests live in `tests/hook/`, not `test/`

The Dart `test/` tree is picked up by `flutter test`; the stdlib-only workflow-hook tests are kept in
`tests/hook/` (plural) so Flutter's runner ignores them. Run them separately:
`python -m unittest discover -s tests/hook`. `tests/` is excluded from the pub tarball via `.pubignore`.
