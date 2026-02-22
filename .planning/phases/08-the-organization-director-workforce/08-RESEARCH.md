# Phase 8: The Organization — Director Workforce - Research

**Researched:** 2026-02-22
**Domain:** OpenClaw multi-agent sessions, Claude Code CLI headless execution, n8n Global Error Trigger, QMD multi-collection memory, agents.list depth
**Confidence:** MEDIUM-HIGH (official docs + verified community patterns + our own working codebase)

---

## Summary

Phase 8 builds the autonomous AI workforce described in ARCHITECTURE_PLAN.md. The foundation (hooks, memorySearch, sub-agent spawning, n8n integration) is complete and working. What remains is instantiating specific Director agents, wiring n8n error handling to the Automation Supervisor, installing and authenticating Claude Code on the server, and configuring QMD multi-collection memory for cross-agent search.

The good news: all major subsystems are proven. The risks are (1) Claude Code CLI authentication on a Linux server requires one-time interactive browser-based OAuth or API key setup, and (2) agents.list fields follow a "full object replacement" (not merge) pattern that can wipe inherited defaults if sub-objects are partially specified. The implementation order must respect these constraints.

**Primary recommendation:** Add Directors to agents.list in bootstrap.sh config-generation block, install Claude Code via the native installer into the persistent volume (`/data/.local/bin/`), configure n8n Global Error Trigger pointing to the hooks endpoint, and set up QMD collections in bootstrap.sh after the main config patch block.

---

## Standard Stack

### What's Already Working (Do Not Change)

