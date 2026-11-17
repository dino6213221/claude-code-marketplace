#!/usr/bin/env bash
# Gate summary of handoff files (stdout, a few lines per file) — the orchestrator runs this instead of
# reading whole handoff files into its context.
#   gate.sh <KEY>            — every handoff file of the issue + state.json + gate rejections
#   gate.sh <KEY> <file>...  — only the named files (e.g. 02-architecture.md)
# Per file: status, unmet criteria, size against the guideline, "Open questions" lines verbatim.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../hooks/lib.sh"
KEY="${1:-}"; [ -n "$KEY" ] || { echo "usage: gate.sh <KEY> [file ...]"; exit 1; }
shift
D="$(agents_dir)/$KEY"
[ -d "$D" ] || { echo "No handoff directory: $D"; exit 1; }

SIZE=""
if [ -f "$D/state.json" ] && command -v jq >/dev/null; then
  SIZE=$(jq -r '.size // empty' "$D/state.json" 2>/dev/null || true)
  echo "state: $(jq -c . "$D/state.json" 2>/dev/null || echo invalid)"
fi
case "$SIZE" in S) LIMIT=30; KB=4 ;; M) LIMIT=80; KB=10 ;; *) LIMIT=0; KB=0 ;; esac

H_CRIT='^## (Success criteria|Kryteria sukcesu)'
H_OPEN='^## (Open questions|Otwarte pytania)'
[ $# -gt 0 ] || set -- 01-analysis.md 02-architecture.md 03-test-plan.md 04-implementation.md 05-review.md 06-qa.md
for F in "$@"; do
  P="$D/${F##*/}"
  [ -f "$P" ] || continue
  STATUS=$(head -1 "$P" | sed -n 's/^STATUS: *\([A-Z_]*\).*/\1/p')
  UNMET=$(awk -v h="$H_CRIT" '$0 ~ h {f=1; next} /^## /{f=0} f' "$P" | grep -c '\[ \]' || true)
  LINES=$(wc -l < "$P" | tr -d ' '); BYTES=$(wc -c < "$P" | tr -d ' ')
  NOTE=""
  if [ "$LIMIT" -gt 0 ] && { [ "$LINES" -gt "$LIMIT" ] || [ "$BYTES" -gt $((KB * 1024)) ]; }; then
    NOTE=" — over the size $SIZE guideline ($LIMIT lines / $KB KB)"
  fi
  echo "${F##*/}: STATUS ${STATUS:-MISSING} · unmet criteria $UNMET · $LINES lines, $((BYTES / 1024)) KB$NOTE"
  awk -v h="$H_CRIT" '$0 ~ h {f=1; next} /^## /{f=0} f && /\[ \]/' "$P" | sed 's/^/  unmet: /'
  awk -v h="$H_OPEN" '$0 ~ h {f=1; next} /^## /{f=0} f && NF' "$P" | cut -c1-600 | sed 's/^/  open: /'
done
if [ -f "$D/timings.log" ]; then
  R=$(grep -c 'rejected\|failed-passed-through' "$D/timings.log" || true)
  [ "$R" -gt 0 ] && { echo "gate rejections: $R"; grep 'rejected\|failed-passed-through' "$D/timings.log" | cut -f2,3,4,6 | sed 's/^/  /'; }
fi
exit 0
