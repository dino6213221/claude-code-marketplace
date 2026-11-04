#!/usr/bin/env bash
# Tests for the delivery hooks: feeds hook JSON input, checks the exit code.
# Usage: bash plugins/delivery/tests/hooks.sh   (requires jq; creates a throwaway project in a temp dir)
set -u
HOOKS="$(cd "$(dirname "$0")/../hooks" && pwd)"
command -v jq >/dev/null || { echo "jq required"; exit 1; }

PROJ=$(mktemp -d)
trap 'rm -rf "$PROJ"' EXIT
export CLAUDE_PROJECT_DIR="$PROJ"
mkdir -p "$PROJ/.claude" "$PROJ/var/agents/T-1"
echo '{"magentoRoot":"."}' > "$PROJ/.claude/delivery.json"
echo "T-1" > "$PROJ/var/agents/.current"
git -C "$PROJ" init -q
branch() { git -C "$PROJ" symbolic-ref HEAD "refs/heads/$1"; }   # empty repo: switch branch without commits
branch feature/T-1-x
D="$PROJ/var/agents/T-1"

PASS=0; FAILED=0
expect() { # expect <exit code> <description> <hook> <json>
  local want="$1" desc="$2" hook="$3" json="$4" got
  printf '%s' "$json" | bash "$HOOKS/$hook" >/dev/null 2>&1; got=$?
  if [ "$got" = "$want" ]; then PASS=$((PASS+1)); else FAILED=$((FAILED+1)); echo "FAIL: $desc (want $want, got $got)"; fi
}
bash_json() { jq -nc --arg a "$1" --arg c "$2" '{agent_type:$a, tool_name:"Bash", tool_input:{command:$c}}'; }
stop_json() { jq -nc --arg a "$1" --argjson s "${2:-false}" '{agent_type:$a, stop_hook_active:$s}'; }
state() { echo "$1" > "$D/state.json"; }

# ---------- pre-bash: git-guard ----------
expect 2 "SA git log blocked"           pre-bash.sh "$(bash_json delivery:solution-architect 'git log -1')"
expect 2 "SA git in chain blocked"      pre-bash.sh "$(bash_json delivery:solution-architect 'ls && git status')"
expect 0 "SA bin/magento allowed"       pre-bash.sh "$(bash_json delivery:solution-architect 'warden env exec -T php-fpm bin/magento module:status')"
expect 0 "dev git log allowed"          pre-bash.sh "$(bash_json delivery:senior-developer 'git log -1')"

