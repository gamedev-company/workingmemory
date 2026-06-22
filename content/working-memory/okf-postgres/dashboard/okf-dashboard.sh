#!/bin/bash
# okf-dashboard.sh — a live HTML view of a project's okf-postgres recall index.
#
# Fetches card data from Postgres with psql, renders a static HTML file through a
# tiny {{token}} template compiler (dashboard/template.html + card.html), and — by
# default — re-generates on an interval. Open the file in a browser; a <meta refresh>
# reloads it as the script rewrites it. No web server, no dependencies beyond psql.
# Pure POSIX-ish bash (works on macOS's stock bash 3.2 — no associative arrays).
#
# Usage:
#   okf-dashboard.sh [--repo DIR] [--db NAME] [--out FILE]
#                    [--interval SECONDS] [--once] [--open]
#
#   --repo DIR       project to view        (default: $OKF_REPO or cwd)
#   --db NAME        database to read        (default: the project's derived name)
#   --out FILE       output HTML path        (default: dashboard/index.html)
#   --interval N     seconds between rebuilds (default: 5)
#   --once           render a single time and exit (no loop)
#   --open           open the HTML in your browser after the first render
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../scripts/lib.sh
. "$SCRIPT_DIR/../scripts/lib.sh"

okf_require_macos

REPO="${OKF_REPO:-$PWD}"
DB_OVERRIDE=""
OUT=""
INTERVAL=5
ONCE=0
OPEN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --repo)       REPO="$2"; shift 2;;
    --repo=*)     REPO="${1#*=}"; shift;;
    --db)         DB_OVERRIDE="$2"; shift 2;;
    --db=*)       DB_OVERRIDE="${1#*=}"; shift;;
    --out)        OUT="$2"; shift 2;;
    --out=*)      OUT="${1#*=}"; shift;;
    --interval)   INTERVAL="$2"; shift 2;;
    --interval=*) INTERVAL="${1#*=}"; shift;;
    --once)       ONCE=1; shift;;
    --open)       OPEN=1; shift;;
    -h|--help)    sed -n '2,19p' "$0" | sed 's/^# \{0,1\}//'; exit 0;;
    *) okf_die "unknown flag: $1 (try --help)";;
  esac
done

REPO="$(cd "$REPO" 2>/dev/null && pwd)" || okf_die "repo path does not exist: $REPO"
if [ -n "$DB_OVERRIDE" ] && ! okf_valid_db_name "$DB_OVERRIDE"; then
  okf_die "--db '$DB_OVERRIDE' is not a valid database name."
fi
PROJECT="$(basename "$REPO")"
DB_NAME="$(okf_db_value DB_NAME "$REPO" "$DB_OVERRIDE")"
DB_DSN="$(okf_db_value DB_DSN "$REPO" "$DB_OVERRIDE")"
[ -n "$DB_NAME" ] || okf_die "could not resolve a database name (is python3 on PATH?)."
OUT="${OUT:-$SCRIPT_DIR/index.html}"

PSQL="$(okf_psql)" || okf_die "no psql found (is Postgres.app installed?)."
okf_pg_ready || okf_die "Postgres not reachable on localhost. Start it and retry."

PAGE_TPL="$(cat "$SCRIPT_DIR/template.html")"
CARD_TPL="$(cat "$SCRIPT_DIR/card.html")"

