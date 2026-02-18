#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/notification.log"

ts() { date -Is; }

# Read stdin JSON (Notification input)
HOOK_INPUT="$(cat || true)"

# Parse fields (fallbacks if missing)
NOTIF_TYPE="$(echo "$HOOK_INPUT" | jq -r '.notification_type // empty' 2>/dev/null || true)"
TITLE="$(echo "$HOOK_INPUT" | jq -r '.title // empty' 2>/dev/null || true)"
MESSAGE="$(echo "$HOOK_INPUT" | jq -r '.message // empty' 2>/dev/null || true)"
CWD="$(echo "$HOOK_INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
SESSION_ID="$(echo "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"

# Sensible defaults
if [ -z "$TITLE" ]; then TITLE="Claude"; fi
if [ -z "$MESSAGE" ]; then MESSAGE="Notification: ${NOTIF_TYPE:-unknown}"; fi

if [ -n "$CWD" ]; then
  SHORT_CWD="$(basename "$CWD")"
  MESSAGE="$MESSAGE [$SHORT_CWD]"
fi

START_MS="$(date +%s%3N)"

{
  echo "==== $(ts) Notification hook start ===="
  echo "session_id=$SESSION_ID"
  echo "cwd=$CWD"
  echo "notification_type=$NOTIF_TYPE"
  echo "title=$TITLE"
  echo "message=$MESSAGE"
  echo "--- raw stdin ---"
  echo "$HOOK_INPUT"
  echo
} >>"$LOG_FILE" 2>&1

# Toast via Windows PowerShell (WSL)
# Note: uses double quotes in PS; safe because bash passes it as one argument.
powershell.exe -NoProfile -Command \
  "Import-Module BurntToast -ErrorAction SilentlyContinue; New-BurntToastNotification -Text \"$TITLE\",\"$MESSAGE\" -AppLogo 'c:\users\damie\Pictures\claude.png'" \
  >>"$LOG_FILE" 2>&1 || echo "[$(ts)] PowerShell toast failed" >>"$LOG_FILE"

END_MS="$(date +%s%3N)"
DUR=$((END_MS-START_MS))
echo "[$(ts)] Duration ms: $DUR" >>"$LOG_FILE"
echo "==== $(ts) Notification hook end ====" >>"$LOG_FILE"
echo >>"$LOG_FILE"

# Optional: add context back into Claude (cannot block notifications)
# Keep it short so you don't spam context.
if [ -n "$NOTIF_TYPE" ]; then
  jq -n --arg t "$NOTIF_TYPE" --arg m "$MESSAGE" '{
    "hookSpecificOutput": {
      "hookEventName": "Notification",
      "additionalContext": ("[notification] type=" + $t + " message=" + $m)
    }
  }'
fi

exit 0

