#!/bin/bash
set -e

# Load DB helper
source "$(dirname "$0")/db.sh"
init_db

# Args
STACK=""
TITLE=""

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --stack) STACK="$2"; shift ;;
        --title) TITLE="$2"; shift ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

if [[ -z "$STACK" || -z "$TITLE" ]]; then
    echo "Usage: ./create_sandbox.sh --stack <stack> --title <title>"
    exit 1
fi

# Validate inputs before any processing
validate_identifier "$STACK" "stack" || exit 1

# Naming: moltbot-essa-{lang}-{project_title}
# Normalize title to be url-safe
SAFE_TITLE=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/ /g' | xargs | tr ' ' '-')

if [[ -z "$SAFE_TITLE" ]]; then
    echo "ERROR: Title '$TITLE' produces empty safe name after normalization." >&2
    exit 1
fi

validate_identifier "$SAFE_TITLE" "normalized title" || exit 1

CONTAINER_NAME="moltbot-essa-${STACK}-${SAFE_TITLE}"
VOLUME_NAME="${CONTAINER_NAME}-data"

echo "Creating Sandbox: $CONTAINER_NAME"

# Sanitize values for SQL
SAFE_CONTAINER_NAME=$(sanitize_sql "$CONTAINER_NAME") || exit 1

# Check if exists
EXISTING=$(query_db "SELECT id FROM sandboxes WHERE name='$SAFE_CONTAINER_NAME';")
if [[ -n "$EXISTING" ]]; then
    echo "Sandbox '$CONTAINER_NAME' already exists."
    exit 1
fi

# Define Stack Configs
DOCKER_IMAGE=""
INIT_CMD=""
INTERNAL_PORT="3000" # Default

case $STACK in
    nextjs)
        DOCKER_IMAGE="oven/bun:1"
        INIT_CMD="bun create next-app . --typescript --no-eslint --no-tailwind --no-src-dir --import-alias '@/*' && bun dev --port 3000 --hostname 0.0.0.0"
        INTERNAL_PORT="3000"
        ;;
    fastapi)
        DOCKER_IMAGE="python:3.11-slim"
        INIT_CMD="pip install uv && uv venv && source .venv/bin/activate && uv pip install fastapi uvicorn[standard] && echo 'from fastapi import FastAPI\napp = FastAPI()\n@app.get(\"/\")\ndef read_root(): return {\"Hello\": \"World\"}' > main.py && uvicorn main:app --host 0.0.0.0 --port 8000"
        INTERNAL_PORT="8000"
        ;;
    laravel)
        DOCKER_IMAGE="bitnami/laravel:latest"
        INIT_CMD="" # Bitnami image handles start
        INTERNAL_PORT="8000"
        ;;
    *)
        echo "Stack '$STACK' not fully automated yet. Using generic alpine."
        DOCKER_IMAGE="alpine:latest"
        INIT_CMD="sleep infinity"
        ;;
esac

# Validate port
validate_port "$INTERNAL_PORT" || exit 1

# Create Volume
echo "Creating volume $VOLUME_NAME..."
docker volume create "$VOLUME_NAME" >/dev/null

# Run Container
echo "Running container..."
CID=$(docker run -d \
    --name "$CONTAINER_NAME" \
    --restart unless-stopped \
    --label "openclaw.managed=true" \
    --label "SANDBOX_CONTAINER=true" \
    -v "$VOLUME_NAME":/app \
    -w /app \
    "$DOCKER_IMAGE" \
    /bin/sh -c "$INIT_CMD")

echo "Container ID: $CID"

# Setup Tunnel
CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$CID")
TUNNEL_LOG="/tmp/${CONTAINER_NAME}.tunnel.log"

echo "Starting Quick Tunnel for http://$CONTAINER_IP:$INTERNAL_PORT..."
nohup cloudflared tunnel --url http://"$CONTAINER_IP":"$INTERNAL_PORT" > "$TUNNEL_LOG" 2>&1 &
TUNNEL_PID=$!

# Wait for URL
sleep 5
TUNNEL_URL=$(grep -o 'https://.*\.trycloudflare\.com' "$TUNNEL_LOG" | head -n 1)

if [[ -z "$TUNNEL_URL" ]]; then
    TUNNEL_URL="(Tunnel failed to start or too slow: check $TUNNEL_LOG)"
fi

echo "Public URL: $TUNNEL_URL"

# Record in DB with sanitized values
SAFE_CID=$(sanitize_sql "$CID") || exit 1
SAFE_STACK=$(sanitize_sql "$STACK") || exit 1
SAFE_TUNNEL_URL=$(sanitize_sql "$TUNNEL_URL") || exit 1
SAFE_VOLUME_NAME=$(sanitize_sql "$VOLUME_NAME") || exit 1

query_db "INSERT INTO sandboxes (id, name, stack, port, tunnel_url, volume_path) VALUES ('$SAFE_CID', '$SAFE_CONTAINER_NAME', '$SAFE_STACK', $INTERNAL_PORT, '$SAFE_TUNNEL_URL', '$SAFE_VOLUME_NAME');"

echo "Sandbox '$CONTAINER_NAME' created and registered."
