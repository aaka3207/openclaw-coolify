#!/usr/bin/env bash
# Fetch secrets from Bitwarden Secrets Manager and write to secrets.env
# Usage: BWS_ACCESS_TOKEN=<token> bash fetch-bws-secrets.sh
set -euo pipefail

SECRETS_FILE="${BWS_SECRETS_FILE:-/data/.openclaw/secrets.env}"
SECRETS_TMP="${SECRETS_FILE}.tmp"

# Require BWS_ACCESS_TOKEN
if [ -z "${BWS_ACCESS_TOKEN:-}" ]; then
  echo "[bws] BWS_ACCESS_TOKEN not set, skipping secrets fetch"
  exit 0
fi

# Check bws CLI
if ! command -v bws &>/dev/null; then
  echo "[bws] bws CLI not installed, skipping secrets fetch"
  exit 0
fi

# Fetch all secrets, write as KEY=VALUE
# Strip trailing whitespace/newlines from values
bws secret list --access-token "$BWS_ACCESS_TOKEN" 2>/dev/null \
  | jq -r '.[] | "\(.key)=\(.value | gsub("\\s+$";""))"' \
  | grep -v '^$' \
  > "$SECRETS_TMP"

chmod 600 "$SECRETS_TMP"

SECRET_COUNT=$(wc -l < "$SECRETS_TMP")

if [ "$SECRET_COUNT" -eq 0 ]; then
  echo "[bws] no secrets found, skipping"
  rm -f "$SECRETS_TMP"
  exit 0
fi

# Compare with existing — only update + restart if changed
if [ -f "$SECRETS_FILE" ] && diff -q "$SECRETS_FILE" "$SECRETS_TMP" >/dev/null 2>&1; then
  rm "$SECRETS_TMP"
  echo "[bws] secrets unchanged ($SECRET_COUNT secrets)"
else
  mv "$SECRETS_TMP" "$SECRETS_FILE"
  echo "[bws] secrets updated ($SECRET_COUNT secrets)"

  # If called from cron (not startup), restart gateway to pick up new values
  if [ "${BWS_CRON:-}" = "1" ]; then
    echo "[bws] restarting gateway to pick up new secrets..."
    openclaw restart || true
  fi
fi
