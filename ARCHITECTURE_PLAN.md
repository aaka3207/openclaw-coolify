# The Organization — Architecture Plan
**Version**: 3.0 | **Date**: 2026-03-05 | **Status**: UPDATED — automation-supervisor retired, main agent owns n8n directly

> **Updated 2026-03-05**: automation-supervisor has been retired. Main agent now owns n8n capabilities directly via the n8n-manager skill. The org chart below and all references have been updated to reflect the current 3-agent model.

---

## Mission Statement

> **Make Ameer's life easier.**

This is a fully autonomous AI workforce running 24/7 on a home server. The Main Agent is the Chief of Staff — the human-facing interface. Specialist Directors own their domains completely and operate without interruption. The Automation Supervisor is the infrastructure team that makes all of it possible.

---

## 1. The Org Chart

```
Ameer
└── Main Agent (Chief of Staff + n8n Operations)
    ├── Owns: all n8n workflows, canonical data feeds, n8n error handling
    ├── Builds: microservices, automation, reusable sub-workflows
    ├── Executes: via n8n-manager skill + direct n8n API calls
    │
    ├── Budget CFO (Finance) [read-only, no exec/write]
    │   └── Consumes: monarch.transaction feed, email.received (financial filter)
    │
    ├── Business Researcher (Research & Comms) [read-only, no exec/write]
    │   └── Consumes: email.received (newsletters), calendar feed
    │
    └── [Future Directors — added via intake process]

Workflow Workers (ephemeral)
    └── Spawned on demand by Main Agent via sessions_spawn
        Model: Gemini Flash | Lifespan: single task
```

> **Note (2026-03-05):** Automation Supervisor was retired after Phase 8 completion. The separation into a dedicated "platform engineering" agent proved unnecessary — the main agent handles n8n operations directly with lower overhead and fewer failure modes. If n8n complexity grows significantly, a dedicated supervisor can be re-added via `add-director.sh`.

---

## 2. Communication Model

### Session Key Routing (no hooks.mappings required)

Each Director lives in a persistent OpenClaw session identified by a dedicated key. n8n triggers agents by POSTing to the hooks endpoint with the target session key in the payload.

| Agent | Session Key | Primary Trigger |
|-------|-------------|----------------|
| Main Agent | `main` | Direct conversation + n8n webhooks + cron (lead screening, etc.) |
| Budget CFO | `hook:budget-cfo` | OpenClaw cron (every 4-6h) + financial email events |
| Business Researcher | `hook:business-researcher` | n8n newsletter webhook + email events |
| Workflow Workers | ephemeral | `sessions_spawn` from Main Agent |

> **Note (2026-03-05):** `hook:automation-supervisor` session key is retired. n8n Global Error Handler workflow routes errors to main agent or logs them.

### Director-to-Director Communication

Directors can POST directly to each other's session keys without routing through main. Example: Budget CFO detects a pattern and needs the Business Researcher to investigate a company — it POSTs directly to `hook:business-researcher`.

### Escalation to Main

Directors POST to main agent when escalation is required. Main agent decides whether to notify Ameer or handle it internally.

---

## 3. n8n Operations (Main Agent Direct)

> **Updated 2026-03-05:** The Automation Supervisor was retired. The Main Agent now handles all n8n operations directly.

### 3a. Claude Code as the Execution Layer

The main agent can invoke Claude Code when deep diagnosis or code-level work is needed:

**Execution mode** (Claude Code via PTY on server):
- Main agent invokes `claude` CLI via PTY with a task spec
- Claude Code reads workflow JSON, edits nodes, commits to git, deploys via n8n API
- Uses Ameer's Claude Max plan — no API token cost
- Auth persists in `/data/.claude/` on server

### 3b. Self-Healing Loop (Simplified)

```
n8n workflow fails
  → Global Error Trigger fires
  → n8n logs the error (current state: error handler active, routing TBD)
  → Main agent notified if escalation threshold met
  → Main agent diagnoses and fixes via n8n-manager skill
  → Pattern recorded in memory/patterns/
```

### 3c. Capability Request Handling

When the main agent or a Director hits a capability gap:

```
Director: "I need emails from March 15-22 to reconcile this expense"
  → POST/escalate to main agent with capability request
  → Main agent checks capabilities registry
    → Exists: returns endpoint to Director
    → Missing: main agent builds n8n microservice via n8n-manager skill
```

### 3d. Memory-Driven Pattern Evolution

