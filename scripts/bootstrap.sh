#!/usr/bin/env bash
set -e

# Ensure PATH includes all tool directories
export PATH="/usr/local/go/bin:/usr/local/bin:/usr/sbin:/usr/bin:/bin:/data/.local/bin:/data/.npm-global/bin:/data/.bun/bin:/data/.bun/install/global/bin:/data/.claude/bin:$PATH"

if [ -f "/app/scripts/migrate-to-data.sh" ]; then
    bash "/app/scripts/migrate-to-data.sh"
fi

OPENCLAW_STATE="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
CONFIG_FILE="$OPENCLAW_STATE/openclaw.json"
# Unlock config for patching (re-locked read-only at end of patch section)
chmod 644 "$CONFIG_FILE" 2>/dev/null || true
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
# Resolve Hooks Token (BWS-managed or auto-generated)
# ----------------------------
HOOKS_TOKEN=""
if [ -f /data/.openclaw/secrets.env ]; then
  HOOKS_TOKEN=$(grep '^OPENCLAW_HOOKS_TOKEN=' /data/.openclaw/secrets.env | cut -d= -f2- || true)
fi
if [ -z "$HOOKS_TOKEN" ]; then
  HOOKS_TOKEN=$(openssl rand -hex 24 2>/dev/null || node -e "console.log(require('crypto').randomBytes(24).toString('hex'))")
fi

