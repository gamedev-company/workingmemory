#!/bin/bash
# install.sh — working-memory-kit installer
#
# Installs the working-memory convention + (optionally) Claude Code harness glue
# into a target project. Idempotent against absence; conservative against presence.
#
# Usage:
#   ./install.sh [--target DIR] [--upgrade] [--with-agents] [--with-obsidian]
#
# Default target: current directory. Run from inside the kit repo, OR pipe via
# curl with KIT_URL pointing to a release tarball.

set -e

WORKING_MEMORY_KIT_VERSION="0.3.0"

# ── Defaults ──────────────────────────────────────────────────────────────────
TARGET="$PWD"
UPGRADE=0
WITH_AGENTS=0
WITH_OBSIDIAN=0
RECALL=-1   # tri-state: -1 ask, 0 skip, 1 set up now (the okf-postgres recall layer)

# ── Parse args ────────────────────────────────────────────────────────────────
while [ $# -gt 0 ]; do
  case "$1" in
    --target)        TARGET="$2"; shift 2;;
    --target=*)      TARGET="${1#*=}"; shift;;
    --upgrade)       UPGRADE=1; shift;;
    --with-agents)   WITH_AGENTS=1; shift;;
    --with-obsidian) WITH_OBSIDIAN=1; shift;;
    --with-recall)   RECALL=1; shift;;
    --no-recall)     RECALL=0; shift;;
    -h|--help)
      cat <<EOF
working-memory-kit installer v${WORKING_MEMORY_KIT_VERSION}

Usage: install.sh [options]

Options:
  --target DIR        Install into DIR (default: current directory)
  --upgrade           Refresh CLAUDE.md sentinel block + harness glue without
                      touching working-memory/ content
  --with-agents       Also install the journalist agent (.claude/agents/journalist.md)
  --with-obsidian     Also install the .obsidian/ vault config
  --with-recall       Set up the Postgres recall layer + inventory the project now
                      (macOS only; runs working-memory/okf-postgres/scripts/okf-doctor.sh
                      + okf-ingest.sh — the engine ships inside the vault)
  --no-recall         Don't offer the recall-layer setup (skip the prompt)
  -h, --help          Show this help

What gets installed:
  CONTENT (always):
    working-memory/                  Skeleton with System.md, Index.md,
                                     short-term.md, empty tier directories
    working-memory/okf-postgres/     Postgres recall engine (Python pkg + scripts +
                                     schema); inert until you run its setup (below)
    CLAUDE.md                        Documentation Discipline section added
                                     (bounded by sentinel markers, idempotent)

  CLAUDE CODE HARNESS (auto-detected — only if .claude/ exists in target):
    .claude/hooks/working-memory-stale-hot.sh
    .claude/commands/working-memory.md
    .claude/commands/working-memory-lint.md
    .claude/commands/working-memory-update.md
    .claude/settings.local.json      Stop-hook registered (merged via jq)

  OPTIONAL:
    --with-agents:    .claude/agents/journalist.md
    --with-obsidian:  working-memory/.obsidian/ (app.json, core-plugins.json,
                                                 daily-notes.json, templates.json)

Conflict policy: conservative. Existing working-memory/ aborts install with
a re-run-with-upgrade message. CLAUDE.md patched only between sentinel markers.
settings merged via jq; conflicting Stop hook aborts with manual-resolution note.
EOF
      exit 0;;
    *) echo "Unknown flag: $1" >&2; echo "Run with --help for usage." >&2; exit 2;;
  esac
done

# ── Resolve paths ─────────────────────────────────────────────────────────────
# Locate the kit's own root (where this script lives)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Resolve target to absolute path
TARGET="$(cd "$TARGET" 2>/dev/null && pwd)" || { echo "Target does not exist: $TARGET" >&2; exit 1; }

CONTENT_SRC="$SCRIPT_DIR/content"
HARNESS_SRC="$SCRIPT_DIR/claude-harness"

if [ ! -d "$CONTENT_SRC" ]; then
  echo "Cannot find content/ next to install.sh ($CONTENT_SRC missing)." >&2
  echo "This installer expects to run from inside the working-memory-kit repo." >&2
  exit 1
fi

