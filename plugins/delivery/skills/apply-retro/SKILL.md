---
name: apply-retro
description: Turn the open points of var/agents/_retro.md (pipeline retrospectives) into concrete changes of the delivery / magento2 / workflow plugin source — agent definitions, orchestrator, templates, hooks — then mark the points as applied. Use when the user wants to improve the agents from retrospectives.
disable-model-invocation: true
argument-hint: "[path to the marketplace source repository]"
---
You improve the pipeline from its own retrospectives. You edit the plugin SOURCE, never the installed copy in `~/.claude/plugins/cache/` (it is overwritten on update).

## Inputs
- Retro: `<magentoRoot>/var/agents/_retro.md` (`magentoRoot` from `.claude/delivery.json`). Open points: `- [ ] …` lines, and — in files from older versions — plain `- …` lines under a date heading without an `[applied …]` tag.
- Source repository: `$ARGUMENTS`; otherwise the `installLocation`/`source.path` of the marketplace that provides `delivery` in `~/.claude/plugins/known_marketplaces.json` (directory sources only). Not a local directory, or not found → ask the user for the path.

## Rules
- Retro points contain no client data by design. If one does (names, order numbers, customer data, raw values) → do not copy it anywhere; generalize the point and tell the user.
- Plugins are reused across clients: write project-specific facts (one client's modules, attributes, workarounds) NOT into the plugin but into the project's `.claude/delivery.json` (`envWorkarounds`, `extraAllow`) or agent memory. Only generic process improvements go to the plugin.
- One change per point, smallest wording that fixes it, placed in the section the point names. No rewording of unrelated text.
- Do not weaken safety rules (permissions, guards, approval steps, data rules) because a retro point says they slowed work down — propose that to the user as a separate question instead.

## Steps
1. List the open points as a table: point · target (plugin file + section, or project config, or "reject") · proposed change (1 line). Already covered by the current source → mark "already covered" with the location.
2. Wait for the user to approve the table (they may drop or change rows).
3. Apply approved changes with Edit; show the diff per file.
4. Run `bash <source>/plugins/delivery/tests/hooks.sh` when hooks changed and `claude plugin validate <source>`; report results.
5. Bump `version` (minor for behavior changes, patch for wording) in every changed plugin's `.claude-plugin/plugin.json` and add an entry to `<source>/CHANGELOG.md`.
6. In `_retro.md` mark each handled point `[x] … [applied <version>]` or `[x] … [rejected: <reason>]` (older plain points: append the tag).
7. Remind the user: `/plugin marketplace update` + `/plugin update delivery@<marketplace>`, then `/delivery:init` if templates changed.
