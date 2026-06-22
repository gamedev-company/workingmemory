#!/bin/bash
# okf-doctor.sh — verify (and, where it can, provision) everything the okf-postgres
# recall layer needs on macOS: Ollama + models, a reachable Postgres with pgvector,
# the project database + schema, and the Python venv.
#
# Idempotent: safe to re-run. Every step checks before it acts and reports what it
# found. Nothing here touches the cloud — embeddings + enrichment are 100% local.
#
# The database is per-project and UNIQUELY named by default (okf_<slug>_<hash> of the
# repo path), so it never collides with an existing database. The doctor refuses to
# apply its schema over a database it didn't create (see the ownership guard).
#
# Usage:
#   okf-doctor.sh [--repo DIR] [--db NAME] [--yes] [--skip-models]
#                 [--embed-model M] [--enrich-model M]
#
#   --repo DIR       project whose database to provision (default: $OKF_REPO or cwd)
#   --db NAME        use/create this exact database instead of the derived name
#   --yes            assume "yes" to every prompt (non-interactive / CI)
#   --skip-models    don't pull Ollama models (just verify the rest)
#   --embed-model    override embedder    (default: $OKF_EMBED_MODEL or nomic-embed-text)
#   --enrich-model   override summarizer  (default: $OKF_ENRICH_MODEL or qwen3.6:27b)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

okf_require_macos

# ── Config (env-overridable, matching okfmem/config.py defaults) ─────────────────
EMBED_MODEL="${OKF_EMBED_MODEL:-nomic-embed-text}"
ENRICH_MODEL="${OKF_ENRICH_MODEL:-qwen3.6:27b}"
SKIP_MODELS=0
REPO="${OKF_REPO:-$PWD}"
DB_OVERRIDE=""
ROOT="$(okf_root)"
SCHEMA="$ROOT/schema/001_init.sql"

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)          REPO="$2"; shift 2;;
    --repo=*)        REPO="${1#*=}"; shift;;
    --db)            DB_OVERRIDE="$2"; shift 2;;
    --db=*)          DB_OVERRIDE="${1#*=}"; shift;;
    --yes|-y)        export OKF_ASSUME_YES=1; shift;;
    --skip-models)   SKIP_MODELS=1; shift;;
    --embed-model)   EMBED_MODEL="$2"; shift 2;;
    --enrich-model)  ENRICH_MODEL="$2"; shift 2;;
    -h|--help)       sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) okf_die "unknown flag: $1 (try --help)";;
  esac
done

REPO="$(cd "$REPO" 2>/dev/null && pwd)" || okf_die "repo path does not exist: $REPO"
if [ -n "$DB_OVERRIDE" ] && ! okf_valid_db_name "$DB_OVERRIDE"; then
  okf_die "--db '$DB_OVERRIDE' is not a valid database name (use [A-Za-z_][A-Za-z0-9_]*, ≤63 chars)."
fi
# Single source of truth: ask the package config to resolve name + DSN.
DB_NAME="$(okf_db_value DB_NAME "$REPO" "$DB_OVERRIDE")"
DB_DSN="$(okf_db_value DB_DSN "$REPO" "$DB_OVERRIDE")"
[ -n "$DB_NAME" ] || okf_die "could not resolve a database name (is python3 on PATH?)."

PROBLEMS=0

# ── Homebrew ─────────────────────────────────────────────────────────────────────
okf_hd "Homebrew"
if okf_have brew; then
  okf_ok "brew present ($(brew --version | head -1))"
else
  okf_warn "Homebrew not found — it's the simplest way to install Ollama & Postgres."
  okf_info "Install it from https://brew.sh then re-run this doctor, or install the"
  okf_info "pieces below manually. Continuing with what's already on this machine."
fi

# ── Ollama (engine + models) ─────────────────────────────────────────────────────
okf_hd "Ollama (local inference)"
if ! okf_have ollama; then
  if okf_have brew && okf_ask_yn "Ollama is not installed. Install it via Homebrew now?" Y; then
    brew install ollama
  else
    okf_warn "Skipping Ollama install — recall/enrichment cannot run without it."
    okf_info "Get it from https://ollama.com/download or 'brew install ollama'."
    PROBLEMS=$((PROBLEMS + 1))
  fi
fi

