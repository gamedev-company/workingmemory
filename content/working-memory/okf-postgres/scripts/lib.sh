#!/bin/bash
# lib.sh — shared helpers for the okf-postgres setup scripts (doctor + ingest).
#
# Sourced, never executed. macOS-only by design (see okf_require_macos). Keeps the
# Postgres.app / Ollama / venv resolution logic in one place so okf-doctor.sh and
# okf-ingest.sh agree on where things live.

# ── Pretty output ───────────────────────────────────────────────────────────────
okf_say()  { printf '%s\n' "$*"; }
okf_info() { printf '  %s\n' "$*"; }
okf_ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
okf_warn() { printf '  \033[33m!\033[0m %s\n' "$*" >&2; }
okf_die()  { printf '\033[31merror:\033[0m %s\n' "$*" >&2; exit 1; }
okf_hd()   { printf '\n\033[1m━━━ %s ━━━\033[0m\n' "$*"; }

# ── Interaction ─────────────────────────────────────────────────────────────────
# okf_ask_yn "Prompt" default(Y|N)  → returns 0 for yes, 1 for no.
# Honors OKF_ASSUME_YES=1 (non-interactive) and a missing TTY (defaults to `default`).
okf_ask_yn() {
  local prompt="$1" default="${2:-N}" reply
  if [ "${OKF_ASSUME_YES:-0}" = "1" ]; then return 0; fi
  if [ ! -t 0 ]; then
    [ "$default" = "Y" ] && return 0 || return 1
  fi
  local hint="[y/N]"; [ "$default" = "Y" ] && hint="[Y/n]"
  printf '%s %s ' "$prompt" "$hint"
  read -r reply || reply=""
  reply="${reply:-$default}"
  case "$reply" in [Yy]*) return 0;; *) return 1;; esac
}

# ── Platform ────────────────────────────────────────────────────────────────────
okf_require_macos() {
  if [ "$(uname)" != "Darwin" ]; then
    okf_die "the okf-postgres setup currently supports macOS only.
Linux/Windows are intentionally left to the community — see okf-postgres/README.md.
You can still run the Python pipeline directly if you provision Postgres + Ollama
yourself: .venv/bin/python -m okfmem.cli index"
  fi
}

okf_have() { command -v "$1" >/dev/null 2>&1; }

# ── Paths ───────────────────────────────────────────────────────────────────────
# The okf-postgres/ root, derived from this lib's location (scripts/ is one below).
okf_root() { (cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd); }

# Python interpreter inside the package venv (may not exist yet — caller checks).
okf_venv_python() { printf '%s/.venv/bin/python\n' "$(okf_root)"; }

# ── Postgres.app / psql resolution ──────────────────────────────────────────────
# Postgres.app keeps its binaries OUT of PATH on purpose. Resolve a usable psql:
# first anything already on PATH, then the Postgres.app bundle's bin dir.
OKF_PGAPP_BIN="/Applications/Postgres.app/Contents/Versions/latest/bin"

okf_psql() {
  if okf_have psql; then command -v psql; return 0; fi
  if [ -x "$OKF_PGAPP_BIN/psql" ]; then printf '%s/psql\n' "$OKF_PGAPP_BIN"; return 0; fi
  return 1
}

okf_createdb() {
  if okf_have createdb; then command -v createdb; return 0; fi
  if [ -x "$OKF_PGAPP_BIN/createdb" ]; then printf '%s/createdb\n' "$OKF_PGAPP_BIN"; return 0; fi
  return 1
}

# Is a Postgres server reachable on localhost? Uses pg_isready when available,
# else a cheap psql connectivity probe against the maintenance db.
okf_pg_ready() {
  local pgr
  if okf_have pg_isready; then pgr="$(command -v pg_isready)"
  elif [ -x "$OKF_PGAPP_BIN/pg_isready" ]; then pgr="$OKF_PGAPP_BIN/pg_isready"; fi
  if [ -n "$pgr" ]; then "$pgr" -h localhost -q >/dev/null 2>&1 && return 0; fi
  local psql; psql="$(okf_psql)" || return 1
  "$psql" -h localhost -d postgres -tAc 'SELECT 1' >/dev/null 2>&1
}

# ── Ollama ──────────────────────────────────────────────────────────────────────
okf_ollama_up() { okf_have ollama && ollama list >/dev/null 2>&1; }

# Does Ollama already have a model whose name matches $1 (with or without :tag)?
okf_ollama_has_model() {
  local want="$1"
  ollama list 2>/dev/null | awk 'NR>1{print $1}' | grep -qiE "^${want%%:*}(:|$)" \
    && return 0
  ollama list 2>/dev/null | awk 'NR>1{print $1}' | grep -qx "$want"
}

