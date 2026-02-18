#!/bin/bash
set -euo pipefail

LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/permission-review.log"
JSON_LOG_FILE="$LOG_DIR/permission-review.jsonl"

# Whitelist and blacklist configuration
WHITELIST_FILE="$HOME/.claude/hooks/whitelist.txt"
BLACKLIST_FILE="$HOME/.claude/hooks/blacklist.txt"

log() {
  echo "[$(date -Is)] $*" >> "$LOG_FILE"
}

log_json() {
  local decision_type="$1"
  local decision="$2"
  local reasoning="$3"
  local reviewer_output="${4:-}"
  
  jq -n \
    --arg timestamp "$(date -Is)" \
    --arg tool_name "$TOOL_NAME" \
    --argjson tool_input "$TOOL_INPUT" \
    --arg cwd "$CWD" \
    --arg decision_type "$decision_type" \
    --arg decision "$decision" \
    --arg reasoning "$reasoning" \
    --arg reviewer_output "$reviewer_output" \
    '{
      timestamp: $timestamp,
      tool_name: $tool_name,
      tool_input: $tool_input,
      cwd: $cwd,
      decision_type: $decision_type,
      decision: $decision,
      reasoning: $reasoning,
      reviewer_output: $reviewer_output
    }' >> "$JSON_LOG_FILE"
}

log "---- hook start ----"

REVIEWER_MODEL="claude-opus-4-5-20251101"

# --- Read stdin ---
HOOK_INPUT=$(cat)
log "STDIN: $HOOK_INPUT"

TOOL_NAME=$(echo "$HOOK_INPUT" | jq -r '.tool_name // empty')
TOOL_INPUT=$(echo "$HOOK_INPUT" | jq -c '.tool_input // {}')
CWD=$(echo "$HOOK_INPUT" | jq -r '.cwd // empty')

log "TOOL_NAME=$TOOL_NAME"
log "CWD=$CWD"

# Malformed input -> passthrough
if [ -z "$TOOL_NAME" ]; then
  log "No tool name -> passthrough"
  exit 0
fi

