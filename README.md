# Claude Code Marketplace

Claude Code plugin marketplace (local) for Magento 2 / Adobe Commerce / Mage-OS projects. Nothing in the plugins is tied to one project: everything project-specific (environment, command prefixes, edition, MSI, stores, frontend, repository host, workarounds) lives in the project's `.claude/delivery.json` and the `CLAUDE.md` section generated from it.

## Installation

```
/plugin marketplace add https://github.com/dino6213221/claude-code-marketplace
/plugin install magento2@daniel-marketplace
/plugin install workflow@daniel-marketplace
/plugin install delivery@daniel-marketplace
```

`delivery` depends on `magento2` and `workflow` (installed automatically as dependencies).

Once per project, before the first pipeline run — and again after every plugin update (see `CHANGELOG.md`):

```
/delivery:init
```

Tests (require `jq`): `bash plugins/delivery/tests/hooks.sh` (guards and handoff gate), `bash plugins/magento2/tests/detect.sh` (project layouts, editions, MSI, credentials never printed), `bash plugins/delivery/tests/render.sh` (generated settings/CLAUDE.md for warden, reward, ddev, custom, native; editions; MSI on/off; single/multi-store). Manifest check: `claude plugin validate .`

## Plugins

| Plugin | Component | Description |
|--------|-----------|-------------|
| `magento2` | `/magento2:coding-rules` | Magento 2 / Adobe Commerce coding rules (SOLID, DI, plugins, service contracts, escaping, FPC, performance) |
| `magento2` | `/magento2:module-readme` | Generates a complete README.md for a Magento 2 module |
| `magento2` | `/magento2:verify-change [scope]` | Verifies a change on the local env: picks browser (Playwright) vs API / CLI / DB per case, runs it, reports evidence. Standalone or as `delivery:qa`'s preloaded skill |
| `magento2` | `magento2-detect` (bin) | Detects Magento root, env (Warden / Reward / DDEV; docker compose → `custom`; PHP on the host → `native`), URLs, frontend, PHP, edition, MSI, repository host (`VCS_HOST`/`VCS_REPO`, credentials stripped); on PATH while the plugin is enabled |
| external | Playwright MCP | Official plugin `playwright@claude-plugins-official` (`/plugin install playwright@claude-plugins-official`; runs `@playwright/mcp@latest`); tools `mcp__plugin_playwright_playwright__*`. Options (ignore HTTPS errors, snapshot mode `none`, image responses `omit`, console level `error`) come from `.claude/playwright-mcp.json`, written by `/delivery:init` and loaded through `env.PLAYWRIGHT_MCP_CONFIG` in `.claude/settings.json` |
| external | Atlassian MCP | Official plugin `atlassian@claude-plugins-official` (`/plugin install atlassian@claude-plugins-official`, OAuth on first use via `/mcp`); tools `mcp__plugin_atlassian_atlassian__*` — the only Atlassian source the pipeline uses. This marketplace ships no Atlassian server of its own (a second server with the same URL is dropped by Claude Code, which left the pipeline without Jira tools) |
| `workflow` | `/workflow:git-conventions` | Branch naming, commit message and PR description conventions |
| `workflow` | `/workflow:jira-tasks` | Jira task templates (Story / Bug), title format and field guidance |
| `workflow` | `/workflow:jira-comments` | Short Jira comments in a human tone: first line = the ask or the fact, ≤ 600 characters, no implementation terms; types questions / scope confirmation / split proposal / delivery note |
| `delivery` | `/delivery:deliver [KEY]` | Orchestrator: BA → SA → QA plan → Dev → CR → QA, with handoff files and `state.json` in `var/agents/<KEY>/`; resumes an interrupted issue |
| `delivery` | `/delivery:status [KEY]` | Read-only: stage, round, statuses of the handoff files, next step |
| `delivery` | `/delivery:apply-retro [source dir]` | Turns open points of `var/agents/_retro.md` into plugin changes (with approval), bumps versions, marks points applied |
| `delivery` | `/delivery:init` | Detects Magento root, local env (Warden / Reward / DDEV / custom / native), edition, MSI, store setup, frontend (Hyvä / Luma / PWA) and repository host, saves `.claude/delivery.json`, merges generated permissions into `.claude/settings.json`, the marked agent context section into `CLAUDE.md` (migrates 1.0.x sections), `.gitignore` entries |
| `delivery` | agents `delivery:*` | `business-analyst`, `solution-architect`, `qa-planner` (test plan), `senior-developer`, `code-reviewer`, `qa` (test execution) |