# ----------------------------
# Generate Config with Prime Directive
# ----------------------------
if [ ! -f "$CONFIG_FILE" ]; then
  echo "🏥 Generating openclaw.json with Prime Directive..."
  # Use Coolify's OPENCLAW_GATEWAY_TOKEN if set, otherwise generate random
  TOKEN="${OPENCLAW_GATEWAY_TOKEN:-$(openssl rand -hex 24 2>/dev/null || node -e "console.log(require('crypto').randomBytes(24).toString('hex'))")}"
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
    "enabled": true,
    "token": "$HOOKS_TOKEN",
    "path": "/hooks",
    "defaultSessionKey": "hook:ingress",
    "allowRequestSessionKey": true,
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
        "mode": "off"
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
  # Patch: sync gateway token with OPENCLAW_GATEWAY_TOKEN env var (Coolify sets this)
  if [ -n "${OPENCLAW_GATEWAY_TOKEN:-}" ]; then
    CONFIG_TOKEN=$(jq -r '.gateway.auth.token // empty' "$CONFIG_FILE" 2>/dev/null)
    if [ "$CONFIG_TOKEN" != "$OPENCLAW_GATEWAY_TOKEN" ]; then
      jq --arg tok "$OPENCLAW_GATEWAY_TOKEN" '.gateway.auth.token = $tok' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
      echo "[config] Synced gateway token with OPENCLAW_GATEWAY_TOKEN env var"
    fi
  fi
  # Patch: add /app/skills to skills.load.extraDirs if not already present
  HAS_EXTRA_DIRS=$(jq -r '.skills.load.extraDirs // [] | index("/app/skills") // empty' "$CONFIG_FILE" 2>/dev/null)
  if [ -z "$HAS_EXTRA_DIRS" ]; then
    jq '.skills.load = (.skills.load // {}) | .skills.load.extraDirs = ((.skills.load.extraDirs // []) + ["/app/skills"] | unique)' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Added /app/skills to skills.load.extraDirs"
  fi
  # Patch existing config: enable hooks with BWS token support
  HOOKS_ENABLED=$(jq -r '.hooks.enabled // false' "$CONFIG_FILE" 2>/dev/null)
  if [ "$HOOKS_ENABLED" != "true" ]; then
    # Resolve hooks token from BWS or existing config
    PATCH_HOOKS_TOKEN=""
    if [ -f /data/.openclaw/secrets.env ]; then
      PATCH_HOOKS_TOKEN=$(grep '^OPENCLAW_HOOKS_TOKEN=' /data/.openclaw/secrets.env | cut -d= -f2- || true)
    fi
    if [ -z "$PATCH_HOOKS_TOKEN" ]; then
      PATCH_HOOKS_TOKEN=$(jq -r '.hooks.token // empty' "$CONFIG_FILE" 2>/dev/null)
    fi
    if [ -z "$PATCH_HOOKS_TOKEN" ]; then
      PATCH_HOOKS_TOKEN=$(openssl rand -hex 24 2>/dev/null || node -e "console.log(require('crypto').randomBytes(24).toString('hex'))")
    fi
    jq --arg t "$PATCH_HOOKS_TOKEN" '.hooks.enabled = true | .hooks.token = $t | .hooks.allowRequestSessionKey = true | .hooks.allowedSessionKeyPrefixes = ["hook:"]' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Enabled hooks with token support"
  fi
  # Patch: enable built-in memorySearch with OpenAI embeddings (hybrid BM25+vector)
  MEMORY_SEARCH=$(jq -r '.agents.defaults.memorySearch.enabled // false' "$CONFIG_FILE" 2>/dev/null)
  if [ "$MEMORY_SEARCH" != "true" ]; then
    jq '.agents.defaults.memorySearch = {
      "enabled": true,
      "provider": "openai",
      "model": "text-embedding-3-small",
      "sources": ["memory"],
      "sync": {"watch": true, "onSearch": true, "onSessionStart": true},
      "query": {
        "maxResults": 10,
        "minScore": 0.25,
        "hybrid": {
          "enabled": true,
          "vectorWeight": 0.7,
          "textWeight": 0.3,
          "mmr": {"enabled": true, "lambda": 0.7},
          "temporalDecay": {"enabled": true, "halfLifeDays": 30}
        }
      }
    }' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Enabled memorySearch (openai/text-embedding-3-small, hybrid BM25+vector)"
  fi
  # Patch: set sub-agent model defaults (Haiku via OpenRouter for cost efficiency)
  # Force-update if set to bare anthropic/ prefix (missing openrouter/)
  SUBAGENT_MODEL=$(jq -r '.agents.defaults.subagents.model.primary // empty' "$CONFIG_FILE" 2>/dev/null)
  if [ -z "$SUBAGENT_MODEL" ] || [ "$SUBAGENT_MODEL" = "anthropic/claude-haiku-4-5" ]; then
    jq '.agents.defaults.subagents = {
      "model": {"primary": "openrouter/anthropic/claude-haiku-4-5"},
      "maxSpawnDepth": 2,
      "maxChildrenPerAgent": 5,
      "maxConcurrent": 8,
      "archiveAfterMinutes": 60
    }' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Set sub-agent model to openrouter/anthropic/claude-haiku-4-5"
  fi
  # Patch: heartbeat model (cheap model for periodic keepalives)
  HEARTBEAT_MODEL=$(jq -r '.agents.defaults.heartbeat.model // empty' "$CONFIG_FILE" 2>/dev/null)
  if [ -z "$HEARTBEAT_MODEL" ]; then
    jq '.agents.defaults.heartbeat.model = "openrouter/anthropic/claude-haiku-4-5"' \
      "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Set heartbeat model to openrouter/anthropic/claude-haiku-4-5"
  fi
  # Patch: image/vision model (must be object with primary key)
  IMAGE_MODEL=$(jq -r '.agents.defaults.imageModel.primary // empty' "$CONFIG_FILE" 2>/dev/null)
  if [ -z "$IMAGE_MODEL" ]; then
    jq '.agents.defaults.imageModel = {"primary": "openrouter/google/gemini-3-flash-preview"}' \
      "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Set image model to openrouter/google/gemini-3-flash-preview"
  fi
  # Patch: enrich fallback models (only if still using default single fallback)
  FALLBACK_COUNT=$(jq -r '.agents.defaults.model.fallbacks | length' "$CONFIG_FILE" 2>/dev/null)
  if [ "${FALLBACK_COUNT:-0}" -le 1 ]; then
    jq '.agents.defaults.model.fallbacks = [
      "openrouter/anthropic/claude-sonnet-4-5",
      "openrouter/google/gemini-3-flash-preview",
      "openrouter/auto"
    ]' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Updated model fallbacks (sonnet → gemini-3-flash-preview → auto)"
  fi
  # Patch: gateway.remote.url — sub-agents use loopback to bypass plaintext LAN security check
  REMOTE_URL=$(jq -r '.gateway.remote.url // empty' "$CONFIG_FILE" 2>/dev/null)
  if [ -z "$REMOTE_URL" ] || [ "$REMOTE_URL" != "ws://127.0.0.1:${OPENCLAW_GATEWAY_PORT:-18789}" ]; then
    jq ".gateway.remote = {\"url\": \"ws://127.0.0.1:${OPENCLAW_GATEWAY_PORT:-18789}\"}" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Set gateway.remote.url=ws://127.0.0.1:${OPENCLAW_GATEWAY_PORT:-18789} (sub-agent loopback)"
  fi
  # Patch: disable gateway/restart tools so agent cannot modify gateway config or trigger restarts
  jq '.commands.gateway = false | .commands.restart = false' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  echo "[config] Disabled commands.gateway and commands.restart"
