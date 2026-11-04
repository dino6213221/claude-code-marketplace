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

Once per project, before the first pipeline run:

```
/delivery:init
```

## Plugins

| Plugin | Component | Description |
|--------|-----------|-------------|
| `magento2` | `/magento2:coding-rules` | Magento 2 / Adobe Commerce coding rules (SOLID, DI, plugins, service contracts, escaping, FPC, performance) |
| `magento2` | `/magento2:module-readme` | Generates a complete README.md for a Magento 2 module |
| `magento2` | `/magento2:verify-change [scope]` | Verifies a change on the local env: picks browser (Playwright) vs API / CLI / DB per case, runs it, reports evidence. Standalone or as `delivery:qa`'s preloaded skill |
| `magento2` | `magento2-detect` (bin) | Detects Magento root, env (Warden / Reward / DDEV), URLs, frontend, PHP; on PATH while the plugin is enabled |
| `magento2` | Playwright MCP | `.mcp.json`, pinned `@playwright/mcp@0.0.83 --ignore-https-errors`; tools `mcp__plugin_magento2_playwright__*` |
| `workflow` | `/workflow:git-conventions` | Branch naming, commit message and PR description conventions |
| `workflow` | `/workflow:jira-tasks` | Jira task templates (Story / Bug), title format and field guidance |
| `delivery` | `/delivery:deliver [KEY]` | Orchestrator: BA → SA → QA plan → Dev → CR → QA, with handoff files in `var/agents/<KEY>/` |
| `delivery` | `/delivery:init` | Detects Magento root, local env (Warden / Reward / DDEV) and frontend (Hyvä / Luma / PWA), saves `.claude/delivery.json`, merges generated permissions into `.claude/settings.json`, agent context into `CLAUDE.md`, `.gitignore` entries |
| `delivery` | agents `delivery:*` | `business-analyst`, `solution-architect`, `qa`, `senior-developer`, `code-reviewer` |

## delivery — how the pieces fit

| Piece | Location | Notes |
|-------|----------|-------|
| Agents | `plugins/delivery/agents/` | Preloaded skills (verified to load with plugin prefix): BA `workflow:jira-tasks`; SA `magento2:coding-rules`; Dev `magento2:coding-rules`, `workflow:git-conventions` (+ `magento2:module-readme` on demand); CR `magento2:coding-rules`, `workflow:git-conventions`; QA `magento2:verify-change` |
| Project config | `.claude/delivery.json` (written by init) | `magentoRoot`, `env`, `baseUrl`, `mailUrl`, `frontend`, `php`; handoff dir = `<magentoRoot>/var/agents/` |
| Generators | `magento2-detect` (from `magento2`), `scripts/render.sh` | Detection and rendering of `templates/settings.json` / `templates/CLAUDE.md` (`{{EXEC}}` etc.) |
| Handoff gate | `hooks/validate-handoff.sh` (SubagentStop) | Rejects a handoff file with wrong status, missing sections or unchecked criteria on a positive status |
| SQL guard | `hooks/sql-guard.sh` (PreToolUse Bash) | Active only for `delivery:qa`; blocks DROP/TRUNCATE/ALTER, DELETE/UPDATE without WHERE, SQL writes not targeting `QA-` records |
| Playwright MCP | provided by `magento2` | used by `delivery:qa` via `mcp__plugin_magento2_playwright__*` |
| Project settings | `templates/` | Rendered and merged by `/delivery:init` (plugins cannot ship project permissions or CLAUDE.md) |

### Limitations of plugin agents

Claude Code ignores `permissionMode`, `hooks` and `mcpServers` in plugin agent frontmatter. Consequently:

- agents inherit the main session's permission mode and the project's `.claude/settings.json` rules (no per-agent `dontAsk` / `acceptEdits`),
- the QA hook is defined at plugin level (`delivery`) and the Playwright server comes from `magento2`, instead of both living in `qa.md`.

Requirements: `jq` (`brew install jq`) for hooks and init; Node.js (`npx`) for Playwright MCP.

Agent memory (`memory: local`) lands in `.claude/agent-memory-local/delivery-<agent>/`.
