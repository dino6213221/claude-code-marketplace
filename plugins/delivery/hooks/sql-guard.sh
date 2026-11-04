#!/usr/bin/env bash
# PreToolUse (Bash), tylko dla agenta delivery:qa: blokuje destrukcyjne SQL i surowe zapisy do bazy.
INPUT=$(cat)
# hook pluginu odpala się dla każdego Bash — pilnujemy tylko agenta QA (sprawdzenie bez jq, żeby brak jq nie blokował innych sesji)
echo "$INPUT" | grep -Eq '"agent_type"[[:space:]]*:[[:space:]]*"([^"]*:)?qa"' || exit 0
command -v jq >/dev/null || { echo 'sql-guard: brak jq — zainstaluj jq (brew/apt install jq). Komenda zablokowana dla bezpieczeństwa.' >&2; exit 2; }
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -n "$CMD" ] || exit 0
UP=$(echo "$CMD" | tr '[:lower:]' '[:upper:]')

block() { echo "Zablokowane przez sql-guard: $1. Dummy data twórz i usuwaj przez API/skrypty Magento, po konkretnych ID z tabeli 'Dummy data'." >&2; exit 2; }

echo "$UP" | grep -Eq '\b(DROP|TRUNCATE|ALTER)\b' && block "DROP/TRUNCATE/ALTER"
# DELETE / UPDATE bez WHERE
if echo "$UP" | grep -Eq '\bDELETE\s+FROM\b|\bUPDATE\s+\S+\s+SET\b'; then
  echo "$UP" | grep -Eq '\bWHERE\b' || block "DELETE/UPDATE bez WHERE"
fi
# INSERT/UPDATE/DELETE bez prefiksu QA w treści — wymagamy, by zapytanie celowało w dane testowe
if echo "$UP" | grep -Eq '\b(INSERT|UPDATE|DELETE)\b' && echo "$UP" | grep -Eq '\bMYSQL\b|\bDB +CONNECT\b'; then
  echo "$CMD" | grep -q 'QA-' || block "zapis SQL, który nie celuje w rekordy z prefiksem QA-"
fi
exit 0
