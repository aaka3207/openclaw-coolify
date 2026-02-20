#!/usr/bin/env bash
# Start OpenClaw browser control on this Mac.
# Connects to the LAN gateway, starts the Chrome extension relay, opens Chrome.
# Ctrl+C to stop everything.

set -e

GATEWAY_HOST="192.168.1.100"
GATEWAY_PORT="18789"

cleanup() {
  echo ""
  echo "Shutting down node host..."
  kill "$NODE_PID" 2>/dev/null || true
  wait "$NODE_PID" 2>/dev/null || true
  echo "Done."
}
trap cleanup EXIT INT TERM

# 1. Start node host in background
echo "Connecting to gateway at $GATEWAY_HOST:$GATEWAY_PORT..."
openclaw node run \
  --host "$GATEWAY_HOST" \
  --port "$GATEWAY_PORT" \
  --node-id my-macbook \
  --display-name "MacBook Pro" &
NODE_PID=$!

# 2. Wait for node to connect and relay to start
sleep 3

# 3. Start browser relay (one-shot — starts relay, exits OK if tab not yet attached)
echo "Starting Chrome extension relay..."
openclaw browser start 2>/dev/null || true

# 4. Open Chrome
echo "Opening Chrome..."
open -a "Google Chrome"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Click the OpenClaw extension icon on any tab"
echo "  Then ask the bot to use your browser"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Press Ctrl+C to disconnect."

# 5. Keep alive
wait "$NODE_PID"
