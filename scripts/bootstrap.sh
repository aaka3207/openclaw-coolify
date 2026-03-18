#!/usr/bin/env bash
set -e

# Ensure PATH includes all tool directories
export PATH="/usr/local/go/bin:/usr/local/bin:/usr/sbin:/usr/bin:/bin:/data/.local/bin:/data/.npm-global/bin:/data/.bun/bin:/data/.bun/install/global/bin:/data/.claude/bin:$PATH"

# Restore openclaw symlink if missing (can be corrupted by agent npm install)
if ! command -v openclaw >/dev/null 2>&1; then
  OPENCLAW_MJS="/usr/local/lib/node_modules/openclaw/openclaw.mjs"
  if [ -f "$OPENCLAW_MJS" ]; then
    ln -sf "$OPENCLAW_MJS" /usr/local/bin/openclaw 2>/dev/null || true
    echo "[bootstrap] Restored missing openclaw symlink"
  fi
fi

if [ -f "/app/scripts/migrate-to-data.sh" ]; then
    bash "/app/scripts/migrate-to-data.sh"
fi

OPENCLAW_STATE="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
CONFIG_FILE="$OPENCLAW_STATE/openclaw.json"
# Unlock config for patching (re-locked read-only at end of patch section)
chmod 644 "$CONFIG_FILE" 2>/dev/null || true
# Early cleanup: remove any invalid gateway keys before other patches run
# gateway.dangerouslyDisableDeviceAuth is NOT a valid key in 2026.2.19+ — crashes gateway
if [ -f "$CONFIG_FILE" ] && command -v jq &>/dev/null; then
  if jq -e '.gateway.dangerouslyDisableDeviceAuth != null' "$CONFIG_FILE" &>/dev/null; then
    jq 'del(.gateway.dangerouslyDisableDeviceAuth)' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Removed invalid gateway.dangerouslyDisableDeviceAuth key"
  fi
  # agents.defaults.tools is NOT a valid key — crashes gateway with "Unrecognized key: tools"
  if jq -e '.agents.defaults.tools != null' "$CONFIG_FILE" &>/dev/null; then
    jq 'del(.agents.defaults.tools)' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Removed invalid agents.defaults.tools key"
  fi
fi
WORKSPACE_DIR="${OPENCLAW_WORKSPACE:-/data/openclaw-workspace}"

mkdir -p "$OPENCLAW_STATE" "$WORKSPACE_DIR"
chmod 700 "$OPENCLAW_STATE"

# Fix: OpenClaw resolves ~/.openclaw/workspace → /data/.openclaw/workspace (via root symlink)
# but config workspace is /data/openclaw-workspace — unify them
if [ ! -L "$OPENCLAW_STATE/workspace" ]; then
  rm -rf "$OPENCLAW_STATE/workspace"
  ln -s "$WORKSPACE_DIR" "$OPENCLAW_STATE/workspace"
  echo "[fix] Symlinked .openclaw/workspace → $WORKSPACE_DIR"
fi

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

# Ensure workspace directory exists
mkdir -p "${OPENCLAW_WORKSPACE:-/data/openclaw-workspace}"

# Seed behavioral files only if missing (agent manages these on volume after first boot)
for _src_file in SOUL.md AGENTS.md TOOLS.md; do
  if [ -f "/app/$_src_file" ] && [ ! -f "${OPENCLAW_WORKSPACE:-/data/openclaw-workspace}/$_src_file" ]; then
    cp "/app/$_src_file" "${OPENCLAW_WORKSPACE:-/data/openclaw-workspace}/$_src_file"
    echo "[bootstrap] Seeded $_src_file to workspace (first boot)"
  fi
done

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
# If config exists but is empty or invalid JSON, delete it so we regenerate cleanly
if [ -f "$CONFIG_FILE" ] && ! jq empty "$CONFIG_FILE" &>/dev/null; then
  echo "[config] Detected invalid/empty openclaw.json — removing for regeneration"
  rm -f "$CONFIG_FILE"
fi

