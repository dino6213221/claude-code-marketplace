#!/usr/bin/env bash
# Generates settings.json, the CLAUDE.md section and retired-rules.json for a project from .claude/delivery.json.
# Usage: render.sh <delivery.json> <output directory>
# Output: <out>/settings.json, <out>/CLAUDE.md, <out>/retired-rules.json — /delivery:init merges them into the project's files.
set -euo pipefail
CFG="$1"; OUT="$2"
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$PLUGIN_ROOT/templates"
command -v jq >/dev/null || { echo "render: jq required" >&2; exit 1; }
mkdir -p "$OUT"

get() { jq -r "$1 // empty" "$CFG"; }
# booleans: `false // empty` is empty in jq, so read them separately ("true" | "false" | "")
getb() { jq -r "$1 | if . == null then \"\" else tostring end" "$CFG"; }
ENV_TOOL=$(get .env)
MAGENTO_ROOT=$(get .magentoRoot); MAGENTO_ROOT=${MAGENTO_ROOT:-.}
BASE_URL=$(get .baseUrl)
MAIL_URL=$(get .mailUrl)
PHP=$(get .php)
LANGUAGE=$(get .language); LANGUAGE=${LANGUAGE:-English}
VCS_HOST=$(get .vcsHost)
VCS_REPO=$(get .vcsRepo)

case "$ENV_TOOL" in
  warden) ENV_NAME="Warden"; EXEC="warden env exec -T php-fpm"; DB="warden db connect"
          DENY='["Bash(warden env down*)","Bash(warden db import*)","Bash(warden env rm*)"]' ;;
  reward) ENV_NAME="Reward"; EXEC="reward env exec -T php-fpm"; DB="reward db connect"
          DENY='["Bash(reward env down*)","Bash(reward db import*)","Bash(reward env rm*)"]' ;;
  ddev)   ENV_NAME="DDEV"; EXEC="ddev exec"; DB="ddev mysql"
          DENY='["Bash(ddev delete*)","Bash(ddev import-db*)","Bash(ddev snapshot restore*)"]' ;;
  custom) # any other setup (docker compose, docker-magento, Valet, VM…): prefixes come from delivery.json
          ENV_NAME=$(get .envName); ENV_NAME=${ENV_NAME:-custom}
          EXEC=$(get .exec); DB=$(get .db); DENY='[]'
          [ -n "$EXEC" ] && [ -n "$DB" ] || { echo "render: env 'custom' needs \"exec\" (command prefix running PHP in the Magento directory) and \"db\" (database client command) in delivery.json" >&2; exit 1; } ;;
  native) # PHP and the database client on the host
          ENV_NAME="native (host)"; EXEC=""; DB=$(get .db); DB=${DB:-mysql}; DENY='[]'
          [ "$MAGENTO_ROOT" = "." ] || { echo "render: env 'native' requires magentoRoot \".\" (commands run without cd); otherwise use env 'custom' with an exec prefix" >&2; exit 1; } ;;
  *) echo "render: unknown environment '$ENV_TOOL' (warden|reward|ddev|custom|native)" >&2; exit 1 ;;
esac
DENY=$(jq -c --argjson d "$DENY" '$d + (.extraDeny // [])' "$CFG")
if [ -n "$EXEC" ]; then
  EXEC_NOTE="Run all PHP/Magento commands inside the container (the container's working directory = the Magento directory):"
else
  EXEC_NOTE="Run all PHP/Magento commands on the host, from the project directory (= the Magento directory):"
fi

# Edition, inventory and store setup — stated only as far as they are known
case "$(get .edition)" in
  adobe-commerce) EDITION_LINE="- Edition: Adobe Commerce (B2B / staging / content-staging modules may be present — check \`app/etc/config.php\`)." ;;
  open-source)    EDITION_LINE="- Edition: Magento Open Source — no Adobe Commerce-only modules (staging, B2B, customer segments)." ;;
  mage-os)        EDITION_LINE="- Edition: Mage-OS (Magento Open Source fork)." ;;
  *)              EDITION_LINE="- Edition: not determined — check composer.json (\`magento/product-*-edition\`) before relying on edition-specific modules." ;;
esac
case "$(getb .msi)" in
  true)  MSI_LINE="- Inventory: MSI enabled — stock through MSI APIs (sources, salable quantity)." ;;
  false) MSI_LINE="- Inventory: MSI disabled — legacy CatalogInventory (\`cataloginventory_stock_item\`)." ;;
  *)     MSI_LINE="- Inventory: not determined — check \`Magento_Inventory\` in \`app/etc/config.php\`." ;;
esac
case "$(getb .multiStore)" in
  true)  STORE_LINE="- Stores: several websites / store views / languages — state the scope of every change; EAV attribute and configuration values can differ per store view: check the value in the store view the issue concerns, not only the default one." ;;
  false) STORE_LINE="- Stores: single store view." ;;
  *)     STORE_LINE="- Stores: not determined — check \`bin/magento store:list\`; if there are several store views, EAV and configuration values can differ per store view." ;;
esac

