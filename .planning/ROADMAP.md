# Roadmap: OpenClaw Coolify

## Overview

This roadmap transforms a security-hardened OpenClaw fork into a fully operational LAN-accessible AI agent with Matrix chat interface, vault-backed secrets management, and persistent knowledge graph memory. Each phase builds on the previous, progressing from foundational deployment through communication layer, secrets hardening, and finally advanced memory capabilities.

## Phases

**Phase Numbering:**
- Integer phases (1, 2, 3, 4): Planned milestone work
- Decimal phases (2.1, 2.2): Urgent insertions (marked with INSERTED)

Decimal phases appear between their surrounding integers in numeric order.

- [ ] **Phase 1: LAN Deployment** - Get OpenClaw running healthy on Coolify with LAN-only access
- [ ] **Phase 2: Matrix Integration** - Enable chat interface through Matrix homeserver
- [ ] **Phase 3: Secrets Management** - Replace env vars with Bitwarden vault references
- [ ] **Phase 4: Memory System** - Add NOVA Memory with PostgreSQL + pgvector
- [ ] **Phase 5: n8n Integration** - Bidirectional n8n ↔ OpenClaw via webhooks and API
- [ ] **Phase 6: Agent Orchestration** - Built-in memory, sub-agent model routing, agent memory discipline
- [ ] **Phase 7: Tailscale Integration** - Secure HTTPS access via Tailscale Serve, fix Control UI, clean up temp patches

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
- [ ] 01-01: Remove unused Dockerfile dependencies to reduce build time
- [ ] 01-02: Configure LAN-only FQDN and validate network isolation

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
- [ ] 02-01-PLAN.md -- Verify Synapse health, network connectivity, and create bot user
- [ ] 02-02-PLAN.md -- Install Matrix plugin, configure openclaw.json, test E2E messaging

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
**Requirements**: MEMO-01, MEMO-02, MEMO-03, MEMO-04, MEMO-05, MEMO-06
**Success Criteria** (what must be TRUE):
  1. PostgreSQL with pgvector is available (reuse Synapse's PG or deploy standalone)
  2. NOVA Memory hooks (extract, recall, session-init) are installed and enabled
  3. OpenClaw can store and retrieve memories across sessions
  4. Memory data survives container restarts (volume persistence works)
  5. Existing QMD memory system continues to function alongside NOVA
**Plans**: 2 plans

Plans:
- [x] 04-01: Deploy PostgreSQL + pgvector and install NOVA Memory
- [ ] 04-02: Enable NOVA hooks and validate memory extraction and recall (**SUPERSEDED by Phase 6** — using built-in memorySearch instead)

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
- [ ] 05-01-PLAN.md -- Enable hooks endpoint, BWS token, and N8N_API_KEY credential isolation
- [ ] 05-02-PLAN.md -- Create n8n-manager skill with API wrapper scripts

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
- [ ] 06-01-PLAN.md -- memorySearch + subagents jq patches in bootstrap.sh, NOVA cron cleanup, deploy and verify
- [ ] 06-02-PLAN.md -- Create AGENTS.md memory protocol, seed memory/patterns/ knowledge base, verify memory_search

### Phase 7: Tailscale Integration
**Goal**: OpenClaw gateway is accessible via HTTPS from anywhere via Tailscale Serve. Control UI works in browser. Temp loopback patches are removed. n8n and other services remain LAN-only.
**Depends on**: Phase 6 (Agent Orchestration)
**Requirements**: Tailscale in-container (binary copy from official image), gateway.bind=loopback, tailscale.mode=serve, TS_AUTHKEY in Coolify env
**Success Criteria** (what must be TRUE):
  1. Control UI is accessible from MacBook browser via HTTPS (Tailscale MagicDNS URL)
  2. Sub-agents continue to work (loopback-native, no temp patch)
  3. Temp patches removed from bootstrap.sh (mode=remote, remote.url, --allow-unconfigured)
  4. n8n has NO Tailscale access -- LAN-only unchanged
  5. Gateway survives container restart without re-auth (state persisted)
  6. TS_AUTHKEY stored in Coolify env, not hardcoded
**Plans**: 2 plans

Plans:
- [ ] 07-01-PLAN.md -- Dockerfile tailscale-install stage, bootstrap.sh tailscaled startup + config patches + temp removal, docker-compose env vars, connect-mac-node.sh update
- [ ] 07-02-PLAN.md -- Deploy verification checkpoint: Tailscale setup, Control UI HTTPS, sub-agent test, restart persistence

## Progress

**Execution Order:**
Phases execute in numeric order: 1 -> 2 -> 3 -> 4 -> 5 -> 6 -> 7

| Phase | Plans Complete | Status | Completed |
|-------|----------------|--------|-----------|
| 1. LAN Deployment | 2/2 | Complete | 2026-02-15 |
| 2. Matrix Integration | 2/2 | Complete | 2026-02-15 |
| 3. Secrets Management | 1/1 | Complete | 2026-02-16 |
| 4. Memory System | 1/2 | Unblocked | - |
| 5. n8n Integration | 2/2 | Complete | 2026-02-17 |
| 6. Agent Orchestration | 0/2 | In Progress | - |
| 7. Tailscale Integration | 0/2 | Planned | - |

**Phase 6 PIVOTED:** Dropped NOVA memory approach (hooks broken, expensive, wrong use case). Now using OpenClaw built-in memorySearch (hybrid BM25 + vector) with OpenAI embeddings. NOVA PostgreSQL container stays in docker-compose but unused.

---
*Roadmap created: 2026-02-14*
*Last updated: 2026-02-22*
