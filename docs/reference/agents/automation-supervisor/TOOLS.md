# TOOLS.md — Automation Supervisor

Operational manual for the tools available to the Automation Supervisor.

---

## 1. Claude Code Worker (n8n-project)

The Claude Code worker is your implementation employee. You manage it via tmux — it runs as a persistent interactive Claude Code session with full GSD framework access and n8n-mcp tools.

**Worker location:** `/data/openclaw-workspace/agents/automation-supervisor/n8n-project/`

### Starting a worker session

```bash
# Start a named tmux session with Claude Code running in the n8n-project
tmux new-session -d -s n8n-worker -c /data/openclaw-workspace/agents/automation-supervisor/n8n-project
tmux send-keys -t n8n-worker "/data/.local/bin/claude" Enter
sleep 5  # wait for Claude Code to initialize
```

Check if a session already exists before creating:
```bash
tmux has-session -t n8n-worker 2>/dev/null && echo "exists" || echo "not running"
```

### Managing multiple sessions

Use named sessions when running parallel tasks to avoid conflicts:
```bash
# Session naming: n8n-worker-<task-id>
tmux new-session -d -s "n8n-worker-repair-$(date +%s)" -c /data/openclaw-workspace/agents/automation-supervisor/n8n-project
```

List all active worker sessions:
```bash
tmux list-sessions | grep n8n-worker
```

Kill a session when done:
```bash
tmux kill-session -t n8n-worker
```

### Sending commands to the worker

```bash
# Send a GSD quick task
tmux send-keys -t n8n-worker "/gsd:quick fix the broken Krisp webhook — timeout on HTTP Request node" Enter

# Send any slash command
tmux send-keys -t n8n-worker "/gsd:plan-phase 1" Enter
```

### Reading output

```bash
# Capture current pane content
tmux capture-pane -t n8n-worker -p

# Capture with scrollback (last 200 lines)
tmux capture-pane -t n8n-worker -p -S -200
```

### Detecting task completion

Poll until the GSD completion banner appears in the output:
```bash
while true; do
  OUTPUT=$(tmux capture-pane -t n8n-worker -p -S -50)
  if echo "$OUTPUT" | grep -q "Next Up\|PHASE.*COMPLETE\|Quick task complete"; then
    echo "Worker done"
    break
  fi
  sleep 5
done
```

GSD completion markers to watch for:
- `## ▶ Next Up` — task or phase complete
- `GSD ► PHASE * COMPLETE` — phase complete
- `Tasks: N/N complete` — all tasks done
- `## Summary` — worker's own summary block (end of response)

---

## 2. GSD Framework (in the worker)

The n8n-project has GSD installed. The worker supports all GSD commands via slash commands.

### Commands you'll use most

**Quick tasks** (small, no planning needed):
```
/gsd:quick <task description>
```
Examples:
- `/gsd:quick fix the broken Krisp webhook — HTTP node returns 401`
- `/gsd:quick add error handling to the Monarch transaction workflow`
- `/gsd:quick export all active workflows to workflows/ directory`

**Planned work** (multi-step, needs research/planning first):
```
/gsd:plan-phase <N>     # create a plan
/gsd:execute-phase <N>  # execute a planned phase
```

**Check status:**
```
/gsd:progress           # what's done, what's next
```

### GSD guarantees you get from the worker

- **Atomic commits** — every meaningful change is committed with a descriptive message
- **State tracking** — `.planning/STATE.md` in the n8n-project tracks what's been built
- **Verification** — GSD verifies work actually achieves the goal, not just that tasks ran
- **SUMMARY.md** — each plan produces a summary you can read to understand what changed

### Reading worker output after a task

```bash
# Read the latest SUMMARY.md from the n8n-project
cat /data/openclaw-workspace/agents/automation-supervisor/n8n-project/.planning/quick/*/SUMMARY.md 2>/dev/null | tail -50
```

### GSD documentation

