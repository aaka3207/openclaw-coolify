---
phase: 09-agent-operating-model
plan: "02"
subsystem: agent-config
tags: [agents-md, memory, cron, icp, lead-screening]

# Dependency graph
requires:
  - phase: 09-agent-operating-model
    provides: "09-01 encoded Operator Domain split and n8n boundary in AGENTS.md"
provides:
  - "AGENTS.md Memory Tiers and Compaction subsection with operational/transaction tier definitions"
  - "workspace/cron/memory-compaction.md weekly cron for digest production"
  - "docs/reference/agents/main/lead-screening-icp.md with scoring guide and output spec"
affects:
  - agent-operating-model
  - lead-screening-workflow
  - memory-management

# Tech tracking
tech-stack:
  added: []
  patterns:
    - "Memory tiering: operational (permanent) vs transaction (30-day rotation)"
    - "Cron file format: YAML frontmatter (schedule, agent, description) + markdown steps"
    - "ICP document pattern: summary frontmatter + criteria sections + scoring table + output format"

key-files:
  created:
    - workspace/cron/memory-compaction.md
    - docs/reference/agents/main/lead-screening-icp.md
  modified:
    - AGENTS.md

key-decisions:
  - "Memory tiering: daily logs and digests are permanent (operational tier); leads/, monitor.log, recovery.log rotate after 30 days (transaction tier)"
  - "Compaction is cron-managed (Sunday 6 AM) — agent does not trigger it manually unless compacting early inline"
  - "ICP document lives in docs/reference/ (repo-owned behavioral config) not agent workspace — seeded as reference, not operational output"
  - "Lead scoring: 1-5 scale; score >=3 written to leads/today.jsonl; score 4-5 surfaced to Ameer"

patterns-established:
  - "Operational vs transaction tier separation: permanent record files vs time-bounded pipeline output"
  - "ICP criteria in repo ensures agent has explicit qualification rules without inference on every call"

# Metrics
duration: 2min
completed: "2026-03-05"
---

# Phase 9 Plan 02: Memory Discipline and Lead Screening ICP Summary

**Memory tier separation encoded in AGENTS.md, weekly compaction cron created, and explicit ICP scoring criteria documented for lead qualification workflow**

## Performance

- **Duration:** 2 min
- **Started:** 2026-03-05T22:32:01Z
- **Completed:** 2026-03-05T22:33:13Z
- **Tasks:** 3
- **Files modified:** 3

## Accomplishments

- Added Memory Tiers and Compaction subsection to AGENTS.md distinguishing permanent operational files from 30-day transaction files
- Created workspace/cron/memory-compaction.md with Sunday 6 AM schedule, 6-step compaction instructions producing memory/digests/ weekly files
- Created docs/reference/agents/main/lead-screening-icp.md with Series A/B SaaS ICP criteria, 1-5 scoring guide, and leads/today.jsonl output spec

## Task Commits

Each task was committed atomically:

1. **Task 1: Add Memory Tiers and Compaction subsection to AGENTS.md** - `5d20b78` (feat)
2. **Task 2: Create memory-compaction.md weekly cron file** - `7199d43` (feat)
3. **Task 3: Create lead-screening-icp.md ICP document** - `1f71d2b` (feat)

## Files Created/Modified

- `AGENTS.md` - Added Memory Tiers and Compaction subsection (operational vs transaction tier definitions + weekly compaction protocol)
- `workspace/cron/memory-compaction.md` - Weekly cron: schedule 0 6 * * 0, 6-step compaction to memory/digests/, transaction tier cleanup
- `docs/reference/agents/main/lead-screening-icp.md` - ICP criteria: Seed-Series B B2B SaaS, strong/weak fit signals, disqualify rules, 1-5 scoring, leads/today.jsonl output format

## Decisions Made

- Memory tiering: daily logs and digests are permanent (operational tier); leads/, monitor.log, recovery.log rotate after 30 days (transaction tier)
- Compaction is cron-managed (Sunday 6 AM) — agent does not trigger it manually unless doing early inline compaction
- ICP document lives in docs/reference/ (repo-owned behavioral config), seeded as reference rather than operational output
- Lead scoring: 1-5 scale; score >=3 written to leads/today.jsonl; score 4-5 surfaced to Ameer

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - no external service configuration required.

## Next Phase Readiness

- 09-02 complete; 09-03 is the next plan in phase 09
- Memory compaction cron behavior is still unverified (same open question as weekly-retrospective.md — whether workspace/cron/ files auto-fire or need openclaw.json config patch)
- ICP document will need seeding to agent workspace on next deploy for agent to reference it

## Self-Check: PASSED

All created files present on disk. All task commits (5d20b78, 7199d43, 1f71d2b) confirmed in git log.

---
*Phase: 09-agent-operating-model*
*Completed: 2026-03-05*
