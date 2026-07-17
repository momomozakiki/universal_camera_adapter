---
title: <Title>
version: 1.0
last_validated: YYYY-MM-DD
official: false
source: agent-generated
tags: [<retrieval-tags>]
applies_when: "<one line: when is this doc the right thing to load?>"
estimated_tokens: <int>
---

<!--
  HOW TO USE THIS TEMPLATE (delete this comment before saving)
  - Copy this file into your documentation directory and fill every <placeholder>.
  - Frontmatter fields (see GUIDE.md §6):
      title           Human title, matches the H1 below.
      version         MAJOR.MINOR. Bump MINOR for content, MAJOR for a restructure.
      last_validated  Date you last confirmed the content is correct (YYYY-MM-DD).
      official        true  = reviewed/approved via governance (e.g. GUIDE.md, ADRs)
                      false = draft / agent-generated / notes / checkpoint
                      unknown = origin not yet confirmed
      source          URL | agent-generated | user-provided, origin unknown
      tags            Lowercase retrieval tags used by the Progressive Disclosure script.
      applies_when    When this doc should be pulled into context.
      estimated_tokens  Honest token estimate; feeds retrieval + the token-budget lint.
  - On every non-trivial edit: bump version, refresh last_validated, add a Revision History row.
  - JSON / code files can't hold frontmatter — use a sidecar <file>.prov.md instead (GUIDE.md §6.2).
  - If this doc grows past its layer's token budget or covers more than one question,
    split it per docs/Progressive Disclosure Documentation Guide.md (§2, §5).

  FOLDING INTO A FOLDER + RELOCATING HISTORY (GUIDE.md §6.4)
  When this doc splits, OR its Revision History exceeds ~8 rows (history now rivals
  content), fold `<name>.md` into `<name>/` and move the history out:
    1. Replace the full Revision History table in `index.md` with this lean format
       (latest ≤3 rows + a link — nothing older stays in index.md):
         ## Revision History
         | Version | Date | Change |
         |---------|------|--------|
         | 2.5     | ...  | Latest |
         | 2.4     | ...  | ...    |
         | 2.3     | ...  | ...    |
         [Full history in `CHANGELOG.md`](CHANGELOG.md)
    2. The sibling `CHANGELOG.md` (copy templates/docs/CHANGELOG_TEMPLATE.md) holds
       the full, un-truncated Revision History table. It is a SIBLING PEER of
       index.md, not a split-child (no `parent:` link, not in the child index).
    3. Recalculate index.md's `estimated_tokens` DOWNWARD (it drops substantially).
       The CHANGELOG.md tokens are EXCLUDED from the active token budget (it carries
       `exclude_from_ai: true`); only index.md counts.
-->

# <Title>
**Version 1.0** — *<one-line scope>*

## Revision History
| Version | Date       | Change   |
|---------|------------|----------|
| 1.0     | YYYY-MM-DD | Initial. |

---

<!-- Document body starts here. Keep it answering one clear question. -->
