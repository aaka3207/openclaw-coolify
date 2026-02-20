# OpenClaw Agent & Memory Architecture Reference

**Researched:** 2026-02-18
**Sources:** Official docs (docs.openclaw.ai), live clawdbot session, NOVA Memory repo, community deep-dives
**Purpose:** Reference for Phase 6 plan — add NOVA complementarily without overriding built-in behavior

---

## 1. Workspace Architecture

### What a "workspace" is

Each OpenClaw agent has a **workspace directory** — a shared filesystem that all sessions belonging to that agent read/write from:

```
~/.openclaw/workspace/          (single-agent default = agentId "main")
  AGENTS.md                     ← agent instructions (injected in all sessions)
  SOUL.md                       ← personality (injected in main/private sessions)
  USER.md                       ← user preferences (injected in main/private sessions)
  TOOLS.md                      ← tool conventions (injected in all sessions)
  MEMORY.md                     ← curated long-term facts (main session ONLY)
  memory/
    YYYY-MM-DD.md               ← daily logs (today + yesterday, main session only)
  skills/
    <skill>/SKILL.md            ← selectively injected per turn
```

In Docker on Coolify, this maps to:
```
/data/.openclaw/workspace/
```

### Key property: workspace is shared, sessions are isolated

> "The workspace is shared, but sessions are isolated. Sub-agents can read/write memory files, but they don't have the main conversation context." — confirmed from live docs

The session store is separate:
```
~/.openclaw/agents/<agentId>/sessions/
  agent:main:main.jsonl                    ← main chat transcript
  agent:main:subagent:<uuid>.jsonl         ← sub-agent execution transcript
  hook:ingress.jsonl                       ← webhook session transcript
  cron:nova-memory-catchup.jsonl           ← cron execution transcript
```

---

## 2. Session Types

OpenClaw uses session keys to identify conversation contexts:

| Session type | Key format | Who uses it |
|---|---|---|
| Main chat | `agent:main:main` | Your direct messages |
| Sub-agent | `agent:main:subagent:<uuid>` | Spawned workers |
| Webhook inbound | `hook:<uuid>` or `hook:ingress` | n8n → OpenClaw |
| Native cron | `cron:<jobId>` | OpenClaw scheduled jobs |
| System cron | n/a (runs outside gateway) | Shell scripts via crontab |
| Group/DM | `agent:main:<channel>:dm:<peer>` | Matrix, Telegram DMs |

Each session has its own `.jsonl` transcript and conversation history. **No session sees another's history** unless explicitly passed in the spawn call.

---

## 3. Sub-Agent Architecture

### What sub-agents get

Sub-agents run in `agent:main:subagent:<uuid>` sessions. Their auto-injected context is **minimal by design**:

| File | Main session | Sub-agent session |
|---|---|---|
| `AGENTS.md` | ✓ injected | ✓ injected |
| `TOOLS.md` | ✓ injected | ✓ injected |
| `SOUL.md` | ✓ injected | ✗ not injected |
| `IDENTITY.md` | ✓ injected | ✗ not injected |
| `USER.md` | ✓ injected | ✗ not injected |
| `BOOTSTRAP.md` | ✓ injected | ✗ not injected |
| `MEMORY.md` | ✓ injected | ✗ not injected |
| Daily notes | ✓ injected | ✗ not injected |
| Parent conversation history | ✓ (its own) | ✗ not shared |
| NOVA semantic recall | ✓ (hooks fire) | ✗ hooks don't fire |

Sub-agents know how to use tools and follow agent conventions. They know nothing about you, your preferences, or your conversation history unless the parent explicitly passes that in the spawn task description.

### What sub-agents CAN do

Since the workspace is shared (same filesystem):
- Sub-agents **can** call `memory_search` tool to query the SQLite index (same markdown files)
- Sub-agents **can** read/write to `memory/YYYY-MM-DD.md` and `MEMORY.md` via file tools
- This is intentional — a sub-agent doing research CAN write notes to the daily log

### What sub-agents CANNOT do (automatically)

