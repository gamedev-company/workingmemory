# working-memory-kit

> A durable cognitive-prosthetic system for AI-agent-driven projects. Installable in any project with one command.

The `working-memory/` vault is the external memory for an AI coding agent across sessions — the durable substrate of decisions, design, and architectural memory. This kit packages the convention + (optionally) Claude Code harness glue so you can drop it into any project.

## New in 0.3 — one-command recall setup (macOS)

The recall layer is no longer a manual, machine-specific chore. It now ships **inside
the vault** at `working-memory/okf-postgres/`:

- **Scripted setup.** A **doctor** verifies/installs Ollama + models, Postgres +
  pgvector, the database + schema, and the Python venv; an **ingest** script
  inventories a repo into knowledge cards. The installer **offers to run them at the
  end** so you go from `install.sh` to a fully-indexed codebase in one sitting.
- **Per-project, collision-proof databases.** Each repo gets a uniquely-named
  database (`okf_<slug>_<hash>`); setup **refuses** to touch a database it didn't
  create, so it can't clobber existing data. Override with `--db NAME`.
- **Live dashboard.** A self-refreshing HTML view of the index (what's mapped, what's
  drifted) — no web server. See the [Recall layer](#recall-layer-optional-macos) below.

macOS-only for now.

## Documentation

- **[WALKTHROUGH.md](WALKTHROUGH.md)** — end-to-end, zero → indexed codebase → live
  dashboard, with every command and what to expect.
- **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** — fixes for the common snags (Ollama,
  Postgres.app, models, the db guard, the dashboard, MCP wiring).
- **[CHANGELOG.md](CHANGELOG.md)** — what changed across releases.
- `working-memory/okf-postgres/`[`README.md`](content/working-memory/okf-postgres/README.md)
  — the recall layer's design + reference.

## New in 0.2 — OKF + Postgres recall

Two upgrades, both backward-compatible:

- **OKF-aligned frontmatter.** The vault is now an [Open Knowledge Format](https://cloud.google.com/blog/products/data-analytics/how-the-open-knowledge-format-can-improve-data-sharing)
  producer — durable docs lead with OKF's structured fields (`type`, `title`,
  `description`, `tags`, `timestamp`, `resource`), keeping `status`/`project` as
  kit extensions. Old `updated:` / `source:` still work. See `working-memory/System.md`.
- **Optional recall layer ([`working-memory/okf-postgres/`](content/working-memory/okf-postgres/README.md)).** Adds a
  Postgres + pgvector index *under* the markdown: a small local model writes
  per-folder `feature-card` code maps on git commit, and any model recalls them
  over MCP (`memory_recall`) — with a git-SHA freshness contract — instead of
  re-reading source every session. The base kit still works as a pure file
  convention without it.

## What you get

**Content** (agent-agnostic — works with Claude Code, Cursor, Aider, or no agent):

- `working-memory/System.md` — taxonomy reference
- `working-memory/Index.md` — Map-of-Content template
- `working-memory/short-term.md` — rolling session-boot brief, capped at ~300 lines
- Tier directories: `core/`, `ref/`, `schema/`, `senses/`, `design/`, `plan/`, `complications/`, `journals/`
- A "Documentation Discipline" section appended to your `CLAUDE.md` (idempotent, bounded by sentinel markers)

**Claude Code harness** (auto-installed if `.claude/` exists in target):

- `.claude/hooks/working-memory-stale-hot.sh` — Stop hook nudging the agent to refresh `short-term.md` after 15 idle turns
- `.claude/commands/working-memory.md` — `/working-memory` slash command (vault status)
- `.claude/commands/working-memory-lint.md` — `/working-memory-lint` (vault health check)
- `.claude/commands/working-memory-update.md` — `/working-memory-update` (refresh `short-term.md`)
- `.claude/settings.local.json` patched to register the Stop hook (merged via `jq`)

**Optional extras:**

- `--with-agents` — installs `.claude/agents/journalist.md`, a Haiku 4.5 per-turn journal writer
- `--with-obsidian` — installs the `working-memory/.obsidian/` vault config so the directory works as a first-class Obsidian vault

## Why this exists

Default agent memory dies at the end of each session. You can dump everything into one CLAUDE.md, but it scales badly: too much, too unstructured, no signal-to-noise discipline. This kit imposes a structure that's been tested across multi-month projects:

- **Short-term** (`short-term.md`) — what bootstraps the next session in ≤300 lines
- **Mid-term** (`complications/`, `journals/`) — open dialectic + chronological record
- **Long-term** (`core/`, `ref/`, `schema/`, `senses/`, `design/`, `plan/`) — durable knowledge by purpose

The discipline rule (added to `CLAUDE.md` by the installer) tells the agent to read `short-term.md` first, journal per turn, complicate before code, and refresh `short-term.md` at session boundaries. Without that rule the agent doesn't know to consult the vault — so the `CLAUDE.md` patch is the one mandatory bit.

## Install

### One-liner (clone + install)

```bash
git clone https://github.com/gamedev-company/workingmemory.git /tmp/wm-kit
cd /path/to/your/project
/tmp/wm-kit/install.sh
```

### Or, install into a specific target

```bash
/tmp/wm-kit/install.sh --target /path/to/your/project
```

### Flags

| Flag | Effect |
|------|--------|
| `--target DIR` | Install into `DIR` (default: current directory) |
| `--upgrade` | Refresh `CLAUDE.md` sentinel block + harness glue without touching `working-memory/` content. Use this to pull in newer kit versions. |
| `--with-agents` | Also install `.claude/agents/journalist.md` |
| `--with-obsidian` | Also install `working-memory/.obsidian/` vault config |
| `--with-recall` | Set up the Postgres recall layer + inventory the project **now** (macOS only; skips the prompt) |
| `--no-recall` | Skip the recall-layer prompt entirely |
| `-h` `--help` | Show full help |

### Recall layer (optional, macOS)

The recall engine ships **inside the vault** at `working-memory/okf-postgres/`
(see its [README](content/working-memory/okf-postgres/README.md)). At the end of
install, on macOS, the installer offers to set it up and **inventory the project
into knowledge cards** right away. Choose:

- **Now** — runs `working-memory/okf-postgres/scripts/okf-doctor.sh` (verifies/installs
  Ollama + models, Postgres + pgvector, a per-project database + schema, and the Python
  venv) then `okf-ingest.sh` to sweep the repo into cards.
- **Later** — the installer prints the exact commands. Run them from your project root:

  ```bash
  working-memory/okf-postgres/scripts/okf-ingest.sh --bootstrap --repo .
  ```

Then watch it live:

```bash
working-memory/okf-postgres/dashboard/okf-dashboard.sh --repo . --open
```

Use `--with-recall` to opt in non-interactively, or `--no-recall` to suppress the
prompt. The base kit works fine without any of this — the recall layer is purely
additive. Linux/Windows support for the setup scripts is left to the community. For a
guided run-through see **[WALKTHROUGH.md](WALKTHROUGH.md)**; for snags,
**[TROUBLESHOOTING.md](TROUBLESHOOTING.md)**.

### Idempotency contract

- Re-running on a fresh target: same result as one run.
- Re-running on an installed target without flags: aborts with "use `--upgrade`" message — conservative, never clobbers content.
- Re-running with `--upgrade`: refreshes the `CLAUDE.md` sentinel block + replaces harness glue files + re-merges settings snippet. Never touches files under `working-memory/`.
- `CLAUDE.md` patches are bounded by sentinel markers (`<!-- working-memory-kit:begin ... -->` / `<!-- working-memory-kit:end -->`) so re-runs and upgrades don't duplicate or drift.

### Requirements

- `bash`, `cp`, `mkdir`, `sed`, `awk` (standard on macOS / Linux)
- `jq` — only required if `.claude/` exists in target (for `settings.json` merge)

## First-session walkthrough

> For the full end-to-end path (including the recall layer and dashboard), see
> **[WALKTHROUGH.md](WALKTHROUGH.md)**. The short version, for the base convention:

After install:

1. Read `working-memory/System.md` — full taxonomy + workflow patterns
2. Seed `working-memory/short-term.md` with current project state (toolchain, branch, what's running where, open work)
3. Create today's journal: `working-memory/journals/$(date +%Y-%m-%d).md` with frontmatter:
   ```markdown
   ---
   type: journal
   date: 2026-05-11
   project: your-project-name
   ---

   # 2026-05-11
   ```
4. In Claude Code, run `/working-memory` to verify the harness and see vault status

After that, the per-turn cadence kicks in: append a `What:` / `Why:` summary (and any `★ Insight` blocks) to today's journal each turn. The agent does this; you don't have to nag it once the discipline rule is in `CLAUDE.md`.

## Example usage

A typical `short-term.md` after a few weeks of work:

```markdown
---
type: meta
updated: 2026-05-09
---

# Short-Term Memory

## Active

[2026-05-08 17:00] [STATUS]            Phases 0–7 merged on main at `ac029a2`. Test baseline 49/0/0.
[2026-05-09 00:30] [PLAN:implemented]  Step 1 done: `/dev/*` prod-404 guard via `import.meta.env.DEV`
[2026-05-09 late]  [HANDOFF]           Engage with [[complications/game-design-thesis]] — resolve Q2 first

## Key Context

[2026-05-08 17:00] [STATUS] [KEEP]     Toolchain: asdf manages elixir/erlang/node
[2026-05-08 17:00] [STATUS] [KEEP]     Phoenix on :4000; Vite/SvelteKit on :5173

## Where to go first

- [[design/migration-from-umbrella]]
- [[ref/data-model]]
```

A typical journal entry per turn:

```markdown
## [13:42] First specialist dispatch — frontend-programmer for /dev route guard

**What:** Landon green-lit the proof-of-life dispatch for the `/dev/*` route guard task...

**Why:** The user explicitly wanted to test-drive the frontend specialist...

### ★ Insight: project-local agents are session-boot-loaded only

The Claude Code harness reads `.claude/agents/*.md` at session start...
```

The full convention (frontmatter, tags, tier purposes, when-to-promote rules) is in `working-memory/System.md` after install.

## What this is NOT

- The base kit is a file convention, not a knowledge graph, database, or search tool. (The optional [`working-memory/okf-postgres/`](content/working-memory/okf-postgres/README.md) layer adds exactly those — embeddings, full-text, semantic recall — *underneath* the markdown, without changing the convention.)
- It does not replace Git history. Decisions still belong in commit messages; the vault captures the *why* behind work, not the *what*.
- It does not enforce structure beyond what the discipline rule in `CLAUDE.md` asks the agent to follow. If the agent isn't reading `CLAUDE.md`, the kit can't help.

## Customizing

The kit is intentionally small. To adapt:

- **Convention tweaks** — edit your `working-memory/System.md` after install. The kit's version is just a starting template.
- **Different journaling cadence** — adjust the prose in your `CLAUDE.md` Documentation Discipline block (between the sentinels). Note: a future `--upgrade` will rewrite this block with the kit's canonical version, so persistent customizations should fork the kit or maintain a wrapper layer.
- **Different slash commands** — edit `.claude/commands/working-memory-*.md` after install.
- **No agent harness** — just don't have a `.claude/` directory; the installer becomes content-only.

## Versioning

`install.sh` reports its version in the install header. The `CLAUDE.md` sentinel includes the version that produced the block: `<!-- working-memory-kit:begin version=0.3.0 -->`. Run `--upgrade` to refresh CLAUDE.md and harness glue to whatever version of the kit you're running.

Changelog is in [`CHANGELOG.md`](CHANGELOG.md).

## License

MIT. See `LICENSE`.

## Acknowledgements

This convention crystallized through several months of iteration on the Shadowrun MMORPG project (`gamedev.company/shadowlands`). The Stop-hook mtime-bug fix that ships in v0.1.0 was caught during that project; the tracker-file-split pattern is the result.
