# Architecture Refinement Notes
**Date**: 2026-02-22 | **Status**: SUPERSEDES Phase 8 plans where noted
**Companion to**: ARCHITECTURE_PLAN.md v2.0

---

## Overview

This document captures architectural decisions made after ARCHITECTURE_PLAN.md v2.0 was written and the Phase 8 plans were created. It reflects what we learned from the OpenClaw docs on agent workspace, context, multi-agent, sessions, hooks, and memory — and the design decisions that followed.

Plans 08-01 through 08-05 need to be rewritten against these findings before execution.

---

## 1. The Repo Is Core Infrastructure Only

**Decision**: bootstrap.sh and this git repo do NOT manage Director lifecycle. The main agent (Chief of Staff) creates and manages Directors.

**Old model**: 4 Director agents hardcoded in bootstrap.sh jq patches. Adding a Director = edit bash + git push + redeploy.

**New model**:
- bootstrap.sh seeds exactly two things: core gateway config + Automation Supervisor workspace (special case — it's infrastructure and must exist before the org can run)
- All other Directors are created by the main agent on first run, following the Director Intake Process
- `add-director.sh` is a script the main agent calls to register a new Director in agents.list and restart the gateway — no redeploy required

**Why this matters for evolvability**: Directors can be created, evolved, and retired by the main agent without touching the repo. The repo stays stable; the org grows dynamically.

---

## 2. Director Registration Mechanism (add-director.sh)

**Constraint**: `openclaw.json` is locked `chmod 444` after bootstrap — this is a single file, selective field locking is not possible.

**Decision**: Option 2 — `add-director.sh` script the main agent can invoke via Bash:

```bash
# Pattern:
chmod 644 /data/.openclaw/openclaw.json
jq '.agents.list += [<new_agent_spec>]' ... | write back
chmod 444 /data/.openclaw/openclaw.json
# Trigger gateway reload (SIGHUP or restart)
```

The script:
- Validates input (refuses to touch gateway/auth/hooks fields)
- Is idempotent (skips if agent id already exists)
- Creates the workspace directory and seeds SOUL.md
- Relocks the config after patching
- Lives at `/app/scripts/add-director.sh` (image path, not agent-writable)

**workflow-worker is NOT registered in agents.list** — see Section 5.

---

## 3. Memory System: Built-in memorySearch, Not QMD

**Current config** (confirmed from openclaw.json):
```json
"memorySearch": {
  "enabled": true,
  "provider": "gemini",
  "model": "gemini-embedding-001",
  "sources": ["memory"],
  "sync": { "onSessionStart": true, "onSearch": true, "watch": true },
  "query": { "hybrid": { "enabled": true, ... } }
}
```

**These are different systems**:
- `memorySearch` = built-in SQLite vector search (what we have)
- `QMD` = optional external sidecar with BM25 + vectors + reranking (`memory.backend: "qmd"`)

**Decision**: Stay on built-in memorySearch. QMD's advantage (reranking) matters at scale. The cost (one sidecar process per agent on an HDD server) is not worth it now.

**Switching to QMD later is clean**: memory files are plain Markdown — agnostic to backend. Switching = config change + one-time re-index on first boot. Do it when search quality becomes a bottleneck.

**Per-agent isolation**: memorySearch is automatically per-agent. Each Director's `memory/` is indexed separately. No manual collection setup needed.

---

## 4. Cross-Agent Shared Memory (COMPANY_MEMORY.md)

**Discovery**: memorySearch supports `extraPaths` for indexing files outside the workspace:

```json5
agents: {
  defaults: {
    memorySearch: {
      extraPaths: ["/data/openclaw-workspace/COMPANY_MEMORY.md"]
    }
  }
}
```

**Decision**: A single jq patch to `agents.defaults.memorySearch.extraPaths` in bootstrap.sh makes COMPANY_MEMORY.md searchable by ALL agents (including every Director added later). This is one line, not per-agent configuration.

**The `add-director.sh` script does not need to handle this** — `agents.defaults` applies to all agents automatically.

**Old plan (throw out)**: Manual `qmd collection add` CLI commands per Director. This was wrong — QMD is not our backend, and extraPaths handles the use case cleanly.

---

## 5. Sessions Are Persistent — This Changes the Director Model

**From docs**: Sessions are persistent by default. Hook POSTs with an explicit `sessionKey` **resume the existing session**, not create a new one.

> "Webhook POSTs with an explicit sessionKey resume existing sessions. Sessions are reused until they expire." — Default expiry: 4AM daily reset.

**What this means**:

When n8n fires an error webhook to `hook:automation-supervisor`, the Automation Supervisor's running session is **resumed**. The Supervisor has a live conversation with all prior events in context. It can see that "this is the 3rd Krisp timeout today." It is not amnesia-reset for each event.

**Session store persists** at `~/.openclaw/agents/{agentId}/sessions/sessions.json`.

**The dual model (confirmed)**:
- **Session** = live context window (conversation history, tool results, in-progress state). Resumes across hook calls throughout the day. Resets at 4AM.
- **Memory files** = cross-session persistence (patterns, health log, schemas). Survive 4AM reset. Bridge between sessions.

**SOUL.md should NOT say "you wake fresh each session."** It should say: check your session context first — you likely have prior work in progress. Read memory when starting a genuinely new task or after a reset.

---

## 6. Workflow Workers Are sessions_spawn, Not agents.list

**Discovery**: `sessions_spawn` is a built-in tool for spawning ephemeral background workers. Workers announce results back to the requester's channel when done.

```
sessions_spawn(task, model, runTimeoutSeconds, cleanup)
```

**Decision**: `workflow-worker` does NOT get an entry in agents.list. Any Director can spawn a Workflow Worker on demand:
```
sessions_spawn(
  task="...",
  model="openrouter/google/gemini-flash-preview",
  cleanup="delete"
)
```

This is already built-in to OpenClaw. Registering a persistent `workflow-worker` agent would be redundant and wrong.

**Remove workflow-worker from Phase 8 plans entirely.**

---

## 7. Director-to-Director Communication — No Special Config Needed

**Discovery**: `tools.agentToAgent` is for OpenClaw's internal inter-agent messaging tools (e.g., `agent_send`). Our communication model uses HTTP POST via Bash (`curl /hooks/agent`) — this is just an HTTP call, not internal routing.

**Decision**: No `tools.agentToAgent` config needed. Directors communicate by:
```bash
curl -X POST http://127.0.0.1:18789/hooks/agent \
  -H "Authorization: Bearer $HOOKS_TOKEN" \
  -d '{"agentId": "budget-cfo", "sessionKey": "hook:budget-cfo", "message": "..."}'
```

This works today with the current hooks setup. No new config required.

---

## 8. Session Routing — Who Decides New vs Resume

**Problem**: There are cases where an incoming message should resume a Director's existing session, and cases where it should start a fresh one. Who decides?

**Three decision points**:

| Who | Mechanism | When |
|-----|-----------|------|
| **Sender** | Choice of sessionKey | Fixed key = resume; namespaced key = new task session |
| **Director itself** | Calls `/new` or `/reset` | After completing a major task, before next clean context |
| **Main agent** | Sends `/new` to Director first | Explicit delegation to a Director in a bad/full/stale state |

**SessionKey patterns**:
- `hook:automation-supervisor` — the Supervisor's event stream. n8n error webhooks always go here. Supervisor accumulates context on failures, sees patterns.
- `hook:automation-supervisor:task-<id>` — when main agent delegates a specific isolated build task. Fresh context, no contamination from error stream.

**Director SOUL.md protocol**:
```
After completing a major task:
1. Write outcome to memory/patterns/ or memory/SYSTEM_HEALTH.md
2. Call /new to reset your session
3. Confirm completion to main agent

This ensures the next incoming event gets clean context.
```

**n8n automated events always use the fixed sessionKey** — n8n doesn't know session state and shouldn't need to. Directors manage their own resets.

---

## 9. Workspace Files Are Always Loaded at Session Start

**From docs**: These files are auto-injected into every session start (20K char limit each):

> AGENTS.md, SOUL.md, TOOLS.md, IDENTITY.md, USER.md, HEARTBEAT.md, BOOTSTRAP.md

**Implications**:

- **SOUL.md** is the Director's persistent identity and instructions — always in context, not just a reference file
- **AGENTS.md** (org-wide protocol) is always in context for every Director — no need to re-read it
- **HEARTBEAT.md** is the right place for session-start checklists ("on wake: read SYSTEM_HEALTH.md, check patterns/") — keep SOUL.md focused on identity and protocols
- **MEMORY.md** loads only in private sessions (not group/shared contexts) — verify hook-triggered Director sessions count as private

**SOUL.md seeding should use cmp-based versioning** (like main SOUL.md in bootstrap.sh) — not just "seed if missing." This ensures SOUL.md template updates in the repo propagate to the container on redeploy.

---

## 10. Automation Supervisor Is Special

The Automation Supervisor is the only Director seeded by bootstrap.sh. Reasons:
- It's infrastructure — must exist before the org can run
- It owns the `add-director.sh` mechanism (all other Director creation flows through it)
- It needs a richer SOUL.md than the generic Director template (Claude Code PTY, escalation rules, session protocol)

**Supervisor-specific SOUL.md must include**:
1. **Session/memory protocol** — check session context first; write to memory after major tasks; call /new after completing a task
2. **Claude Code PTY execution** — `/data/.claude/bin/claude -p "..."  --dangerously-skip-permissions --tools "Bash,Read,Write,Edit" --max-turns 20 --output-format json`
3. **Credential file path** — `/data/.openclaw/credentials/N8N_API_KEY`
4. **Escalation taxonomy** — Class 1-4 (from ARCHITECTURE_PLAN.md)
5. **Session key patterns** — event stream vs task sessions
6. **add-director.sh usage** — how to onboard new Directors

**Supervisor HEARTBEAT.md** (session-start checklist):
```
## On Session Start
- [ ] Read memory/SYSTEM_HEALTH.md (last 20 lines)
- [ ] Run: memory_search "pending repairs"
- [ ] Run: memory_search "pending capability requests"
```

---

## 11. What Changes in Phase 8 Plans

| Plan | Status | What changes |
|------|--------|-------------|
| 08-01 | REWRITE | Remove budget-cfo, business-researcher, workflow-worker from bootstrap.sh. Only Automation Supervisor seeded. Add extraPaths patch for COMPANY_MEMORY.md. Add add-director.sh script. |
| 08-02 | UNCHANGED | Claude Code install + copy ~/.claude/ from Mac |
| 08-03 | MINOR UPDATE | Checkpoint gate already added. Verify sessionKey pattern in HTTP payload. |
| 08-04 | REWRITE | Remove all qmd collection add commands. Add COMPANY_MEMORY.md extraPaths patch (one jq patch). Weekly cron unchanged. |
| 08-05 | UPDATE | Remove workflow-worker from verification checklist. Add: test add-director.sh creates a new Director live. |

**New addition**: The main agent (or Automation Supervisor) creates Budget CFO and Business Researcher on first run via `add-director.sh`, following the Director Intake Process. This is not in any current plan — it's the first real test of the system working as designed.

---

## 12. Open Questions (Verify Before Execution)

1. **MEMORY.md in hook sessions**: Do webhook-triggered Director sessions count as "private" (MEMORY.md loads) or "shared/group" (MEMORY.md suppressed)?
2. **Gateway reload mechanism**: Does patching agents.list + `chmod 444` require a full restart, or does the gateway hot-reload on SIGHUP?
3. **add-director.sh as a skill vs raw script**: Should this be packaged as an OpenClaw skill for discoverability, or a raw `/app/scripts/` script?
4. **HEARTBEAT.md vs BOOT.md**: Are these different things? BOOT.md is listed as "first run only" — need to understand if HEARTBEAT.md runs every session or also first-run-only.

---

*Refinement documented: 2026-02-22*
*Ready for: Phase 8 plan rewrite*
