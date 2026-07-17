#!/usr/bin/env python3
"""Adaptive Self-Correcting Workflow -- hook dispatcher.

A single fail-soft dispatcher invoked by Claude Code for the ``SessionStart``,
``PostToolUse`` and ``Stop`` hook events. It reads the event JSON from stdin,
loads the project's ``workflow_config.json`` and branches to the appropriate
handler. Every handler is wrapped so the process *always* exits 0 -- a bug in
the workflow tooling must never break a coding session.

Stdlib only (Python 3.8+). No third-party dependencies, so projects can vendor
this file as a git submodule without inheriting a dependency tree.

See ``schemas/hook_contract.md`` for the input/output contracts and
``GUIDE.md`` section 7 for the full behavioural spec.
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

STATE_TTL_SECONDS = 24 * 60 * 60  # stale session state older than this is purged
DEFAULT_MAX_BLOCKS = 2
DEFAULT_MAIN_BRANCH = "main"


# --------------------------------------------------------------------------- #
# Config discovery & loading
# --------------------------------------------------------------------------- #
def find_config_path() -> Optional[Path]:
    """Locate ``workflow_config.json``.

    Primary: ``$CLAUDE_PROJECT_DIR`` (set by Claude Code to the project root,
    correct even when this hook lives deep inside ``.claude/workflow-core/``).
    Fallback: walk upward from this file looking for ``.claude/workflow_config.json``
    or a repo-root ``workflow_config.json`` (covers self-dogfooding, where the
    hook sits at the repo root).
    """
    project_dir = os.environ.get("CLAUDE_PROJECT_DIR")
    if project_dir:
        candidate = Path(project_dir) / ".claude" / "workflow_config.json"
        if candidate.is_file():
            return candidate
        candidate = Path(project_dir) / "workflow_config.json"
        if candidate.is_file():
            return candidate

    here = Path(__file__).resolve()
    for parent in [here.parent, *here.parents]:
        for candidate in (
            parent / ".claude" / "workflow_config.json",
            parent / "workflow_config.json",
        ):
            if candidate.is_file():
                return candidate
    return None


def load_config() -> Tuple[Dict[str, Any], Path]:
    """Return (config dict, project_root). Always returns a usable config."""
    config_path = find_config_path()
    if config_path is None:
        return {}, Path(os.environ.get("CLAUDE_PROJECT_DIR") or ".").resolve()

    try:
        config = json.loads(config_path.read_text(encoding="utf-8"))
    except Exception:
        config = {}

    # Project root: explicit config value wins, else the dir containing .claude/,
    # else the config file's directory.
    root_hint = config.get("project_root")
    if root_hint and root_hint != ".":
        project_root = (config_path.parent / root_hint).resolve()
    elif config_path.parent.name == ".claude":
        project_root = config_path.parent.parent.resolve()
    else:
        project_root = config_path.parent.resolve()
    return config, project_root


# --------------------------------------------------------------------------- #
# Per-session state
# --------------------------------------------------------------------------- #
def _sanitize(session_id: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]", "_", session_id)[:128]


def state_path(session_id: str) -> Path:
    return Path(tempfile.gettempdir()) / f"workflow_hook_state_{_sanitize(session_id)}.json"


def default_state() -> Dict[str, Any]:
    return {
        "source_changed": False,
        "ledger_touched": False,
        "stop_block_count": 0,
        "doc_nudged": False,
        "session_start_ts": time.time(),
    }


def load_state(session_id: Optional[str]) -> Dict[str, Any]:
    if not session_id:
        return default_state()
    try:
        return json.loads(state_path(session_id).read_text(encoding="utf-8"))
    except Exception:
        return default_state()


def save_state(session_id: Optional[str], state: Dict[str, Any]) -> None:
    if not session_id:
        return
    try:
        path = state_path(session_id)
        tmp = path.with_suffix(".tmp")
        tmp.write_text(json.dumps(state), encoding="utf-8")
        os.replace(tmp, path)  # atomic on the same filesystem
    except Exception:
        pass


def purge_stale_state() -> None:
    """Remove session state files older than the TTL."""
    try:
        now = time.time()
        for f in Path(tempfile.gettempdir()).glob("workflow_hook_state_*.json"):
            try:
                if now - f.stat().st_mtime > STATE_TTL_SECONDS:
                    f.unlink()
            except Exception:
                continue
    except Exception:
        pass


# --------------------------------------------------------------------------- #
# Git helpers (all guarded -- never raise)
# --------------------------------------------------------------------------- #
def _git(project_root: Path, *args: str) -> Optional[str]:
    try:
        out = subprocess.run(
            ["git", *args],
            cwd=str(project_root),
            capture_output=True,
            text=True,
            timeout=10,
        )
        if out.returncode != 0:
            return None
        return out.stdout.strip()
    except Exception:
        return None


def git_status(project_root: Path) -> Dict[str, Any]:
    branch = _git(project_root, "rev-parse", "--abbrev-ref", "HEAD")
    dirty = bool(_git(project_root, "status", "--porcelain"))
    ahead = behind = None
    counts = _git(project_root, "rev-list", "--left-right", "--count", "@{u}...HEAD")
    if counts:
        parts = counts.split()
        if len(parts) == 2:
            behind, ahead = parts[0], parts[1]
    return {"branch": branch, "dirty": dirty, "ahead": ahead, "behind": behind}


# --------------------------------------------------------------------------- #
# F5: daily workflow-core update check (opt-in)
# --------------------------------------------------------------------------- #
def check_workflow_updates(config: Dict[str, Any], project_root: Path) -> Optional[str]:
    """Return an F5 update notice if the vendored ``workflow-core`` is behind.

    Opt-in and fail-soft: returns ``None`` (silent) unless
    ``workflow_update_check.enabled`` is true, the submodule is actually linked,
    and a once-per-day fetch finds new upstream commits. Never auto-applies the
    update -- detection & notification only (the agent asks the user per F5).
    """
    cfg = config.get("workflow_update_check") or {}
    if not cfg.get("enabled"):
        return None

    submodule_rel = cfg.get("submodule_path", ".claude/workflow-core")
    remote = cfg.get("remote", "origin")
    branch = cfg.get("branch", "main")

    submodule = (project_root / submodule_rel).resolve()
    if not (submodule / ".git").exists():
        return None  # not linked -- nothing to check

    # Once-per-day gate via a project-persistent state file (survives sessions).
    today = time.strftime("%Y-%m-%d")
    date_file = project_root / ".ai" / ".workflow_check_date"
    try:
        if date_file.read_text(encoding="utf-8").strip() == today:
            return None  # already checked today
    except Exception:
        pass  # missing/unreadable -> proceed with the check

    if _git(submodule, "fetch", "--depth=1", remote, branch) is None:
        return None  # offline or fetch failed -- stay silent

    count = _git(submodule, "rev-list", "--count", f"HEAD..{remote}/{branch}")

    # Record today's check regardless of the outcome, so we don't refetch today.
    try:
        date_file.parent.mkdir(parents=True, exist_ok=True)
        date_file.write_text(today + "\n", encoding="utf-8")
    except Exception:
        pass

    if count and count.strip().isdigit() and int(count) > 0:
        return (
            f"🔄 Workflow updates available ({count} new commits) in "
            f"`{submodule_rel}`. F5: I can run `git submodule update --remote` "
            "and re-validate any new mandatory steps."
        )
    return None


# --------------------------------------------------------------------------- #
# Phase-3 breadcrumb (Stop hook)
# --------------------------------------------------------------------------- #
BREADCRUMB_MARKER = "<!-- workflow-hook: auto-breadcrumb -->"


def write_unfinished_breadcrumb(project_root: Path, gs: Dict[str, Any],
                                reminders: List[str]) -> None:
    """Record an interrupted Phase-3 closure to ``plans/UNFINISHED.md``.

    Durable safety net: if a session ends with a dirty tree, the next
    ``SessionStart`` (F4) surfaces this file. Fail-soft and idempotent -- it
    overwrites only its own marked breadcrumb and never clobbers a
    human-authored plan (a file lacking ``BREADCRUMB_MARKER`` is left untouched).
    """
    try:
        target = project_root / "plans" / "UNFINISHED.md"
        if target.is_file():
            try:
                existing = target.read_text(encoding="utf-8")
            except Exception:
                existing = ""
            if BREADCRUMB_MARKER not in existing:
                return  # genuine, human-authored plan -- do not overwrite

        porcelain = _git(project_root, "status", "--porcelain") or ""
        files = "\n".join(f"  {line}" for line in porcelain.splitlines()) or "  (none reported)"
        stamp = time.strftime("%Y-%m-%d %H:%M:%S")
        branch = gs.get("branch") or "(unknown)"
        pending = "\n".join(f"- {r}" for r in reminders) or "- Commit & push pending work."

        body = (
            f"{BREADCRUMB_MARKER}\n"
            f"# Unfinished session — auto-recorded {stamp}\n\n"
            "> This breadcrumb was written by the workflow Stop hook because the\n"
            "> working tree was dirty at session end (Phase 3 not completed).\n"
            "> Review, finish closure, then delete this file. It will be\n"
            "> overwritten by the hook while it remains a breadcrumb, but a\n"
            "> human-authored plan placed here is never overwritten.\n\n"
            f"**Branch:** `{branch}`\n\n"
            "**Pending closure steps:**\n"
            f"{pending}\n\n"
            "**Uncommitted files (`git status --porcelain`):**\n\n"
            f"```\n{files}\n```\n"
        )
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(body, encoding="utf-8")
    except Exception:
        pass  # fail-soft: never break session close


# --------------------------------------------------------------------------- #
# Path helpers
# --------------------------------------------------------------------------- #
def _norm(p: str) -> str:
    return p.replace("\\", "/").strip("/")


def path_under_any(path: str, directories: List[str], project_root: Path) -> bool:
    """True if ``path`` is inside any of ``directories`` (relative to project root)."""
    if not path:
        return False
    try:
        abs_path = Path(path)
        if not abs_path.is_absolute():
            abs_path = (project_root / path)
        abs_path = abs_path.resolve()
    except Exception:
        abs_path = None

    norm_path = _norm(path)
    for d in directories or []:
        nd = _norm(d)
        if not nd:
            continue
        # relative-string match
        if norm_path == nd or norm_path.startswith(nd + "/"):
            return True
        # absolute containment match
        if abs_path is not None:
            try:
                base = (project_root / d).resolve()
                abs_path.relative_to(base)
                return True
            except Exception:
                pass
    return False


def collect_touched_paths(event: Dict[str, Any]) -> List[str]:
    """Extract every file path touched by an Edit/Write/MultiEdit tool call."""
    paths: List[str] = []
    tool_input = event.get("tool_input") or {}
    if isinstance(tool_input, dict):
        fp = tool_input.get("file_path")
        if isinstance(fp, str):
            paths.append(fp)
        edits = tool_input.get("edits")
        if isinstance(edits, list):
            for e in edits:
                if isinstance(e, dict) and isinstance(e.get("file_path"), str):
                    paths.append(e["file_path"])
    return paths


# --------------------------------------------------------------------------- #
# Output helpers
# --------------------------------------------------------------------------- #
def emit(obj: Dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(obj))
    sys.stdout.write("\n")


def session_context(event_name: str, additional_context: str,
                    session_title: Optional[str] = None) -> Dict[str, Any]:
    hook_out: Dict[str, Any] = {
        "hookEventName": event_name,
        "additionalContext": additional_context,
    }
    out: Dict[str, Any] = {"hookSpecificOutput": hook_out}
    if session_title:
        out["hookSpecificOutput"]["sessionTitle"] = session_title
    return out


# --------------------------------------------------------------------------- #
# Handlers
# --------------------------------------------------------------------------- #
def run_env_checks(config: Dict[str, Any], project_root: Path) -> List[str]:
    lines: List[str] = []
    tool_paths = (config.get("env_check") or {}).get("tool_paths") or {}
    for name, spec in tool_paths.items():
        if not isinstance(spec, dict):
            continue
        raw_path = spec.get("path", "")
        tool_path = Path(raw_path)
        if not tool_path.is_absolute():
            tool_path = (project_root / raw_path)
        version_flag = spec.get("version_flag", "--version")

        if version_flag in (None, ""):
            exists = tool_path.exists() or _which(raw_path) is not None
            lines.append(f"  - {name}: {'found' if exists else 'NOT FOUND'} ({raw_path})")
            continue

        try:
            res = subprocess.run(
                [str(raw_path), str(version_flag)],
                capture_output=True, text=True, timeout=15,
            )
            ver = (res.stdout or res.stderr or "").strip().splitlines()
            ver_str = ver[0] if ver else "(no output)"
            lines.append(f"  - {name}: {ver_str}")
        except Exception:
            lines.append(f"  - {name}: NOT FOUND ({raw_path})")
    return lines


def _which(cmd: str) -> Optional[str]:
    from shutil import which
    try:
        return which(cmd)
    except Exception:
        return None


def parse_next_action(config: Dict[str, Any], project_root: Path) -> Optional[str]:
    roadmap_rel = config.get("roadmap_file")
    if not roadmap_rel:
        return None
    roadmap = project_root / roadmap_rel
    # Require the marker at the start of the line (after optional whitespace,
    # blockquote '>' or a list bullet) so prose that merely *mentions* the
    # marker inline doesn't produce a false match.
    marker = re.compile(r"^\s*(?:[>]\s*)?(?:[-*+]\s+)?\*\*Next action:\*\*\s*(.+)$")
    try:
        for line in roadmap.read_text(encoding="utf-8").splitlines():
            m = marker.match(line)
            if m:
                return m.group(1).strip()
    except Exception:
        return None
    return None


def handle_session_start(event: Dict[str, Any], config: Dict[str, Any],
                         project_root: Path) -> None:
    purge_stale_state()
    session_id = event.get("session_id")
    save_state(session_id, default_state())

    parts: List[str] = ["## Adaptive Workflow — session start"]

    gs = git_status(project_root)
    if gs.get("branch"):
        git_line = f"Git: branch `{gs['branch']}`"
        if gs.get("dirty"):
            git_line += " (dirty working tree — F1: stash/commit before you begin?)"
        if gs.get("ahead") not in (None, "0") or gs.get("behind") not in (None, "0"):
            git_line += f" — ahead {gs.get('ahead')}, behind {gs.get('behind')}"
        parts.append(git_line)

    env_lines = run_env_checks(config, project_root)
    if env_lines:
        parts.append("Environment (F2):\n" + "\n".join(env_lines))

    next_action = parse_next_action(config, project_root)
    if next_action:
        parts.append(f"Roadmap next action (F4): {next_action}")

    unfinished = project_root / "plans" / "UNFINISHED.md"
    if unfinished.is_file():
        parts.append("⚠️ Unfinished plan detected (plans/UNFINISHED.md) — "
                     "F4: surface it and ask whether to continue or archive.")

    update_notice = check_workflow_updates(config, project_root)
    if update_notice:
        parts.append(update_notice)

    parts.append("Reminders: log intentional changes to the weekly ledger "
                 "(history/YYYY-Www.md); add doc frontmatter (provenance + version) to new docs.")

    emit(session_context("SessionStart", "\n\n".join(parts),
                         session_title="Adaptive Workflow session"))


def handle_post_tool_use(event: Dict[str, Any], config: Dict[str, Any],
                         project_root: Path) -> None:
    session_id = event.get("session_id")
    state = load_state(session_id)

    paths = collect_touched_paths(event)
    source_dirs = config.get("source_directories") or []
    doc_dirs = config.get("documentation_directories") or []
    ledger_dir = (config.get("ledger") or {}).get("directory", "history")

    doc_touched_now = False
    for p in paths:
        if path_under_any(p, source_dirs, project_root):
            state["source_changed"] = True
        if path_under_any(p, [ledger_dir], project_root):
            state["ledger_touched"] = True
        if path_under_any(p, doc_dirs, project_root):
            doc_touched_now = True

    nudge = None
    if (state.get("source_changed") and not doc_touched_now
            and not state.get("doc_nudged")):
        state["doc_nudged"] = True
        nudge = ("Consider updating docs and the weekly ledger "
                 "(history/YYYY-Www.md) if this change is worth tracing.")

    save_state(session_id, state)

    if nudge:
        emit(session_context("PostToolUse", nudge))


def handle_stop(event: Dict[str, Any], config: Dict[str, Any],
                project_root: Path) -> None:
    session_id = event.get("session_id")
    state = load_state(session_id)

    max_blocks = (config.get("stop_hook") or {}).get("max_blocks", DEFAULT_MAX_BLOCKS)
    main_branch = (config.get("stop_hook") or {}).get("main_branch", DEFAULT_MAIN_BRANCH)

    if event.get("stop_hook_active") or state.get("stop_block_count", 0) >= max_blocks:
        return  # exit 0, no output

    reminders: List[str] = []

    gs = git_status(project_root)
    if gs.get("dirty") and gs.get("branch") and gs.get("branch") != main_branch:
        reminders.append(
            f"Working tree is dirty on branch `{gs['branch']}`. "
            "Phase 3 closure: commit & push before ending "
            "(`git add -A && git commit && git push`)."
        )

    if state.get("source_changed") and not state.get("ledger_touched"):
        reminders.append(
            "Source files changed this session but the weekly ledger "
            "(history/YYYY-Www.md) wasn't updated. Add an entry "
            "(What / Why / Refs) before closing."
        )

    # Durable safety net: any dirty tree at Stop leaves a breadcrumb (on any
    # branch, so main-branch closures are covered too). This happens whether or
    # not we block, so the record survives an ignored reminder or a force-close.
    if gs.get("dirty"):
        write_unfinished_breadcrumb(project_root, gs, reminders)

    if reminders:
        state["stop_block_count"] = state.get("stop_block_count", 0) + 1
        save_state(session_id, state)
        emit({"decision": "block", "reason": "\n".join(reminders)})
    # else: exit 0 silently, allowing the session to end.


HANDLERS = {
    "SessionStart": handle_session_start,
    "PostToolUse": handle_post_tool_use,
    "Stop": handle_stop,
}


# --------------------------------------------------------------------------- #
# Entry point
# --------------------------------------------------------------------------- #
def main(argv: Optional[List[str]] = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    dry_run = "--dry-run" in argv

    try:
        raw = sys.stdin.read()
        event = json.loads(raw) if raw.strip() else {}
    except Exception:
        return 0  # fail-soft: unparseable input never breaks the session

    if not isinstance(event, dict):
        return 0

    event_name = event.get("hookEventName") or event.get("hook_event_name")
    handler = HANDLERS.get(event_name)
    if handler is None:
        return 0

    try:
        config, project_root = load_config()
    except Exception:
        config, project_root = {}, Path(".").resolve()

    if dry_run:
        # In dry-run mode we still compute output but suppress state mutation by
        # routing writes to a throwaway session id.
        event = dict(event)
        event["session_id"] = None

    try:
        handler(event, config, project_root)
    except Exception:
        return 0  # fail-soft: any handler error is swallowed

    return 0


if __name__ == "__main__":
    sys.exit(main())
