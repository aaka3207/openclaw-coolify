#!/bin/bash
# activate-workflow.sh - Activate or deactivate an n8n workflow
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/n8n-api.sh"

WORKFLOW_ID=""
ACTIVE=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --id) WORKFLOW_ID="$2"; shift 2 ;;
    --active) ACTIVE="$2"; shift 2 ;;
    *) echo "Usage: $0 --id <workflow_id> --active <true|false>" >&2; exit 1 ;;
  esac
done

if [ -z "$WORKFLOW_ID" ]; then
  echo "ERROR: --id is required" >&2
  exit 1
fi

if [ -z "$ACTIVE" ]; then
  echo "ERROR: --active is required (true or false)" >&2
  exit 1
fi

# Validate workflow ID
if [[ ! "$WORKFLOW_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "ERROR: Invalid workflow ID format" >&2
  exit 1
fi

# Validate active value
if [[ "$ACTIVE" != "true" && "$ACTIVE" != "false" ]]; then
  echo "ERROR: --active must be 'true' or 'false'" >&2
  exit 1
fi

RESPONSE=$(n8n_api PATCH "/workflows/$WORKFLOW_ID" "{\"active\": $ACTIVE}")
echo "Workflow $WORKFLOW_ID active=$ACTIVE"
echo "$RESPONSE" | jq .