The main agent's memory/patterns/ tracks n8n workflow patterns over time. The built-in memorySearch backend (hybrid BM25 + vector) surfaces these patterns before each repair attempt.

---

## 4. The n8n Microservice Layer

### Canonical Data Feeds

No Director ever touches raw API credentials. All external data flows through standardized n8n microservices owned by the Automation Supervisor.

```
Gmail Inbox 1 ─┐
Gmail Inbox 2 ─┼─→ [Merge + Normalize] → [Enrich] → email.received event
Gmail Inbox 3 ─┘                                           ↓
                                              ┌────────────┴────────────┐
                                        Budget CFO              Business Researcher
                                    (financial filter)         (newsletter filter)
```

| Feed | Source | Schema Owner | Consumers |
|------|--------|--------------|-----------|
| `email.received` | Gmail (3 inboxes) | Automation Supervisor | CFO, BR, future |
| `monarch.transaction.new` | Monarch via n8n | Automation Supervisor | Budget CFO |
| `calendar.event.created` | Google Calendar | Automation Supervisor | BR, Main |
| `krisp.meeting.completed` | Krisp webhook | Automation Supervisor | BR, future |

### Microservice Design Principles

1. **Standardize first** — if two Directors need similar data, build one feed they both consume
2. **Enrich at ingestion** — normalize and enrich data before it hits any Director
3. **Event-driven** — feeds publish events; Directors subscribe, they don't poll
4. **Git-versioned** — every workflow change is committed before deployment

---

## 5. Schema Registry

Location: `Automation Supervisor workspace/memory/schemas/`

Each canonical event type has a JSON schema file:
- `memory/schemas/email.received.json`
- `memory/schemas/monarch.transaction.json`
- `memory/schemas/calendar.event.json`

The Supervisor owns and evolves these. QMD indexes them. When a Director requests a capability involving a new data type, the Supervisor checks the registry first — if the schema exists, it builds against it; if not, it defines the schema before building.

---

## 6. Memory Architecture

| Agent | Memory Type | Location | Access |
|-------|-------------|----------|--------|
| Main Agent | Personal | `MEMORY.md` | Main only — never shared |
| Main Agent | Org-wide | `COMPANY_MEMORY.md` | All Directors can search |
| Automation Supervisor | Operational | `memory/SYSTEM_HEALTH.md` | Supervisor only |
| Automation Supervisor | Schemas | `memory/schemas/` | All Directors (read) |
| Automation Supervisor | Patterns | `memory/patterns/n8n-error-recovery.md` | Supervisor only |
| Automation Supervisor | Capabilities | `memory/schemas/capabilities.md` | All Directors (read) |
| Budget CFO | Financial | `memory/patterns/` | CFO only |
| Business Researcher | Research | `memory/patterns/` | BR only |
| Workflow Workers | Ephemeral | In-memory only | Deleted after task |

### Weekly Retrospective

Main agent cron (weekly) reviews all Director memory files and updates `COMPANY_MEMORY.md` with distilled organizational learning. This is the institutional memory of the workforce — patterns, decisions, and lessons that outlast individual sessions.

---

## 7. Escalation Taxonomy

The main agent maintains an escalation policy. Directors post to main when they hit a blocker; main decides whether to handle it or notify Ameer.

**Current taxonomy** (main agent updates as new cases are encountered):

| Class | Definition | Examples | Handler |
|-------|-----------|---------|---------|
| **Class 1: Authorization** | Requires a new credential, OAuth consent, or API key that doesn't exist yet | New Gmail OAuth scope, Monarch API key rotation, new n8n credential | Notify Ameer |
| **Class 2: Infrastructure** | Requires Dockerfile change, new service, or server-level config | Install new dependency, new Docker service, port change | Notify Ameer |
| **Class 3: Design** | Requires architectural decision beyond the Supervisor's scope | Fundamental workflow redesign, new Director needed | Main agent decides, may involve Ameer |
| **Class 4: Recoverable** | Transient failure, known pattern, self-healing applicable | API timeout, rate limit, malformed payload | Automation Supervisor handles autonomously |

---

## 8. Token Efficiency via QMD

Cross-agent memory sharing must be query-driven, not file-dump-driven. As the workforce grows, passing full memory files between agents becomes expensive and slow. QMD's semantic search is the solution.

### The Rule: Never Read What You Can Query

