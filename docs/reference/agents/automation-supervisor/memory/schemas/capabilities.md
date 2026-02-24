# Capability Registry

This file is the Automation Supervisor's capability registry. It tracks every data endpoint and microservice available to Directors. When a Director requests a capability, check here first before building anything new.

**Location on volume**: `/data/openclaw-workspace/agents/automation-supervisor/memory/schemas/capabilities.md`
**Seeded by**: `bootstrap.sh` (cmp-based, propagates repo updates on redeploy)
**Owned by**: Automation Supervisor — update this file whenever you register a new capability.

---

## How to Use This Registry

**When a Director requests a capability:**
1. `memory_search "capabilities"` — pulls this file
2. Scan for the requested capability below
3. **Found**: Reply with the endpoint/method immediately
4. **Not found**: Build the n8n microservice → test it → add entry below → notify Director

**When you build a new capability**, add an entry in the appropriate section below.

---

## Infrastructure Capabilities (Available Now)

### Hook Endpoints — Director Communication

All Directors can be reached via POST to the hooks endpoint. These are always available.

| Recipient | Endpoint | Session Key |
|-----------|----------|-------------|
| Main Agent | `POST http://127.0.0.1:18789/hooks/agent` with `agentId: "main"` | `hook:main` |
| Automation Supervisor | `POST http://127.0.0.1:18789/hooks/agent` with `agentId: "automation-supervisor"` | `hook:automation-supervisor` |
| Budget CFO | `POST http://127.0.0.1:18789/hooks/agent` with `agentId: "budget-cfo"` | `hook:budget-cfo` |
| Business Researcher | `POST http://127.0.0.1:18789/hooks/agent` with `agentId: "business-researcher"` | `hook:business-researcher` |

Auth: `Authorization: Bearer $(cat /data/.openclaw/credentials/HOOKS_TOKEN)`

### n8n Workflow API

The Supervisor manages all n8n workflows via REST API.

| Operation | Method | URL |
|-----------|--------|-----|
| List workflows | GET | `http://192.168.1.100:5678/api/v1/workflows` |
| Get workflow | GET | `http://192.168.1.100:5678/api/v1/workflows/{id}` |
| Create workflow | POST | `http://192.168.1.100:5678/api/v1/workflows` |
| Activate workflow | POST | `http://192.168.1.100:5678/api/v1/workflows/{id}/activate` |
| Deactivate workflow | POST | `http://192.168.1.100:5678/api/v1/workflows/{id}/deactivate` |
| Trigger webhook workflow | POST | `http://192.168.1.100:5678/webhook/{path}` |

Auth: `X-N8N-API-KEY: $(cat /data/.openclaw/credentials/N8N_API_KEY)`

---

## Data Feed Capabilities (Planned — Not Yet Built)

These feeds are specified in ARCHITECTURE_PLAN.md Section 4. They need to be built by the Supervisor before Directors can use them. When built, move to "Available Now" and add the webhook trigger URL.

| Feed | Source | Consumers | Status |
|------|--------|-----------|--------|
| `email.received` | Gmail (3 inboxes, merged + normalized) | Budget CFO, Business Researcher | **NOT BUILT** |
| `monarch.transaction.new` | Monarch Money via n8n | Budget CFO | **NOT BUILT** |
| `calendar.event.created` | Google Calendar | Business Researcher, Main | **NOT BUILT** |
| `krisp.meeting.completed` | Krisp webhook | Business Researcher | **NOT BUILT** |

**To build a feed**: create the n8n workflow, test it, move the entry here to "Available Now" with the webhook trigger URL and output schema reference.

---

## Schema Files

JSON schemas for canonical event types live in this same `memory/schemas/` directory. Check here before defining a new data structure for a Director.

| File | Event Type | Status |
|------|-----------|--------|
| `email.received.json` | Normalized email event | **NOT CREATED** |
| `monarch.transaction.json` | Monarch transaction event | **NOT CREATED** |
| `calendar.event.json` | Calendar event | **NOT CREATED** |

---

*Last updated: 2026-02-23 — initial seeding. No data feed microservices built yet.*
