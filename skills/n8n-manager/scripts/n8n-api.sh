#!/bin/bash
# n8n-api.sh - Base API helper for n8n REST API
# Sourced by action scripts, not run directly.
# Auth: reads API key from credential file (written by bootstrap.sh)
# Docs: https://docs.n8n.io/api/

N8N_BASE_URL="${N8N_API_URL:-http://192.168.1.100:5678}"
N8N_API_KEY_FILE="/data/.openclaw/credentials/N8N_API_KEY"

if [ ! -f "$N8N_API_KEY_FILE" ]; then
  echo "ERROR: N8N_API_KEY not found at $N8N_API_KEY_FILE" >&2
  echo "Ensure N8N_API_KEY is set in BWS and the container has been restarted." >&2
  exit 1
fi

N8N_API_KEY=$(cat "$N8N_API_KEY_FILE")

if [ -z "$N8N_API_KEY" ]; then
  echo "ERROR: N8N_API_KEY file is empty" >&2
  exit 1
fi

# n8n_api METHOD ENDPOINT [DATA]
# Example: n8n_api GET "/workflows"
# Example: n8n_api POST "/workflows" '{"name":"test"}'
n8n_api() {
  local method="$1"
  local endpoint="$2"
  local data="${3:-}"

  local url="${N8N_BASE_URL}/api/v1${endpoint}"
  local args=(-s -f -X "$method"
    -H "X-N8N-API-KEY: $N8N_API_KEY"
    -H "Content-Type: application/json"
    -w "\n%{http_code}"
    "$url")

  if [ -n "$data" ]; then
    args+=(-d "$data")
  fi

  local response
  response=$(curl "${args[@]}" 2>&1)
  local exit_code=$?

  if [ $exit_code -ne 0 ]; then
    echo "ERROR: curl failed (exit $exit_code) for $method $url" >&2
    echo "$response" >&2
    return 1
  fi

  # Extract HTTP status code from last line
  local http_code
  http_code=$(echo "$response" | tail -1)
  local body
  body=$(echo "$response" | sed '$d')

  if [[ "$http_code" -ge 400 ]]; then
    echo "ERROR: n8n API returned HTTP $http_code for $method $endpoint" >&2
    echo "$body" >&2
    return 1
  fi

  echo "$body"
}
