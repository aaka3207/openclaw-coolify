#!/bin/bash
# execute-workflow.sh - Execute an n8n workflow by ID
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/n8n-api.sh"

WORKFLOW_ID=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --id) WORKFLOW_ID="$2"; shift 2 ;;
    *) echo "Usage: $0 --id <workflow_id>" >&2; exit 1 ;;
  esac
done

if [ -z "$WORKFLOW_ID" ]; then
  echo "ERROR: --id is required" >&2
  exit 1
fi

# Validate workflow ID (alphanumeric, may include hyphens in some n8n versions)
if [[ ! "$WORKFLOW_ID" =~ ^[a-zA-Z0-9_-]+$ ]]; then
  echo "ERROR: Invalid workflow ID format (must be alphanumeric)" >&2
  exit 1
fi

RESPONSE=$(n8n_api POST "/workflows/$WORKFLOW_ID/run" '{}')
echo "Executed workflow $WORKFLOW_ID"
echo "$RESPONSE" | jq .
