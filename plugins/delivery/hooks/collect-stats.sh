#!/usr/bin/env bash
# SubagentStop: token and time statistics of a pipeline agent run, from its transcript.
# Writes var/agents/<KEY>/stats/<agent>-<agent_id>.json (overwritten on every stop of the same run,
# so the last stop holds the whole run). Never blocks: always exit 0.
INPUT=$(cat)
. "$(dirname "$0")/lib.sh"
command -v jq >/dev/null || exit 0
SID=$(input_sid "$INPUT")
KEY=$(current_key)
[ -n "$KEY" ] || exit 0
DIR="$(agents_dir)/$KEY"
[ -d "$DIR" ] || exit 0
AGENT=$(agent_short "$(echo "$INPUT" | jq -r '.agent_type // empty')")
AID=$(echo "$INPUT" | jq -r '.agent_id // empty')
TR=$(echo "$INPUT" | jq -r '.agent_transcript_path // empty')
MAIN_TR=$(echo "$INPUT" | jq -r '.transcript_path // empty')
case "$TR" in "~/"*) TR="$HOME/${TR#\~/}" ;; esac
[ -n "$AID" ] && [ -f "$TR" ] || exit 0

mkdir -p "$DIR/stats"
STATS=$(jq -R -s --argjson from null --argjson to null -f "$(dirname "$0")/../scripts/transcript-stats.jq" "$TR" 2>/dev/null) || exit 0
[ -n "$STATS" ] || exit 0
STATE=$(jq -c . "$DIR/state.json" 2>/dev/null) || STATE='{}'
[ -n "$STATE" ] || STATE='{}'
jq -n --argjson s "$STATS" --argjson state "$STATE" \
  --arg key "$KEY" --arg agent "$AGENT" --arg aid "$AID" --arg main "$MAIN_TR" '
  {key: $key, agent: $agent, agent_id: $aid,
   stage: ($state.stage // null), round: ($state.round // null), qaMode: ($state.qaMode // null),
   size: ($state.size // null), track: ($state.track // null),
   main_transcript: $main} + $s' > "$DIR/stats/$AGENT-$AID.json.tmp" 2>/dev/null \
  && mv "$DIR/stats/$AGENT-$AID.json.tmp" "$DIR/stats/$AGENT-$AID.json"
rm -f "$DIR/stats/$AGENT-$AID.json.tmp"
exit 0
