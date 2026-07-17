# Hook I/O Contract

The dispatcher (`hooks/workflow_hook.py`) is invoked by Claude Code for three
hook events. For each, Claude writes a JSON event object to the hook's **stdin**
and reads a JSON object from its **stdout**. The hook **always exits 0**
(fail-soft): an error in the workflow tooling must never break a session.

See `GUIDE.md` §7 for the full behavioural spec.

---

## Shared input fields

| Field | Type | Notes |
|-------|------|-------|
| `hookEventName` | string | `SessionStart` \| `PostToolUse` \| `Stop`. (`hook_event_name` is also accepted.) |
| `session_id` | string | Identifies the session; used to name the per-session state file. If absent, the hook runs statelessly. |

Per-session state lives at
`{tempdir}/workflow_hook_state_{sanitized_session_id}.json` and holds
`source_changed`, `ledger_touched`, `stop_block_count`, `doc_nudged`,
`session_start_ts`.

---

## SessionStart

**Input:** `{ "hookEventName": "SessionStart", "session_id": "..." }`

**Behaviour:** purge stale state (>24h), reset session state, gather git
status, run `env_check` tool checks, parse the roadmap `**Next action:**`,
flag an unfinished plan, and — when `workflow_update_check.enabled` is true —
run the F5 daily update check.

**F5 update check (opt-in, default off):** no-op unless
`workflow_update_check.enabled`. When on, and the `submodule_path` (default
`.claude/workflow-core`) is a linked git repo, it is fetched at most once per
day (gated by the project-persistent `.ai/.workflow_check_date` file) and
compared against `{remote}/{branch}`. If the submodule is behind, a
`🔄 Workflow updates available (N new commits)` line is appended to the injected
context. **Detection & notification only — never auto-applies the update.**
Fail-soft: any git/network error leaves the check silent.

**Output:**
```json
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "…markdown context injected into the session…",
    "sessionTitle": "Adaptive Workflow session"
  }
}
```

---

## PostToolUse

**Matcher (in settings.json):** `Edit|Write|MultiEdit`.

**Input:**
```json
{
  "hookEventName": "PostToolUse",
  "session_id": "...",
  "tool_name": "MultiEdit",
  "tool_input": {
    "file_path": "src/a.py",
    "edits": [ { "file_path": "src/b.py" } ]
  }
}
```
Both the top-level `file_path` and every `edits[].file_path` are collected.

**Behaviour:** set `source_changed` / `ledger_touched` flags by directory; emit
a one-time advisory nudge if source changed without a doc file being touched.
**Advisory only — never blocks.**

**Output (only when nudging):**
```json
{ "hookSpecificOutput": { "hookEventName": "PostToolUse", "additionalContext": "…" } }
```
Otherwise: no output.

---

## Stop

**Input:** `{ "hookEventName": "Stop", "session_id": "...", "stop_hook_active": false }`

**Behaviour:**
- If `stop_hook_active` is true **or** `stop_block_count >= stop_hook.max_blocks`
  → exit 0, no output (allow the session to end).
- Dirty working tree on a non-`main_branch` branch → commit reminder.
- `source_changed` && !`ledger_touched` → ledger reminder.
- **Dirty working tree on _any_ branch → write a Phase-3 breadcrumb** to
  `plans/UNFINISHED.md` (see below). This happens whether or not the hook blocks.
- If any reminder: increment `stop_block_count`, emit a block decision.

Detection of the ledger reminder uses the **session state file**, not
`git diff HEAD` (which would include pre-session changes). The breadcrumb and the
commit reminder use live `git status`.

**Phase-3 breadcrumb:** on a dirty tree the hook writes/refreshes
`plans/UNFINISHED.md` (timestamp, branch, `git status --porcelain` file list, and
the pending reminders) so the next `SessionStart` (F4) surfaces the unfinished
work — durable even if the reminder is ignored or the session is force-closed.
The file begins with the marker `<!-- workflow-hook: auto-breadcrumb -->`; the
hook overwrites only its own marked breadcrumb and **never** clobbers a
human-authored `UNFINISHED.md` (one lacking the marker). Fail-soft: write errors
never break session close.

**Output (only when blocking):**
```json
{ "decision": "block", "reason": "…what to do before ending…" }
```
Otherwise: no output.

---

## Flags

- `--dry-run` — compute and print output as normal but route state writes to a
  null session so nothing is persisted and no real block count increments.
