#!/bin/bash
# create-workflow.sh - Create a new n8n workflow
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/n8n-api.sh"

NAME=""
FILE=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --name) NAME="$2"; shift 2 ;;
    --file) FILE="$2"; shift 2 ;;
    *) echo "Usage: $0 --name <name> [--file <workflow.json>]" >&2; exit 1 ;;
  esac
done

if [ -z "$NAME" ]; then
  echo "ERROR: --name is required" >&2
  exit 1
fi

# Read workflow JSON from file or stdin
if [ -n "$FILE" ]; then
  if [ ! -f "$FILE" ]; then
    echo "ERROR: File not found: $FILE" >&2
    exit 1
  fi
  WORKFLOW_JSON=$(cat "$FILE")
else
  if [ -t 0 ]; then
    echo "ERROR: Provide workflow JSON via --file or stdin" >&2
    exit 1
  fi
  WORKFLOW_JSON=$(cat)
fi

# Ensure name is set in the JSON payload
WORKFLOW_JSON=$(echo "$WORKFLOW_JSON" | jq --arg name "$NAME" '.name = $name')

RESPONSE=$(n8n_api POST "/workflows" "$WORKFLOW_JSON")
WORKFLOW_ID=$(echo "$RESPONSE" | jq -r '.id')
echo "Created workflow: ID=$WORKFLOW_ID Name=$NAME"
echo "$RESPONSE" | jq .
