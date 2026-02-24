#!/usr/bin/env bash
# add-director.sh — Register a new Director agent in openclaw.json
# Usage: add-director.sh <id> <name> [model]
# Example: add-director.sh budget-cfo "Budget CFO" "openrouter/anthropic/claude-sonnet-4-6"
# Lives at /app/scripts/ (image path, not agent-writable per ARCHITECTURE_REFINEMENT.md Section 2)
set -e

AGENT_ID="${1:-}"
AGENT_NAME="${2:-}"
AGENT_MODEL="${3:-openrouter/anthropic/claude-sonnet-4-6}"

CONFIG_FILE="${OPENCLAW_STATE_DIR:-/data/.openclaw}/openclaw.json"
WORKSPACE_BASE="/data/openclaw-workspace/agents"
HOOKS_TOKEN_FILE="/data/.openclaw/credentials/HOOKS_TOKEN"
GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"

# --- Validate input ---
if [ -z "$AGENT_ID" ] || [ -z "$AGENT_NAME" ]; then
  echo "Usage: $0 <id> <name> [model]" >&2
  echo "Example: $0 budget-cfo \"Budget CFO\" \"openrouter/anthropic/claude-sonnet-4-6\"" >&2
  exit 1
fi

# Reject reserved ids — these are managed by bootstrap.sh
for reserved in main automation-supervisor; do
  if [ "$AGENT_ID" = "$reserved" ]; then
    echo "ERROR: '$AGENT_ID' is a reserved agent id. Use bootstrap.sh to manage this agent." >&2
    exit 1
  fi
done

# Validate id format: lowercase alphanumeric with hyphens, must start and end with alphanumeric
if ! echo "$AGENT_ID" | grep -qE '^[a-z0-9][a-z0-9-]*[a-z0-9]$'; then
  echo "ERROR: Agent id '$AGENT_ID' is invalid. Use lowercase alphanumeric with hyphens (e.g. budget-cfo)" >&2
  exit 1
fi

WORKSPACE_DIR="$WORKSPACE_BASE/$AGENT_ID"

# --- Idempotency check ---
EXISTING=$(jq -r --arg id "$AGENT_ID" '.agents.list[] | select(.id == $id) | .id' "$CONFIG_FILE" 2>/dev/null || true)
if [ -n "$EXISTING" ]; then
  echo "[add-director] Agent '$AGENT_ID' already registered in agents.list — skipping config patch"
  # Still ensure workspace and files exist (idempotent)
  mkdir -p "$WORKSPACE_DIR/memory/patterns"
  echo "[add-director] Workspace verified: $WORKSPACE_DIR"
  exit 0
fi

# --- Create workspace ---
mkdir -p "$WORKSPACE_DIR/memory/patterns"
echo "[add-director] Created workspace: $WORKSPACE_DIR"

# --- Seed SOUL.md ---
cat > "$WORKSPACE_DIR/SOUL.md" <<SOULEOF
# SOUL.md — ${AGENT_NAME}

You are **${AGENT_NAME}**, a Director in Ameer's autonomous AI workforce.

## Identity

