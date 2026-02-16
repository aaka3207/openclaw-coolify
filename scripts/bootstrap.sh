#!/usr/bin/env bash
set -eE
trap 'echo "[bootstrap] FATAL: line $LINENO exited with code $?" >&2' ERR

# NOTE: PATH is inherited from Dockerfile ENV via gosu (no PAM reset).
# Only add paths not already present.
export PATH="$PATH"
echo "[bootstrap] Starting... (PID $$, user $(whoami))"

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

  # MAIN agent: sync SOUL.md and BOOTSTRAP.md from repo (hybrid approach)
  # Repo is source of truth — copies when repo version differs from volume.
  # UI edits survive until the next repo update changes the file.
  if [ "$id" = "main" ]; then
    for doc in SOUL.md BOOTSTRAP.md; do
      if [ -f "/app/$doc" ]; then
        if [ ! -f "$dir/$doc" ]; then
          echo "[seed] Copying $doc to $dir"
          cp "/app/$doc" "$dir/$doc"
        elif ! cmp -s "/app/$doc" "$dir/$doc"; then
          echo "[seed] Updating $doc (repo version changed)"
          cp "/app/$doc" "$dir/$doc"
        fi
      fi
    done
    return 0
  fi

  # fallback for other agents — only seed if missing
  if [ ! -f "$dir/SOUL.md" ]; then
    cat >"$dir/SOUL.md" <<EOF