if okf_have ollama; then
  okf_ok "ollama present ($(ollama --version 2>/dev/null | head -1))"
  if ! okf_ollama_up; then
    okf_info "Ollama server not responding — starting it in the background…"
    # `brew services` gives a persistent server; fall back to a detached `ollama serve`.
    if okf_have brew && brew services list 2>/dev/null | grep -q '^ollama'; then
      brew services start ollama >/dev/null 2>&1 || true
    fi
    if ! okf_ollama_up; then
      (ollama serve >/dev/null 2>&1 &) || true
      for _ in 1 2 3 4 5 6 7 8 9 10; do okf_ollama_up && break; sleep 1; done
    fi
  fi
  if okf_ollama_up; then
    okf_ok "ollama server reachable"
    if [ "$SKIP_MODELS" -eq 1 ]; then
      okf_info "--skip-models set; not pulling models."
    else
      for m in "$EMBED_MODEL" "$ENRICH_MODEL"; do
        if okf_ollama_has_model "$m"; then
          okf_ok "model present: $m"
        elif okf_ask_yn "Pull model '$m' now? (large models can be many GB)" Y; then
          okf_info "pulling $m … (this can take a while)"
          ollama pull "$m"
          okf_ok "pulled $m"
        else
          okf_warn "model '$m' missing — enrichment/recall will fail until it's pulled."
          PROBLEMS=$((PROBLEMS + 1))
        fi
      done
    fi
  else
    okf_warn "could not reach the Ollama server. Start it with 'ollama serve' and re-run."
    PROBLEMS=$((PROBLEMS + 1))
  fi
fi

# ── Postgres (server + pgvector + database + schema) ─────────────────────────────
okf_hd "Postgres + pgvector"
if ! okf_pg_ready; then
  # Prefer Postgres.app (the project's reference setup); offer to install if absent.
  if [ -d "/Applications/Postgres.app" ]; then
    okf_info "Postgres.app is installed but no server is answering on localhost."
    okf_info "Opening it now — if prompted, click \"Initialize\" / \"Start\"."
    open -a Postgres.app >/dev/null 2>&1 || true
    for _ in $(seq 1 20); do okf_pg_ready && break; sleep 1; done
  elif okf_have brew && okf_ask_yn "No Postgres found. Install Postgres.app (GUI, bundles pgvector) via Homebrew?" Y; then
    brew install --cask postgres-unofficial
    okf_info "Launching Postgres.app — click \"Initialize\" to create the default server."
    open -a Postgres.app >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do okf_pg_ready && break; sleep 1; done
  fi
fi

if okf_pg_ready; then
  okf_ok "Postgres reachable on localhost"
  PSQL="$(okf_psql)"          || okf_die "Postgres is up but no psql binary found (Postgres.app bin missing?)."
  CREATEDB="$(okf_createdb)"  || CREATEDB=""
  okf_info "project database: $DB_NAME"
  [ -n "$DB_OVERRIDE" ] && okf_info "(explicit --db override)"
  # Guarded create + schema: refuses to touch a database it didn't create. Hard-aborts
  # on a foreign, non-empty database (your data is safe); soft-fails on pgvector/schema.
  okf_ensure_db "$PSQL" "$CREATEDB" "$DB_NAME" "$DB_DSN" "$SCHEMA" "$ROOT" \
    || PROBLEMS=$((PROBLEMS + 1))
else
  okf_warn "no reachable Postgres. Install Postgres.app (https://postgresapp.com) or a"
  okf_info "brew server, start it, then re-run this doctor."
  PROBLEMS=$((PROBLEMS + 1))
fi

# ── Python venv + okfmem package ─────────────────────────────────────────────────
okf_hd "Python environment (okfmem)"
VENV_PY="$(okf_venv_python)"
if [ ! -x "$VENV_PY" ]; then
  okf_have python3 || okf_die "python3 not found — install it (brew install python) and re-run."
  okf_info "creating venv at $ROOT/.venv …"
  python3 -m venv "$ROOT/.venv"
fi
okf_info "installing okfmem (editable) + dependencies…"
"$VENV_PY" -m pip install -q --upgrade pip >/dev/null 2>&1 || true
"$VENV_PY" -m pip install -q -e "$ROOT"
if "$VENV_PY" -c "import okfmem" 2>/dev/null; then
  okf_ok "okfmem importable from the venv"
else
  okf_warn "okfmem failed to import after install — see pip output above."
  PROBLEMS=$((PROBLEMS + 1))
fi

# ── Verdict ──────────────────────────────────────────────────────────────────────
okf_hd "Verdict"
if [ "$PROBLEMS" -eq 0 ]; then
  okf_ok "environment ready. Inventory a repo with:"
  okf_info "  working-memory/okf-postgres/scripts/okf-ingest.sh --repo ."
  exit 0
else
  okf_warn "$PROBLEMS item(s) need attention above. Resolve them and re-run the doctor."
  exit 1
fi
