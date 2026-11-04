#!/usr/bin/env bash
# PreToolUse (Bash), only for the delivery:qa agent: blocks destructive SQL and raw database writes.
INPUT=$(cat)
# plugin hooks fire for every Bash call — guard only the QA agent (checked without jq, so a missing jq never blocks other sessions)
echo "$INPUT" | grep -Eq '"agent_type"[[:space:]]*:[[:space:]]*"([^"]*:)?qa"' || exit 0
command -v jq >/dev/null || { echo 'sql-guard: jq missing — install jq (brew/apt install jq). Command blocked for safety.' >&2; exit 2; }
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -n "$CMD" ] || exit 0
UP=$(echo "$CMD" | tr '[:lower:]' '[:upper:]')

block() { echo "Blocked by sql-guard: $1. Create and delete dummy data through the Magento API/scripts, by specific IDs from the 'Dummy data' table." >&2; exit 2; }

echo "$UP" | grep -Eq '\b(DROP|TRUNCATE|ALTER)\b' && block "DROP/TRUNCATE/ALTER"
# DELETE / UPDATE without WHERE
if echo "$UP" | grep -Eq '\bDELETE\s+FROM\b|\bUPDATE\s+\S+\s+SET\b'; then
  echo "$UP" | grep -Eq '\bWHERE\b' || block "DELETE/UPDATE without WHERE"
fi
# INSERT/UPDATE/DELETE without the QA prefix — the query must target test data
if echo "$UP" | grep -Eq '\b(INSERT|UPDATE|DELETE)\b' && echo "$UP" | grep -Eq '\bMYSQL\b|\bDB +CONNECT\b'; then
  echo "$CMD" | grep -q 'QA-' || block "SQL write not targeting records with the QA- prefix"
fi
exit 0
