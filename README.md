# Claude Code Permission Review System

A comprehensive permission review and security monitoring system for Claude Code (VS Code with Claude AI integration). This toolkit provides automated whitelist/blacklist filtering, AI-powered security review, and detailed logging of all tool execution requests.

## What Does This Do?

When Claude Code wants to execute a tool (run bash commands, edit files, etc.), this system:

1. **Checks whitelist** - Auto-approves trusted operations
2. **Checks blacklist** - Auto-denies dangerous operations  
3. **AI Security Review** - Uses Claude Opus to review uncertain operations
4. **Logs everything** - Records all decisions in JSON format for audit and analysis
5. **Sends notifications** - Alerts you when manual review is needed (Windows toast notifications)

This gives you granular control and visibility over what Claude is doing in your workspace.

## Components

### Core Scripts

#### `permission-review.sh` 
**The main permission review hook**

This script intercepts every tool call Claude makes and decides whether to allow, deny, or ask for manual approval.

**Decision Flow:**
```
Tool Call Request
    ↓
Whitelist Check → Auto-approve if matched
    ↓
Blacklist Check → Auto-deny if matched
    ↓
MCP Write Detection → Ask user for external service modifications
    ↓
AI Security Review → Claude Opus analyzes the request
    ↓
{approve, deny, ask} → Log decision + Execute or block
```

**Features:**
- Pattern matching with wildcards (`*`, `?`)
- Content-aware filtering (e.g., `Bash:git *` matches git commands)
- Structured JSON logging to `~/.claude/logs/permission-review.jsonl`
- Windows toast notifications for manual review requests
- AI reviewer using Claude Opus 4.5 with security-focused prompts

#### `notify-wrapper.sh`
**Notification hook for Windows (WSL)**

Captures notification events from Claude and displays them as Windows toast notifications using PowerShell's BurntToast module.

**Features:**
- Logs all notifications to `~/.claude/logs/notification.log`
- Shows project context in notification messages
- Tracks notification timing and duration
- Returns context to Claude for awareness

#### `analyze-permissions.sh`
**Log analysis and whitelist recommendation tool**

Analyzes the permission review JSON logs to help you optimize your whitelist/blacklist rules.

**Output includes:**
- Total permission requests and decision breakdown
- Top 10 most used tools
- Whitelist candidates (tools approved ≥3 times)
- Most common approved Bash commands
- All denied operations with reasoning
- Suggested whitelist patterns based on usage

### Configuration Files

#### `whitelist.txt`
Auto-approve patterns for trusted operations.

**Syntax:**
```bash
# Simple tool matching - approves ANY use of this tool
ToolName

# Content matching - approves only when pattern matches
ToolName:content_pattern

# Examples:
read_file                    # Always allow file reading
Bash:git *                   # Allow all git commands
Bash:npm test*               # Allow npm test variations
Write:*/test/*               # Allow writes only in test directories
```

#### `blacklist.txt`
Auto-deny patterns for dangerous operations.

**Syntax:**
```bash
# Block specific dangerous commands
Bash:*cat*~/.aws/credentials*
Bash:rm -rf /*
Bash:curl * | bash*

# Block dangerous file operations
Write:~/.ssh/*
Edit:/etc/*

# Block entire tools
mcp_github_delete_repository
```

## Installation

### Prerequisites

1. **Claude CLI** - Install the Claude command-line tool
2. **jq** - JSON processor
   ```bash
   # Ubuntu/Debian
   sudo apt install jq
   
   # macOS
   brew install jq
   ```
3. **PowerShell BurntToast Module** (Windows only, for notifications)
   ```powershell
   Install-Module -Name BurntToast
   ```

### Step 1: Create Hook Directory

```bash
mkdir -p ~/.claude/hooks
mkdir -p ~/.claude/logs
```

### Step 2: Copy Scripts

Copy all scripts to the hooks directory:

```bash
cp hooks/permission-review.sh ~/.claude/hooks/
cp hooks/notify-wrapper.sh ~/.claude/hooks/
cp hooks/analyze-permissions.sh ~/.claude/hooks/
cp hooks/whitelist.txt ~/.claude/hooks/
cp hooks/blacklist.txt ~/.claude/hooks/
```

### Step 3: Make Scripts Executable

```bash
chmod +x ~/.claude/hooks/permission-review.sh
chmod +x ~/.claude/hooks/notify-wrapper.sh
chmod +x ~/.claude/hooks/analyze-permissions.sh
```

### Step 4: Configure Claude Code Hooks

Add hook configuration to Claude's settings. The location depends on your setup:

**VS Code Settings** (`settings.json`):
```json
{
  "claude.hooks": {
    "permissionRequest": {
      "command": "/home/YOUR_USERNAME/.claude/hooks/permission-review.sh"
    },
    "notification": {
      "command": "/home/YOUR_USERNAME/.claude/hooks/notify-wrapper.sh"
    }
  }
}
```

