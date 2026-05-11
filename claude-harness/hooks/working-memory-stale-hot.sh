#!/bin/bash
# working-memory-stale-hot.sh — Stop hook that reminds the agent to update short-term.md
#
# Fires on every Stop event. Tracks turn count per session.
# After 10+ turns, if short-term.md hasn't been modified this session,
# injects a gentle reminder every 15 turns.
#
# Ultra-lightweight: file stat checks + counter. No LLM calls.
#
# Part of the working-memory-kit: https://github.com/landongn/workingmemory

set -e

# Read JSON input from stdin
input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id // empty')
cwd=$(echo "$input" | jq -r '.cwd // empty')

# Bail if we can't determine session or cwd
if [ -z "$session_id" ] || [ -z "$cwd" ]; then
  echo '{"continue": true}'
  exit 0
fi

short_term="$cwd/working-memory/short-term.md"
counter="/tmp/working-memory-short-term-$session_id"
stamp="/tmp/working-memory-short-term-$session_id.start"

# Session-start stamp: created once on first turn, never re-written.
# This file's mtime is the ground truth for "when did this session begin?"
# Comparing short-term.md's mtime to this stamp tells us whether short-term.md
# was touched at any point during the session — without being polluted by the
# counter's per-turn writes.
[ -f "$stamp" ] || : > "$stamp"

# Initialize or increment turn counter (separate file from the stamp)
if [ -f "$counter" ]; then
  count=$(cat "$counter")
  count=$((count + 1))
else
  count=1
fi
echo "$count" > "$counter"

# Only check after 10+ turns (skip trivial sessions)
if [ "$count" -lt 10 ]; then
  echo '{"continue": true}'
  exit 0
fi

# Only remind every 15 turns to avoid noise
if [ "$((count % 15))" -ne 0 ]; then
  echo '{"continue": true}'
  exit 0
fi

# Check if short-term.md exists
if [ ! -f "$short_term" ]; then
  echo '{"continue": true, "systemMessage": "Reminder: working-memory/short-term.md does not exist yet. Create it with current STATUS, active PLAN entries, BLOCKERs, and HANDOFFs so the next session can bootstrap efficiently. See working-memory/System.md for the taxonomy."}'
  exit 0
fi

# Check if short-term.md was modified at any point during this session.
# Compare against the session-start stamp (created once on turn 1), NOT the
# counter (which gets re-written every turn and would always be newer).
if [ "$(uname)" = "Darwin" ]; then
  stamp_mtime=$(stat -f %m "$stamp" 2>/dev/null)
  short_mtime=$(stat -f %m "$short_term" 2>/dev/null)
else
  stamp_mtime=$(stat -c %Y "$stamp" 2>/dev/null)
  short_mtime=$(stat -c %Y "$short_term" 2>/dev/null)
fi

if [ -n "$stamp_mtime" ] && [ -n "$short_mtime" ] && [ "$short_mtime" -lt "$stamp_mtime" ]; then
  echo '{"continue": true, "systemMessage": "Reminder: working-memory/short-term.md has not been updated this session. Refresh it so the next session bootstraps efficiently — promote durable INSIGHTs to journal, drop stale STATUS, update active PLAN entries."}'
  exit 0
fi

# short-term.md is fresh — nothing to do
echo '{"continue": true}'
exit 0
