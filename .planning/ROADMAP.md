# Roadmap: OpenClaw Coolify

## Overview

This roadmap transformed a security-hardened OpenClaw fork into a fully operational LAN-accessible AI agent with Matrix chat interface, vault-backed secrets management, and persistent knowledge graph memory. All phases are complete as of 2026-02-23. The project is now in steady-state operations — the Director workforce runs autonomously and future work is on-demand via quick tasks.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3, 4): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [x] **Phase 1: LAN Deployment** - Get OpenClaw running healthy on Coolify with LAN-only access
- [x] **Phase 2: Matrix Integration** - Enable chat interface through Matrix homeserver
- [x] **Phase 3: Secrets Management** - Replace env vars with Bitwarden vault references
- [x] **Phase 4: Memory System** - Add NOVA Memory with PostgreSQL + pgvector (superseded by built-in memorySearch in Phase 6)
- [x] **Phase 5: n8n Integration** - Bidirectional n8n ↔ OpenClaw via webhooks and API
- [x] **Phase 6: Agent Orchestration** - Built-in memory, sub-agent model routing, agent memory discipline
- [x] **Phase 7: Tailscale Integration** - Secure HTTPS access via Tailscale Serve, fix Control UI, clean up temp patches
- [x] **Phase 8: The Organization** - Autonomous Director workforce with self-healing n8n loop and cross-agent memory

## Phase Details

### Phase 1: LAN Deployment
**Goal**: OpenClaw container builds, deploys, and runs healthy on Coolify with LAN-only web access
**Depends on**: Nothing (first phase)
**Requirements**: DEPL-01, DEPL-02, DEPL-03, DEPL-04, DEPL-05, DEPL-06, DEPL-07
**Success Criteria** (what must be TRUE):
  1. Container builds successfully on Coolify within 3600s timeout
  2. Gateway is accessible from LAN (192.168.100.0/24) at configured FQDN
  3. Gateway is NOT accessible from public internet
  4. Health check passes and container stays in healthy state
  5. All security hardening from audit is preserved in deployed configuration
**Plans**: 2 plans

Plans:
- [x] 01-01: Remove unused Dockerfile dependencies to reduce build time
- [x] 01-02: Configure LAN-only FQDN and validate network isolation

### Phase 2: Matrix Integration
**Goal**: Users can interact with OpenClaw through Matrix direct messages
**Depends on**: Phase 1
**Requirements**: MTRX-01, MTRX-02, MTRX-03, MTRX-04, MTRX-05, MTRX-06
**Success Criteria** (what must be TRUE):
  1. Matrix Synapse service is running in healthy state on Coolify
  2. OpenClaw bot user exists on Matrix homeserver with valid credentials
  3. User can send a message to OpenClaw via Matrix DM and receive AI-generated response
  4. Only authorized users/rooms can interact with the bot (access control works)
**Plans**: 2 plans

Plans:
- [x] 02-01-PLAN.md -- Verify Synapse health, network connectivity, and create bot user
- [x] 02-02-PLAN.md -- Install Matrix plugin, configure openclaw.json, test E2E messaging

### Phase 3: Secrets Management
**Goal**: API keys are fetched from Bitwarden vault at startup instead of hardcoded env vars
**Depends on**: Phase 2
**Requirements**: SECR-01, SECR-02, SECR-03, SECR-04, SECR-05, SECR-06
**Success Criteria** (what must be TRUE):
  1. BWS CLI is available in OpenClaw container and can authenticate to Vaultwarden
  2. OPENAI_API_KEY and ANTHROPIC_API_KEY are stored in Bitwarden vault (not Coolify env)
  3. Container boots successfully, fetches secrets from vault, and unsets them from environment
  4. Only BWS_ACCESS_TOKEN remains visible as a direct Coolify environment variable
**Plans**: 1 plan (completed as quick task)

Plans:
- [x] Quick task: BWS secrets auto-injection in bootstrap.sh (commit 2459ee4)

