---
name: working-memory
description: Show working-memory vault status, stats, and available operations
allowed-tools: Read Bash Glob
---

# working-memory Vault Status

Show a concise overview of the working-memory vault: tier file counts, short-term cache freshness, today's journal presence, available commands.

## Gather stats

Run these checks (quietly, don't narrate):

- File counts per tier:
  - `core: $(ls working-memory/core/*.md 2>/dev/null | wc -l)`
  - `ref: $(ls working-memory/ref/*.md 2>/dev/null | wc -l)`
  - `schema: $(ls working-memory/schema/*.md 2>/dev/null | wc -l)`
  - `senses: $(ls working-memory/senses/*.md 2>/dev/null | wc -l)`
  - `design: $(ls working-memory/design/*.md 2>/dev/null | wc -l)`
  - `plan: $(ls working-memory/plan/*.md 2>/dev/null | wc -l)`
  - `complications: $(ls working-memory/complications/*.md 2>/dev/null | wc -l)`
  - `journals: $(ls working-memory/journals/*.md 2>/dev/null | wc -l)`
- short-term cache: read `working-memory/short-term.md` `updated:` frontmatter and line count
- today's journal: check if `working-memory/journals/$(date +%Y-%m-%d).md` exists
- Index presence: check if `working-memory/Index.md` exists

## Output format

Compact status card:

```
━━━ working-memory Vault ━━━

core: N    ref: N    schema: N    senses: N
design: N  plan: N   complications: N    journals: N

short-term.md: <line count>/300 lines, updated <date>
today's journal: <✓ present / ✗ not yet>
Index: <✓ present / ✗ missing>

Commands:
  /working-memory-update  Refresh short-term.md
  /working-memory-lint    Vault health check

Entry points:
  working-memory/System.md         Conventions
  working-memory/Index.md          Map of Content
  working-memory/short-term.md     Session-boot brief
```

If `short-term.md` is missing or stale (`updated:` older than today), suggest `/working-memory-update`.
If today's journal is missing, mention it (per-turn journaling is the system convention).
If lint hasn't been run recently, suggest `/working-memory-lint`.

Keep output under 20 lines. Status snapshot, not full report.
