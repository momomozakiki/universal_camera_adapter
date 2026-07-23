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

## `env_check.tool_paths` stays bare names — the hook resolves Windows `.bat` shims itself

**Keep `env_check.tool_paths` entries as bare names** (`dart`, `flutter`, `python`). Do **not** pin
absolute paths: those are machine-specific, and a stale one from another dev box makes Phase 0 report
NOT FOUND on every other machine.

**Root cause of the old NOT FOUND:** the SessionStart hook invokes tools via `subprocess` with
`shell=False`. On Windows the Dart/Flutter entry points are `.bat` shims (here under puro), and
`CreateProcess` only ever appends `.exe` when searching `PATH` — never `PATHEXT` — so a bare
`flutter` raised `FileNotFoundError`. `python` passed only because it is a genuine `.exe`.

**Fix (in `run_env_checks`):** resolve the name through `shutil.which` first — it honours `PATHEXT`
and returns e.g. `...\flutter.BAT` — then exec that resolved path. A fully-resolved `.bat` runs fine
under `shell=False`; it does *not* raise `ERROR_BAD_EXE_FORMAT (193)`, because CPython's `subprocess`
does not set `lpApplicationName`. No `cmd /c` prefix is needed.

**`shell=True` was considered and rejected.** It would re-introduce cmd quoting/escaping over a
config-supplied string, and it breaks the missing-tool branch: `cmd /c` exits 1 with "is not
recognized" instead of raising, so an absent tool would be reported with a garbage version line
rather than NOT FOUND.

The same call decodes as UTF-8 with `errors="replace"` — Flutter emits UTF-8, and the default
cp1252 decode mangled the `•` separators in the Phase 0 banner.

## Python hook tests live in `tests/hook/`, not `test/`

The Dart `test/` tree is picked up by `flutter test`; the stdlib-only workflow-hook tests are kept in
`tests/hook/` (plural) so Flutter's runner ignores them. Run them separately:
`python -m unittest discover -s tests/hook`. `tests/` is excluded from the pub tarball via `.pubignore`.
