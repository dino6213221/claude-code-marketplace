#!/usr/bin/env bash
# SubagentStop: enforces a valid, fresh, proportional handoff file before the agent hands over.
# Exit 2 = the agent cannot finish; it receives the stderr message and must fix the file.
set -euo pipefail
INPUT=$(cat)
. "$(dirname "$0")/lib.sh"
command -v jq >/dev/null || { echo 'validate-handoff: jq missing — validation skipped, only the orchestrator checks the gate.' >&2; exit 0; }
AGENT=$(agent_short "$(echo "$INPUT" | jq -r '.agent_type // empty')")
ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
SID=$(input_sid "$INPUT")
KEY=$(current_key)
[ -n "$KEY" ] || exit 0          # no active pipeline (e.g. BA mode A: the orchestrator clears .current)
DIR="$(agents_dir)/$KEY"
[ -d "$DIR" ] || exit 0

STAGE=$(state .stage)
SIZE=$(state .size)
QA_MODE=$(state .qaMode)

case "$AGENT" in
  business-analyst)   FILE="01-analysis.md";        OK="READY";    ALL="READY|BLOCKED|TOO_LARGE" ;;
  solution-architect) FILE="02-architecture.md";    OK="READY";    ALL="READY|NEEDS_INPUT|TOO_LARGE" ;;
  senior-developer)   FILE="04-implementation.md";  OK="DONE";     ALL="DONE|NEEDS_INPUT" ;;
  code-reviewer)      FILE="05-review.md";          OK="APPROVED"; ALL="APPROVED|CHANGES_REQUESTED" ;;
  qa)
    case "$QA_MODE" in
      plan) FILE="03-test-plan.md" ;;
      exec) FILE="06-qa.md" ;;
      *)    # legacy fallback (no state.json): the most recently modified QA file
            FILE=$( { ls -t "$DIR"/03-test-plan.md "$DIR"/06-qa.md 2>/dev/null || true; } | head -1)
            FILE=${FILE##*/}; [ -n "$FILE" ] || FILE="06-qa.md" ;;
    esac
    if [ "$FILE" = "03-test-plan.md" ]; then OK="READY"; ALL="READY|NEEDS_INPUT"; else OK="PASS"; ALL="PASS|FAIL"; fi ;;
  *) exit 0 ;;   # other agents (Explore, Plan, …) — no validation
esac

# Timing: one line per stop attempt in timings.log (agent, file, round, seconds since SubagentStart, ok|rejected).
# The orchestrator reports stage durations from it in the retrospective.
log_timing() {
  local rc=$? start="" secs=0 result=ok
  [ -f "$DIR/.start-$AGENT" ] && start=$(tr -dc '0-9' < "$DIR/.start-$AGENT")
  [ -n "$start" ] && secs=$(( $(date +%s) - start ))
  [ "$rc" -eq 0 ] || result=rejected
  [ -n "${PASSED_THROUGH:-}" ] && result=failed-passed-through
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$AGENT" "$FILE" "$(state .round)" "$secs" "$result" \
    >> "$DIR/timings.log" 2>/dev/null || true
}
trap log_timing EXIT

fail() {
  echo "Handoff file $FILE fails the gate: $1. Fix the file according to its 'Success criteria' section and the rules in CLAUDE.md (section 'Handoff files')." >&2
  # do not loop forever — on the second attempt the orchestrator decides
  [ "$ACTIVE" = "true" ] && { PASSED_THROUGH=1; exit 0; }
  exit 2
}

# Headings: English (current) or Polish (projects initialized with delivery < 1.1.0)
H_CRIT='^## (Success criteria|Kryteria sukcesu)'
H_OPEN='^## (Open questions|Otwarte pytania)'

P="$DIR/$FILE"
[ -f "$P" ] || fail "file missing"
STATUS=$(head -1 "$P" | sed -n 's/^STATUS: *\([A-Z_]*\).*/\1/p')
[ -n "$STATUS" ] || fail "first line does not contain 'STATUS: <value>'"
echo "$STATUS" | grep -Eqx "$ALL" || fail "status '$STATUS' not allowed (allowed: $ALL)"
grep -Eq "$H_CRIT" "$P" || fail "missing section '## Success criteria'"
grep -Eq "$H_OPEN" "$P" || fail "missing section '## Open questions'"

# Freshness: the file must have been written during this agent run (skipped at closing — cleanup may not touch it)
START_FILE="$DIR/.start-$AGENT"
if [ -f "$START_FILE" ] && [ "$STAGE" != "closing" ]; then
  START=$(tr -dc '0-9' < "$START_FILE")
  [ -n "$START" ] && [ "$(mtime "$P")" -lt "$START" ] && fail "the file was not updated in this run (it is left over from an earlier round)"
fi

if [ "$STATUS" = "$OK" ]; then
  UNCHECKED=$(awk -v h="$H_CRIT" '$0 ~ h {f=1; next} /^## /{f=0} f' "$P" | grep -c '\[ \]' || true)
  [ "$UNCHECKED" -eq 0 ] || fail "status $STATUS with $UNCHECKED unmet criteria"
fi

# Proportionality: hard limit = 2x the size guideline (S ≤ 30, M ≤ 80 lines); L has no limit
case "$SIZE" in
  S) LIMIT=30 ;;
  M) LIMIT=80 ;;
  *) LIMIT=0 ;;
esac
if [ "$LIMIT" -gt 0 ]; then
  LINES=$(wc -l < "$P" | tr -d ' ')
  [ "$LINES" -le $((LIMIT * 2)) ] || fail "$LINES lines for a size $SIZE issue (guideline ≤ $LIMIT, hard limit $((LIMIT * 2))) — shorten: no restating earlier files, tables instead of prose, omit sections that do not apply"
fi
exit 0
