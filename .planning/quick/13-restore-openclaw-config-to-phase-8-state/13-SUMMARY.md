---
phase: quick-13
plan: "01"
subsystem: infrastructure
tags: [config-restore, bootstrap, openclaw, recovery]
dependency_graph:
  requires: [scripts/bootstrap.sh]
  provides: [scripts/restore-config.sh]
  affects: [openclaw config volume, container startup]
tech_stack:
  added: []
  patterns: [delete-and-regenerate, bootstrap idempotency]
key_files:
  created:
    - scripts/restore-config.sh
  modified: []
decisions:
  - "Delete corrupted config rather than write manually — bootstrap.sh already has the full Phase 8 template (lines 216-301) plus 50+ jq patches"
metrics:
  duration: "~1 min"
  completed: "2026-02-23T21:10:16Z"
---

# Quick Task 13: Restore openclaw Config to Phase 8 State

**One-liner:** Delete-and-regenerate recovery via bootstrap.sh for corrupted openclaw.json

## What Was Built

`scripts/restore-config.sh` — a server-side bash script that:

1. Requires root (`id -u` guard)
2. Backs up the corrupted config to `openclaw.json.corrupted.bak` (if non-empty)
3. Deletes `openclaw.json` from the Docker volume at the exact host path
4. Explains what bootstrap.sh will regenerate (all Phase 8 config elements)
5. Finds the openclaw container by name filter and restarts it
6. Tails logs for 30 seconds to confirm startup and patch application
7. Falls back to Coolify redeploy instructions if no container is running

## Why This Approach

bootstrap.sh line 211 checks `[ ! -f "$CONFIG_FILE" ] || [ ! -s "$CONFIG_FILE" ]`. When the file is missing, it:
- Generates the full Phase 8 JSON template (gateway/loopback/tailscale/hooks/cron/agents)
- Runs 50+ `jq` patches covering: memorySearch, subagents, automation-supervisor, model aliases, extraPaths, access groups, etc.

Writing the config manually would require duplicating all of that logic and keeping it in sync with future changes. Delegating to bootstrap.sh is the correct single source of truth.

## Tasks

| # | Task | Status | Commit |
|---|------|--------|--------|
| 1 | Create restore-config.sh server script | COMPLETE | c234dc0 |
| 2 | Verify config restoration on server (checkpoint) | AWAITING HUMAN | — |

## Verification Steps (for human checkpoint)

```bash
# 1. Copy script to server
scp scripts/restore-config.sh ameer@192.168.1.100:/home/ameer/

# 2. SSH to server
sshpass -p '@pack86N5891' ssh -o StrictHostKeyChecking=no -o PreferredAuthentications=password ameer@192.168.1.100

# 3. Run
sudo bash /home/ameer/restore-config.sh

# 4. Watch logs for "[config]" patch lines and "OpenClaw is ready!"

# 5. Test
curl -s http://192.168.1.100:18789/health
```

## Deviations from Plan

None — plan executed exactly as written.

## Self-Check: PASSED

- [x] `scripts/restore-config.sh` created
- [x] Syntax check passes (`bash -n`)
- [x] Contains `rm -f` of config path
- [x] Contains `docker restart` logic
- [x] Contains no `jq` command calls (bootstrap.sh handles all JSON patching)
- [x] Task 1 commit `c234dc0` exists in git log
