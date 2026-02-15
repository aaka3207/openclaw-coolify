#!/usr/bin/env bash
set -e

if [ -f "/app/scripts/migrate-to-data.sh" ]; then
    bash "/app/scripts/migrate-to-data.sh"
fi

OPENCLAW_STATE="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
CONFIG_FILE="$OPENCLAW_STATE/openclaw.json"
WORKSPACE_DIR="${OPENCLAW_WORKSPACE:-/data/openclaw-workspace}"

mkdir -p "$OPENCLAW_STATE" "$WORKSPACE_DIR"
chmod 700 "$OPENCLAW_STATE"

mkdir -p "$OPENCLAW_STATE/credentials"
mkdir -p "$OPENCLAW_STATE/agents/main/sessions"
chmod 700 "$OPENCLAW_STATE/credentials"

# SECURITY: Isolate deployment credentials into files, remove from environment
CRED_DIR="$OPENCLAW_STATE/credentials"
mkdir -p "$CRED_DIR"
chmod 700 "$CRED_DIR"
for var in GITHUB_TOKEN; do
    if [ -n "${!var}" ]; then
        printf '%s' "${!var}" > "$CRED_DIR/$var"
        chmod 600 "$CRED_DIR/$var"
    fi
done
# Unset deployment tokens from environment (AI agent doesn't need them directly)
unset GITHUB_TOKEN

# Ensure data subdirectories exist (HOME=/data, no /root/ symlinks needed)
for dir in .agents .ssh .config .local .cache .npm .bun .claude .kimi; do
    mkdir -p "/data/$dir"
done

# ----------------------------
# Seed Agent Workspaces
# ----------------------------
seed_agent() {
  local id="$1"
  local name="$2"
  local dir="/data/openclaw-$id"

  if [ "$id" = "main" ]; then
    dir="${OPENCLAW_WORKSPACE:-/data/openclaw-workspace}"
  fi

  mkdir -p "$dir"

  # 🔒 NEVER overwrite existing SOUL.md
  if [ -f "$dir/SOUL.md" ]; then
    echo "🧠 SOUL.md already exists for $id — skipping"
    return 0
  fi

  # ✅ MAIN agent gets ORIGINAL repo SOUL.md and BOOTSTRAP.md
  if [ "$id" = "main" ]; then
    if [ -f "./SOUL.md" ] && [ ! -f "$dir/SOUL.md" ]; then
      echo "✨ Copying original SOUL.md to $dir"
      cp "./SOUL.md" "$dir/SOUL.md"
    fi
    if [ -f "./BOOTSTRAP.md" ] && [ ! -f "$dir/BOOTSTRAP.md" ]; then
      echo "🚀 Seeding BOOTSTRAP.md to $dir"
      cp "./BOOTSTRAP.md" "$dir/BOOTSTRAP.md"
    fi
    return 0
  fi

  # fallback for other agents
  cat >"$dir/SOUL.md" <<EOF
# SOUL.md - $name
You are OpenClaw, a helpful and premium AI assistant.
EOF
}

seed_agent "main" "OpenClaw"

# ----------------------------
# Generate Config with Prime Directive
# ----------------------------
if [ ! -f "$CONFIG_FILE" ]; then
  echo "🏥 Generating openclaw.json with Prime Directive..."
  TOKEN=$(openssl rand -hex 24 2>/dev/null || node -e "console.log(require('crypto').randomBytes(24).toString('hex'))")
  cat >"$CONFIG_FILE" <<EOF
{
"commands": {
    "native": true,
    "nativeSkills": true,
    "text": true,
    "bash": true,
    "config": true,
    "debug": true,
    "restart": true,
    "useAccessGroups": true
  },
  "plugins": {
    "enabled": true,
    "entries": {
      "whatsapp": {
        "enabled": true
      },
      "telegram": {
        "enabled": true
      },
      "google-antigravity-auth": {
        "enabled": true
      }
    }
  },
  "skills": {
    "allowBundled": [
      "*"
    ],
    "install": {
      "nodeManager": "npm"
    }
  },
  "gateway": {
  "port": $OPENCLAW_GATEWAY_PORT,
  "mode": "local",
    "bind": "lan",
    "controlUi": {
      "enabled": true,
      "allowInsecureAuth": true
    },
    "trustedProxies": [
      "172.16.0.0/12",
      "192.168.1.0/24"
    ],
    "tailscale": {
      "mode": "off",
      "resetOnExit": false
    },
    "auth": { "mode": "token", "token": "$TOKEN" }
  },
  "agents": {
    "defaults": {
      "workspace": "$WORKSPACE_DIR",
      "envelopeTimestamp": "on",
      "envelopeElapsed": "on",
      "cliBackends": {},
      "heartbeat": {
        "every": "1h"
      },
      "maxConcurrent": 4,
      "sandbox": {
        "mode": "non-main",
        "scope": "session",
        "browser": {
          "enabled": true
        }
      }
    },
    "list": [
      { "id": "main","default": true, "name": "default",  "workspace": "${OPENCLAW_WORKSPACE:-/data/openclaw-workspace}"}
    ]
  }
}
EOF
fi