| Component | Location | Status |
|-----------|----------|--------|
| Hooks endpoint | openclaw.json `.hooks.enabled=true`, `.hooks.allowRequestSessionKey=true` | WORKING |
| sessionKey routing | `hook:` prefix allowed, routes to named persistent sessions | WORKING |
| Sub-agent spawning | `gateway.mode=remote` + loopback patch (TEMP — #22582) | WORKING |
| memorySearch | gemini/gemini-embedding-001, sources=["memory"] | WORKING |
| n8n-specialist agent | agents.list entry with workspace + skills | WORKING |
| AGENTS.md + patterns | Seeded to workspace via bootstrap.sh | WORKING |
| Config lock | chmod 444 on openclaw.json after bootstrap patches | WORKING |
| useAccessGroups=false | Sub-agents get operator scope without pairing | WORKING |

### What Needs to Be Added

| Component | Purpose | Priority |
|-----------|---------|----------|
| automation-supervisor in agents.list | Persistent Director session | P1 |
| budget-cfo in agents.list | Financial Director | P1 |
| business-intelligence in agents.list | Research/Comms Director | P1 |
| workflow-worker in agents.list | Ephemeral task profile | P1 |
| Claude Code CLI on server | Automation Supervisor execution layer | P1 |
| n8n Global Error Trigger workflow | Self-healing loop entry point | P1 |
| QMD installed + collections | Cross-agent memory search | P2 |
| COMPANY_MEMORY.md + weekly cron | Org-wide institutional memory | P2 |
| Director workspace seeding | ONBOARDING.md, SOUL.md, AGENTS.md stubs | P2 |

### Already Prepared in Workspace (Agent-Created)

The following directories exist in the running container (agent created them in a prior session):

```
/data/openclaw-workspace/agents/automation-supervisor/memory/patterns/
/data/openclaw-workspace/agents/budget-cfo/memory/patterns/
/data/openclaw-workspace/agents/business-researcher/memory/patterns/
/data/openclaw-workspace/agents/n8n-specialist/  (full silo)
```

These dirs were created by the main agent but the Directors are NOT yet registered in agents.list. Bootstrap.sh does not yet seed them.

---

## Session Key Routing

**Confidence: HIGH** (official docs: docs.openclaw.ai/concepts/session, plus GHSA advisory on session key behavior)

### How sessionKey Works

A `sessionKey` is a **stable logical identifier** — not a session transcript. It maps a "conversation address" to the current active `sessionId`. The sessions store is at `~/.openclaw/agents/{agentId}/sessions/sessions.json` and **survives container restarts**.

When you POST to `/hooks/agent` with `sessionKey: "hook:automation-supervisor"`:
1. OpenClaw looks up the sessionKey in the sessions store
2. If found and not expired: resumes that conversation thread (same context window)
3. If new or expired: creates a fresh sessionId under that key, starts new context

**Session expiry policies** (configured in `agents.defaults` or per-agent):
- `session.reset.idleMinutes`: expires after N minutes of no activity
- Daily reset at 4:00 AM local time by default
- `/new` or `/reset` commands force a new sessionId

**For Directors**, the important implication: a Director's session key creates continuity — the Director "remembers" previous interactions in the current session window. But the session resets daily by default. To give a Director "persistent identity across sessions," the Director must write state to its workspace (memory files), not rely on session context.

### agentId and sessionKey Interaction

From the docs: `agentId` in a sessionKey determines which agent's context and workspace is used. The native session key format for a specific agent is `agent:<agentId>:main`. When using hook routing, the `agentId` field in the POST payload can target a specific agent in agents.list:

```json
{
  "message": "...",
  "agentId": "automation-supervisor",
  "sessionKey": "hook:automation-supervisor"
}
```

Without `agentId`, hooks route to the default agent (main). With `agentId`, they route to the named agent.

**Note on allowedSessionKeyPrefixes:** Our current config allows `hook:` prefix. This means n8n can POST with `sessionKey: "hook:automation-supervisor"` — that's already enabled. No config change needed.

### Persistent Session Across Restarts

The sessions.json file is stored on the persistent Docker volume (`/data/.openclaw/`). It survives redeploys. Sessions for Director keys will persist as long as they haven't expired by the daily reset or idle timeout.

**Practical implication:** Directors don't need "always-on" processes. They're event-driven: a hook POST wakes them, they process the event, they go idle. The next POST resumes the same session (until daily reset). This matches the ARCHITECTURE_PLAN.md design.

### Payload Schema (Verified)

```json
{
  "message": "Error in workflow 'Email Normalization': TypeError at 'HTTP Request' node...",
  "agentId": "automation-supervisor",
  "sessionKey": "hook:automation-supervisor",
  "name": "n8n-error",
  "wakeMode": "now",
  "deliver": false,
  "model": null,
  "timeoutSeconds": 300
}
```

Additional optional fields: `thinking` (level override), `channel` (delivery target if deliver=true), `to` (recipient).

---

## Claude Code PTY

**Confidence: HIGH** (official code.claude.com/docs/en/cli-reference — verified)

### Headless Invocation Pattern

The `claude -p` (or `--print`) flag runs Claude Code in non-interactive SDK mode — no PTY, no terminal UI, exits after task completion. This is the correct invocation for the Automation Supervisor's execution mode.

**Minimal headless invocation:**
```bash
claude -p "task description here" --dangerously-skip-permissions
```

**With tool restriction (recommended for focused tasks):**
```bash
claude -p "Fix n8n workflow: read /tmp/task-spec.json, call n8n API, return result" \
  --tools "Bash,Read,Write" \
  --dangerously-skip-permissions \
  --max-turns 10 \
  --output-format json
```

**With custom system prompt (replaces default):**
```bash
claude -p "task" \
  --system-prompt "You are an n8n automation engineer. Fix the specified workflow." \
  --tools "Bash,Read,Write" \
  --dangerously-skip-permissions
```

**Key flags for the Automation Supervisor:**

| Flag | Purpose | Notes |
|------|---------|-------|
| `-p` / `--print` | Non-interactive, exits after task | Required for headless use |
| `--dangerously-skip-permissions` | Skip all permission prompts | Required for unattended execution |
| `--tools "Bash,Read,Write"` | Restrict to needed tools | Prevents scope creep |
| `--max-turns N` | Limit agentic turns | Prevents infinite loops |
| `--output-format json` | Parse results programmatically | Useful for Supervisor to read output |
| `--system-prompt "..."` | Override default system prompt | Give task-specific instructions |
| `--max-budget-usd N` | Hard spend cap per invocation | Cost control |
| `--no-session-persistence` | Don't save session to disk | Keeps Claude Code stateless between invocations |

### Authentication on Linux Server

Claude Code on Linux stores credentials in `~/.claude/` directory:
- `~/.claude/.credentials.json` — OAuth tokens (access + refresh)
- `~/.claude/settings.local.json` — user preferences
- `~/.claude.json` — global config (auth state, hasCompletedOnboarding, etc.)

**On Linux, credentials stored in `~/.claude/` (NOT macOS Keychain).**

**Two authentication options for the server:**

**Option A: ANTHROPIC_API_KEY environment variable (recommended for server use)**
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
claude -p "task"
```
This bypasses OAuth entirely. No browser needed. The API key is sourced from the environment. This is the standard pattern for headless Docker/server use.

Since the server already has `ANTHROPIC_API_KEY` set via Coolify environment variables (it's used for OpenClaw's OpenRouter calls — wait, actually it uses OpenRouter), we need to verify. The server uses `OPENROUTER_API_KEY` for the agent but the Claude Code CLI needs `ANTHROPIC_API_KEY` directly.

**Option B: OAuth token file (for Claude Max plan)**
```bash
# One-time: authenticate interactively on a machine with a browser
claude  # opens browser OAuth flow, stores tokens in ~/.claude/

# Then copy ~/.claude/ to the server persistent volume
# Server: HOME=/data, so target is /data/.claude/
scp -r ~/.claude/ ameer@192.168.1.100:/data/.claude/
```
Tokens expire (access token ~8-12h, refresh token longer). The CLI auto-refreshes. Complete re-auth required when refresh token expires.

**Recommended approach: ANTHROPIC_API_KEY** — simpler, more reliable, no token expiry. The Claude Max plan includes Claude Code usage through the claude.ai OAuth flow, but for a server, API key auth via console.anthropic.com is the practical choice.

### Installation on Server

```bash
# Install to user-local path (persistent across restarts since HOME=/data)
curl -fsSL https://claude.ai/install.sh | bash
# Installs to ~/.local/bin/claude = /data/.local/bin/claude (persistent volume)
```

The server has `HOME=/data` (from Dockerfile/bootstrap.sh). The native installer targets `~/.local/bin/claude` which resolves to `/data/.local/bin/claude` — this is on the persistent Docker volume. Claude Code will survive container restarts.

**bootstrap.sh already adds `/data/.local/bin` to PATH** (line 5). No PATH change needed.

**Verification:**
```bash
/data/.local/bin/claude --version
```

### Task Spec Pattern for Automation Supervisor

The Supervisor should write a task spec to a temp file, invoke Claude Code, parse the result:

```bash
# In Automation Supervisor's tool execution:
cat > /tmp/supervisor-task-$(date +%s).json <<EOF
{
  "problem": "Workflow 'Email Normalization' fails with TypeError at 'HTTP Request' node",
  "context": "n8n workflow ID: wf_abc123, error: Cannot read property 'email' of undefined",
  "tools_available": ["n8n API at http://192.168.1.100:5678", "N8N_API_KEY in /data/.openclaw/credentials/N8N_API_KEY"],
  "expected_output": "JSON with: fixed: true/false, changes_made: [...], deploy_status: activated/failed"
}
EOF

ANTHROPIC_API_KEY="$(cat /data/.openclaw/credentials/ANTHROPIC_API_KEY)" \
  /data/.local/bin/claude -p "$(cat /tmp/supervisor-task-*.json)" \
  --tools "Bash,Read,Write" \
  --dangerously-skip-permissions \
  --max-turns 20 \
  --output-format json \
  --no-session-persistence \
  2>/tmp/supervisor-claude.log

rm /tmp/supervisor-task-*.json
```

---

## QMD Multi-Collection

**Confidence: MEDIUM** (QMD docs + quick-task-5 research + our Dockerfile has QMD installed)

### What QMD Is (from prior research, quick-task-5)

QMD (`@tobilu/qmd`) is already in the Dockerfile. It provides BM25 + vector + LLM re-ranking search over named markdown collections. The `qmd` binary goes to `/data/.bun/install/global/bin/qmd` (persistent).

**Models required (downloaded on first embed):**
- `embeddinggemma-300M-Q8_0` (~300MB)
- `qwen3-reranker-0.6b-q8_0` (~640MB)
- `qmd-query-expansion-1.7B-q4_k_m` (~1.1GB)
- Total: ~2GB cached in `/data/.cache/qmd/models/`

**ARCHITECTURE_PLAN.md specifies these collections:**

| Collection | Path | Readable By |
|------------|------|-------------|
| `company` | Main workspace `COMPANY_MEMORY.md` | All Directors |
| `schemas` | Supervisor `memory/schemas/` | All Directors (read) |
| `capabilities` | Supervisor `memory/schemas/capabilities.md` | All Directors |
| `supervisor-patterns` | Supervisor `memory/patterns/` | Supervisor only |
| `main-workspace` | Main workspace `memory/` | Main agent |
| `[director]-workspace` | Per-Director `memory/` | That Director only |

### Multi-Collection Configuration

QMD collections are configured via CLI. No openclaw.json changes needed. Setup in bootstrap.sh (run once, idempotent):

```bash
# In bootstrap.sh, after main config patches:
QMD_BIN="/data/.bun/install/global/bin/qmd"
if command -v "$QMD_BIN" &>/dev/null || command -v qmd &>/dev/null; then
  QMD="$(command -v qmd 2>/dev/null || echo $QMD_BIN)"

  # Company-wide collection (main workspace COMPANY_MEMORY.md)
  COMPANY_MEM="${OPENCLAW_WORKSPACE:-/data/openclaw-workspace}/COMPANY_MEMORY.md"
  if [ -f "$COMPANY_MEM" ]; then
    "$QMD" collection add "$COMPANY_MEM" --name company 2>/dev/null || true
  fi

  # Schemas collection (Supervisor's schema registry)
  SUP_SCHEMAS="/data/openclaw-workspace/agents/automation-supervisor/memory/schemas"
  mkdir -p "$SUP_SCHEMAS"
  "$QMD" collection add "$SUP_SCHEMAS" --name schemas 2>/dev/null || true

  # Main workspace memory
  "$QMD" collection add "${OPENCLAW_WORKSPACE:-/data/openclaw-workspace}/memory" --name main-workspace 2>/dev/null || true

  echo "[qmd] Collections configured"
fi
```

### Cross-Agent Access Pattern

OpenClaw's built-in memorySearch (`memory_search` tool) only indexes the current agent's workspace. To query cross-agent collections (e.g., Budget CFO asking "what is the schema for email.received?"), the agent must use QMD directly.

**Two access patterns:**

**Pattern A: Agent invokes QMD CLI via bash skill**
```bash
# Agent runs: qmd query "what is the schema for email.received?"
qmd query "email.received schema" --collection schemas
```

**Pattern B: QMD as MCP server (add to openclaw.json)**
```json
{
  "mcp": {
    "servers": {
      "qmd": {
        "command": "qmd",
        "args": ["mcp"]
      }
    }
  }
}
```
This gives ALL agents access to `qmd_search`, `qmd_query`, `qmd_vector_search` tools via MCP. The `mcp` key in openclaw.json is a global MCP config — it applies to all agents unless overridden.

**Recommendation:** Start with MCP server pattern (simpler agent experience). Add the `mcp.servers.qmd` block via bootstrap.sh jq patch. This makes QMD tools available to all agents without per-agent bash skill invocations.

### Re-indexing Behavior

QMD does not auto-watch like OpenClaw's built-in memorySearch. Must run `qmd update` or `qmd embed` periodically. Add to bootstrap.sh or a cron job:

```bash
# In bootstrap.sh (after collections configured):
nohup qmd update --all-collections > /dev/null 2>&1 &
echo "[qmd] Background index update started"
```

### WARNING: HDD Performance

First `qmd embed` run downloads 2GB of GGUF models AND processes all markdown. On the HDD server this will take **20-40 minutes** and should not block gateway startup. Always run QMD operations with `nohup ... &`.

---

## agents.list Config Depth

**Confidence: HIGH** (deepwiki.com/openclaw/openclaw/4.3-agent-configuration — verified)

### Full Per-Agent Schema

All `agents.defaults` fields can be overridden per-agent. **Objects replace entirely** — setting `agents.list[i].model` replaces the ENTIRE model config, not just the primary field. Always include all needed sub-fields.

**Safe per-Director agent entry:**

```json
{
  "id": "automation-supervisor",
  "name": "Automation Supervisor",
  "workspace": "/data/openclaw-workspace/agents/automation-supervisor",
  "default": false,
  "model": {
    "primary": "openrouter/anthropic/claude-sonnet-4-6",
    "fallbacks": ["openrouter/google/gemini-3-flash-preview", "openrouter/auto"]
  },
  "tools": {
    "profile": "coding",
    "allow": ["Bash", "Read", "Write", "n8n-manager"],
    "deny": []
  },
  "heartbeat": {
    "every": "1h",
    "model": "openrouter/anthropic/claude-haiku-4-5"
  }
}
```

**Workflow-worker entry (ephemeral profile):**

```json
{
  "id": "workflow-worker",
  "name": "Workflow Worker",
  "workspace": "/data/openclaw-workspace/agents/workflow-worker",
  "default": false,
  "model": {
    "primary": "openrouter/google/gemini-3-flash-preview",
    "fallbacks": ["openrouter/anthropic/claude-haiku-4-5"]
  },
  "tools": {
    "profile": "minimal"
  }
}
```

### Valid Field Reference (Confirmed)

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | Required. alphanumeric + hyphens. Used in agentId routing. |
| `name` | string | Display name |
| `default` | boolean | Exactly one agent must be true |
| `workspace` | string | Absolute path to agent workspace dir |
| `model.primary` | string | Model ID in `provider/model` format |
| `model.fallbacks` | array | Ordered fallback model list |
| `tools.profile` | string | "minimal", "coding", "messaging", "full" |
| `tools.allow` | array | Additional tools to allow |
| `tools.deny` | array | Tools to block (takes precedence over allow) |
| `sandbox.mode` | string | "off", "non-main", "all" |
| `memorySearch.enabled` | boolean | Per-agent memory search toggle |
| `memorySearch.extraPaths` | array | Additional dirs to index |
| `memorySearch.sources` | array | ["memory"], ["sessions"], or both |
| `heartbeat.every` | string | Heartbeat interval e.g. "1h" |
| `heartbeat.model` | string | Model for heartbeat turns |
| `thinkingDefault` | string | Default reasoning level |
| `contextTokens` | number | Context window limit |
| `skipBootstrap` | boolean | Skip BOOTSTRAP.md execution |
| `compaction` | object | Memory compaction strategy |

### Skills Field

Skills are auto-discovered from `<workspace>/skills/` — there is NO `skills` array in agents.list. Per-agent skills live in `<workspace>/skills/`. The n8n-specialist has its own skills directory (confirmed working). Other Directors get their skills by having skill directories in their workspace.

The `skills.entries[name].enabled = false` global disable (in openclaw.json) applies across all agents.

### MCP Per-Agent

The `mcp.servers` in openclaw.json is global (all agents). Per-agent MCP override is not documented as a valid field in agents.list. To give a specific agent different MCP access, use the global config plus `tools.deny` to block specific MCP tools for other agents.

### Object Replacement Warning

This is the critical pitfall: specifying `model` in agents.list REPLACES the entire model object from defaults, including fallbacks. Always specify all fields you need:

```json
// WRONG — wipes fallbacks:
{ "id": "budget-cfo", "model": { "primary": "openrouter/..." } }

// CORRECT — includes fallbacks:
{ "id": "budget-cfo", "model": { "primary": "openrouter/...", "fallbacks": [...] } }
```

### How to Add Agents via bootstrap.sh

The agents.list is in the config file that bootstrap.sh patches. The config is locked (chmod 444) at the end of bootstrap. The correct pattern is to patch agents.list in the bootstrap.sh jq block, before the lock:

```bash
# In bootstrap.sh, before "chmod 444" line:
# Check if automation-supervisor agent already exists in list
HAS_SUP=$(jq -r '.agents.list[] | select(.id == "automation-supervisor") | .id' "$CONFIG_FILE" 2>/dev/null)
if [ -z "$HAS_SUP" ]; then
  jq '.agents.list += [{
    "id": "automation-supervisor",
    "name": "Automation Supervisor",
    "workspace": "/data/openclaw-workspace/agents/automation-supervisor",
    "default": false,
    "model": {"primary": "openrouter/anthropic/claude-sonnet-4-6", "fallbacks": ["openrouter/google/gemini-3-flash-preview", "openrouter/auto"]},
    "tools": {"profile": "coding"}
  }]' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  echo "[config] Added automation-supervisor agent"