FRONTEND_RULES=""
for f in $(jq -r '.frontend[]? // empty' "$CFG"); do
  case "$f" in
    hyva) FRONTEND_RULES+=$'\n'"- Frontend: Hyvä (Alpine.js + Tailwind); no RequireJS/Knockout on the storefront." ;;
    luma) FRONTEND_RULES+=$'\n'"- Frontend: Luma (RequireJS, Knockout, LESS); JS initialized via \`data-mage-init\` / \`x-magento-init\`." ;;
    pwa)  FRONTEND_RULES+=$'\n'"- Frontend: PWA Studio (React, Venia/Peregrine) — the storefront talks to Magento via GraphQL; verify storefront backend changes with a GraphQL query as well." ;;
  esac
done
[ -n "$FRONTEND_RULES" ] || FRONTEND_RULES=$'\n'"- Frontend: not determined — ask the user before making frontend decisions."

# Known environment workarounds (free text from delivery.json, {{EXEC}} allowed)
WORKAROUNDS=$(jq -r '.envWorkarounds[]? | "- " + .' "$CFG")
[ -n "$WORKAROUNDS" ] || WORKAROUNDS="- none recorded (add them to \`envWorkarounds\` in \`.claude/delivery.json\` and run \`/delivery:init\` again)."

case "$VCS_HOST" in
  github)    VCS="GitHub (\`$VCS_REPO\`) — PR via \`gh pr create\`" ;;
  bitbucket) VCS="Bitbucket (\`$VCS_REPO\`) — no CLI: the orchestrator gives the user the compare link \`https://bitbucket.org/$VCS_REPO/pull-requests/new?source=<branch>&dest=<target>\` with the ready title and description" ;;
  gitlab)    VCS="GitLab (\`$VCS_REPO\`) — the orchestrator gives the user the link \`https://gitlab.com/$VCS_REPO/-/merge_requests/new?merge_request[source_branch]=<branch>&merge_request[target_branch]=<target>\` (self-hosted: replace the host) with the ready title and description" ;;
  *)         VCS="not determined — the orchestrator gives the user the branch name with the ready PR title and description" ;;
esac

# sed replacement escaping (#, & and \ are special in the replacement part)
esc() { printf '%s' "$1" | sed -e 's/[\\#&]/\\&/g'; }

# settings.json: placeholders + environment-specific deny rules + project extraAllow
EXTRA=$(jq -c '.extraAllow // []' "$CFG")
# empty prefix (native): "{{EXEC}} bin/magento" -> "bin/magento"
fill_exec() { if [ -n "$EXEC" ]; then sed "s#{{EXEC}}#$(esc "$EXEC")#g"; else sed -e 's#{{EXEC}} ##g' -e 's#{{EXEC}}##g'; fi; }
fill_exec < "$TPL/settings.json" \
  | jq --argjson deny "$DENY" --argjson extra "$EXTRA" '
      .permissions.deny += $deny | .permissions.deny |= unique
      | .permissions.allow += $extra | .permissions.allow |= unique' > "$OUT/settings.json"

# retired rules with the environment's prefix filled in
fill_exec < "$TPL/retired-rules.json" > "$OUT/retired-rules.json"

# CLAUDE.md — multi-line values are inserted with awk from temp files
FR_FILE=$(mktemp); WA_FILE=$(mktemp)
printf '%s' "${FRONTEND_RULES#$'\n'}" > "$FR_FILE"
printf '%s' "$WORKAROUNDS" | fill_exec > "$WA_FILE"
fill_exec < "$TPL/CLAUDE.md" \
  | sed -e "s#{{ENV_NAME}}#$(esc "$ENV_NAME")#g" \
    -e "s#{{EXEC_NOTE}}#$(esc "$EXEC_NOTE")#g" \
    -e "s#{{EDITION_LINE}}#$(esc "$EDITION_LINE")#g" \
    -e "s#{{MSI_LINE}}#$(esc "$MSI_LINE")#g" \
    -e "s#{{STORE_LINE}}#$(esc "$STORE_LINE")#g" \
    -e "s#{{DB}}#$(esc "$DB")#g" \
    -e "s#{{MAGENTO_ROOT}}#$(esc "$MAGENTO_ROOT")#g" \
    -e "s#{{BASE_URL}}#$(esc "${BASE_URL:-(not determined — ask the user)}")#g" \
    -e "s#{{MAIL_URL}}#$(esc "${MAIL_URL:-(not determined — ask the user)}")#g" \
    -e "s#{{PHP}}#$(esc "${PHP:-determine from composer.json (require.php) and \`${EXEC:+$EXEC }php -v\`}")#g" \
    -e "s#{{LANGUAGE}}#$(esc "$LANGUAGE")#g" \
    -e "s#{{VCS}}#$(esc "$VCS")#g" \
  | awk -v f="$FR_FILE" -v w="$WA_FILE" '
      /{{FRONTEND_RULES}}/ {while((getline l < f)>0) print l; next}
      /{{WORKAROUNDS}}/    {while((getline l < w)>0) print l; next}
      {print}' > "$OUT/CLAUDE.md"
rm -f "$FR_FILE" "$WA_FILE"
grep -q '{{' "$OUT/CLAUDE.md" "$OUT/settings.json" && { echo "render: unreplaced placeholder left" >&2; exit 1; }
echo "OK: $OUT/settings.json, $OUT/CLAUDE.md, $OUT/retired-rules.json"