# --- Check whitelist (auto-approve) ---
if [ -f "$WHITELIST_FILE" ]; then
  while IFS= read -r pattern || [ -n "$pattern" ]; do
    # Skip empty lines and comments
    [[ -z "$pattern" || "$pattern" =~ ^[[:space:]]*# ]] && continue
    # Remove leading/trailing whitespace
    pattern=$(echo "$pattern" | xargs)
    
    # Check if pattern includes content matching (ToolName:content_pattern)
    if [[ "$pattern" == *:* ]]; then
      tool_pattern="${pattern%%:*}"
      content_pattern="${pattern#*:}"
      
      # Check if tool name matches first
      if [[ "$TOOL_NAME" == $tool_pattern ]]; then
        # Extract command/content to match against
        MATCH_CONTENT=""
        if [ "$TOOL_NAME" = "Bash" ]; then
          MATCH_CONTENT=$(echo "$TOOL_INPUT" | jq -r '.command // empty')
        elif [[ "$TOOL_NAME" =~ ^(Write|Edit)$ ]]; then
          MATCH_CONTENT=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty')
        fi
        
        # Check if content matches the pattern
        if [[ -n "$MATCH_CONTENT" && "$MATCH_CONTENT" == $content_pattern ]]; then
          log "WHITELISTED: $TOOL_NAME with content '$MATCH_CONTENT' matches pattern: $pattern"
          log_json "whitelist" "allow" "Matched pattern: $pattern (content: $MATCH_CONTENT)"
          echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
          log "---- hook end (whitelisted) ----"
          exit 0
        fi
      fi
    else
      # Simple tool name matching (existing behavior)
      if [[ "$TOOL_NAME" == $pattern ]]; then
        log "WHITELISTED: $TOOL_NAME matches pattern: $pattern"
        log_json "whitelist" "allow" "Matched pattern: $pattern"
        echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
        log "---- hook end (whitelisted) ----"
        exit 0
      fi
    fi
  done < "$WHITELIST_FILE"
fi

# --- Check blacklist (auto-deny) ---
if [ -f "$BLACKLIST_FILE" ]; then
  while IFS= read -r pattern || [ -n "$pattern" ]; do
    # Skip empty lines and comments
    [[ -z "$pattern" || "$pattern" =~ ^[[:space:]]*# ]] && continue
    # Remove leading/trailing whitespace
    pattern=$(echo "$pattern" | xargs)
    
    # Check if pattern includes content matching (ToolName:content_pattern)
    if [[ "$pattern" == *:* ]]; then
      tool_pattern="${pattern%%:*}"
      content_pattern="${pattern#*:}"
      
      # Check if tool name matches first
      if [[ "$TOOL_NAME" == $tool_pattern ]]; then
        # Extract command/content to match against
        MATCH_CONTENT=""
        if [ "$TOOL_NAME" = "Bash" ]; then
          MATCH_CONTENT=$(echo "$TOOL_INPUT" | jq -r '.command // empty')
        elif [[ "$TOOL_NAME" =~ ^(Write|Edit)$ ]]; then
          MATCH_CONTENT=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty')
        fi
        
        # Check if content matches the pattern
        if [[ -n "$MATCH_CONTENT" && "$MATCH_CONTENT" == $content_pattern ]]; then
          log "BLACKLISTED: $TOOL_NAME with content '$MATCH_CONTENT' matches pattern: $pattern"
          log_json "blacklist" "deny" "Matched pattern: $pattern (content: $MATCH_CONTENT)"
          jq -n --arg reason "Tool is blacklisted: $TOOL_NAME - $MATCH_CONTENT" \
            '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":$reason}}}'
          log "---- hook end (blacklisted) ----"
          exit 0
        fi
      fi
    else
      # Simple tool name matching (existing behavior)
      if [[ "$TOOL_NAME" == $pattern ]]; then
        log "BLACKLISTED: $TOOL_NAME matches pattern: $pattern"
        log_json "blacklist" "deny" "Matched pattern: $pattern"
        jq -n --arg reason "Tool is blacklisted: $TOOL_NAME" \
          '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":$reason}}}'
        log "---- hook end (blacklisted) ----"
        exit 0
      fi
    fi
  done < "$BLACKLIST_FILE"
fi

log "Tool not in whitelist or blacklist, proceeding to AI review"

# --- Always ask user for MCP write operations on external services ---
if echo "$TOOL_NAME" | grep -qE '^mcp__.*(create|update|delete|add_message|write|push|merge|assign|move|duplicate)'; then
  log "MCP write operation -> manual approval"
  exit 0
fi

# --- Truncate large tool input (keep first 4000 chars) ---
TRUNCATED_INPUT=$(echo "$TOOL_INPUT" | head -c 4000)
log "TRUNCATED_INPUT=$TRUNCATED_INPUT"

# --- Build reviewer prompt ---
REVIEWER_PROMPT="You are a security reviewer for an AI coding assistant. Review this tool call and decide: approve, ask, or deny.
TOOL: ${TOOL_NAME}
CWD: ${CWD}
INPUT: ${TRUNCATED_INPUT}
APPROVE if:
- Standard dev commands (npm test/install/build, git operations, make, cargo, etc.)
- Reading/writing/editing files within the project directory
- Running linters, formatters, type checkers, test suites
- Standard CLI tools used non-destructively
- curl/wget GET requests to known/public URLs
- General purpose commands that don't touch credentials or sensitive data
DENY (hard block, no override) ONLY for truly dangerous operations:
- Accessing or exfiltrating credentials/secrets (~/.ssh, ~/.aws, ~/.env, tokens, API keys)
- Piping secrets or credentials to external services
- Mass/recursive deletion outside safe targets (node_modules, dist, build, .cache)
- Obfuscated commands designed to hide intent (base64 decode | bash, eval of encoded strings)
- curl | bash patterns (downloading and executing remote scripts)
ASK (let the user decide) for anything uncertain:
- Commands you're not fully sure about
- curl/wget POST requests
- sudo or privilege escalation
- Force pushing to remote repos
- Destructive database operations
- Anything not clearly safe but not clearly credential/leak/mass-deletion risk
When in doubt, ask -- NOT deny.
Respond with ONLY a JSON object: {\"decision\":\"approve\" or \"ask\" or \"deny\", \"reasoning\":\"brief explanation\"}"

log "Calling reviewer model"

# --- Call reviewer ---
REVIEWER_OUTPUT=""
if REVIEWER_OUTPUT=$(claude -p \
  --output-format json \
  --model "$REVIEWER_MODEL" \
  --tools "" \
  --no-session-persistence \
  --dangerously-skip-permissions \
  "$REVIEWER_PROMPT" 2>>"$LOG_FILE"); then
  log "Reviewer raw output: $REVIEWER_OUTPUT"
else
  log "Reviewer call failed -> passthrough"
  exit 0
fi

# --- Parse response ---
RESULT_TEXT=$(echo "$REVIEWER_OUTPUT" | jq -r '.result // empty' 2>/dev/null)
if [ -z "$RESULT_TEXT" ]; then
  RESULT_TEXT="$REVIEWER_OUTPUT"
fi

log "RESULT_TEXT=$RESULT_TEXT"

CLEAN_JSON="$RESULT_TEXT"
if ! echo "$CLEAN_JSON" | jq -e '.decision' >/dev/null 2>&1; then
  CLEAN_JSON=$(echo "$RESULT_TEXT" | sed '/^```/d')
fi

DECISION=$(echo "$CLEAN_JSON" | jq -r '.decision // empty' 2>/dev/null)
REASONING=$(echo "$CLEAN_JSON" | jq -r '.reasoning // "No reasoning provided"' 2>/dev/null)

log "DECISION=$DECISION"
log "REASONING=$REASONING"

# --- Emit hook decision ---
if [ "$DECISION" = "approve" ]; then
  log "Emitting allow"
  log_json "ai_review" "approve" "$REASONING" "$REVIEWER_OUTPUT"
  echo '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
elif [ "$DECISION" = "deny" ]; then
  log "Emitting deny"
  log_json "ai_review" "deny" "$REASONING" "$REVIEWER_OUTPUT"
  jq -n --arg reason "$REASONING" \
    '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":$reason}}}'
else
  CWD_TAG=""
  if [ -n "${CWD:-}" ]; then
    CWD_TAG=" [$(basename "${CWD%/}")]"
  fi

  # best-effort toast; don't break permissions flow if it fails
  log "Sending notification to windows"
  powershell.exe -NoProfile -Command \
    "Import-Module BurntToast -ErrorAction SilentlyContinue; New-BurntToastNotification -Text 'Claude','Permission needs review ${CWD_TAG}: ${TOOL_NAME}' -AppLogo 'c:\users\damie\Pictures\claude.png'" \
    >/dev/null 2>&1 || true

  log "Decision ask/unknown -> manual approval"
  log_json "ai_review" "ask" "$REASONING" "$REVIEWER_OUTPUT"
  exit 0
fi

log "---- hook end ----"
exit 0

