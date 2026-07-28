#!/usr/bin/env python3
"""Synthetic-event tests for the workflow hook dispatcher.

Stdlib ``unittest`` only -- run with::

    python -m unittest discover -s tests
    # or
    python -m unittest tests.test_hook

Each test drives ``workflow_hook.main`` with a fabricated hook event on stdin
and asserts on the JSON emitted to stdout, mirroring how Claude Code invokes
the hook. State is isolated per-test via a unique ``session_id`` and a temp
``CLAUDE_PROJECT_DIR``.
"""

import io
import json
import os
import sys
import tempfile
import types
import unittest
import uuid
from unittest import mock
from contextlib import redirect_stdout
from pathlib import Path

# Make the vendored hook importable regardless of CWD.
# This test lives at tests/hook/test_hook.py; the hook is at .claude/hooks/.
REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT / ".claude" / "hooks"))

import workflow_hook  # noqa: E402


def run_hook(event, argv=None, project_dir=None):
    """Invoke the dispatcher with ``event`` on stdin; return parsed stdout (or None)."""
    stdin = io.StringIO(json.dumps(event))
    buf = io.StringIO()
    old_stdin, sys.stdin = sys.stdin, stdin
    old_env = os.environ.get("CLAUDE_PROJECT_DIR")
    if project_dir is not None:
        os.environ["CLAUDE_PROJECT_DIR"] = str(project_dir)
    try:
        with redirect_stdout(buf):
            rc = workflow_hook.main(argv or [])
    finally:
        sys.stdin = old_stdin
        if old_env is None:
            os.environ.pop("CLAUDE_PROJECT_DIR", None)
        else:
            os.environ["CLAUDE_PROJECT_DIR"] = old_env
    out = buf.getvalue().strip()
    parsed = json.loads(out) if out else None
    return rc, parsed


class BaseCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.project = Path(self.tmp.name)
        (self.project / ".claude").mkdir()
        (self.project / "src").mkdir()
        (self.project / "docs").mkdir()
        (self.project / "history").mkdir()
        self.session_id = f"test-{uuid.uuid4()}"
        self.write_config({
            "project_root": ".",
            "roadmap_file": "ROADMAP.md",
            "ledger": {"enabled": True, "directory": "history"},
            "source_directories": ["src"],
            "documentation_directories": ["docs"],
            "env_check": {"tool_paths": {}},
            "stop_hook": {"max_blocks": 2, "main_branch": "main"},
        })

    def tearDown(self):
        try:
            workflow_hook.state_path(self.session_id).unlink()
        except OSError:
            pass
        self.tmp.cleanup()

    def write_config(self, cfg):
        (self.project / ".claude" / "workflow_config.json").write_text(
            json.dumps(cfg), encoding="utf-8")

    def edit_event(self, file_path):
        return {"hookEventName": "PostToolUse", "session_id": self.session_id,
                "tool_name": "Edit", "tool_input": {"file_path": file_path}}


class TestFailSoft(BaseCase):
    def test_unparseable_stdin_exits_zero(self):
        sys.stdin = io.StringIO("not json {{{")
        buf = io.StringIO()
        try:
            with redirect_stdout(buf):
                rc = workflow_hook.main([])
        finally:
            sys.stdin = sys.__stdin__
        self.assertEqual(rc, 0)
        self.assertEqual(buf.getvalue().strip(), "")

    def test_unknown_event_no_output(self):
        rc, out = run_hook({"hookEventName": "Nonsense"}, project_dir=self.project)
        self.assertEqual(rc, 0)
        self.assertIsNone(out)

    def test_missing_session_id_still_runs(self):
        rc, out = run_hook({"hookEventName": "SessionStart"}, project_dir=self.project)
        self.assertEqual(rc, 0)
        self.assertIn("hookSpecificOutput", out)


