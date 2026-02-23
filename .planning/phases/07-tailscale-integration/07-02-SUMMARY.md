---
phase: 07-tailscale-integration
plan: 02
subsystem: infrastructure
tags: [tailscale, deployment, verification, control-ui, https]
dependency_graph:
  requires:
    - phase: 07-01
      provides: [tailscale-binaries-in-image, tailscaled-startup-in-bootstrap, gateway-bind-loopback, tailscale-mode-serve]
  provides: []
  affects: []
tech-stack:
  added: []
  patterns: []
key-files:
  created: []
  modified: []
key-decisions: []
patterns-established: []
duration: pending
completed: pending
---

# Phase 7 Plan 02: Tailscale Deploy + Verify Summary

**STATUS: PAUSED AT CHECKPOINT — awaiting user Tailscale setup + deploy + post-deploy verification**

## Performance

- **Duration:** pending
- **Started:** 2026-02-23T00:39:36Z
- **Completed:** pending (at checkpoint)
- **Tasks:** 0/2 complete (both are human-verify checkpoints)
- **Files modified:** 0

## Plan Structure

This plan is entirely human-verification-driven. Both tasks are `checkpoint:human-verify`:

1. **Task 1** (checkpoint): User Tailscale account setup + deploy trigger
2. **Task 2** (checkpoint): Post-deploy verification of Tailscale + Control UI + sub-agents + restart persistence

No automatable work precedes either checkpoint — the plan is a structured deployment and verification guide.

## Accomplishments

None yet — plan paused at first checkpoint awaiting user action.

## Task Commits

None — no automatable tasks in this plan.

## Deviations from Plan

None.

## Issues Encountered

None.

## User Setup Required

Full user action needed:

**Task 1 — Pre-deploy Tailscale setup:**
1. Create Tailscale account at https://login.tailscale.com
2. Create ACL tag `tag:server` in Tailscale Admin -> Access Controls
3. Create OAuth client (scope: auth_keys write, tag: tag:server), get `tskey-client-...` secret
4. Add `TS_AUTHKEY=tskey-client-...` to Coolify env vars for openclaw service
5. Add `TS_HOSTNAME=openclaw-server` to Coolify env vars (optional)
6. Enable MagicDNS in Tailscale Admin -> DNS
7. Install Tailscale on MacBook: `brew install --cask tailscale`, login with same account
8. Push commit to trigger Coolify deploy (or use empty commit: `git commit --allow-empty`)
9. Signal: type "deployed"

**Task 2 — Post-deploy verification (8 steps):**
See 07-02-PLAN.md Task 2 for full verification script.

## Next Phase Readiness

Blocked on user completing Tasks 1 and 2. Once verified:
- Phase 7 complete — Tailscale integration done
- Project at 100% planned phases complete

---
*Phase: 07-tailscale-integration*
*Status: PAUSED at checkpoint*
