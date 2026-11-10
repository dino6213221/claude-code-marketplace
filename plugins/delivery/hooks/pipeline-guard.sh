#!/usr/bin/env bash
# PreToolUse (Write|Edit|Agent): code lock for parallel pipelines.
# Several issues may be in analysis / architecture / test plan at once, but only ONE issue at a time
# may be in a code stage (implementation, review, qa): they share the checkout, the branch and the
# local environment. Exit 2 = the call is blocked and the orchestrator gets the reason.
#   Write var/agents/<KEY>/state.json  -> must be valid JSON; entering a code stage takes the atomic lock
#                                         var/agents/.code-lock (mkdir), leaving it releases the lock
#   Edit  var/agents/<KEY>/state.json  -> blocked (use Write, so the new stage is known)
#   Agent pipeline agent (except BA)   -> blocked when the session is not bound to an issue
#   Agent senior-developer / code-reviewer / qa (exec) -> blocked unless this issue holds a code stage
INPUT=$(cat)
case "$INPUT" in *var/agents/*|*developer*|*reviewer*|*qa*|*architect*) ;; *) exit 0 ;; esac    # fast path
. "$(dirname "$0")/lib.sh"
command -v jq >/dev/null || exit 0
[ -f "$DELIVERY_JSON" ] || exit 0
[ -z "$(echo "$INPUT" | jq -r '.agent_id // empty')" ] || exit 0   # only the orchestrator (main session)
SID=$(input_sid "$INPUT")
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')
AD="$(agents_dir)"
LOCK="$AD/.code-lock"

block() {
  echo "delivery code lock: $1" >&2
  exit 2
}
LOCK_HELP="Only one issue at a time may be in implementation/review/qa (shared checkout and environment). Tell the user; options: wait until that issue reaches closing, or — with the user's approval — park it by writing its state.json with \"stage\": \"paused\" and \"resumeStage\": \"<its stage>\"."

in_code_stage() {   # in_code_stage <KEY> — its state.json has a code stage
  local st
  st=$(jq -r '.stage // empty' "$AD/$1/state.json" 2>/dev/null || true)
  echo "$st" | grep -Eqx "$CODE_STAGES"
}
lock_owner() { cat "$LOCK/key" 2>/dev/null || true; }
lock_age() { echo $(( $(date +%s) - $(mtime "$LOCK") )); }
acquire() {         # acquire <KEY> — atomic (mkdir). A lock is stale only when its owner is not in a code stage
                    # AND it is older than 2 minutes (the owner's state.json is written right AFTER this hook).
  local o
  if mkdir "$LOCK" 2>/dev/null; then echo "$1" > "$LOCK/key"; return 0; fi
  o=$(lock_owner)
  [ "$o" = "$1" ] && return 0
  if [ -n "$o" ] && ! in_code_stage "$o" && [ "$(lock_age)" -gt 120 ]; then
    rm -f "$LOCK/key"; rmdir "$LOCK" 2>/dev/null
    if mkdir "$LOCK" 2>/dev/null; then echo "$1" > "$LOCK/key"; return 0; fi
  fi
  return 1
}
release() {         # release <KEY> — only the owner's lock
  [ "$(lock_owner)" = "$1" ] || return 0
  rm -f "$LOCK/key"; rmdir "$LOCK" 2>/dev/null || true
}
pipeline_in_use() { ls "$AD"/*/state.json >/dev/null 2>&1; }

case "$TOOL" in
  Write|Edit)
    FP=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    case "$FP" in */var/agents/*/state.json) ;; *) exit 0 ;; esac
    [ "$TOOL" = "Edit" ] && block "edit state.json with the Write tool (whole file), not Edit."
    K=$(basename "$(dirname "$FP")")
    CONTENT=$(echo "$INPUT" | jq -r '.tool_input.content // empty')
    echo "$CONTENT" | jq -e 'type == "object"' >/dev/null 2>&1 || block "state.json for $K is not a valid JSON object — fix the content."
    ST=$(echo "$CONTENT" | jq -r '.stage // empty')
    if echo "$ST" | grep -Eqx "$CODE_STAGES"; then
      H=$(code_lock_holder "$K")
      [ -z "$H" ] || block "$K cannot enter stage '$ST': $H holds the code stages. $LOCK_HELP"
      acquire "$K" || block "$K cannot enter stage '$ST': the code lock is held by $(lock_owner). $LOCK_HELP"
    else
      release "$K"
    fi ;;
  Agent|Task)
    T=$(echo "$INPUT" | jq -r '.tool_input.subagent_type // empty')
    T=${T#delivery:}
    case "$T" in
      senior-developer|code-reviewer|qa|solution-architect) ;;
      *) exit 0 ;;                                  # business-analyst (mode A runs unbound) and non-pipeline agents
    esac
    KEY=$(current_key)
    if [ -z "$KEY" ]; then
      pipeline_in_use || exit 0                     # no pipeline in this project — ad-hoc use of the agent
      block "this session is not bound to an issue (new session, /clear or restart?). Write var/agents/.current and var/agents/<KEY>/state.json with the Write tool first — otherwise the handoff gate and the code lock cannot apply."
    fi
    case "$T" in
      senior-developer|code-reviewer) ;;
      qa) [ "$(state .qaMode)" = "exec" ] || exit 0 ;;
      *) exit 0 ;;
    esac
    ST=$(state .stage)
    OKST="$CODE_STAGES"; [ "$T" = "qa" ] && OKST="$CODE_STAGES|closing"   # QA cleanup at closing
    echo "$ST" | grep -Eqx "$OKST" || block "$T for $KEY needs state.json with a code stage (implementation/review/qa) written first — it is '$ST'."
    [ "$ST" = "closing" ] && exit 0
    H=$(code_lock_holder "$KEY")
    [ -z "$H" ] || block "$KEY and $H are both in code stages. $LOCK_HELP"
    O=$(lock_owner)
    if [ -n "$O" ] && [ "$O" != "$KEY" ] && { in_code_stage "$O" || [ "$(lock_age)" -le 120 ]; }; then block "the code lock is held by $O. $LOCK_HELP"; fi ;;
esac
exit 0
