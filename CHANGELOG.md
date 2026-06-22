# Changelog

All notable changes to working-memory-kit are recorded here. The kit version is
reported by `install.sh` and stamped into the `CLAUDE.md` sentinel block.

## 0.3.0 — Scripted recall setup (macOS)

The okf-postgres recall layer goes from "manually provisioned on one machine" to a
repeatable, one-command setup.

### Added
- **`okf-postgres/scripts/okf-doctor.sh`** — idempotent environment bootstrap/verify
  (macOS): installs/checks Ollama + pulls the embed/enrich models, finds or installs
  Postgres (prefers Postgres.app, resolving its bundled `psql` even when it's off
  `PATH`), creates the `okf_memory` database, applies the schema, and builds the
  Python venv. Flags: `--yes`, `--skip-models`, `--embed-model`, `--enrich-model`.
- **`okf-postgres/scripts/okf-ingest.sh`** — inventories a target repo into per-folder
  knowledge cards (the "seed" step). `--bootstrap` chains the doctor first;
  `--with-hook` installs the git `post-commit` auto-refresh hook with the package
  path baked in; `--repo`, `--project`, `--yes`.
- **`okf-postgres/scripts/lib.sh`** — shared helpers (Postgres.app binary resolution,
  server-ready probe, Ollama/model detection, venv locator, y/n prompt).
- **`install.sh`**: at the end of an install, on macOS, offers to set up the recall
  layer and inventory the project immediately, or prints the deferred commands to run
  later. New flags `--with-recall` (opt in non-interactively) and `--no-recall`.

### Changed
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