**OR Claude CLI Config** (`~/.claude/config.json`):
```json
{
  "hooks": {
    "permissionRequest": {
      "command": "/home/YOUR_USERNAME/.claude/hooks/permission-review.sh"
    },
    "notification": {
      "command": "/home/YOUR_USERNAME/.claude/hooks/notify-wrapper.sh"
    }
  }
}
```

> **Important:** Replace `/home/YOUR_USERNAME` with your actual home directory path. Use `echo $HOME` to find it.

### Step 5: Customize Whitelist/Blacklist

Edit the configuration files to match your workflow:

```bash
# Edit whitelist
nano ~/.claude/hooks/whitelist.txt

# Edit blacklist  
nano ~/.claude/hooks/blacklist.txt
```

### Step 6: Test the Installation

Restart VS Code and ask Claude to run a simple command:

```
Can you run 'ls -la' in the terminal?
```

You should see the permission request being processed. Check the logs:

```bash
cat ~/.claude/logs/permission-review.log
cat ~/.claude/logs/permission-review.jsonl
```

## Usage

### Daily Workflow

The scripts work automatically once installed. Claude's tool calls are intercepted transparently:

1. **Whitelisted tools** execute immediately
2. **Blacklisted tools** are blocked with a message
3. **Uncertain tools** trigger AI review or manual approval
4. **MCP write operations** always ask for confirmation

### Analyzing Your Logs

Run the analysis script regularly to optimize your configuration:

```bash
~/.claude/hooks/analyze-permissions.sh
```

Example output:
```
=== Permission Review Analysis ===
Log file: /home/user/.claude/logs/permission-review.jsonl

Total permission requests: 847

--- Decision Types ---
Whitelisted: 612
Blacklisted: 3
AI Reviewed: 232

--- Whitelist Candidates (AI-approved ≥3 times) ---
Write (approved 45 times)
Edit (approved 38 times)
Bash (approved 89 times)
```

### Manual Log Queries

**Find all denied operations:**
```bash
jq 'select(.decision=="deny")' ~/.claude/logs/permission-review.jsonl
```

**Count approvals by tool:**
```bash
jq -r 'select(.decision=="approve") | .tool_name' ~/.claude/logs/permission-review.jsonl | \
  sort | uniq -c | sort -rn
```

**Extract approved Bash commands:**
```bash
jq -r 'select(.tool_name=="Bash" and .decision=="approve") | .tool_input.command' \
  ~/.claude/logs/permission-review.jsonl | head -20
```

**Find patterns for whitelist:**
```bash
jq -r 'select(.decision=="approve") | 
  "\(.tool_name):\(.tool_input.command // .tool_input.file_path // "")"' \
  ~/.claude/logs/permission-review.jsonl | \
  grep -v ':$' | sort | uniq -c | sort -rn | head -20
```

## Configuration Details

### AI Reviewer Model

The AI reviewer uses Claude Opus 4.5. Change the model in `permission-review.sh`:

```bash
REVIEWER_MODEL="claude-opus-4-5-20251101"
```

### AI Review Guidelines

The AI reviewer is instructed to:

**APPROVE:**
- Standard development commands (npm, git, make, cargo, etc.)
- File operations within the project directory
- Linters, formatters, type checkers, test suites
- Non-destructive CLI tools
- GET requests to known/public URLs

**DENY (hard block):**
- Accessing credentials (`~/.ssh`, `~/.aws`, API keys)
- Exfiltrating secrets to external services
- Mass deletion outside safe targets
- Obfuscated commands (`base64 decode | bash`)
- `curl | bash` patterns

**ASK (manual review):**
- Uncertain commands
- POST requests
- `sudo` or privilege escalation
- Force pushing to repos
- Destructive database operations

### Pattern Matching

Both whitelist and blacklist support:

1. **Tool name only:** `Bash`, `Write`, `Edit`
2. **Content patterns:** `ToolName:pattern`
   - For `Bash`: matches against the command
   - For `Write`/`Edit`: matches against the file path
3. **Wildcards:** 
   - `*` = any characters
   - `?` = single character

**Examples:**
```bash
# Whitelist all git commands
Bash:git *

# Whitelist npm install variants
Bash:npm install*
Bash:npm i*

# Allow writes only in specific directories
Write:*/src/*
Write:*/test/*

# Blacklist credential access
Bash:*cat*~/.aws/*
Bash:*echo*$SSH_KEY*
```

## Customization

### Windows-Specific Modifications

The scripts include Windows toast notifications via PowerShell. If you're not on Windows/WSL, you can:

**Remove notification code** in `permission-review.sh` (around line 260):
```bash
# Comment out or remove this block:
# powershell.exe -NoProfile -Command \
#   "Import-Module BurntToast -ErrorAction SilentlyContinue; ..." \
#   >/dev/null 2>&1 || true
```

**Or replace with Linux notification:**
```bash
notify-send "Claude" "Permission needs review: ${TOOL_NAME}"
```

### macOS Notifications

