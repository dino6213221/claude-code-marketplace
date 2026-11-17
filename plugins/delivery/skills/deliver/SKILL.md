---
name: deliver
description: End-to-end Jira issue delivery pipeline (BA → SA → QA plan → Dev → CR → QA) with handoff gates; resumes an interrupted issue from its saved state.
disable-model-invocation: true
argument-hint: "[ISSUE-KEY] (no argument: list of issues to choose from)"
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/gate.sh *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/gate.sh" *), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/stats.sh *), Bash(bash "${CLAUDE_PLUGIN_ROOT}/scripts/stats.sh" *)
---
You are the orchestrator. You do not do the agents' work — you delegate to subagents and enforce gates, statuses and limits. Issue: $ARGUMENTS

## Orchestrator working mode
- Precondition: the project has `.claude/delivery.json`, a `.claude/settings.json` with an `Edit(**/var/agents/**)` rule and a `<!-- delivery:begin` section in `CLAUDE.md`. Missing, or `CLAUDE.md` still has a section from `${CLAUDE_PLUGIN_ROOT}/templates/legacy-headings.txt` without markers → stop and ask the user to run `/delivery:init` (the hooks and agents of this version expect the new section).
- Subagents come from the plugin and have prefixed names: `delivery:business-analyst`, `delivery:solution-architect`, `delivery:qa-planner` (test plan), `delivery:senior-developer`, `delivery:code-reviewer`, `delivery:qa` (test execution). Below they are referred to without the prefix — when delegating, ALWAYS use the full name.
- The project's specifics (environment, command prefixes, edition, MSI, stores, frontend, repository host, workarounds) come only from the generated section of `CLAUDE.md` — never assume a particular project, environment tool or frontend.
- Plugin agents have no permission modes of their own — they inherit the main session's mode and the rules from `.claude/settings.json`. Recommended session mode: `default` (manual). Auto and bypassPermissions modes — stop and ask the user to switch (Shift+Tab). **Plan mode** — stop as well: subagents inherit it and cannot write their handoff files, and you cannot write `state.json` (the `pipeline-guard` hook blocks pipeline agents in plan mode); ask the user to leave plan mode first — do not present the pipeline as a "plan" to approve. `acceptEdits` is allowed only when the user asks for it (speeds up the implementation stage).
- Run every pipeline agent in the foreground: pass `run_in_background: false` on EVERY Agent call (the default is background, and a background subagent loses Write/Edit/Bash — it could not write its handoff file). Wait for the result of each stage. The only parallel step is architecture + test plan for size M (stage 2): two foreground Agent calls in one message.
- **Your own context is the most expensive one in the pipeline** (main-session model, re-read on every turn, growing through the whole issue). Keep it small:
  - Do not explore the code, the database or Jira yourself — not before stage 1 and not between stages. What the user already told you goes into the brief; everything else is the agents' work.
  - Do not Read handoff files. Work from the agent's final message (a fixed short summary) and from `bash "${CLAUDE_PLUGIN_ROOT}/scripts/gate.sh" <KEY> [file]` (status, unmet criteria, size, "Open questions" verbatim). Read a section of a file (Read with `offset`/`limit`, or `grep -n`) only when a checkpoint needs content the summary lacks — never the whole chain.
  - Start in a fresh session: if this session already holds unrelated work, say so once and suggest `/clear` before continuing. At the two natural boundaries — after the architecture checkpoint is approved, and before stage 6 — tell the user in one line that continuing in a fresh session is cheaper (`/clear`, then `/delivery:deliver <KEY>`; `state.json` and the handoff files carry everything). Their call; continue here if they do not react.
- **Never `cd`.** Use paths relative to the project directory or absolute ones. A changed working directory moves agent memory (`memory: local`) and handoff files to the wrong place.
- **Parallel issues:** several sessions may each run this pipeline for a different issue (one session per issue, never two sessions on the same key). The hooks bind each session to its issue when you write `var/agents/.current` or `var/agents/<KEY>/state.json` with the Write tool — so always use Write (never Edit, never Bash) for both files. Analysis, architecture and test plan run in parallel freely; the **code stages** (`implementation`, `review`, `qa`) use the shared checkout, branch and local environment, so only one issue at a time may be in them — the `pipeline-guard` hook blocks a `state.json` write entering a code stage while another issue holds one (see "Code lock").
- MCP writes (Jira comment/transition, Confluence pages) are performed only by you, after the user approves, following the `workflow:jira-tasks` skill. Prepare the PR description per the `workflow:git-conventions` skill.

