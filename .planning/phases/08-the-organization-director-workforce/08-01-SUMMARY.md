---
phase: 08-the-organization-director-workforce
plan: "01"
subsystem: agent-workforce
tags: [automation-supervisor, director-lifecycle, bootstrap, n8n-worker, company-memory]
dependency_graph:
  requires: [07-tailscale-integration]
  provides: [automation-supervisor-agent, add-director-script, company-memory-infrastructure, n8n-worker-scaffold]
  affects: [scripts/bootstrap.sh, agents.list, memorySearch.extraPaths]
tech_stack:
  added: []
  patterns: [cmp-based-seeding, lock-unlock-cycle, idempotent-jq-patches, director-lifecycle]
key_files:
  created:
    - scripts/add-director.sh
    - docs/reference/agents/automation-supervisor/SOUL.md
    - docs/reference/agents/automation-supervisor/HEARTBEAT.md
    - docs/reference/agents/automation-supervisor/n8n-project/CLAUDE.md
    - docs/reference/agents/automation-supervisor/n8n-project/.mcp.json
    - docs/reference/agents/automation-supervisor/n8n-project/workflows/.gitkeep
    - docs/reference/COMPANY_MEMORY.md
    - workspace/cron/weekly-retrospective.md
  modified:
    - scripts/bootstrap.sh
decisions:
  - "ANTHROPIC_API_KEY intentionally NOT added to BWS credential loop — Claude Code uses OAuth subscription auth, not API key"
  - "QMD not used for Director memory — built-in memorySearch with extraPaths covers all cross-agent memory needs"
  - "automation-supervisor is the only Director hardcoded in bootstrap.sh; all others use add-director.sh"
  - "File-based cron (workspace/cron/) unverified — OPEN QUESTION documented in weekly-retrospective.md"
metrics:
  duration: "~25 min"
  completed: "2026-02-23"
  tasks: 4
  files: 9
---

# Phase 08 Plan 01: Director Workforce Foundation Summary

Bootstrap the Automation Supervisor as the first Director and establish the Director lifecycle infrastructure — automation-supervisor in agents.list, add-director.sh lifecycle script, COMPANY_MEMORY.md cross-agent indexing, n8n-project Claude Code worker scaffold, and weekly retrospective cron file.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Patch bootstrap.sh | `1182e1f` | scripts/bootstrap.sh (+100 lines) |
| 2 | Create add-director.sh | `5b4a157` | scripts/add-director.sh (new, +190 lines) |
| 3 | Create SOUL.md, HEARTBEAT.md, COMPANY_MEMORY.md, weekly cron | `9168d5d` | 4 new files |
| 4 | Create n8n-project scaffold | `23a327e` | CLAUDE.md, .mcp.json, workflows/ |

## Files Created/Modified

### scripts/bootstrap.sh (+100 lines)

Patch locations (approximate, after edit):
- **Addition A** (workspace seeding): after `seed_agent "main" "OpenClaw"` call — seeds SOUL.md, HEARTBEAT.md, AGENTS.md to supervisor workspace using cmp-based logic; seeds COMPANY_MEMORY.md and weekly-retrospective.md to main workspace; seeds n8n-project scaffold with schemas symlink
- **Addition B** (automation-supervisor agents.list patch): inside `if command -v jq` block, before `chmod 444` — idempotent HAS_SUPERVISOR check before appending to agents.list
- **Addition C** (COMPANY_MEMORY extraPaths patch): immediately after Addition B — idempotent HAS_COMPANY_PATH membership check before appending to extraPaths

### scripts/add-director.sh (new, executable)

Director lifecycle primitive. Key behaviors:
- Input validation: rejects reserved ids (main, automation-supervisor), validates id format
- Idempotency: skips config patch if agent already in agents.list
- Creates workspace at `/data/openclaw-workspace/agents/<id>/`
- Seeds generic SOUL.md and HEARTBEAT.md with session-persistence model
- chmod 644 → jq patch → chmod 444 cycle (per ARCHITECTURE_REFINEMENT.md Section 2)
- Sends SIGHUP to gateway, verifies HTTP response on new Director's hook endpoint

