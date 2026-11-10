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

# timing log
rm -f "$D/timings.log"
state '{"size":"M","round":2}'
printf '%s' "$(stop_json delivery:senior-developer)" | bash "$HOOKS/subagent-start.sh"
good DONE > "$D/04-implementation.md"
expect 0 "timing: valid stop"           validate-handoff.sh "$(stop_json delivery:senior-developer)"
printf 'STATUS: DONE\n## Success criteria\n- [ ] a\n## Open questions\n- none\n' > "$D/04-implementation.md"
expect 2 "timing: rejected stop"        validate-handoff.sh "$(stop_json delivery:senior-developer)"
check() { if eval "$2"; then PASS=$((PASS+1)); else FAILED=$((FAILED+1)); echo "FAIL: $1"; fi; }
check "timings.log has 2 lines"         '[ "$(wc -l < "$D/timings.log" | tr -d " ")" = 2 ]'
check "timing line: agent, file, round, ok" 'head -1 "$D/timings.log" | cut -f2-4,6 | grep -qx "senior-developer	04-implementation.md	2	ok"'
check "timing line: rejected"           'tail -1 "$D/timings.log" | cut -f6 | grep -qx rejected'
check "timing seconds numeric"          'head -1 "$D/timings.log" | cut -f5 | grep -Eqx "[0-9]+"'
expect 0 "other agents: no timing"      validate-handoff.sh "$(stop_json Explore)"
check "other agents not logged"         '[ "$(wc -l < "$D/timings.log" | tr -d " ")" = 2 ]'

# no active pipeline
: > "$PROJ/var/agents/.current"
expect 0 "no .current key → skip"       validate-handoff.sh "$(stop_json delivery:business-analyst)"
expect 0 "other agents ignored"         validate-handoff.sh "$(stop_json Explore)"

# ---------- parallel pipelines: session binding + code lock ----------
A="$PROJ/var/agents"
write_json() { jq -nc --arg s "$1" --arg f "$2" --arg c "${3:-}" '{session_id:$s, tool_name:"Write", tool_input:{file_path:$f, content:$c}}'; }
edit_json()  { jq -nc --arg s "$1" --arg f "$2" '{session_id:$s, tool_name:"Edit", tool_input:{file_path:$f, old_string:"a", new_string:"b"}}'; }
agent_json() { jq -nc --arg s "$1" --arg t "$2" '{session_id:$s, tool_name:"Agent", tool_input:{subagent_type:$t, prompt:"x"}}'; }
sstop_json() { jq -nc --arg s "$1" --arg a "$2" '{session_id:$s, agent_id:"ag1", agent_type:$a, stop_hook_active:false}'; }
post() { printf '%s' "$1" | bash "$HOOKS/bind-session.sh"; }   # PostToolUse: after the file was written
mkdir -p "$A/P-1" "$A/P-2"

# binding: session s1 -> P-1 via .current, s2 -> P-2 via state.json
echo "P-1" > "$A/.current"; post "$(write_json s1 "$A/.current")"
echo '{"stage":"analysis"}' > "$A/P-2/state.json"; post "$(write_json s2 "$A/P-2/state.json")"
check "s1 bound to P-1"                 '[ "$(cat "$A/.sessions/s1")" = P-1 ]'
check "s2 bound to P-2"                 '[ "$(cat "$A/.sessions/s2")" = P-2 ]'
post "$(jq -nc --arg f "$A/P-1/state.json" '{session_id:"s9", agent_id:"x", tool_name:"Write", tool_input:{file_path:$f}}')"
check "subagent writes never bind"      '[ ! -f "$A/.sessions/s9" ]'

# each session validates its own issue
good READY > "$A/P-1/01-analysis.md"; good WRONG > "$A/P-2/01-analysis.md"
expect 0 "s1 validates P-1"             validate-handoff.sh "$(sstop_json s1 delivery:business-analyst)"
expect 2 "s2 validates P-2"             validate-handoff.sh "$(sstop_json s2 delivery:business-analyst)"
expect 0 "unbound session skipped (no legacy .current fallback)" validate-handoff.sh "$(sstop_json s3 delivery:business-analyst)"
printf '%s' "$(sstop_json s3 delivery:business-analyst)" | bash "$HOOKS/subagent-start.sh"
check "unbound start logged"            'grep -q "business-analyst" "$A/.unbound.log"'

# paused write parks another issue without rebinding the session
echo '{"stage":"paused","resumeStage":"implementation"}' > "$A/P-2/state.json"; post "$(write_json s1 "$A/P-2/state.json")"
check "paused write keeps s1 on P-1"    '[ "$(cat "$A/.sessions/s1")" = P-1 ]'
echo '{"stage":"analysis"}' > "$A/P-2/state.json"

