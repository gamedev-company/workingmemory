---
type: meta
tags:
  - system
  - conventions
---

# Working-Memory System Conventions

> Durable substrate of design, decisions, and architectural memory. Read by both human and AI coding agent. The dialectic is the mechanic; knowledge is the output.
>
> This system is purpose-designed for **long-term cognitive assistance across sessions** — what was decided ten sessions ago should still be reachable, not just what's in the current window.

## Tiers

### Long-term (durable)

| Tier | Folder | Purpose |
|------|--------|---------|
| Core | `core/` | Elevator-pitch strata about the project. Where you START orientation, not where you end up on a deep-dive. |
| Reference | `ref/` | Subsystem briefings — gotchas, technical orientation, "before you touch X, know this." |
| Schema | `schema/` | Data shapes — ORM schemas, channel event shapes, persistence models. |
| Senses | `senses/` | The agent's own observations — feature ideas, friction logs, working-relationship notes. Curated and durable. |
| Design | `design/` | Architectural proposals, target shapes, audits. Status: `draft` / `design` / `approved` / `superseded`. |
| Plan | `plan/` | Step-by-step execution playbooks. Status: `new` / `locked` / `implemented` / `finished`. |

### Mid-term (curated, transient)

| Tier | Folder | Purpose |
|------|--------|---------|
| Complications | `complications/` | Q&A docs that complicate ideas before code. Resolved in-place; promoted to `design/` / `ref/` / `plan/` / `core/` when the resolution stands alone as durable knowledge. |
| Journals | `journals/` | Per-day, per-turn record of what was done and why, plus `★ Insight` blocks. Append-only chronological log. |

### Short-term (volatile)

| File | Purpose |
|------|---------|
| `short-term.md` | Rolling working scratchpad. Capped at ~300 lines. Curated, not append-log. The session-boot brief. |

## File Conventions

### Frontmatter

All durable files start with YAML frontmatter:

```yaml
---
type: <core|ref|schema|sense|design|plan|complication|journal>
status: <type-specific>
project: <your-project-name>
updated: YYYY-MM-DD
---
```

| Type | Status values | Required extras |
|------|---------------|-----------------|
| ref | (n/a) | `source:` (path to authoritative code) |
| design | draft / design / approved / superseded | — |
| plan | new / locked / implemented / finished | — |
| complication | open / resolved | `topic:`, `opened:` |
| journal | (n/a) | `date:` |
| core, schema, sense | (n/a) | — |

### Naming

- All files: `kebab-case.md`
- Journals: `journals/YYYY-MM-DD.md`
- Complications: `complications/<topic>.md`

### Cross-references

- `[[wikilinks]]` for in-vault references (Obsidian + grep both resolve them)
- `[text](path)` for code/docs outside the vault

## short-term.md Taxonomy

Each entry: `[YYYY-MM-DD HH:MM] [TAG[:status]] body`

| Tag | Use for |
|-----|---------|
| `STATUS` | Where work currently sits — phase, branch, test counts, what's running where |
| `DECISION` | A choice was made; rationale lives in journal/design, this is the pointer |
| `INSIGHT` | A reframing or non-obvious observation; if durable, graduates to a journal |
| `BLOCKER` | Stops forward progress until unblocked |
| `PLAN:<status>` | Near-term intent. status ∈ `new` / `locked` / `implemented` / `finished` |
| `QUESTION` | Needs an answer; if it accumulates substance, graduates to a complication |
| `HANDOFF` | Note for the next session/agent |

Modifier: `[KEEP]` after the tag exempts the line from automatic rewriting (e.g., `[BLOCKER] [KEEP]`).

The 300-line cap is a guard against bootup token bloat. `short-term.md` is freely rewritten — anything stale is cut, anything durable graduates to the appropriate long-term tier (insight → journal/sense/design; status → updated in place; decision → recorded in journal or design doc). Goal: a clean session boot in ≤300 lines.

## Workflow Patterns

### When an idea surfaces — complicate it

For any non-trivial concept, before code: open or extend `complications/<topic>.md`. Each open question is a section with a yes-and proposed answer. Resolved questions move to `## Resolved` in-place. If the resolutions stand alone as durable knowledge, promote them to the appropriate tier.

### When an insight surfaces — journal it

Every turn produces a journal entry: one-line title + `**What:** / **Why:**` body + optional `### ★ Insight: <title>` subsection. Per-turn cadence — that's where the churn happens. The agent uses its own judgment on what merits durable journaling.

### When a decision is made — short-term.md it

Decisions worth remembering across sessions land in `short-term.md` with `[DECISION]`. Rationale lives in the journal entry or design doc; the short-term entry is the pointer.

### When friction or ideas surface from working — sense it

Things the agent wants to remember about the codebase, the project, or the working relationship across sessions go to `senses/`. These are *the agent's* observations — feature suggestions, bug callouts, ergonomics, "this would be better if…", pain points worth raising. Distinct from `journals/` (chronological, of-the-moment); senses are curated, durable, opinion-bearing.

## Index.md Scope

Index surfaces:

- **Always:** every file in `core/`, `ref/`, `schema/`, `senses/`
- **Selectively:** `design/` and `plan/` entries with active or approved status (or in-progress for plans)
- **Not indexed:** `complications/` (linked from the docs that need them, not surfaced centrally), `journals/` (browse chronologically), `short-term.md` (the working scratch)

## For the AI agent — session lifecycle

1. **At session start:** read `short-term.md` first. Then `Index.md` if you need orientation.
2. **As insights surface:** append to today's `journals/YYYY-MM-DD.md`.
3. **Per turn:** append a one-section summary (What/Why) to today's journal.
4. **Before code on a non-trivial idea:** open or extend a `complications/<topic>.md`.
5. **Before touching a subsystem:** check `ref/`. Before architecting: check `design/` and `core/`.
6. **When suggesting features or noting friction:** write to `senses/`.
7. **When closing a session or hitting context budget:** ensure `short-term.md` reflects what the next session needs to bootstrap. Anything durable beyond that has already been moved to a long-term tier.
