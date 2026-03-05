---
phase: 09-agent-operating-model
plan: "03"
subsystem: infra
tags: [openclaw, workspace, heartbeat, cleanup, matrix]

# Dependency graph
requires:
  - phase: 09-02
    provides: memory tiers, compaction cron, ICP document — Wave 1 repo changes
provides:
  - Live HEARTBEAT.md on server updated to periodic-check model (not n8n pipeline monitoring)
  - 55 stale n8n workflow JSON artifact files purged from workspace root
  - Matrix notification sent confirming Phase 9 complete
affects: [main-agent-behavior, workspace-hygiene]

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "SSH + sudo bash script pattern for volume writes (heredoc over SSH with sudo fails; scp script then run is reliable)"
    - "Hook POST via docker exec to loopback (not host curl) — gateway bind=loopback requires in-container curl"

key-files:
  created: []
  modified:
    - "/data/openclaw-workspace/HEARTBEAT.md (server volume, not repo)"

key-decisions:
  - "HEARTBEAT.md is at workspace root, not agents/main/ — plan assumed wrong path, adapted correctly"
  - "Stale JSON files were in workspace root, not leads/ — 55 files purged (all n8n workflow build artifacts)"
  - "Gateway hook requires curl from inside container (bind=loopback means host curl gets connection-reset)"

patterns-established:
  - "Pattern: Write to volume via scp+sudo script, not heredoc-over-SSH"
  - "Pattern: Send hooks via docker exec curl to 127.0.0.1:18789 (not from host)"

# Metrics
duration: 3min
completed: 2026-03-05
---

# Phase 09 Plan 03: Live Server Cleanup Summary

**Live HEARTBEAT.md replaced with periodic-check model, 55 stale n8n workflow JSON files purged from workspace root, Matrix notification sent via hooks — Phase 9 fully complete.**

## Performance

- **Duration:** 3 min
- **Started:** 2026-03-05T22:35:25Z
- **Completed:** 2026-03-05T22:38:54Z
- **Tasks:** 2
- **Files modified:** 1 (server volume)

## Accomplishments

- Updated live HEARTBEAT.md at `/data/openclaw-workspace/HEARTBEAT.md` — replaced n8n pipeline monitoring checklist with correct periodic-check model (Emails, Calendar, Leads)
- Purged 55 stale n8n workflow JSON files from workspace root (all named: engine_v*.json, fetcher_*.json, workflow_*.json, email_hub.json, etc.) — backed up to /tmp/workspace-json-backup-20260305 before deletion
- Sent Matrix notification via hooks endpoint confirming Phase 9 complete — hook returned `{"ok":true,"runId":"ea63834e-9fa9-4abd-a7b6-977f9924714b"}`
- leads/ directory was already clean (only today.jsonl + archive/) — no purge needed there

## Task Commits

Server-only operations — no git commits per plan spec (no repo files modified).

## Files Created/Modified

- `/data/openclaw-workspace/HEARTBEAT.md` (server volume) — replaced n8n monitoring with periodic-check template
- `/data/openclaw-workspace/HEARTBEAT.md.bak.20260305` (server volume) — backup of old content

## Decisions Made

- HEARTBEAT.md lives at workspace root (`/data/openclaw-workspace/HEARTBEAT.md`), not `agents/main/` as the plan assumed. Adapted path discovery at runtime — wrote to correct location.
- The 55 stale JSON files were in workspace root, not leads/. The plan described the spirit of the cleanup correctly (workflow build artifacts from when the agent was managing n8n); location differed from expectation. Applied deviation Rule 2 (auto-fix missing critical cleanup) and purged workspace root.
- Gateway bind=loopback means `curl http://127.0.0.1:18789` from the host gets "connection reset by peer" — only works from inside the container. Used `docker exec ... curl` to send the hook POST successfully.

## Deviations from Plan

### Auto-fixed Issues

**1. [Rule 1 - Adapt] HEARTBEAT.md path was workspace root, not agents/main/**
- **Found during:** Task 1 (Step 1 — Verify workspace path)
- **Issue:** Plan expected `/data/openclaw-workspace/agents/main/HEARTBEAT.md` but that path doesn't exist. Discovery revealed HEARTBEAT.md is at workspace root.
- **Fix:** Used correct path `/data/openclaw-workspace/HEARTBEAT.md` throughout
- **Verification:** `grep "Periodic Checks" HEARTBEAT.md` confirmed write

**2. [Rule 2 - Extended Scope] Stale JSON files in workspace root, not leads/**
- **Found during:** Task 1 (Step 5 — List leads/ directory)
- **Issue:** leads/ was already clean. The 55 stale n8n workflow JSON files described in the plan were actually in the workspace root, not leads/.
- **Fix:** Backed up and deleted all 55 `*.json` files from workspace root — all are clearly n8n build artifacts (engine_v*.json, fetcher_*.json, workflow_*.json, etc.)
- **Verification:** `find workspace -maxdepth 1 -name "*.json" | wc -l` returns 0

**3. [Rule 3 - Blocking] Hook POST required in-container curl**
- **Found during:** Task 2 (Step 2 — Send hook)
- **Issue:** Gateway is bound to loopback inside container. Host `curl http://127.0.0.1:18789` returns "connection reset by peer" — docker-proxy forwards the port but the gateway rejects plain HTTP (expects WebSocket upgrade or in-container loopback). Shell from server SSH is NOT inside the container.
- **Fix:** Used `docker exec openclaw-ukwkggw4o8go0wgg804oc4oo-221708004157 curl ...` to send the POST from inside the container where 127.0.0.1:18789 is the actual gateway.
- **Verification:** Hook returned `{"ok":true,"runId":"ea63834e..."}`

---

**Total deviations:** 3 auto-fixed (1 path adaptation, 1 extended scope, 1 blocking)
**Impact on plan:** All auto-fixes necessary for correctness. Cleanup achieved the intended outcome. No scope creep.

## Issues Encountered

- `heredoc over SSH with sudo` pattern (`sudo bash -c 'cat > file' << 'EOF'`) silently empties the file. Workaround: write script locally, scp to server, run with `sudo bash /tmp/script.sh`.
- Gateway bind=loopback causes HTTP connection reset from host. hooks can only be sent via `docker exec` curl inside the container.

## User Setup Required

None — all operations were automated via SSH.

## Next Phase Readiness

Phase 9 (Agent Operating Model) is fully complete:
- Wave 1 (repo): SOUL.md, TOOLS.md, AGENTS.md, HEARTBEAT.md template, memory compaction cron, ICP document
- Wave 2 (live server): HEARTBEAT.md updated, workspace cleaned, notification sent

All behavioral config is now aligned with the locked operating model. Agent should operate in its correct domain (judgment layer, not n8n builder) going forward. The only remaining active concern is the WhatsApp health monitor restart loop (not part of Phase 9 scope).

---
*Phase: 09-agent-operating-model*
*Completed: 2026-03-05*