# ── Helpers ───────────────────────────────────────────────────────────────────
say()  { printf '%s\n' "$*"; }
warn() { printf 'warn: %s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

need() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

# ── Recall layer (okf-postgres) offer ─────────────────────────────────────────
# After the content/harness install, optionally bootstrap the Postgres recall
# layer and inventory the target repo into knowledge cards. macOS-only; the heavy
# lifting (Ollama, Postgres, models, schema, venv, the index sweep) lives in the
# engine that ships INSIDE the vault at working-memory/okf-postgres/scripts/.
# Honors --with-recall (1) / --no-recall (0); otherwise asks.
offer_recall_setup() {
  local engine="$TARGET_WM/okf-postgres"
  local doctor="$engine/scripts/okf-doctor.sh"
  local ingest="$engine/scripts/okf-ingest.sh"

  # Nothing to offer if the recall layer isn't shipped alongside this installer.
  [ -x "$ingest" ] || return 0
  # Explicit opt-out.
  [ "$RECALL" -eq 0 ] && return 0

  # macOS-only for now (Linux/Windows left to the community).
  if [ "$(uname)" != "Darwin" ]; then
    [ "$RECALL" -eq 1 ] && warn "--with-recall ignored: the recall layer is macOS-only for now."
    return 0
  fi

  say ""
  say "━━━ Optional: Postgres recall layer (okf-postgres) ━━━"
  say "Inventories this project into per-folder knowledge cards (embeddings + full-text"
  say "in Postgres) so an agent recalls the codebase instead of re-reading it. Setup"
  say "verifies/installs Ollama + models + Postgres, then runs the inventory sweep."
  say ""

  local do_it=0 reply="" yes_flag=""
  if [ "$RECALL" -eq 1 ]; then
    do_it=1
    # Explicit --with-recall is non-interactive intent: let the sub-scripts auto-yes
    # (install Ollama / pull models / install Postgres.app without re-prompting).
    yes_flag="--yes"
  elif [ ! -t 0 ]; then
    say "[recall] non-interactive shell — skipping. Run setup later with:"
  else
    printf 'Set up the recall layer and inventory this project now? [y/N] '
    read -r reply || reply=""
    case "$reply" in [Yy]*) do_it=1;; esac
  fi

  if [ "$do_it" -eq 1 ]; then
    say ""
    say "[recall] bootstrapping environment + inventorying $TARGET …"
    # --bootstrap chains the doctor; pass the project name from the target's basename.
    "$ingest" --bootstrap $yes_flag --repo "$TARGET" --project "$(basename "$TARGET")" || {
      warn "recall setup did not complete cleanly — see output above."
      warn "you can re-run it any time: $ingest --bootstrap --repo \"$TARGET\""
      return 0
    }
  else
    say ""
    say "[recall] skipped. The engine ships inside your vault — set it up later with:"
    say "  working-memory/okf-postgres/scripts/okf-doctor.sh            # verify/install env"
    say "  working-memory/okf-postgres/scripts/okf-ingest.sh --repo .   # inventory into cards"
    say "Or in one shot: working-memory/okf-postgres/scripts/okf-ingest.sh --bootstrap --repo ."
  fi
}

# ── Pre-flight ────────────────────────────────────────────────────────────────
need cp
need mkdir
# jq is only needed if .claude/ exists — check later

say "━━━ working-memory-kit installer v${WORKING_MEMORY_KIT_VERSION} ━━━"
say ""
say "target: $TARGET"
[ "$UPGRADE" -eq 1 ]      && say "mode:   upgrade (CLAUDE.md + harness refresh; content untouched)"
[ "$WITH_AGENTS" -eq 1 ]  && say "flags:  --with-agents (journalist agent)"
[ "$WITH_OBSIDIAN" -eq 1 ] && say "flags:  --with-obsidian (.obsidian/ vault config)"
say ""

# ── Step 1: Content install ───────────────────────────────────────────────────
TARGET_WM="$TARGET/working-memory"

if [ -d "$TARGET_WM" ]; then
  if [ "$UPGRADE" -eq 1 ]; then
    say "[content] working-memory/ exists; --upgrade mode — leaving content untouched"
  else
    die "working-memory/ already exists at $TARGET.
Re-run with --upgrade to refresh CLAUDE.md and harness glue, or
remove the existing directory if you want a fresh install."
  fi
