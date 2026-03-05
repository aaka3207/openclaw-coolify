---
phase: 09-agent-operating-model
plan: 01
subsystem: agent-config
tags: [soul, tools, agents, heartbeat, n8n, operating-model]

requires: []
provides:
  - SOUL.md n8n Boundary section — judgment layer vs pipeline plumbing boundary encoded
  - SOUL.md Memory Architecture updated — file-based two-tier model, QMD/NOVA refs removed
  - TOOLS.md role boundary blockquote — Ameer builds n8n workflows, agent diagnoses/escalates
  - AGENTS.md Operator Domain section — agent vs operator ownership layers defined
  - HEARTBEAT.md template — inbox/calendar/leads checklist, HEARTBEAT_OK conditions
affects:
  - Agent behavior on next redeploy (behavioral files seeded to workspace)
  - Future planning phases referencing operating model

tech-stack:
  added: []
  patterns:
    - "n8n boundary pattern: agent is judgment layer, never builds/manages workflows"
    - "Operator domain split: agent owns memory+judgment, Ameer owns infrastructure+n8n"

key-files:
  created: []
  modified:
    - SOUL.md
    - TOOLS.md
    - AGENTS.md
    - docs/reference/templates/HEARTBEAT.md

key-decisions:
  - "Agent is n8n judgment layer only: called by n8n, never builds or manages workflows"
  - "Operator Domain explicitly defined in AGENTS.md: two-layer ownership model"
  - "HEARTBEAT.md template excludes n8n pipeline monitoring (handled by Error Handler workflow)"
  - "QMD and NOVA Memory references removed from SOUL.md — superseded by file-based model"

patterns-established:
  - "Behavioral boundary pattern: encode locked decisions in both SOUL.md and TOOLS.md for redundancy"
  - "HEARTBEAT.md template: inbox/calendar/leads only — no infra monitoring in heartbeat"

duration: 2min
completed: 2026-03-05
---

# Phase 09 Plan 01: Agent Operating Model — Behavioral Config Summary

**Encoded correct n8n boundary and operator ownership model into SOUL.md, TOOLS.md, AGENTS.md, and HEARTBEAT.md template to prevent agent drift after Phase 8.**

## Performance

- **Duration:** ~2 min
- **Started:** 2026-03-05T22:28:39Z
- **Completed:** 2026-03-05T22:30:19Z
- **Tasks:** 3
- **Files modified:** 4

## Accomplishments

- SOUL.md Memory Architecture replaced: removed stale QMD/NOVA Memory references, now reflects the file-based two-tier model (operational permanent + transaction 30-day rotation)
- SOUL.md n8n Boundary section added before ACIP block: clear statement that agent is judgment layer, n8n handles pipeline plumbing, Ameer builds workflows
- TOOLS.md n8n section opens with role boundary blockquote and escalation section updated to prohibit autonomous workflow building/repair
- AGENTS.md Operator Domain section appended: two-layer ownership model, sub-agent guidance, escalation vs act criteria
- HEARTBEAT.md template rewritten: inbox/calendar/leads checks only, no n8n pipeline monitoring, HEARTBEAT_OK conditions documented

## Task Commits

Each task was committed atomically:

1. **Task 1: Add n8n Boundary to SOUL.md and update Memory Architecture** - `df00c91` (feat)
2. **Task 2: Add role boundary to TOOLS.md and Operator Domain to AGENTS.md** - `6c51590` (feat)
3. **Task 3: Rewrite HEARTBEAT.md template** - `1a35ae3` (feat)

**Plan metadata:** (docs commit to follow)

## Files Created/Modified

- `SOUL.md` - Replaced stale Memory Architecture (QMD/NOVA refs removed); added n8n Boundary section before ACIP block
- `TOOLS.md` - Role boundary blockquote at top of n8n section; escalation section updated
- `AGENTS.md` - Operator Domain section appended after Memory Search Protocol
- `docs/reference/templates/HEARTBEAT.md` - Full rewrite: periodic check template with inbox/calendar/leads

## Decisions Made

- Agent is the n8n judgment layer only: called by n8n, returns output, never builds or manages workflows
- Operator Domain split explicitly encoded: agent owns memory and judgment, Ameer owns n8n, Dockerfile, bootstrap.sh, and infrastructure
- HEARTBEAT.md excludes n8n pipeline health monitoring — the n8n Error Handler workflow (Phase 8) handles pipeline failures automatically
- QMD and NOVA Memory sections removed from SOUL.md — both superseded by the current file-based memory model

## Deviations from Plan

None — plan executed exactly as written.

## Issues Encountered

None. HEARTBEAT.md had a malformed frontmatter character (`r---`) — corrected as part of the rewrite.

## User Setup Required

None — no external service configuration required. Behavioral files take effect on next agent session after workspace sync.

## Next Phase Readiness

- 09-02 and 09-03 plans can proceed — operating model baseline is now encoded
- Behavioral files are in the repo; they seed to the agent workspace on next deploy (bootstrap.sh uses cmp-based update)

---
*Phase: 09-agent-operating-model*
*Completed: 2026-03-05*
