#!/usr/bin/env bash
# Shared helpers for the delivery hooks. Source it: . "$(dirname "$0")/lib.sh"

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-.}"
DELIVERY_JSON="$PROJECT_DIR/.claude/delivery.json"

# Handoff root: <project>/<magentoRoot>/var/agents
agents_dir() {
  local mr="."
  if [ -f "$DELIVERY_JSON" ] && command -v jq >/dev/null; then
    mr=$(jq -r '.magentoRoot // "."' "$DELIVERY_JSON" 2>/dev/null || echo .)
  fi
  echo "$PROJECT_DIR/${mr:-.}/var/agents"
}

# Session id of the hook input (set SID before calling current_key): SID=$(input_sid "$INPUT")
input_sid() { printf '%s' "$1" | jq -r '.session_id // empty' 2>/dev/null || true; }

# Current issue key of this session (empty when no pipeline is active in it).
# Sessions are bound to issues by hooks/bind-session.sh (var/agents/.sessions/<session_id>),
# so several sessions can run pipelines for different issues at the same time.
# Legacy fallback: var/agents/.current, only while no session was ever bound (no .sessions dir).
current_key() {
  local d f
  d="$(agents_dir)"
  if [ -n "${SID:-}" ] && [ -f "$d/.sessions/$SID" ]; then
    tr -d '[:space:]' < "$d/.sessions/$SID"
  elif [ -d "$d/.sessions" ]; then
    :
  else
    f="$d/.current"
    [ -f "$f" ] && tr -d '[:space:]' < "$f" || true
  fi
}

# Stages that use the shared checkout and local environment — one issue at a time
CODE_STAGES='implementation|review|qa'

# code_lock_holder <KEY> — the other issue currently in a code stage (empty when free)
code_lock_holder() {
  local d s k st
  d="$(agents_dir)"
  for s in "$d"/*/state.json; do
    [ -f "$s" ] || continue
    k=$(basename "$(dirname "$s")")
    [ "$k" = "$1" ] && continue
    st=$(jq -r '.stage // empty' "$s" 2>/dev/null || true)
    if echo "$st" | grep -Eqx "$CODE_STAGES"; then echo "$k ($st)"; return; fi
  done
}

# state <jq path> — value from var/agents/<KEY>/state.json (empty when missing)
state() {
  local f
  f="$(agents_dir)/$(current_key)/state.json"
  [ -f "$f" ] && command -v jq >/dev/null && jq -r "$1 // empty" "$f" 2>/dev/null || true
}

# mtime <file> — modification time as epoch seconds (GNU stat first, then BSD/macOS)
mtime() {
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

# agent_short <raw agent_type> — "delivery:qa" -> "qa"
agent_short() { echo "${1##*:}"; }
