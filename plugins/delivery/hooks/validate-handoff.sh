#!/usr/bin/env bash
# SubagentStop: enforces a valid handoff file before the agent hands over.
# Exit 2 = the agent cannot finish; it receives the stderr message and must fix the file.
set -euo pipefail
INPUT=$(cat)
command -v jq >/dev/null || { echo 'validate-handoff: jq missing — validation skipped, only the orchestrator checks the gate.' >&2; exit 0; }
AGENT=$(echo "$INPUT" | jq -r '.agent_type // empty')
AGENT="${AGENT##*:}"   # plugin agents: "delivery:qa" -> "qa"
ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
ROOT="${CLAUDE_PROJECT_DIR:-.}"
# Magento directory from .claude/delivery.json (written by /delivery:init); defaults to the project directory
MR=$(jq -r '.magentoRoot // "."' "$ROOT/.claude/delivery.json" 2>/dev/null || echo .)
AGENTS="$ROOT/${MR:-.}/var/agents"
[ -f "$AGENTS/.current" ] || exit 0
KEY=$(tr -d '[:space:]' < "$AGENTS/.current")
DIR="$AGENTS/$KEY"

case "$AGENT" in
  business-analyst)   FILE="01-analysis.md";        OK="READY";    ALL="READY|BLOCKED|TOO_LARGE" ;;
  solution-architect) FILE="02-architecture.md";    OK="READY";    ALL="READY|NEEDS_INPUT|TOO_LARGE" ;;
  senior-developer)   FILE="04-implementation.md";  OK="DONE";     ALL="DONE|NEEDS_INPUT" ;;
  code-reviewer)      FILE="05-review.md";          OK="APPROVED"; ALL="APPROVED|CHANGES_REQUESTED" ;;
  qa)
    # QA works in two modes — check the most recently modified file
    FILE=$( { ls -t "$DIR"/03-test-plan.md "$DIR"/06-qa.md 2>/dev/null || true; } | head -1)
    FILE=${FILE##*/}
    [ -n "$FILE" ] || FILE="06-qa.md"
    if [ "$FILE" = "03-test-plan.md" ]; then OK="READY"; ALL="READY|NEEDS_INPUT"; else OK="PASS"; ALL="PASS|FAIL"; fi ;;
  *) exit 0 ;;   # other agents (Explore, Plan, BA mode A etc.) — no validation
esac

# BA mode A (issue list) creates no file — let it pass when the issue directory is missing
[ -d "$DIR" ] || exit 0

fail() {
  echo "Handoff file $FILE fails the gate: $1. Fix the file according to its 'Success criteria' section and the statuses in CLAUDE.md." >&2
  # do not loop forever — on the second attempt the orchestrator decides
  [ "$ACTIVE" = "true" ] && exit 0
  exit 2
}

[ -f "$DIR/$FILE" ] || fail "file missing"
STATUS=$(head -1 "$DIR/$FILE" | sed -n 's/^STATUS: *\([A-Z_]*\).*/\1/p')
[ -n "$STATUS" ] || fail "first line does not contain 'STATUS: <value>'"
echo "$STATUS" | grep -Eqx "$ALL" || fail "status '$STATUS' not allowed (allowed: $ALL)"
grep -q '^## Success criteria' "$DIR/$FILE" || fail "missing section '## Success criteria'"
grep -q '^## Open questions'     "$DIR/$FILE" || fail "missing section '## Open questions'"

if [ "$STATUS" = "$OK" ]; then
  # cut out the Success criteria section and look for unchecked items
  UNCHECKED=$(awk '/^## Success criteria/{f=1;next} /^## /{f=0} f' "$DIR/$FILE" | grep -c '\[ \]' || true)
  [ "$UNCHECKED" -eq 0 ] || fail "status $STATUS with $UNCHECKED unmet criteria"
fi
exit 0
