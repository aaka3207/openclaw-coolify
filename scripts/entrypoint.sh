#!/usr/bin/env bash
# Entrypoint: runs as root, handles privileged setup, then drops to openclaw via gosu.
# gosu preserves ENV (no PAM reset), so PATH and all env vars pass through cleanly.
set -e

# --- Privileged operations (must run as root) ---
echo "[entrypoint] Starting privileged setup..."

# Fix volume ownership — openclaw user must own /data and key subdirs
# Non-recursive for large dirs to avoid HDD stalls
chown openclaw:openclaw /data 2>/dev/null || true
for dir in /data/.local /data/.cache /data/.config /data/.openclaw /data/.openclaw/credentials; do
  [ -d "$dir" ] && chown openclaw:openclaw "$dir" 2>/dev/null || true
done
# Recursive for small dirs + config files that must be readable
chown -R openclaw:openclaw /data/.openclaw/agents 2>/dev/null || true
chown openclaw:openclaw /data/.openclaw/*.json /data/.openclaw/*.txt /data/.openclaw/*.env 2>/dev/null || true
# NOVA dirs and workspace scripts (cloned/created by previous root-based runs)
for dir in /data/clawd /data/nova-relationships /data/openclaw-workspace/scripts /data/.openclaw/scripts; do
  [ -d "$dir" ] && chown -R openclaw:openclaw "$dir" 2>/dev/null || true
done

# Start cron daemon (runs as root, executes crontab entries)
/usr/sbin/cron || echo "[entrypoint] WARNING: cron daemon failed to start"

# Remove stale matrix plugin extensions (prevents duplicate plugin warning)
rm -rf /data/.openclaw/extensions/matrix 2>/dev/null || true

# --- Drop privileges and run bootstrap ---
exec gosu openclaw bash /app/scripts/bootstrap.sh