# empty .current unbinds
: > "$A/.current"; post "$(write_json s1 "$A/.current")"
check "empty .current unbinds s1"       '[ ! -f "$A/.sessions/s1" ]'
echo "P-1" > "$A/.current"; post "$(write_json s1 "$A/.current")"

# code lock
expect 0 "P-1 enters implementation (free)" pipeline-guard.sh "$(write_json s1 "$A/P-1/state.json" '{"stage":"implementation"}')"
echo '{"stage":"implementation"}' > "$A/P-1/state.json"
expect 2 "P-2 blocked from implementation"  pipeline-guard.sh "$(write_json s2 "$A/P-2/state.json" '{"stage":"implementation"}')"
expect 2 "P-2 blocked from qa"              pipeline-guard.sh "$(write_json s2 "$A/P-2/state.json" '{"stage":"qa","qaMode":"exec"}')"
expect 0 "P-2 architecture allowed"         pipeline-guard.sh "$(write_json s2 "$A/P-2/state.json" '{"stage":"architecture"}')"
expect 0 "P-1 stays in its code stage"      pipeline-guard.sh "$(write_json s1 "$A/P-1/state.json" '{"stage":"review"}')"
expect 2 "Edit of state.json blocked"       pipeline-guard.sh "$(edit_json s1 "$A/P-1/state.json")"
expect 0 "other Writes untouched"           pipeline-guard.sh "$(write_json s1 "$A/P-1/01-analysis.md" 'x')"
expect 0 "s1 dev call allowed"              pipeline-guard.sh "$(agent_json s1 delivery:senior-developer)"
expect 2 "s2 dev call blocked (P-2 not in code stage)" pipeline-guard.sh "$(agent_json s2 delivery:senior-developer)"
expect 0 "s2 SA call allowed"               pipeline-guard.sh "$(agent_json s2 delivery:solution-architect)"
echo '{"stage":"test-plan","qaMode":"plan"}' > "$A/P-2/state.json"
expect 0 "s2 QA plan allowed"               pipeline-guard.sh "$(agent_json s2 delivery:qa)"
expect 0 "P-1 closing write releases the lock" pipeline-guard.sh "$(write_json s1 "$A/P-1/state.json" '{"stage":"closing"}')"
echo '{"stage":"closing"}' > "$A/P-1/state.json"
expect 0 "closing frees the lock"           pipeline-guard.sh "$(write_json s2 "$A/P-2/state.json" '{"stage":"implementation"}')"
expect 0 "QA cleanup at closing allowed"    pipeline-guard.sh "$(agent_json s1 delivery:qa)"
expect 0 "P-2 closing releases"            pipeline-guard.sh "$(write_json s2 "$A/P-2/state.json" '{"stage":"closing"}')"
echo '{"stage":"closing"}' > "$A/P-2/state.json"
expect 0 "P-1 parked via hook releases"     pipeline-guard.sh "$(write_json s1 "$A/P-1/state.json" '{"stage":"paused","resumeStage":"implementation"}')"
echo '{"stage":"paused","resumeStage":"implementation"}' > "$A/P-1/state.json"
expect 0 "paused issue does not hold lock"  pipeline-guard.sh "$(write_json s2 "$A/P-2/state.json" '{"stage":"implementation"}')"

