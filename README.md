# Claude Code hooks: PermissionRequest and Notification

This doc explains how the two hooks work, what they receive on stdin, what you can output, and how to run/debug them in a real WSL/Linux + Windows toast setup. 

## What hooks are

Hooks are user-defined commands that Claude Code runs at specific lifecycle points. They receive JSON on **stdin** and communicate back via **stdout**, **stderr**, and **exit code**. 

## Common fields you usually get on stdin

Most hook events include some or all of these fields (exact set depends on event):

* `session_id`
* `transcript_path` (path to session transcript `.jsonl`)
* `cwd`
* `permission_mode`
* `hook_event_name`



## PermissionRequest hook

### When it fires

Runs when Claude Code is about to show the user a permission dialog (the “allow this tool?” moment). 

### What it’s for

Deterministically decide on the user’s behalf:

* allow automatically
* deny automatically with a message (optionally interrupt)
* otherwise do nothing and let the normal UI prompt happen

Claude Code calls this “decision control” for `PermissionRequest`. 

### Input (stdin)

`PermissionRequest` receives JSON via stdin (same general hook input mechanism). The exact schema is documented in the hook reference page.

In practice you’ll see a structure similar to the tool permission context (tool name + tool input + cwd), depending on the permission being requested.

### Output (stdout)

To auto-allow or auto-deny, print a JSON object with `hookSpecificOutput` and a `decision`:

Allow (optionally modify tool input):

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow",
      "updatedInput": {
        "command": "npm run lint"
      }
    }
  }
}
```

Deny (with optional message, optional interrupt):

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "deny",
      "message": "Reason shown to Claude/user",
      "interrupt": true
    }
  }
}
```

These fields are explicitly documented for PermissionRequest decision control. 

### Exit codes

Keep it simple:

* exit `0` after printing valid JSON output
* exit `0` with no output to “fall through” to normal UI permission prompt

(Claude Code’s hook system uses stdout + exit behavior; the docs emphasize stdout JSON and exit behavior patterns across hooks.

### Typical team patterns

* Always “fall through” (manual approval) for anything that touches external services or looks destructive
* Auto-allow only for well-known safe commands in-repo (tests, lint, formatting, read-only commands, local file edits)

### Debugging PermissionRequest

Minimal approach:

* log raw stdin JSON
* log parsed fields (`tool_name`, `tool_input`, `cwd`)
* log decision + emitted JSON

Your existing script approach (log file under `~/.claude/logs/`) is the right model: PermissionRequest hooks always get stdin, so logging is reliable.

## Notification hook

### When it fires

Runs when Claude Code emits a notification event (not a tool permission decision). Common notification types include:

* `permission_prompt`
* `idle_prompt` (after extended idle time)
* `auth_success`
* `elicitation_dialog` (MCP tool elicitation input needed)

These matchers are listed in the hook reference. 

### What it’s for

Side effects only:

* desktop toasts
* sound alerts
* logging
* bridging notifications to Slack/Teams/etc (if you want)

Notification hooks **cannot block or modify** the notification flow. They are informational. 

### Input (stdin)

Notification hooks receive the common fields plus:

* `message` (notification text)
* `title` (optional)
* `notification_type` (which type fired)

Example input from the docs (title may be absent depending on event):

```json
{
  "session_id": "abc123",
  "transcript_path": "/Users/.../.claude/projects/.../....jsonl",
  "cwd": "/Users/...",
  "permission_mode": "default",
  "hook_event_name": "Notification",
  "message": "Claude needs your permission to use Bash",
  "notification_type": "permission_prompt"
}
```

This example appears in the hook reference. 

### Output (stdout)

Notification hooks can optionally return `additionalContext` to add a short string into Claude’s context.

Structured form:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "Notification",
    "additionalContext": "Short context string here"
  }
}
```

The hook reference documents `hookSpecificOutput.additionalContext` as a way to add context, and shows it as a general pattern across events. 

If you don’t want to add context, just produce no stdout and exit 0.

## Reference implementation

This section is copy/paste ready for a team.

### settings.json

This calls Linux wrappers for both events:

```json
{
  "hooks": {
    "PermissionRequest": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/permission-review.sh",
            "timeout": 30
          }
        ]
      }
    ],
    "Notification": [
      {
        "matcher": "permission_prompt|idle_prompt|auth_success|elicitation_dialog",
        "hooks": [
          {
            "type": "command",
            "command": "~/.claude/hooks/notify-wrapper.sh"
          }
        ]
      }
    ]
  }
}
```

Matchers for Notification types are documented in the hook reference. ([[Claude Code](https://code.claude.com/docs/fr/hooks?utm_source=chatgpt.com)][4])

### Notification wrapper (Linux/WSL)

`~/.claude/hooks/notify-wrapper.sh`

* reads stdin JSON
* logs raw + parsed fields
* emits a Windows toast (via `powershell.exe`)
* optionally returns `additionalContext` (kept short)

```bash
#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="$HOME/.claude/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/notification.log"