## delivery — how the pieces fit

| Piece | Location | Notes |
|-------|----------|-------|
| Agents | `plugins/delivery/agents/` | Preloaded skills (verified to load with plugin prefix): BA `workflow:jira-tasks`, `workflow:jira-comments`; SA `magento2:coding-rules`; Dev `magento2:coding-rules`, `workflow:git-conventions` (+ `magento2:module-readme` on demand); CR `magento2:coding-rules`, `workflow:git-conventions`; `qa` `magento2:verify-change`; `qa-planner` none (Read/Write/Glob/Grep only — no browser, no Bash). BA has only the Atlassian read tools it uses (9 instead of the whole server). Every agent ends with a fixed short "Final message" for the orchestrator |
| Project config | `.claude/delivery.json` (written by init) | `magentoRoot`, `env` (`warden`\|`reward`\|`ddev`\|`custom`\|`native`), `exec` + `db` + `envName` (custom), `baseUrl`, `mailUrl`, `frontendUrl` (storefront UI for tests when a headless/PWA storefront runs on its own URL), `edition`, `msi`, `multiStore`, `frontend`, `php`, `language` (handoff prose; headings stay English), `vcsHost`, `vcsRepo`, `envWorkarounds` (lines for CLAUDE.md, `{{EXEC}}` allowed), `extraAllow` / `extraDeny` (extra permission rules); only `magentoRoot` and `env` are required; handoff dir = `<magentoRoot>/var/agents/` |
| Pipeline state | `var/agents/<KEY>/state.json` (orchestrator only) | `stage` (incl. `paused` + `resumeStage`), `round`, `track`, `size`, `risk` — read by the hooks and `/delivery:status` |
| Generators | `magento2-detect` (from `magento2`), `scripts/render.sh` | Detection and rendering of `templates/settings.json`, `templates/CLAUDE.md`, `templates/retired-rules.json` (`{{EXEC}}` etc.); fails on an unreplaced placeholder |
| Session binding | `hooks/bind-session.sh` (PostToolUse Write/Edit) | Binds the orchestrator's session to its issue (`var/agents/.sessions/<session_id>`) when it writes `.current` or `state.json`; all hooks resolve the issue per session, so several sessions can run pipelines for different issues |
| Code lock | `hooks/pipeline-guard.sh` (PreToolUse Write/Edit/Agent) | Only one issue at a time in `implementation`/`review`/`qa` (shared checkout and environment): atomic `var/agents/.code-lock` (mkdir) taken when `state.json` enters a code stage and released when it leaves; invalid `state.json` JSON and Edit of `state.json` blocked; pipeline agents (except BA) blocked in a session not bound to an issue; pipeline agents blocked while the session is in plan mode (subagents inherit it and cannot write handoff files); dev/CR/`qa` calls blocked before the issue's code stage is recorded. `stage: paused` parks an issue (user's approval) |
| git pre-push | `templates/pre-push`, installed by `/delivery:init` into the clone's hooks path | Authoritative: rejects pushes to `master`/`main` and non-fast-forward (force) pushes on the resolved refs — no quoting/alias/subshell bypass. Chains an existing hook kept as `pre-push.local` |
| Statistics | `hooks/collect-stats.sh` (SubagentStop), `scripts/transcript-stats.jq`, `scripts/stats.sh`, `/delivery:stats` | Per agent run from its transcript: wall time, turns, model, tokens (input, cache write, cache read, output), time and result size per tool, 5 slowest calls (Bash labeled by program/subcommand only) → `var/agents/<KEY>/stats/`. Report per run/agent/tool + orchestrator; `--archive` at closing → `var/agents/_stats.jsonl`; `/delivery:stats all` compares issues by agent and size |
| Gate summary | `scripts/gate.sh <KEY> [file]` | Status, unmet criteria, size against the guideline and "Open questions" per handoff file, plus gate rejections — the orchestrator and `/delivery:status` run it instead of reading the files |
| Start marker | `hooks/subagent-start.sh` (SubagentStart) | Writes `var/agents/<KEY>/.start-<agent>` so the gate can tell a fresh file from one left over from an earlier round |
| Handoff gate | `hooks/validate-handoff.sh` (SubagentStop) | Rejects a handoff file with wrong status, missing sections (English or 1.0.x Polish headings), unchecked criteria on a positive status, not updated in this run, or over 2× the size guideline in lines or bytes (S 60 lines / 8 KB, M 160 lines / 20 KB). `qa-planner` → `03-test-plan.md`, `qa` → `06-qa.md`. Second attempt passes — the orchestrator decides. Appends every stop (agent, file, round, seconds, ok/rejected) to `var/agents/<KEY>/timings.log` for the retrospective |
| Bash guards | `hooks/pre-bash.sh` (PreToolUse Bash, shared helpers in `hooks/lib.sh`) | **git-guard** — every `git`/`gh` blocked for `delivery:business-analyst` and `delivery:solution-architect`. **sql-guard** — `delivery:qa` only: DROP/TRUNCATE/ALTER, DELETE/UPDATE without WHERE, SQL writes not targeting `QA-` records, SQL from files, DB access from inline PHP. **push-guard** — every session in an initialized project: push to `master`/`main` via any refspec, force (also bundled `-uf`), `+refspec`, `--mirror`, `--all`, `--prune`, `--no-verify`, `git -c alias.*/push.*`, substitutions; quotes/subshells normalized; only the real `push` subcommand is inspected. Defense in depth on top of the settings rules and the pre-push hook, not a sandbox |
| Playwright MCP | official `playwright` plugin + `templates/playwright-mcp.json` | used by `delivery:qa` via `mcp__plugin_playwright_playwright__*` |
| Project settings | `templates/` | Rendered and merged by `/delivery:init` (plugins cannot ship project permissions or CLAUDE.md) |

