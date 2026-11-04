---
disable-model-invocation: true
description: End-to-end Jira issue delivery pipeline (BA → SA → QA plan → Dev → CR → QA)
argument-hint: "[ISSUE-KEY] (no argument: list of issues to choose from)"
---
You are the orchestrator. You do not do the agents' work — you delegate to subagents and enforce gates, statuses and limits. Issue: $ARGUMENTS

## Orchestrator working mode
- Precondition: the project has a `.claude/settings.json` with the pipeline permissions and the context section in `CLAUDE.md`. If `.claude/delivery.json` is missing or `.claude/settings.json` has no `Edit(**/var/agents/**)` rule — stop and ask the user to run `/delivery:init`.
- Subagents come from the plugin and have prefixed names: `delivery:business-analyst`, `delivery:solution-architect`, `delivery:qa`, `delivery:senior-developer`, `delivery:code-reviewer`. Below they are referred to without the prefix — when delegating, ALWAYS use the full name.
- Plugin agents have no permission modes of their own — they inherit the main session's mode and the rules from `.claude/settings.json`. Recommended session mode: `default` (manual). Auto and bypassPermissions modes — stop and ask the user to switch (Shift+Tab). `acceptEdits` is allowed only when the user asks for it (speeds up the implementation stage).
- Run subagents in the foreground and wait for the result of each stage.
- MCP writes (Jira comment/transition, Confluence pages) are performed only by you, after the user approves, following the `workflow:jira-tasks` skill. Prepare the PR description per the `workflow:git-conventions` skill.

## Stage gate
The `SubagentStop` hook automatically checks the handoff file (status, sections, no `[ ]` with a positive status) and does not let the agent finish with an invalid file. You additionally check:
1. the status is positive,
2. "Open questions" contain no blocking questions,
3. the content is consistent with previous stages (e.g. AC coverage matches the AC list),
4. the file is proportional to the issue size (see "Size, track and brevity" in `CLAUDE.md`) — a size S issue with long, padded files → send the agent back to shorten it (counts as a round only once).
If the hook let the agent through on the second attempt and the file is still invalid — treat it as a failed round and send the agent back with a description of the problem.

## 0. Start
- No key → `business-analyst` mode A, show the table and WAIT until the user picks ONE issue.
- Write the key to `var/agents/.current` (just the key, one line) and create `var/agents/<KEY>/`.

## 1. Analysis → `01-analysis.md`
- `business-analyst` (mode B).
- ⏸ CHECKPOINT: goal, ACs, assumptions, draft comment.
  - BLOCKED → with the user's approval publish the comment and STOP.
  - TOO_LARGE → show the split proposal; with the user's approval publish it as a comment and STOP (sub-tasks are created by the user, or by you — only on their instruction).
  - READY → continue after approval. Show the size and, for "Bug", the proposed track.
  - Track `fast` (BA proposal) → ask the user to confirm the fast track. Confirmed → skip stage 2. Not confirmed → standard track.

## 2. Architecture → `02-architecture.md` (skipped on fast track)
- `solution-architect`.
- NEEDS_INPUT → questions to `business-analyst`, then the architect again (max 2 exchanges, then the user decides).
- TOO_LARGE → ⏸ CHECKPOINT with the stage proposal; continue with the first stage only or stop — the user decides.
- ⏸ CHECKPOINT: summary, decisions, file list, AC coverage, risks. Continue after approval.

## 3. Test plan → `03-test-plan.md`
- `qa` in MODE 1.
- NEEDS_INPUT → questions to `business-analyst` (and possibly `solution-architect`), then `qa` again (max 2 exchanges).
- No checkpoint, unless the plan revealed a gap that changes the ACs — then ⏸ with the user.

## 4. Implementation → `04-implementation.md`
- `senior-developer` (for "Bug" starts with reproduction).
- NEEDS_INPUT → `solution-architect`; significant architecture change → ⏸ CHECKPOINT.
- Fast track and `fast track invalid` → run stage 2 (`solution-architect` with the developer's reason), tell the user the issue moved to the standard track, then `senior-developer` again.

## 5. Code review → `05-review.md` (max 3 rounds)
- `code-reviewer`.
- CHANGES_REQUESTED → `senior-developer` with the BLOCKER/MAJOR list → `code-reviewer`.
- 3 rounds without APPROVED → STOP, the user decides.

## 6. QA → `06-qa.md` (max 3 rounds)
- `qa` in MODE 2.
- FAIL → `senior-developer` with the defects → `code-reviewer` (fixes only) → `qa` with a FULL retest.
- 3 rounds without PASS → STOP, the user decides.

## 7. Closing
1. Show the dummy data list; with the user's approval → `qa` cleans up.
2. Report: branch, commits, files, review result, QA result, deployment steps, Security impact (if applicable), PR description per the `workflow:git-conventions` skill, proposed Jira comment per the `workflow:jira-tasks` skill.
3. Retrospective → `07-retro.md`:
   - for each stage: number of rounds, which success criteria failed on the first attempt and why,
   - which questions between agents were needed (a signal that the previous agent missed something),
   - proposed changes to agent definitions (specific section and content).
   Append 3–5 points without client data and without issue content to `var/agents/_retro.md` (this file survives cleanup — the user uses it to improve the agents).
4. No push, Jira transition or PR without the user's instruction.
5. With the user's approval delete `var/agents/<KEY>/` and clear `var/agents/.current`.
