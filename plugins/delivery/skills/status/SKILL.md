---
name: status
description: Show the state of the delivery pipeline for the current (or given) issue — stage, round, track, size and the status line of every handoff file — without changing anything. Use when the user asks "where is the pipeline", "status of <KEY>", or before resuming /delivery:deliver.
argument-hint: "[ISSUE-KEY] (default: the key in var/agents/.current)"
---
Read-only. Do not write, delegate or run git.

1. Handoff root: `<magentoRoot>/var/agents` (`magentoRoot` from `.claude/delivery.json`, default `.`). Key: `$ARGUMENTS`, else the content of `var/agents/.current`. No key → list the directories in `var/agents/` (except `_retro.md`) with the `stage` from each `state.json`, and stop.
2. For the key: show `state.json` (stage, round, track, size, qaMode) and a table — file · first line (`STATUS: …`) · number of unchecked `[ ]` in "Success criteria" · open questions addressed to `user` (count) · last modified.
3. One line "Next step": what `/delivery:deliver <KEY>` would do on resume (per the stage and the statuses), and anything blocking it (open questions to the user, access/diagnostic/git proposals waiting for approval).
4. Problems worth flagging, if any: `.current` points to a key with no directory; `state.json` missing (issue started with delivery < 1.1.0 — resume works, but hooks fall back to legacy QA detection); a `.claude` directory under `var/agents/` (agent memory in the wrong place).
