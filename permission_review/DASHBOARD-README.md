# Permission Review Dashboard

A modern web application for reviewing and analyzing AI permission request logs.

## Features

- 📊 **Dashboard Overview**: Statistics cards showing total requests, approvals, asks, and costs
- 🔍 **Advanced Filtering**: Filter by decision type, decision status, and search across commands
- 📋 **Interactive Table**: Click any entry to view detailed information
- 💰 **Cost Tracking**: Monitor AI review costs and token usage
- 🎨 **Modern UI**: Built with Tailwind CSS and Alpine.js for a responsive experience

## Installation

### Option 1: Docker (Recommended)

1. **Make sure templates directory exists in the same folder as Dockerfile**

2. **Build and run with Docker Compose**:
   ```bash
   docker-compose up -d
   ```

3. **Or build and run with Docker**:
   ```bash
   docker build -t permission-review .
   docker run -d -p 5001:5001 \
     -v ~/.claude/logs:/root/.claude/logs:ro \
     permission-review
   ```

4. **Open your browser**:
   Navigate to `http://localhost:5001`

### Option 2: Local Python

1. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

2. **Run the application**:
   ```bash
   python app.py
   ```

3. **Open your browser**:
   Navigate to `http://localhost:5001`

## Usage

### Dashboard
The main dashboard shows:
- Total permission requests processed
- Number of approved/allowed requests
- Number of requests requiring user confirmation (asks)
- Total AI review costs

### Filtering and Search
- **Search**: Search across commands, reasoning, and working directory paths
- **Decision Filter**: Filter by approve, allow, ask, or deny
- **Type Filter**: Filter by AI review, whitelist, blacklist, or manual decisions

### Detailed View
Click any entry to see:
- Full command and description
- Working directory
- Decision reasoning
- AI review metrics (cost, duration, tokens)
- Complete JSON data

## Technology Stack

- **Backend**: Flask (Python)
- **Frontend**: Tailwind CSS, Alpine.js
- **Icons**: Font Awesome
- **Data Source**: JSONL log files

## File Structure

```
permission_review/
├── app.py                       # Flask application
├── requirements.txt             # Python dependencies
├── Dockerfile                   # Docker container definition
├── docker-compose.yml           # Docker Compose configuration
├── .dockerignore               # Docker ignore file
├── templates/
│   └── index.html              # Main dashboard template
└── DASHBOARD-README.md         # This file
```

**Data Source**: `~/.claude/logs/permission-review.jsonl`