# ---------- collect-stats ----------
TR="$PROJ/agent-x.jsonl"
cat > "$TR" <<'JSONL'
{"type":"user","timestamp":"2026-01-01T10:00:00.000Z","message":{"content":"brief"}}
{"type":"assistant","timestamp":"2026-01-01T10:00:02.000Z","message":{"id":"m1","model":"claude-sonnet-5-5","usage":{"input_tokens":10,"cache_creation_input_tokens":1000,"cache_read_input_tokens":500,"output_tokens":50},"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"cd x && warden env exec -T php-fpm bin/magento indexer:reindex catalog"}}]}}
{"type":"assistant","timestamp":"2026-01-01T10:00:02.100Z","message":{"id":"m1","model":"claude-sonnet-5-5","usage":{"input_tokens":10,"cache_creation_input_tokens":1000,"cache_read_input_tokens":500,"output_tokens":50},"content":[{"type":"tool_use","id":"t2","name":"Read","input":{"file_path":"/a"}}]}}
{"type":"user","timestamp":"2026-01-01T10:01:32.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"t1","content":"done"}]}}
{"type":"user","timestamp":"2026-01-01T10:00:03.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"t2","content":"0123456789"}]}}
not json
{"type":"assistant","timestamp":"2026-01-01T10:02:00.000Z","message":{"id":"m2","model":"claude-sonnet-5-5","usage":{"input_tokens":5,"cache_creation_input_tokens":0,"cache_read_input_tokens":2000,"output_tokens":20},"content":[{"type":"text","text":"ok"}]}}
JSONL
echo '{"stage":"qa","qaMode":"exec","round":1,"size":"S"}' > "$A/P-1/state.json"
cstats() { jq -nc --arg s "$1" --arg t "$2" '{session_id:$s, agent_type:"delivery:qa", agent_id:"ag7", agent_transcript_path:$t, transcript_path:""}'; }
expect 0 "collect-stats exits 0"        collect-stats.sh "$(cstats s1 "$TR")"
SF="$A/P-1/stats/qa-ag7.json"
check "stats file written"              '[ -f "$SF" ]'
check "turns deduped by message id"     '[ "$(jq .turns "$SF")" = 2 ]'
check "tokens summed once per message"  '[ "$(jq -c .tokens "$SF")" = "{\"input\":15,\"cache_write\":1000,\"cache_read\":2500,\"output\":70}" ]'
check "run duration 120s"               '[ "$(jq .seconds "$SF")" = 120 ]'
check "slowest call labeled, no args"   '[ "$(jq -r ".slowest[0].label" "$SF")" = "bin/magento indexer:reindex" ]'
check "tool time 90s"                   '[ "$(jq ".tools.Bash.seconds" "$SF")" = 90 ]'
check "state copied"                    '[ "$(jq -r .qaMode "$SF")" = exec ]'
expect 0 "missing transcript ignored"   collect-stats.sh "$(cstats s1 "$PROJ/none.jsonl")"
expect 0 "unbound session ignored"      collect-stats.sh "$(cstats s3 "$TR")"
check "stats report renders"            'bash "$HOOKS/../scripts/stats.sh" P-1 | grep -q "bin/magento indexer:reindex"'
check "archive appends rows"            'bash "$HOOKS/../scripts/stats.sh" P-1 --archive >/dev/null && [ "$(wc -l < "$A/_stats.jsonl" | tr -d " ")" = 1 ]'
check "archive has no transcript path"  '! grep -q transcript "$A/_stats.jsonl"'
check "all-issues report renders"       'bash "$HOOKS/../scripts/stats.sh" --all | grep -q "| qa | S | 1 |"'

# ---------- 1.6.0: guard bypasses from the review ----------
echo '{"magentoRoot":"."}' > "$PROJ/.claude/delivery.json"
branch feature/T-1-x
expect 2 "push -uf (bundled force)"          pre-bash.sh "$(bash_json '' 'git push -uf origin feature/T-1-x')"
expect 2 "push -fu (bundled force)"          pre-bash.sh "$(bash_json '' 'git push -fu origin feature/T-1-x')"
expect 0 "push -n (dry run) allowed"         pre-bash.sh "$(bash_json '' 'git push -n origin feature/T-1-x')"
expect 2 "(git push origin master)"          pre-bash.sh "$(bash_json '' '(git push origin master)')"
expect 2 "subshell cd && push master)"       pre-bash.sh "$(bash_json '' '(cd /x && git push origin master)')"
expect 2 "\"git\" push origin master"        pre-bash.sh "$(bash_json '' '"git" push origin master')"
expect 2 "mas\"\"ter"                        pre-bash.sh "$(bash_json '' 'git push origin mas""ter')"
expect 2 "push \$(echo master)"              pre-bash.sh "$(bash_json '' 'git push origin $(echo master)')"
expect 2 "git -c alias push"                 pre-bash.sh "$(bash_json '' 'git -c alias.p=push p origin master')"
expect 2 "git -c push.default"               pre-bash.sh "$(bash_json '' 'git -c push.default=upstream push')"
expect 2 "push --no-verify"                  pre-bash.sh "$(bash_json '' 'git push --no-verify origin feature/T-1-x')"
expect 0 "commit message mentioning push main" pre-bash.sh "$(bash_json '' 'git commit -m "do not push to main"')"
branch master
expect 0 "git stash push on master"          pre-bash.sh "$(bash_json '' 'git stash push -m "wip on master"')"
branch feature/T-1-x
expect 0 "git -C dir push issue branch"      pre-bash.sh "$(bash_json '' 'git -C /x push -u origin feature/T-1-x')"

expect 2 "QA- only in a comment"             pre-bash.sh "$(bash_json delivery:qa 'warden db connect -e "DELETE FROM sales_order WHERE 1=1" # QA-')"
expect 2 "QA- in SET, multi-table update"    pre-bash.sh "$(bash_json delivery:qa "warden db connect -e \"UPDATE sales_order o, store s SET o.status='QA-x'\"")"
expect 2 "DELETE alias FROM"                 pre-bash.sh "$(bash_json delivery:qa "warden db connect -e \"DELETE o FROM sales_order o WHERE o.x='QA-1'\"")"
expect 2 "QA- in SET, WHERE on real rows"    pre-bash.sh "$(bash_json delivery:qa "warden db connect -e \"UPDATE sales_order SET status='QA-x' WHERE entity_id=5\"")"
expect 2 "OR in WHERE"                       pre-bash.sh "$(bash_json delivery:qa "warden db connect -e \"DELETE FROM catalog_product_entity WHERE sku LIKE 'QA-T-1-%' OR 1=1\"")"
expect 2 "two statements"                    pre-bash.sh "$(bash_json delivery:qa "warden db connect -e \"DELETE FROM a WHERE sku='QA-1'; DELETE FROM b WHERE x=1\"")"
expect 2 "pipe file into db"                 pre-bash.sh "$(bash_json delivery:qa 'cat /tmp/x.sql | warden db connect')"
expect 2 "SOURCE uppercase"                  pre-bash.sh "$(bash_json delivery:qa 'warden db connect -e "SOURCE /tmp/x.sql"')"
expect 2 "substitution into db"              pre-bash.sh "$(bash_json delivery:qa 'warden db connect -e "$(cat /tmp/x.sql)"')"
mkdir -p "$PROJ/qa-scripts"; echo '<?php $c->getConnection()->query("DELETE FROM x");' > "$PROJ/qa-scripts/raw.php"
echo '<?php echo "hi";' > "$PROJ/qa-scripts/ok.php"
expect 2 "php script with raw DB access"     pre-bash.sh "$(bash_json delivery:qa 'php qa-scripts/raw.php')"
expect 0 "php script without DB access"      pre-bash.sh "$(bash_json delivery:qa 'php qa-scripts/ok.php')"
expect 0 "valid QA delete still allowed"     pre-bash.sh "$(bash_json delivery:qa "warden db connect -e \"DELETE FROM catalog_product_entity WHERE sku LIKE 'QA-T-1-%'\"")"
expect 0 "mysql --user option is not a comment" pre-bash.sh "$(bash_json delivery:qa "mysql --user=x -e \"DELETE FROM a WHERE sku='QA-1'\"")"
expect 2 "SA /usr/bin/git"                   pre-bash.sh "$(bash_json delivery:solution-architect '/usr/bin/git log -1')"
expect 2 "SA \"git\" log"                    pre-bash.sh "$(bash_json delivery:solution-architect '"git" log')"
expect 2 "SA \$(which git)"                  pre-bash.sh "$(bash_json delivery:solution-architect '$(which git) log')"
expect 0 "SA word 'digit' ok"                pre-bash.sh "$(bash_json delivery:solution-architect 'grep -r digit app/code')"

