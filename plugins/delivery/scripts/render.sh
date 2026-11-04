#!/usr/bin/env bash
# Generates settings.json and the CLAUDE.md section for a project from .claude/delivery.json.
# Usage: render.sh <delivery.json> <output directory>
# Output: <out>/settings.json, <out>/CLAUDE.md — /delivery:init merges them into the project's files.
set -euo pipefail
CFG="$1"; OUT="$2"
PLUGIN_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$PLUGIN_ROOT/templates"
command -v jq >/dev/null || { echo "render: jq required" >&2; exit 1; }
mkdir -p "$OUT"

get() { jq -r "$1 // empty" "$CFG"; }
ENV_TOOL=$(get .env)
MAGENTO_ROOT=$(get .magentoRoot); MAGENTO_ROOT=${MAGENTO_ROOT:-.}
BASE_URL=$(get .baseUrl)
MAIL_URL=$(get .mailUrl)
PHP=$(get .php)

case "$ENV_TOOL" in
  warden) ENV_NAME="Warden"; EXEC="warden env exec -T php-fpm"; DB="warden db connect"
          DENY='["Bash(warden env down*)","Bash(warden db import*)","Bash(warden env rm*)"]' ;;
  reward) ENV_NAME="Reward"; EXEC="reward env exec -T php-fpm"; DB="reward db connect"
          DENY='["Bash(reward env down*)","Bash(reward db import*)","Bash(reward env rm*)"]' ;;
  ddev)   ENV_NAME="DDEV"; EXEC="ddev exec"; DB="ddev mysql"
          DENY='["Bash(ddev delete*)","Bash(ddev import-db*)","Bash(ddev snapshot restore*)"]' ;;
  *) echo "render: unknown environment '$ENV_TOOL' (warden|reward|ddev)" >&2; exit 1 ;;
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

# settings.json: placeholders + environment-specific deny rules
sed "s#{{EXEC}}#$EXEC#g" "$TPL/settings.json" \
  | jq --argjson deny "$DENY" '.permissions.deny += $deny | .permissions.deny |= unique' > "$OUT/settings.json"

# CLAUDE.md
FR_FILE=$(mktemp); printf '%s' "${FRONTEND_RULES#$'\n'}" > "$FR_FILE"
sed -e "s#{{ENV_NAME}}#$ENV_NAME#g" \
    -e "s#{{EXEC}}#$EXEC#g" \
    -e "s#{{DB}}#$DB#g" \
    -e "s#{{MAGENTO_ROOT}}#$MAGENTO_ROOT#g" \
    -e "s#{{BASE_URL}}#${BASE_URL:-(not determined — ask the user)}#g" \
    -e "s#{{MAIL_URL}}#${MAIL_URL:-(not determined — ask the user)}#g" \
    -e "s#{{PHP}}#${PHP:-determine from composer.json (require.php) and \`$EXEC php -v\`}#g" \
    "$TPL/CLAUDE.md" \
  | awk -v f="$FR_FILE" '/{{FRONTEND_RULES}}/{while((getline l < f)>0) print l; next} {print}' > "$OUT/CLAUDE.md"
rm -f "$FR_FILE"
echo "OK: $OUT/settings.json, $OUT/CLAUDE.md"
