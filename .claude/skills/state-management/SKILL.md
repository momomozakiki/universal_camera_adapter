---
name: state-management
description: >-
  Use whenever adding or changing a screen, widget, or setting in `example/` (or any future
  consumer-facing UI in this repo) that carries state a user would notice — selection state
  (selected camera device, active tab/index, zoom/pan/tilt values), a saved setting, or anything
  a user would expect to survive a widget rebuild or an app restart. Trigger whenever a request
  mentions `setState`, `ChangeNotifier`, `Provider`, `Riverpod`, `Bloc`, `SharedPreferences`,
  "remember", "persist state", "restore on launch", "state management", or "don't lose my
  selection" — even if none of those exact words appear, whenever a change touches
  `example/lib/camera_session.dart` or `example/lib/main.dart`. Defer the adapter contract itself
  to [[camera-adapter-authoring]] — this skill owns what the UI *remembers* about it, not how the
  adapter is shaped. For treating restored/loaded values as untrusted, see [[input-hardening]].
---

# State management — decide what the app remembers, and prove it

The example app is a **testing toolkit today, but every screen you add makes it look more like a
real app** to whoever uses it — and a real app that forgets your selected camera or zoom level on
every rebuild reads as broken, not minimal. State handling isn't automatic; it's a decision made
once per piece of state, and this skill exists so that decision doesn't quietly default to "gets
forgotten" by omission.

## Rule 1 — Decide, don't default; separate ephemeral from meaningful

Purely transient UI state — scroll offset, an expanded accordion, in-progress form text — can
safely live in-memory and reset on rebuild; nobody expects otherwise. State a user would call
"their setting" — selected device, last-used tab, saved connection details, zoom level — needs an
explicit choice: in-memory-only vs. persisted (`SharedPreferences` or another persistence layer;
don't hard-lock the codebase to one library by default). Silence defaults to in-memory, which must
be a conscious call, not an oversight.

**Smell:** a new `bool`/`int`/`String` field added to a state container with no comment or PR note
on whether it's expected to survive a restart.

## Rule 2 — One state container, not a second competing one

Today's baseline is `CameraSession`, a plain `ChangeNotifier`
(`example/lib/camera_session.dart`), consumed by a `StatefulWidget`
(`example/lib/main.dart`) — nothing persisted yet. Extend that existing container for new state
rather than introducing a second, parallel pattern (a new `Provider`/`Riverpod` tree, a second
notifier) without a stated reason — two sources of truth for overlapping state is how "which one
is right" bugs start.

**Smell:** a new `ChangeNotifier`/`StatefulWidget` holding a value that's also readable from
`CameraSession`.

## Rule 3 — Persist at the edge; treat loaded values as untrusted input

When persistence is warranted, keep the read/write at the edge (load on init, save on change) and
keep the persisted shape minimal and versionable — persist plain values/IDs, not `CameraDevice`
instances. On load, treat disk exactly like any other external input per [[input-hardening]]: a
missing key, wrong type, or a value written by an older version of the app must fall back to a
sane default rather than throwing — a stored value from a previous release must never crash the
app on upgrade.

**Smell:** a bare `as String`/`as int` on a value read back from `SharedPreferences`; a persisted
`Map` shaped exactly like an internal model class, ready to break the moment that class changes.

## Rule 4 — A persisted reference can go stale

A restored device ID may no longer be present in `listDevices()` — the camera got unplugged, or a
network camera went offline. Re-validate a restored reference against the live device list before
using it, and fall back gracefully (no selection, or first available) rather than assuming it
still resolves.

**Smell:** using a restored device ID directly in `adapter.open(...)` without first checking it's
still in the current device list.

## Rule 5 — Verify restoration, not just the write

For any state that's persisted, the acceptance check is an actual restart: change the value, kill
and relaunch the app (or, in a unit test, tear down and reconstruct the container from the same
storage backend), and confirm the value comes back. A `save()` call that's never proven to
round-trip isn't done.

**Smell:** a PR that adds a `save()` call but no restart/round-trip check anywhere — manual note or
test.

## PR litmus test

- ✅ Is every new piece of user-visible state explicitly in-memory or persisted — never accidental?
- ✅ Does new state extend `CameraSession` rather than spawning a second, competing container?
- ✅ Is anything loaded from disk validated/defaulted like untrusted input, not bare-cast?
- ✅ Does a restored reference (e.g. a device ID) get re-checked against live data before use?
- ✅ Has restoration actually been verified with a restart or an equivalent round-trip test?
- ✅ Does the PR/ledger entry say which state is in-memory vs. persisted, and why?

## References

- `example/lib/camera_session.dart` — the current `ChangeNotifier` state container; extend this
  rather than duplicating it.
- `example/lib/main.dart` — the `StatefulWidget` that owns and consumes `CameraSession`.
- Related skills: [[input-hardening]] (loaded/restored values are untrusted input),
  [[camera-adapter-authoring]] (the adapter contract this state refers to),
  [[dart-solid-principles]] (state container design/testability).

> Paths are intentionally concrete; if they move, update this skill.