### Phase 4: Memory System
**Goal**: OpenClaw has persistent long-term memory via NOVA Memory (PostgreSQL + pgvector)
**Depends on**: Phase 3
**Status**: SUPERSEDED — Phase 6 adopted built-in memorySearch instead of NOVA
**Plans**: 2 plans (04-01 done; 04-02 superseded)

Plans:
- [x] 04-01: Deploy PostgreSQL + pgvector and install NOVA Memory
- [x] 04-02: SUPERSEDED by Phase 6 — using built-in memorySearch instead of NOVA hooks

### Phase 5: n8n Integration
**Goal**: OpenClaw can create/manage n8n workflows and receive webhooks from n8n for event-driven automation
**Depends on**: Phase 3 (BWS for credentials)
**Requirements**: N8N-01, N8N-02, N8N-03, N8N-04
**Success Criteria** (what must be TRUE):
  1. OpenClaw hooks endpoint is enabled and accessible from n8n container
  2. n8n can POST webhooks to OpenClaw that trigger agent actions
  3. OpenClaw agent can create, activate, and execute n8n workflows via API
  4. n8n API key is stored in BWS (not hardcoded)
  5. Example flow works: Notion change -> n8n webhook -> OpenClaw processes it
**Plans**: 2 plans

Plans:
- [x] 05-01-PLAN.md -- Enable hooks endpoint, BWS token, and N8N_API_KEY credential isolation
- [x] 05-02-PLAN.md -- Create n8n-manager skill with API wrapper scripts

### Phase 6: Agent Orchestration
**Goal**: OpenClaw uses built-in hybrid memory (BM25 + vector via memorySearch) to remember patterns and preferences across sessions. Sub-agents use Haiku for token efficiency. NOVA catch-up cron is cleaned up. Agent has clear instructions for memory discipline.
**Depends on**: Phase 5 (completed)
**Requirements**: Built-in memorySearch config, sub-agent model routing, agent instructions
**Success Criteria** (what must be TRUE):
  1. memorySearch is enabled in openclaw.json with OpenAI embeddings (text-embedding-3-small)
  2. Sub-agents default to anthropic/claude-haiku-4-5
  3. NOVA catch-up cron is removed from container crontab
  4. AGENTS.md exists in workspace with memory read/write protocol
  5. memory/patterns/ knowledge base has seed content for indexing
**Plans**: 2 plans

Plans:
- [x] 06-01-PLAN.md -- memorySearch + subagents jq patches in bootstrap.sh, NOVA cron cleanup, deploy and verify
- [x] 06-02-PLAN.md -- Create AGENTS.md memory protocol, seed memory/patterns/ knowledge base, verify memory_search

### Phase 7: Tailscale Integration
**Goal**: OpenClaw gateway is accessible via HTTPS from anywhere via Tailscale Serve. Control UI works in browser. Temp loopback patches are removed. n8n and other services remain LAN-only.
**Depends on**: Phase 6 (Agent Orchestration)
**Requirements**: Tailscale in-container (binary copy from official image), gateway.bind=loopback, tailscale.mode=serve, TS_AUTHKEY in Coolify env
**Plans**: 2 plans

Plans:
- [x] 07-01-PLAN.md -- Dockerfile tailscale-install stage, bootstrap.sh tailscaled startup + config patches + temp removal, docker-compose env vars, connect-mac-node.sh update
- [x] 07-02-PLAN.md -- Deploy verification checkpoint: Tailscale setup, Control UI HTTPS, sub-agent test, restart persistence

### Phase 8: The Organization — Director Workforce
**Goal**: Autonomous AI workforce with 2 persistent analyst Directors (Budget CFO, Business Researcher) + ephemeral Workflow Workers via sessions_spawn, self-healing n8n error loop, Claude Code execution layer, built-in memorySearch with COMPANY_MEMORY.md extraPaths, and institutional memory via weekly retrospective cron.
**Depends on**: Phase 6 (Agent Orchestration)
**Plans**: 5 plans (all complete)

