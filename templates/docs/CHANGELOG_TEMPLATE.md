---
title: <Doc Name> Changelog
version: 1.0
last_validated: YYYY-MM-DD
official: false
source: agent-generated
tags: [changelog, episodic, audit]
applies_when: "Never load — episodic doc history for humans and audit only."
exclude_from_ai: true
estimated_tokens: <int>
---

<!--
  SIBLING CHANGELOG (delete this comment before saving)
  - This file is the relocated Revision History for its sibling `index.md`.
    Create it only when a doc folds into a folder (GUIDE.md §6.4): either the doc
    split per the Progressive Disclosure "Rule of One Question" / token budget, or
    its in-file Revision History grew past ~8 rows.
  - It is a SIBLING PEER of `index.md`, not a split-child — do not list it in
    `index.md`'s child index and do not give it a `parent:` link. It only holds
    history.
  - `exclude_from_ai: true` is the machine-readable "never load" flag. The
    Progressive Disclosure retrieval script skips any file carrying it, so its
    `estimated_tokens` never count against the active token budget — only
    `index.md` does.
  - This file is append-only: add the newest row on top, never rewrite old rows.
-->

# <Doc Name> — Full Revision History

| Version | Date       | Change   |
|---------|------------|----------|
| 1.0     | YYYY-MM-DD | Initial. |