# ---------- pre-bash: sql-guard ----------
expect 2 "QA DROP blocked"              pre-bash.sh "$(bash_json delivery:qa 'warden db connect -e "DROP TABLE x"')"
expect 2 "QA DELETE without WHERE"      pre-bash.sh "$(bash_json delivery:qa 'warden db connect -e "DELETE FROM sales_order"')"
expect 2 "QA write not QA- record"      pre-bash.sh "$(bash_json delivery:qa "warden db connect -e \"UPDATE customer_entity SET firstname='x' WHERE entity_id=5\"")"
expect 0 "QA write on QA- record"       pre-bash.sh "$(bash_json delivery:qa "warden db connect -e \"DELETE FROM catalog_product_entity WHERE sku LIKE 'QA-T-1-%'\"")"
expect 2 "QA SQL from file blocked"     pre-bash.sh "$(bash_json delivery:qa 'warden db connect < var/agents/T-1/qa-scripts/x.sql')"
expect 2 "QA inline PHP PDO blocked"    pre-bash.sh "$(bash_json delivery:qa 'php -r "\$p=new PDO(\"mysql:host=db\"); \$p->exec(\"DELETE FROM x\");"')"
expect 2 "QA n98 db:query write blocked" pre-bash.sh "$(bash_json delivery:qa 'n98-magerun2 db:query "DELETE FROM customer_entity WHERE entity_id=1"')"
echo '{"magentoRoot":".","db":"bin/dbshell"}' > "$PROJ/.claude/delivery.json"
expect 2 "QA custom db command write blocked" pre-bash.sh "$(bash_json delivery:qa 'bin/dbshell -e "UPDATE sales_order SET status=1 WHERE entity_id=2"')"
echo '{"magentoRoot":"."}' > "$PROJ/.claude/delivery.json"
expect 0 "QA SELECT allowed"            pre-bash.sh "$(bash_json delivery:qa 'warden db connect -e "SELECT COUNT(*) FROM sales_order"')"
expect 0 "dev DROP not guarded by sql"  pre-bash.sh "$(bash_json delivery:senior-developer 'echo DROP')"

# ---------- pre-bash: push-guard ----------
expect 0 "push issue branch"            pre-bash.sh "$(bash_json '' 'git push -u origin feature/T-1-x')"
expect 0 "push without refspec on issue branch" pre-bash.sh "$(bash_json '' 'git push')"
expect 2 "push HEAD:master"             pre-bash.sh "$(bash_json '' 'git push origin HEAD:master')"
expect 2 "push x:refs/heads/main"       pre-bash.sh "$(bash_json '' 'git push origin feature/T-1-x:refs/heads/main')"
expect 2 "push master"                  pre-bash.sh "$(bash_json '' 'git push origin master')"
expect 2 "push --force-with-lease"      pre-bash.sh "$(bash_json '' 'git push --force-with-lease origin feature/T-1-x')"
expect 2 "push +refspec"                pre-bash.sh "$(bash_json '' 'git push origin +feature/T-1-x')"
expect 2 "push --mirror"                pre-bash.sh "$(bash_json '' 'git push --mirror origin')"
expect 2 "git -C push main"             pre-bash.sh "$(bash_json '' 'cd x && git -C . push origin main')"
expect 2 "push --delete master"         pre-bash.sh "$(bash_json '' 'git push origin --delete master')"
expect 0 "branch named master-data ok"  pre-bash.sh "$(bash_json '' 'git push origin bugfix/T-1-master-data')"
expect 0 "non-git 'push' word ok"       pre-bash.sh "$(bash_json '' 'echo push master')"
branch master
expect 2 "push without refspec on master" pre-bash.sh "$(bash_json '' 'git push')"
expect 2 "push HEAD on master"          pre-bash.sh "$(bash_json '' 'git push origin HEAD')"
branch feature/T-1-x
mv "$PROJ/.claude/delivery.json" "$PROJ/.claude/delivery.json.off"
expect 0 "push-guard off outside delivery projects" pre-bash.sh "$(bash_json '' 'git push origin master')"
mv "$PROJ/.claude/delivery.json.off" "$PROJ/.claude/delivery.json"

# ---------- validate-handoff ----------
good() { printf 'STATUS: %s\n# T-1\n## Success criteria\n- [x] a\n## Open questions\n- none\n' "$1"; }
good READY > "$D/01-analysis.md"
expect 0 "BA valid READY"               validate-handoff.sh "$(stop_json delivery:business-analyst)"
printf 'STATUS: READY\n## Success criteria\n- [ ] a\n## Open questions\n- none\n' > "$D/01-analysis.md"
expect 2 "BA READY with [ ]"            validate-handoff.sh "$(stop_json delivery:business-analyst)"
expect 0 "second attempt lets through"  validate-handoff.sh "$(stop_json delivery:business-analyst true)"
printf 'STATUS: BLOCKED\n## Success criteria\n- [ ] a\n## Open questions\n- → user: x\n' > "$D/01-analysis.md"
expect 0 "BA BLOCKED with [ ] ok"       validate-handoff.sh "$(stop_json delivery:business-analyst)"
printf 'STATUS: READY\n## Kryteria sukcesu\n- [x] a\n## Otwarte pytania\n- brak\n' > "$D/01-analysis.md"
expect 0 "Polish headings accepted"     validate-handoff.sh "$(stop_json delivery:business-analyst)"
good WRONG > "$D/01-analysis.md"
expect 2 "bad status"                   validate-handoff.sh "$(stop_json delivery:business-analyst)"
rm -f "$D/02-architecture.md"
expect 2 "SA file missing"              validate-handoff.sh "$(stop_json delivery:solution-architect)"

# freshness
good APPROVED > "$D/05-review.md"; touch -t 202001010000 "$D/05-review.md"
printf '%s' "$(stop_json delivery:code-reviewer)" | bash "$HOOKS/subagent-start.sh"
expect 2 "stale file from earlier round" validate-handoff.sh "$(stop_json delivery:code-reviewer)"
good APPROVED > "$D/05-review.md"
expect 0 "fresh file ok"                validate-handoff.sh "$(stop_json delivery:code-reviewer)"
touch -t 202001010000 "$D/05-review.md"; state '{"stage":"closing"}'
expect 0 "closing skips freshness"      validate-handoff.sh "$(stop_json delivery:code-reviewer)"

# QA mode from state.json
good READY > "$D/03-test-plan.md"; good PASS > "$D/06-qa.md"; rm -f "$D/.start-qa"
state '{"qaMode":"plan"}'; touch "$D/06-qa.md"
expect 0 "QA plan mode checks 03"       validate-handoff.sh "$(stop_json delivery:qa)"
state '{"qaMode":"exec"}'; rm -f "$D/06-qa.md"
expect 2 "QA exec mode needs 06"        validate-handoff.sh "$(stop_json delivery:qa)"

# size limit
state '{"size":"S"}'
{ good DONE; for i in $(seq 1 70); do echo "line $i"; done; } > "$D/04-implementation.md"
expect 2 "size S over 60 lines"         validate-handoff.sh "$(stop_json delivery:senior-developer)"
state '{"size":"M"}'
expect 0 "size M under 160 lines"       validate-handoff.sh "$(stop_json delivery:senior-developer)"

# no active pipeline
: > "$PROJ/var/agents/.current"
expect 0 "no .current key → skip"       validate-handoff.sh "$(stop_json delivery:business-analyst)"
expect 0 "other agents ignored"         validate-handoff.sh "$(stop_json Explore)"

echo "passed: $PASS, failed: $FAILED"
[ "$FAILED" -eq 0 ]
