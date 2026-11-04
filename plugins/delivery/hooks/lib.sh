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

# Current issue key (empty when no pipeline is active)
current_key() {
  local f
  f="$(agents_dir)/.current"
  [ -f "$f" ] && tr -d '[:space:]' < "$f" || true
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