If you need to understand a GSD command or workflow in depth, use your `web_search` tool:
- Search: `site:reddit.com "get shit done" claude code framework`
- Direct reference: https://www.reddit.com/r/ClaudeAI/comments/1q4yjo0/get_shit_done_the_1_cc_framework_for_people_tired/

Key GSD concepts to know:
- GSD operates in **phases** (numbered) and **plans** (PLAN.md per phase) — the worker tracks state in `.planning/`
- `/gsd:quick` is for self-contained tasks that don't need a formal phase. Use it for 90% of n8n fixes.
- `/gsd:plan-phase` + `/gsd:execute-phase` for larger multi-step builds (new workflow from scratch, major refactors)
- The worker will ask clarifying questions before executing — write your task instruction with enough context to avoid back-and-forth
- Always include: what workflow, what's broken/needed, what success looks like

---

## 3. n8n-mcp Tools (available to the worker)

The worker has n8n-mcp loaded via `.mcp.json`. These tools are available inside the worker's Claude Code session — you don't call them directly; the worker uses them.

For reference when writing task instructions:

| Tool | Use for |
|------|---------|
| `n8n_list_workflows` | List all workflows (filter by active/inactive) |
| `n8n_get_workflow` | Fetch full workflow JSON |
| `n8n_update_partial_workflow` | Surgical edits — update a node, add a connection, rename |
| `n8n_update_full_workflow` | Replace entire workflow |
| `n8n_create_workflow` | Create a new workflow from JSON |
| `n8n_executions` | Read failed execution logs with node-level error detail |
| `n8n_test_workflow` | Trigger a test run |
| `n8n_validate_workflow` | Validate before deploying |
| `n8n_autofix_workflow` | Auto-detect and fix common structural errors |
| `search_templates` | Search 2,700+ community workflow templates |

When writing task instructions for the worker, be explicit about what workflows to touch and what the expected outcome is. The worker will choose the right tools.

---

## 4. Direct n8n API (for you, not the worker)

For simple operations you can call n8n directly without spawning a worker session:

```bash
N8N_KEY=$(cat /data/.openclaw/credentials/N8N_API_KEY)
N8N_URL="https://n8n.aakashe.org/api/v1"

# List workflows
curl -s "$N8N_URL/workflows" -H "X-N8N-API-KEY: $N8N_KEY" | jq '[.data[] | {id, name, active}]'

# Get failed executions
curl -s "$N8N_URL/executions?status=error&limit=10" -H "X-N8N-API-KEY: $N8N_KEY" | jq '.data[] | {id, workflowId, startedAt, .data.resultData.error.message}'

# Activate a workflow
curl -s -X POST "$N8N_URL/workflows/<id>/activate" -H "X-N8N-API-KEY: $N8N_KEY"
```

Use direct API for: listing, activating/deactivating, reading recent errors.
Spawn the worker for: diagnosis, editing nodes, building new workflows.

---

## 5. Schema Registry

Schemas live in your workspace at `memory/schemas/`. They define canonical data shapes for all feeds.

**Your responsibilities:**
- Define new schemas when a new data type is introduced
- The worker reads schemas at `../memory/schemas/` when building workflows
- The worker may update schemas — check `memory/schemas/` after worker tasks for changes

**Reading a schema:**
```bash
cat /data/openclaw-workspace/agents/automation-supervisor/memory/schemas/monarch.transaction.json
```

**After a worker task, check for schema changes:**
```bash
git -C /data/openclaw-workspace/agents/automation-supervisor/n8n-project log --oneline -5
```

---

## 6. Decision: When to use the worker vs direct tools

| Situation | Approach |
|-----------|----------|
| Read a workflow or list executions | Direct n8n API call |
| Activate / deactivate a workflow | Direct n8n API call |
| Fix a known error (you know the exact node/fix) | Direct n8n API call |
| Diagnose an unknown failure | Spawn worker — `/gsd:quick diagnose...` |
| Build a new workflow from scratch | Spawn worker — `/gsd:quick build...` |
| Refactor multiple workflows | Spawn worker — plan + execute phase |
| Infrastructure change (new service, Dockerfile) | Escalate Class 2 to main |
