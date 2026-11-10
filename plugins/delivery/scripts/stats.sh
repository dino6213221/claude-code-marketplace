#!/usr/bin/env bash
# Token and time report of the delivery pipeline (Markdown on stdout).
#   stats.sh <KEY>              — one issue: per agent run, per agent, tools, slowest calls, orchestrator
#   stats.sh <KEY> --archive    — also append the issue's per-run rows to var/agents/_stats.jsonl (survives cleanup)
#   stats.sh --all              — all archived issues + issues still in var/agents: averages per agent and size
# Data: var/agents/<KEY>/stats/*.json written by hooks/collect-stats.sh (SubagentStop).
# Tokens: "new" = input + cache write + output (what a run really adds); "cache read" = re-read cached context.
# Time = wall clock of the run, including waits for permission prompts.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
. "$HERE/../hooks/lib.sh"
command -v jq >/dev/null || { echo "jq required"; exit 1; }
A="$(agents_dir)"

fmt_defs='
def dur: (. // 0 | floor) as $s | "\($s / 60 | floor)m\($s % 60 | tostring | if length < 2 then "0" + . else . end)s";
def k: (. // 0) as $n | if $n >= 1000000 then "\($n / 100000 | floor / 10)M" elif $n >= 1000 then "\($n / 100 | floor / 10)k" else "\($n)" end;
def new: (.tokens.input + .tokens.cache_write + .tokens.output);
def pct($a; $b): if $b > 0 then "\($a * 100 / $b | round)%" else "-" end;
def stg: if .agent == "qa" then "qa:\(.qaMode // "?")" else (.stage // "?") end;
'

if [ "${1:-}" = "--all" ]; then
  ROWS=$( { cat "$A/_stats.jsonl" 2>/dev/null; for f in "$A"/*/stats/*.json; do [ -f "$f" ] && jq -c '{key, agent, stage, qaMode, round, size, track, models, seconds, turns, tokens}' "$f"; done; } | jq -s 'unique_by([.key, .agent, .stage, .qaMode, .round, .seconds])')
  echo "$ROWS" | jq -r "$fmt_defs"'
    "# Delivery pipeline — all issues (\(map(.key) | unique | length) issues, \(length) agent runs)\n",
    "| Agent | Size | Runs | Avg time | Avg new tokens | Avg cache read | Share of all new tokens | Share of all time |",
    "|---|---|---|---|---|---|---|---|",
    ((map(new) | add // 0) as $T | (map(.seconds) | add // 0) as $S
     | group_by([.agent, (.size // "?")])[]
     | "| \(.[0].agent) | \(.[0].size // "?") | \(length) | \(map(.seconds) | add / length | dur) | \(map(new) | add / length | floor | k) | \(map(.tokens.cache_read) | add / length | floor | k) | \(pct(map(new) | add; $T)) | \(pct(map(.seconds) | add; $S)) |")'
  exit 0
fi

KEY="${1:-}"; [ -n "$KEY" ] || { echo "usage: stats.sh <KEY> [--archive] | --all"; exit 1; }
D="$A/$KEY/stats"
ls "$D"/*.json >/dev/null 2>&1 || { echo "No statistics for $KEY (no $D/*.json — hooks/collect-stats.sh writes them when pipeline agents stop)."; exit 0; }
RUNS=$(jq -s 'sort_by(.start)' "$D"/*.json)

# Orchestrator: the main session's own turns between the first agent start and the last agent end
MAIN=$(echo "$RUNS" | jq -r 'map(.main_transcript // empty) | map(select(length > 0)) | last // empty')
case "$MAIN" in "~/"*) MAIN="$HOME/${MAIN#\~/}" ;; esac
ORCH='null'
if [ -n "$MAIN" ] && [ -f "$MAIN" ]; then
  FROM=$(echo "$RUNS" | jq 'map(.start) | min'); TO=$(echo "$RUNS" | jq 'map(.end) | max')
  ORCH=$(jq -R -s --argjson from "$FROM" --argjson to "$TO" -f "$HERE/transcript-stats.jq" "$MAIN" 2>/dev/null || echo null)
fi

echo "$RUNS" | jq -r --argjson orch "$ORCH" --arg key "$KEY" "$fmt_defs"'
  (map(new) | add) as $T | (map(.seconds) | add) as $S
  | "# \($key) — tokens and time\n",
    "Agent runs: \(length) · total time \($S | dur) · new tokens \($T | k) · cache read \(map(.tokens.cache_read) | add | k)" +
      (if $orch != null then " · orchestrator: new tokens \($orch | new | k), cache read \($orch.tokens.cache_read | k)" else "" end),
    "\n## Per agent run (chronological)\n",
    "| # | Agent | Stage | Round | Model | Time | Turns | New tokens | Cache read | Output | Top tool (time) |",
    "|---|---|---|---|---|---|---|---|---|---|---|",
    (to_entries[] | .key as $i | .value
     | (.tools | to_entries | sort_by(-.value.seconds) | .[0] // null) as $top
     | "| \($i + 1) | \(.agent) | \(stg) | \(.round // "-") | \(.models | map(sub("^claude-"; "")) | join(", ")) | \(.seconds | dur) | \(.turns) | \(new | k) (\(pct(new; $T))) | \(.tokens.cache_read | k) | \(.tokens.output | k) | \(if $top then "\($top.key) \($top.value.seconds | dur)" else "-" end) |"),
    "\n## Per agent\n",
    "| Agent | Runs | Time | Share of time | New tokens | Share of tokens |",
    "|---|---|---|---|---|---|",
    (group_by(.agent) | sort_by(-(map(new) | add))[]
     | "| \(.[0].agent) | \(length) | \(map(.seconds) | add | dur) | \(pct(map(.seconds) | add; $S)) | \(map(new) | add | k) | \(pct(map(new) | add; $T)) |"),
    "\n## Tools (all agents)\n",
    "| Tool | Calls | Time | Result size (≈ tokens added to context) |",
    "|---|---|---|---|",
    ([.[].tools | to_entries[]] | group_by(.key) | map({tool: .[0].key, calls: (map(.value.calls) | add), seconds: (map(.value.seconds) | add), chars: (map(.value.result_chars) | add)})
     | sort_by(-.seconds)[] | "| \(.tool) | \(.calls) | \(.seconds | dur) | \(.chars / 4 | floor | k) |"),
    "\n## Slowest calls\n",
    "| Agent | Stage | Call | Time |",
    "|---|---|---|---|",
    ([.[] | . as $r | .slowest[] | . + {agent: $r.agent, stage: ($r | stg)}] | map(select(.seconds >= 1)) | sort_by(-.seconds) | .[0:10][]
     | "| \(.agent) | \(.stage) | \(.label) | \(.seconds | dur) |")'

if [ "${2:-}" = "--archive" ]; then
  echo "$RUNS" | jq -c '.[] | {key, agent, stage, qaMode, round, size, track, models, seconds, turns, tokens}' >> "$A/_stats.jsonl"
  echo; echo "_Archived $(echo "$RUNS" | jq length) runs to var/agents/_stats.jsonl._"
fi