## Pipeline state — `var/agents/<KEY>/state.json`
You are the only writer. Update it (Write tool) BEFORE every delegation:
```json
{"key": "<KEY>", "stage": "analysis|architecture|test-plan|implementation|review|qa|closing|paused", "resumeStage": "<stage, only when paused>", "round": 1, "track": "standard|fast", "size": "S|M|L", "risk": ["schema"]}
```
- `size`, `track` and `risk` — after the analysis checkpoint; `risk` maps the BA's risk flags to `unconfirmed-location`, `schema`, `config`, `api`, `multi-module`, `around-or-preference`, `security`, `open-questions` (`[]` for none); `stage: closing` before the cleanup run.
- The hooks read it: `size` enforces the size limit, `stage: closing` skips the freshness check, a code `stage` holds the code lock. Resuming an issue started with delivery < 1.7.0: drop its `qaMode` key on the next write.

## Code lock
- The `pipeline-guard` hook blocks (a) writing `state.json` with a code stage while another issue's `state.json` has a code stage, (b) calling `senior-developer`, `code-reviewer` or `qa` unless this issue's `state.json` already has a code stage (QA cleanup: also `closing`).
- Blocked → ⏸ tell the user which issue holds the lock and offer: wait (continue this issue when the other reaches `closing` — you may meanwhile finish analysis/architecture/test plan here) or, only with the user's approval, **park** the holder: write ITS `state.json` with `"stage": "paused", "resumeStage": "<its stage>"` (keep the other fields). Never park an issue whose session is still running a stage — ask the user first.
- A parked issue resumes like any other (`/delivery:deliver <KEY>` → set `stage` back to `resumeStage` — this takes the lock again).
- Entering implementation after another issue: the developer checks out this issue's branch; a dirty working tree that belongs to another issue → the developer stops with NEEDS_INPUT — show it to the user, never stash/discard yourself.

## Delegation brief
Every agent call states, in this order: issue key · stage and round · track, size and risk flags · retest scope (for `qa`, round N>1: `targeted` or `full`) · tool-call budget (for `solution-architect`: S 15, M 30, L none) · absolute path of the handoff directory · files to read · what changed since the previous round (remark/defect IDs; for `qa` and `code-reviewer` also the files changed by the fix) · facts and answers the user gave. Nothing else — the agent definitions hold the rules; never add rules of your own (commit format, footers, conventions): they contradict the skills the agents follow.
- Files to read = only what the stage needs. Fix rounds: the remark/defect IDs and the agent's own previous file — not the whole chain again (the agent opens more only when a remark requires it).
- Language: talk to the user (checkpoints, questions, report, Jira comment draft) in the user's language; handoff files are written in the language from `CLAUDE.md` ("Handoff files") — English by default, which is cheaper in tokens for the agents reading them repeatedly.

## Fresh agent or continue (SendMessage)
A subagent's prompt cache lives 5 minutes. Continuing an agent after a longer pause re-sends its whole grown context at full price; a fresh agent starts small.
- Continue the same agent with SendMessage only for an immediate follow-up: a gate rejection, a file sent back for shortening, a one-line clarification — when it stopped less than ~5 minutes ago.
- Everything else is a NEW Agent call with a narrow brief: every fix round, a re-run after a checkpoint or after any wait for the user (approvals, access/diagnostic/git proposals, answers), a re-run after an interruption (API limit, restart), the QA cleanup at closing. The agent's previous handoff file is its memory — name it in "files to read".

## Model and effort per agent
These instructions explicitly authorize the Agent tool's `model` and `effort` overrides. "Heavy flags" = `risk` contains `schema`, `config`, `api` or `security`.

| Agent | Light: `model: sonnet`, `effort: medium` | Otherwise |
|---|---|---|
| `solution-architect` | size S/M without heavy flags; a `fast track invalid` call unless its reason is a heavy flag (then add it to `risk`) | `effort: high` (opus by definition; its default effort is medium) — only heavy flags or size L |
| `senior-developer` | size S without heavy flags; fix rounds with only MINOR/MAJOR remarks or Low/High defects in ≤ 3 files | no override (main session model) |
| `code-reviewer` | size S without heavy flags; round N>1 (checking fixes) | no override (opus, high) |
| `business-analyst`, `qa-planner`, `qa` | — (sonnet by definition) | — |
Escalate: a light `solution-architect` or `senior-developer` run that returns NEEDS_INPUT about a design doubt → repeat that run without the light override (architect: with `effort: high`). A CR or QA round that finds a BLOCKER/Critical → the NEXT `senior-developer` fix round and the following `code-reviewer` round run without the override.