# ----------------------------
# Export state
# ----------------------------
export OPENCLAW_STATE_DIR="$OPENCLAW_STATE"

# ----------------------------
# Sandbox setup
# ----------------------------
# Sandbox setup requires docker CLI (installed via post-deploy script)
if command -v docker &>/dev/null; then
  [ -f scripts/sandbox-setup.sh ] && bash scripts/sandbox-setup.sh
  [ -f scripts/sandbox-browser-setup.sh ] && bash scripts/sandbox-browser-setup.sh
else
  echo "⏭️  Skipping sandbox setup (docker CLI not yet installed — run post-deploy script)"
fi

# ----------------------------
# Recovery & Monitoring
# ----------------------------
# SECURITY: Run scripts from /app/scripts/ (read-only image path), NOT workspace
if [ -f /app/scripts/recover_sandbox.sh ]; then
  echo "Running Recovery Protocols..."
  # Remove any old copies from workspace (cleanup from previous versions)
  rm -f "$WORKSPACE_DIR/recover_sandbox.sh" "$WORKSPACE_DIR/monitor_sandbox.sh"

  # Run from immutable image path
  bash /app/scripts/recover_sandbox.sh

  # Start background monitor from image path
  nohup bash /app/scripts/monitor_sandbox.sh >/dev/null 2>&1 &
fi

# ----------------------------
# BWS Secrets Injection
# ----------------------------
if [ -n "${BWS_ACCESS_TOKEN:-}" ]; then
  bash /app/scripts/fetch-bws-secrets.sh
fi
if [ -f /data/.openclaw/secrets.env ]; then
  set -a
  source /data/.openclaw/secrets.env
  set +a
  echo "[bws] loaded $(wc -l < /data/.openclaw/secrets.env) secrets"
fi

# Start BWS secrets refresh cron (every 5 min)
if [ -n "${BWS_ACCESS_TOKEN:-}" ] && command -v bws &>/dev/null; then
  (crontab -l 2>/dev/null; echo "*/5 * * * * BWS_ACCESS_TOKEN=\"${BWS_ACCESS_TOKEN}\" BWS_CRON=1 bash /app/scripts/fetch-bws-secrets.sh >> /tmp/bws-cron.log 2>&1") | crontab -
  cron 2>/dev/null || crond 2>/dev/null || true
  echo "[bws] cron refresh enabled (every 5 min)"
fi

# ----------------------------
# Run OpenClaw
# ----------------------------
ulimit -n 65535
# ----------------------------
# Banner & Access Info
# ----------------------------
# Try to extract existing token if not already set (e.g. from previous run)
if [ -f "$CONFIG_FILE" ]; then
    SAVED_TOKEN=$(jq -r '.gateway.auth.token // empty' "$CONFIG_FILE" 2>/dev/null || grep -o '"token": "[^"]*"' "$CONFIG_FILE" | tail -1 | cut -d'"' -f4)
    if [ -n "$SAVED_TOKEN" ]; then
        TOKEN="$SAVED_TOKEN"
    fi
fi

# SECURITY: Write access credentials to file instead of printing to stdout/logs
ACCESS_FILE="$OPENCLAW_STATE/access.txt"
cat > "$ACCESS_FILE" <<ACCESSEOF
Access Token: $TOKEN
Service URL (Local): http://localhost:${OPENCLAW_GATEWAY_PORT:-18789}?token=$TOKEN
ACCESSEOF
if [ -n "$SERVICE_FQDN_OPENCLAW" ]; then
    echo "Service URL (Public): https://${SERVICE_FQDN_OPENCLAW}?token=$TOKEN" >> "$ACCESS_FILE"
fi
chmod 600 "$ACCESS_FILE"

echo ""
echo "=================================================================="
echo "OpenClaw is ready!"
echo "=================================================================="
echo ""
echo "Access credentials saved to: $ACCESS_FILE"
echo "To view: cat $ACCESS_FILE"
echo ""
echo "Onboarding:"
echo "  1. View credentials: cat $ACCESS_FILE"
echo "  2. Approve this machine: openclaw-approve"
echo "  3. Start onboarding: openclaw onboard"
echo ""
echo "=================================================================="
exec openclaw gateway run