# SOUL.md - $name
You are OpenClaw, a helpful and premium AI assistant.
EOF
  fi
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
    "load": {
      "extraDirs": ["/app/skills"]
    },
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
  "hooks": {
    "enabled": false,
    "token": "$TOKEN",
    "path": "/hooks",
    "defaultSessionKey": "hook:ingress",
    "allowRequestSessionKey": false,
    "allowedSessionKeyPrefixes": ["hook:"]
  },
  "cron": {
    "enabled": true
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

# Patch existing config: enable cron if not already set
if command -v jq &>/dev/null && [ -f "$CONFIG_FILE" ]; then
  CRON_ENABLED=$(jq -r '.cron.enabled // false' "$CONFIG_FILE" 2>/dev/null)
  if [ "$CRON_ENABLED" != "true" ]; then
    jq '.cron = (.cron // {}) | .cron.enabled = true' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Enabled cron in openclaw.json"
  fi
  # Patch: add /app/skills to skills.load.extraDirs if not already present
  HAS_EXTRA_DIRS=$(jq -r '.skills.load.extraDirs // [] | index("/app/skills") // empty' "$CONFIG_FILE" 2>/dev/null)
  if [ -z "$HAS_EXTRA_DIRS" ]; then
    jq '.skills.load = (.skills.load // {}) | .skills.load.extraDirs = ((.skills.load.extraDirs // []) + ["/app/skills"] | unique)' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Added /app/skills to skills.load.extraDirs"
  fi
fi

# ----------------------------
# Export state
# ----------------------------
export OPENCLAW_STATE_DIR="$OPENCLAW_STATE"

# ----------------------------
# Sandbox setup
# ----------------------------
# Sandbox setup (docker CLI is baked into image)
[ -f /app/scripts/sandbox-setup.sh ] && bash /app/scripts/sandbox-setup.sh || echo "[sandbox] Base image setup failed (non-fatal)"
[ -f /app/scripts/sandbox-browser-setup.sh ] && bash /app/scripts/sandbox-browser-setup.sh || echo "[sandbox] Browser image setup failed (non-fatal)"

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
  echo "[bws] cron refresh enabled (every 5 min)"
fi

# ----------------------------
# NOVA Memory Installation
# ----------------------------
if [ -n "${NOVA_MEMORY_DB_HOST:-}" ]; then
  echo "[nova] Waiting for PostgreSQL..."
  PG_READY=false
  for i in $(seq 1 30); do
    if (echo > /dev/tcp/${NOVA_MEMORY_DB_HOST}/${NOVA_MEMORY_DB_PORT}) 2>/dev/null; then
      echo "[nova] PostgreSQL ready"
      PG_READY=true
      break
    fi
    sleep 2
  done
  if [ "$PG_READY" = "false" ]; then
    echo "[nova] ERROR: PostgreSQL not ready after 30 attempts, skipping NOVA Memory"
  fi

  if [ "$PG_READY" = "true" ]; then
    # Clone or update NOVA Memory to persistent volume
    NOVA_DIR="/data/clawd/nova-memory"
    if [ ! -d "$NOVA_DIR/.git" ]; then
      mkdir -p /data/clawd
      git clone https://github.com/NOVA-Openclaw/nova-memory.git "$NOVA_DIR" 2>/dev/null || echo "[nova] WARNING: git clone failed"
      echo "[nova] Cloned NOVA Memory"
    else
      cd "$NOVA_DIR" && git pull --rebase 2>/dev/null || true
      echo "[nova] Updated NOVA Memory"
    fi

    # Clone or update NOVA Relationships (semantic-recall hook depends on /data/nova-relationships/)
    NOVA_REL_DIR="/data/nova-relationships"
    if [ ! -d "$NOVA_REL_DIR/.git" ]; then
      git clone https://github.com/NOVA-Openclaw/nova-relationships.git "$NOVA_REL_DIR" 2>/dev/null || echo "[nova] WARNING: nova-relationships clone failed"
      echo "[nova] Cloned NOVA Relationships"
    else
      cd "$NOVA_REL_DIR" && git pull --rebase 2>/dev/null || true
      echo "[nova] Updated NOVA Relationships"
    fi
    # Install nova-relationships entity-resolver deps (semantic-recall needs 'pg' package)
    if [ -f "$NOVA_REL_DIR/lib/entity-resolver/package.json" ]; then
      cd "$NOVA_REL_DIR/lib/entity-resolver" && npm install --omit=dev --quiet 2>/dev/null && echo "[nova] Entity-resolver deps installed" || echo "[nova] WARNING: Entity-resolver deps install failed"
    fi

    # Ensure directories agent-install.sh needs are writable
    mkdir -p /data/.local/share/nova 2>/dev/null || true

    # Install Python deps for NOVA hooks (idempotent, fast if already installed)
    pip3 install --quiet --break-system-packages psycopg2-binary anthropic openai 2>/dev/null && echo "[nova] Python deps installed" || echo "[nova] WARNING: Python deps install failed"

    # Run agent-install.sh with PG environment variables set (idempotent)
    cd "$NOVA_DIR" || { echo "[nova] WARNING: NOVA directory not found"; }
    if [ -d "$NOVA_DIR" ]; then
      export PGHOST="${NOVA_MEMORY_DB_HOST}"
      export PGPORT="${NOVA_MEMORY_DB_PORT}"
      export PGUSER="${NOVA_MEMORY_DB_USER}"
      export PGPASSWORD="${NOVA_MEMORY_DB_PASSWORD}"
      export PGDATABASE="${NOVA_MEMORY_DB_NAME}"

      if [ -x "./agent-install.sh" ]; then
        ./agent-install.sh && echo "[nova] Schema applied" || echo "[nova] WARNING: agent-install.sh failed"
      else
        echo "[nova] WARNING: agent-install.sh not found or not executable"
      fi
      # Ensure hooks.token exists if agent-install.sh enabled hooks
      # (gateway crashes with "hooks.enabled requires hooks.token" otherwise)
      if command -v jq &>/dev/null && [ -f "$CONFIG_FILE" ]; then
        HOOKS_ENABLED=$(jq -r '.hooks.enabled // false' "$CONFIG_FILE" 2>/dev/null)
        HOOKS_TOKEN=$(jq -r '.hooks.token // empty' "$CONFIG_FILE" 2>/dev/null)
        if [ "$HOOKS_ENABLED" = "true" ] && [ -z "$HOOKS_TOKEN" ]; then
          HOOKS_TOKEN=$(openssl rand -hex 24 2>/dev/null || node -e "console.log(require('crypto').randomBytes(24).toString('hex'))")
          jq --arg t "$HOOKS_TOKEN" '.hooks.token = $t | .hooks.path = (.hooks.path // "/hooks") | .hooks.defaultSessionKey = (.hooks.defaultSessionKey // "hook:ingress")' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
          echo "[nova] Patched hooks.token into config"
        fi
      fi
    fi

    # Clean up invalid config keys from previous runs
    if command -v jq &>/dev/null && [ -f "$CONFIG_FILE" ]; then
      if jq -e '.experimental' "$CONFIG_FILE" &>/dev/null; then
        jq 'del(.experimental)' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
        echo "[nova] Removed invalid 'experimental' key from config"
      fi
    fi

    # Symlink nova-relationships into .openclaw for hook import paths
    if [ -d "$NOVA_REL_DIR" ] && [ ! -L "/data/.openclaw/nova-relationships" ]; then
      ln -sf "$NOVA_REL_DIR" /data/.openclaw/nova-relationships
      echo "[nova] Symlinked nova-relationships"
    fi

    # Memory catch-up processor (workaround: message:received hook not yet implemented)
    # Processes session transcripts every 5 min via cron
    CATCHUP_SCRIPT="$NOVA_DIR/scripts/memory-catchup.sh"
    if [ -f "$CATCHUP_SCRIPT" ]; then
      chmod +x "$CATCHUP_SCRIPT"
      CATCHUP_CRON="*/5 * * * * PGHOST=${NOVA_MEMORY_DB_HOST} PGPORT=${NOVA_MEMORY_DB_PORT} PGUSER=${NOVA_MEMORY_DB_USER} PGPASSWORD=${NOVA_MEMORY_DB_PASSWORD} PGDATABASE=${NOVA_MEMORY_DB_NAME} ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-} bash $CATCHUP_SCRIPT >> /tmp/nova-catchup.log 2>&1"
      if ! crontab -l 2>/dev/null | grep -q "memory-catchup"; then
        (crontab -l 2>/dev/null; echo "$CATCHUP_CRON") | crontab -
        echo "[nova] Catch-up processor cron enabled (every 5 min)"
      fi
    fi
  fi
fi
# --- End NOVA Memory Installation ---

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
echo "[bootstrap] All setup complete, launching gateway..."
exec openclaw gateway run