# ── The "quick and dirty template compiler" ─────────────────────────────────────
# Bash's ${var//find/replace} is a LITERAL replacement (no regex / no `&` hazards),
# so any HTML-escaped value drops in safely. No associative arrays → bash 3.2 OK.
html_escape() {
  local s="$1"
  s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"; s="${s//\"/&quot;}"
  printf '%s' "$s"
}

render_card() {  # resource title desc tags_html updated covered freshness label
  local o="$CARD_TPL"
  o="${o//'{{RESOURCE}}'/$1}"; o="${o//'{{TITLE}}'/$2}"
  o="${o//'{{DESCRIPTION}}'/$3}"; o="${o//'{{TAGS}}'/$4}"
  o="${o//'{{UPDATED}}'/$5}"; o="${o//'{{COVERED}}'/$6}"
  o="${o//'{{FRESHNESS}}'/$7}"; o="${o//'{{FRESHNESS_LABEL}}'/$8}"
  printf '%s' "$o"
}

render_page() {  # project db generated total stale refresh cards
  local o="$PAGE_TPL"
  o="${o//'{{PROJECT}}'/$1}"; o="${o//'{{DB}}'/$2}"
  o="${o//'{{GENERATED}}'/$3}"; o="${o//'{{TOTAL}}'/$4}"
  o="${o//'{{STALE_COUNT}}'/$5}"; o="${o//'{{REFRESH}}'/$6}"
  o="${o//'{{CARDS}}'/$7}"
  printf '%s' "$o"
}

LAST_TOTAL=0 LAST_STALE=0

build() {
  # Which cards have drifted? Ask okfmem (it does the git-sha comparison). The list
  # is card vault-paths, one per line. If the venv isn't built we just show all fresh.
  local stale_list="" vpy; vpy="$(okf_venv_python)"
  if [ -x "$vpy" ]; then
    stale_list="$(OKF_REPO="$REPO" OKF_DB_NAME="$DB_NAME" "$vpy" -m okfmem.cli stale 2>/dev/null \
                  | awk '/^STALE/{print $2}')"
  fi

  local stale_html="" fresh_html="" total=0 stale_n=0
  local resource title desc tags updated covered path
  while IFS=$'\t' read -r resource title desc tags updated covered path; do
    [ -z "$path" ] && continue
    total=$((total + 1))

    local fresh="fresh" label="fresh"
    if [ -n "$stale_list" ] && printf '%s\n' "$stale_list" | grep -qxF "$path"; then
      fresh="stale"; label="stale"; stale_n=$((stale_n + 1))
    fi

    local chips="" t oldifs="$IFS"
    IFS=','
    for t in $tags; do [ -n "$t" ] && chips="$chips<span class=\"chip\">$(html_escape "$t")</span>"; done
    IFS="$oldifs"

    local files_label="$covered file"; [ "$covered" = "1" ] || files_label="$covered files"
    local card
    card="$(render_card "$(html_escape "$resource")" "$(html_escape "$title")" \
              "$(html_escape "$desc")" "$chips" "$(html_escape "$updated")" \
              "$files_label" "$fresh" "$label")"
    # Stale first, so what needs attention floats to the top.
    if [ "$fresh" = "stale" ]; then stale_html="$stale_html$card"$'\n'
    else fresh_html="$fresh_html$card"$'\n'; fi
  done < <("$PSQL" "$DB_DSN" -tAF $'\t' -c "
      SELECT coalesce(resource, '(root)'),
             coalesce(title, ''),
             coalesce(description, ''),
             array_to_string(tags, ','),
             coalesce(to_char(doc_timestamp, 'YYYY-MM-DD HH24:MI'), '—'),
             (SELECT count(*) FROM card_sources cs WHERE cs.document_id = d.id),
             path
      FROM documents d
      WHERE type = 'feature-card'
      ORDER BY resource;" 2>/dev/null)

  local cards="$stale_html$fresh_html"
  [ "$total" -eq 0 ] && cards='      <p class="empty">No cards yet — run okf-ingest.sh to inventory this project.</p>'

  # Atomic write: render to a temp file, then mv into place so the browser (which is
  # polling this path) never reads a half-written page.
  render_page "$(html_escape "$PROJECT")" "$(html_escape "$DB_NAME")" \
              "$(date '+%Y-%m-%d %H:%M:%S')" "$total" "$stale_n" "$INTERVAL" "$cards" \
    > "$OUT.tmp" && mv "$OUT.tmp" "$OUT"
  LAST_TOTAL=$total; LAST_STALE=$stale_n
}

mkdir -p "$(dirname "$OUT")"
build
okf_ok "wrote $OUT  ($LAST_TOTAL cards, $LAST_STALE stale)"
okf_info "open it: file://$OUT"
[ "$OPEN" -eq 1 ] && { open "$OUT" 2>/dev/null || true; }

if [ "$ONCE" -eq 1 ]; then exit 0; fi

okf_info "regenerating every ${INTERVAL}s — Ctrl-C to stop."
while :; do
  sleep "$INTERVAL"
  build
  printf '  [%s] %s cards, %s stale\n' "$(date '+%H:%M:%S')" "$LAST_TOTAL" "$LAST_STALE"
done