# lock: atomic dir, invalid JSON, unbound sessions, unprefixed names
rm -rf "$A/.code-lock"
for k in P-1 P-2; do echo '{"stage":"analysis"}' > "$A/$k/state.json"; done
expect 2 "invalid JSON state.json blocked"   pipeline-guard.sh "$(write_json s1 "$A/P-1/state.json" '{"stage":"implementation",}')"
expect 0 "P-1 takes the lock"                pipeline-guard.sh "$(write_json s1 "$A/P-1/state.json" '{"stage":"implementation"}')"
check "lock dir owned by P-1"                '[ "$(cat "$A/.code-lock/key")" = P-1 ]'
expect 2 "P-2 blocked by lock dir alone (state not yet written)" pipeline-guard.sh "$(write_json s2 "$A/P-2/state.json" '{"stage":"implementation"}')"
echo '{"stage":"implementation"}' > "$A/P-1/state.json"
echo '{"stage":"analysis"}' > "$A/P-1/state.json"; touch -t 202001010000 "$A/.code-lock"
expect 0 "stale lock (old, owner not in code stage) taken over" pipeline-guard.sh "$(write_json s2 "$A/P-2/state.json" '{"stage":"implementation"}')"
check "lock now owned by P-2"                '[ "$(cat "$A/.code-lock/key")" = P-2 ]'
expect 0 "P-2 leaves, lock released"         pipeline-guard.sh "$(write_json s2 "$A/P-2/state.json" '{"stage":"closing"}')"
echo '{"stage":"closing"}' > "$A/P-2/state.json"
expect 0 "P-1 takes it again"                pipeline-guard.sh "$(write_json s1 "$A/P-1/state.json" '{"stage":"implementation"}')"
echo '{"stage":"implementation"}' > "$A/P-1/state.json"
expect 0 "P-1 leaving code stage releases"   pipeline-guard.sh "$(write_json s1 "$A/P-1/state.json" '{"stage":"closing"}')"
check "lock released"                        '[ ! -d "$A/.code-lock" ]'
echo '{"stage":"closing"}' > "$A/P-1/state.json"
expect 2 "unbound session: dev blocked"      pipeline-guard.sh "$(agent_json s99 delivery:senior-developer)"
expect 2 "unbound session: SA blocked"       pipeline-guard.sh "$(agent_json s99 delivery:solution-architect)"
expect 0 "unbound session: BA allowed"       pipeline-guard.sh "$(agent_json s99 delivery:business-analyst)"
expect 2 "unprefixed senior-developer gated" pipeline-guard.sh "$(agent_json s2 senior-developer)"

