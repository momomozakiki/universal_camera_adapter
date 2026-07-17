# Universal Camera Adapter — Documentation

Index of the package documentation, grouped by theme. Filenames are kebab-case; the authoritative
"where are we" tracker is [`plan/ROADMAP.md`](plan/ROADMAP.md).

Documentation conventions (frontmatter provenance + version, the weekly change ledger, and
progressive-disclosure folding) are adopted from the
[`ai-self-correcting-workflow`](https://github.com/momomozakiki/ai-self-correcting-workflow); see
[`DOC-PROVENANCE.md`](DOC-PROVENANCE.md) for how provenance is applied here.

## spec/ — specification & architecture
- _(reserved)_ — the package contract spec and settled architecture decisions live here as the
  API matures. The canonical contract today is `lib/src/camera_adapter.dart` and the README.

## camera/ — camera integration architecture & backend guides
- [`camera-integration-architecture.md`](camera/camera-integration-architecture.md) — what ships
  today (`FlutterCameraAdapter`), the extension point for new backends, and the ONVIF plan.
  Authoritative for the hardware-access layer's shape.
- [`onvif-setup-guide.md`](camera/onvif-setup-guide.md) — setup + network-permission requirements
  for the (planned) ONVIF/IP-camera backend: Android `INTERNET`/`CHANGE_WIFI_MULTICAST_STATE`,
  Windows UDP 3702 firewall, RTSP/TCP transport.

## plan/ — active planning & tracking
- [`ROADMAP.md`](plan/ROADMAP.md) — the canonical, checkable "where are we" tracker. The
  `**Next action:**` line is auto-surfaced into context at the start of every session by
  `.claude/hooks/workflow_hook.py`. Follow it top-down.

## operations/ — running & maintaining the package
- _(reserved)_ — release/publish checklists and cross-machine dev notes land here as needed.

## Conventions reference (adopted from workflow-core)
- [`Progressive Disclosure Documentation Guide.md`](Progressive%20Disclosure%20Documentation%20Guide.md)
  — when a flat doc folds into a folder; the "Rule of One Question" and token budgets.
- [`claude-code-hook-integration.md`](claude-code-hook-integration.md) — how the SessionStart /
  PostToolUse / Stop hooks integrate with Claude Code.
- [`DOC-PROVENANCE.md`](DOC-PROVENANCE.md) — the provenance-frontmatter policy for this repo.