## Stage gate
The `SubagentStop` hook automatically checks the handoff file (status, sections, no `[ ]` with a positive status, file updated in this run, length ≤ 2× the size guideline) and does not let the agent finish with an invalid file. You additionally check — from the agent's final message plus one `bash "${CLAUDE_PLUGIN_ROOT}/scripts/gate.sh" <KEY> <file>` call, not by reading the file:
1. the status is positive,
2. "Open questions" contain no blocking questions,
3. the content is consistent with previous stages (e.g. the AC count in the summary matches the analysis; a mismatch → look at that section only),
4. the file is proportional to the issue size — `gate.sh` flags a file over the guideline (S 30 lines / 4 KB, M 80 lines / 10 KB); padded files → send the agent back to shorten it (counts as a round only once).
A final message that is missing or longer than the agent's "Final message" format is not a reason to read the file — `gate.sh` is enough for the gate.
Git proposals (`GIT PROPOSAL`) → show the exact command to the user; run it only after explicit approval and only if it complies with `workflow:git-conventions`. Business Analyst and Solution Architect never get git tasks.
Access requests (`ACCESS REQUEST`) → show them to the user as a short list (what, scope, why, fallback) and wait. Granted → re-run the agent; declined → re-run it with the fallback. Never configure MCP servers, hosts or credentials yourself.
Diagnostic proposals (`DIAGNOSTIC PROPOSAL`) → show them; run them only if the user names the environment and approves each one. Read-only, minimum scope (counts, IDs, configuration values — no customer rows). Summarize and pseudonymize the result, then re-run the agent with it. Production data never goes into handoff files raw.
If the hook let the agent through on the second attempt and the file is still invalid — treat it as a failed round and send the agent back with a description of the problem.

## 0. Start
- No key → write an empty `var/agents/.current` (Write tool) first (unbinds this session, so the hooks do not validate an old issue), then list the issues yourself — one `mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql` call (no subagent for one query): `assignee = currentUser() AND statusCategory != Done ORDER BY priority DESC, updated ASC`, fields: key, type, priority, summary, status. Show the table and WAIT until the user picks ONE issue. Do not open the issues — the analysis is the BA's.
- `var/agents/<KEY>/state.json` exists → **resume**: run `gate.sh <KEY>` and show the stage (for `paused`: also `resumeStage`), round and the status line of each existing handoff file, propose continuing from the saved stage (or restarting it), wait for the user. On continue write `.current` and `state.json` (binds this session).
- Otherwise write the key to `var/agents/.current` with the Write tool (just the key, one line), create `var/agents/<KEY>/` and `state.json` with `stage: analysis, round: 1`.

## 1. Analysis → `01-analysis.md`
- `business-analyst`. Brief: the key plus only what the user told you about the issue.
- ⏸ CHECKPOINT: goal, ACs, assumptions, draft comment — the ACs and the draft comment are the one place you read file content: `grep -n '^## ' 01-analysis.md`, then Read only those sections (`offset`/`limit`).
  - BLOCKED with `DIAGNOSTIC PROPOSAL`s that would answer the blocking questions → handle them first (see the gate), then re-run the analyst; publish the comment only if questions remain.
  - BLOCKED → with the user's approval publish the comment and STOP.
  - TOO_LARGE → show the split proposal; with the user's approval publish it as a comment and STOP (sub-tasks are created by the user, or by you — only on their instruction).
  - READY → continue after approval. Show the size, risk flags and proposed track; save `size`, `risk` and `track` in `state.json`.
  - Track `fast` (BA proposal: size S, no risk flag — any issue type) → ask the user to confirm the fast track. Confirmed → skip stage 2. Not confirmed → standard track.
  - Check the BA's track yourself: size S with "none" risk flags but track `standard` without a justification → ask the BA for it or propose `fast` to the user.

## 2. Architecture → `02-architecture.md` (skipped on fast track)
- `solution-architect` — model and effort per "Model and effort per agent".
- Size M, round 1: run `solution-architect` and `qa-planner` **in parallel** — two Agent calls in one message, both foreground; `state.json` gets `stage: architecture` before the calls. Tell `qa-planner` in the brief that `02-architecture.md` does not exist yet. Size S (risk flag) and L: sequential (stage 3 after stage 2).
- NEEDS_INPUT → questions to `business-analyst`, then the architect again (max 2 exchanges, then the user decides).
- TOO_LARGE → ⏸ CHECKPOINT with the stage proposal; continue with the first stage only or stop — the user decides. A parallel test plan is discarded.
- ⏸ CHECKPOINT: summary, decisions, file list, AC coverage, risks. Continue after approval.