Replace PowerShell calls with:
```bash
osascript -e "display notification \"${TOOL_NAME} needs review\" with title \"Claude\""
```

### Add Custom Analysis

Extend `analyze-permissions.sh` with your own queries:

```bash
echo "--- Custom Analysis ---"
jq -r 'select(.tool_name=="Bash" and .cwd | contains("production")) | 
  .tool_input.command' "$JSON_LOG" | head -10
```

## Security Best Practices

1. **Start restrictive** - Begin with a minimal whitelist and expand based on analysis
2. **Review logs weekly** - Use `analyze-permissions.sh` to identify patterns
3. **Never whitelist wildcards for sensitive tools** - Be specific
4. **Monitor denied operations** - Check if legitimate operations are being blocked
5. **Backup your logs** - The JSONL file is valuable audit data
6. **Review blacklist patterns** - Ensure critical operations are blocked
7. **Test changes** - After modifying whitelist/blacklist, monitor the first session carefully

### Example Starter Whitelist

```bash
# Safe read-only operations
read_file
grep_search
semantic_search
file_search
list_dir
get_errors

# Safe development commands
Bash:git status*
Bash:git diff*
Bash:git log*
Bash:npm test*
Bash:docker ps*
Bash:ls *
Bash:cat *

# Project-specific writes
Write:*/src/*
Write:*/test/*
Edit:*/src/*
Edit:*/test/*
```

### Example Starter Blacklist

```bash
# Credential access
Bash:*cat*~/.aws/*
Bash:*cat*~/.ssh/*
Bash:*cat*.env*
Bash:*echo*$AWS*
Bash:*echo*$SSH*

# Dangerous operations
Bash:rm -rf /*
Bash:sudo rm *
Bash:curl * | bash*
Bash:wget * | sh*
Bash:eval *

# System modifications
Write:~/.ssh/*
Write:/etc/*
Edit:~/.bashrc*
Edit:~/.zshrc*
```

## Troubleshooting

### Hooks not executing

**Check hook configuration:**
```bash
# For VS Code
cat ~/.config/Code/User/settings.json | grep claude.hooks

# For Claude CLI  
cat ~/.claude/config.json | grep hooks
```

**Check script permissions:**
```bash
ls -l ~/.claude/hooks/*.sh
# Should show -rwxr-xr-x (executable)
```

### AI reviewer failing

**Check Claude CLI is installed:**
```bash
which claude
claude --version
```

**Check logs for errors:**
```bash
tail -f ~/.claude/logs/permission-review.log
```

**Test reviewer manually:**
```bash
claude -p --model claude-opus-4-5-20251101 "Say hello"
```

### No notifications appearing

**Windows/WSL - Check BurntToast:**
```powershell
Import-Module BurntToast
New-BurntToastNotification -Text "Test", "Notification test"
```

**Check notification log:**
```bash
tail -f ~/.claude/logs/notification.log
```

### jq command not found

Install jq:
```bash
# Ubuntu/Debian
sudo apt update && sudo apt install jq

# macOS
brew install jq
```

## Advanced Usage

### Multiple Whitelists for Different Projects

Create project-specific whitelists:

```bash
# In permission-review.sh, add before the main whitelist check:
PROJECT_WHITELIST="$CWD/.claude-whitelist.txt"
if [ -f "$PROJECT_WHITELIST" ]; then
  # Check project whitelist first
  while IFS= read -r pattern; do
    # ... same logic as main whitelist
  done < "$PROJECT_WHITELIST"
fi
```

### Temporary Whitelist Override

Add an environment variable check:

```bash
# In permission-review.sh, add after variable declarations:
if [ "${CLAUDE_SKIP_REVIEW:-}" = "1" ]; then
  log "CLAUDE_SKIP_REVIEW set -> auto-approve"
  exit 0
fi
```

Use it:
```bash
CLAUDE_SKIP_REVIEW=1 code .
```

### Integration with CI/CD

Log permission requests in CI environments:

```bash
# Add to permission-review.sh:
if [ -n "${CI:-}" ]; then
  echo "::warning::Claude tool request: $TOOL_NAME"
  # Auto-approve in CI but log for review
  exit 0
fi
```

## Additional Resources

- **JSON Logging Documentation:** See [JSON-LOGGING.md](hooks/JSON-LOGGING.md)
- **Claude CLI Documentation:** `claude --help`
- **jq Manual:** https://stedolan.github.io/jq/manual/

## Contributing

To improve these scripts:

1. Add new patterns to whitelist/blacklist
2. Enhance the AI reviewer prompt
3. Add new analysis queries to `analyze-permissions.sh`
4. Submit cross-platform compatibility improvements

## License

Feel free to use, modify, and distribute these scripts as needed.

## Disclaimer

These scripts are security tools but not foolproof. Always review the logs and monitor Claude's actions, especially in sensitive environments. The AI reviewer is helpful but not infallible - when in doubt, it will ask for your confirmation.

---

**Happy coding with confidence and visibility!**
