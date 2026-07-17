# Change-History Ledger — Format

A weekly, chronological record of every **intentional** change to the project.
It is **not** a verbatim copy of `git log` — it captures what a reviewer would
care about, with the *why*.

## Files & rotation
- One file per ISO week: `history/YYYY-Www.md` (e.g. `history/2026-W28.md`).
- Create the file on the first qualifying change of the week.

## What to log
Log every intentional change with a purpose: feature work, bug fixes,
refactoring, documentation updates, configuration changes, important decisions.

**Do not log:** single-character typo fixes in comments, whitespace-only
changes, or trivial `.gitignore` tweaks that don't affect project logic. Rule of
thumb: *if a reviewer would care, log it.*

## Tag vocabulary
`[design]` `[doc]` `[code]` `[workflow]` `[config]` `[decision]` `[data]`

## Entry format

Substantial changes use the full form:

```markdown
# 2026-W28  (2026-07-06 – 2026-07-12)

## 2026-07-08
### [design] docs/artifact/Scale Indicator.dc.html
- **What:** Reworked ODB reference into full weighing-terminal layout.
- **Why:** Round-2 UI/UX pass.
- **Refs:** plan `plans/archive/2026-07-08_scale-indicator/plan.md` · commit b30333d
```

Minor / routine changes get a one-line note under the day's heading:

```markdown
### [code] src/utils.py – minor: fixed typo in error message
```

## Reference field
Always include the abbreviated commit hash when available. For substantial
changes, also link the corresponding plan file by its relative path.
