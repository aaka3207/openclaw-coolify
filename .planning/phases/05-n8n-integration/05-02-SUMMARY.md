---
phase: 05-n8n-integration
plan: 02
subsystem: infra
tags: [n8n, bash, curl, jq, rest-api, automation]

# Dependency graph
requires:
  - phase: 05-n8n-integration/05-01
    provides: "hooks endpoint enabled, N8N_API_KEY credential isolation in bootstrap.sh"
provides:
  - "n8n-manager skill with SKILL.md definition"
  - "n8n REST API wrapper (n8n-api.sh) with credential file auth"
  - "4 action scripts: list, create, execute, activate workflows"
affects: [n8n-integration, openclaw-skills]

# Tech tracking
tech-stack:
  added: []
  patterns: ["sourceable bash library for API auth", "credential-file-based API key reading", "workflow ID input validation regex"]

key-files:
  created:
    - skills/n8n-manager/SKILL.md
    - skills/n8n-manager/scripts/n8n-api.sh
    - skills/n8n-manager/scripts/list-workflows.sh
    - skills/n8n-manager/scripts/create-workflow.sh
    - skills/n8n-manager/scripts/execute-workflow.sh
    - skills/n8n-manager/scripts/activate-workflow.sh
  modified: []

key-decisions:
  - "n8n-api.sh is a sourceable library (not directly executable) -- action scripts source it"
  - "Default API URL uses LAN IP (192.168.1.100:5678), overridable via N8N_API_URL env var"
  - "API key read from /data/.openclaw/credentials/N8N_API_KEY file, matching bootstrap.sh credential isolation pattern"
  - "Workflow ID validation via regex [a-zA-Z0-9_-]+ prevents injection in curl URLs"

patterns-established:
  - "Sourceable API library pattern: base script provides auth + helper function, action scripts source it"
  - "Workflow ID validation: regex whitelist for URL path segments"

# Metrics
duration: 8min
completed: 2026-02-17
---

# Phase 5 Plan 2: n8n Manager Skill Summary

**Bash skill wrapping n8n REST API with credential-file auth for listing, creating, executing, and activating workflows**

## Performance

- **Duration:** 8 min
- **Started:** 2026-02-17T18:32:00Z
- **Completed:** 2026-02-17T18:40:00Z
- **Tasks:** 2
- **Files created:** 6

## Accomplishments
- Created n8n-manager skill with SKILL.md following existing web-utils format
- Built n8n-api.sh as a reusable API wrapper with auth from credential file
- Implemented 4 action scripts with strict error handling and input validation
- All scripts pass bash syntax checks with no hardcoded secrets

## Task Commits

Each task was committed atomically:

1. **Task 1: Create SKILL.md and n8n-api.sh base wrapper** - `a85e29d` (feat)
2. **Task 2: Create action scripts (list, create, execute, activate)** - `a8679b2` (feat)

## Files Created/Modified
- `skills/n8n-manager/SKILL.md` - Skill definition with 4 actions (list, create, execute, activate)
- `skills/n8n-manager/scripts/n8n-api.sh` - Sourceable API wrapper with auth and error handling
- `skills/n8n-manager/scripts/list-workflows.sh` - Lists workflows with jq formatting
- `skills/n8n-manager/scripts/create-workflow.sh` - Creates workflow from stdin or --file
- `skills/n8n-manager/scripts/execute-workflow.sh` - Executes workflow by validated ID
- `skills/n8n-manager/scripts/activate-workflow.sh` - Activates/deactivates with ID and boolean validation

## Decisions Made
- n8n-api.sh designed as sourceable library rather than standalone script -- action scripts `source` it to get the `n8n_api()` function
- LAN IP default (192.168.1.100:5678) per research recommendation -- avoids Coolify predefined network UUID hostname issues
- Credential file path `/data/.openclaw/credentials/N8N_API_KEY` matches bootstrap.sh isolation pattern from Phase 5 Plan 1
- Workflow ID validation uses `^[a-zA-Z0-9_-]+$` regex -- prevents path traversal/injection in curl URLs

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered

None.

## User Setup Required

None - N8N_API_KEY credential file provisioning was handled in 05-01-PLAN.md (bootstrap.sh credential isolation).

## Next Phase Readiness
- n8n-manager skill is complete and ready for agent use
- Requires N8N_API_KEY to be set in BWS and container restarted for scripts to function
- n8n instance must be accessible at 192.168.1.100:5678 (or N8N_API_URL override)

## Self-Check: PASSED

- [x] skills/n8n-manager/SKILL.md: FOUND
- [x] skills/n8n-manager/scripts/n8n-api.sh: FOUND
- [x] skills/n8n-manager/scripts/list-workflows.sh: FOUND
- [x] skills/n8n-manager/scripts/create-workflow.sh: FOUND
- [x] skills/n8n-manager/scripts/execute-workflow.sh: FOUND
- [x] skills/n8n-manager/scripts/activate-workflow.sh: FOUND
- [x] Commit a85e29d: FOUND
- [x] Commit a8679b2: FOUND
- [x] All scripts pass bash -n syntax check
- [x] No hardcoded secrets (grep verified)

---
*Phase: 05-n8n-integration*
*Completed: 2026-02-17*
