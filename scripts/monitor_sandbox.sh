#!/bin/bash
# monitor_sandbox.sh - OpenClaw Health Monitor
# Runs in background to check sandbox health
# SECURITY: References recovery script from /app/scripts/ (read-only image path)

LOG_FILE="${OPENCLAW_WORKSPACE:-/data/openclaw-workspace}/monitor.log"
RECOVERY_SCRIPT="/app/scripts/recover_sandbox.sh"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" >> "$LOG_FILE"
}

log "Health Monitor Started"

while true; do
  # Run every 5 minutes
  sleep 300

  log "Performing health check..."

  # Run recovery script from read-only image path
  if [ -f "$RECOVERY_SCRIPT" ]; then
    bash "$RECOVERY_SCRIPT" >> "$LOG_FILE" 2>&1
  else
    log "ERROR: Recovery script not found at $RECOVERY_SCRIPT"
  fi
done
