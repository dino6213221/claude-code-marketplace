#!/usr/bin/env bash
# PostToolUse (Write|Edit): binds the orchestrator's session to its issue, so several sessions
# can run pipelines for different issues at the same time.
#   write var/agents/.current           -> bind the session to its content (empty = unbind)
#   write var/agents/<KEY>/state.json   -> bind the session to <KEY> (except a "paused" write,
#                                          which parks ANOTHER issue)
# Binding file: var/agents/.sessions/<session_id> (one line: the key).
INPUT=$(cat)
case "$INPUT" in *var/agents/*) ;; *) exit 0 ;; esac    # fast path
. "$(dirname "$0")/lib.sh"
command -v jq >/dev/null || exit 0
[ -f "$DELIVERY_JSON" ] || exit 0
[ -z "$(echo "$INPUT" | jq -r '.agent_id // empty')" ] || exit 0   # subagents never bind
SID=$(input_sid "$INPUT")
[ -n "$SID" ] || exit 0
FP=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
D="$(agents_dir)"
S="$D/.sessions"

case "$FP" in
  */var/agents/.current)
    mkdir -p "$S"
    K=$(tr -d '[:space:]' < "$FP" 2>/dev/null || true)
    if [ -n "$K" ]; then echo "$K" > "$S/$SID"; else rm -f "$S/$SID"; fi ;;
  */var/agents/*/state.json)
    # Bind only an unbound session (or confirm the same key): writing ANOTHER issue's state.json
    # (parking it, setting it to closing) must not move this session to that issue.
    # Switching issues in one session goes through var/agents/.current.
    K=$(basename "$(dirname "$FP")")
    CUR=""; [ -f "$S/$SID" ] && CUR=$(tr -d '[:space:]' < "$S/$SID")
    [ -z "$CUR" ] || [ "$CUR" = "$K" ] || exit 0
    ST=$(jq -r '.stage // empty' "$FP" 2>/dev/null || true)
    [ "$ST" = "paused" ] && exit 0
    mkdir -p "$S"
    echo "$K" > "$S/$SID" ;;
esac
exit 0
