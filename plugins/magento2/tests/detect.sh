#!/usr/bin/env bash
# Tests for bin/magento2-detect on synthetic project layouts. Usage: bash plugins/magento2/tests/detect.sh
set -u
DETECT="$(cd "$(dirname "$0")/../bin" && pwd)/magento2-detect"
PASS=0; FAILED=0
check() { # check <name> <setup commands> <expected KEY=VALUE>...
  local name="$1" setup="$2"; shift 2
  local T; T=$(mktemp -d); (cd "$T" && eval "$setup")
  local out; out=$(bash "$DETECT" "$T")
  for kv in "$@"; do echo "$out" | grep -qx -- "$kv" && PASS=$((PASS+1)) || { FAILED=$((FAILED+1)); echo "FAIL: $name: expected $kv"; }; done
  rm -rf "$T"
}
check warden   'mkdir -p bin; touch bin/magento; printf "WARDEN_ENV_TYPE=magento2\nTRAEFIK_DOMAIN=shop.test\nTRAEFIK_SUBDOMAIN=app\n" > .env' \
  MAGENTO_ROOT=. ENV_TOOL=warden BASE_URL=https://app.shop.test/ MAIL_URL=https://webmail.shop.test/
check ddev     'mkdir -p bin .ddev; touch bin/magento; echo "name: shop" > .ddev/config.yaml' \
  ENV_TOOL=ddev BASE_URL=https://shop.ddev.site/
check compose  'mkdir -p src/bin; touch src/bin/magento compose.yaml' MAGENTO_ROOT=src ENV_TOOL=custom
check sub-noenv 'mkdir -p src/bin; touch src/bin/magento' MAGENTO_ROOT=src ENV_TOOL=
check commerce 'mkdir -p bin; touch bin/magento; echo "{\"require\":{\"php\":\"~8.3.0\",\"magento/product-enterprise-edition\":\"2.4.7\"}}" > composer.json' \
  EDITION=adobe-commerce PHP_CONSTRAINT=~8.3.0
check opensrc  'mkdir -p bin app/etc; touch bin/magento; echo "{\"require\":{\"magento/product-community-edition\":\"2.4.7\"}}" > composer.json; echo "<?php return [\"modules\"=>[\"Magento_Inventory\" => 1]];" > app/etc/config.php' \
  EDITION=open-source MSI=yes
check nomsi    'mkdir -p bin app/etc; touch bin/magento; echo "<?php return [\"modules\"=>[\"Magento_Catalog\" => 1]];" > app/etc/config.php' MSI=no
check hyva     'mkdir -p bin; touch bin/magento; echo "{\"require\":{\"hyva-themes/magento2-default-theme\":\"1.3\"}}" > composer.json' FRONTEND=hyva
check vcs      'mkdir -p bin; touch bin/magento; git init -q; git remote add origin https://user:TOKEN@bitbucket.org/ws/shop.git' VCS_HOST=bitbucket VCS_REPO=ws/shop
T=$(mktemp -d); mkdir -p "$T/bin"; touch "$T/bin/magento"; git -C "$T" init -q; git -C "$T" remote add origin https://u:SECRET@github.com/o/r.git
bash "$DETECT" "$T" | grep -q SECRET && { FAILED=$((FAILED+1)); echo "FAIL: credentials leaked"; } || PASS=$((PASS+1)); rm -rf "$T"
echo "passed: $PASS, failed: $FAILED"
[ "$FAILED" -eq 0 ]
