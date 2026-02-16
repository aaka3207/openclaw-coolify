#!/usr/bin/env bash
# Entrypoint: runs as root, handles privileged setup, then drops to openclaw via gosu.
# gosu preserves ENV (no PAM reset), so PATH and all env vars pass through cleanly.
set -e

# --- Privileged operations (must run as root) ---
echo "[entrypoint] Starting privileged setup..."

# Fix volume ownership (non-recursive to avoid HDD stalls on large dirs)
for dir in /data/.local /data/.cache /data/.config; do
  [ -d "$dir" ] && chown openclaw:openclaw "$dir" 2>/dev/null || true
done
# Recursive only for small dirs that need it
chown -R openclaw:openclaw /data/.openclaw/agents 2>/dev/null || true

# Start cron daemon (runs as root, executes crontab entries)
/usr/sbin/cron || echo "[entrypoint] WARNING: cron daemon failed to start"

# Remove stale matrix plugin extensions (prevents duplicate plugin warning)
rm -rf /data/.openclaw/extensions/matrix 2>/dev/null || true

# --- Drop privileges and run bootstrap ---
exec gosu openclaw bash /app/scripts/bootstrap.sh
