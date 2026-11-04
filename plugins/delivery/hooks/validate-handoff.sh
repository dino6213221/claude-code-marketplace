#!/usr/bin/env bash
# SubagentStop: wymusza poprawny plik przekazania zanim agent odda pałeczkę.
# Exit 2 = agent nie może zakończyć, dostaje komunikat ze stderr i musi poprawić plik.
set -euo pipefail
INPUT=$(cat)
command -v jq >/dev/null || { echo 'validate-handoff: brak jq — walidacja pominięta, bramkę sprawdza tylko orkiestrator.' >&2; exit 0; }
AGENT=$(echo "$INPUT" | jq -r '.agent_type // empty')
AGENT="${AGENT##*:}"   # agenci z pluginu: "delivery:qa" -> "qa"
ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
ROOT="${CLAUDE_PROJECT_DIR:-.}"
# katalog Magento z .claude/delivery.json (zapisuje /delivery:init); domyślnie katalog projektu
MR=$(jq -r '.magentoRoot // "."' "$ROOT/.claude/delivery.json" 2>/dev/null || echo .)
AGENTS="$ROOT/${MR:-.}/var/agents"
[ -f "$AGENTS/.current" ] || exit 0
KEY=$(tr -d '[:space:]' < "$AGENTS/.current")
DIR="$AGENTS/$KEY"

case "$AGENT" in
  business-analyst)   FILE="01-analysis.md";        OK="READY";    ALL="READY|BLOCKED|TOO_LARGE" ;;
  solution-architect) FILE="02-architecture.md";    OK="READY";    ALL="READY|NEEDS_INPUT|TOO_LARGE" ;;
  senior-developer)   FILE="04-implementation.md";  OK="DONE";     ALL="DONE|NEEDS_INPUT" ;;
  code-reviewer)      FILE="05-review.md";          OK="APPROVED"; ALL="APPROVED|CHANGES_REQUESTED" ;;
  qa)
    # QA pracuje w dwóch trybach — sprawdzamy plik zmodyfikowany jako ostatni
    FILE=$( { ls -t "$DIR"/03-test-plan.md "$DIR"/06-qa.md 2>/dev/null || true; } | head -1)
    FILE=${FILE##*/}
    [ -n "$FILE" ] || FILE="06-qa.md"
    if [ "$FILE" = "03-test-plan.md" ]; then OK="READY"; ALL="READY|NEEDS_INPUT"; else OK="PASS"; ALL="PASS|FAIL"; fi ;;
  *) exit 0 ;;   # inni agenci (Explore, Plan, tryb A BA itp.) — bez walidacji
esac

# Tryb A BA (lista zadań) nie tworzy pliku — przepuszczamy, gdy brak katalogu zadania
[ -d "$DIR" ] || exit 0

fail() {
  echo "Plik przekazania $FILE nie spełnia bramki: $1. Popraw plik zgodnie z sekcją 'Kryteria sukcesu' i statusami z CLAUDE.md." >&2
  # nie zapętlamy się w nieskończoność — przy drugim podejściu decyduje orkiestrator
  [ "$ACTIVE" = "true" ] && exit 0
  exit 2
}

[ -f "$DIR/$FILE" ] || fail "brak pliku"
STATUS=$(head -1 "$DIR/$FILE" | sed -n 's/^STATUS: *\([A-Z_]*\).*/\1/p')
[ -n "$STATUS" ] || fail "pierwsza linia nie zawiera 'STATUS: <wartość>'"
echo "$STATUS" | grep -Eqx "$ALL" || fail "niedozwolony status '$STATUS' (dozwolone: $ALL)"
grep -q '^## Kryteria sukcesu' "$DIR/$FILE" || fail "brak sekcji '## Kryteria sukcesu'"
grep -q '^## Otwarte pytania'   "$DIR/$FILE" || fail "brak sekcji '## Otwarte pytania'"

if [ "$STATUS" = "$OK" ]; then
  # wycinamy sekcję Kryteria sukcesu i szukamy niezaznaczonych pozycji
  UNCHECKED=$(awk '/^## Kryteria sukcesu/{f=1;next} /^## /{f=0} f' "$DIR/$FILE" | grep -c '\[ \]' || true)
  [ "$UNCHECKED" -eq 0 ] || fail "status $STATUS przy $UNCHECKED niespełnionych kryteriach"
fi
exit 0
