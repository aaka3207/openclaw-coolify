# TOOLS.md — Main Agent

Operational reference for tools available to the main agent.

---

## Endpoint Registry

Your tools are HTTP endpoints. You call them; you don't manage what's behind them. Ameer adds entries here as tools are provisioned.

| Name | URL | What it does |
|------|-----|-------------|
| *(none yet — Ameer adds entries as tools are set up)* | | |

**How to call an endpoint:**
```bash
curl -s -X POST "https://n8n.aakashe.org/webhook/<id>" \
  -H "Content-Type: application/json" \
  -d '{"action": "read", "pageId": "..."}'
```

If you identify a need for a new tool endpoint, document the capability you need and tell Ameer.

---

## Lobster — Deterministic Pipelines

Use Lobster when Ameer asks you to run a multi-step task where some steps need his approval before proceeding (e.g., "process my inbox and pause before sending replies").

**When to reach for Lobster:**
- Multi-step task where side effects (send, post, delete) need a human gate before executing
- You want to show Ameer a preview of what you're about to do, wait for approval, then continue
- Task needs to be resumable if interrupted

**Basic pattern:**
```json
{
  "action": "run",
  "pipeline": "exec --json --shell 'step-one --json' | exec --stdin json --shell 'step-two --json' | approve --preview-from-stdin --prompt 'Apply these changes?'",
  "timeoutMs": 30000
}
```

**Resume after approval:**
```json
{
  "action": "resume",
  "token": "<resumeToken>",
  "approve": true
}
```

Full docs: `docs/tools/lobster.md`

---

## Incoming Webhook Spec

When designing an orchestration with Ameer, here's how to wire an external system to call you:

```
POST http://127.0.0.1:18789/hooks/agent
Authorization: Bearer <HOOKS_TOKEN>
Content-Type: application/json

{
  "agentId": "main",
  "sessionKey": "hook:main",
  "message": "..."
}
```

**sessionKey conventions:**
- `hook:main` — resumes your persistent main session (use for ongoing tasks)
- `hook:main:<task>` — isolated session for a specific task (doesn't mix with main context)

HOOKS_TOKEN: `cat /data/.openclaw/credentials/HOOKS_TOKEN`

---

## Memory Search

Use `memory_search` to query your memory files before starting any task:
- Before diagnosing a problem: `memory_search "known fix for [error type]"`
- Before building something new: `memory_search "existing capabilities"`
- Cross-agent context: `memory_search "company [topic]"`

---

## Director Communication

To send a message to another Director (budget-cfo, business-researcher):
```bash
HOOKS_TOKEN=$(cat /data/.openclaw/credentials/HOOKS_TOKEN 2>/dev/null || \
  grep '^OPENCLAW_HOOKS_TOKEN=' /data/.openclaw/secrets.env | cut -d= -f2-)

curl -X POST http://127.0.0.1:18789/hooks/agent \
  -H "Authorization: Bearer $HOOKS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"agentId": "budget-cfo", "sessionKey": "hook:budget-cfo", "message": "..."}'
```

Always include both `agentId` AND `sessionKey` — `agentId` routes to the correct Director.

---

## Escalation to User (Ameer)

Escalate when:
- A new tool endpoint is needed (you document the capability, Ameer provisions it)
- New credentials or API keys are needed
- Infrastructure changes required (Dockerfile, new Docker service, port changes)
- Architectural decisions beyond your scope