fi
```

Repeat for each Director. This is idempotent — only adds if the id is not already in the list.

---

## n8n Integration Points

**Confidence: MEDIUM** (official n8n docs confirmed Error Trigger exists; payload schema from community + blog verified; global error workflow config confirmed)

### Error Trigger Payload Schema

When a workflow fails, n8n fires the linked error workflow (or global error workflow) with an Error Trigger node. Confirmed payload fields (MEDIUM confidence — from community verification):

```json
{
  "workflow": {
    "id": "wf_abc123",
    "name": "Email Normalization",
    "url": "https://n8n.aakashe.org/workflow/wf_abc123"
  },
  "execution": {
    "id": "exec_xyz789",
    "url": "https://n8n.aakashe.org/execution/exec_xyz789",
    "error": {
      "message": "Cannot read property 'email' of undefined",
      "stack": "TypeError: Cannot read...",
      "name": "TypeError"
    },
    "lastNodeExecuted": "HTTP Request",
    "retryOf": null
  }
}
```

**Important:** `execution.id` and `execution.url` require that "Save successful executions" is enabled in n8n workflow settings. If not enabled, these fields may be absent.

**Workflow JSON is NOT included** in the error payload — only metadata. The Automation Supervisor needs to call the n8n API to fetch the workflow JSON: `GET /api/v1/workflows/{id}`.

### Global Error Workflow Configuration

In n8n, a Global Error Workflow fires for ALL workflows that don't have their own error workflow set. Configure it at:

**n8n UI**: Settings (left sidebar) → Workflow Settings → Error Workflow → select your error handler workflow

**The error handler workflow structure:**
```
[Error Trigger] → [HTTP Request to OpenClaw hooks] → [optional: send notification]
```

**The HTTP Request node payload to OpenClaw:**
```json
{
  "method": "POST",
  "url": "http://192.168.1.100:18789/hooks/agent",
  "headers": {
    "Authorization": "Bearer {{OPENCLAW_HOOKS_TOKEN}}",
    "Content-Type": "application/json"
  },
  "body": {
    "agentId": "automation-supervisor",
    "sessionKey": "hook:automation-supervisor",
    "message": "=Workflow '{{ $json.workflow.name }}' (ID: {{ $json.workflow.id }}) failed at node '{{ $json.execution.lastNodeExecuted }}'. Error: {{ $json.execution.error.message }}. Execution URL: {{ $json.execution.url }}",
    "name": "n8n-error-trigger",
    "wakeMode": "now",
    "deliver": false
  }
}
```

### Infinite Loop Prevention

n8n does NOT trigger the error workflow for the error workflow itself. This is built-in protection. If the error handler workflow fails, n8n logs the failure but does NOT recurse.

However, there is a risk: if the Automation Supervisor fixes a workflow and re-activates it, and it immediately fails again, the error trigger fires again. The Supervisor must track repair attempts and escalate to main after N failures.

### Workflow-to-Workflow (w2w) Calls

n8n supports w2w via "Execute Sub-workflow" node. These calls are synchronous or async:
- **Sync**: caller waits for sub-workflow result
- **Async**: caller continues immediately

For the canonical data feeds pattern (email.received broadcast to multiple Directors), the preferred pattern is: **one workflow normalizes the data → calls Director webhook via HTTP Request node** (not w2w Execute). This avoids w2w concurrency limits and is more fault-tolerant.

n8n community reports: deadlocks occur when w2w cycles form (A calls B calls A). Prevent by designing feeds as one-directional: Source → Normalize → Director (each a separate workflow, never calling back).

---

## Safety Constraints

**Confidence: HIGH** (our own codebase — these are facts, not hypotheses)

### MUST NOT CHANGE (Breaking Risk)

| Config/Setting | Why Critical | Breaking Impact |
|----------------|-------------|-----------------|
| `gateway.mode = "remote"` | Sub-agent spawning TEMP patch (#22582) | Sub-agents fail with ECONNREFUSED |
| `gateway.remote.url = "ws://127.0.0.1:PORT"` | Loopback bypass for isSecureWebSocketUrl | Sub-agents fail |
| `gateway.remote.token = OPENCLAW_GATEWAY_TOKEN` | Sub-agent auth when mode=remote | Sub-agents get 401 |
| `commands.useAccessGroups = false` | Sub-agents get operator scope | Sub-agents restricted, session spawning fails |
| `hooks.allowRequestSessionKey = true` | Enables Director routing via sessionKey | All hook routing breaks |
| `hooks.allowedSessionKeyPrefixes = ["hook:"]` | Restricts session key scope | Hook routing fails or security hole |
| `chmod 444 openclaw.json` (config lock) | Prevents agent corruption of config | Must be last step in bootstrap.sh |
| `agents.list[].default = true` on main | Exactly one default required | Gateway startup validation fails |

### Safe to Add (Low Risk)

| Change | Risk Level | Notes |
|--------|-----------|-------|
| Add new agent to agents.list | LOW | Use jq `+= [...]` pattern, idempotent check |
| Add MCP server to mcp.servers | LOW | New servers don't affect existing ones |
| Seed new Director workspace dirs | NONE | mkdir -p is always safe |
| Add QMD collections | NONE | QMD runs independently |
| Add n8n Global Error Trigger | NONE | External to OpenClaw |
| Install Claude Code CLI | NONE | Goes to /data/.local/bin/ |

### bootstrap.sh Ordering Rules

The current bootstrap.sh has a strict ordering that must be preserved:

1. `chmod 644 "$CONFIG_FILE"` (unlock)
2. Config patches (cron, hooks, memorySearch, etc.)
3. Director agent additions (NEW — insert here)
4. QMD setup (NEW — can go here)
5. `chmod 444 "$CONFIG_FILE"` (lock)
6. System services (cron, matrix, sandbox, etc.)
7. `exec openclaw gateway run --allow-unconfigured`

**New patches MUST go between step 2 and step 5.**

### Workspace Isolation

Each Director MUST have its own workspace directory. The workspace is the agent's entire context boundary — SOUL.md, AGENTS.md, memory/, skills/ all live there. Director workspaces must not overlap.

```
/data/openclaw-workspace/                    # Main agent workspace
/data/openclaw-workspace/agents/automation-supervisor/  # Supervisor workspace
/data/openclaw-workspace/agents/budget-cfo/             # CFO workspace
/data/openclaw-workspace/agents/business-intelligence/  # BI workspace
/data/openclaw-workspace/agents/workflow-worker/        # Worker (minimal) workspace
```

Note: The ARCHITECTURE_PLAN.md specifies "business-researcher" but MEMORY.md shows the workspace as "business-researcher". The Coolify agent memory says "Business Intelligence Director" with session key `hook:business-intelligence`. Use `business-intelligence` as the agent id to match the hook key.

### Config Schema Safety

openclaw.json STRICTLY validates. The following will CRASH the gateway:
- Unknown top-level keys (e.g., `experimental`, `commands.gateway`, `commands.restart`)
- `gateway.bind = "custom"` or `gateway.bind = "auto"`
- `imageModel` as a string (must be `{"primary": "..."}` object)
- `agents.list[]` entries without required `id` field
- Two entries with `default: true`

Safe pattern for adding agents to agents.list: always check for existing entry before appending. Never add duplicate IDs.

---

## Implementation Order

**Confidence: HIGH** — based on dependency analysis of the working system

### Order Rationale

The "don't break" constraint dominates. The sub-agent spawning TEMP patch is fragile — any change to `gateway.mode`, `gateway.remote`, or `commands.useAccessGroups` will break it.

### Recommended Build Order

**Step 1: Director agent entries in agents.list (bootstrap.sh patch)**
- Prerequisites: None (pure config addition)
- Risk: LOW (idempotent jq append)
- What: Add automation-supervisor, budget-cfo, business-intelligence, workflow-worker
- Verify: Gateway starts, `agents_list` tool shows all 4 new agents

**Step 2: Seed Director workspaces in bootstrap.sh**
- Prerequisites: Step 1
- Risk: NONE (mkdir + cp, idempotent)
- What: Create workspace dirs, seed SOUL.md stubs, copy AGENTS.md, create memory/patterns/
- Verify: Workspace dirs exist in container

**Step 3: Install Claude Code CLI on server (one-time)**
- Prerequisites: Server access, ANTHROPIC_API_KEY from console.anthropic.com
- Risk: LOW (external tool, not in OpenClaw path)
- What: SSH to server, run `curl -fsSL https://claude.ai/install.sh | bash` inside container
- OR: Add to Dockerfile for persistent install
- Verify: `/data/.local/bin/claude --version`

