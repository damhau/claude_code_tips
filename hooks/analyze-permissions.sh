#!/bin/bash
# Analyze permission review logs and suggest whitelisting candidates

JSON_LOG="${1:-$HOME/.claude/logs/permission-review.jsonl}"

if [ ! -f "$JSON_LOG" ]; then
  echo "JSON log file not found: $JSON_LOG"
  echo "Usage: $0 [path-to-permission-review.jsonl]"
  exit 1
fi

echo "=== Permission Review Analysis ==="
echo "Log file: $JSON_LOG"
echo ""

# Count total requests
TOTAL=$(wc -l < "$JSON_LOG")
echo "Total permission requests: $TOTAL"
echo ""

# Count by decision type
echo "--- Decision Types ---"
WHITELIST_COUNT=$(jq -r 'select(.decision_type=="whitelist")' "$JSON_LOG" 2>/dev/null | wc -l | tr -d ' ')
BLACKLIST_COUNT=$(jq -r 'select(.decision_type=="blacklist")' "$JSON_LOG" 2>/dev/null | wc -l | tr -d ' ')
AI_REVIEW_COUNT=$(jq -r 'select(.decision_type=="ai_review")' "$JSON_LOG" 2>/dev/null | wc -l | tr -d ' ')
echo "Whitelisted: $WHITELIST_COUNT"
echo "Blacklisted: $BLACKLIST_COUNT"
echo "AI Reviewed: $AI_REVIEW_COUNT"
echo ""

# Count AI review decisions
echo "--- AI Review Decisions ---"
APPROVED_COUNT=$(jq -r 'select(.decision_type=="ai_review") | select(.decision=="approve")' "$JSON_LOG" 2>/dev/null | wc -l | tr -d ' ')
DENIED_COUNT=$(jq -r 'select(.decision_type=="ai_review") | select(.decision=="deny")' "$JSON_LOG" 2>/dev/null | wc -l | tr -d ' ')
ASKED_COUNT=$(jq -r 'select(.decision_type=="ai_review") | select(.decision=="ask")' "$JSON_LOG" 2>/dev/null | wc -l | tr -d ' ')
echo "Approved: $APPROVED_COUNT"
echo "Denied: $DENIED_COUNT"
echo "Asked (manual): $ASKED_COUNT"
echo ""

# Most common tools
echo "--- Top 10 Most Used Tools ---"
jq -r '.tool_name' "$JSON_LOG" | sort | uniq -c | sort -rn | head -10
echo ""

# Whitelist candidates: Tools that were AI-approved multiple times
echo "--- Whitelist Candidates (AI-approved ≥3 times) ---"
jq -r 'select(.decision_type=="ai_review" and .decision=="approve") | .tool_name' "$JSON_LOG" | \
  sort | uniq -c | sort -rn | awk '$1 >= 3 {print $2 " (approved " $1 " times)"}'
echo ""

# For Bash commands, show most common approved commands
echo "--- Most Common Approved Bash Commands ---"
jq -r 'select(.tool_name=="Bash" and .decision=="approve") | .tool_input.command' "$JSON_LOG" 2>/dev/null | \
  head -c 2000 | \
  awk '{print substr($0,1,80)}' | \
  sort | uniq -c | sort -rn | head -10
echo ""

# Show denied operations
echo "--- Denied Operations ---"
jq -r 'select(.decision=="deny") | "\(.tool_name): \(.reasoning)"' "$JSON_LOG" | head -10
echo ""

# Suggest patterns for whitelist
echo "=== Suggested Whitelist Patterns ==="
echo "# Based on frequently approved tools:"
jq -r 'select(.decision_type=="ai_review" and .decision=="approve") | .tool_name' "$JSON_LOG" | \
  sort | uniq -c | sort -rn | awk '$1 >= 3 {print $2}' | head -10
echo ""
echo "# Based on frequently approved Bash commands:"
jq -r 'select(.tool_name=="Bash" and .decision=="approve") | .tool_input.command' "$JSON_LOG" 2>/dev/null | \
  sed 's/^\([^ ]*\).*/Bash:\1*/' | \
  sort | uniq -c | sort -rn | awk '$1 >= 2 {print $2}' | head -10

echo ""
echo "=== Analysis Complete ==="
