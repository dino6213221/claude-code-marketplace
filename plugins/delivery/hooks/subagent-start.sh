#!/usr/bin/env bash
# SubagentStart: remembers when a pipeline agent started, so SubagentStop can reject
# a handoff file left over from an earlier round (file not updated in this run).
INPUT=$(cat)
. "$(dirname "$0")/lib.sh"
command -v jq >/dev/null || exit 0
AGENT=$(agent_short "$(echo "$INPUT" | jq -r '.agent_type // empty')")
KEY=$(current_key)
[ -n "$KEY" ] || exit 0
DIR="$(agents_dir)/$KEY"
[ -d "$DIR" ] || exit 0
date +%s > "$DIR/.start-$AGENT"
exit 0
