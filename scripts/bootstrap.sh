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
    # AGENTS.md: seed if missing only — agent's own version takes precedence
    if [ -f "/app/AGENTS.md" ] && [ ! -f "$dir/AGENTS.md" ]; then
      cp "/app/AGENTS.md" "$dir/AGENTS.md"
      echo "[seed] Copied AGENTS.md to $dir"
    fi
    # memory/patterns/: seed missing files only — agent writes to these during operation
    if [ -d "/app/memory/patterns" ]; then
      mkdir -p "$dir/memory/patterns"
      for pattern in /app/memory/patterns/*.md; do
        local basename_file
        basename_file=$(basename "$pattern")
        if [ ! -f "$dir/memory/patterns/$basename_file" ]; then
          cp "$pattern" "$dir/memory/patterns/$basename_file"
          echo "[seed] Copied memory/patterns/$basename_file"
        fi
      done
    fi
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

# Seed Automation Supervisor workspace (cmp-based: propagates repo updates on redeploy)
# Per ARCHITECTURE_REFINEMENT.md Section 9 and Section 10
SUPERVISOR_DIR="/data/openclaw-workspace/agents/automation-supervisor"
mkdir -p "$SUPERVISOR_DIR/memory/patterns" "$SUPERVISOR_DIR/memory/schemas"

for doc in SOUL.md HEARTBEAT.md TOOLS.md; do
  REPO_DOC="/app/docs/reference/agents/automation-supervisor/$doc"
  DEST="$SUPERVISOR_DIR/$doc"
  if [ -f "$REPO_DOC" ]; then
    if [ ! -f "$DEST" ]; then
      cp "$REPO_DOC" "$DEST"
      echo "[seed] Copied automation-supervisor/$doc"
    elif ! cmp -s "$REPO_DOC" "$DEST"; then
      cp "$REPO_DOC" "$DEST"
      echo "[seed] Updated automation-supervisor/$doc (repo version changed)"
    fi
  fi
done

# Capability registry: cmp-based seed (propagates updates, never overwrites Supervisor's live edits
# unless repo version changed — Supervisor adds entries, repo updates structure/initial content)
CAPS_REPO="/app/docs/reference/agents/automation-supervisor/memory/schemas/capabilities.md"
CAPS_DEST="$SUPERVISOR_DIR/memory/schemas/capabilities.md"
if [ -f "$CAPS_REPO" ]; then
  if [ ! -f "$CAPS_DEST" ]; then
    cp "$CAPS_REPO" "$CAPS_DEST"
    echo "[seed] Copied automation-supervisor capabilities registry"
  fi
  # Note: NOT cmp-based for capabilities.md — Supervisor owns live updates.
  # Repo version is only seeded once; Supervisor appends its own capability entries.
fi

# AGENTS.md: seed if missing — agent's own version takes precedence once seeded
if [ -f "/app/AGENTS.md" ] && [ ! -f "$SUPERVISOR_DIR/AGENTS.md" ]; then
  cp "/app/AGENTS.md" "$SUPERVISOR_DIR/AGENTS.md"
  echo "[seed] Copied AGENTS.md to automation-supervisor workspace"
fi

# Seed ONBOARDING.md for all Director workspaces that don't have one yet
# Per ARCHITECTURE_PLAN.md Section 10: every Director should have an ONBOARDING.md
# automation-supervisor and main are excluded (handled separately or not applicable)
DIRECTORS_BASE="/data/openclaw-workspace/agents"
if [ -d "$DIRECTORS_BASE" ]; then
  for dir in "$DIRECTORS_BASE"/*/; do
    agent_id=$(basename "$dir")
    if [ "$agent_id" = "automation-supervisor" ] || [ "$agent_id" = "main" ]; then
      continue
    fi
    ONBOARDING_DEST="$dir/ONBOARDING.md"
    ONBOARDING_REPO="/app/docs/reference/agents/$agent_id/ONBOARDING.md"
    if [ ! -f "$ONBOARDING_DEST" ] && [ -f "$ONBOARDING_REPO" ]; then
      cp "$ONBOARDING_REPO" "$ONBOARDING_DEST"
      echo "[seed] Copied ONBOARDING.md to $agent_id workspace"
    fi
  done