# binding: writing another issue's state.json does not move the session
echo P-1 > "$A/.sessions/s1"
echo '{"stage":"closing"}' > "$A/P-2/state.json"; post "$(write_json s1 "$A/P-2/state.json")"
check "s1 stays on P-1 after writing P-2"    '[ "$(cat "$A/.sessions/s1")" = P-1 ]'

# pass-through on the second attempt is logged as such
echo '{"stage":"architecture","round":1}' > "$A/P-1/state.json"; rm -f "$A/P-1/02-architecture.md" "$A/P-1/timings.log"
expect 0 "second attempt passes"             validate-handoff.sh "$(jq -nc '{session_id:"s1", agent_type:"delivery:solution-architect", stop_hook_active:true}')"
check "logged as failed-passed-through"      'tail -1 "$A/P-1/timings.log" | cut -f6 | grep -qx failed-passed-through'

# stats labels never carry secrets or arbitrary words
TR2="$PROJ/agent-y.jsonl"
printf '%s\n' '{"type":"assistant","timestamp":"2026-01-01T10:00:00.000Z","message":{"id":"m","content":[{"type":"tool_use","id":"a","name":"Bash","input":{"command":"MYSQL_PWD=hunter2 mysql -e x"}},{"type":"tool_use","id":"b","name":"Bash","input":{"command":"jan.kowalski@example.com.sh go"}}]}}' \
  '{"type":"user","timestamp":"2026-01-01T10:00:05.000Z","message":{"content":[{"type":"tool_result","tool_use_id":"a","content":"x"},{"type":"tool_result","tool_use_id":"b","content":"x"}]}}' > "$TR2"
LBL=$(jq -R -s --argjson from null --argjson to null -f "$HOOKS/../scripts/transcript-stats.jq" "$TR2" | jq -r '[.slowest[].label] | join(",")')
check "no env assignment in labels"          '! echo "$LBL" | grep -q hunter2'
check "unknown program labeled bash"         '! echo "$LBL" | grep -q kowalski'

# git pre-push hook (resolved refs)
PP="$HOOKS/../templates/pre-push"
R="$PROJ/pp"; mkdir -p "$R"; git init -q --bare "$R/remote.git"; git init -q "$R/w"
git -C "$R/w" -c user.email=t@example.com -c user.name=t commit -q --allow-empty -m one
cp "$PP" "$R/w/.git/hooks/pre-push"; chmod +x "$R/w/.git/hooks/pre-push"
git -C "$R/w" remote add origin "$R/remote.git"
gp() { git -C "$R/w" -c user.email=t@example.com -c user.name=t "$@" >/dev/null 2>&1; }
check "pre-push: feature branch ok"          'gp push -q origin HEAD:refs/heads/feature/T-1-x'
check "pre-push: master blocked"             '! gp push -q origin HEAD:refs/heads/master'
check "pre-push: main blocked via alias"     '! gp -c alias.p=push p -q origin HEAD:main'
gp commit -q --amend --allow-empty -m two
check "pre-push: force push blocked"         '! gp push -q --force origin HEAD:refs/heads/feature/T-1-x'
gp commit -q --allow-empty -m three
check "pre-push: fast-forward ok"            'gp push -q origin HEAD:refs/heads/feature/T-1-y'
printf '#!/bin/sh\nexit 1\n' > "$R/w/.git/hooks/pre-push.local"; chmod +x "$R/w/.git/hooks/pre-push.local"
check "pre-push: chained local hook runs"    '! gp push -q origin HEAD:refs/heads/feature/T-1-z'

echo "passed: $PASS, failed: $FAILED"
[ "$FAILED" -eq 0 ]