**Step 4: Wire ANTHROPIC_API_KEY for Claude Code**
- Prerequisites: Step 3
- Risk: LOW (adds new credential file, doesn't touch gateway config)
- What: Add ANTHROPIC_API_KEY to BWS secrets, bootstrap.sh writes to credential file
- Verify: `cat /data/.openclaw/credentials/ANTHROPIC_API_KEY` inside container

**Step 5: n8n Global Error Trigger workflow**
- Prerequisites: Working hooks endpoint (already done)
- Risk: NONE for OpenClaw (external n8n change)
- What: Create error handler workflow in n8n, set as Global Error Workflow in n8n Settings
- Verify: Manually fail a test workflow, check if hook:automation-supervisor session gets a message

**Step 6: Automation Supervisor SOUL.md and AGENTS.md**
- Prerequisites: Step 2 (workspace exists)
- Risk: NONE (files in workspace, not config)
- What: Write Supervisor-specific identity, capabilities, and n8n PTY instructions
- Verify: Send test message to hook:automation-supervisor, check response

**Step 7: QMD multi-collection setup**
- Prerequisites: QMD binary available (needs a full redeploy if not yet deployed)
- Risk: LOW (independent of gateway)
- What: Configure collections in bootstrap.sh, add mcp.servers.qmd to openclaw.json
- Verify: `qmd list` shows collections; agent can use qmd_search tool

**Step 8: COMPANY_MEMORY.md + weekly cron**
- Prerequisites: Main workspace seeded
- Risk: LOW
- What: Create COMPANY_MEMORY.md template, add openclaw native cron job
- Verify: Cron fires (check logs), COMPANY_MEMORY.md updated

---

## Common Pitfalls

### Pitfall 1: agents.list Object Replacement Wipes Defaults
**What goes wrong:** Add `"model": {"primary": "..."}` to an agent entry, heartbeat model reverts to default (Sonnet), costs spike.
**Why it happens:** Objects in agents.list REPLACE corresponding defaults entirely. No deep merge.
**How to avoid:** Always include all sub-fields when overriding an object: `"model": {"primary": "...", "fallbacks": [...]}`.
**Warning signs:** Agent ignores defaults you expect it to inherit; unexpected model costs.

### Pitfall 2: Missing agentId in Hook POST
**What goes wrong:** POST to `hook:automation-supervisor` but message goes to main agent.
**Why it happens:** sessionKey routes the conversation thread, but without `agentId`, the gateway uses the default agent's context (main agent).
**How to avoid:** Always include both `agentId` and `sessionKey` in hook POSTs to Directors.

```json
// WRONG — routes to main agent context despite correct sessionKey:
{"message": "...", "sessionKey": "hook:automation-supervisor"}

// CORRECT:
{"message": "...", "agentId": "automation-supervisor", "sessionKey": "hook:automation-supervisor"}
```

### Pitfall 3: Claude Code Auth Expiry on Server
**What goes wrong:** Automation Supervisor's Claude Code invocations start failing with auth errors weeks later.
**Why it happens:** OAuth refresh tokens expire. With API key auth this doesn't happen.
**How to avoid:** Use `ANTHROPIC_API_KEY` env var authentication, not OAuth. Store key in BWS + credential file.

### Pitfall 4: QMD Model Download Blocks Gateway
**What goes wrong:** First `qmd embed` downloads 2GB of models, bootstrap.sh hangs for 40 minutes.
**Why it happens:** QMD auto-downloads GGUF models on first use if not cached.
**How to avoid:** Run `qmd embed` with `nohup ... &` in bootstrap.sh. Let gateway start; QMD indexes in background.

### Pitfall 5: n8n Error Trigger Missing execution.id
**What goes wrong:** Automation Supervisor's hook message has empty execution URL — can't call n8n API to get workflow details.
**Why it happens:** `execution.id` and `execution.url` are only populated if n8n is configured to save executions.
**How to avoid:** In n8n workflow settings, set "Save successful executions" and "Save failed executions" to enabled. Or: include `workflow.id` in the hook message (always present) and use the n8n API to fetch workflow details.

### Pitfall 6: Director workspace NOT in agents.list
**What goes wrong:** Agent directories exist on disk but the agent is not registered — hooks to `hook:automation-supervisor` with `agentId: "automation-supervisor"` return 404.
**Why it happens:** workspace directories were created by the main agent in prior sessions, but `agents.list` was never updated.
**How to avoid:** Workspace directory existence ≠ agent registration. Both are needed.

### Pitfall 7: Daily Session Reset Breaks Director Continuity
**What goes wrong:** Director loses conversation context every day at 4 AM — loses track of ongoing repairs.
**Why it happens:** Default daily reset creates a new sessionId for every sessionKey.
**How to avoid:** Director MUST write all important state to memory files before session ends. Design Directors to be stateless between sessions — state lives in `memory/patterns/`, not in session context.

### Pitfall 8: Claude Code Auto-Update Breaking the Version
**What goes wrong:** Claude Code auto-updates itself on server, breaks compatibility with task specs.
**Why it happens:** Native installer auto-updates by default.
**How to avoid:** Set `DISABLE_AUTOUPDATER=1` in the container environment, or pin the version at install time.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead | Why |
|---------|-------------|-------------|-----|
| Agent-to-agent messaging | Custom TCP/IPC channel | OpenClaw hooks endpoint with agentId routing | Already exists, auth'd, handles session routing |
| Workflow error detection | Custom n8n polling script | n8n Global Error Trigger + Error Trigger node | Built-in, fires automatically, rich error payload |
| Claude Code in container | Custom API client to call Anthropic API | `claude -p` CLI with ANTHROPIC_API_KEY | Max plan, no token cost; full tool ecosystem |
| Cross-agent memory search | Read all memory files from other agents | QMD with named collections | Purpose-built, BM25+vector+reranking, avoids file dumps |
| Persistent Director identity | Agent tries to remember across sessions | Write to workspace memory files | Only files survive session reset |
| Sub-workflow fan-out | Execute Sub-workflow node in n8n | HTTP Request node to each Director's hook | Avoids w2w deadlock risk, more fault-tolerant |
| Tool restrictions per agent | Complex middleware | `tools.profile` + `tools.allow`/`tools.deny` in agents.list | Built-in, config-only |

**Key insight:** The entire Director communication model is solved by the existing hooks endpoint with `allowRequestSessionKey: true` and `agentId` targeting. No new infrastructure needed for agent-to-agent messaging.

---

## Sources

### Primary (HIGH confidence)

- `docs.openclaw.ai/concepts/session` — sessionKey vs sessionId, persistence across restarts, session expiry policies (verified via WebFetch)
- `code.claude.com/docs/en/cli-reference` — All claude CLI flags including -p, --print, --tools, --dangerously-skip-permissions, --output-format (verified via WebFetch)
- `code.claude.com/docs/en/authentication` — Credential storage in ~/.claude/, ANTHROPIC_API_KEY auth (verified via WebFetch)
- `code.claude.com/docs/en/setup` — Linux installation, ~/.local/bin/ path, uninstall cleanup (verified via WebFetch)
- `deepwiki.com/openclaw/openclaw/4.3-agent-configuration` — Full agents.list schema, object replacement behavior, valid fields (verified via WebFetch)
- `docs.openclaw.ai/concepts/session-tool` — sessions_spawn parameters, agentId/model override, worker spawning (verified via WebFetch)
- Our own `scripts/bootstrap.sh` — exact patch patterns, config lock, PATH setup, agent workspace paths (codebase truth)
- Our own `ARCHITECTURE_PLAN.md` — Director spec, hook keys, memory architecture, implementation requirements
- Our own `MEMORY.md` — known working state, temp patches, gateway token

### Secondary (MEDIUM confidence)

- `deepwiki.com/openclaw/openclaw/9.6-subagent-management` — sessions_spawn context/announce parameters (verified via WebFetch)
- WebSearch n8n error trigger payload — confirmed fields: `workflow.id`, `workflow.name`, `execution.id`, `execution.url`, `execution.error.message`, `execution.lastNodeExecuted` (multiple community sources corroborating)
- `blog.n8n.io/creating-error-workflows-in-n8n/` — Global Error Workflow setup via Settings → Workflow Settings (verified via WebFetch)
- `deepwiki.com/openclaw/openclaw/4.3-multi-agent-configuration` — agent field overrides, defaults inheritance (verified via WebFetch)
- `.planning/quick/5-research-how-to-make-openclaw-qmd-memory/5-RESEARCH.md` — QMD installation path, model sizes, collection CLI commands (prior research)

### Tertiary (LOW confidence — verify if acting on)

- WebSearch findings on Claude Code Docker container patterns — ANTHROPIC_API_KEY env var auth (multiple sources, consistent)
- Community finding on n8n w2w deadlock behavior (pattern confirmed by community posts, not official docs)
- `claude-did-this.com/claude-hub/getting-started/setup-container-guide` — ~/.claude/.credentials.json file structure (third-party guide, consistent with official auth docs)

---

## Metadata

**Confidence breakdown:**
- Session key routing: HIGH — official docs confirm persistence + payload schema
- Claude Code PTY: HIGH — official CLI reference confirmed all flags
- agents.list depth: HIGH — deepwiki (code-derived) confirmed full schema
- n8n error trigger: MEDIUM — payload fields confirmed via community, official docs not fully accessible
- QMD multi-collection: MEDIUM — prior research + docs consistent, no new deployment test
- Safety constraints: HIGH — derived from our own working codebase

**Research date:** 2026-02-22
**Valid until:** 2026-03-22 (30 days — CHANGELOG #22582 may ship before then, requiring TEMP patch removal)

---

## Open Questions

1. **Does n8n Global Error Workflow fire for ALL workflows or only opted-in ones?**
   - What we know: "Global Error Workflow" in n8n Settings applies to workflows that do NOT have their own error workflow set
   - What's unclear: Whether newly created workflows automatically opt into the global one
   - Recommendation: Set the global error workflow, AND verify by testing with a deliberately broken workflow

2. **ANTHROPIC_API_KEY for Claude Code — separate from OpenRouter key?**
   - What we know: OpenClaw uses `OPENROUTER_API_KEY` for its LLM calls (via OpenRouter). Claude Code needs `ANTHROPIC_API_KEY` directly (not OpenRouter).
   - What's unclear: Whether the user has a separate Anthropic API Console account for Claude Code
   - Recommendation: Add `ANTHROPIC_API_KEY` as a new BWS secret. May need to create one at console.anthropic.com if not already present. The ARCHITECTURE_PLAN.md says "uses Ameer's Claude Max plan" — but Max plan auth requires OAuth browser flow, not API key. Clarify with user.

3. **QMD binary availability after latest redeploy**
   - What we know: QMD was added to Dockerfile in a prior quick task. Confirmed in docker-compose.yaml. The last deploy was recent.
   - What's unclear: Whether the current running container has QMD installed (depends on whether it was a full rebuild or cached)
   - Recommendation: Check `which qmd` or `/data/.bun/install/global/bin/qmd --version` in running container before assuming it's available.

4. **business-researcher vs business-intelligence agent id**
   - What we know: Workspace exists at `agents/business-researcher/` (created by agent). ARCHITECTURE_PLAN.md specifies session key `hook:business-intelligence` and agent name "Business Intelligence". MEMORY.md says "business-intelligence".
   - What's unclear: The canonical agent id — is it `business-researcher` or `business-intelligence`?
   - Recommendation: Use `business-intelligence` (matches hook key and ARCHITECTURE_PLAN.md session routing table). Create workspace at `/data/openclaw-workspace/agents/business-intelligence/` — the `business-researcher` dir can be left or cleaned up.
