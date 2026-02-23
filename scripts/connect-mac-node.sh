#!/usr/bin/env bash
# Start OpenClaw browser control on this Mac.
# Connects to the gateway via Tailscale HTTPS, starts the Chrome extension relay, opens Chrome.
# Ctrl+C to stop everything.
#
# Prerequisites:
#   1. Tailscale installed and logged in on this Mac (brew install --cask tailscale)
#   2. Same Tailscale account as the server
#   3. Find your URL: tailscale status (look for openclaw-server)
#
# Usage:
#   ./connect-mac-node.sh                                    # uses default URL
#   GATEWAY_URL=https://openclaw-server.tailnet-name.ts.net ./connect-mac-node.sh  # custom URL

set -e

# Default: MagicDNS URL — user must update the tailnet name on first use
GATEWAY_URL="${GATEWAY_URL:-https://openclaw-server.CHANGE-ME.ts.net}"

if [[ "$GATEWAY_URL" == *"CHANGE-ME"* ]]; then
  echo "ERROR: Update GATEWAY_URL with your tailnet name."
  echo ""
  echo "Find it by running: tailscale status"
  echo "Look for the machine named 'openclaw-server' and use its full MagicDNS name."
  echo ""
  echo "Example:"
  echo "  GATEWAY_URL=https://openclaw-server.tail12345.ts.net $0"
  echo ""
  echo "Or edit this script and replace CHANGE-ME with your tailnet name."
  exit 1
fi

cleanup() {
  echo ""
  echo "Shutting down node host..."
  kill "$NODE_PID" 2>/dev/null || true
  wait "$NODE_PID" 2>/dev/null || true
  echo "Done."
}
trap cleanup EXIT INT TERM

# 1. Verify Tailscale is connected
if ! tailscale status >/dev/null 2>&1; then
  echo "ERROR: Tailscale is not running or not logged in."
  echo "Install: brew install --cask tailscale"
  echo "Then open Tailscale.app and login."
  exit 1
fi

# 2. Determine correct flag for gateway URL
# openclaw node run may use --url, --gateway-url, --host/--port, or other flags
NODE_HELP=$(openclaw node run --help 2>&1 || true)
if echo "$NODE_HELP" | grep -qE '\-\-url\b'; then
  NODE_CMD=(openclaw node run --url "$GATEWAY_URL" --node-id my-macbook --display-name "MacBook Pro")
elif echo "$NODE_HELP" | grep -qE '\-\-gateway-url\b'; then
  NODE_CMD=(openclaw node run --gateway-url "$GATEWAY_URL" --node-id my-macbook --display-name "MacBook Pro")
elif echo "$NODE_HELP" | grep -qE '\-\-host\b'; then
  # Extract hostname from URL for --host flag
  GW_HOST=$(echo "$GATEWAY_URL" | sed 's|https://||;s|/.*||')
  NODE_CMD=(openclaw node run --host "$GW_HOST" --port 443 --tls --node-id my-macbook --display-name "MacBook Pro")
else
  echo "WARNING: Could not determine correct flag from 'openclaw node run --help'."
  echo "Trying --url (most likely). If this fails, run 'openclaw node run --help' and update this script."
  NODE_CMD=(openclaw node run --url "$GATEWAY_URL" --node-id my-macbook --display-name "MacBook Pro")
fi

# 3. Start node host in background
echo "Connecting to gateway at $GATEWAY_URL..."
echo "  Using command: ${NODE_CMD[*]}"
"${NODE_CMD[@]}" &
NODE_PID=$!

# 4. Wait for node to connect and relay to start
sleep 3

# 5. Start browser relay (one-shot — starts relay, exits OK if tab not yet attached)
echo "Starting Chrome extension relay..."
openclaw browser start 2>/dev/null || true

# 6. Open Chrome
echo "Opening Chrome..."
open -a "Google Chrome"

echo ""
echo "---"
echo "  Gateway: $GATEWAY_URL"
echo "  Click the OpenClaw extension icon on any tab"
echo "  Then ask the bot to use your browser"
echo "---"
echo ""
echo "Press Ctrl+C to disconnect."

# 7. Keep alive
wait "$NODE_PID"