class TestSessionStart(BaseCase):
    def test_emits_context(self):
        rc, out = run_hook(
            {"hookEventName": "SessionStart", "session_id": self.session_id},
            project_dir=self.project)
        self.assertEqual(rc, 0)
        self.assertEqual(out["hookSpecificOutput"]["hookEventName"], "SessionStart")
        self.assertIn("session start", out["hookSpecificOutput"]["additionalContext"].lower())

    def test_env_check_null_version_flag_existence(self):
        # A tool with version_flag=null: only existence is checked.
        tool = self.project / "mytool.bin"
        tool.write_text("x", encoding="utf-8")
        self.write_config({
            "project_root": ".",
            "source_directories": ["src"],
            "documentation_directories": ["docs"],
            "ledger": {"directory": "history"},
            "env_check": {"tool_paths": {
                "mytool": {"path": str(tool), "version_flag": None}}},
        })
        rc, out = run_hook(
            {"hookEventName": "SessionStart", "session_id": self.session_id},
            project_dir=self.project)
        ctx = out["hookSpecificOutput"]["additionalContext"]
        self.assertIn("mytool: found", ctx)

    def test_env_check_missing_tool_reports_not_found(self):
        self.write_config({
            "project_root": ".",
            "source_directories": ["src"],
            "documentation_directories": ["docs"],
            "ledger": {"directory": "history"},
            "env_check": {"tool_paths": {
                "ghost": {"path": "/no/such/tool", "version_flag": None}}},
        })
        rc, out = run_hook(
            {"hookEventName": "SessionStart", "session_id": self.session_id},
            project_dir=self.project)
        self.assertIn("ghost: NOT FOUND",
                      out["hookSpecificOutput"]["additionalContext"])

    def test_roadmap_next_action_parsed(self):
        (self.project / "ROADMAP.md").write_text(
            "# Roadmap\n\n**Next action:** wire up the Stop hook\n", encoding="utf-8")
        rc, out = run_hook(
            {"hookEventName": "SessionStart", "session_id": self.session_id},
            project_dir=self.project)
        self.assertIn("wire up the Stop hook",
                      out["hookSpecificOutput"]["additionalContext"])

    def test_roadmap_ignores_inline_mention(self):
        # A prose line that merely mentions the marker inside backticks must not
        # be matched; only the real leading-marker line counts.
        (self.project / "ROADMAP.md").write_text(
            "# Roadmap\n\nThe hook parses the first `**Next action:**` line below.\n\n"
            "**Next action:** the real task\n", encoding="utf-8")
        rc, out = run_hook(
            {"hookEventName": "SessionStart", "session_id": self.session_id},
            project_dir=self.project)
        ctx = out["hookSpecificOutput"]["additionalContext"]
        self.assertIn("the real task", ctx)
        self.assertNotIn("line below", ctx)