ts() { date -Is; }

START_MS="$(date +%s%3N)"

HOOK_INPUT="$(cat || true)"

NOTIF_TYPE="$(echo "$HOOK_INPUT" | jq -r '.notification_type // empty' 2>/dev/null || true)"
TITLE="$(echo "$HOOK_INPUT" | jq -r '.title // empty' 2>/dev/null || true)"
MESSAGE="$(echo "$HOOK_INPUT" | jq -r '.message // empty' 2>/dev/null || true)"
CWD="$(echo "$HOOK_INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)"
SESSION_ID="$(echo "$HOOK_INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)"

[ -n "$TITLE" ] || TITLE="Claude"
[ -n "$MESSAGE" ] || MESSAGE="Notification: ${NOTIF_TYPE:-unknown}"

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

# Toast (WSL -> Windows)
# BurntToast can add noticeable latency on cold start.
powershell.exe -NoProfile -Command \
  "Import-Module BurntToast -ErrorAction SilentlyContinue; New-BurntToastNotification -Text \"$TITLE\",\"$MESSAGE\" -AppLogo 'c:\users\damie\Pictures\claude.png'" \
  >>"$LOG_FILE" 2>&1 || echo "[$(ts)] PowerShell toast failed" >>"$LOG_FILE"

END_MS="$(date +%s%3N)"
echo "[$(ts)] Duration ms: $((END_MS-START_MS))" >>"$LOG_FILE"
echo "==== $(ts) Notification hook end ====" >>"$LOG_FILE"
echo >>"$LOG_FILE"

# Optional: add short context back to Claude (Notification cannot block/modify)
if [ -n "$NOTIF_TYPE" ] && [ -n "$MESSAGE" ]; then
  jq -n --arg t "$NOTIF_TYPE" --arg m "$MESSAGE" '{
    "hookSpecificOutput": {
      "hookEventName": "Notification",
      "additionalContext": ("[notification] type=" + $t + " message=" + $m)
    }
  }'
fi

exit 0
```

Notification input fields (`message`, optional `title`, `notification_type`) and the ability to return `additionalContext` are documented in the hook reference. 

### How to validate it works

Run a manual stdin test (simulates Claude Code):

```bash
cat <<'JSON' | ~/.claude/hooks/notify-wrapper.sh
{
  "session_id": "abc123",
  "cwd": "/tmp",
  "hook_event_name": "Notification",
  "notification_type": "permission_prompt",
  "title": "Permission needed",
  "message": "Claude needs your permission to use Bash"
}
JSON
```

Watch logs:

```bash
tail -f ~/.claude/logs/notification.log
```

### PermissionRequest output example

If your security reviewer decides “allow”:

```json
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}
```

If “deny”:

```json
{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"deny","message":"Why it was denied","interrupt":true}}}
```

Behavior and optional fields are documented in PermissionRequest decision control. 

## Operational notes for teams

### Keep hooks deterministic

A hook should be deterministic and fast. If you call an LLM inside a hook (like your permission-reviewer flow), you’re trading speed for policy centralization. That can be fine, but log timings and keep timeouts tight.

### Don’t spam additionalContext

`additionalContext` is powerful but easy to abuse. Keep it short, and only include what you actually want the model to remember for the rest of the session.

### Keep a shared log convention

Recommend standardizing on:

* `~/.claude/logs/permission-review.log`
* `~/.claude/logs/notification.log`

Include timestamps, raw stdin JSON, and the final emitted JSON.

If you want, paste your team’s exact `settings.json` hooks section and I’ll merge these two wrappers into a single “hooks repo” layout (with a README, install steps, and a self-test script).

