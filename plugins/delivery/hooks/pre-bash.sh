#!/usr/bin/env bash
# PreToolUse (Bash) — one dispatcher for all delivery guards (plugin hooks fire for EVERY Bash call):
#   git-guard  — delivery:business-analyst / delivery:solution-architect: no git/gh at all
#   sql-guard  — delivery:qa: no destructive SQL, no SQL writes outside QA- records, no SQL from files / PHP
#   push-guard — any session in a project initialized by /delivery:init: no push to master/main,
#                no force / mirror / all (closes refspec bypasses such as `git push origin HEAD:master`)
# Exit 2 = command blocked; stderr goes back to the agent.
INPUT=$(cat)
. "$(dirname "$0")/lib.sh"

# Fast path without jq: decide whether any guard applies at all
AGENT_RAW=$(printf '%s' "$INPUT" | sed -n 's/.*"agent_type"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)
GUARD_GIT=0; GUARD_SQL=0; GUARD_PUSH=0
echo "$AGENT_RAW" | grep -Eqx '(delivery:)?(business-analyst|solution-architect)' && GUARD_GIT=1
echo "$AGENT_RAW" | grep -Eqx '(delivery:)?qa' && GUARD_SQL=1
[ -f "$DELIVERY_JSON" ] && printf '%s' "$INPUT" | grep -q 'push' && GUARD_PUSH=1
[ $((GUARD_GIT + GUARD_SQL + GUARD_PUSH)) -gt 0 ] || exit 0

command -v jq >/dev/null || { echo 'delivery guard: jq missing — install jq (brew/apt install jq). Command blocked for safety.' >&2; exit 2; }
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[ -n "$CMD" ] || exit 0

block() { echo "Blocked by delivery $1" >&2; exit 2; }

# ---------- git-guard ----------
if [ "$GUARD_GIT" = 1 ] && echo "$CMD" | grep -Eq '(^|[^[:alnum:]_./-])(git|gh)([[:space:]]|$)'; then
  block "git-guard: this agent may not run git commands. Read the code with Read/Grep/Glob; if repository history is needed, add a question to 'Open questions'."
fi

# ---------- sql-guard ----------
if [ "$GUARD_SQL" = 1 ]; then
  UP=$(echo "$CMD" | tr '[:lower:]' '[:upper:]')
  HINT="Create and delete dummy data through the Magento API/scripts, by specific IDs from the 'Dummy data' table."
  # database clients: mysql/mariadb, `warden|reward db connect`, n98-magerun2 db:query/db:console, the project's own `db` command (env custom)
  DBCLI='\b(MYSQL|MARIADB)\b|\bDB +CONNECT\b|\bDB:(QUERY|CONSOLE)\b'
  if [ -f "$DELIVERY_JSON" ]; then
    CUSTOM_DB=$(jq -r '.db // empty' "$DELIVERY_JSON" 2>/dev/null | tr '[:lower:]' '[:upper:]')
    [ -n "$CUSTOM_DB" ] && DBCLI="$DBCLI|$(printf '%s' "$CUSTOM_DB" | sed 's/[][\.*^$(){}+?|/]/\\&/g')"
  fi
  echo "$UP" | grep -Eq '\b(DROP|TRUNCATE|ALTER)\b' && block "sql-guard: DROP/TRUNCATE/ALTER. $HINT"
  if echo "$UP" | grep -Eq '\bDELETE\s+FROM\b|\bUPDATE\s+\S+\s+SET\b'; then
    echo "$UP" | grep -Eq '\bWHERE\b' || block "sql-guard: DELETE/UPDATE without WHERE. $HINT"
  fi
  if echo "$UP" | grep -Eq "$DBCLI"; then
    # SQL from a file cannot be checked — statements must be inline
    echo "$CMD" | grep -Eq '(^|[^<])<[[:space:]]*[^<([:space:]]|\bsource\b|\\\.[[:space:]]' \
      && block "sql-guard: SQL read from a file — put the statements inline (-e \"...\") so they can be checked. $HINT"
    if echo "$UP" | grep -Eq '\b(INSERT|UPDATE|DELETE|REPLACE)\b'; then
      echo "$CMD" | grep -q 'QA-' || block "sql-guard: SQL write not targeting records with the QA- prefix. $HINT"
    fi
  fi
  # raw DB access from inline PHP bypasses the checks above
  echo "$UP" | grep -Eq '\bPHP\b.*(-R|-A)\b' && echo "$UP" | grep -Eq 'PDO|MYSQLI|->QUERY\(|->EXEC\(|RESOURCECONNECTION' \
    && block "sql-guard: raw database access from inline PHP. $HINT"
fi

# ---------- push-guard ----------
if [ "$GUARD_PUSH" = 1 ]; then
  current_branch() { git -C "$PROJECT_DIR" branch --show-current 2>/dev/null; }
  is_protected() { case "$1" in master|main) return 0 ;; *) return 1 ;; esac; }
  # split into simple commands on ; && || | and newlines, then inspect every `git … push …`
  # (awk, not sed: BSD sed on macOS does not turn \n into a newline)
  echo "$CMD" | awk '{gsub(/&&|\|\||;|\|/, "\n"); print}' | while IFS= read -r SEG; do
    read -ra T <<< "$SEG"
    i=0; n=${#T[@]}
    while [ $i -lt $n ] && [ "${T[$i]##*/}" != "git" ]; do i=$((i+1)); done
    [ $i -lt $n ] || continue
    while [ $i -lt $n ] && [ "${T[$i]}" != "push" ]; do i=$((i+1)); done
    [ $i -lt $n ] || continue
    i=$((i+1)); POS=0; REFSPECS=0
    while [ $i -lt $n ]; do
      A="${T[$i]}"; A="${A%\"}"; A="${A#\"}"; A="${A%\'}"; A="${A#\'}"
      case "$A" in
        --force*|-f|--mirror|--all|--prune) echo "push-guard: '$A' is not allowed"; exit 3 ;;
        -o|--push-option|--repo|--receive-pack|--exec) i=$((i+1)) ;;
        -*) ;;
        *)
          POS=$((POS+1))
          if [ $POS -gt 1 ]; then
            REFSPECS=$((REFSPECS+1))
            case "$A" in +*) echo "push-guard: force refspec '$A' is not allowed"; exit 3 ;; esac
            DST="${A##*:}"; DST="${DST#refs/heads/}"
            [ "$DST" = "HEAD" ] || [ "$DST" = "@" ] && DST=$(current_branch)
            is_protected "$DST" && { echo "push-guard: push to '$DST' is not allowed"; exit 3; }
          fi ;;
      esac
      i=$((i+1))
    done
    # no refspec → pushes the current branch
    if [ $REFSPECS -eq 0 ] && is_protected "$(current_branch)"; then
      echo "push-guard: the current branch is $(current_branch) — push only the issue branch"; exit 3
    fi
  done > "${TMPDIR:-/tmp}/delivery-push-guard.$$"
  MSG=$(cat "${TMPDIR:-/tmp}/delivery-push-guard.$$" 2>/dev/null); rm -f "${TMPDIR:-/tmp}/delivery-push-guard.$$"
  [ -n "$MSG" ] && block "$MSG. Push only the issue branch, without force (see CLAUDE.md, section 'Git')."
fi
exit 0