class TestEnvCheckShimResolution(unittest.TestCase):
    """`run_env_checks` must resolve a bare tool name via PATHEXT before exec.

    On Windows the configured tools (`dart`, `flutter`) are `.bat` shims.
    CreateProcess only appends `.exe` when searching PATH, so passing the bare
    name to subprocess raises FileNotFoundError and the tool is misreported as
    NOT FOUND even when installed. These tests pin the resolution behaviour
    without depending on a real `.bat` existing on the runner.
    """

    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.project = Path(self.tmp.name)
        self.calls = []
        self.addCleanup(self.tmp.cleanup)

    def stub(self, which_result, run_result):
        """Stub `_which` and `subprocess.run`, recording the run() call.

        Patched via mock so the real `subprocess` module is restored even if an
        assertion fails mid-test.
        """
        def fake_run(args, **kwargs):
            self.calls.append((args, kwargs))
            if isinstance(run_result, Exception):
                raise run_result
            return run_result

        for patcher in (
            mock.patch.object(workflow_hook, "_which", lambda cmd: which_result),
            mock.patch.object(workflow_hook.subprocess, "run", fake_run),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    @staticmethod
    def config(path):
        return {"env_check": {"tool_paths": {
            "flutter": {"path": path, "version_flag": "--version"}}}}

    def test_bare_name_is_resolved_via_which_before_exec(self):
        resolved = r"C:\puro\envs\default\flutter\bin\flutter.BAT"
        self.stub(resolved, types.SimpleNamespace(stdout="Flutter 3.44.0\n", stderr=""))

        lines = workflow_hook.run_env_checks(self.config("flutter"), self.project)

        self.assertEqual(lines, ["  - flutter: Flutter 3.44.0"])
        # The regression that would silently reappear: exec'ing the bare name.
        args, kwargs = self.calls[0]
        self.assertEqual(args, [resolved, "--version"])
        self.assertNotIn("shell", kwargs)

    def test_resolution_does_not_leak_absolute_path_into_output(self):
        # The reported line stays machine-independent even though exec resolved.
        self.stub(r"C:\somewhere\flutter.BAT", types.SimpleNamespace(stdout="", stderr=""))
        lines = workflow_hook.run_env_checks(self.config("flutter"), self.project)
        self.assertEqual(lines, ["  - flutter: (no output)"])

    def test_unresolvable_name_reports_not_found(self):
        self.stub(None, FileNotFoundError(2, "The system cannot find the file specified"))
        lines = workflow_hook.run_env_checks(self.config("ghost-tool"), self.project)
        self.assertEqual(lines, ["  - flutter: NOT FOUND (ghost-tool)"])

    def test_subprocess_failure_still_reports_not_found(self):
        # `which` resolves but exec blows up -> must not crash the hook.
        self.stub(r"C:\somewhere\flutter.BAT", OSError("boom"))
        lines = workflow_hook.run_env_checks(self.config("flutter"), self.project)
        self.assertEqual(lines, ["  - flutter: NOT FOUND (flutter)"])

    def test_existing_relative_path_wins_over_which(self):
        # A repo-vendored tool referenced by relative path must not regress.
        vendored = self.project / "tool.bin"
        vendored.write_text("x", encoding="utf-8")
        self.stub(r"C:\elsewhere\tool.exe", types.SimpleNamespace(stdout="v1\n", stderr=""))

        lines = workflow_hook.run_env_checks(self.config("tool.bin"), self.project)

        self.assertEqual(lines, ["  - flutter: v1"])
        self.assertEqual(self.calls[0][0], [str(vendored), "--version"])

    def test_output_is_decoded_as_utf8(self):
        self.stub(r"C:\somewhere\flutter.BAT",
                  types.SimpleNamespace(stdout="Flutter 3.44.0 \u2022 channel stable\n", stderr=""))

        lines = workflow_hook.run_env_checks(self.config("flutter"), self.project)

        self.assertIn("\u2022", lines[0])
        self.assertEqual(self.calls[0][1].get("encoding"), "utf-8")


class TestPostToolUse(BaseCase):
    def test_source_edit_sets_flag_no_output_when_doc_also_touched(self):
        # MultiEdit touching a source AND a doc file -> no nudge.
        event = {"hookEventName": "PostToolUse", "session_id": self.session_id,
                 "tool_name": "MultiEdit",
                 "tool_input": {"file_path": "src/a.py",
                                "edits": [{"file_path": "docs/b.md"}]}}
        rc, out = run_hook(event, project_dir=self.project)
        self.assertIsNone(out)  # doc touched this call -> suppress nudge
        state = workflow_hook.load_state(self.session_id)
        self.assertTrue(state["source_changed"])

    def test_source_edit_emits_nudge_once(self):
        rc, out = run_hook(self.edit_event("src/a.py"), project_dir=self.project)
        self.assertIsNotNone(out)
        self.assertIn("ledger", out["hookSpecificOutput"]["additionalContext"].lower())
        # Second source edit -> no repeat nudge.
        rc, out2 = run_hook(self.edit_event("src/c.py"), project_dir=self.project)
        self.assertIsNone(out2)

    def test_ledger_edit_sets_ledger_touched(self):
        run_hook(self.edit_event("history/2026-W28.md"), project_dir=self.project)
        state = workflow_hook.load_state(self.session_id)
        self.assertTrue(state["ledger_touched"])
        self.assertFalse(state["source_changed"])

    def test_non_source_edit_no_flag(self):
        run_hook(self.edit_event("README.md"), project_dir=self.project)
        state = workflow_hook.load_state(self.session_id)
        self.assertFalse(state["source_changed"])


class TestStop(BaseCase):
    def _seed_state(self, **kw):
        state = workflow_hook.default_state()
        state.update(kw)
        workflow_hook.save_state(self.session_id, state)

    def test_ledger_reminder_when_source_changed_unlogged(self):
        self._seed_state(source_changed=True, ledger_touched=False)
        rc, out = run_hook(
            {"hookEventName": "Stop", "session_id": self.session_id},
            project_dir=self.project)
        self.assertEqual(out["decision"], "block")
        self.assertIn("ledger", out["reason"].lower())
        # block count incremented
        self.assertEqual(
            workflow_hook.load_state(self.session_id)["stop_block_count"], 1)

    def test_no_block_when_ledger_touched(self):
        self._seed_state(source_changed=True, ledger_touched=True)
        rc, out = run_hook(
            {"hookEventName": "Stop", "session_id": self.session_id},
            project_dir=self.project)
        self.assertIsNone(out)

    def test_stop_hook_active_short_circuits(self):
        self._seed_state(source_changed=True, ledger_touched=False)
        rc, out = run_hook(
            {"hookEventName": "Stop", "session_id": self.session_id,
             "stop_hook_active": True},
            project_dir=self.project)
        self.assertIsNone(out)

    def test_max_blocks_cap(self):
        self._seed_state(source_changed=True, ledger_touched=False, stop_block_count=2)
        rc, out = run_hook(
            {"hookEventName": "Stop", "session_id": self.session_id},
            project_dir=self.project)
        self.assertIsNone(out)  # already at cap -> allow stop


class TestStopBreadcrumb(BaseCase):
    """Workstream A: the Phase-3 auto-breadcrumb on a dirty tree."""

    def _seed_state(self, **kw):
        state = workflow_hook.default_state()
        state.update(kw)
        workflow_hook.save_state(self.session_id, state)

    def _run_stop_with_status(self, status):
        """Drive a Stop event with git_status/_git stubbed to `status`."""
        orig_git_status = workflow_hook.git_status
        orig_git = workflow_hook._git
        workflow_hook.git_status = lambda project_root: status
        # _git is used inside the breadcrumb for `status --porcelain`.
        workflow_hook._git = lambda root, *args: (
            " M src/a.py\n?? new.txt" if args[:1] == ("status",) else None)
        try:
            return run_hook(
                {"hookEventName": "Stop", "session_id": self.session_id},
                project_dir=self.project)
        finally:
            workflow_hook.git_status = orig_git_status
            workflow_hook._git = orig_git

    def test_dirty_tree_writes_breadcrumb_on_feature_branch(self):
        self._seed_state()
        self._run_stop_with_status(
            {"branch": "feat/x", "dirty": True, "ahead": None, "behind": None})
        bc = self.project / "plans" / "UNFINISHED.md"
        self.assertTrue(bc.is_file())
        text = bc.read_text(encoding="utf-8")
        self.assertIn(workflow_hook.BREADCRUMB_MARKER, text)
        self.assertIn("feat/x", text)
        self.assertIn("src/a.py", text)  # porcelain file list included

    def test_dirty_tree_writes_breadcrumb_on_main(self):
        self._seed_state()
        self._run_stop_with_status(
            {"branch": "main", "dirty": True, "ahead": None, "behind": None})
        self.assertTrue((self.project / "plans" / "UNFINISHED.md").is_file())

    def test_clean_tree_writes_no_breadcrumb(self):
        self._seed_state()
        self._run_stop_with_status(
            {"branch": "feat/x", "dirty": False, "ahead": None, "behind": None})
        self.assertFalse((self.project / "plans" / "UNFINISHED.md").exists())

    def test_human_unfinished_is_not_overwritten(self):
        self._seed_state()
        plans = self.project / "plans"
        plans.mkdir()
        human = plans / "UNFINISHED.md"
        human.write_text("# My real handoff plan\nstep 1\n", encoding="utf-8")
        self._run_stop_with_status(
            {"branch": "feat/x", "dirty": True, "ahead": None, "behind": None})
        self.assertEqual(human.read_text(encoding="utf-8"),
                         "# My real handoff plan\nstep 1\n")

    def test_own_breadcrumb_is_overwritten_idempotently(self):
        self._seed_state()
        plans = self.project / "plans"
        plans.mkdir()
        bc = plans / "UNFINISHED.md"
        bc.write_text(workflow_hook.BREADCRUMB_MARKER + "\nold content\n",
                      encoding="utf-8")
        self._run_stop_with_status(
            {"branch": "feat/x", "dirty": True, "ahead": None, "behind": None})
        text = bc.read_text(encoding="utf-8")
        self.assertIn(workflow_hook.BREADCRUMB_MARKER, text)
        self.assertNotIn("old content", text)  # refreshed, not appended


class TestF5UpdateCheck(BaseCase):
    """Workstream B: opt-in daily workflow-core update check."""

    def _cfg(self, **overrides):
        base = {
            "project_root": ".",
            "source_directories": ["src"],
            "documentation_directories": ["docs"],
            "ledger": {"directory": "history"},
            "env_check": {"tool_paths": {}},
        }
        if overrides:
            base["workflow_update_check"] = overrides
        return base

    def test_disabled_is_noop_and_makes_no_git_calls(self):
        calls = []
        orig = workflow_hook._git
        workflow_hook._git = lambda root, *a: calls.append(a) or None
        try:
            notice = workflow_hook.check_workflow_updates(
                self._cfg(enabled=False), self.project)
        finally:
            workflow_hook._git = orig
        self.assertIsNone(notice)
        self.assertEqual(calls, [])

    def test_missing_submodule_is_noop(self):
        notice = workflow_hook.check_workflow_updates(
            self._cfg(enabled=True), self.project)
        self.assertIsNone(notice)

    def test_same_day_check_is_skipped(self):
        # Link a fake submodule so we pass the .git existence gate.
        sub = self.project / ".claude" / "workflow-core"
        sub.mkdir(parents=True)
        (sub / ".git").write_text("gitdir: x", encoding="utf-8")
        ai = self.project / ".ai"
        ai.mkdir()
        import time as _t
        (ai / ".workflow_check_date").write_text(
            _t.strftime("%Y-%m-%d"), encoding="utf-8")
        called = []
        orig = workflow_hook._git
        workflow_hook._git = lambda root, *a: called.append(a) or None
        try:
            notice = workflow_hook.check_workflow_updates(
                self._cfg(enabled=True), self.project)
        finally:
            workflow_hook._git = orig
        self.assertIsNone(notice)
        self.assertEqual(called, [])  # date-gated: no fetch today

    def test_behind_submodule_emits_notice_and_writes_date(self):
        sub = self.project / ".claude" / "workflow-core"
        sub.mkdir(parents=True)
        (sub / ".git").write_text("gitdir: x", encoding="utf-8")

        def fake_git(root, *args):
            if args[:1] == ("fetch",):
                return ""
            if args[:1] == ("rev-list",):
                return "3"
            return None
        orig = workflow_hook._git
        workflow_hook._git = fake_git
        try:
            notice = workflow_hook.check_workflow_updates(
                self._cfg(enabled=True), self.project)
        finally:
            workflow_hook._git = orig
        self.assertIsNotNone(notice)
        self.assertIn("3 new commits", notice)
        import time as _t
        self.assertEqual(
            (self.project / ".ai" / ".workflow_check_date").read_text(
                encoding="utf-8").strip(), _t.strftime("%Y-%m-%d"))

    def test_up_to_date_submodule_is_silent(self):
        sub = self.project / ".claude" / "workflow-core"
        sub.mkdir(parents=True)
        (sub / ".git").write_text("gitdir: x", encoding="utf-8")
        workflow_hook_git = lambda root, *a: "" if a[:1] == ("fetch",) else (
            "0" if a[:1] == ("rev-list",) else None)
        orig = workflow_hook._git
        workflow_hook._git = workflow_hook_git
        try:
            notice = workflow_hook.check_workflow_updates(
                self._cfg(enabled=True), self.project)
        finally:
            workflow_hook._git = orig
        self.assertIsNone(notice)


class TestBranchDisciplinePostToolUse(BaseCase):
    """PostToolUse nudge when source is edited on a protected branch."""

    def _on_branch(self, name):
        # The temp project isn't a git repo; stub the live-branch read.
        p = mock.patch.object(workflow_hook, "current_branch", lambda root: name)
        p.start()
        self.addCleanup(p.stop)

    def test_source_edit_on_protected_branch_nudges(self):
        self._on_branch("main")
        rc, out = run_hook(self.edit_event("src/a.py"), project_dir=self.project)
        ctx = out["hookSpecificOutput"]["additionalContext"]
        self.assertIn("protected branch `main`", ctx)
        self.assertIn("feature branch", ctx)
        self.assertTrue(workflow_hook.load_state(self.session_id)["branch_nudged"])

    def test_branch_nudge_fires_once(self):
        self._on_branch("main")
        run_hook(self.edit_event("src/a.py"), project_dir=self.project)
        rc, out2 = run_hook(self.edit_event("src/c.py"), project_dir=self.project)
        # Second source edit: branch already nudged and doc already nudged -> silent.
        self.assertIsNone(out2)

    def test_source_edit_on_feature_branch_no_branch_nudge(self):
        self._on_branch("feat/x")
        rc, out = run_hook(self.edit_event("src/a.py"), project_dir=self.project)
        ctx = out["hookSpecificOutput"]["additionalContext"]
        self.assertNotIn("protected branch", ctx)
        self.assertIn("ledger", ctx.lower())  # only the doc/ledger nudge

    def test_non_source_edit_on_main_no_branch_nudge(self):
        self._on_branch("main")
        rc, out = run_hook(self.edit_event("README.md"), project_dir=self.project)
        self.assertIsNone(out)  # non-source path -> no git read, no branch nudge

    def test_disabled_policy_suppresses_branch_nudge(self):
        self._on_branch("main")
        self.write_config({
            "project_root": ".",
            "source_directories": ["src"],
            "documentation_directories": ["docs"],
            "ledger": {"directory": "history"},
            "env_check": {"tool_paths": {}},
            "stop_hook": {"max_blocks": 2, "main_branch": "main"},
            "branch_policy": {"require_feature_branch": False},
        })
        rc, out = run_hook(self.edit_event("src/a.py"), project_dir=self.project)
        ctx = out["hookSpecificOutput"]["additionalContext"]
        self.assertNotIn("protected branch", ctx)  # policy off -> ledger nudge only


class TestStopBranchDiscipline(BaseCase):
    """Stop-hook block for uncommitted source changes on a protected branch."""

    def _seed_state(self, **kw):
        state = workflow_hook.default_state()
        state.update(kw)
        workflow_hook.save_state(self.session_id, state)

    def _run_stop_with_status(self, status):
        orig_git_status = workflow_hook.git_status
        orig_git = workflow_hook._git
        workflow_hook.git_status = lambda project_root: status
        workflow_hook._git = lambda root, *args: (
            " M src/a.py" if args[:1] == ("status",) else None)
        try:
            return run_hook(
                {"hookEventName": "Stop", "session_id": self.session_id},
                project_dir=self.project)
        finally:
            workflow_hook.git_status = orig_git_status
            workflow_hook._git = orig_git

    def test_source_dirty_on_main_blocks_with_branch_message(self):
        # Isolate from the ledger reminder by marking the ledger touched.
        self._seed_state(source_changed=True, ledger_touched=True)
        rc, out = self._run_stop_with_status(
            {"branch": "main", "dirty": True, "ahead": None, "behind": None})
        self.assertEqual(out["decision"], "block")
        self.assertIn("protected branch `main`", out["reason"])
        self.assertIn("feature branch", out["reason"])

    def test_docs_only_dirty_on_main_does_not_block(self):
        self._seed_state(source_changed=False, ledger_touched=True)
        rc, out = self._run_stop_with_status(
            {"branch": "main", "dirty": True, "ahead": None, "behind": None})
        self.assertIsNone(out)  # docs-only on the trunk is exempt

    def test_source_dirty_on_feature_branch_uses_commit_reminder(self):
        self._seed_state(source_changed=True, ledger_touched=True)
        rc, out = self._run_stop_with_status(
            {"branch": "feat/x", "dirty": True, "ahead": None, "behind": None})
        self.assertEqual(out["decision"], "block")
        self.assertIn("commit & push", out["reason"].lower())
        self.assertNotIn("should have been a feature branch", out["reason"])


class TestDryRun(BaseCase):
    def test_dry_run_does_not_mutate_state(self):
        rc, out = run_hook(self.edit_event("src/a.py"), argv=["--dry-run"],
                           project_dir=self.project)
        # Output still computed...
        self.assertIsNotNone(out)
        # ...but no state file written for this session.
        self.assertFalse(workflow_hook.state_path(self.session_id).exists())


if __name__ == "__main__":
    unittest.main()
