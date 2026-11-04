#!/usr/bin/env bash
# PreToolUse (Bash): the business-analyst and solution-architect agents may not run any git command.
# Plugin hooks fire for every Bash call — only those two agents are guarded (checked without jq).
INPUT=$(cat)
echo "$INPUT" | grep -Eq '"agent_type"[[:space:]]*:[[:space:]]*"([^"]*:)?(business-analyst|solution-architect)"' || exit 0
command -v jq >/dev/null || { echo 'git-guard: jq missing — install jq (brew/apt install jq). Command blocked for safety.' >&2; exit 2; }
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
[ -n "$CMD" ] || exit 0
# any git invocation, including "git" inside sh -c / pipes / && chains, and gh (GitHub CLI)
if echo "$CMD" | grep -Eq '(^|[^[:alnum:]_./-])(git|gh)([[:space:]]|$)'; then
  echo "Blocked by git-guard: this agent may not run git commands. Read the code with Read/Grep/Glob; if repository history is needed, add a question to 'Open questions'." >&2
  exit 2
fi
exit 0