- They don't get NOVA's semantic recall (hooks don't fire at session start)
- They don't see the parent's conversation history
- They don't get MEMORY.md auto-injected into their system prompt

### Spawning and model routing

```json
// In openclaw.json (via bootstrap.sh jq patch)
{
  "agents": {
    "defaults": {
      "subagents": {
        "model": "anthropic/claude-haiku-4-5",   // default model for all sub-agents
        "maxSpawnDepth": 1,                        // sub-agents cannot spawn sub-sub-agents
        "maxChildrenPerAgent": 3,                  // max active sub-agents at once
        "maxConcurrent": 4,                        // concurrent across all sessions
        "archiveAfterMinutes": 60                  // auto-cleanup
      }
    }
  }
}
```

Override per-spawn: `sessions_spawn` accepts `model` and `thinking` params that override the default for that specific run.

---

## 4. Built-in Memory System (OpenClaw Native)

OpenClaw has **two built-in memory layers** that operate independently of NOVA:

### Layer 1: Markdown files (workspace)
- `MEMORY.md` — curated durable facts, agent writes explicitly
- `memory/YYYY-MM-DD.md` — append-only daily log
- Both are plain files on the shared workspace filesystem
- Any session (main or sub-agent) can read/write via file tools

### Layer 2: SQLite vector index
- Path: `~/.openclaw/memory/<agentId>.sqlite`
- Indexes all `.md` files in the workspace (MEMORY.md, daily notes, skills)
- Hybrid search: 70% vector similarity + 30% BM25 keyword
- Powers `memory_search` and `memory_get` tools
- Per-agent (not per-session) — all sessions under the same agentId share one index
- Auto-syncs when workspace files change (1.5s debounce)

### Auto-injection rules
- Main/private sessions: get MEMORY.md + today's + yesterday's daily notes in system prompt
- Sub-agent sessions: get AGENTS.md + TOOLS.md only
- Group/DM sessions: get daily notes only (MEMORY.md excluded for privacy)

### Memory flush before compaction
When a session's context approaches the limit, OpenClaw runs a silent "memory flush" turn reminding the model to write durable notes to MEMORY.md before context resets. This is per-session.

---

## 5. NOVA Memory System (PostgreSQL + pgvector)

NOVA is a **separate, additional** memory layer that sits alongside OpenClaw's built-in system. It does NOT replace or override it.

### What NOVA does
Three hook handlers installed into `~/.openclaw/hooks/`:
- `memory-extract` — extracts entities/episodes from session transcripts → PostgreSQL
- `semantic-recall` — queries PostgreSQL for relevant memories → injects into context
- `session-init` — fires on `agent:bootstrap`, injects memories into fresh sessions

### What NOVA does NOT replace
- `MEMORY.md` and daily notes still work exactly as before
- SQLite vector search (`memory_search` tool) still works
- NOVA adds episodic extraction and recall on top of these

### Hook event behavior

| Hook | Event | Fires for main session | Fires for sub-agents | Notes |
|---|---|---|---|---|
| `memory-extract` | `message:received` | ✓ yes | ✗ no | Hooks don't fire for sub-agent sessions |
| `semantic-recall` | `message:received` | ✓ yes | ✗ no | Same |
| `session-init` | `agent:bootstrap` | ✓ yes | ✗ uncertain | Unclear if bootstrap fires for sub-agents |

**Confidence:** Hook behavior for sub-agents is inferred (docs are silent = likely doesn't fire). Confirmed by community research and the DeepWiki subagent management docs which state sub-agents run in `AGENT_LANE_SUBAGENT`, a separate execution lane from the main hook event system.

### Catch-up cron and the sub-agent transcript problem

NOVA's `memory-catchup.sh` runs on system cron every 5 minutes. It reads session transcript `.jsonl` files from:
```
/data/.openclaw/agents/main/sessions/
```

**Problem:** This directory contains ALL session types — including sub-agent transcripts (`agent:main:subagent:*.jsonl`), cron sessions, and webhook sessions.

Without filtering, NOVA extracts from sub-agent execution chatter:
- "I am now searching DuckDuckGo for X" → noisy entity in PostgreSQL
- "Fetching URL Y, found 3 results" → noise
- OpenClaw internal tool execution logs → definitely noise

**Solution:** Pass a session key filter to `memory-catchup.sh` so it only processes main chat transcripts. See Section 6.

---

## 6. Recommended Architecture for This Deployment

### The two-layer memory design

```
OpenClaw built-in (SQLite + markdown)
  ├── MEMORY.md           ← agent writes curated facts explicitly
  ├── memory/YYYY-MM-DD.md ← running daily log (main session auto-writes)
  └── SQLite index         ← powers memory_search tool (any session can use)

NOVA PostgreSQL (episodic extraction)
  ├── entities table       ← people, projects, preferences extracted from conversations
  ├── episodes table       ← what happened and when
  └── relationships        ← entity graph (via nova-relationships)
```

These are **additive** — NOVA supplements built-in memory with episodic extraction. Neither overrides the other.

### Session memory access summary

```
Main chat session (Matrix DM → you)
  ✓ Gets MEMORY.md auto-injected
  ✓ Gets daily notes (today + yesterday)
  ✓ NOVA session-init fires → PostgreSQL recall injected
  ✓ NOVA memory-extract fires → entities written to PostgreSQL
  ✓ memory_search tool available

Sub-agent session (spawned worker)
  ✗ Does NOT get MEMORY.md auto-injected
  ✗ Does NOT get daily notes auto-injected
  ✗ NOVA hooks do NOT fire
  ✓ Shares workspace filesystem (can tool-call memory_search)
  ✓ Can write to memory files explicitly
  → Context comes from: spawn task description + AGENTS.md + TOOLS.md

n8n webhook session (hook:ingress)
  ✗ Does NOT get MEMORY.md
  ✓/✗ NOVA may extract (message:received may fire) — verify in 06-03
  → Reasonable to keep in NOVA extraction (represents real agent work)

Cron sessions (cron:jobId)
  ✗ Should NOT feed NOVA (maintenance noise)
  → Filter out of catch-up cron
```

### How sub-agents get memory context (the right pattern)

Since sub-agents don't get NOVA recall automatically, the parent agent (which HAS full memory context) must pass relevant context in the spawn call:

```
Parent (main session, has NOVA recall):
  "User prefers TypeScript. ProjectAlpha is their main repo.
   Research best TypeScript patterns for a data fetching layer."
                    ↓ sessions_spawn with this task description
Sub-agent (worker):
  Gets the task + curated context from parent
  Does the work, returns result
  (does NOT write to PostgreSQL, does NOT get noisy extraction)
                    ↓ announces result back to parent
Parent synthesizes result → replies to user
  NOVA extracts the user's conversation (not the sub-agent's execution log)
```

This is the "pass by value" model: parent holds shared memory state, selectively distills what's relevant, passes it to workers.

### NOVA catch-up filter (what needs implementing)

The catch-up cron should only process main chat session transcripts. Session key patterns to include/exclude:

```bash
# Include ONLY:
# agent:main:main.jsonl (and mainKey variants like agent:main:telegram:dm:...)

# Exclude:
# agent:main:subagent:*.jsonl   — sub-agent execution logs
# cron:*.jsonl                   — cron maintenance logs
# hook:*.jsonl                   — check first: n8n webhooks may be worth keeping

# Recommended filter approach:
# Pass --session-pattern or --exclude to memory-catchup.sh
# OR pre-filter file list in the cron invocation:
# Only process files NOT matching subagent|cron: patterns
```

---

## 7. What Phase 6 Plans Must Verify

Beyond NOVA activation, Phase 6 execution should confirm:

1. **NOVA hook events don't fire for sub-agents** — send a test message from main session AND spawn a sub-agent; only main session entities should appear in PostgreSQL
2. **Catch-up cron filters correctly** — after adding filter, sub-agent transcripts should not be processed
3. **Sub-agent model routing works** — logs should show haiku model for spawned agents
4. **Memory is additive** — MEMORY.md still works, daily notes still work, NOVA adds to these

---

## 8. Open Questions (as of 2026-02-18)

| Question | Status | How to resolve |
|---|---|---|
| Does `agent:bootstrap` fire for sub-agent sessions? | Unknown | Check hook logs after spawning a sub-agent |
| Does NOVA's `session-init` fire for sub-agents? | Unknown (inferred: no) | Inspect hook invocation logs |
| Does `message:received` fire for webhook sessions (`hook:ingress`)? | Unknown | Send n8n test webhook, check entity extraction |
| Does `memory-catchup.sh` accept a session filter argument? | Unknown | Read the script after NOVA is enabled |
| What exact Haiku model alias does OpenClaw 2026.2.17 use? | Likely `anthropic/claude-haiku-4-5` | Run `openclaw models list` |

---

*Last updated: 2026-02-18*
*Research sources: docs.openclaw.ai, live clawdbot session research, NOVA Memory GitHub, OpenClaw GitHub issues*