if [ ! -f "$CONFIG_FILE" ]; then
  echo "🏥 Generating openclaw.json with Prime Directive..."
  # Try openclaw doctor --fix first — it may bootstrap a valid config non-interactively
  TOKEN="${OPENCLAW_GATEWAY_TOKEN:-$(openssl rand -hex 24 2>/dev/null || node -e "console.log(require('crypto').randomBytes(24).toString('hex'))")}"
  openclaw doctor --fix 2>/dev/null || true
  # If doctor produced a valid config, use it; otherwise fall back to heredoc
  if jq empty "$CONFIG_FILE" &>/dev/null 2>&1; then
    echo "[config] openclaw doctor --fix produced a valid config"
  else
    echo "[config] Falling back to heredoc config generation"
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
  "port": ${OPENCLAW_GATEWAY_PORT:-18789},
  "mode": "local",
    "bind": "loopback",
    "controlUi": {
      "enabled": true,
      "allowInsecureAuth": true
    },
    "trustedProxies": [
      "100.64.0.0/10",
      "172.16.0.0/12",
      "192.168.1.0/24"
    ],
    "tailscale": {
      "mode": "serve",
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
  fi  # end heredoc fallback
fi

# Backup config before patching so we can revert if patches corrupt it
CONFIG_BACKUP="${CONFIG_FILE}.pre-patch.bak"
if [ -f "$CONFIG_FILE" ]; then
  cp "$CONFIG_FILE" "$CONFIG_BACKUP"
  echo "[config] Backed up openclaw.json before patching"
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
  # Seed-once: memorySearch config (only if provider is empty — agent manages after first boot)
  # CRITICAL: remote.apiKey must be set explicitly — GEMINI_API_KEY env var alone is NOT picked up by the plugin.
  GEMINI_KEY="${GEMINI_API_KEY:-$(grep '^GEMINI_API_KEY=' /data/.openclaw/secrets.env 2>/dev/null | cut -d= -f2- || true)}"
  MEMORY_PROVIDER=$(jq -r '.agents.defaults.memorySearch.provider // empty' "$CONFIG_FILE" 2>/dev/null)
  if [ -z "$MEMORY_PROVIDER" ]; then
    jq --arg apikey "${GEMINI_KEY}" '.agents.defaults.memorySearch = {
      "enabled": true,
      "provider": "gemini",
      "model": "gemini-embedding-001",
      "remote": {"apiKey": $apikey},
      "sources": ["memory"],
      "sync": {"watch": true, "onSearch": true, "onSessionStart": true},
      "query": {
        "maxResults": 10,
        "minScore": 0.25,
        "hybrid": {
          "enabled": true,
          "vectorWeight": 0.7,
          "textWeight": 0.3,
          "candidateMultiplier": 4,
          "mmr": {"enabled": true, "lambda": 0.7},
          "temporalDecay": {"enabled": true, "halfLifeDays": 30}
        }
      }
    }' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Seeded memorySearch provider=gemini/gemini-embedding-001"
  fi
  # Always: refresh memorySearch apiKey from secrets.env (credential rotation support)
  if [ -n "$GEMINI_KEY" ]; then
    jq --arg apikey "${GEMINI_KEY}" '.agents.defaults.memorySearch.remote.apiKey = $apikey' \
      "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  fi
  # Patch: enable memory_search + memory_get via tools.alsoAllow (additive).
  # Cannot use tools.allow — openclaw rejects allow+alsoAllow together, and allow with unknown
  # entries (e.g. group:memory before memorySearch initializes) causes the entire allowlist to be ignored.
  # Cleanup: remove tools.allow if it only contains group:memory (stale from old patch).
  if jq -e '.tools.allow == ["group:memory"]' "$CONFIG_FILE" &>/dev/null; then
    jq 'del(.tools.allow)' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Removed stale tools.allow=[group:memory] (replaced by alsoAllow)"
  fi
  HAS_MEMORY_ALSO=$(jq -r '.tools.alsoAllow // [] | map(select(. == "group:memory")) | length' "$CONFIG_FILE" 2>/dev/null)
  if [ "$HAS_MEMORY_ALSO" = "0" ]; then
    jq '.tools.alsoAllow = ((.tools.alsoAllow // []) + ["group:memory"] | unique)' \
      "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Added group:memory to tools.alsoAllow (memory_search + memory_get)"
  fi
  # Seed-once: sub-agent model defaults (only if empty — agent manages after first boot)
  SUBAGENT_MODEL=$(jq -r '.agents.defaults.subagents.model.primary // empty' "$CONFIG_FILE" 2>/dev/null)
  if [ -z "$SUBAGENT_MODEL" ]; then
    jq '.agents.defaults.subagents = {
      "model": {"primary": "openrouter/minimax/minimax-m2.7"},
      "maxSpawnDepth": 2,
      "maxChildrenPerAgent": 5,
      "maxConcurrent": 8,
      "archiveAfterMinutes": 60
    }' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Seeded sub-agent model to openrouter/minimax/minimax-m2.7"
  fi
  # Seed-once: heartbeat model (only if empty — agent manages after first boot)
  HEARTBEAT_MODEL=$(jq -r '.agents.defaults.heartbeat.model // empty' "$CONFIG_FILE" 2>/dev/null)
  if [ -z "$HEARTBEAT_MODEL" ]; then
    jq '.agents.defaults.heartbeat.model = "openrouter/openai/gpt-5-nano"' \
      "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Seeded heartbeat model to openrouter/openai/gpt-5-nano"
  fi
  # Patch: image/vision model (must be object with primary key)
  IMAGE_MODEL=$(jq -r '.agents.defaults.imageModel.primary // empty' "$CONFIG_FILE" 2>/dev/null)
  if [ -z "$IMAGE_MODEL" ]; then
    jq '.agents.defaults.imageModel = {"primary": "openrouter/google/gemini-3-pro-image-preview"}' \
      "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Set image model to openrouter/google/gemini-3-pro-image-preview"
  fi
  # Seed-once: fallback models (only if missing/null — agent manages after first boot)
  FALLBACKS_EXISTS=$(jq -r '.agents.defaults.model.fallbacks // empty' "$CONFIG_FILE" 2>/dev/null)
  if [ -z "$FALLBACKS_EXISTS" ]; then
    jq '.agents.defaults.model.fallbacks = [
      "openrouter/anthropic/claude-sonnet-4-5",
      "openrouter/minimax/minimax-m2.7",
      "openrouter/auto"
    ]' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Seeded model fallbacks (sonnet → minimax-m2.7 → auto)"
  fi
  # Patch: ensure Tailscale subnet 100.64.0.0/10 is in trustedProxies (Phase 7 — for MacBook access)
  HAS_TS_PROXY=$(jq -r '.gateway.trustedProxies // [] | index("100.64.0.0/10") // empty' "$CONFIG_FILE" 2>/dev/null)
  if [ -z "$HAS_TS_PROXY" ]; then
    jq '.gateway.trustedProxies = ((.gateway.trustedProxies // []) + ["100.64.0.0/10"] | unique)' \
      "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Added 100.64.0.0/10 to gateway.trustedProxies (Tailscale subnet)"
  fi
  # Patch: gateway.bind=loopback + tailscale.mode=serve (Phase 7)
  # bind=loopback means gateway only listens on 127.0.0.1 — Tailscale Serve proxies HTTPS
  CURRENT_BIND=$(jq -r '.gateway.bind // empty' "$CONFIG_FILE" 2>/dev/null)
  if [ "$CURRENT_BIND" != "loopback" ]; then
    jq '.gateway.bind = "loopback"' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Set gateway.bind=loopback (Tailscale Serve handles external access)"
  fi
  CURRENT_TS_MODE=$(jq -r '.gateway.tailscale.mode // empty' "$CONFIG_FILE" 2>/dev/null)
  if [ "$CURRENT_TS_MODE" != "serve" ]; then
    jq '.gateway.tailscale = {"mode": "serve", "resetOnExit": false}' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Set gateway.tailscale.mode=serve"
  fi
  # Patch: fix agents.list model fields — convert string-form model refs to object form.
  # openclaw does not properly resolve a string model ref in agents.list when ANTHROPIC_API_KEY is
  # set — it falls back to anthropic/claude-opus-4-6 instead of the configured OpenRouter model.
  # Fix: for each agent with a string model field, convert to {"primary": <string>} object form.
  jq '(.agents.list // []) |= map(
    if (.model | type) == "string" then
      .model = {"primary": .model, "fallbacks": ["openrouter/minimax/minimax-m2.7", "openrouter/auto"]}
    else
      .
    end
  )' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  echo "[config] Normalized agents.list model fields to object form (prevents Opus fallback)"
  # Patch: disable useAccessGroups so sub-agents get full operator scope without pairing
  jq '.commands.useAccessGroups = false' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  echo "[config] Set commands.useAccessGroups=false (sub-agent scope fix)"
  # NOTE: gateway.dangerouslyDisableDeviceAuth is NOT a valid gateway key in 2026.2.19+
  # (causes "Unrecognized key" crash). Remove it if agent or previous bootstrap added it.
  jq 'del(.gateway.dangerouslyDisableDeviceAuth)' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  # Patch: remove invalid commands keys if agent accidentally added them
  jq 'del(.commands.gateway) | del(.commands.restart)' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  # Patch: remove invalid heartbeat keys agent may write (intervalMinutes is not valid — use "every")
  jq 'del(.agents.defaults.heartbeat.intervalMinutes) |
      (.agents.list // []) |= map(del(.heartbeat.intervalMinutes))' \
    "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  # Cleanup: remove retired Directors from agents.list (company automation paused)
  for _retired_id in automation-supervisor budget-cfo business-researcher; do
    if jq -e --arg id "$_retired_id" '.agents.list[] | select(.id == $id)' "$CONFIG_FILE" &>/dev/null; then
      jq --arg id "$_retired_id" '.agents.list |= map(select(.id != $id))' \
        "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
      echo "[config] Removed $_retired_id from agents.list (retired)"
    fi
  done

  # Seed-once: model aliases (only if agents.defaults.models is null/empty)
  MODELS_COUNT=$(jq -r '.agents.defaults.models // {} | length' "$CONFIG_FILE" 2>/dev/null)
  if [ "${MODELS_COUNT:-0}" -eq 0 ]; then
    jq '
      .agents.defaults.models["openrouter/google/gemini-3.1-pro-preview"] = {"alias": "gemini-3.1-pro-preview"} |
      .agents.defaults.models["openrouter/minimax/minimax-m2.7"] = {"alias": "minimax-m2.7"} |
      .agents.defaults.models["openrouter/anthropic/claude-haiku-4-5"] = {"alias": "claude-haiku-4-5"} |
      .agents.defaults.models["openrouter/anthropic/claude-sonnet-4.6"] = {"alias": "claude-sonnet-4.6"} |
      .agents.defaults.models["openrouter/openai/gpt-5.2"] = {"alias": "gpt-5.2"} |
      .agents.defaults.models["openrouter/minimax/minimax-m2.5"] = {"alias": "minimax-m2.5"} |
      .agents.defaults.models["openrouter/openai/gpt-5-nano"] = {"alias": "gpt-5-nano"}
    ' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Seeded model aliases in agents.defaults.models"
  fi

  # Patch: deny gateway tool globally — prevents any agent from patching config via gateway tool
  # (chmod 444 on openclaw.json covers file writes; this covers config.apply/config.patch via gateway process)
  HAS_GATEWAY_DENY=$(jq -r '.tools.deny // [] | index("gateway") // empty' "$CONFIG_FILE" 2>/dev/null)
  if [ -z "$HAS_GATEWAY_DENY" ]; then
    jq '.tools.deny = ((.tools.deny // []) + ["gateway"] | unique)' \
      "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Added gateway to tools.deny (prevents config.apply/patch via agent)"
  fi
  # Patch: Matrix channel config (Phase 2) — uses env vars from Coolify
  # Only patch if MATRIX_HOMESERVER and MATRIX_PASSWORD are set and channel not yet configured
  if [ -n "${MATRIX_HOMESERVER:-}" ] && [ -n "${MATRIX_PASSWORD:-}" ]; then
    MATRIX_ENABLED=$(jq -r '.channels.matrix.enabled // empty' "$CONFIG_FILE" 2>/dev/null)
    if [ "$MATRIX_ENABLED" != "true" ]; then
      jq --arg hs "${MATRIX_HOMESERVER}" \
         --arg uid "@${MATRIX_USER_ID:-bot}:matrix.aakashe.org" \
         --arg pw "${MATRIX_PASSWORD}" \
         '.channels = (.channels // {}) |
          .channels.matrix = {
            "enabled": true,
            "homeserver": $hs,
            "userId": $uid,
            "password": $pw,
            "groupPolicy": "disabled",
            "dm": {"policy": "allowlist", "allowFrom": ["@ameer:matrix.aakashe.org"]},
            "encryption": true,
            "markdown": {"tables": "bullets"},
            "chunkMode": "newline"
          }' \
         "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
      echo "[config] Configured channels.matrix (homeserver=${MATRIX_HOMESERVER}, userId=@${MATRIX_USER_ID:-bot}:matrix.aakashe.org)"
    fi
  fi
fi

# Lock config read-only so agent cannot overwrite it via bash between boots
chmod 444 "$CONFIG_FILE"
echo "[config] Locked openclaw.json read-only"

# Verify config is valid after patching — revert to backup if not
if ! jq empty "$CONFIG_FILE" &>/dev/null; then
  echo "[config] WARNING: openclaw.json is invalid after patching — reverting to backup"
  if [ -f "$CONFIG_BACKUP" ] && jq empty "$CONFIG_BACKUP" &>/dev/null; then
    cp "$CONFIG_BACKUP" "$CONFIG_FILE"
    chmod 444 "$CONFIG_FILE"
    echo "[config] Reverted to pre-patch backup"
  else
    echo "[config] ERROR: backup also invalid — regenerating from scratch on next restart"
    rm -f "$CONFIG_FILE"
  fi
else
  echo "[config] Config verified valid after patching"
  rm -f "$CONFIG_BACKUP"
fi

# ----------------------------
# Export state
# ----------------------------
export OPENCLAW_STATE_DIR="$OPENCLAW_STATE"

# ----------------------------
# System services
# ----------------------------
# Start cron daemon for periodic tasks (BWS refresh)
/usr/sbin/cron 2>/dev/null || true

# Matrix plugin: install fixed copy to persistent volume (runs once, survives deploys)
# The bundled copy at npm root has pnpm workspace:* refs npm can't resolve.
# Install to /data/.openclaw/extensions/matrix (persistent volume) so npm install
# only runs once ever, not on every deploy. Remove bundled copy to prevent duplicate warning.
MATRIX_USER_EXT="/data/.openclaw/extensions/matrix"
MATRIX_BUNDLED="/usr/local/lib/node_modules/openclaw/extensions/matrix"
if [ ! -d "$MATRIX_USER_EXT/node_modules/@vector-im" ]; then
  echo "[matrix] Installing matrix plugin to persistent volume (one-time)..."
  mkdir -p "/data/.openclaw/extensions"
  rm -rf "$MATRIX_USER_EXT" 2>/dev/null || true
  cp -r "$MATRIX_BUNDLED" "$MATRIX_USER_EXT" 2>/dev/null || true
  if [ -d "$MATRIX_USER_EXT" ]; then
    sed -i 's/"workspace:\*"/"*"/g' "$MATRIX_USER_EXT/package.json" 2>/dev/null || true
    cd "$MATRIX_USER_EXT" && npm install --omit=dev --quiet 2>/dev/null \
      && echo "[matrix] Matrix plugin installed to persistent volume" \
      || echo "[matrix] WARNING: matrix npm install failed"
  fi
fi
# Remove bundled copy — user copy on volume takes precedence, prevents duplicate warning
rm -rf "$MATRIX_BUNDLED" 2>/dev/null || true

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

# Claude Code CLI: disable auto-updater on server (prevents version drift)
# Auth is via subscription OAuth stored in /data/.claude/ — no API key needed
CLAUDE_DIR="/data/.claude"
mkdir -p "$CLAUDE_DIR"
CLAUDE_SETTINGS_ENV="$CLAUDE_DIR/settings.env"
if ! grep -q "DISABLE_AUTOUPDATER" "$CLAUDE_SETTINGS_ENV" 2>/dev/null; then
  echo "DISABLE_AUTOUPDATER=1" >> "$CLAUDE_SETTINGS_ENV"
  echo "[claude] Wrote DISABLE_AUTOUPDATER=1 to $CLAUDE_SETTINGS_ENV"
fi


# ----------------------------
# One-time workspace cleanup (runs once, sentinel prevents re-run)
# ----------------------------
CLEANUP_SENTINEL="/data/.openclaw/.reboot-cleanup-done"
if [ ! -f "$CLEANUP_SENTINEL" ]; then
  echo "[cleanup] Running one-time workspace cleanup..."
  ARCHIVE_DIR="/data/openclaw-workspace.pre-reboot"
  mkdir -p "$ARCHIVE_DIR"

  # Archive stale workspace directories
  for _dir in agents leads projects tools cron docs scripts state backups config; do
    if [ -d "$WORKSPACE_DIR/$_dir" ]; then
      mv "$WORKSPACE_DIR/$_dir" "$ARCHIVE_DIR/$_dir" 2>/dev/null || true
      echo "[cleanup] Archived $WORKSPACE_DIR/$_dir"
    fi
  done

  # Remove stale root files (keep core OpenClaw files)
  for _file in COMPANY_MEMORY.md ARCHITECTURE_PLAN.md BOOTSTRAP.md n8n_WORKFLOW_REGISTRY.md SECURITY.local.md; do
    rm -f "$WORKSPACE_DIR/$_file" 2>/dev/null
  done
  # Remove backup/log artifacts
  rm -f "$WORKSPACE_DIR"/SOUL.md.backup.* "$WORKSPACE_DIR"/HEARTBEAT.md.bak.* 2>/dev/null
  rm -f "$WORKSPACE_DIR"/monitor.log "$WORKSPACE_DIR"/recovery.log "$WORKSPACE_DIR"/subagent-poll.log 2>/dev/null
  rm -f "$WORKSPACE_DIR"/last_id.txt "$WORKSPACE_DIR"/quick_id.txt "$WORKSPACE_DIR"/spoke_id.txt 2>/dev/null

  touch "$CLEANUP_SENTINEL"
  echo "[cleanup] One-time workspace cleanup complete (sentinel: $CLEANUP_SENTINEL)"
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
echo "  2. Access Control UI: https://${TS_HOSTNAME:-openclaw-server}.[tailnet].ts.net"
echo "  3. Approve this machine: openclaw-approve"
echo "  4. Start onboarding: openclaw onboard"
echo ""
echo "=================================================================="

# ----------------------------
# Tailscale Startup (Phase 7)
# ----------------------------
# OpenClaw with tailscale.mode=serve requires tailscaled running and authenticated.
# Uses userspace networking — no NET_ADMIN cap or /dev/net/tun needed.
# State persisted to /data/tailscale/ (existing volume) to survive restarts.
if command -v tailscaled >/dev/null 2>&1; then
  TS_STATE="/data/tailscale"
  mkdir -p "$TS_STATE"
  tailscaled --tun=userspace-networking \
    --statedir="$TS_STATE" \
    --socket=/var/run/tailscale/tailscaled.sock \
    >/tmp/tailscaled.log 2>&1 &
  TAILSCALED_PID=$!
  echo "[tailscale] Started tailscaled (PID $TAILSCALED_PID, userspace networking)"

  # Wait for socket to be available (up to 10s)
  for i in $(seq 1 10); do
    [ -S /var/run/tailscale/tailscaled.sock ] && break
    sleep 1
  done

  # Brief pause after socket appears — daemon may not be fully ready yet
  sleep 1

  # Verify daemon is responsive before proceeding
  tailscale --socket=/var/run/tailscale/tailscaled.sock status >/dev/null 2>&1 || echo "[tailscale] WARNING: tailscaled socket exists but daemon not yet responsive"

  # Authenticate — try reconnecting with persisted node key first (avoids expired TS_AUTHKEY problem).
  # tailscale up without --auth-key reconnects if node is already registered (node key persists in /data/tailscale/).
  # Only falls back to TS_AUTHKEY if node key is missing (fresh machine registration).
  echo "[tailscale] Attempting reconnect with existing node key..."
  if tailscale --socket=/var/run/tailscale/tailscaled.sock up \
      --hostname="${TS_HOSTNAME:-openclaw-server}" \
      --accept-routes 2>&1; then
    echo "[tailscale] Reconnected using existing node key"
  elif [ -n "${TS_AUTHKEY:-}" ]; then
    echo "[tailscale] No existing node key — authenticating with TS_AUTHKEY..."
    tailscale --socket=/var/run/tailscale/tailscaled.sock up \
      --auth-key="${TS_AUTHKEY}" \
      --hostname="${TS_HOSTNAME:-openclaw-server}" \
      --accept-routes 2>&1 || echo "[tailscale] WARNING: tailscale up failed — TS_AUTHKEY may be expired; update in Coolify"
  else
    echo "[tailscale] WARNING: No existing node key and TS_AUTHKEY not set — tailscale will not work"
  fi

  # Wait for tailscale to be connected (up to 30s)
  TS_READY=false
  for i in $(seq 1 15); do
    if tailscale --socket=/var/run/tailscale/tailscaled.sock status --json 2>/dev/null \
        | jq -e '.BackendState == "Running"' >/dev/null 2>&1; then
      TS_IP=$(tailscale --socket=/var/run/tailscale/tailscaled.sock ip -4 2>/dev/null || true)
      TS_READY=true
      echo "[tailscale] Connected to tailnet (IP: ${TS_IP:-unknown})"
      break
    fi
    sleep 2
  done
  if [ "$TS_READY" = "false" ]; then
    echo "[tailscale] WARNING: tailscale not connected after 30s — gateway may fail with tailscale.mode=serve"
  fi

  # Pre-configure tailscale serve before openclaw starts.
  # openclaw calls `tailscale serve --bg --yes 18789` internally when tailscale.mode=serve,
  # but `--yes` is not valid in tailscale v1.94.2. Pre-configuring here ensures serve is active
  # even if openclaw's internal call fails. Serve config persists in /data/tailscale/ state.
  if [ "$TS_READY" = "true" ]; then
    GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
    tailscale --socket=/var/run/tailscale/tailscaled.sock serve --bg "$GATEWAY_PORT" >/dev/null 2>&1 \
      && echo "[tailscale] Serve configured: https://${TS_HOSTNAME:-openclaw-server}.[tailnet].ts.net -> :${GATEWAY_PORT}" \
      || echo "[tailscale] WARNING: tailscale serve pre-config failed (Serve may need enabling in Tailscale admin console)"

    # Patch controlUi.allowedOrigins to include the Tailscale HTTPS URL so the browser
    # origin is trusted (gateway is on loopback, browser hits https://<hostname>.<tailnet>).
    TS_DOMAIN=$(tailscale --socket=/var/run/tailscale/tailscaled.sock status --json 2>/dev/null \
      | jq -r '.MagicDNSSuffix // empty' 2>/dev/null || true)
    if [ -n "$TS_DOMAIN" ]; then
      TS_ORIGIN="https://${TS_HOSTNAME:-openclaw-server}.${TS_DOMAIN}"
      chmod 644 "$CONFIG_FILE"
      jq --arg origin "$TS_ORIGIN" '
        if (.gateway.controlUi.allowedOrigins // [] | map(. == $origin) | any) then .
        else .gateway.controlUi.allowedOrigins = ((.gateway.controlUi.allowedOrigins // []) + [$origin])
        end
      ' "$CONFIG_FILE" > /tmp/openclaw-config-patched.json \
        && mv /tmp/openclaw-config-patched.json "$CONFIG_FILE" \
        && echo "[tailscale] Patched controlUi.allowedOrigins: $TS_ORIGIN"
      chmod 444 "$CONFIG_FILE"
    fi
  fi

  # Log tailscale serve status for diagnostics
  echo "[tailscale] Serve status at startup:"
  tailscale --socket=/var/run/tailscale/tailscaled.sock serve status 2>&1 || true
fi

hash -r 2>/dev/null || true
exec openclaw gateway run