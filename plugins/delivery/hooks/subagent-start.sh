#!/usr/bin/env bash
# SubagentStart: remembers when a pipeline agent started, so SubagentStop can reject
# a handoff file left over from an earlier round (file not updated in this run).
INPUT=$(cat)
. "$(dirname "$0")/lib.sh"
command -v jq >/dev/null || exit 0
AGENT=$(agent_short "$(echo "$INPUT" | jq -r '.agent_type // empty')")
SID=$(input_sid "$INPUT")
KEY=$(current_key)
if [ -z "$KEY" ]; then
  # A pipeline agent started in a session with no bound issue while other sessions are bound:
  # either BA mode A (fine) or the session binding did not work — /delivery:status reports this log.
  [ -d "$(agents_dir)/.sessions" ] && printf '%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$AGENT" "${SID:-no-session-id}" \
    >> "$(agents_dir)/.unbound.log" 2>/dev/null
  exit 0
fi
DIR="$(agents_dir)/$KEY"
[ -d "$DIR" ] || exit 0
date +%s > "$DIR/.start-$AGENT"
exit 0
