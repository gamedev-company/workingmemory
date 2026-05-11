---
name: working-memory-update
description: Refresh working-memory/short-term.md with current session context for continuity across sessions
allowed-tools: Read Write Glob Grep
---

# Refresh Short-Term Memory

Refresh `working-memory/short-term.md` with the current session state. This file bridges sessions — the next conversation reads it first to bootstrap context efficiently.

## Process

1. Read the current `working-memory/short-term.md` to see what's cached.
2. Read recent `working-memory/journals/` entries (today + last 1-2 days) for additional context.
3. Rewrite `working-memory/short-term.md` to reflect current state, organized into sections:
   - **Active** — current STATUS, in-flight PLAN entries, live BLOCKERs
   - **Key Context** — durable facts (toolchain, conventions) tagged `[KEEP]`
   - **Cross-cutting follow-ups** — HANDOFFs that should survive the session boundary
   - **Where to go first (deeper reads)** — wikilinks to the most relevant durable docs

## Format

Each entry: `[YYYY-MM-DD HH:MM] [TAG[:status]] body`

Tags: `STATUS`, `DECISION`, `INSIGHT`, `BLOCKER`, `PLAN:<new|locked|implemented|finished>`, `QUESTION`, `HANDOFF`. Modifier `[KEEP]` after the tag exempts a line from automatic rewriting. See [[System]] for the full taxonomy.

## Rules

- **Curate, don't accumulate.** `short-term.md` is rewritten freely — stale STATUS/PLAN entries are removed; durable INSIGHT/DECISION entries graduate to journals or long-term tiers *before* removal.
- **Cap: ~300 lines.** If it's longer, you're caching too much — push durable knowledge into long-term tiers.
- **Update the `updated:` field** in frontmatter to today's date.
- **Be concrete.** File paths, function names, error messages, branch names — not "made progress on the backend."