| Instead of... | Do this |
|---------------|---------|
| Reading all of `WORKFLOWS.md` | Query: "what workflows exist for Monarch data?" |
| Reading the full schema registry | Query: "what is the schema for email.received?" |
| Dumping COMPANY_MEMORY.md into context | Query: "what has the CFO learned about spending patterns?" |
| Supervisor reading all patterns before a fix | Query: "what is the known fix for Krisp 429 errors?" |

### Cross-Agent Query Protocol

Before any cross-silo memory access:
1. Run a targeted `memory_search` query first
2. Only escalate to reading a full file if the query returns nothing useful
3. Sub-agents summarize findings concisely before reporting back — never return raw file contents

### QMD Collection Configuration

QMD must index the right directories for cross-agent queries to work. Required collections:

| Collection | Path | Readable By |
|------------|------|-------------|
| `company` | `COMPANY_MEMORY.md` | All Directors |
| `schemas` | Supervisor `memory/schemas/` | All Directors |
| `capabilities` | Supervisor `memory/schemas/capabilities.md` | All Directors |
| `supervisor-patterns` | Supervisor `memory/patterns/` | Supervisor only |
| `main-workspace` | Main workspace | Main agent |
| `[director]-workspace` | Each Director's `memory/` | That Director only |

Setting up and maintaining these collections is part of the Automation Supervisor's responsibilities. When a new Director is onboarded, the Supervisor adds its collection.

---

## 9. Supervisor Health Monitoring

The Main Agent runs a periodic heartbeat check on the Automation Supervisor. If the Supervisor is unresponsive or in a broken state, the Main Agent escalates directly to Ameer (Class 2 escalation).

The Automation Supervisor maintains `memory/SYSTEM_HEALTH.md` — a running log of what it has built, repaired, and deployed. This is the first thing the Main Agent reads during health checks.

---

## 10. Director Intake Process

No Director goes live without a structured onboarding. When a new Director is needed:

1. **Main agent drafts a brief**: domain, what data it needs, what capabilities it requires
2. **Automation Supervisor responds**: what it can provide from existing infrastructure, what needs to be built, what gaps exist
3. **Ameer reviews and approves**: confirms scope, provides any missing credentials
4. **Supervisor builds**: required n8n microservices, registers capabilities, updates schema registry
5. **Director onboarded**: workspace seeded with `ONBOARDING.md` — the transcript of the intake meeting, the full capability surface, what was explicitly excluded and why

The Director comes online knowing exactly what it has, what the Supervisor built for it, and what to ask for if it needs more.

---

## 11. Infrastructure Requirements

### Current Status (2026-03-05)

| Requirement | Status |
|-------------|--------|
| OpenClaw multi-agent (agents.list) | Done — main, budget-cfo, business-researcher |
| n8n hooks endpoint | Done |
| BWS secrets management | Done |
| memorySearch (built-in hybrid BM25+vector) | Done |
| AGENTS.md + memory/patterns/ (agent-owned) | Done — agent manages its own workspace |
| Phase 7 Tailscale (off-LAN access) | Done — https://openclaw-server.tailad0efc.ts.net/ |
| `claude` CLI installed + auth'd on server | Done — `/data/.claude/` OAuth subscription |
| budget-cfo in agents.list | Done (read-only permissions) |
| business-researcher in agents.list | Done (read-only permissions) |
| n8n Global Error Trigger workflow | Done |
| Email hub n8n workflow | Done — agent built autonomously |
| Lead screening cron (n8n → main agent) | Done — running every 30min, writing leads/today.jsonl |
| COMPANY_MEMORY.md + weekly cron | Done (COMPANY_MEMORY.md seeded at first run) |
| workflow-worker (generic) in agents.list | Not needed — sessions_spawn used directly |
| automation-supervisor in agents.list | Retired — main agent owns n8n directly |

---

## 12. What This Is Not

- **Not a replacement for Ameer's judgment** — the workforce surfaces information and executes known patterns. Novel decisions, strategic choices, and anything requiring authorization still come to Ameer.
- **Not fully autonomous from day one** — Directors will hit capability gaps and escalate frequently at first. That's normal. Over time the escalation rate should drop as the Supervisor builds out the platform.
- **Not dependent on any single component** — if n8n goes down, Directors can't act but they can still reason. If the Supervisor is broken, Directors escalate to main. The system degrades gracefully.

---

*Plan authored: 2026-02-22*
*v3.0 updated: 2026-03-05 — automation-supervisor retired, main agent owns n8n, org chart simplified, infrastructure table updated to reflect live state*
*Based on: ARCHITECTURE_PLAN.md v1.0 (agent-authored) + design review session + post-Phase-8 operational experience*