### Size, fast track, brevity

- BA assigns size S / M / L; every agent scales its handoff file to it (guideline: S ≤ 30 lines / 4 KB, M ≤ 80 lines / 10 KB).
- BA also locates the change in code and lists risk flags (unconfirmed location, schema, config, API, more than one module, around plugin/preference, security-sensitive area, open questions).
- Fast track: size S (bug or small tweak) + no risk flag → BA proposes, user confirms at the analysis checkpoint, Solution Architect is skipped; the developer makes the small design choice. Developer reports `fast track invalid` if the change turns out bigger → standard track.
- Standard track: the orchestrator runs the Solution Architect on `sonnet`/`medium` for S/M without schema/config/API/security flags, `opus`/`high` otherwise (the architect's own default effort is `medium`); the architect starts from the BA's code location and has a tool-call budget (S 15, M 30). Size M: architecture and test plan run in parallel, the plan is reconciled with the architecture afterwards.
- Retrospective reports stage durations from `timings.log`.
- Sections that don't apply are omitted; non-applicable criteria are `[x] n/a`. QA tests only what the change can break (size S: typically 2–5 cases).

### Speed and token economy

- Model and effort per agent chosen by the orchestrator (`deliver` → "Model and effort per agent"): `sonnet`/`medium` for SA, developer and CR on light issues (size S, no `schema`/`config`/`api`/`security` flag) and fix-checking rounds; escalation to the default when a light run hits a design doubt or a BLOCKER.
- Fast track skips both the architecture and the separate test plan (QA designs the cases at execution).
- Atlassian MCP only for the BA (and the orchestrator); other agents work from `01-analysis.md` and ask the BA.
- Fix rounds read only the remark/defect IDs and the agent's previous file; CR reads the diff per file (`--stat` first), round N>1 only the delta since the reviewed commit; tools run on changed files only.
- Playwright MCP is configured (`.claude/playwright-mcp.json`) with snapshot mode `none`, image responses `omit`, console level `error`; QA checks targeted elements (`browser_find`/`browser_evaluate`) instead of re-reading page snapshots.
- Orchestrator context: it does not read handoff files or explore code — it works from each agent's short final message and `scripts/gate.sh`; lists issues with one JQL call (no subagent); suggests a fresh session after the architecture checkpoint and before QA.
- Fresh agent instead of resuming: SendMessage only for an immediate follow-up (< ~5 min, the subagent cache lifetime); every fix round or re-run after a wait is a new agent with a narrow brief.
- Turn economy in every agent: parallel reads, chained commands, one script for repeated cases, output trimmed to what is needed — the number of turns × context size is the main cost.
- QA retest after fixes is `targeted` by default (failed cases, cases touched by the changed files, one positive case per AC); `full` after a Critical/BLOCKER or a fix in more than 3 files or shared code.
- Generated settings allow `curl -sk` against `baseUrl` / `frontendUrl` (no prompt per API check). Database reads still ask.
- Handoff prose defaults to English (`language` in `delivery.json`); the orchestrator talks to the user in the user's language.
- `CLAUDE.md` section trimmed to rules every agent needs (loaded into every agent run).

### Parallel issues

- Run `/delivery:deliver <KEY>` in separate Claude Code sessions (one per issue). Analysis, architecture and test plans run in parallel; implementation, review and QA run for one issue at a time — the next issue waits at the lock (or the user parks the holder).
- Full parallel implementation would need a separate checkout and environment per issue — not supported (the local environment serves one checkout).

### Git, access requests, manual actions

- Commit (developer), push and PR (orchestrator at closing) only with the user's approval (`ask` rules) and per `workflow:git-conventions`. Force push and push to `master`/`main` are denied. PR: `gh pr create` on GitHub; other hosts get the compare link + ready title/description.
- Agents request missing access (MCP, server, tool) as `ACCESS REQUEST` in "Open questions"; the orchestrator relays it to the user.
- Every manual/server action (bin/magento commands, scripts, admin config…) is listed as numbered exact commands in "Deployment steps" and shown at the top of the final report.
- `templates/retired-rules.json` lets `/delivery:init` remove rules from older template versions (e.g. the old `deny: Bash(git push *)`).

### Limitations of plugin agents

Claude Code ignores `permissionMode`, `hooks` and `mcpServers` in plugin agent frontmatter. Consequently:

- agents inherit the main session's permission mode and the project's `.claude/settings.json` rules (no per-agent `dontAsk` / `acceptEdits`),
- the QA hook is defined at plugin level (`delivery`) and the Playwright server comes from the official `playwright` plugin, instead of both living in `qa.md`.

External dependencies: the official plugins `atlassian` (Jira/Confluence) and `playwright` (browser QA) from `claude-plugins-official` — official plugins are used instead of servers shipped here (a second server with the same definition is dropped by Claude Code). This marketplace ships skills, agents, hooks and templates only — no MCP servers.

Requirements: `jq` (`brew install jq`) for hooks and init; Node.js (`npx`) for Playwright MCP; the official `atlassian` and `playwright` plugins; an Atlassian account (OAuth).

Agent memory (`memory: local`) lands in `<project>/.claude/agent-memory-local/delivery-<agent>/` — only while the session's working directory is the project directory (the orchestrator never `cd`s; init and closing check for memory misplaced under `var/agents/`).
