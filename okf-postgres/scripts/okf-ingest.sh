#!/bin/bash
# okf-ingest.sh — inventory a codebase into the OKF recall index.
#
# Walks the target repo, explores it into sections (one knowledge card per
# code-bearing folder), and writes each card to the markdown vault + Postgres via
# the okfmem pipeline (a small LOCAL model does the summarizing — no cloud tokens).
#
# This is the "seed" step. It assumes the environment is ready; pass --bootstrap to
# run okf-doctor.sh first (install/verify Ollama, Postgres, models, schema, venv).
#
# Usage:
#   okf-ingest.sh [--repo DIR] [--project NAME] [--bootstrap] [--with-hook] [--yes]
#
#   --repo DIR     repo to inventory      (default: current directory)
#   --project NAME tag cards with project (default: repo's basename)
#   --bootstrap    run okf-doctor.sh first to provision/verify the environment
#   --with-hook    install the git post-commit hook so cards auto-refresh on commit
#   --yes          assume "yes" to prompts (passed through to the doctor)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

okf_require_macos

REPO="$PWD"
PROJECT=""
BOOTSTRAP=0
WITH_HOOK=0
ROOT="$(okf_root)"

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)       REPO="$2"; shift 2;;
    --repo=*)     REPO="${1#*=}"; shift;;
    --project)    PROJECT="$2"; shift 2;;
    --project=*)  PROJECT="${1#*=}"; shift;;
    --bootstrap)  BOOTSTRAP=1; shift;;
    --with-hook)  WITH_HOOK=1; shift;;
    --yes|-y)     export OKF_ASSUME_YES=1; shift;;
    -h|--help)    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) okf_die "unknown flag: $1 (try --help)";;
  esac
done

REPO="$(cd "$REPO" 2>/dev/null && pwd)" || okf_die "repo path does not exist: $REPO"
[ -z "$PROJECT" ] && PROJECT="$(basename "$REPO")"
VAULT="${OKF_VAULT:-$REPO/working-memory}"

okf_hd "okf-ingest → $PROJECT"
okf_info "repo:    $REPO"
okf_info "vault:   $VAULT"
okf_info "project: $PROJECT"

# ── Optional environment bootstrap ───────────────────────────────────────────────
if [ "$BOOTSTRAP" -eq 1 ]; then
  "$SCRIPT_DIR/okf-doctor.sh" ${OKF_ASSUME_YES:+--yes} \
    || okf_die "doctor reported problems; resolve them (above) before ingesting."
fi

# ── Pre-flight: the things ingestion actually needs ──────────────────────────────
VENV_PY="$(okf_venv_python)"
[ -x "$VENV_PY" ] || okf_die "okfmem venv missing ($VENV_PY).
Run with --bootstrap, or: okf-postgres/scripts/okf-doctor.sh"
okf_ollama_up || okf_die "Ollama server not reachable. Start it ('ollama serve') or run with --bootstrap."
okf_pg_ready  || okf_die "Postgres not reachable on localhost. Run with --bootstrap or start Postgres.app."

# The vault is where cards are written; the kit's installer normally creates it, but
# ingest can stand alone, so make sure at least cards/ exists.
mkdir -p "$VAULT/cards"

# ── Run the inventory sweep ──────────────────────────────────────────────────────
okf_hd "Inventorying (one card per code folder — local model is writing)"
okf_info "First run downloads nothing but does call the model per folder; large repos"
okf_info "can take a while. Progress prints one line per folder below."
echo

set +e
OKF_REPO="$REPO" OKF_VAULT="$VAULT" \
  "$VENV_PY" -m okfmem.cli --project "$PROJECT" index
RC=$?
set -e
[ "$RC" -eq 0 ] || okf_die "ingestion exited non-zero ($RC). See output above."

# ── Optional: auto-refresh hook ──────────────────────────────────────────────────
if [ "$WITH_HOOK" -eq 1 ]; then
  okf_hd "Installing post-commit auto-refresh hook"
  if [ ! -d "$REPO/.git" ]; then
    okf_warn "$REPO is not a git repo — skipping hook install."
  else
    HOOK_SRC="$ROOT/hooks/post-commit"
    HOOK_DST="$REPO/.git/hooks/post-commit"
    if [ -e "$HOOK_DST" ]; then
      okf_warn "a post-commit hook already exists at $HOOK_DST — not overwriting."
      okf_info "Merge by hand if you want auto-refresh; the source is $HOOK_SRC."
    else
      # Materialize the hook with this okf-postgres dir baked in (replaces the
      # __OKF_POSTGRES_DIR__ placeholder so it needs no further editing).
      sed "s#__OKF_POSTGRES_DIR__#$ROOT#g" "$HOOK_SRC" > "$HOOK_DST"
      chmod +x "$HOOK_DST"
      okf_ok "installed $HOOK_DST (enrich-changed runs in the background on commit)"
    fi
  fi
fi

# ── Done ─────────────────────────────────────────────────────────────────────────
okf_hd "Done"
okf_ok "Inventory complete. Cards live in $VAULT/cards/ and in Postgres."
okf_info "Try a recall:"
okf_info "  OKF_REPO=$REPO $VENV_PY -m okfmem.cli recall \"how does X work\""
okf_info "Wire it into Claude Code: copy okf-postgres/mcp.example.json's mcpServers"
okf_info "block into this project's .mcp.json (set OKF_REPO=$REPO)."
