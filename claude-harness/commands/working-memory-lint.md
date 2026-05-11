---
name: working-memory-lint
description: Check working-memory vault health — broken links, missing frontmatter, stale refs, orphaned files, short-term.md cap
allowed-tools: Read Glob Grep Bash
---

# working-memory Vault Lint

Audit the `working-memory/` vault for structural health. Run all checks below, then report a summary table followed by details for each finding.

## Checks to Perform

### 1. Missing Frontmatter

Scan every `.md` file in `working-memory/` (excluding `templates/` and `.obsidian/`). Flag any file that does not start with a `---` YAML frontmatter block.

### 2. Incomplete Frontmatter

For files WITH frontmatter, verify type-appropriate required fields:
- **`type: ref`** must have `source:` field
- **`type: design`** must have `status:` (draft / design / approved / superseded)
- **`type: plan`** must have `status:` (new / locked / implemented / finished)
- **`type: complication`** must have `topic:`, `opened:`, and `status:` (open / resolved)
- **`type: journal`** must have `date:` field
- **All types** should have `project:` field

### 3. Broken Wikilinks

Find all `[[wikilink]]` references across the vault. For each, verify the target file exists. Wikilinks resolve to `working-memory/<path>.md`.

### 4. Orphaned Files

Compare files in *durable* tiers (`core/`, `ref/`, `schema/`, `senses/`) and *active* design/plan entries against entries in `working-memory/Index.md`. Flag files that exist but are not referenced. Exclude: `System.md`, `Index.md`, `short-term.md`, files in `templates/`, files in `complications/` (linked inline, not via Index per [[System]]), files in `journals/` (chronological, not indexed).

### 5. Stale Refs

For each file in `working-memory/ref/`, read the `source:` frontmatter field. Check if that path still exists in the project. Flag refs whose source paths are missing.

### 6. Index Drift

Read `working-memory/Index.md` and extract all `[[wikilink]]` entries. Verify each linked file exists. Flag entries that point to non-existent files.

### 7. short-term.md Cap

Count lines in `working-memory/short-term.md`. Flag if over 300.

### 8. Today's Journal

Check whether `working-memory/journals/$(date +%Y-%m-%d).md` exists. If not, surface as a soft warning (not a structural error — the day may not have started a turn yet).

## Output Format

```
| Check                  | Issues |
|------------------------|--------|
| Missing frontmatter    | N      |
| Incomplete frontmatter | N      |
| Broken wikilinks       | N      |
| Orphaned files         | N      |
| Stale refs             | N      |
| Index drift            | N      |
| short-term.md cap      | N      |
| Today's journal        | N      |
| **Total**              | **N**  |
```

Then list details for each category that has issues. If all checks pass, say so.

## After the Audit

If issues are found, ask whether to fix them. Common auto-fixes:
- Add missing frontmatter from file content (infer type from location)
- Add orphaned files to Index.md
- Remove dead Index entries
- Update stale ref source paths
- Trim `short-term.md` by promoting durable entries to long-term tiers
