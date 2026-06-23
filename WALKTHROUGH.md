# Walkthrough — zero to a self-updating codebase memory

This takes you from a fresh clone to an indexed codebase, live recall in your agent,
and a self-refreshing dashboard. It has two independent layers:

1. **The base convention** — a markdown `working-memory/` vault + a discipline rule in
   `CLAUDE.md`. Agent-agnostic, no dependencies, works anywhere.
2. **The recall layer** (optional, **macOS**) — a Postgres + pgvector index *under* the
   vault that a small **local** model fills with per-folder "knowledge cards," so an
   agent recalls the codebase instead of re-reading it.

You can stop after layer 1. Layer 2 is purely additive.

> See also **[TROUBLESHOOTING.md](TROUBLESHOOTING.md)** when a step misbehaves, and the
> recall layer's [README](content/working-memory/okf-postgres/README.md) for design detail.

---

## 0. Prerequisites

| For | You need |
|-----|----------|
| Base convention | `bash`, `git`. (`jq` only if you have a `.claude/` dir.) |
| Recall layer | **macOS**, [Homebrew](https://brew.sh), `python3`. The doctor installs the rest (Ollama, models, Postgres.app) if missing. |

The recall layer runs **100% locally** — embeddings and summarization go through Ollama
on your machine. Nothing leaves the box.

---

## 1. Install the kit

```bash
git clone https://github.com/gamedev-company/workingmemory.git /tmp/wm-kit
cd /path/to/your/project
/tmp/wm-kit/install.sh
```

What lands in your project:

- `working-memory/` — the vault skeleton (`System.md`, `Index.md`, `short-term.md`, and
  empty tier dirs) **plus** the recall engine at `working-memory/okf-postgres/` (inert
  until you set it up in step 3).
- `CLAUDE.md` — a "Documentation Discipline" block (bounded by sentinel markers, so
  re-runs don't duplicate it).
- If a `.claude/` directory exists, the Claude Code harness too (a Stop hook + the
  `/working-memory*` slash commands).

The installer is conservative: an existing `working-memory/` aborts the run with a
`--upgrade` hint rather than clobbering anything.

On macOS it then **offers to set up the recall layer now** (that's steps 3–4 in one go).
Say no for now if you want to walk through it deliberately — or pass `--no-recall` to
skip the prompt, `--with-recall` to take it non-interactively.

---

## 2. The base convention (first session)

1. **Read `working-memory/System.md`** — the taxonomy: which tier holds what, when to
   promote a note from short-term to a durable doc, the frontmatter shape.
2. **Seed `working-memory/short-term.md`** — the ≤300-line session-boot brief: toolchain,
   branch, what's running where, open threads.
3. **Start journaling** — one `What:` / `Why:` entry per turn in
   `working-memory/journals/$(date +%Y-%m-%d).md`. With the discipline rule in
   `CLAUDE.md`, the agent does this itself.
4. In Claude Code, run **`/working-memory`** to verify the harness and see vault status.

That's the whole base layer. The rest of this guide is the recall layer.

---

## 3. Set up the recall layer (macOS)

One command provisions everything and indexes the repo (it's idempotent — safe to
re-run):

```bash
cd /path/to/your/project
working-memory/okf-postgres/scripts/okf-ingest.sh --bootstrap --repo . --with-hook
```

`--bootstrap` runs the **doctor** first, which checks (and installs where it can):

| Step | What happens |
|------|--------------|
| **Ollama** | Installs via Homebrew if missing, starts the server, pulls `nomic-embed-text` (embeddings) and `qwen3.6:27b` (summarizer). The summarizer is large (~17 GB) — first pull takes a while. |
| **Postgres** | Prefers **Postgres.app** (finds its `psql` even though it's off `PATH`, starts the server); offers to install it if absent. |
| **Database** | Creates a **per-project, uniquely-named** database `okf_<slug>_<hash>` and applies the schema. It **refuses** to write into a database it didn't create (see step 8). |
| **Python venv** | Builds `working-memory/okf-postgres/.venv` and installs the `okfmem` package into it. |

Run the doctor on its own any time to re-verify:

```bash
working-memory/okf-postgres/scripts/okf-doctor.sh        # add --yes for non-interactive
```

The resolved database name is pinned in `working-memory/okf-postgres/.okf-env` so every
entry point (ingest, the commit hook, the MCP server) agrees on it.

---

## 4. Inventory the codebase

If you ran `--bootstrap` above, this already happened. To (re)run the sweep alone:

```bash
working-memory/okf-postgres/scripts/okf-ingest.sh --repo .
```

It walks the repo, treats **each code-bearing folder as one "card,"** and a local model
writes a terse map of what that folder does, which files own which responsibility, and
any gotchas. Each card is written **twice**:

- as OKF markdown at `working-memory/cards/<folder>/index.md` (git-tracked, the source of
  truth, Obsidian-openable);
- as a row in Postgres (embedding + full-text + a **freshness contract**: the git blob
  SHA of every file it covers).

Expect one line of output per folder. Large repos take a while on the first run — the
model writes ~5k tokens per card. Folders like `node_modules`, `.git`, `working-memory`
itself, and build dirs are skipped.

---

## 5. Recall it

**From the CLI** (the `okfmem` tool lives in the venv):

```bash
VENV=working-memory/okf-postgres/.venv/bin/python
OKF_REPO=. $VENV -m okfmem.cli recall "how does auth refresh work"
OKF_REPO=. $VENV -m okfmem.cli stale        # what's drifted since it was carded
```

**From Claude Code (MCP)** — give the agent the memory tools so it recalls instead of
re-reading. Copy the `okf-memory` server block from
`working-memory/okf-postgres/mcp.example.json` into your project's `.mcp.json`, setting
the absolute path and `OKF_REPO`:

```json
{
  "mcpServers": {
    "okf-memory": {
      "command": "/abs/path/to/your/project/working-memory/okf-postgres/bin/okf-memory-mcp",
      "env": { "OKF_REPO": "/abs/path/to/your/project" }
    }
  }
}
```

The agent then has `memory_recall`, `memory_get_card`, and `memory_stale_cards`. Each
recall result carries a **freshness** verdict — if `stale` is true, the code drifted
since the card was written, so the agent treats the card as a hint and verifies.

---

## 6. Keep it fresh

If you installed the hook with `--with-hook` (step 3), every `git commit` kicks off a
background re-enrichment of the folders that commit touched — the commit returns
instantly; the model catches up behind it. Install it later by hand:

```bash
cd working-memory/okf-postgres
sed "s#__OKF_POSTGRES_DIR__#$PWD#g" hooks/post-commit > "$(git rev-parse --show-toplevel)/.git/hooks/post-commit"
chmod +x "$(git rev-parse --show-toplevel)/.git/hooks/post-commit"
```

Without the hook, re-run `okf-ingest.sh --repo .` whenever you want to refresh, or check
drift with `okfmem stale`.

---

## 7. Watch it live (dashboard)

A self-refreshing HTML view — no web server:

```bash
working-memory/okf-postgres/dashboard/okf-dashboard.sh --repo . --open
```

It queries Postgres, renders the page through a tiny `{{token}}` shell template compiler,
and rewrites the file every few seconds; a `<meta refresh>` in the page reloads it in the
browser. Cards sort **stale-first** so what needs attention floats to the top.

```
--interval N   seconds between rebuilds (default 5)   --once   render once and exit
--db NAME      read a specific database                --out FILE   where to write the HTML
```

The look lives in `dashboard/template.html` + `dashboard/card.html` — plain `{{token}}`
templates. Restyle them freely; the script doesn't care.

---

## 8. Multiple projects on one machine

Each project gets its **own** uniquely-named database (`okf_<slug>_<hash>` of the repo's
absolute path), so they never collide on a shared Postgres. Just run the setup once per
repo. To pin an explicit name (e.g. a shared team database), pass `--db NAME` to the
doctor/ingest/dashboard — the choice is recorded in that project's `.okf-env`.

Setup will **never** apply its schema to a database it didn't create: if you point `--db`
at a database that already holds other tables, it aborts rather than risk your data.

---

## Quick command reference

```bash
# Install into the current project
/tmp/wm-kit/install.sh

# Provision the recall layer + inventory + auto-refresh hook
working-memory/okf-postgres/scripts/okf-ingest.sh --bootstrap --repo . --with-hook

# Re-verify the environment / re-inventory
working-memory/okf-postgres/scripts/okf-doctor.sh
working-memory/okf-postgres/scripts/okf-ingest.sh --repo .

# Recall + drift (from the venv)
OKF_REPO=. working-memory/okf-postgres/.venv/bin/python -m okfmem.cli recall "…"
OKF_REPO=. working-memory/okf-postgres/.venv/bin/python -m okfmem.cli stale

# Live dashboard
working-memory/okf-postgres/dashboard/okf-dashboard.sh --repo . --open
```