# ── Database name resolution + safety ───────────────────────────────────────────
# A valid bare Postgres identifier we're willing to create: starts with a letter or
# underscore, then letters/digits/underscores, max 63 chars. Rejects anything that
# would need quoting (and anything that smells like injection).
okf_valid_db_name() {
  printf '%s' "$1" | grep -qE '^[A-Za-z_][A-Za-z0-9_]{0,62}$'
}

# Resolve the canonical db name/DSN via the package config — the SINGLE source of
# truth, shared with the Python runtime. config.py is stdlib-only, so this works
# with the system python3 before any venv exists. Pass the repo; optional override
# is the --db value (exported as OKF_DB_NAME for the precedence in config.py).
#   okf_db_value DB_NAME|DB_DSN  <repo>  [override]
okf_db_value() {
  local which="$1" repo="$2" override="$3"
  (
    export OKF_REPO="$repo" PYTHONPATH="$(okf_root)"
    [ -n "$override" ] && export OKF_DB_NAME="$override"
    python3 -c "from okfmem.config import ${which}; print(${which})"
  ) 2>/dev/null
}

# Is a DSN pointed at the local machine (so the doctor can manage it)?
okf_dsn_is_local() {
  case "$1" in
    *://localhost/*|*://localhost:*|*://localhost) return 0;;
    *://127.0.0.1*) return 0;;
    *:///*) return 0;;
    *) return 1;;
  esac
}

# Has this database been stamped as ours (okf_meta owner=okfmem)?
okf_db_is_ours() {  # psql db_name
  "$1" -h localhost -d "$2" -tAc \
    "SELECT 1 FROM okf_meta WHERE key='owner' AND value='okfmem'" 2>/dev/null | grep -q 1
}

# Count public tables in a database (0 for empty/new).
okf_db_table_count() {  # psql db_name
  local n
  n="$("$1" -h localhost -d "$2" -tAc \
    "SELECT count(*) FROM information_schema.tables WHERE table_schema='public'" 2>/dev/null)"
  printf '%s' "${n:-0}"
}

# Ensure a database exists, is SAFE to use, and carries our schema. Refuses to
# apply the schema over a pre-existing database that isn't ours and isn't empty.
# Writes <engine>/.okf-env pinning the name so every entry point agrees later.
#   okf_ensure_db psql createdb db_name db_dsn schema engine_dir
okf_ensure_db() {
  local psql="$1" createdb="$2" name="$3" dsn="$4" schema="$5" engine="$6"

  if ! okf_dsn_is_local "$dsn"; then
    okf_warn "OKF_DB_DSN points at a non-local host — the doctor won't create or"
    okf_info "migrate a remote database. Ensure '$name' exists with schema applied:"
    okf_info "  psql \"$dsn\" -f \"$schema\""
    return 1
  fi

  if "$psql" -h localhost -d postgres -tAc \
       "SELECT 1 FROM pg_database WHERE datname='$name'" 2>/dev/null | grep -q 1; then
    if okf_db_is_ours "$psql" "$name"; then
      okf_ok "database '$name' exists (okfmem-owned)"
    elif [ "$(okf_db_table_count "$psql" "$name")" = "0" ]; then
      okf_ok "database '$name' exists and is empty — adopting it"
    else
      okf_die "database '$name' already exists and contains tables NOT created by
okfmem. Refusing to apply our schema over someone else's data. Pick another name
with --db, or drop/rename '$name' first."
    fi
  else
    okf_info "creating database '$name'…"
    if [ -n "$createdb" ]; then "$createdb" -h localhost "$name"
    else "$psql" -h localhost -d postgres -c "CREATE DATABASE \"$name\"" >/dev/null; fi
    okf_ok "created database '$name'"
  fi

  if ! "$psql" "$dsn" -tAc \
       "SELECT 1 FROM pg_available_extensions WHERE name='vector'" 2>/dev/null | grep -q 1; then
    okf_warn "pgvector not available in this Postgres."
    okf_info "Postgres.app bundles it; for a brew server run: brew install pgvector"
    return 1
  fi

  okf_info "applying schema (idempotent)…"
  if PGOPTIONS='-c client_min_messages=warning' \
       "$psql" "$dsn" -v ON_ERROR_STOP=1 -q -f "$schema"; then
    okf_ok "schema applied to '$name'"
  else
    okf_warn "schema apply failed — see the psql error above."
    return 1
  fi

  okf_write_env "$engine" "$name"
}

# Pin the resolved db name so the commit hook + MCP launcher use the SAME database
# (even if the repo later moves and the derived name would change).
okf_write_env() {  # engine_dir db_name
  local f="$1/.okf-env"
  {
    printf '# okf-postgres — per-project settings (generated; safe to delete).\n'
    printf '# Pins the database so ingest, the commit hook, and the MCP server agree.\n'
    printf 'OKF_DB_NAME=%s\n' "$2"
  } > "$f" 2>/dev/null || true
}
