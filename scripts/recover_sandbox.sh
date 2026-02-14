#!/bin/bash
# recover_sandbox.sh - OpenClaw Recovery Protocol
# Auto-runs on startup to restore sandboxes and tunnels from state

STATE_FILE="${OPENCLAW_STATE_DIR:-/data/.openclaw}/state/sandboxes.json"
LOG_FILE="${OPENCLAW_WORKSPACE:-/data/openclaw-workspace}/recovery.log"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Validate container ID format (Docker hash or openclaw-prefixed name)
validate_container_id() {
    local id="$1"
    if [[ "$id" =~ ^[a-f0-9]{12,64}$ ]]; then
        return 0  # Docker short/long hash
    elif [[ "$id" =~ ^(openclaw-sandbox-|moltbot-essa-)[a-zA-Z0-9._-]+$ ]]; then
        return 0  # Named container with expected prefix
    else
        return 1
    fi
}

# Verify container belongs to openclaw (has managed label)
verify_managed_container() {
    local id="$1"
    local label
    label=$(docker inspect -f '{{index .Config.Labels "openclaw.managed"}}' "$id" 2>/dev/null)
    if [ "$label" = "true" ]; then
        return 0
    fi
    # Also check SANDBOX_CONTAINER label
    label=$(docker inspect -f '{{index .Config.Labels "SANDBOX_CONTAINER"}}' "$id" 2>/dev/null)
    if [ "$label" = "true" ]; then
        return 0
    fi
    return 1
}

if [ ! -f "$STATE_FILE" ]; then
  log "No state file found at $STATE_FILE. Nothing to recover."
  exit 0
fi

log "Starting Sandbox Recovery..."

# Iterate through sandboxes in state using jq
SANDBOX_IDS=$(jq -r '.sandboxes | keys[]' "$STATE_FILE" 2>/dev/null)

for id in $SANDBOX_IDS; do
  log "Checking sandbox: $id"

  # SECURITY: Validate container ID format
  if ! validate_container_id "$id"; then
    log "REJECTED: Invalid container ID format: $id"
    continue
  fi

  # Extract details
  PROJECT=$(jq -r ".sandboxes[\"$id\"].project" "$STATE_FILE")
  STATUS=$(jq -r ".sandboxes[\"$id\"].status" "$STATE_FILE")

  # Check if docker container exists
  if ! docker ps -a --format '{{.Names}}' | grep -q "^${id}$"; then
    log "Container $id not found in Docker. Marking as lost/stopped in state."
    continue
  fi

  # SECURITY: Verify container has openclaw-managed label
  if ! verify_managed_container "$id"; then
    log "REJECTED: Container $id is not openclaw-managed (missing label). Skipping."
    continue
  fi

  # Check if running
  IS_RUNNING=$(docker inspect -f '{{.State.Running}}' "$id" 2>/dev/null)

  if [ "$IS_RUNNING" != "true" ]; then
    log "Container $id is stopped. Attempting restart..."
    if docker start "$id"; then
      log "Restarted container $id"
    else
      log "Failed to restart $id"
      continue
    fi
  else
    log "Container $id is running."
  fi
done

log "Recovery scan complete."
