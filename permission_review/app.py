"""
Permission Review Dashboard
A Flask web application for reviewing and analyzing permission logs
"""

import json
from datetime import datetime
from pathlib import Path
from typing import List, Dict, Any
from collections import Counter

from flask import Flask, render_template, jsonify, request

app = Flask(__name__)

# Path to the JSONL file
JSONL_PATH = Path("~/.claude/logs/permission-review.jsonl").expanduser()


def parse_jsonl() -> List[Dict[str, Any]]:
    """Parse the JSONL file and return a list of entries"""
    entries = []
    with open(JSONL_PATH, "r") as f:
        content = f.read()

    # The file contains multi-line JSON objects separated by lines
    # We need to parse it differently
    current_obj = ""
    brace_count = 0
    entry_num = 0

    for line in content.split("\n"):
        if not line.strip() and brace_count == 0:
            continue

        current_obj += line + "\n"

        # Count braces to track JSON object boundaries
        for char in line:
            if char == "{":
                brace_count += 1
            elif char == "}":
                brace_count -= 1

        # When we've closed all braces, we have a complete JSON object
        if brace_count == 0 and current_obj.strip():
            try:
                entry_num += 1
                entry = json.loads(current_obj)
                entry["_id"] = entry_num
                # Parse reviewer_output if it exists
                if entry.get("reviewer_output") and isinstance(entry["reviewer_output"], str):
                    try:
                        entry["reviewer_output_parsed"] = json.loads(entry["reviewer_output"])
                    except json.JSONDecodeError:
                        entry["reviewer_output_parsed"] = {}
                entries.append(entry)
                current_obj = ""
            except json.JSONDecodeError as e:
                print(f"Error parsing entry {entry_num}: {e}")
                current_obj = ""

    return entries


def get_statistics(entries: List[Dict[str, Any]]) -> Dict[str, Any]:
    """Calculate statistics from entries"""
    total = len(entries)
    decisions = Counter(e.get("decision", "unknown") for e in entries)
    decision_types = Counter(e.get("decision_type", "unknown") for e in entries)
    tools = Counter(e.get("tool_name", "unknown") for e in entries)

    # Calculate total cost
    total_cost = 0
    for entry in entries:
        parsed = entry.get("reviewer_output_parsed", {})
        if isinstance(parsed, dict):
            cost = parsed.get("total_cost_usd", 0)
            if cost:
                total_cost += cost

    return {
        "total": total,
        "decisions": dict(decisions),
        "decision_types": dict(decision_types),
        "tools": dict(tools),
        "total_cost_usd": round(total_cost, 4),
        "avg_cost_usd": round(total_cost / total, 6) if total > 0 else 0,
    }


@app.route("/")
def index():
    """Main dashboard page"""
    entries = parse_jsonl()
    stats = get_statistics(entries)
    return render_template("index.html", stats=stats)


@app.route("/api/entries")
def get_entries():
    """API endpoint to get all entries with filtering"""
    entries = parse_jsonl()

    # Apply filters
    decision_filter = request.args.get("decision")
    decision_type_filter = request.args.get("decision_type")
    tool_filter = request.args.get("tool")
    search_query = request.args.get("search", "").lower()

    filtered = entries

    if decision_filter:
        filtered = [e for e in filtered if e.get("decision") == decision_filter]

    if decision_type_filter:
        filtered = [e for e in filtered if e.get("decision_type") == decision_type_filter]

    if tool_filter:
        filtered = [e for e in filtered if e.get("tool_name") == tool_filter]

    if search_query:
        filtered = [
            e
            for e in filtered
            if search_query in str(e.get("tool_input", {}).get("command", "")).lower()
            or search_query in e.get("reasoning", "").lower()
            or search_query in e.get("cwd", "").lower()
        ]

    # Sort by timestamp descending
    filtered.sort(key=lambda x: x.get("timestamp", ""), reverse=True)

    return jsonify(filtered)


@app.route("/api/entry/<int:entry_id>")
def get_entry(entry_id):
    """API endpoint to get a single entry by ID"""
    entries = parse_jsonl()
    for entry in entries:
        if entry["_id"] == entry_id:
            return jsonify(entry)
    return jsonify({"error": "Entry not found"}), 404


@app.route("/api/stats")
def get_stats():
    """API endpoint to get statistics"""
    entries = parse_jsonl()
    stats = get_statistics(entries)
    return jsonify(stats)


if __name__ == "__main__":
    app.run(debug=True, host="0.0.0.0", port=5000)
