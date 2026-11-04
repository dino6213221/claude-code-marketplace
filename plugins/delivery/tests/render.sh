#!/usr/bin/env bash
# Tests for scripts/render.sh across environment types and project shapes (no project-specific values).
# Usage: bash plugins/delivery/tests/render.sh   (requires jq)
set -u
RENDER="$(cd "$(dirname "$0")/../scripts" && pwd)/render.sh"
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
PASS=0; FAILED=0
ok()   { PASS=$((PASS+1)); }
bad()  { FAILED=$((FAILED+1)); echo "FAIL: $1"; }
run()  { # run <name> <json> → renders into $T/<name>, returns render's exit code
  echo "$2" > "$T/$1.json"; bash "$RENDER" "$T/$1.json" "$T/$1" >/dev/null 2>&1
}
has()  { grep -qF -- "$3" "$T/$1/$2" && ok || bad "$1/$2 should contain: $3"; }
hasnt(){ grep -qF -- "$3" "$T/$1/$2" && bad "$1/$2 should not contain: $3" || ok; }
allow(){ jq -e --arg r "$2" '.permissions.allow | index($r)' "$T/$1/settings.json" >/dev/null && ok || bad "$1 allow should have: $2"; }

# minimal: Warden, nothing else known
run minimal '{"magentoRoot":".","env":"warden"}' && ok || bad "minimal renders"
has minimal CLAUDE.md "warden env exec -T php-fpm bin/magento"
has minimal CLAUDE.md "Edition: not determined"
has minimal CLAUDE.md "Inventory: not determined"
has minimal CLAUDE.md "Stores: not determined"
has minimal CLAUDE.md "prose is written in English"
has minimal CLAUDE.md "Repository host: not determined"
hasnt minimal CLAUDE.md "{{"
allow minimal "Bash(warden env exec -T php-fpm tail * var/log/*)"
allow minimal "mcp__plugin_workflow_atlassian__getJiraIssue"
jq -e '[.permissions.allow[] | select(test("atlassian") and (test("^mcp__plugin_workflow_atlassian__") | not))] | length == 0' "$T/minimal/settings.json" >/dev/null && ok || bad "only workflow-plugin Atlassian rules"
jq -e '.permissions.allow | index("mcp__plugin_workflow_atlassian__*") | not' "$T/minimal/settings.json" >/dev/null && ok || bad "no Atlassian wildcard allow"
jq -e '.permissions.ask | index("mcp__plugin_workflow_atlassian__executeWrite")' "$T/minimal/settings.json" >/dev/null && ok || bad "Atlassian writes ask"
has minimal CLAUDE.md "mcp__plugin_workflow_atlassian__"

# Open Source + Luma + DDEV, single store, no MSI, GitHub
run ddev '{"magentoRoot":".","env":"ddev","edition":"open-source","msi":false,"multiStore":false,"frontend":["luma"],"vcsHost":"github","vcsRepo":"org/shop","language":"German"}' && ok || bad "ddev renders"
has ddev CLAUDE.md "ddev exec bin/magento"
has ddev CLAUDE.md "ddev mysql -e"
has ddev CLAUDE.md "Magento Open Source"
has ddev CLAUDE.md "MSI disabled"
has ddev CLAUDE.md "single store view"
has ddev CLAUDE.md "Frontend: Luma"
has ddev CLAUDE.md "gh pr create"
has ddev CLAUDE.md "prose is written in German"
hasnt ddev CLAUDE.md "multi-store"
jq -e '.permissions.deny | index("Bash(ddev delete*)")' "$T/ddev/settings.json" >/dev/null && ok || bad "ddev deny rules"

# Adobe Commerce + Hyvä + MSI + multi-store, workarounds, extra rules
run commerce '{"magentoRoot":"src","env":"reward","edition":"adobe-commerce","msi":true,"multiStore":true,"frontend":["hyva"],"envWorkarounds":["phpcs: `{{EXEC}} vendor/bin/phpcs --runtime-set installed_paths vendor/magento/magento-coding-standard`"],"extraAllow":["Bash(reward env exec -T php-fpm vendor/bin/phpcs --runtime-set *)"],"extraDeny":["Bash(reward env exec -T php-fpm bin/magento setup:install*)"]}' && ok || bad "commerce renders"
has commerce CLAUDE.md "Edition: Adobe Commerce"
has commerce CLAUDE.md "MSI enabled"
has commerce CLAUDE.md "several websites / store views"
has commerce CLAUDE.md "Frontend: Hyvä"
has commerce CLAUDE.md "reward env exec -T php-fpm vendor/bin/phpcs --runtime-set"
has commerce CLAUDE.md '`src/var/agents/<KEY>/`'
allow commerce "Bash(reward env exec -T php-fpm vendor/bin/phpcs --runtime-set *)"
jq -e '.permissions.deny | index("Bash(reward env exec -T php-fpm bin/magento setup:install*)")' "$T/commerce/settings.json" >/dev/null && ok || bad "extraDeny merged"

# custom (docker compose / docker-magento)
run custom '{"magentoRoot":".","env":"custom","envName":"docker compose","exec":"docker compose exec -T phpfpm","db":"docker compose exec -T db mysql magento"}' && ok || bad "custom renders"
has custom CLAUDE.md "docker compose exec -T phpfpm bin/magento"
has custom CLAUDE.md "Local environment: docker compose"
allow custom "Bash(docker compose exec -T phpfpm vendor/bin/phpunit *)"
run custom-missing '{"magentoRoot":".","env":"custom"}' && bad "custom without exec/db must fail" || ok

# native (PHP on the host)
run native '{"magentoRoot":".","env":"native","db":"mysql -h127.0.0.1 magento"}' && ok || bad "native renders"
has native CLAUDE.md '`bin/magento <command>`'
has native CLAUDE.md "on the host"
hasnt native CLAUDE.md '` bin/magento'
allow native "Bash(bin/magento cache:*)"
allow native "Bash(tail * var/log/*)"
grep -q '"Bash(tail \*)"' "$T/native/retired-rules.json" && ok || bad "native retired rule without prefix"
run native-subdir '{"magentoRoot":"magento","env":"native"}' && bad "native with subdirectory root must fail" || ok

run unknown '{"magentoRoot":".","env":"vagrant"}' && bad "unknown env must fail" || ok

echo "passed: $PASS, failed: $FAILED"
[ "$FAILED" -eq 0 ]
