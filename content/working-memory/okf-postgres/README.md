# okf-postgres

> A local, OKF-compliant codebase-memory layer: Postgres-backed semantic recall
> over a working-memory vault, so an AI agent stops re-reading the repo every session.

This extends the [working-memory kit](../../../README.md) with the thing its own README
said it deliberately *wasn't*: a database. The vault stays the **source of truth**
(git-tracked, Obsidian-openable, [OKF](https://cloud.google.com/blog/products/data-analytics/how-the-open-knowledge-format-can-improve-data-sharing)-portable
markdown). Postgres is a **derived recall index** — embeddings + full-text + a
freshness contract — maintained by a procedural pipeline and a *small local model*,
never the premium agent.

## The idea

Re-deriving "what does this codebase do" costs ~100k tokens of Explore-agent time
every session. But that map was already true last session. So:

- **Derive once, read many.** A per-folder *knowledge card* (what it does, which
  files, gotchas) costs ~5k tokens to write but ~50 to read.
- **Cheap labor does the writing.** A local model (`qwen3.6:27b`) summarizes
  changed folders; procedural code embeds + stores. Zero cloud tokens.
- **Hashes keep it honest.** Each card records the git blob SHA of every file it
  covers. Recall flags a card `stale` the moment its code drifts — so the agent
  knows when to trust it vs. re-enrich.

```
working-memory/  (OKF markdown, git)  ──indexer──▶  Postgres + pgvector
   cards/<folder>/index.md                            documents · card_sources · links
        ▲                                                   │
        └──────────── enrichment (small local LLM) ─────────┘
                              MCP tools (recall / get_card / stale)
                         ┌──────────────┴───────────────┐
                    qwen via mcphost              Claude Code
```

## Components

| Path | Role |
|------|------|
| `schema/001_init.sql` | Tables: `documents` (cards), `card_sources` (freshness contract), `links`; HNSW + GIN indexes |
| `okfmem/config.py` | Env-driven config (DB, repo, vault, Ollama models) |
| `okfmem/embed.py` | Local embeddings + chat via Ollama (`/api/embed`, `/api/chat`) |
| `okfmem/enrich.py` | Folder → OKF card: gather → small-LLM summarize → write md → embed → upsert |
| `okfmem/recall.py` | Hybrid recall: semantic + full-text fused with RRF, annotated with staleness |
| `okfmem/cli.py` | `index` / `enrich` / `enrich-changed` / `stale` / `recall` |
| `okfmem/mcp_server.py` | MCP server: `memory_recall`, `memory_get_card`, `memory_stale_cards` |
| `bin/okf-memory-mcp` | Launcher for MCP hosts (sets up env + venv) |
| `hooks/post-commit` | Git hook → `enrich-changed` in the background (the refresh trigger) |
| `scripts/okf-doctor.sh` | **Bootstrap/verify the environment** (Ollama + models, Postgres + pgvector, db + schema, venv) — idempotent, macOS-only |
| `scripts/okf-ingest.sh` | **Inventory a repo into cards** (the seed step); `--bootstrap` chains the doctor, `--with-hook` installs auto-refresh |
| `scripts/lib.sh` | Shared helpers (Postgres.app resolution, server-ready probe, venv locator, db guard) |
| `dashboard/okf-dashboard.sh` | **Live HTML view** of the index — fetches from Postgres, renders via a tiny `{{token}}` compiler, re-generates on an interval |
| `dashboard/template.html`, `card.html` | The page shell + per-card partial (restyle freely) |
| `mcp.example.json` | Config for mcphost **and** Claude Code (same schema) |

## Setup (scripted — macOS)

> **Platform:** the setup scripts support **macOS only** for now. Linux/Windows are
> left to the community — the Python pipeline itself is portable if you provision
> Postgres + Ollama yourself and run `okfmem` directly.

This engine ships **inside the vault** (`working-memory/okf-postgres/`), so the
paths below are written from your project root. One command provisions everything
and inventories your repo:

```bash
working-memory/okf-postgres/scripts/okf-ingest.sh --bootstrap --repo .
```

`--bootstrap` first runs **`okf-doctor.sh`**, which is idempotent and checks (and,
where it can, installs) each piece, then `okf-ingest.sh` runs the inventory sweep:

1. **Ollama + models** — installs Ollama via Homebrew if missing, starts the server,
   pulls `nomic-embed-text` (768-dim embeddings) and `qwen3.6:27b` (enrichment).
2. **Postgres + pgvector** — prefers **Postgres.app** (locates its bundled `psql`
   even when it's off `PATH`, starts the server); offers to install it via Homebrew
   if absent. Creates a **per-project, uniquely-named** database (`okf_<slug>_<hash8>`,
   or `--db NAME`) and applies the schema — refusing to touch a database it didn't
   create.
3. **Python env** — `python3 -m venv .venv && .venv/bin/pip install -e .` (editable
   install; `okfmem` then imports from any cwd, so the launcher and git hook need no
   `PYTHONPATH`).

Run the doctor on its own any time to (re)verify the environment:

```bash
working-memory/okf-postgres/scripts/okf-doctor.sh    # add --yes for non-interactive
```

## Usage

```bash
# Provision + inventory in one shot (the scripted path above), from project root:
working-memory/okf-postgres/scripts/okf-ingest.sh --bootstrap --repo . --with-hook

# …or drive the CLI directly once the environment is ready (from this engine dir,
# i.e. cd working-memory/okf-postgres):
export OKF_REPO=/path/to/your/project          # the repo to map
export OKF_VAULT=$OKF_REPO/working-memory       # where cards are written

.venv/bin/python -m okfmem.cli index            # one-time: card every folder
.venv/bin/python -m okfmem.cli recall "how does auth work"
.venv/bin/python -m okfmem.cli stale            # what's drifted
```

`okf-ingest.sh --with-hook` installs the git `post-commit` hook for you (it
materializes `hooks/post-commit` with this directory's absolute path baked in, so
cards auto-refresh on commit). To wire it up by hand instead:

```bash
sed "s#__OKF_POSTGRES_DIR__#$PWD#g" hooks/post-commit > "$OKF_REPO/.git/hooks/post-commit"
chmod +x "$OKF_REPO/.git/hooks/post-commit"
```

### Live dashboard

A self-refreshing HTML view of the index — what's mapped, what's drifted — with no
web server. The script queries Postgres, renders the page through a tiny `{{token}}`
shell template compiler, and rewrites the file on an interval; a `<meta refresh>` in
the page reloads it in the browser.

```bash
working-memory/okf-postgres/dashboard/okf-dashboard.sh --repo . --open   # live, every 5s
working-memory/okf-postgres/dashboard/okf-dashboard.sh --repo . --once   # render one shot
#   --interval N   seconds between rebuilds      --db NAME   read a specific database
#   --out FILE     where to write the HTML        --open     open it in your browser
```

Cards are sorted **stale-first**; the freshness verdict reuses `okfmem stale` (so it
matches recall). The look lives in `dashboard/template.html` + `card.html` — both are
plain `{{token}}` templates, so restyle them without touching the script.

### Give a model the memory tools

```bash
# Local qwen, via mcphost:
mcphost -m ollama:qwen3.6:27b --config ~/.mcp.json -p "recall how recall works"

# Claude Code: copy the mcpServers block into the project's .mcp.json.
```

> **Gotcha — the env-block key differs by host.** mcphost reads the per-server
> environment as `"environment"`; Claude Code / Claude Desktop read it as `"env"`.
> Set `OKF_REPO` under the key your host expects, or the launcher's guard aborts
> with "transport closed". `mcp.example.json` shows the `command` shape; swap the
> key to match the consumer.

## Config knobs (env)

| Var | Default | Meaning |
|-----|---------|---------|
| `OKF_REPO` | `.` | Repo being mapped |
| `OKF_VAULT` | `$OKF_REPO/working-memory` | Where cards live |
| `OKF_DB_NAME` | `okf_<slug>_<hash8>` | Database name — **derived per repo** so it never collides; override here or with `--db` |
| `OKF_DB_DSN` | `postgresql://localhost/$OKF_DB_NAME` | Full connection string (wins over `OKF_DB_NAME`) |
| `OKF_EMBED_MODEL` | `nomic-embed-text` | Embedder (768-dim) |
| `OKF_ENRICH_MODEL` | `qwen3.6:27b` | Summarizer (run with `think=false`) |
| `OLLAMA_HOST` | `http://localhost:11434` | Local Ollama |

**Database naming & safety.** Each project gets its own database, named
`okf_<repo-slug>_<hash8>` (the hash is of the repo's absolute path), so multiple
projects share one Postgres without colliding — and setup never lands on a database
you already have. Pin a specific name with `okf-doctor.sh`/`okf-ingest.sh --db NAME`
(or `OKF_DB_NAME`); the resolved name is written to `.okf-env` so the commit hook and
MCP server use the same one. Before applying its schema to a *pre-existing* database,
setup checks for an `okf_meta` ownership marker and **refuses** if the database holds
tables it didn't create — so it can't clobber someone else's data.

## Design decisions (settled)

- **Source of truth:** markdown vault; Postgres is rebuildable.
- **Card grain:** per folder (natural git boundaries, simple staleness).
- **Refresh trigger:** git `post-commit` (deterministic, no idle daemon).
- **Recall fusion:** Reciprocal Rank Fusion of semantic + full-text.

## Remaining / TODO

- **OKF frontmatter convergence** in the kit's own templates (`title`/`description`/
  `tags`/`timestamp`/`resource`) so *all* tiers — not just cards — are OKF docs.
- **Link extraction**: populate `links` from `[[wikilinks]]` to power `neighbors`.
- **Staleness policy**: currently recall *flags* stale cards. Decide whether to also
  down-rank or auto-refresh them (a real product call — see conversation).
- **Chunk-level embeddings** for long docs if folder cards get big.
