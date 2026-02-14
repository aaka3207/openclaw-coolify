#!/usr/bin/env bash
# openclaw-approve: Approve pending device requests with confirmation
echo "Checking for pending device requests..."

# Find the binary
OPENCLAW=$(command -v openclaw || command -v clawdbot || echo "openclaw")

if ! command -v "$OPENCLAW" >/dev/null 2>&1; then
  echo "Error: OpenClaw binary not found!"
  exit 1
fi

# Try multiple common keys for the request ID
IDS=$($OPENCLAW devices list --json | sed -n '/^{/,$p' | jq -r '.pending[] | .requestId // .id // .request' 2>/dev/null | grep -v "null")

if [ -z "$IDS" ]; then
  echo "No pending requests found."
  exit 0
fi

echo "Pending device requests:"
echo "$IDS"
echo ""

# SECURITY: If OPENCLAW_AUTO_APPROVE_FIRST is set and first-device marker doesn't exist,
# approve only the first request (for headless initial setup)
MARKER_FILE="${OPENCLAW_STATE_DIR:-/data/.openclaw}/.first-device-approved"
if [ "${OPENCLAW_AUTO_APPROVE_FIRST:-0}" = "1" ] && [ ! -f "$MARKER_FILE" ]; then
  FIRST_ID=$(echo "$IDS" | head -n 1)
  echo "Auto-approving first request only: $FIRST_ID"
  $OPENCLAW devices approve "$FIRST_ID"
  touch "$MARKER_FILE"
  exit 0
fi

# Interactive approval
for ID in $IDS; do
  read -p "Approve request $ID? (y/N): " CONFIRM
  if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
    $OPENCLAW devices approve "$ID"
    echo "Approved: $ID"
  else
    echo "Skipped: $ID"
  fi
done
