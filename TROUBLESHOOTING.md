# Troubleshooting

Symptom → cause → fix, grouped by area. Most recall-layer problems are environment
issues the **doctor** can diagnose — when in doubt, re-run it (it's idempotent):

```bash
working-memory/okf-postgres/scripts/okf-doctor.sh
```

---

## Install

**`error: missing required command: jq`**
The installer needs `jq` only to merge the Stop hook into `.claude/settings*.json`, and
only when a `.claude/` directory exists. Install it (`brew install jq`) or run with
`--no-recall` in a project that has no `.claude/`.

**`working-memory/ already exists at …`**
Conservative by design — the installer won't clobber an existing vault. To refresh the
`CLAUDE.md` block + harness glue without touching vault content, re-run with `--upgrade`.
For a clean reinstall, remove `working-memory/` first.

**The `CLAUDE.md` Documentation Discipline block appears twice**
It shouldn't — the block is bounded by `<!-- working-memory-kit:begin … -->` /
`<!-- …:end -->` sentinels and replaced in place. If you have duplicates from an older
version, delete the extra block; the next `--upgrade` will keep a single one.

**The recall prompt never appears at the end of install**
It's macOS-only and skipped on a non-interactive shell (piped stdin). Run the setup
directly: `working-memory/okf-postgres/scripts/okf-ingest.sh --bootstrap --repo .`

---

## Ollama

**`could not reach the Ollama server`**
The daemon isn't running. Start it (`ollama serve`, or `brew services start ollama`) and
re-run the doctor. Verify with `ollama list`.

**A model pull is enormous / slow**
The default summarizer `qwen3.6:27b` is ~17 GB. That's expected on first pull. To skip
pulls while you verify everything else: `okf-doctor.sh --skip-models`. To use a smaller
model, set it everywhere with `--enrich-model NAME` (doctor) or `OKF_ENRICH_MODEL`, e.g.
a smaller local model you already have from `ollama list`.

**`model 'X' missing — enrichment/recall will fail`**
The doctor offered to pull it and you declined, or the tag doesn't exist. Pull it
manually: `ollama pull nomic-embed-text` and `ollama pull qwen3.6:27b` (or your chosen
tags), then re-run.

**Enrichment fails on some folders with JSON errors**
The enricher constrains the model to a JSON schema and retries at escalating temperature;
a folder that still fails is logged as `FAILED` and the batch continues. Re-run
`okf-ingest.sh --repo .` to retry just the gaps, or try a stronger `--enrich-model`.

---

## Postgres / Postgres.app

**`no reachable Postgres` even though Postgres.app is installed**
Postgres.app keeps its binaries **off `PATH`** on purpose, and its server may not be
started. The doctor resolves `psql` from the app bundle and tries to start it — if it
can't, open **Postgres.app** and click **Initialize** / **Start** on the default server,
then re-run. Quick manual check:

```bash
/Applications/Postgres.app/Contents/Versions/latest/bin/pg_isready -h localhost
```

**`pgvector not available in this Postgres`**
Postgres.app bundles pgvector, so this usually means a *different* Postgres is answering
(e.g. a Homebrew one). Either point at Postgres.app, or install the extension for your
server: `brew install pgvector`, then re-run the doctor (the schema does
`CREATE EXTENSION vector`).

**`psql: command not found` when running things by hand**
Use the bundled binary explicitly:
`/Applications/Postgres.app/Contents/Versions/latest/bin/psql`, or add that directory to
your `PATH`.

---

## Database naming & the guard

**`database '…' already exists and contains tables NOT created by okfmem. Refusing …`**
This is the safety guard doing its job: you pointed `--db` (or `OKF_DB_NAME`/`OKF_DB_DSN`)
at a database that already holds tables it didn't create, and it won't apply its schema
over your data. Pick a different name with `--db NAME`, or drop/rename that database
first. An *empty* database is adopted; a brand-new one is created.

**"Which database is this project using?"**
The default is `okf_<repo-slug>_<hash8>`, derived from the repo's absolute path. The
resolved name is written to `working-memory/okf-postgres/.okf-env`. To see it:

```bash
OKF_REPO=. working-memory/okf-postgres/.venv/bin/python -c "from okfmem.config import DB_NAME; print(DB_NAME)"
cat working-memory/okf-postgres/.okf-env
```

**I moved the repo and now it's a fresh, empty index**
The derived name is a function of the absolute path, so moving the repo changes it.
The old data still lives in the old database. Either re-ingest at the new path, or pin
the old name: `--db <old-name>` (the value is then stored in `.okf-env`, so it sticks).

**Upgrading from before per-project databases (the old shared `okf_memory`)**
Nothing migrates automatically. Re-run `okf-ingest.sh --repo .` to build the project's
new database; drop the old `okf_memory` by hand once you're satisfied.

---

## Python venv

**`okfmem venv missing`**
The venv at `working-memory/okf-postgres/.venv` hasn't been built. Run the doctor (or
`okf-ingest.sh --bootstrap`). It needs `python3` on `PATH` (`brew install python` if not).

