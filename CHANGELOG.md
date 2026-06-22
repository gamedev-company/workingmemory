# Changelog

All notable changes to working-memory-kit are recorded here. The kit version is
reported by `install.sh` and stamped into the `CLAUDE.md` sentinel block.

## 0.3.0 — Scripted recall setup (macOS) + in-vault engine

The okf-postgres recall layer goes from "manually provisioned on one machine" to a
repeatable, one-command setup — and now ships **inside the vault** so it travels with
the project instead of cluttering the repo root.

### Added
- **`working-memory/okf-postgres/scripts/okf-doctor.sh`** — idempotent environment
  bootstrap/verify (macOS): installs/checks Ollama + pulls the embed/enrich models,
  finds or installs Postgres (prefers Postgres.app, resolving its bundled `psql` even
  when it's off `PATH`), creates the `okf_memory` database, applies the schema, and
  builds the Python venv. Flags: `--yes`, `--skip-models`, `--embed-model`,
  `--enrich-model`.
- **`working-memory/okf-postgres/scripts/okf-ingest.sh`** — inventories a target repo
  into per-folder knowledge cards (the "seed" step). `--bootstrap` chains the doctor
  first; `--with-hook` installs the git `post-commit` auto-refresh hook with the
  package path baked in; `--repo`, `--project`, `--yes`.
- **`…/scripts/lib.sh`** — shared helpers (Postgres.app binary resolution,
  server-ready probe, Ollama/model detection, venv locator, y/n prompt, db resolution
  + ownership guard).
- **`install.sh`**: at the end of an install, on macOS, offers to set up the recall
  layer and inventory the project immediately, or prints the deferred commands to run
  later. New flags `--with-recall` (opt in non-interactively) and `--no-recall`.

### Database naming & safety
- **Per-project, uniquely-named databases.** Each repo gets `okf_<slug>_<hash8>`
  (hash of the absolute repo path), derived in `okfmem/config.py` so the CLI, commit
  hook, and MCP server all agree. No more shared `okf_memory` — multiple projects on
  one Postgres no longer collide, and setup never lands on a database you already have.
- **`--db NAME`** on `okf-doctor.sh` and `okf-ingest.sh` (and `OKF_DB_NAME`) to pin an
  explicit database name; the resolved name is written to a generated `.okf-env` that
  the commit hook and MCP launcher source, so the choice survives a repo move.
- **Ownership guard.** Schema carries an `okf_meta` (`owner=okfmem`) marker; setup
  checks it before applying the schema to a *pre-existing* database and **refuses**
  (hard-aborts) if that database holds tables it didn't create. Empty databases are
  adopted; brand-new ones are created. So the tooling cannot clobber your data.

### Changed
- **Relocated `okf-postgres/` → `working-memory/okf-postgres/`.** The recall engine is
  now installable content that ships inside the vault (one self-contained directory
  per project, with its own `.venv`), instead of a top-level sibling. The indexer
  ignores `working-memory/`, so the engine never self-indexes. `install.sh` strips
  build artifacts (`.venv`, `__pycache__`, `*.egg-info`) on copy so a dev's local
  environment never lands in a target.
- Installer version → `0.3.0`; `okfmem` package → `0.3.0`.
- okf-postgres README: replaced the "already done on this machine" notes with the
  scripted, reproducible setup (doctor + ingest); documented the macOS-only scope.

### Notes
- Linux/Windows are intentionally unsupported by the setup scripts for now (the
  Python pipeline remains portable if you provision Postgres + Ollama yourself).

## 0.2.0 — OKF frontmatter + okf-postgres recall layer

- OKF-aligned frontmatter across durable tiers (`type`/`title`/`description`/`tags`/
  `timestamp`/`resource`), backward-compatible with `updated:`/`source:`.
- Optional `okf-postgres/` recall index: Postgres + pgvector under the markdown vault,
  a small local model writes per-folder `feature-card` maps, recall over MCP with a
  git-SHA freshness contract.

## 0.1.0 — Initial release

- `working-memory/` convention + Claude Code harness (Stop hook, slash commands,
  optional journalist agent and Obsidian vault config).
