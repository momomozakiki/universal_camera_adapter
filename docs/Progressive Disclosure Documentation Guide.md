---
title: The Progressive Disclosure Documentation Guide
version: 4.2
last_validated: 2026-07-11
official: true
source: agent-generated
tags: [documentation, progressive-disclosure, ai-context, token-budget, retrieval]
applies_when: "Designing, reviewing, or refactoring documentation structure for AI-assisted projects."
estimated_tokens: 3900
---

# The Progressive Disclosure Documentation Guide (v4.2)
### A Complete, Production-Ready Standard for AI-Assisted Projects

## Revision History
| Version | Date       | Change                                                                                          |
|---------|------------|-------------------------------------------------------------------------------------------------|
| 4.2     | 2026-07-11 | Harvested net-new content from an incoming "AI-Oriented Documentation" guide: §3.1 optional distributed **`SCOPE.md`** scaling tier; §5.1 content-quality rules (Show-Don't-Tell, textual-twin diagrams); §7.E Module Doc / `SCOPE.md` template. Additive subsections only — top-level numbering unchanged. |
| 4.1     | 2026-07-10 | Added the per-doc **`CHANGELOG.md`** convention: relocated Revision History as an Episodic sibling (§4 taxonomy row, §9); `load_md_files()` now skips `exclude_from_ai: true` files before scoring. |
| 4.0     | 2026-07-10 | Adopted as the repo's canonical splitting standard (GUIDE.md §6.4 references it); added this frontmatter + Revision History; §7 templates aligned to the unified Documentation Standard fields. |

---

## 1. Core Philosophy

Disk space is infinite. **Context windows are not.** 

If you load a monolithic document into every prompt, the AI suffers from the "lost-in-the-middle" effect—its adherence to every rule degrades uniformly. 

**The Paradigm Shift:** Move from *Memorization* (loading everything) to *Retrieval* (loading exactly what is needed for the current task).

**The Golden Rule:** Your *active* documentation—the core files loaded for a standard task—must fit comfortably within **6,000 to 8,000 tokens**.

---

## 2. The Four-Layer Architecture (Hard Token Budgets)

Organize your knowledge into four distinct layers. Each has a strict purpose and a maximum token limit.

| Layer | Purpose | Max Tokens | Example File |
| :--- | :--- | :--- | :--- |
| **1. Working Memory** | *Dynamic.* Current session state, active goals, and immediate blockers. | ≤ **1,500** | `CONTEXT.md` |
| **2. Procedural Memory** | *Static.* Immutable global rules, coding standards, and master navigation. | ≤ **2,000** | `AGENTS.md` |
| **3. Semantic Memory** | *Modular.* Long-term facts (architecture, data models, API specs). Loaded on-demand. | ≤ **5,000** *per file* | `.docs/knowledge/*.md` |
| **4. Episodic Memory** | *Archived.* Raw chat logs for human auditing. **Never loaded into AI context.** | N/A | `.docs/sessions/archive/` |

---

## 3. The Static vs. Dynamic Boundary

To prevent overlap and bloat, enforce a rigid separation:

- **`AGENTS.md` (Static):** Contains your Top 5 non-negotiable rules, the master navigation table, and high-level architectural tenets. **Update this only when the project's foundation changes** (e.g., switching from REST to GraphQL).
- **`CONTEXT.md` (Dynamic):** Contains the current Sprint Goal, live task checklist (`[x]`/`[ ]`), and decisions made *during the ongoing session*. **Update this at the end of every major AI interaction.**

### 3.1 Optional scaling tier: the distributed `SCOPE.md` network

§3 draws the static/dynamic line; `SCOPE.md` is the **static, per-directory
extension** of it. Root `CONTEXT.md` describes the whole project's working context.
As a project grows, one file can no longer honestly describe every major subtree, so
per-directory `SCOPE.md` files carry static context for those large-scale cases.

| File | Nature | Scope | Answers |
| :--- | :--- | :--- | :--- |
| Root `CONTEXT.md` | **Dynamic** working memory | Whole project, current session | "What are we doing *right now*?" |
| Per-dir `SCOPE.md` | **Static** structural scope | One directory's responsibility | "What is *this directory* for, and what are its boundaries?" |

A `SCOPE.md` sits in a significant directory and states that directory's purpose, its
key files/responsibilities, and links to any child `SCOPE.md` files — forming a
navigable tree the agent can crawl to scope a change without loading the whole repo.

**When to scale (qualitative — no hard thresholds):** Default to the root
`CONTEXT.md` alone. Introduce `SCOPE.md` files **only** when a single root file can no
longer honestly describe each major subtree — typically monorepos or repos with
several independently-owned packages/services. For small-to-medium projects, adding
them is premature and just more surface to keep current. A `SCOPE.md` is static: update
it when a directory's *responsibility* changes, not on every task.

> **Naming discipline.** The distributed file is `SCOPE.md`, never `CONTEXT.md`.
> `CONTEXT.md` is reserved for the single root dynamic working-memory file (§2, §3);
> reusing that name per-directory would give one filename two opposite meanings and
> confuse both readers and the retrieval script.

---

## 4. Content Strategy: The Lifespan Taxonomy

Not all documentation is created equal. Separate content based on its *expiration date*:

| Category | Lifespan | Location | Action on Expiry |
| :--- | :--- | :--- | :--- |
| **Knowledge** | Permanent until refactored. | `.docs/knowledge/` | Keep indefinitely. |
| **ADRs (Decisions)** | Permanent historical record. | `.docs/decisions/` | Keep indefinitely. |
| **Checkpoints** | Feature lifetime. | `.docs/checkpoints/` | Review when feature ships. Promote to ADR if structural; otherwise, delete. |
| **Incidents (Bug Fixes)** | Short-lived (≤ 3 months). | `.docs/incidents/` | Auto-delete after expiry using a cron job or manual purge. |
| **Per-doc changelog** | Append-only for the doc's life. | `<doc>/CHANGELOG.md` (sibling of `index.md`) | Never loaded (Episodic — see §9); keep for human audit. Relocated here when a doc folds into a folder. |

---

## 5. Atomicity: The "Rule of One Question"

How do you know when to split a giant doc or merge tiny ones?

- **The Rule:** A single note must fully answer **one specific "How-to" or "What-is" question** without requiring a second note, *unless* that second note is a clearly linked dependency (e.g., "To understand API pagination, you must first view the Data Model").
- **The Merge Signal:** If you consistently copy-paste the *same 3 notes* together for every single task, merge them into one comprehensive "Combo" note to save retrieval overhead.

### 5.1 Content quality rules (writing for AI accuracy)

Atomicity governs a doc's *size*; these rules govern its *content*. They make a note
legible to an AI, not just short.

- **Show, don't just tell.** Prefer a concrete example over prose. When a rule has a
  right and a wrong way, show **both**, and anchor each to the **real file path** where
  it lives so the AI can locate the pattern:

  ~~~markdown
  ## Auth middleware (`src/middleware/auth.ts`)
  ✅ Correct
  ```ts
  // Validates JWT and attaches user to request
  export const auth = /* … */
  ```
  ❌ Incorrect
  ```ts
  // Never skip token verification
  export const auth = (req, res, next) => next()
  ```
  ~~~

- **Diagrams need a textual twin.** An AI cannot reliably read a raster image. Prefer
  **Mermaid** (plain text the model parses directly). If you must embed an image,
  place a detailed alt-text or a bulleted summary of the flow directly beneath it, so
  the information survives even when the visual does not.

---

## 6. The Retrieval Mechanism

**Crucial:** Do not assume the AI can "browse" your file system. You must explicitly fetch the right files before sending the prompt.

### Strategy A: Manual Workflow
The developer reads `AGENTS.md`, finds the relevant link (e.g., `db-indexing.md`), and manually pastes that file's content into the chat alongside their query.

### Strategy B: Automated Retrieval (Recommended)
Use the script below. It scans YAML frontmatter and content, scores relevance using weighted signals (tag matches = 3x, keyword matches = 1x), enforces token caps, and supports monorepo scoping.

```python
#!/usr/bin/env python3
"""
Progressive Disclosure Retrieval Script (v4.0)
Usage: python retrieve.py --query "optimize postgres" --tags postgres performance --scope backend
"""
import os
import glob
import yaml
import re
import argparse

# --- For CI Linting (Precise Token Counting) ---
# Uncomment for production CI enforcement:
# import tiktoken
# enc = tiktoken.encoding_for_model("gpt-4")

# --- Optional: For Semantic Search ---
# Uncomment for embedding-based retrieval (adds ~5ms latency per doc):
# from sentence_transformers import SentenceTransformer, util
# model = SentenceTransformer('all-MiniLM-L6-v2')

def load_md_files(directory=".docs", scope=None):
    """Load all markdown files, gracefully handling missing or malformed YAML."""
    docs = []
    search_path = f"{directory}/{scope}/**/*.md" if scope else f"{directory}/**/*.md"
    
    for file in glob.glob(search_path, recursive=True):
        with open(file, 'r', encoding='utf-8') as f:
            content = f.read()
        
        frontmatter = {}
        clean_content = content
        
        if content.startswith('---'):
            parts = content.split('---', 2)
            if len(parts) >= 3:
                try:
                    frontmatter = yaml.safe_load(parts[1]) or {}
                    clean_content = parts[2].strip()
                except yaml.YAMLError:
                    pass  # Graceful fallback for malformed YAML
        
        # Episodic tier: never load files explicitly flagged out of AI context
        # (e.g. a doc's sibling CHANGELOG.md). See §4, §9, and GUIDE.md §6.4.
        if frontmatter.get('exclude_from_ai'):
            continue
        
        docs.append({
            "path": file,
            "content": clean_content,
            "meta": frontmatter,
            "tokens": frontmatter.get('estimated_tokens', 500)
        })
    return docs

def retrieve_relevant(query, tags=None, docs=None, top_k=3, max_tokens=5000):
    """Score, rank, and select documents based on relevance and token budget."""
    if docs is None:
        docs = load_md_files()
    if tags is None:
        tags = []
    
    scored = []
    query_terms = set(re.findall(r'\w+', query.lower()))
    
    for doc in docs:
        score = 0
        meta = doc['meta']
        
        # 1. Tag Overlap (Weight: 3x) - Highest precision
        doc_tags = set(meta.get('tags', []))
        score += len(doc_tags.intersection(set(tags))) * 3
        
        # 2. Applies_When Context (Weight: 2x)
        applies = meta.get('applies_when', '').lower()
        if any(term in applies for term in query_terms):
            score += 2
        
        # 3. Term Frequency (Weight: 1x) - Baseline fallback
        content_words = set(re.findall(r'\w+', doc['content'].lower()))
        score += len(content_words.intersection(query_terms)) * 1
        
        # 4. Semantic Similarity (Weight: 5x) - Opt-in
        # Uncomment the block below and ensure 'model' is loaded.
        # if 'model' in globals() and query_terms:
        #     query_emb = model.encode(query)
        #     doc_emb = model.encode(doc['content'][:500])
        #     score += util.cos_sim(query_emb, doc_emb).item() * 5
        
        scored.append((score, doc))
    
    # Sort by score descending, then by token size ascending (cheapest first)
    scored.sort(key=lambda x: (-x[0], x[1]['tokens']))
    
    # Select top_k while enforcing total token limit
    selected, total_tokens = [], 0
    for _, doc in scored[:top_k]:
        if total_tokens + doc['tokens'] <= max_tokens:
            selected.append(doc)
            total_tokens += doc['tokens']
        else:
            break
    
    return selected

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Retrieve relevant documentation for AI context.")
    parser.add_argument("--query", required=True, help="The user's question or task description.")
    parser.add_argument("--tags", nargs="+", default=[], help="Target tags for high-precision filtering.")
    parser.add_argument("--scope", default=None, help="Subdirectory scope for monorepos (e.g., 'backend').")
    parser.add_argument("--top_k", type=int, default=3, help="Maximum number of files to retrieve.")
    args = parser.parse_args()
    
    docs = load_md_files(scope=args.scope)
    results = retrieve_relevant(args.query, args.tags, docs, top_k=args.top_k)
    
    print("\n📄 Documents to load into AI context:\n")
    for r in results:
        print(f"  • {r['path']} (Tokens: {r['tokens']})")
    
    total = sum(r['tokens'] for r in results)
    print(f"\n✅ Total tokens: {total} (Limit: 5000)")
```

---

## 7. Templates for Every File Type

Copy and paste these templates to standardize your documentation. Each carries the
unified **Documentation Standard** fields (`version`, `last_validated`, `official`,
`source`) from `GUIDE.md` §6 **plus** the retrieval/lifespan fields specific to its
type. Bump `version` and refresh `last_validated` on every non-trivial edit.

### A. Knowledge Note (`.docs/knowledge/backend/db-indexing.md`)
```yaml
---
title: Postgres Indexing Strategy
version: 1.0
last_validated: 2026-07-10
official: false
source: agent-generated
category: Database
tags: [postgres, indexing, performance]
applies_when: "Creating new tables or troubleshooting slow queries"
estimated_tokens: 450
---
# Postgres Indexing Strategy
[Full, detailed content answering "How do we index?"]
```

### B. Incident Note (`.docs/incidents/2026-07-10_auth-null.md`)
```yaml
---
title: Auth Null Pointer Fix
version: 1.0
last_validated: 2026-07-10
official: false
source: agent-generated
type: incident
tags: [auth, bugfix]
expires_on: 2026-10-10
estimated_tokens: 200
---
# Auth Null Pointer Fix
**Symptom:** Login failed with 500 error.
**Root Cause:** Missing validation on `req.user.id`.
**Fix:** Added validation in line 42 of `auth.ts`.
```

### C. Checkpoint (`.docs/checkpoints/feature-payment.md`)
```yaml
---
title: Payment Webhook — Checkpoint
version: 1.0
last_validated: 2026-07-10
official: false
source: agent-generated
type: checkpoint
feature: Payment Webhook
status: Completed
estimated_tokens: 300
---
**Goal:** Implement Stripe retry logic.
**Attempted:** Approach A (setTimeout) → Failed due to process death.
**Chosen:** Approach B (BullMQ).
**Open Questions:** Should we alert Slack on final failure?
```

### D. Decision Record / ADR (`.docs/decisions/adr-004-redis-cache.md`)
```yaml
---
title: "ADR-004: Adopt Redis for Session Caching"
version: 1.0
last_validated: 2026-07-10
official: true
source: agent-generated
type: adr
status: Accepted
date: 2026-07-10
estimated_tokens: 400
---
# ADR-004: Adopt Redis for Session Caching
**Context:** Postgres was hitting connection limits under load.
**Decision:** Use Redis for ephemeral session storage.
**Consequences:** Reduced DB load by 40%; requires new Redis cluster setup.
```

### E. Module Doc / `SCOPE.md` (`src/payment/SCOPE.md`)
A directory's static scope file (§3.1). It states the directory's purpose, its
boundaries, and an explicit **DO/DON'T block** the agent must honour. On conflict,
global rules in the project's `CLAUDE.md` / `AGENTS.md` win.
```yaml
---
title: Payment Module — Scope
version: 1.0
last_validated: 2026-07-10
official: false
source: agent-generated
type: scope
tags: [payment, module]
applies_when: "Editing anything under src/payment/"
estimated_tokens: 250
---
# Payment Module (`src/payment/`)
**Purpose:** All payment-processing logic and provider integrations.
**Key files:** `service.ts` (public interface), `stripe.ts` (provider adapter).
**Child scopes:** [webhooks/SCOPE.md](./webhooks/SCOPE.md)

## 🤖 AI Rules for This Module
- ✅ DO use the `PaymentService` interface for all payment logic.
- ❌ DON'T import `Stripe` directly outside `src/payment/`.
- ❌ DON'T add fields to `User` without updating the privacy audit.
```

---

## 8. Automation & Garbage Collection Routines

Documentation rots if not pruned. Implement these routines:

1.  **Checkpoint Automation:** At the end of every major session, prompt the AI: *"Summarize this session into a Checkpoint. Update CONTEXT.md with our current progress."*
2.  **The Friday Purge (Cron job or manual):**
    - Run a script that deletes all `/incidents` files where `expires_on` is older than today.
    - Review `/checkpoints` for shipped features. If the checkpoint contains a breakthrough insight, promote it to an ADR. If not, delete it.
3.  **PR Linting:** Add a CI step that runs a token-count linter on `AGENTS.md`. If it exceeds 2,000 tokens, the PR fails with: *"AGENTS.md is overloaded. Split this into modular knowledge files."*
    - *Implementation hint:* Use the `tiktoken` library (`enc.encode(content)`) for precise counting in CI.

---

## 9. Episodic Memory: What to Do with Raw Logs

The `.docs/sessions/archive/` folder stores raw chat transcripts. 

- **Purpose:** Human post-mortem analysis and onboarding new team members.
- **Rule:** These logs are **never** loaded into the AI's context. They are for forensic reference only. Summarize them into Checkpoints if they contain reusable insights.

### Per-document changelogs belong here too

When a document folds into a folder (see `GUIDE.md` §6.4 — triggered by a split or
by its in-file **Revision History** table outgrowing its content), the full history
is relocated to a sibling `CHANGELOG.md` next to `index.md`. That changelog is
Episodic: it carries `applies_when: "Never load…"` **and** the machine-readable
`exclude_from_ai: true` flag. The retrieval script in §6 skips any file carrying
that flag *before scoring*, so a doc's history never competes for the active token
budget — only its lean `index.md` does. The `CHANGELOG.md` is a **sibling peer** of
`index.md` (not a split-child): it is not listed in `index.md`'s child index and
carries no `parent:` link; it only holds history.

---

## 10. Final Directory Tree

```text
project-root/
├── AGENTS.md               # Static Procedural (≤ 2,000 tokens)
├── CONTEXT.md              # Dynamic Working Memory (≤ 1,500 tokens)
├── .docs/
│   ├── knowledge/          # Semantic Memory (Permanent facts)
│   │   ├── architecture/
│   │   ├── api-specs/
│   │   └── coding-standards/
│   ├── decisions/          # Permanent ADRs
│   │   └── adr-xxx-title.md
│   ├── checkpoints/        # Temporary AI reasoning snapshots
│   │   └── 2026-07-10_payment-webhook.md
│   ├── incidents/          # Bug fixes (Auto-delete after 3 months)
│   │   └── 2026-07-10_auth-bug.md
│   ├── knowledge/db-tuning/ # A doc that FOLDED into a folder (GUIDE.md §6.4)
│   │   ├── index.md        #   canonical, lean; keeps only the latest ≤3 history rows
│   │   └── CHANGELOG.md    #   Episodic sibling: full history, exclude_from_ai: true
│   └── sessions/           # Episodic (Human auditing ONLY)
│       ├── raw_logs/
│       └── archive/
└── README.md               # For humans, not the AI
```

---

## 11. Migration Path (Rolling This Out)

You don't need to refactor everything on Day 1. Follow this 3-week rollout:

- **Week 1:** Create `AGENTS.md` with your Top 5 rules. Stop writing long documents; start writing small atomic notes for *new* features only.
- **Week 2:** When you need to touch an old, monolithic document, *split it* at that moment. Apply the "Leave it better than you found it" principle.
- **Week 3:** Enable the Friday Purge for `/incidents` and stale `/checkpoints`. Enforce the PR linter.

---

## 12. IDE & Tooling Integration

- **Cursor / Windsurf:** Use the `@` symbol to explicitly reference a specific knowledge file when asking a question (e.g., `@db-indexing How do I add a composite key?`).
- **Git Hooks:** Add a pre-commit hook that blocks commits containing any `.md` file over 5,000 tokens, forcing developers to atomize early.

---

## 13. Final Rule of Thumb

If you cannot load your entire active documentation folder (`AGENTS.md` + `CONTEXT.md` + the 2–3 reference files retrieved for a task) into a standard 8k-token model context, **your documentation is too bloated**.

Treat your documentation like code: refactor it regularly, prune dead branches (incidents), and promote successful experiments (checkpoints to ADRs). This is not a set-it-and-forget-it archive; it is a **living knowledge system** that grows smarter and leaner alongside your project.

---

**End of Guide.**