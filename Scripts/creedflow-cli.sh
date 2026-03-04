#!/usr/bin/env bash
# creedflow-cli.sh — Simple CLI wrapper for CreedFlow webhook API
# Usage:
#   creedflow-cli status                                    — Check server status
#   creedflow-cli create-task --project <id> --title <title> [--agent <type>] [--description <desc>]
#
# Configuration: ~/.creedflow/cli.conf
#   CREEDFLOW_HOST=127.0.0.1
#   CREEDFLOW_PORT=8080
#   CREEDFLOW_API_KEY=

set -euo pipefail

# Defaults
CREEDFLOW_HOST="${CREEDFLOW_HOST:-127.0.0.1}"
CREEDFLOW_PORT="${CREEDFLOW_PORT:-8080}"
CREEDFLOW_API_KEY="${CREEDFLOW_API_KEY:-}"

# Load config file if exists
CONFIG_FILE="${HOME}/.creedflow/cli.conf"
if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

BASE_URL="http://${CREEDFLOW_HOST}:${CREEDFLOW_PORT}"

# Build auth header
AUTH_HEADER=""
if [[ -n "$CREEDFLOW_API_KEY" ]]; then
  AUTH_HEADER="-H X-API-Key: ${CREEDFLOW_API_KEY}"
fi

usage() {
  cat <<EOF
CreedFlow CLI — Interact with CreedFlow webhook API

Usage:
  $(basename "$0") status
  $(basename "$0") create-task --project <id> --title <title> [--agent <type>] [--description <desc>]

Options:
  --project, -p     Project ID (required for create-task)
  --title, -t       Task title (required for create-task)
  --agent, -a       Agent type (default: coder)
  --description, -d Task description (optional)
  --help, -h        Show this help

Configuration:
  Create ~/.creedflow/cli.conf with:
    CREEDFLOW_HOST=127.0.0.1
    CREEDFLOW_PORT=8080
    CREEDFLOW_API_KEY=your-api-key

  Or set environment variables directly.
EOF
  exit 0
}

cmd_status() {
  if [[ -n "$AUTH_HEADER" ]]; then
    curl -s ${AUTH_HEADER} "${BASE_URL}/api/status"
  else
    curl -s "${BASE_URL}/api/status"
  fi
  echo ""
}

cmd_create_task() {
  local project_id=""
  local title=""
  local agent_type="coder"
  local description=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --project|-p) project_id="$2"; shift 2 ;;
      --title|-t) title="$2"; shift 2 ;;
      --agent|-a) agent_type="$2"; shift 2 ;;
      --description|-d) description="$2"; shift 2 ;;
      *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
  done

  if [[ -z "$project_id" || -z "$title" ]]; then
    echo "Error: --project and --title are required" >&2
    exit 1
  fi

  local payload
  payload=$(cat <<ENDJSON
{
  "projectId": "${project_id}",
  "title": "${title}",
  "description": "${description}",
  "agentType": "${agent_type}"
}
ENDJSON
)

  local curl_args=(-s -X POST "${BASE_URL}/api/tasks" -H "Content-Type: application/json" -d "$payload")
  if [[ -n "$CREEDFLOW_API_KEY" ]]; then
    curl_args+=(-H "X-API-Key: ${CREEDFLOW_API_KEY}")
  fi

  curl "${curl_args[@]}"
  echo ""
}

# Parse command
if [[ $# -eq 0 ]]; then
  usage
fi

case "$1" in
  status)
    shift
    cmd_status
    ;;
  create-task)
    shift
    cmd_create_task "$@"
    ;;
  --help|-h)
    usage
    ;;
  *)
    echo "Unknown command: $1" >&2
    echo "Run '$(basename "$0") --help' for usage." >&2
    exit 1
    ;;
esac