else
  say "[content] installing working-memory/ skeleton"
  cp -R "$CONTENT_SRC/working-memory" "$TARGET_WM"
  # Remove .obsidian unless requested
  if [ "$WITH_OBSIDIAN" -eq 0 ] && [ -d "$TARGET_WM/.obsidian" ]; then
    rm -rf "$TARGET_WM/.obsidian"
  fi
  # The okf-postgres engine now ships inside the vault. Strip any local-only build
  # artifacts that a dev's working copy may carry (cp -R would otherwise drag a
  # 100MB+ .venv with stale paths into every target). The doctor rebuilds .venv
  # in-place per project.
  if [ -d "$TARGET_WM/okf-postgres" ]; then
    rm -rf "$TARGET_WM/okf-postgres/.venv" \
           "$TARGET_WM/okf-postgres/.okf-env" \
           "$TARGET_WM/okf-postgres/test-vault" \
           "$TARGET_WM/okf-postgres/build" \
           "$TARGET_WM/okf-postgres/okfmem.egg-info"
    find "$TARGET_WM/okf-postgres" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null || true
  fi
  # Inject today's date (OKF timestamp + legacy updated) into short-term.md template
  today=$(date +%Y-%m-%d)
  now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  if [ -f "$TARGET_WM/short-term.md" ]; then
    sedi() { if [ "$(uname)" = "Darwin" ]; then sed -i '' "$1" "$2"; else sed -i "$1" "$2"; fi; }
    sedi "s/updated: YYYY-MM-DD/updated: $today/" "$TARGET_WM/short-term.md"
    # Stamp the OKF timestamp placeholder across all shipped templates that carry it
    for f in short-term.md Index.md System.md; do
      [ -f "$TARGET_WM/$f" ] && sedi "s/timestamp: YYYY-MM-DDTHH:MM:SSZ/timestamp: $now/" "$TARGET_WM/$f"
    done
  fi
fi

# ── Step 2: CLAUDE.md patch ───────────────────────────────────────────────────
TARGET_CLAUDE_MD="$TARGET/CLAUDE.md"
SNIPPET="$CONTENT_SRC/claude-md-snippet.md"
SENTINEL_BEGIN="<!-- working-memory-kit:begin"
SENTINEL_END="<!-- working-memory-kit:end -->"

if [ ! -f "$TARGET_CLAUDE_MD" ]; then
  say "[claude.md] creating CLAUDE.md with Documentation Discipline section"
  cp "$SNIPPET" "$TARGET_CLAUDE_MD"
elif grep -qF "$SENTINEL_BEGIN" "$TARGET_CLAUDE_MD"; then
  say "[claude.md] sentinel markers found; replacing block in place"
  # Use awk to replace content between sentinels (inclusive of sentinel lines)
  tmp="$(mktemp)"
  awk -v snippet_file="$SNIPPET" '
    /^<!-- working-memory-kit:begin/ { in_block=1; while ((getline line < snippet_file) > 0) print line; next }
    /^<!-- working-memory-kit:end -->/ { in_block=0; next }
    !in_block { print }
  ' "$TARGET_CLAUDE_MD" > "$tmp"
  mv "$tmp" "$TARGET_CLAUDE_MD"
else
  say "[claude.md] sentinels not found; appending Documentation Discipline section"
  printf '\n' >> "$TARGET_CLAUDE_MD"
  cat "$SNIPPET" >> "$TARGET_CLAUDE_MD"
fi

# ── Step 3: Claude Code detection ─────────────────────────────────────────────
TARGET_CLAUDE_DIR="$TARGET/.claude"

if [ ! -d "$TARGET_CLAUDE_DIR" ]; then
  say ""
  say "[harness] .claude/ not found in target — skipping Claude Code harness install."
  say "          Content-only install complete. The Documentation Discipline section is in CLAUDE.md."
  say "          If you adopt Claude Code later, re-run install.sh with --upgrade to install hooks + slash commands."
  say ""
  say "━━━ Next steps ━━━"
  say "  1. Read working-memory/System.md to learn the convention"
  say "  2. Seed working-memory/short-term.md with current project context"
  say "  3. Create today's journal: working-memory/journals/$(date +%Y-%m-%d).md"
  offer_recall_setup
  exit 0
fi

# ── Step 4: Harness install ───────────────────────────────────────────────────
need jq

say "[harness] .claude/ detected — installing hooks + slash commands"

mkdir -p "$TARGET_CLAUDE_DIR/hooks" "$TARGET_CLAUDE_DIR/commands"

# Hook
HOOK_TARGET="$TARGET_CLAUDE_DIR/hooks/working-memory-stale-hot.sh"
if [ -f "$HOOK_TARGET" ] && [ "$UPGRADE" -eq 0 ]; then
  warn "$HOOK_TARGET exists; skipping (run with --upgrade to replace)"
else
  cp "$HARNESS_SRC/hooks/working-memory-stale-hot.sh" "$HOOK_TARGET"
  chmod +x "$HOOK_TARGET"
  say "          installed hooks/working-memory-stale-hot.sh"