fi

# COMPANY_MEMORY.md: seed to main workspace if missing
COMPANY_MEM="${WORKSPACE_DIR}/COMPANY_MEMORY.md"
if [ ! -f "$COMPANY_MEM" ] && [ -f "/app/docs/reference/COMPANY_MEMORY.md" ]; then
  cp "/app/docs/reference/COMPANY_MEMORY.md" "$COMPANY_MEM"
  echo "[seed] Created COMPANY_MEMORY.md in main workspace"
fi

# Weekly retrospective cron file: seed to main workspace if missing
CRON_DIR="${WORKSPACE_DIR}/cron"
mkdir -p "$CRON_DIR"
RETRO_SRC="/app/workspace/cron/weekly-retrospective.md"
RETRO_DEST="$CRON_DIR/weekly-retrospective.md"
if [ -f "$RETRO_SRC" ] && [ ! -f "$RETRO_DEST" ]; then
  cp "$RETRO_SRC" "$RETRO_DEST"
  echo "[seed] Created weekly-retrospective.md cron file in main workspace"
fi

# Seed n8n-project scaffold (CLAUDE.md and .mcp.json — cmp-based)
N8N_PROJECT_DIR="$SUPERVISOR_DIR/n8n-project"
mkdir -p "$N8N_PROJECT_DIR/workflows"
for f in CLAUDE.md .mcp.json; do
  REPO_F="/app/docs/reference/agents/automation-supervisor/n8n-project/$f"
  DEST_F="$N8N_PROJECT_DIR/$f"
  if [ -f "$REPO_F" ]; then
    if [ ! -f "$DEST_F" ]; then
      cp "$REPO_F" "$DEST_F"
      echo "[seed] Copied n8n-project/$f"
    elif ! cmp -s "$REPO_F" "$DEST_F"; then
      cp "$REPO_F" "$DEST_F"
      echo "[seed] Updated n8n-project/$f (repo version changed)"
    fi
  fi
done

# schemas symlink: point n8n-project/schemas -> ../memory/schemas
if [ ! -L "$N8N_PROJECT_DIR/schemas" ]; then
  ln -sf "$SUPERVISOR_DIR/memory/schemas" "$N8N_PROJECT_DIR/schemas"
  echo "[seed] Created n8n-project/schemas symlink -> memory/schemas"