fi

# Lock config read-only so agent cannot overwrite it via bash between boots
chmod 444 "$CONFIG_FILE"
echo "[config] Locked openclaw.json read-only"

# ----------------------------
# Export state
# ----------------------------
export OPENCLAW_STATE_DIR="$OPENCLAW_STATE"

# ----------------------------
# System services
# ----------------------------
# Start cron daemon for periodic tasks (BWS refresh, NOVA catch-up)
/usr/sbin/cron 2>/dev/null || true

# Remove stale matrix plugin extensions (prevents duplicate plugin warning)
rm -rf /data/.openclaw/extensions/matrix 2>/dev/null || true

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

# Write BWS-sourced credentials to files (not available during early credential isolation)
for var in N8N_API_KEY; do
    if [ -n "${!var:-}" ]; then
        printf '%s' "${!var}" > "$CRED_DIR/$var"
        chmod 600 "$CRED_DIR/$var"
        echo "[credentials] wrote BWS-sourced $var to credential file"
        unset "$var"
    fi
done

# ----------------------------
# NOVA Memory Installation
# ----------------------------
# Set NOVA_MEMORY_ENABLED=true in Coolify to enable.
# Currently disabled: message:received hook not implemented in OpenClaw through 2026.2.15.
# Data was being extracted but never recalled — semantic-recall hook can't fire.
# Re-enable when OpenClaw ships message:received (GitHub issue #8807).
if [ "${NOVA_MEMORY_ENABLED:-false}" = "true" ] && [ -n "${NOVA_MEMORY_DB_HOST:-}" ]; then
  echo "[nova] NOVA Memory enabled, waiting for PostgreSQL..."
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

      # Generate postgres.json (required by nova-memory v2.1+)
      PG_JSON="${HOME}/.openclaw/postgres.json"
      mkdir -p "$(dirname "$PG_JSON")"
      cat > "$PG_JSON" <<PGJSON
{"host":"${NOVA_MEMORY_DB_HOST}","port":${NOVA_MEMORY_DB_PORT},"database":"${NOVA_MEMORY_DB_NAME}","user":"${NOVA_MEMORY_DB_USER}","password":"${NOVA_MEMORY_DB_PASSWORD}"}
PGJSON
      chmod 600 "$PG_JSON"
      echo "[nova] Generated postgres.json"

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

    # Symlink nova-relationships into .openclaw for hook import paths
    if [ -d "$NOVA_REL_DIR" ] && [ ! -L "/data/.openclaw/nova-relationships" ]; then
      ln -sf "$NOVA_REL_DIR" /data/.openclaw/nova-relationships
      echo "[nova] Symlinked nova-relationships"
    fi

    # Memory catch-up processor — DISABLED: using built-in memorySearch instead of NOVA hooks
    # Legacy cron removed 2026-02-21. To clean stale entries: crontab -l | grep -v memory-catchup | crontab -
  fi
else
  echo "[nova] NOVA Memory disabled (set NOVA_MEMORY_ENABLED=true to enable — waiting for issue #8807)"
fi
# --- End NOVA Memory Installation ---

# ----------------------------
# Fix Matrix plugin dependencies
# ----------------------------
# OpenClaw 2026.2.15 ships the matrix plugin with pnpm workspace:* refs
# that npm can't resolve. Replace with wildcard and install deps.
MATRIX_EXT="/usr/local/lib/node_modules/openclaw/extensions/matrix"
if [ -f "$MATRIX_EXT/package.json" ]; then
  if grep -q '"workspace:\*"' "$MATRIX_EXT/package.json" 2>/dev/null; then
    sed -i 's/"workspace:\*"/"*"/g' "$MATRIX_EXT/package.json"
    echo "[matrix] Fixed workspace:* refs in matrix plugin"
  fi
  if [ ! -d "$MATRIX_EXT/node_modules/@vector-im" ]; then
    cd "$MATRIX_EXT" && npm install --omit=dev --quiet 2>/dev/null && echo "[matrix] Installed matrix plugin deps" || echo "[matrix] WARNING: npm install failed"
  fi
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