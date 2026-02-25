# TOOLS.md — Main Agent

Operational reference for tools and external services available to the main agent.

---

## n8n Workflow Automation

You have the **n8n-manager skill** available — use it for standard operations (list, create, activate, execute workflows). The skill handles auth and error formatting automatically.

For operations the skill doesn't cover (reading executions, partial node edits, bulk changes), use the API directly.

**API base URL**: `https://n8n.aakashe.org/api/v1`
**API key**: `cat /data/.openclaw/credentials/N8N_API_KEY`

### Common Operations (direct API)

```bash
N8N_KEY=$(cat /data/.openclaw/credentials/N8N_API_KEY)
N8N_URL="https://n8n.aakashe.org/api/v1"

# List all workflows
curl -s "$N8N_URL/workflows" -H "X-N8N-API-KEY: $N8N_KEY" | jq '[.data[] | {id, name, active}]'

# Get a specific workflow (full JSON)
curl -s "$N8N_URL/workflows/<id>" -H "X-N8N-API-KEY: $N8N_KEY" | jq .

# Get failed executions
curl -s "$N8N_URL/executions?status=error&limit=10" -H "X-N8N-API-KEY: $N8N_KEY" \
  | jq '.data[] | {id, workflowId, startedAt, error: .data.resultData.error.message}'

# Activate a workflow
curl -s -X POST "$N8N_URL/workflows/<id>/activate" -H "X-N8N-API-KEY: $N8N_KEY"

# Deactivate a workflow
curl -s -X POST "$N8N_URL/workflows/<id>/deactivate" -H "X-N8N-API-KEY: $N8N_KEY"

# Update a workflow (replace full JSON)
curl -s -X PUT "$N8N_URL/workflows/<id>" \
  -H "X-N8N-API-KEY: $N8N_KEY" \
  -H "Content-Type: application/json" \
  -d @workflow.json

# Create a new workflow
curl -s -X POST "$N8N_URL/workflows" \
  -H "X-N8N-API-KEY: $N8N_KEY" \
  -H "Content-Type: application/json" \
  -d @new-workflow.json

# Test/trigger a workflow manually
curl -s -X POST "$N8N_URL/workflows/<id>/execute" -H "X-N8N-API-KEY: $N8N_KEY"
```

### Diagnosing Failures

When a workflow fails:
1. Get recent failed executions (see above)
2. Get the full workflow JSON to inspect node configs
3. Fix the node in the JSON (edit locally with bash/jq or write a temp file)
4. PUT the updated workflow back
5. Activate and test

### Workflow JSON Structure

n8n workflows are JSON objects with:
- `name` — workflow name
- `nodes` — array of node objects (each has `id`, `name`, `type`, `parameters`, `position`)
- `connections` — wiring between nodes
- `settings` — workflow-level settings (e.g. `saveExecutionProgress`)
- `active` — boolean

To safely edit a single node parameter without touching the rest:
```bash
# Fetch, edit with jq, put back
curl -s "$N8N_URL/workflows/<id>" -H "X-N8N-API-KEY: $N8N_KEY" > /tmp/wf.json
# Edit /tmp/wf.json with jq
jq '(.nodes[] | select(.name == "HTTP Request") | .parameters.url) = "https://new-url.com"' \
  /tmp/wf.json > /tmp/wf-fixed.json
curl -s -X PUT "$N8N_URL/workflows/<id>" \
  -H "X-N8N-API-KEY: $N8N_KEY" \
  -H "Content-Type: application/json" \
  -d @/tmp/wf-fixed.json
```

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
- New credentials or API keys are needed (cannot self-provision)
- Infrastructure changes required (Dockerfile, new Docker service, port changes)
- Architectural decisions beyond your scope

For everything else — workflow repairs, new automations, capability building — handle autonomously using the n8n API directly.
