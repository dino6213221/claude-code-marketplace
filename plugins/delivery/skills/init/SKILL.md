---
name: init
description: Prepare the current project for the delivery agent pipeline — detect Magento root, local environment (Warden / Reward / DDEV) and frontend, save them in .claude/delivery.json, then merge generated permissions into .claude/settings.json, the agent context into CLAUDE.md and entries into .gitignore. Run once per project (and again after the environment changes) before /delivery:deliver.
disable-model-invocation: true
---
You prepare the current project for the `/delivery:deliver` pipeline. A plugin cannot install project settings by itself, so you generate them from the plugin's templates for the detected environment.

Tools and files:
- `magento2-detect` — command from the `magento2` plugin (on PATH because `delivery` depends on it); detects the project layout and prints `KEY=VALUE`
- `${CLAUDE_PLUGIN_ROOT}/scripts/render.sh` — generates `settings.json` and the `CLAUDE.md` section from `.claude/delivery.json`
- `${CLAUDE_PLUGIN_ROOT}/templates/gitignore-snippet` — `.gitignore` entries
- `${CLAUDE_PLUGIN_ROOT}/templates/retired-rules.json` — rules from earlier template versions to remove

## Rules
- Never overwrite anything wholesale. Read every target file first, then show the user the planned change (diff) and wait for approval, separately for each file.
- Do not remove existing rules, entries or sections (exception: replacing your own previously generated section in `CLAUDE.md` — see step 6).
- Do not read `app/etc/env.php`, `auth.json` or secret values from `.env`. Do not commit.
- Keep working files in the session's temporary directory, not in the repo.

## Steps
1. **Project directory**: `$CLAUDE_PROJECT_DIR` (or the session's working directory). Confirm it with the user.
2. **Detection**: `magento2-detect "<project directory>"`. Command not found → the `magento2` plugin is disabled; ask for `/plugin install magento2@daniel-marketplace`.
   Show the result as a table and collect missing or ambiguous values:
   - `MAGENTO_ROOT` empty → ask (directory containing `bin/magento`, relative to the project),
   - `ENV_CANDIDATES` lists several tools or `ENV_TOOL` is empty → ask which environment is used (`warden` | `reward` | `ddev`),
   - `FRONTEND` empty or uncertain → ask (`hyva`, `luma`, `pwa`; several allowed),
   - `BASE_URL`, `MAIL_URL`, `PHP_CONSTRAINT` empty → propose a value or leave it empty (agents will ask when needed).
3. **Configuration**: write `.claude/delivery.json` (show it before writing):
   ```json
   {
     "magentoRoot": "app/magento",
     "env": "warden",
     "baseUrl": "https://app.example.test/",
     "mailUrl": "https://webmail.example.test/",
     "frontend": ["hyva"],
     "php": ">=8.1"
   }
   ```
   The file contains no secrets — it may be committed if the team uses the same environment. If it already exists, show the differences and ask which values to change.
4. **Generation**: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/render.sh" "<project>/.claude/delivery.json" "<temporary directory>"`.
5. **`.claude/settings.json`**:
   - no file → create it from the generated one,
   - file exists → merge: `env` (keys only when missing), `permissions.allow|deny|ask` (union without duplicates), `permissions.defaultMode` only when missing. Other project keys unchanged. You may use `jq -s`.
   - Retired rules: every rule from `retired-rules.json` found in the same list of the project's settings (e.g. an old `deny: Bash(git push *)` that would now block the approved push) → show them and, with approval, remove them.
   - Conflict (the same rule in `allow` and `deny`, or rules of the previous environment after an `env` change) → show it and ask.
6. **`CLAUDE.md`** in the project directory:
   - the section starts with the heading `# Project context (shared by all agents)`;
   - no section → append the generated one at the end of the file (or create the file),
   - section exists (previous init) → show the diff and, with approval, replace it entirely, up to the next first-level `# ` heading or the end of the file.
7. **`.gitignore`**: append missing lines from `gitignore-snippet`. Check that the handoff directory is ignored: `git check-ignore -q "<magentoRoot>/var/agents/x"`; if not — append `<magentoRoot>/var/agents/`.
8. **Environment check** (if the containers are running; if not — skip and report):
   - `<EXEC> php -v` and `<EXEC> ls bin/magento` — confirms the command prefix and the container's working directory; error → show it and ask for the correct prefix,
   - `HAS_JQ=no` → pipeline hooks do not fully work (`brew install jq`),
   - `HAS_NPX=no` → the Playwright server from the `magento2` plugin (browser QA) will not start; Node.js is required.
9. **Summary**: what changed in each file, what was skipped and why. Remind the user to run `/reload-plugins` or restart the session so the permissions and `CLAUDE.md` take effect.
