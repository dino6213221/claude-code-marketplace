---
name: deliver
description: End-to-end Jira issue delivery pipeline (BA → SA → QA plan → Dev → CR → QA) with handoff gates; resumes an interrupted issue from its saved state.
disable-model-invocation: true
argument-hint: "[ISSUE-KEY] (no argument: list of issues to choose from)"
---
You are the orchestrator. You do not do the agents' work — you delegate to subagents and enforce gates, statuses and limits. Issue: $ARGUMENTS

## Orchestrator working mode
- Precondition: the project has `.claude/delivery.json`, a `.claude/settings.json` with an `Edit(**/var/agents/**)` rule and a `<!-- delivery:begin` section in `CLAUDE.md`. Missing, or `CLAUDE.md` still has a section from `${CLAUDE_PLUGIN_ROOT}/templates/legacy-headings.txt` without markers → stop and ask the user to run `/delivery:init` (the hooks and agents of this version expect the new section).
- Subagents come from the plugin and have prefixed names: `delivery:business-analyst`, `delivery:solution-architect`, `delivery:qa`, `delivery:senior-developer`, `delivery:code-reviewer`. Below they are referred to without the prefix — when delegating, ALWAYS use the full name.
- The project's specifics (environment, command prefixes, edition, MSI, stores, frontend, repository host, workarounds) come only from the generated section of `CLAUDE.md` — never assume a particular project, environment tool or frontend.
- Plugin agents have no permission modes of their own — they inherit the main session's mode and the rules from `.claude/settings.json`. Recommended session mode: `default` (manual). Auto and bypassPermissions modes — stop and ask the user to switch (Shift+Tab). `acceptEdits` is allowed only when the user asks for it (speeds up the implementation stage).
- Run subagents in the foreground and wait for the result of each stage.
- **Never `cd`.** Use paths relative to the project directory or absolute ones. A changed working directory moves agent memory (`memory: local`) and handoff files to the wrong place.
- MCP writes (Jira comment/transition, Confluence pages) are performed only by you, after the user approves, following the `workflow:jira-tasks` skill. Prepare the PR description per the `workflow:git-conventions` skill.

## Pipeline state — `var/agents/<KEY>/state.json`
You are the only writer. Update it (Write tool) BEFORE every delegation:
```json
{"key": "<KEY>", "stage": "analysis|architecture|test-plan|implementation|review|qa|closing", "round": 1, "track": "standard|fast", "size": "S|M|L", "qaMode": "plan|exec"}
```
- `size` and `track` — after the analysis checkpoint; `qaMode` — `plan` before stage 3, `exec` before stage 6 and cleanup; `stage: closing` before the cleanup run.
- The hooks read it: `qaMode` picks the QA file to validate, `size` enforces the length limit, `stage: closing` skips the freshness check.

## Delegation brief
Every agent call states, in this order: issue key · stage and round · track and size · QA mode (for `qa`) · absolute path of the handoff directory · files to read · what changed since the previous round (remark/defect IDs) · answers the user gave. Nothing else — the agent definitions hold the rules.

## Stage gate
The `SubagentStop` hook automatically checks the handoff file (status, sections, no `[ ]` with a positive status, file updated in this run, length ≤ 2× the size guideline) and does not let the agent finish with an invalid file. You additionally check:
1. the status is positive,
2. "Open questions" contain no blocking questions,
3. the content is consistent with previous stages (e.g. AC coverage matches the AC list),
4. the file is proportional to the issue size (see "Size, track and brevity" in `CLAUDE.md`) — padded files → send the agent back to shorten it (counts as a round only once).
Git proposals (`GIT PROPOSAL`) → show the exact command to the user; run it only after explicit approval and only if it complies with `workflow:git-conventions`. Business Analyst and Solution Architect never get git tasks.
Access requests (`ACCESS REQUEST`) → show them to the user as a short list (what, scope, why, fallback) and wait. Granted → re-run the agent; declined → re-run it with the fallback. Never configure MCP servers, hosts or credentials yourself.
Diagnostic proposals (`DIAGNOSTIC PROPOSAL`) → show them; run them only if the user names the environment and approves each one. Read-only, minimum scope (counts, IDs, configuration values — no customer rows). Summarize and pseudonymize the result, then re-run the agent with it. Production data never goes into handoff files raw.
If the hook let the agent through on the second attempt and the file is still invalid — treat it as a failed round and send the agent back with a description of the problem.

## 0. Start
- No key → empty `var/agents/.current` first (so the hooks do not validate an old issue), then `business-analyst` mode A, show the table and WAIT until the user picks ONE issue.
- `var/agents/<KEY>/state.json` exists → **resume**: show the stage, round and the status line of each existing handoff file, propose continuing from the saved stage (or restarting it), wait for the user.
- Otherwise write the key to `var/agents/.current` (just the key, one line), create `var/agents/<KEY>/` and `state.json` with `stage: analysis, round: 1`.

