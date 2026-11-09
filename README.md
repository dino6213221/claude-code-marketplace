# Claude Code Marketplace

Personal Claude Code plugin marketplace.

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
| `magento2` | Playwright MCP | `.mcp.json`, pinned `@playwright/mcp@0.0.83 --ignore-https-errors`; tools `mcp__plugin_magento2_playwright__*` |
| `workflow` | Atlassian MCP | `.mcp.json`, Atlassian Remote MCP `https://mcp.atlassian.com/v2/mcp` (OAuth on first use via `/mcp`); tools `mcp__plugin_workflow_atlassian__*` — the only Atlassian source the pipeline uses |
| `workflow` | `/workflow:git-conventions` | Branch naming, commit message and PR description conventions |
| `workflow` | `/workflow:jira-tasks` | Jira task templates (Story / Bug), title format and field guidance |
| `delivery` | `/delivery:deliver [KEY]` | Orchestrator: BA → SA → QA plan → Dev → CR → QA, with handoff files and `state.json` in `var/agents/<KEY>/`; resumes an interrupted issue |
| `delivery` | `/delivery:status [KEY]` | Read-only: stage, round, statuses of the handoff files, next step |
| `delivery` | `/delivery:apply-retro [source dir]` | Turns open points of `var/agents/_retro.md` into plugin changes (with approval), bumps versions, marks points applied |
| `delivery` | `/delivery:init` | Detects Magento root, local env (Warden / Reward / DDEV / custom / native), edition, MSI, store setup, frontend (Hyvä / Luma / PWA) and repository host, saves `.claude/delivery.json`, merges generated permissions into `.claude/settings.json`, the marked agent context section into `CLAUDE.md` (migrates 1.0.x sections), `.gitignore` entries |
| `delivery` | agents `delivery:*` | `business-analyst`, `solution-architect`, `qa`, `senior-developer`, `code-reviewer` |

## delivery — how the pieces fit

| Piece | Location | Notes |
|-------|----------|-------|
| Agents | `plugins/delivery/agents/` | Preloaded skills (verified to load with plugin prefix): BA `workflow:jira-tasks`; SA `magento2:coding-rules`; Dev `magento2:coding-rules`, `workflow:git-conventions` (+ `magento2:module-readme` on demand); CR `magento2:coding-rules`, `workflow:git-conventions`; QA `magento2:verify-change` |
| Project config | `.claude/delivery.json` (written by init) | `magentoRoot`, `env` (`warden`\|`reward`\|`ddev`\|`custom`\|`native`), `exec` + `db` + `envName` (custom), `baseUrl`, `mailUrl`, `edition`, `msi`, `multiStore`, `frontend`, `php`, `language` (handoff prose; headings stay English), `vcsHost`, `vcsRepo`, `envWorkarounds` (lines for CLAUDE.md, `{{EXEC}}` allowed), `extraAllow` / `extraDeny` (extra permission rules); only `magentoRoot` and `env` are required; handoff dir = `<magentoRoot>/var/agents/` |
| Pipeline state | `var/agents/<KEY>/state.json` (orchestrator only) | `stage`, `round`, `track`, `size`, `risk`, `qaMode` — read by the hooks and `/delivery:status` |
| Generators | `magento2-detect` (from `magento2`), `scripts/render.sh` | Detection and rendering of `templates/settings.json`, `templates/CLAUDE.md`, `templates/retired-rules.json` (`{{EXEC}}` etc.); fails on an unreplaced placeholder |
| Start marker | `hooks/subagent-start.sh` (SubagentStart) | Writes `var/agents/<KEY>/.start-<agent>` so the gate can tell a fresh file from one left over from an earlier round |
| Handoff gate | `hooks/validate-handoff.sh` (SubagentStop) | Rejects a handoff file with wrong status, missing sections (English or 1.0.x Polish headings), unchecked criteria on a positive status, not updated in this run, or longer than 2× the size guideline. Second attempt passes — the orchestrator decides. Appends every stop (agent, file, round, seconds, ok/rejected) to `var/agents/<KEY>/timings.log` for the retrospective |
| Bash guards | `hooks/pre-bash.sh` (PreToolUse Bash, shared helpers in `hooks/lib.sh`) | **git-guard** — every `git`/`gh` blocked for `delivery:business-analyst` and `delivery:solution-architect`. **sql-guard** — `delivery:qa` only: DROP/TRUNCATE/ALTER, DELETE/UPDATE without WHERE, SQL writes not targeting `QA-` records, SQL from files, DB access from inline PHP. **push-guard** — every session in an initialized project: push to `master`/`main` via any refspec, force, `+refspec`, `--mirror`, `--all`, `--prune`. Defense in depth on top of the settings rules, not a sandbox |
| Playwright MCP | provided by `magento2` | used by `delivery:qa` via `mcp__plugin_magento2_playwright__*` |
| Project settings | `templates/` | Rendered and merged by `/delivery:init` (plugins cannot ship project permissions or CLAUDE.md) |

### Size, fast track, brevity

- BA assigns size S / M / L; every agent scales its handoff file to it (guideline: S ≤ 30 lines, M ≤ 80).
- BA also locates the change in code and lists risk flags (unconfirmed location, schema, config, API, more than one module, around plugin/preference, security-sensitive area, open questions).
- Fast track: size S (bug or small tweak) + no risk flag → BA proposes, user confirms at the analysis checkpoint, Solution Architect is skipped; the developer makes the small design choice. Developer reports `fast track invalid` if the change turns out bigger → standard track.
- Standard track: the orchestrator runs the Solution Architect on `sonnet`/`medium` for S/M without schema/config/API/security flags, `opus`/`high` otherwise; the architect starts from the BA's code location and has a tool-call budget (S 15, M 30). Size M: architecture and test plan run in parallel, the plan is reconciled with the architecture afterwards.
- Retrospective reports stage durations from `timings.log`.
- Sections that don't apply are omitted; non-applicable criteria are `[x] n/a`. QA tests only what the change can break (size S: typically 2–5 cases).

### Git, access requests, manual actions

- Commit (developer), push and PR (orchestrator at closing) only with the user's approval (`ask` rules) and per `workflow:git-conventions`. Force push and push to `master`/`main` are denied. PR: `gh pr create` on GitHub; other hosts get the compare link + ready title/description.
- Agents request missing access (MCP, server, tool) as `ACCESS REQUEST` in "Open questions"; the orchestrator relays it to the user.
- Every manual/server action (bin/magento commands, scripts, admin config…) is listed as numbered exact commands in "Deployment steps" and shown at the top of the final report.
- `templates/retired-rules.json` lets `/delivery:init` remove rules from older template versions (e.g. the old `deny: Bash(git push *)`).

### Limitations of plugin agents

Claude Code ignores `permissionMode`, `hooks` and `mcpServers` in plugin agent frontmatter. Consequently:

- agents inherit the main session's permission mode and the project's `.claude/settings.json` rules (no per-agent `dontAsk` / `acceptEdits`),
- the QA hook is defined at plugin level (`delivery`) and the Playwright server comes from `magento2`, instead of both living in `qa.md`.

Self-contained: the pipeline uses only plugins and MCP servers from this marketplace (no external plugins required).

Requirements: `jq` (`brew install jq`) for hooks and init; Node.js (`npx`) for Playwright MCP; an Atlassian account for the Atlassian MCP (OAuth).

Agent memory (`memory: local`) lands in `<project>/.claude/agent-memory-local/delivery-<agent>/` — only while the session's working directory is the project directory (the orchestrator never `cd`s; init and closing check for memory misplaced under `var/agents/`).