fi

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
  # Patch: enable built-in memorySearch with Gemini embeddings (free, hybrid BM25+vector)
  # Force-update if provider != gemini OR remote.apiKey is missing.
  # CRITICAL: remote.apiKey must be set explicitly — GEMINI_API_KEY env var alone is NOT picked up by the plugin.
  MEMORY_PROVIDER=$(jq -r '.agents.defaults.memorySearch.provider // empty' "$CONFIG_FILE" 2>/dev/null)
  MEMORY_APIKEY=$(jq -r '.agents.defaults.memorySearch.remote.apiKey // empty' "$CONFIG_FILE" 2>/dev/null)
  if [ "$MEMORY_PROVIDER" != "gemini" ] || [ -z "$MEMORY_APIKEY" ]; then
    jq --arg apikey "${GEMINI_API_KEY:-}" '.agents.defaults.memorySearch = {
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
    echo "[config] Set memorySearch provider=gemini/gemini-embedding-001 with remote.apiKey"
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
  # Patch: set sub-agent model defaults (gemini-3-flash-preview — fast + cheap)
  # Force-update if unset or still on old haiku value
  SUBAGENT_MODEL=$(jq -r '.agents.defaults.subagents.model.primary // empty' "$CONFIG_FILE" 2>/dev/null)
  if [ -z "$SUBAGENT_MODEL" ] || [ "$SUBAGENT_MODEL" = "anthropic/claude-haiku-4-5" ] || [ "$SUBAGENT_MODEL" = "openrouter/anthropic/claude-haiku-4-5" ]; then
    jq '.agents.defaults.subagents = {
      "model": {"primary": "openrouter/google/gemini-3-flash-preview"},
      "maxSpawnDepth": 2,
      "maxChildrenPerAgent": 5,
      "maxConcurrent": 8,
      "archiveAfterMinutes": 60
    }' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Set sub-agent model to openrouter/google/gemini-3-flash-preview"
  fi
  # Patch: heartbeat model (gpt-5-nano — cheapest capable model for keepalives)
  # Force-update if unset or still on old haiku value
  HEARTBEAT_MODEL=$(jq -r '.agents.defaults.heartbeat.model // empty' "$CONFIG_FILE" 2>/dev/null)
  if [ -z "$HEARTBEAT_MODEL" ] || [ "$HEARTBEAT_MODEL" = "openrouter/anthropic/claude-haiku-4-5" ]; then
    jq '.agents.defaults.heartbeat.model = "openrouter/openai/gpt-5-nano"' \
      "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Set heartbeat model to openrouter/openai/gpt-5-nano"
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
  # Cleanup: remove stale temp patches from volume config (Phase 7)
  if jq -e '.gateway.mode == "remote"' "$CONFIG_FILE" &>/dev/null; then
    jq '.gateway.mode = "local"' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Reverted gateway.mode from remote to local (temp patch removed)"
  fi
  if jq -e '.gateway.remote != null' "$CONFIG_FILE" &>/dev/null; then
    jq 'del(.gateway.remote)' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Removed gateway.remote (temp patch removed)"
  fi
  # Patch: disable useAccessGroups so sub-agents get full operator scope without pairing
  jq '.commands.useAccessGroups = false' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  echo "[config] Set commands.useAccessGroups=false (sub-agent scope fix)"
  # NOTE: gateway.dangerouslyDisableDeviceAuth is NOT a valid gateway key in 2026.2.19+
  # (causes "Unrecognized key" crash). Remove it if agent or previous bootstrap added it.
  jq 'del(.gateway.dangerouslyDisableDeviceAuth)' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  # Patch: remove invalid commands keys if agent accidentally added them
  jq 'del(.commands.gateway) | del(.commands.restart)' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

  # Patch: add automation-supervisor Director to agents.list (idempotent)
  # Per ARCHITECTURE_REFINEMENT.md Section 10 — only Supervisor is hardcoded in bootstrap.sh
  HAS_SUPERVISOR=$(jq -r '.agents.list[] | select(.id == "automation-supervisor") | .id' "$CONFIG_FILE" 2>/dev/null)
  if [ -z "$HAS_SUPERVISOR" ]; then
    jq --arg ws "/data/openclaw-workspace/agents/automation-supervisor" \
       '.agents.list += [{
         "id": "automation-supervisor",
         "name": "Automation Supervisor",
         "workspace": $ws,
         "default": false,
         "model": {
           "primary": "openrouter/google/gemini-3.1-pro-preview",
           "fallbacks": ["openrouter/google/gemini-3-flash-preview", "openrouter/auto"]
         },
         "heartbeat": {
           "every": "1h",
           "model": "openrouter/openai/gpt-5-nano"
         }
       }]' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Added automation-supervisor Director to agents.list"
  fi

  # Cleanup: remove invalid contextWindow/maxTokens from model entries (written by broken patch c4cbc46)
  # These fields are only valid for custom local providers (litellm/vllm/ollama), not OpenRouter entries.
  if jq -e '.agents.defaults.models | to_entries[] | .value | has("contextWindow") or has("maxTokens")' "$CONFIG_FILE" &>/dev/null 2>&1; then
    jq '.agents.defaults.models |= with_entries(.value |= del(.contextWindow, .maxTokens))' \
      "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Removed invalid contextWindow/maxTokens from agents.defaults.models entries"
  fi
  # Patch: set model aliases in agents.defaults.models (alias only — display name in CLI/UI)
  jq '
    .agents.defaults.models["openrouter/google/gemini-3.1-pro-preview"] //= {} |
    .agents.defaults.models["openrouter/google/gemini-3.1-pro-preview"].alias = "gemini-3.1-pro-preview" |

    .agents.defaults.models["openrouter/google/gemini-3-flash-preview"] //= {} |
    .agents.defaults.models["openrouter/google/gemini-3-flash-preview"].alias = "gemini-3-flash-preview" |

    .agents.defaults.models["openrouter/anthropic/claude-haiku-4-5"] //= {} |
    .agents.defaults.models["openrouter/anthropic/claude-haiku-4-5"].alias = "claude-haiku-4-5" |

    .agents.defaults.models["openrouter/anthropic/claude-sonnet-4.6"] //= {} |
    .agents.defaults.models["openrouter/anthropic/claude-sonnet-4.6"].alias = "claude-sonnet-4.6" |

    .agents.defaults.models["openrouter/openai/gpt-5.2"] //= {} |
    .agents.defaults.models["openrouter/openai/gpt-5.2"].alias = "gpt-5.2" |

    .agents.defaults.models["openrouter/minimax/minimax-m2.5"] //= {} |
    .agents.defaults.models["openrouter/minimax/minimax-m2.5"].alias = "minimax-m2.5" |

    .agents.defaults.models["openrouter/openai/gpt-5-nano"] //= {} |
    .agents.defaults.models["openrouter/openai/gpt-5-nano"].alias = "gpt-5-nano"
  ' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  echo "[config] Set model aliases in agents.defaults.models"

  # Patch: add COMPANY_MEMORY.md to agents.defaults.memorySearch.extraPaths
  # Per ARCHITECTURE_REFINEMENT.md Section 4 — one patch makes it searchable by ALL agents
  COMPANY_MEM_PATH="${WORKSPACE_DIR}/COMPANY_MEMORY.md"
  HAS_COMPANY_PATH=$(jq -r --arg p "$COMPANY_MEM_PATH" \
    '.agents.defaults.memorySearch.extraPaths // [] | index($p) // empty' \
    "$CONFIG_FILE" 2>/dev/null)
  if [ -z "$HAS_COMPANY_PATH" ]; then
    jq --arg p "$COMPANY_MEM_PATH" \
       '.agents.defaults.memorySearch.extraPaths = ((.agents.defaults.memorySearch.extraPaths // []) + [$p] | unique)' \
       "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "[config] Added COMPANY_MEMORY.md to agents.defaults.memorySearch.extraPaths"
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
            "dm": {"policy": "pairing"},
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
# Start cron daemon for periodic tasks (BWS refresh, NOVA catch-up)
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

# Write BWS-sourced credentials to files (not available during early credential isolation)
for var in N8N_API_KEY; do
    if [ -n "${!var:-}" ]; then
        printf '%s' "${!var}" > "$CRED_DIR/$var"
        chmod 600 "$CRED_DIR/$var"
        echo "[credentials] wrote BWS-sourced $var to credential file"
        unset "$var"
    fi
done

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

  # Authenticate (idempotent — skips if already logged in from persisted state)
  if [ -n "${TS_AUTHKEY:-}" ]; then
    tailscale --socket=/var/run/tailscale/tailscaled.sock up \
      --auth-key="${TS_AUTHKEY}" \
      --hostname="${TS_HOSTNAME:-openclaw-server}" \
      --accept-routes 2>&1 || echo "[tailscale] WARNING: tailscale up failed (may already be authenticated)"
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
  fi

  # Log tailscale serve status for diagnostics
  echo "[tailscale] Serve status at startup:"
  tailscale --socket=/var/run/tailscale/tailscaled.sock serve status 2>&1 || true
fi

hash -r 2>/dev/null || true
exec openclaw gateway run