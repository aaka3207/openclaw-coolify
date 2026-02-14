#!/bin/bash
set -e
source "$(dirname "$0")/db.sh"
init_db

NAME="$1"

if [[ -z "$NAME" ]]; then
    echo "Usage: $0 <sandbox_name>"
    exit 1
fi

# Validate input
validate_identifier "$NAME" "sandbox name" || exit 1

# Sanitize for SQL
SAFE_NAME=$(sanitize_sql "$NAME") || exit 1

# Get info
ID=$(query_db "SELECT id FROM sandboxes WHERE name='$SAFE_NAME';")

if [[ -z "$ID" ]]; then
    echo "Sandbox '$NAME' not found in registry."
    exit 1
fi

echo "Deleting Sandbox: $NAME ($ID)"

# Stop/Remove Container
docker rm -f "$ID" || echo "Warning: Container might already be gone."

# Sanitize the ID retrieved from DB before using in delete query
SAFE_ID=$(sanitize_sql "$ID") || exit 1

# Remove from DB
query_db "DELETE FROM sandboxes WHERE id='$SAFE_ID';"

echo "Sandbox deleted."
# Note: We purposely do NOT delete the volume by default to preserve data safety
# unless explicitly requested.