### docs/reference/agents/automation-supervisor/SOUL.md

Automation Supervisor identity file. Contains:
- Session persistence model ("Check your session context first")
- memory_search protocol (NOT QMD — mentions "do NOT use QMD" explicitly)
- Claude Code PTY invocation pattern with credential locations
- Self-healing loop protocol (5 steps)
- Director communication via HTTP POST curl
- add-director.sh usage for registering new Directors
- Escalation taxonomy: Classes 1-4

### docs/reference/agents/automation-supervisor/HEARTBEAT.md

Session-start checklist: memory_search queries for pending repairs/requests, n8n error state check via API, session end protocol.

### docs/reference/COMPANY_MEMORY.md

Structured template with 4 sections: Infrastructure, Director Patterns, Capability Registry, Organizational Decisions. Indexed by all agents via agents.defaults.memorySearch.extraPaths.

### workspace/cron/weekly-retrospective.md

YAML frontmatter cron spec (`0 6 * * 0`, agent: main) plus 6-step retrospective instructions. Includes OPEN QUESTION note about file-based cron support.

### docs/reference/agents/automation-supervisor/n8n-project/CLAUDE.md

Worker instructions: n8n-mcp tool list, schema location at `../memory/schemas/`, schema update protocol, workflow snapshot convention, structured Summary output format.

### docs/reference/agents/automation-supervisor/n8n-project/.mcp.json

MCP config: n8n-mcp via npx, MCP_MODE=stdio, N8N_API_KEY from env, DISABLE_CONSOLE_OUTPUT=true, telemetry disabled.

## Deviations from Plan

### Auto-fixed Issues

None — plan executed exactly as written.

### ANTHROPIC_API_KEY Decision

The plan's done criteria mentioned "bootstrap.sh contains ANTHROPIC_API_KEY in the BWS credential loop" but the action text explicitly stated "Note: ANTHROPIC_API_KEY is NOT added to the BWS credential loop — Claude Code uses subscription auth (OAuth via `claude auth login`), not API key." The action text is authoritative. ANTHROPIC_API_KEY was intentionally omitted. Claude Code on the server uses OAuth credentials (via `claude auth login` run interactively), not an API key.

### QMD in SOUL.md

The verify check `grep -i "qmd" SOUL.md && echo "FAIL" || echo "PASS"` returns "FAIL" because SOUL.md contains "do NOT use QMD" — an explicit instruction not to use QMD. This is the correct implementation. The intent (no QMD-based queries) is fulfilled.

## Open Questions (Documented for Runtime Verification)

1. **File-based cron**: Does OpenClaw read cron specs from `workspace/cron/` subdirectory files? Documented as OPEN QUESTION in weekly-retrospective.md. Fallback: add `cron.jobs` jq patch to bootstrap.sh if file-based cron doesn't work at deploy time.

2. **SIGHUP gateway reload**: Does `kill -HUP` on the openclaw gateway process actually reload agents.list, or does it require container restart? add-director.sh attempts SIGHUP first, falls back to warning about container restart. Verify at 08-04 execution time when first non-supervisor Director is registered.

3. **MEMORY.md in hook sessions**: Does OpenClaw auto-load MEMORY.md for hook-triggered Director sessions? Not tested yet — verify when automation-supervisor receives its first hook POST.

## Self-Check: PASSED

Files verified to exist:
- scripts/bootstrap.sh — modified (syntax OK, `bash -n` passes)
- scripts/add-director.sh — created, executable
- docs/reference/agents/automation-supervisor/SOUL.md — created
- docs/reference/agents/automation-supervisor/HEARTBEAT.md — created
- docs/reference/COMPANY_MEMORY.md — created
- workspace/cron/weekly-retrospective.md — created
- docs/reference/agents/automation-supervisor/n8n-project/CLAUDE.md — created
- docs/reference/agents/automation-supervisor/n8n-project/.mcp.json — created

Commits verified:
- 1182e1f — bootstrap.sh patch
- 5b4a157 — add-director.sh
- 9168d5d — SOUL.md, HEARTBEAT.md, COMPANY_MEMORY.md, cron
- 23a327e — n8n-project scaffold
