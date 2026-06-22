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
