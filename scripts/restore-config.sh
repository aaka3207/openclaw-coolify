#!/usr/bin/env bash
# restore-config.sh — Delete corrupted openclaw.json and restart the container.
# bootstrap.sh detects the missing file and regenerates the full Phase 8 config.
#
# Usage (on server 192.168.1.100):
#   sudo bash /home/ameer/restore-config.sh
set -e

# ---------------------------------------------------------------------------
# Guards
# ---------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: This script must be run as root (sudo bash $0)"
  exit 1
fi

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
CONFIG_PATH="/var/lib/docker/volumes/ukwkggw4o8go0wgg804oc4oo_openclaw-data/_data/.openclaw/openclaw.json"
BACKUP_PATH="${CONFIG_PATH}.corrupted.bak"
CONTAINER_FILTER="openclaw-ukwkggw4o8go0wgg804oc4oo"

# ---------------------------------------------------------------------------
# Step 1: Back up corrupted config (if non-empty)
# ---------------------------------------------------------------------------
if [ -f "$CONFIG_PATH" ] && [ -s "$CONFIG_PATH" ]; then
  echo "[restore] Backing up corrupted config → $BACKUP_PATH"
  cp "$CONFIG_PATH" "$BACKUP_PATH"
else
  echo "[restore] Config is missing or already empty — no backup needed"
fi

# ---------------------------------------------------------------------------
# Step 2: Delete the config file
# ---------------------------------------------------------------------------
rm -f "$CONFIG_PATH"
echo "[restore] Deleted: $CONFIG_PATH"

echo ""
echo "[restore] On next container start, bootstrap.sh will regenerate the full"
echo "          Phase 8 config, including:"
echo "            - gateway (bind=loopback, tailscale.mode=serve)"
echo "            - memorySearch (gemini embedding provider)"
echo "            - subagents (claude-haiku model)"
echo "            - hooks (endpoint + auto-generated token)"
echo "            - cron (enabled)"
echo "            - automation-supervisor agent entry"
echo "            - model aliases (claude-4-5, haiku-4-5)"
echo "            - COMPANY_MEMORY.md extraPaths"
echo "            - AGENTS.md / memory/patterns/ seeds"
echo "            - All 50+ jq patches applied in sequence"
echo ""

# ---------------------------------------------------------------------------
# Step 3: Find and restart the openclaw container
# ---------------------------------------------------------------------------
CONTAINER=$(docker ps --filter "name=${CONTAINER_FILTER}" --format '{{.Names}}' | head -1)

if [ -n "$CONTAINER" ]; then
  echo "[restore] Found container: $CONTAINER"
  echo "[restore] Restarting..."
  docker restart "$CONTAINER"
  echo ""
  echo "[restore] Tailing container logs for 30 seconds (watching for [config] patch lines and startup)..."
  echo "-----------------------------------------------------------------------"
  timeout 30 docker logs -f --since 1s "$CONTAINER" 2>&1 | head -80 || true
  echo "-----------------------------------------------------------------------"
  echo ""
  echo "[restore] Done. Verify with:"
  echo "  curl -s http://192.168.1.100:18789/health"
  echo "  docker exec \$CONTAINER openclaw doctor"
else
  echo "[restore] No running container matched '${CONTAINER_FILTER}'."
  echo ""
  echo "The config has been deleted. To complete restoration, redeploy from"
  echo "Coolify or trigger a git push so bootstrap.sh regenerates the config:"
  echo ""
  echo "  # Empty commit to trigger webhook deploy:"
  echo "  git commit --allow-empty -m 'fix: trigger redeploy to restore openclaw config'"
  echo "  git push"
fi