Wave structure:
- Wave 1: 08-01 (foundation)
- Wave 2: 08-02, 08-03 (parallel — Claude Code install + n8n error workflow)
- Wave 3: 08-04 (Director onboarding)
- Wave 4: 08-05 (end-to-end verification)

Plans:
- [x] 08-01-PLAN.md — Bootstrap automation-supervisor + add-director.sh + COMPANY_MEMORY.md extraPaths + weekly cron + ANTHROPIC_API_KEY credential write
- [x] 08-02-PLAN.md — Install Claude Code CLI on server + configure headless auth
- [x] 08-03-PLAN.md — Create n8n Global Error Trigger workflow routing to Automation Supervisor
- [x] 08-04-PLAN.md — Onboard Budget CFO and Business Researcher via add-director.sh
- [x] 08-05-PLAN.md — End-to-end verification: 3-agent count, self-healing loop, Claude Code, Director-to-Director comm

## Post-Phase 8 Simplifications (2026-03)

After Phase 8 completed, several architectural simplifications were made based on operational experience:

### automation-supervisor Retired (commit 7406d8a)
The Automation Supervisor Director was removed from agents.list. Its n8n capabilities have been absorbed directly by the main agent via the n8n-manager skill and TOOLS.md documentation. The separation of "reasoning" and "execution" into two agents proved unnecessary overhead — the main agent handles n8n operations directly. The n8n Global Error Handler workflow remains active but routes to main agent.

### Workspace File Seeding Removed (commit 3fb579c)
All workspace file seeding was removed from bootstrap.sh. The main agent's workspace files (SOUL.md, HEARTBEAT.md, TOOLS.md, AGENTS.md, memory/patterns/) are now owned and maintained entirely by the agent itself. bootstrap.sh no longer writes to the workspace on every deploy. This eliminates the "bootstrap overwrites agent changes" problem.

### Security Restrictions Applied (commit ee32594)
- `gateway` tool denied globally for all agents (prevents agents from modifying gateway config)
- `budget-cfo` and `business-researcher` restricted: deny exec, write, edit, apply_patch (analyst Directors are read-only, communicate-only)

### Infrastructure Cleanup
- `container_name: openclaw` added to docker-compose.yaml for stable container naming
- bootstrap.sh simplified by ~85 lines
- OpenClaw upgraded to 2026.3.2 (commit 903d625)

### Current Active Agents (as of 2026-03-05)
- `main` — Chief of Staff, owns n8n directly via n8n-manager skill
- `budget-cfo` — Finance analyst (read-only permissions)
- `business-researcher` — Research & Comms analyst (read-only permissions)

The main agent is running a live lead screening workflow — scanning newsletters every 30 minutes and writing qualified leads to `leads/today.jsonl`. It created its own agent spec at `agents/LeadScreeningAgent.md` and built the n8n email hub workflow autonomously.

## What's Next

The project is in steady-state operations. No more phased buildout. Future work is on-demand via quick tasks when the agent hits a capability gap or Ameer identifies a new need.

The Director Intake Process (from ARCHITECTURE_PLAN.md Section 10) is the mechanism for adding new Directors when needed — the main agent drives the onboarding without repo changes.

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7 -> 8

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. LAN Deployment | 2/2 | Complete | 2026-02-15 |
| 2. Matrix Integration | 2/2 | Complete | 2026-02-15 |
| 3. Secrets Management | 1/1 | Complete | 2026-02-16 |
| 4. Memory System | 2/2 | Complete (superseded by Phase 6) | 2026-02-16 |
| 5. n8n Integration | 2/2 | Complete | 2026-02-17 |
| 6. Agent Orchestration | 2/2 | Complete | 2026-02-22 |
| 7. Tailscale Integration | 2/2 | Complete | 2026-02-22 |
| 8. The Organization | 5/5 | Complete | 2026-02-23 |

**Post-Phase 8 simplifications applied:** automation-supervisor retired, workspace seeding removed, security restrictions tightened, bootstrap.sh simplified.

---
*Roadmap created: 2026-02-14*
*Last updated: 2026-03-05 — All phases complete, post-Phase 8 simplifications documented*
