# Permission Review JSON Logging

## Overview
The permission hook now logs all requests and decisions to a JSONL (JSON Lines) file for analysis.

## Log Location
`~/.claude/logs/permission-review.jsonl`

## Log Format
Each line is a JSON object with:
```json
{
  "timestamp": "2026-02-18T13:41:58+01:00",
  "tool_name": "Bash",
  "tool_input": {
    "command": "docker build -t democlaude2 .",
    "description": "Build the Docker image"
  },
  "cwd": "/home/damien/code/perso/democlaude2",
  "decision_type": "ai_review",
  "decision": "approve",
  "reasoning": "Standard Docker build command...",
  "reviewer_output": "{...full AI response...}"
}
```

## Decision Types
- `whitelist` - Auto-approved by whitelist
- `blacklist` - Auto-denied by blacklist
- `ai_review` - Reviewed by AI (decisions: approve/deny/ask)

## Analyzing Logs

Run the analysis script:
```bash
~/.claude/hooks/analyze-permissions.sh
```

Or specify a custom log file:
```bash
~/.claude/hooks/analyze-permissions.sh /path/to/custom.jsonl
```

### Analysis Output
- Total requests
- Decision type breakdown
- Most common tools
- Whitelist candidates (tools approved ≥3 times)
- Common Bash commands
- Denied operations
- Suggested whitelist patterns

## Manual Analysis

### Count approvals by tool name
```bash
jq -r 'select(.decision=="approve") | .tool_name' ~/.claude/logs/permission-review.jsonl | sort | uniq -c | sort -rn
```

### Find all denied operations
```bash
jq 'select(.decision=="deny")' ~/.claude/logs/permission-review.jsonl
```

### Extract all Bash commands that were approved
```bash
jq -r 'select(.tool_name=="Bash" and .decision=="approve") | .tool_input.command' ~/.claude/logs/permission-review.jsonl
```

### Find patterns that should be whitelisted
```bash
jq -r 'select(.decision=="approve") | "\(.tool_name):\(.tool_input.command // .tool_input.file_path // "")"' ~/.claude/logs/permission-review.jsonl | grep -v ':$' | sort | uniq -c | sort -rn
```

## Tips

1. **Review regularly**: Run the analysis script weekly to identify patterns
2. **Whitelist common operations**: Commands approved 3+ times are good candidates
3. **Monitor denials**: Check denied operations to ensure they're actually dangerous
4. **Backup the log**: The JSONL file contains valuable security audit data