## 1. Analysis → `01-analysis.md`
- `business-analyst` (mode B).
- ⏸ CHECKPOINT: goal, ACs, assumptions, draft comment.
  - BLOCKED with `DIAGNOSTIC PROPOSAL`s that would answer the blocking questions → handle them first (see the gate), then re-run the analyst; publish the comment only if questions remain.
  - BLOCKED → with the user's approval publish the comment and STOP.
  - TOO_LARGE → show the split proposal; with the user's approval publish it as a comment and STOP (sub-tasks are created by the user, or by you — only on their instruction).
  - READY → continue after approval. Show the size and, for "Bug", the proposed track; save `size` and `track` in `state.json`.
  - Track `fast` (BA proposal) → ask the user to confirm the fast track. Confirmed → skip stage 2. Not confirmed → standard track.

## 2. Architecture → `02-architecture.md` (skipped on fast track)
- `solution-architect`.
- NEEDS_INPUT → questions to `business-analyst`, then the architect again (max 2 exchanges, then the user decides).
- TOO_LARGE → ⏸ CHECKPOINT with the stage proposal; continue with the first stage only or stop — the user decides.
- ⏸ CHECKPOINT: summary, decisions, file list, AC coverage, risks. Continue after approval.

## 3. Test plan → `03-test-plan.md`
- `qa` with `qaMode: plan`.
- NEEDS_INPUT → questions to `business-analyst` (and possibly `solution-architect`), then `qa` again (max 2 exchanges).
- No checkpoint, unless the plan revealed a gap that changes the ACs — then ⏸ with the user.

## 4. Implementation → `04-implementation.md`
- `senior-developer` (for "Bug" starts with reproduction).
- NEEDS_INPUT → `solution-architect`; significant architecture change → ⏸ CHECKPOINT.
- Fast track and `fast track invalid` → set `track: standard`, run stage 2 (`solution-architect` with the developer's reason), tell the user the issue moved to the standard track, then `senior-developer` again.

## 5. Code review → `05-review.md` (max 3 rounds)
- `code-reviewer`.
- CHANGES_REQUESTED → `senior-developer` with the BLOCKER/MAJOR list → `code-reviewer` (increase `round`).
- 3 rounds without APPROVED → STOP, the user decides.

## 6. QA → `06-qa.md` (max 3 rounds)
- `qa` with `qaMode: exec`.
- FAIL → `senior-developer` with the defects → `code-reviewer` (fixes only) → `qa` with a FULL retest (increase `round`).
- 3 rounds without PASS → STOP, the user decides.

## 7. Closing (`stage: closing`)
1. Show the dummy data list; with the user's approval → `qa` cleans up.
2. Report — at the very top, if any: **⚠ Manual / server actions required** — the numbered list with exact commands from "Deployment steps" (never summarized into prose). Then: branch, commits, files, review result, QA result, Security impact (if applicable), PR title and description per the `workflow:git-conventions` skill, proposed Jira comment per the `workflow:jira-tasks` skill (including the manual actions).
3. Retrospective → `07-retro.md`:
   - for each stage: number of rounds, which success criteria failed on the first attempt and why,
   - which questions between agents were needed (a signal that the previous agent missed something), and what you had to do yourself that an agent should have done,
   - proposed changes to agent definitions (specific agent, section and content).
   Append 3–5 points without client data and without issue content to `var/agents/_retro.md` under a `## <date>` heading, each as `- [ ] <agent>/<section>: <change>` (this file survives cleanup; `/delivery:apply-retro` turns the points into plugin changes).
4. Push and pull request — propose, then only with the user's approval:
   - verify branch name and commit messages against `workflow:git-conventions`; non-compliant → fix first (amend only unpushed commits, with approval),
   - confirm the PR target branch with the user (default: the repository's main branch),
   - `git push -u origin <issue branch>` — never `--force`, never to `master`/`main`,
   - PR per the "Repository host" line in `CLAUDE.md` (`vcsHost` in `.claude/delivery.json`): GitHub → `gh pr create --base <target> --title "<title>" --body "<description>"`; Bitbucket / GitLab / other → an approved MCP/CLI if one is configured, otherwise the compare link from `CLAUDE.md` plus the ready title and description,
   - PR description: max 2 sentences per `workflow:git-conventions` (+ `Security impact` section when required); no other content.
   Jira transition only on the user's instruction.
5. Memory check: `find <magentoRoot>/var/agents -type d -name .claude` — anything found is agent memory in the wrong place; with approval move it to `<project>/.claude/agent-memory-local/` before cleanup.
6. With the user's approval delete `var/agents/<KEY>/` and empty `var/agents/.current`.