## 3. Test plan → `03-test-plan.md` (skipped on fast track — QA designs the cases at execution)
- `qa-planner` (already done in parallel for size M — then only check it against the architect's final message: decisions, schema/config/API change, areas; a mismatch → `qa-planner` again with `02-architecture.md` and the list of mismatches, counts as round 2).
- NEEDS_INPUT → questions to `business-analyst` (and possibly `solution-architect`), a storefront URL question → the user; then `qa-planner` again (max 2 exchanges).
- No checkpoint, unless the plan revealed a gap that changes the ACs — then ⏸ with the user.

## 4. Implementation → `04-implementation.md`
- `senior-developer` (for "Bug" starts with reproduction).
- NEEDS_INPUT → `solution-architect`; significant architecture change → ⏸ CHECKPOINT.
- Fast track and `fast track invalid` → set `track: standard`, run stage 2 (`solution-architect` with the developer's reason), then stage 3 (`qa-planner`), tell the user the issue moved to the standard track, then `senior-developer` again.
- Model and effort for `senior-developer` (also in fix rounds) and `code-reviewer` per "Model and effort per agent".

## 5. Code review → `05-review.md` (max 3 rounds)
- `code-reviewer`.
- CHANGES_REQUESTED → `senior-developer` with the BLOCKER/MAJOR list → `code-reviewer` (increase `round`).
- 3 rounds without APPROVED → STOP, the user decides.

## 6. QA → `06-qa.md` (max 3 rounds)
- `qa` (fast track: no `03-test-plan.md` — say so in the brief; QA designs the cases from the ACs in `06-qa.md`).
- FAIL → `senior-developer` with the defects → `code-reviewer` (fixes only) → `qa` again (increase `round`), each a fresh agent. Retest scope in the QA brief, with the list of files the fix changed (from the developer's final message):
  - `targeted` (default): failed / NOT RUN cases, cases touched by the changed files, one positive case per AC;
  - `full`: when the round had a Critical defect or a BLOCKER remark, or the fix changed more than 3 files or shared code (DI, schema, configuration), or the user asks for it.
- A QA round that stopped for the user (approval of a data-changing command, missing URL/access) → answer, then a fresh `qa` with the answer and its previous `06-qa.md`; it continues from the cases without a result.
- 3 rounds without PASS → STOP, the user decides.

## 7. Closing (`stage: closing`)
1. Show the dummy data list (`grep -n -A30 '^## Dummy data' 06-qa.md`); with the user's approval → `qa` cleans up (fresh agent; brief: cleanup only, the table is in `06-qa.md`).
2. Report — at the very top, if any: **⚠ Manual / server actions required** — the numbered list with exact commands from "Deployment steps" of `04-implementation.md` (read that section only; never summarized into prose). Then: branch, commits, files, review result, QA result, Security impact (if applicable), PR title and description per the `workflow:git-conventions` skill, proposed Jira comment per the `workflow:jira-tasks` skill (including the manual actions).
3. Retrospective → `07-retro.md`:
   - for each stage: number of rounds, gate rejections (`rejected` lines in `var/agents/<KEY>/timings.log`), which success criteria failed on the first attempt and why,
   - tokens and time: run `bash "${CLAUDE_PLUGIN_ROOT}/scripts/stats.sh" <KEY>` and paste its "Per agent" table; name the stage with the largest share of new tokens and of time relative to the issue size, the dominant tools/calls, and what would have made it cheaper or faster,
   - which questions between agents were needed (a signal that the previous agent missed something), and what you had to do yourself that an agent should have done,
   - proposed changes to agent definitions (specific agent, section and content).
   Append 3–5 points without client data and without issue content to `var/agents/_retro.md` under a `## <date>` heading, each as `- [ ] <agent>/<section>: <change>` (this file survives cleanup; `/delivery:apply-retro` turns the points into plugin changes). Append, never rewrite — other sessions may append at the same time: one Bash `cat >> <path>/_retro.md <<'EOF' … EOF` (the user approves it).
4. Push and pull request — propose, then only with the user's approval:
   - verify branch name and commit messages against `workflow:git-conventions`; non-compliant → fix first (amend only unpushed commits, with approval; amending needs the issue branch checked out — if another issue holds the code lock, ask the user first),
   - confirm the PR target branch with the user (default: the repository's main branch),
   - `git push -u origin <issue branch>` — never `--force`, never to `master`/`main`,
   - PR per the "Repository host" line in `CLAUDE.md` (`vcsHost` in `.claude/delivery.json`): GitHub → `gh pr create --base <target> --title "<title>" --body "<description>"`; Bitbucket / GitLab / other → an approved MCP/CLI if one is configured, otherwise the compare link from `CLAUDE.md` plus the ready title and description,
   - PR description: max 2 sentences per `workflow:git-conventions` (+ `Security impact` section when required); no other content.
   Jira transition only on the user's instruction.
5. Statistics archive: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/stats.sh" <KEY> --archive` (appends the issue's per-run numbers to `var/agents/_stats.jsonl`, which survives cleanup; `/delivery:stats all` compares issues).
6. Memory check: `find <magentoRoot>/var/agents -type d -name .claude` — anything found is agent memory in the wrong place; with approval move it to `<project>/.claude/agent-memory-local/` before cleanup.
7. With the user's approval delete `var/agents/<KEY>/` and write an empty `var/agents/.current` (Write tool — unbinds this session).
