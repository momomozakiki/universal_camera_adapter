---
title: Document Provenance Convention
version: 1.0
last_validated: 2026-07-18
official: true
source: project-internal
---

# Document provenance convention

A lightweight adaptation of the provenance-frontmatter idea from the
[`ai-self-correcting-workflow`](https://github.com/momomozakiki/ai-self-correcting-workflow)
repo, scoped to the doc trees where **"is this authoritative?" changes how a reader should trust
and act on the content**:

- `docs/spec/**` — the package specification and architecture baseline.
- `docs/camera/**` — the camera integration architecture and backend setup guides.

It is deliberately **not** applied to ephemeral docs (`docs/plan/`, roadmaps, `history/`) where a
version/validated-date header would just be churn, and it drops the upstream `estimated_tokens`
field (token-budget linting is over-engineering for this repo).

## The frontmatter block

Every doc under the two trees above carries a YAML block as its very first lines:

```yaml
---
title: <human title>
version: <semver-ish; MINOR for content, MAJOR for restructure>
last_validated: YYYY-MM-DD   # date the CONTENT was last confirmed accurate, not merely edited
official: true | false | unknown
source: <see vocabulary>
---
```

### Field rules

- **`last_validated`** — the date a human/agent last confirmed the *content* is accurate. On first
  application it is set to the file's last content-commit date (not "today"), because adding
  frontmatter is not a content review. Refresh it only on a real re-review.
- **`official`** — `true` only for an externally-published standard (e.g. an ONVIF spec) or a
  **governance-approved baseline** (e.g. the camera integration architecture, cited as
  authoritative in `CLAUDE.md`). Self-assessments, drafts, and reference guides authored in-repo are
  `false`. Use `unknown` when origin/authority is genuinely unconfirmed.
- **`source`** — one of:
  - a **URL** — for a doc copied from an external authoritative source (e.g. an ONVIF/RTSP spec);
  - **`project-internal`** — authored inside this repo (human and/or agent); git history is the
    authorship record;
  - **`user-provided`** — supplied by the user, origin unconfirmed;
  - **`agent-generated`** — produced wholesale by an agent with no human authoring pass.

## Rule: confirm before claiming authority

Never mark a doc `official: true` or attach an external `source:` URL on a guess. For any doc
introduced from outside the repo (an ONVIF spec excerpt, a vendor PTZ note), **ask the user**
whether it comes from an official / authoritative source and for the URL before setting these
fields; use `unknown` until confirmed. Fabricating provenance defeats the purpose of tracking it.

## Ownership

This convention is maintained by the **`doc-writer`** agent. When it next reviews a doc, it
refreshes `last_validated` and bumps `version` per the rules above.
