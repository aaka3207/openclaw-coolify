#!/usr/bin/env bash
# Test NOVA memory catch-up processor manually
# Run on server: bash test-nova-catchup.sh
set -euo pipefail

CONTAINER=$(sudo docker ps --filter "label=com.docker.compose.project=ukwkggw4o8go0wgg804oc4oo" --filter "name=openclaw-" --format "{{.Names}}" | head -1)

if [ -z "$CONTAINER" ]; then
  echo "ERROR: OpenClaw container not found"
  exit 1
fi

echo "Container: $CONTAINER"

# Start cron if not running
if ! sudo docker exec "$CONTAINER" pgrep -x cron >/dev/null 2>&1; then
  echo "Starting cron daemon..."
  sudo docker exec "$CONTAINER" /usr/sbin/cron
fi

# Extract env vars from the crontab entry
ENV_VARS=$(sudo docker exec "$CONTAINER" crontab -l | grep memory-catchup | sed 's|^\*/5 \* \* \* \* ||' | sed 's| bash /data/.*||')

echo "Running memory catchup..."
sudo docker exec "$CONTAINER" bash -c "$ENV_VARS bash /data/clawd/nova-memory/scripts/memory-catchup.sh"
