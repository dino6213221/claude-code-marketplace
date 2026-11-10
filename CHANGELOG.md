# Changelog

## 1.6.0 — 2026-11-10

Upgrade: `/plugin marketplace update daniel-marketplace`, `/plugin update delivery`, `/plugin update magento2`, `/reload-plugins`, then **`/delivery:init` in every project and every clone** (installs the git `pre-push` hook, new allow rule for agent memory).

### delivery — fixes from the code review
- **Orchestrator:** every Agent call passes `run_in_background: false` (a background subagent loses Write/Edit/Bash and could not write its handoff file). Escalation rule fixed: a BLOCKER/Critical found by CR/QA sends the NEXT developer and reviewer rounds to the full model. `_retro.md` is appended (`cat >>`), never rewritten — safe with parallel sessions.
- **git `pre-push` hook** (`templates/pre-push`, installed by init into the clone's hooks path, chains an existing hook as `pre-push.local`): rejects pushes to `master`/`main` and non-fast-forward pushes on the resolved refs.
- **push-guard:** bundled force flags (`-uf`), quoting/subshell/brace/backtick bypasses (normalized command), `git -c alias.*|push.*|remote.*|url.*|core.hooksPath`, command substitution and `--no-verify` blocked; only the real `push` subcommand is inspected (no more false blocks on `git commit -m "… push to main"` or `git stash push`); no temp file.
- **sql-guard:** writes need a WHERE clause targeting a `'QA-…'` literal, without OR/NOT/always-true conditions, comments, multiple statements or multi-table syntax (`UPDATE a, b`, `DELETE x FROM`, JOIN/USING); SQL piped into the client, `SOURCE` in any case, `\.`, `\!`, command substitution and PHP scripts with raw DB access blocked; RENAME TABLE/GRANT/REVOKE/LOAD DATA added.
- **git-guard:** `/usr/bin/git`, `"git"`, `$(which git)` caught.
- **Code lock:** atomic `var/agents/.code-lock` (mkdir, stale after 2 min when the owner left the code stages); invalid JSON in `state.json` blocked; pipeline agents (except BA) blocked in a session not bound to an issue; unprefixed agent names gated like prefixed ones (matchers `^(delivery:)?…`).
- **Session binding:** writing another issue's `state.json` no longer moves the session to it (switching issues goes through `.current`).
- **Handoff gate:** a file passed through on the second attempt is logged as `failed-passed-through` in `timings.log`.
- **Statistics:** Bash call labels whitelisted (known programs, `bin/magento <command>`, `git <sub>`; anything else `bash`) — env assignments such as `MYSQL_PWD=…` and arbitrary words never reach stats or retros.
- Settings: allow `Edit(**/.claude/agent-memory-local/**)` (architect/reviewer memory without prompts). `/delivery:stats` pre-approves the script via `${CLAUDE_PLUGIN_ROOT}`.
- Agents: developer's description and steps cover the fast track (no test plan); QA screenshots under the absolute handoff directory.
- Tests: 59 new cases (bypasses, lock, binding, labels, pre-push with a bare remote).

### magento2 (1.2.1)
- `verify-change`: pipeline mode recognized from the `delivery:qa` brief instead of `var/agents/.current`; fast track cases come from `06-qa.md`.

## 1.5.0 — 2026-11-10

Upgrade: `/plugin marketplace update daniel-marketplace`, `/plugin update delivery`, `/reload-plugins`, then `/delivery:init` in every project (new allow rule for the report script).

### delivery — token and time statistics
- New `hooks/collect-stats.sh` (SubagentStop): reads the agent's transcript (`agent_transcript_path`) and writes `var/agents/<KEY>/stats/<agent>-<agent_id>.json` — wall time, turns, models, tokens (input, cache write, cache read, output; deduplicated per API message), per-tool calls/time/result size and the 5 slowest calls. Bash calls are labeled by program/subcommand only (`bin/magento indexer:reindex`), no arguments or file content. Never blocks the agent.
- New `scripts/stats.sh` + `/delivery:stats [KEY|all]`: Markdown report per agent run, per agent (share of new tokens and time), per tool, slowest calls, plus the orchestrator's own tokens while the issue's agents ran; `--all` averages per agent and size across issues.
- Orchestrator: the retrospective includes the "Per agent" table and names the most expensive stage; closing archives the numbers to `var/agents/_stats.jsonl` (survives cleanup; keys and numbers only).
- Verified: a subagent transcript's `sessionId` equals the main session id, so the per-session binding from 1.3.0 works for subagent hooks.
- Tests: synthetic transcript cases in `tests/hooks.sh`.

## 1.4.0 — 2026-11-10

Upgrade: `/plugin marketplace update daniel-marketplace`, `/plugin update delivery`, `/plugin update magento2` (Playwright server options), `/reload-plugins`, then **`/delivery:init` in every project** (the CLAUDE.md section changed; consider `language: English` in `delivery.json`).

### delivery — speed and token economy
- **Model and effort per agent:** new orchestrator table — `solution-architect`, `senior-developer`, `code-reviewer` run on `sonnet`/`medium` for size S without `schema`/`config`/`api`/`security` flags (SA also M), and for fix rounds / fix-checking review rounds; escalation to the default model when a light run hits a design doubt or a BLOCKER/Critical.
- **Fast track skips the separate test plan:** QA designs the cases (one per AC + reproduction + ≤ 2 regression) in `06-qa.md` at execution; developer and CR take edge cases from the ACs.
- **Atlassian MCP only for the BA** (and the orchestrator): removed from SA, developer, CR and QA tools; they ask the BA for documents. Fewer tool schemas per run and no re-reading of Jira.
- **Fix rounds read less:** briefs list only remark/defect IDs and the agent's previous file. CR: diff `--stat` first, per-file diff without lock/generated files, round N>1 only the delta since the reviewed commit (`Reviewed:` line in `05-review.md`); phpcs/phpstan/phpunit on changed files/modules only. CR reads only relevant memory entries.
- **QA browser economy:** one `browser_snapshot` per page, targeted `browser_find`/`browser_evaluate` checks, screenshots read only for visual cases and saved under `var/agents/<KEY>/screens/`.
- **Language:** handoff prose defaults to English (init recommends it); the orchestrator talks to the user in the user's language.
- **`CLAUDE.md` section trimmed** (≈ 1650 → ≈ 1150 words, loaded into every agent run): Git, access requests, manual actions, handoff files and memory condensed; orchestrator-only rules (model choice, timing, parallel issues, code lock) live in `deliver`.

### magento2 (1.2.0)
- Playwright MCP started with `--snapshot-mode none`, `--image-responses omit`, `--console-level error` (actions no longer return full page snapshots; screenshots go to files).
- `verify-change`: one snapshot per page, targeted element checks, network only on failures, screenshots read only for visual cases.

## 1.3.0 — 2026-11-10

Upgrade: `/plugin marketplace update daniel-marketplace`, `/plugin update delivery`, `/reload-plugins` (new hooks), then **`/delivery:init` in every project** (the CLAUDE.md section changed). Run each issue in its own Claude Code session.

### delivery — parallel issues
- **Several sessions, different issues at once:** new `hooks/bind-session.sh` (PostToolUse Write/Edit) binds the orchestrator's session to its issue in `var/agents/.sessions/<session_id>`; `subagent-start.sh` and `validate-handoff.sh` resolve the issue per session (`session_id` of the hook input) instead of the shared `.current` (legacy fallback only before any binding exists). Unbound pipeline-agent starts are logged to `var/agents/.unbound.log`.
- **Code lock:** new `hooks/pipeline-guard.sh` (PreToolUse Write/Edit/Agent) — only one issue at a time in `implementation`/`review`/`qa`; `state.json` must be written with Write; dev/CR/QA-exec calls require the issue's code stage. New stage `paused` (+ `resumeStage`) parks an issue with the user's approval.
- Orchestrator: "Parallel issues" and "Code lock" rules, writes `.current`/`state.json` only with Write, resume of paused issues. Developer: clean working tree before switching branches, never stash/discard another issue's changes. QA: branch check before testing. `/delivery:status`: lists all issues, the lock holder, session bindings and unbound starts.
- Tests: session binding and code lock cases in `tests/hooks.sh`.

## 1.2.0 — 2026-11-09

Upgrade: `/plugin marketplace update daniel-marketplace`, `/plugin update delivery`, then **`/delivery:init` in every project** (the CLAUDE.md section changed).

### delivery — faster pipeline for small issues
- **Fast track for every size S issue** (bug or small tweak), not only bugs: condition is "no risk flag" instead of "Bug + root cause evident". BA locates the change in code and lists risk flags for every issue; the developer makes the small design choice on the fast track (named in one line, reviewed by CR) and reports `fast track invalid` beyond the limits.
- **Solution Architect scaled to the issue:** the orchestrator passes `model: sonnet`, `effort: medium` for S/M without `schema`/`config`/`api`/`security` flags (default opus/high otherwise); tool-call budget in the brief (S 15, M 30); the architect starts from the BA's code location, reads only relevant memory entries, checks environment/EAV facts only when they matter, marks untouched criteria `n/a` without investigating; `maxTurns` 60 → 40.
- **Parallel architecture + test plan** for size M; the plan is reconciled with the architecture afterwards (mismatch → QA round 2).
- `state.json` gets `risk` (fixed flag names).
- **Timing:** `validate-handoff.sh` appends each agent stop to `var/agents/<KEY>/timings.log`; the retrospective reports stage durations and the slowest stage.
- Tests: timing log cases in `tests/hooks.sh`.

## 1.1.0 — 2026-11-04

Upgrade: `/plugin marketplace update daniel-marketplace`, `/plugin update` for each plugin, then **`/delivery:init` in every project** (the CLAUDE.md section, permissions and retired rules changed). Projects initialized with 1.0.x keep working until then: the hook accepts Polish headings, and the QA mode falls back to file mtime when there is no `state.json`.

### delivery
- **Project-agnostic:** environments `custom` (any docker compose / docker-magento / VM setup: `exec` + `db` from delivery.json) and `native` (PHP on the host); edition (`adobe-commerce` / `open-source` / `mage-os`), `msi` and `multiStore` rendered into the stack section instead of the hardcoded "Adobe Commerce, MSI, multi-store"; `extraDeny`; agents and rules mention MSI / multi-store / edition only as far as the project has them.
- sql-guard recognizes `n98-magerun2 db:query|db:console` and the project's own `db` command.
- Tests: `plugins/delivery/tests/render.sh`, `plugins/magento2/tests/detect.sh`.
- **Security:** allow rule `Bash(<EXEC> tail *)` (could read `app/etc/env.php` without a prompt) narrowed to `tail * var/log/*`; the old rule is retired by init.
- **Security:** push guard in the PreToolUse hook blocks pushes to `master`/`main` through refspecs (`HEAD:master`, `x:refs/heads/main`, `--delete master`, push without refspec from `master`), `--force*`, `+refspec`, `--mirror`, `--all`, `--prune`. Active only in projects with `.claude/delivery.json`. Extra deny rules for the same.
- **Security:** sql-guard also blocks SQL read from files (`< file.sql`, `source`) and DB access from inline PHP (`php -r` with PDO/mysqli).
- Guards merged into one dispatcher `hooks/pre-bash.sh` (one process per Bash call, fast path without jq).
- Handoff gate: rejects a file not updated during the agent's run (`SubagentStart` writes a start marker), files over 2× the size guideline, reads the QA mode from `state.json`, accepts English and Polish headings.
- Orchestrator moved from `commands/` to `skills/deliver/`; keeps `var/agents/<KEY>/state.json`, resumes interrupted issues, empties `.current` before BA mode A, never `cd`s, uses a fixed delegation brief, handles `DIAGNOSTIC PROPOSAL`, checks for misplaced agent memory before cleanup, opens PRs according to the detected repository host.
- New skills: `/delivery:status` (read-only pipeline state), `/delivery:apply-retro` (turns `_retro.md` points into plugin changes).
- Templates: CLAUDE.md section wrapped in `<!-- delivery:begin/end -->`; init migrates sections from 1.0.x (`legacy-headings.txt`) instead of appending a second one. New `delivery.json` keys: `language`, `vcsHost`, `vcsRepo`, `envWorkarounds`, `extraAllow`.
- Agents (from pipeline retrospectives): BA proposes read-only diagnostics instead of blocking on data a system can provide; SA verifies environment facts (indexer mode, config) and EAV scope, memory location fixed to `<project>/.claude/agent-memory-local/`; CR runs the tools itself using the project's workarounds; QA plans attribute cases per store view.
- Tests: `plugins/delivery/tests/hooks.sh`.

### magento2
- `magento2-detect` prints `VCS_HOST` / `VCS_REPO` (credentials in the remote URL are stripped), `EDITION`, `MSI`, `custom`/`native` candidates; PHP constraint falls back to `composer.lock` `platform.php`.
- `coding-rules`: DI areas and array-argument merging, config scope, EAV per store view, GraphQL (batch resolvers, cache identities, Store header), MSI APIs when MSI is enabled (CatalogInventory otherwise), queues/cron, secrets/ACL, tests; cross-module rule relaxed to "API when it exists".
- `module-readme`: sections only when they apply; updates existing READMEs instead of regenerating.
- `verify-change`: EAV row in the method table.

### workflow
- **Atlassian MCP shipped with the plugin** (`.mcp.json`, `https://mcp.atlassian.com/v2/mcp`, same server as the official `atlassian` plugin). Agents and permissions use only `mcp__plugin_workflow_atlassian__*`; the project server `atlassian`, the claude.ai connector and the external `atlassian` plugin are no longer referenced (their old allow wildcards are retired by init). Read tools are allow-listed explicitly instead of a wildcard, so a new write tool on the server always prompts.
- `jira-tasks`: follow the Jira project's existing title convention before the default `[Type]` rule.
- `git-conventions`: where the PR is created per host; PR title rule.

## 1.0.0
- Initial version.
