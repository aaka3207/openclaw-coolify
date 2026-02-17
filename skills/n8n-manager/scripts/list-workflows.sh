#!/bin/bash
# list-workflows.sh - List all n8n workflows
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/n8n-api.sh"

RESPONSE=$(n8n_api GET "/workflows")
echo "$RESPONSE" | jq -r '.data[] | "ID: \(.id) | Name: \(.name) | Active: \(.active)"'