**`okfmem failed to import after install`**
The editable install didn't complete — usually a pip/network hiccup. Re-run the doctor;
it reinstalls `okfmem` into the venv. To inspect:
`working-memory/okf-postgres/.venv/bin/python -c "import okfmem"`.

---

## Recall

**Recall returns nothing**
Either the index is empty (run `okf-ingest.sh --repo .`) or you're querying the wrong
database. Confirm the project's db name (above) and that it has cards:

```bash
PSQL=/Applications/Postgres.app/Contents/Versions/latest/bin/psql
$PSQL "$(OKF_REPO=. working-memory/okf-postgres/.venv/bin/python -c 'from okfmem.config import DB_DSN;print(DB_DSN)')" \
  -c "SELECT count(*) FROM documents;"
```

**Everything shows as `stale`**
Stale = the file's current git blob SHA differs from the one recorded when it was carded.
If *everything* is stale, the cards predate a big change (or were built against a
different checkout). Re-run `okf-ingest.sh --repo .` to re-enrich. Note: freshness uses
`git hash-object`, so it's meaningful only inside a git repo.

---

## Dashboard

**`declare: -A: invalid option`**
You're on an old `bash` (macOS ships 3.2). The shipped scripts are written for 3.2 — if
you hit this, you're likely running a stale copy. Re-pull the kit / re-`--upgrade`. (The
dashboard deliberately avoids associative arrays for exactly this reason.)

**The page is blank or shows "No cards yet"**
The database has no `feature-card` rows. Run an inventory first (`okf-ingest.sh --repo .`),
then re-open the dashboard.

**The page doesn't update**
The generator loop must be running — `okf-dashboard.sh --repo .` (without `--once`) keeps
re-rendering on `--interval` seconds; the browser reloads via the page's `<meta refresh>`.
If you used `--once`, it rendered a single snapshot by design.

**Freshness badges are all green even though code changed**
The dashboard reads drift from `okfmem stale`, which needs the venv. If the venv is
missing it degrades to showing everything fresh. Build it (run the doctor) and refresh.

---

## MCP (Claude Code / mcphost)

**The server dies immediately / "transport closed"**
Usually `OKF_REPO` isn't set in the host config's env block — the launcher aborts without
it. Also note the **env-block key differs by host**: mcphost reads `"environment"`, while
Claude Code / Claude Desktop read `"env"`. Set `OKF_REPO` under the key your host expects.

**Recall over MCP hits the wrong database**
The launcher sources `working-memory/okf-postgres/.okf-env` to pin the project's database.
If you customized `--db`, make sure that `.okf-env` exists (it's written by the doctor /
ingest). Confirm the `command` path in `.mcp.json` points at *this* project's
`working-memory/okf-postgres/bin/okf-memory-mcp`.

---

## Still stuck?

Run the doctor and read its section-by-section output — it reports exactly which piece is
unhealthy:

```bash
working-memory/okf-postgres/scripts/okf-doctor.sh --yes
```

The markdown vault under `working-memory/` is always the source of truth; the Postgres
index is derived and safe to rebuild from scratch (`okf-ingest.sh --repo .`).