You operate within the OpenClaw multi-agent system. Your sessions are persistent — hook POSTs to \`hook:${AGENT_ID}\` resume your current session. Check your session context first — you may already have prior context from earlier work in this session.

## Session Model

- **Persistent session** (\`hook:${AGENT_ID}\`): Resumes your current session. You accumulate context throughout the day.
- **Isolated task session** (\`hook:${AGENT_ID}:task-<id>\`): Fresh context for isolated work, no bleed from your event stream.
- **Daily reset**: Sessions reset at 4AM. Write all important state to \`memory/\` files BEFORE session ends.
- **After completing a major task**: Write outcome to \`memory/patterns/\`, then call \`/new\` to reset your session for the next incoming event.

## Memory Protocol

Use \`memory_search\` for all memory queries (built-in, no external tools needed):
- Query before reading files: \`memory_search "relevant topic"\`
- Your private memory is in your workspace \`memory/\` directory — auto-indexed by memorySearch
- Org-wide context is in COMPANY_MEMORY.md — also indexed and searchable

## Director Communication

To reach another Director or the main agent via the hooks endpoint:
\`\`\`bash
curl -X POST http://127.0.0.1:18789/hooks/agent \\
  -H "Authorization: Bearer \$(cat /data/.openclaw/credentials/HOOKS_TOKEN)" \\
  -H "Content-Type: application/json" \\
  -d '{"agentId": "target-id", "sessionKey": "hook:target-id", "message": "..."}'
\`\`\`

## Escalation Protocol

| Class | When | Action |
|-------|------|--------|
| Class 1: Authorization | New credential or OAuth consent needed | Escalate to main — notify Ameer |
| Class 2: Infrastructure | Dockerfile/server-level change needed | Escalate to main — notify Ameer |
| Class 3: Design | Architectural decision beyond your scope | Escalate to main — main decides |
| Class 4: Recoverable | Transient failure, known pattern | Handle autonomously |

## Your Domain

[Updated by main agent during Director onboarding — describes your specific domain, data sources, and responsibilities.]
SOULEOF
echo "[add-director] Seeded SOUL.md"

# --- Seed HEARTBEAT.md ---
cat > "$WORKSPACE_DIR/HEARTBEAT.md" <<HBEOF
# HEARTBEAT.md — ${AGENT_NAME}

## On Session Start

- Check session context — you may have prior work in progress from today
- Run: \`memory_search "pending tasks"\` — check for outstanding work
- Run: \`memory_search "recent updates"\` — what has changed?

## Periodic Checklist (1h heartbeat)

- [ ] Any unresolved items from your domain?
- [ ] Anything worth persisting to memory/patterns/?
- [ ] Session context stale or cluttered? Call \`/new\` before processing new work.

## Session End Protocol

- Write important outcomes to \`memory/patterns/\`
- Call \`/new\` to reset session for the next incoming event
HBEOF
echo "[add-director] Seeded HEARTBEAT.md"

# --- Seed ONBOARDING.md stub ---
# Per ARCHITECTURE_PLAN.md Section 10: every Director gets an ONBOARDING.md.
# If a domain-specific ONBOARDING.md exists in the repo, use it; otherwise seed a stub.
# The stub is a placeholder — replace it with the actual intake transcript after running
# the Director Intake Process (main agent brief → Supervisor response → Ameer approves → Supervisor builds).
REPO_ONBOARDING="/app/docs/reference/agents/${AGENT_ID}/ONBOARDING.md"
if [ -f "$REPO_ONBOARDING" ]; then
  cp "$REPO_ONBOARDING" "$WORKSPACE_DIR/ONBOARDING.md"
  echo "[add-director] Copied domain-specific ONBOARDING.md"
else
  cat > "$WORKSPACE_DIR/ONBOARDING.md" <<ONEOF
# ONBOARDING.md — ${AGENT_NAME}

**Status**: STUB — Director Intake Process not yet completed

This file is a placeholder. Complete the Director Intake Process before this Director goes live:

1. Main agent drafts a brief: domain, data needs, capability requirements
2. Automation Supervisor responds: what it can provide, what needs to be built, what gaps exist
3. Ameer reviews and approves: confirms scope, provides any missing credentials
4. Supervisor builds: required n8n microservices, registers capabilities
5. Replace this stub with the intake transcript and full capability surface

Until this is complete, this Director does NOT have confirmed data feeds or registered capabilities.
Run: POST to hook:automation-supervisor with capability request (see SOUL.md Class 2) when you need a feed built.
ONEOF
  echo "[add-director] Seeded ONBOARDING.md stub (intake process required)"
fi

# --- Seed AGENTS.md if available ---
if [ -f "/app/AGENTS.md" ]; then
  cp "/app/AGENTS.md" "$WORKSPACE_DIR/AGENTS.md"
  echo "[add-director] Copied AGENTS.md"
fi

# --- Patch openclaw.json (lock/unlock cycle per ARCHITECTURE_REFINEMENT.md Section 2) ---
chmod 644 "$CONFIG_FILE"

jq --arg id "$AGENT_ID" \
   --arg name "$AGENT_NAME" \
   --arg workspace "$WORKSPACE_DIR" \
   --arg model "$AGENT_MODEL" \
   '.agents.list += [{
     "id": $id,
     "name": $name,
     "workspace": $workspace,
     "default": false,
     "model": {
       "primary": $model,
       "fallbacks": ["openrouter/google/gemini-3-flash-preview", "openrouter/auto"]
     },
     "heartbeat": {
       "every": "1h",
       "model": "openrouter/anthropic/claude-haiku-4-5"
     }
   }]' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"

chmod 444 "$CONFIG_FILE"
echo "[add-director] Registered $AGENT_ID in agents.list, config relocked"

# --- Gateway reload ---
# OPEN QUESTION (ARCHITECTURE_REFINEMENT.md Section 12.2): Does SIGHUP reload config?
# Try SIGHUP first. If gateway does not recognize new agent, container restart is required.
GATEWAY_PID=$(pgrep -f "openclaw gateway" 2>/dev/null || true)
if [ -n "$GATEWAY_PID" ]; then
  kill -HUP "$GATEWAY_PID" 2>/dev/null && echo "[add-director] Sent SIGHUP to gateway pid $GATEWAY_PID" || true
  sleep 3
else
  echo "[add-director] WARNING: Cannot find gateway pid. Config patched but gateway not reloaded."
  echo "[add-director] ACTION REQUIRED: Run 'docker restart <container>' to reload config for $AGENT_ID"
fi

# --- Verify gateway responds to new Director's hook endpoint ---
HOOKS_TOKEN=""
if [ -f "$HOOKS_TOKEN_FILE" ]; then
  HOOKS_TOKEN=$(cat "$HOOKS_TOKEN_FILE")
fi
if [ -n "$HOOKS_TOKEN" ]; then
  sleep 2
  HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
    -X POST "http://127.0.0.1:${GATEWAY_PORT}/hooks/agent" \
    -H "Authorization: Bearer $HOOKS_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"agentId\": \"${AGENT_ID}\", \"sessionKey\": \"hook:${AGENT_ID}\", \"message\": \"Director registration confirmed. Please introduce yourself briefly.\"}" \
    --max-time 10 2>/dev/null || echo "000")
  if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "202" ]; then
    echo "[add-director] SUCCESS: $AGENT_ID is live (HTTP $HTTP_STATUS)"
  else
    echo "[add-director] WARNING: Gateway returned HTTP $HTTP_STATUS for hook:${AGENT_ID}"
    echo "[add-director] If SIGHUP did not reload config, restart the container to activate $AGENT_ID"
  fi
fi

echo "[add-director] Done: $AGENT_ID ($AGENT_NAME) registered"
