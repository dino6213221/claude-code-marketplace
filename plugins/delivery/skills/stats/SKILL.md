---
name: stats
description: Token and time statistics of the delivery pipeline — which stages, agents, tools and individual calls consume the most tokens and time, for one issue or across all issues. Use when the user asks "how many tokens", "which stage is slowest", "statystyki", or after closing an issue.
argument-hint: "[ISSUE-KEY | all] (default: issues in var/agents with statistics)"
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/stats.sh *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/stats.sh" *)
---
Read-only. Do not write, delegate or run git.

1. Run the report script from this plugin (it resolves the handoff root from `.claude/delivery.json`):
   - `$ARGUMENTS` is an issue key → `bash "${CLAUDE_PLUGIN_ROOT}/scripts/stats.sh" <KEY>`
   - `all` → `bash "${CLAUDE_PLUGIN_ROOT}/scripts/stats.sh" --all`
   - empty → list the directories `var/agents/*/stats/` and run the script for each key (or `--all` when none is left but `var/agents/_stats.jsonl` exists).
2. Show the Markdown tables as they are, then at most 3 lines of conclusions, in the user's language:
   - the stage with the largest share of new tokens and of time, compared with the issue size,
   - tools or calls that dominate time (e.g. a reindex or a long phpunit run) or context (large Read/snapshot results),
   - one concrete change to the agent definitions that would reduce it — or "none" when the profile looks proportional.
3. How to read it: **new tokens** = input + cache write + output (what a run really adds; the main cost driver); **cache read** = re-read cached context (cheap per token, but grows with the number of turns); **time** is wall clock including waits for permission prompts; **result size** ≈ tokens a tool result added to the agent's context. The orchestrator row covers the main session's own turns while the issue's agents ran.
