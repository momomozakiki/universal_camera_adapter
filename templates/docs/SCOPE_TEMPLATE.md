---
title: <Directory Name> — Scope
version: 1.0
last_validated: YYYY-MM-DD
official: false
source: agent-generated
type: scope
tags: [<module-tags>]
applies_when: "Editing anything under <relative/dir/path>/"
estimated_tokens: <int>
---

<!--
  SCOPE.md — per-directory STATIC context (Progressive Disclosure Guide §3.1)
  (delete this comment before saving)

  WHEN TO USE THIS TEMPLATE
  - This is an OPTIONAL scaling tier. Default to a single root CONTEXT.md.
  - Add SCOPE.md files ONLY when a repo is large enough that one root file can no
    longer honestly describe each major subtree (monorepos / independently-owned
    packages). For small-to-medium projects, skip it.

  NAMING DISCIPLINE
  - This file is SCOPE.md, never CONTEXT.md.
  - CONTEXT.md is reserved for the single ROOT dynamic working-memory file.
  - SCOPE.md is STATIC: update it when this directory's RESPONSIBILITY changes,
    not on every task.

  FRONTMATTER: same Documentation Standard fields as any doc (GUIDE.md §6);
  `type: scope` marks the retrieval category.
-->

# <Directory Name> (`<relative/dir/path>/`)
**Purpose:** <one line: what this directory is responsible for>
**Key files:** `<file>` (<role>), `<file>` (<role>)
**Child scopes:** [<subdir>/SCOPE.md](./<subdir>/SCOPE.md)

## 🤖 AI Rules for This Module
On conflict, global rules in the project's `CLAUDE.md` / `AGENTS.md` win.

- ✅ DO <the required pattern for this module>.
- ❌ DON'T <the forbidden pattern / leaky boundary>.
- ❌ DON'T <change that requires a cross-cutting update elsewhere>.
