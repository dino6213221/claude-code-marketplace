---
name: status
description: Show the state of the delivery pipeline for the current (or given) issue — stage, round, track, size and the status line of every handoff file — without changing anything. Use when the user asks "where is the pipeline", "status of <KEY>", or before resuming /delivery:deliver.
argument-hint: "[ISSUE-KEY] (default: all issues in var/agents)"
---
Read-only. Do not write, delegate or run git.

1. Handoff root: `<magentoRoot>/var/agents` (`magentoRoot` from `.claude/delivery.json`, default `.`). Key: `$ARGUMENTS`. No key → list the issue directories in `var/agents/` (skip dot-entries and `_retro.md`) with `stage` (and `resumeStage` when paused) from each `state.json`, mark the one holding the **code lock** (stage `implementation`/`review`/`qa`; more than one = problem), list the session bindings from `var/agents/.sessions/` (count per key; two sessions on one key = problem), and stop.
2. For the key: show `state.json` (stage, round, track, size, risk, qaMode), the last `timings.log` line per agent (seconds, ok/rejected) when the file exists, and a table — file · first line (`STATUS: …`) · number of unchecked `[ ]` in "Success criteria" · open questions addressed to `user` (count) · last modified.
3. One line "Next step": what `/delivery:deliver <KEY>` would do on resume (per the stage and the statuses), and anything blocking it (open questions to the user, access/diagnostic/git proposals waiting for approval).
4. Problems worth flagging, if any: a session binding (`.sessions/*`) pointing to a key with no directory; recent lines in `var/agents/.unbound.log` (a pipeline agent ran in a session with no bound issue — normal for BA mode A, otherwise the session binding did not work and the gate was skipped); `state.json` missing (issue started with delivery < 1.1.0 — resume works, but hooks fall back to legacy QA detection); a `.claude` directory under `var/agents/` (agent memory in the wrong place).