fi

# Slash commands
for cmd in working-memory.md working-memory-lint.md working-memory-update.md; do
  CMD_TARGET="$TARGET_CLAUDE_DIR/commands/$cmd"
  if [ -f "$CMD_TARGET" ] && [ "$UPGRADE" -eq 0 ]; then
    warn "$CMD_TARGET exists; skipping (run with --upgrade to replace)"
  else
    cp "$HARNESS_SRC/commands/$cmd" "$CMD_TARGET"
    say "          installed commands/$cmd"
  fi
done

# Journalist agent (gated)
if [ "$WITH_AGENTS" -eq 1 ]; then
  mkdir -p "$TARGET_CLAUDE_DIR/agents"
  AGENT_TARGET="$TARGET_CLAUDE_DIR/agents/journalist.md"
  if [ -f "$AGENT_TARGET" ] && [ "$UPGRADE" -eq 0 ]; then
    warn "$AGENT_TARGET exists; skipping (run with --upgrade to replace)"
  else
    cp "$HARNESS_SRC/agents/journalist.md" "$AGENT_TARGET"
    say "          installed agents/journalist.md"
  fi
fi

# ── Step 5: Settings merge ────────────────────────────────────────────────────
# Prefer settings.local.json; fall back to settings.json
SETTINGS_TARGET="$TARGET_CLAUDE_DIR/settings.local.json"
[ ! -f "$SETTINGS_TARGET" ] && [ -f "$TARGET_CLAUDE_DIR/settings.json" ] && SETTINGS_TARGET="$TARGET_CLAUDE_DIR/settings.json"

SNIPPET_JSON="$HARNESS_SRC/settings.snippet.json"

if [ ! -f "$SETTINGS_TARGET" ]; then
  say "[settings] creating $SETTINGS_TARGET with Stop hook registered"
  cp "$SNIPPET_JSON" "$SETTINGS_TARGET"
else
  # Check for conflicting Stop hooks
  existing_stop=$(jq -r '.hooks.Stop // empty' "$SETTINGS_TARGET")
  hook_path='${CLAUDE_PROJECT_DIR}/.claude/hooks/working-memory-stale-hot.sh'

  if [ -n "$existing_stop" ]; then
    # Check if our hook is already registered
    if jq -e --arg p "$hook_path" '
      .hooks.Stop // [] | map(.hooks // []) | flatten | map(.command) | any(. == $p)
    ' "$SETTINGS_TARGET" >/dev/null; then
      say "[settings] hook already registered — no change"
    else
      say "[settings] merging Stop hook into existing settings"
      tmp="$(mktemp)"
      jq --slurpfile snippet "$SNIPPET_JSON" '
        .hooks.Stop = (.hooks.Stop // []) + $snippet[0].hooks.Stop
      ' "$SETTINGS_TARGET" > "$tmp"
      mv "$tmp" "$SETTINGS_TARGET"
    fi
  else
    say "[settings] no existing Stop hooks; merging in"
    tmp="$(mktemp)"
    jq --slurpfile snippet "$SNIPPET_JSON" '
      .hooks = (.hooks // {}) | .hooks.Stop = $snippet[0].hooks.Stop
    ' "$SETTINGS_TARGET" > "$tmp"
    mv "$tmp" "$SETTINGS_TARGET"
  fi
fi

# ── Done ──────────────────────────────────────────────────────────────────────
say ""
say "━━━ install complete (v${WORKING_MEMORY_KIT_VERSION}) ━━━"
say ""
say "Content:"
say "  working-memory/System.md     ← read this first to learn the convention"
say "  working-memory/Index.md      ← Map of Content (currently empty)"
say "  working-memory/short-term.md ← session-boot brief (seed this)"
say "  CLAUDE.md                    ← Documentation Discipline section added"
say ""
say "Harness:"
say "  .claude/hooks/working-memory-stale-hot.sh"
say "  .claude/commands/working-memory{,-lint,-update}.md"
[ "$WITH_AGENTS" -eq 1 ] && say "  .claude/agents/journalist.md"
say "  .claude/settings.local.json  (Stop hook registered)"
say ""
say "Next steps:"
say "  1. Read working-memory/System.md"
say "  2. Seed working-memory/short-term.md"
say "  3. Create today's journal: working-memory/journals/$(date +%Y-%m-%d).md"
say "  4. In Claude Code, run /working-memory to verify the harness"

offer_recall_setup
