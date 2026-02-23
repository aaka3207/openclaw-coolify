# Phase 8: The Organization — Director Workforce - Context

**Gathered:** 2026-02-22
**Status:** Ready for planning

**Source documents:**
- `ARCHITECTURE_PLAN.md` v2.0 — original architecture vision
- `ARCHITECTURE_REFINEMENT.md` — supersedes ARCHITECTURE_PLAN.md where explicitly noted

**Reconciliation note:** ARCHITECTURE_REFINEMENT.md was written after ARCHITECTURE_PLAN.md to capture evolved decisions. Where both documents exist, ARCHITECTURE_REFINEMENT.md wins. ARCHITECTURE_PLAN.md is authoritative for everything not touched by the refinement (escalation taxonomy, Director domains, intake process, self-healing loop structure, weekly retrospective goal).

<domain>
## Phase Boundary

Build an autonomous AI workforce within the existing OpenClaw deployment. Three persistent Director agents (Automation Supervisor, Budget CFO, Business Researcher) receive work via OpenClaw hook sessionKeys. An add-director.sh script handles Director lifecycle (create/configure/activate). Claude Code CLI serves as the Automation Supervisor's execution layer for infrastructure tasks. The n8n Global Error Trigger creates the self-healing repair loop. Ephemeral Workflow Workers are spawned via sessions_spawn, not registered in agents.list.

**Explicitly NOT in scope for Phase 8:**
- Canonical data feeds (email.received, monarch.transaction, calendar, Notion) — built on-demand by Directors after they're running
- n8n-specialist Claude Code project — exists as separate tooling, not part of this phase's deployment
- Tailscale integration — Phase 7 (separate phase, not a dependency)
- NOVA PostgreSQL memory — already deployed, already disabled from NOVA cron (Phase 4). Not touched here.

</domain>

<decisions>
## Implementation Decisions

### Memory Architecture: memorySearch, NOT QMD

**Decision:** Use OpenClaw built-in memorySearch for all Director memory operations. QMD is NOT used for cross-agent memory.

- `ARCHITECTURE_PLAN.md` Sections 3d and 8 referenced QMD for cross-agent search — **SUPERSEDED**
- `ARCHITECTURE_REFINEMENT.md` Section 3: "Stay on built-in memorySearch. QMD's advantage matters at scale. Cost is not worth it now."
- All references to "QMD search" or "qmd_query" in architecture docs map to `memory_search` tool call in implementation
- COMPANY_MEMORY.md is indexed via `agents.defaults.memorySearch.extraPaths` — a single jq patch makes it searchable by ALL agents
- Per-Director private memory lives in their workspace `memory/` directory — auto-indexed by memorySearch via workspace path
- No QMD collection setup, no QMD MCP server config, no QMD binary calls in bootstrap.sh for Phase 8

### Director Lifecycle: Automation Supervisor is Hardcoded, Rest via add-director.sh

**Decision:** Only Automation Supervisor is seeded in bootstrap.sh. All other Directors use add-director.sh for creation.

- `ARCHITECTURE_REFINEMENT.md` Section 1: "Repo = core infrastructure only. Main agent manages Director lifecycle."
- add-director.sh mechanism (from refinement Section 2):
  1. `chmod 644 openclaw.json` (unlock config)
  2. `jq` patch: append to `agents.list`, create workspace directory, seed SOUL.md and HEARTBEAT.md
  3. `chmod 444 openclaw.json` (re-lock config)
  4. Send SIGHUP to gateway process (config reload without restart)
- Bootstrap.sh idempotency: check if Automation Supervisor already in agents.list before patching
- Budget CFO and Business Researcher are onboarded via add-director.sh as a human-guided step (08-04)
- `agents.list` at end of Phase 8: exactly 4 entries — main, automation-supervisor, budget-cfo, business-researcher
- workflow-worker is NOT in agents.list — it is sessions_spawn ephemeral (see Workflow Workers decision)

### Agents.list Final State

**Decision:** 4 agents total after Phase 8 completes.

| Agent ID | Type | Seeded by |
|----------|------|-----------|
| main | persistent | Already exists (Phase 1) |
| automation-supervisor | persistent Director | bootstrap.sh (08-01) |
| budget-cfo | persistent Director | add-director.sh (08-04) |
| business-researcher | persistent Director | add-director.sh (08-04) |

- n8n-specialist is a **Claude Code project**, NOT an OpenClaw agent — does not appear in agents.list
- workflow-worker is a **sessions_spawn pattern**, NOT an agents.list entry

### Workflow Workers: sessions_spawn, NOT agents.list

**Decision:** Ephemeral sub-agents for discrete tasks are created with sessions_spawn, not registered as agents.

- `ARCHITECTURE_REFINEMENT.md` Section 6: "workflow-worker is NOT in agents.list — use sessions_spawn"
- Directors spawn workers as needed for specific tasks; workers terminate after completion
- No bootstrap.sh changes needed for workflow-worker support (it's a runtime primitive)
- `ARCHITECTURE_PLAN.md` Section 3b listed workflow-worker as a "New" agents.list entry — **SUPERSEDED**

### Sessions: Persistent Resume, NOT Create-New

**Decision:** Director sessions are persistent. Hook POSTs with a fixed sessionKey resume the existing session.

- `ARCHITECTURE_REFINEMENT.md` Section 5: "Sessions are persistent. Hook POSTs with explicit sessionKey resume existing session."
- SOUL.md must say "check your session context first — you may already have context" NOT "you wake fresh each session"
- Session routing rules (Section 8):
  - **Fixed sessionKey** (e.g., `hook:automation-supervisor`) → resumes existing session, maintains context continuity
  - **Namespaced sessionKey** (e.g., `hook:automation-supervisor:task-<id>`) → isolated new task session, no bleed-over
- This means Directors accumulate knowledge within their sessions over time — intentional design
- bootstrap.sh does NOT clear/reset Director session files on deploy

### Director Communication: HTTP POST curl, NOT tools.agentToAgent

**Decision:** Directors communicate with each other via HTTP POST to the hooks endpoint using curl.

- `ARCHITECTURE_REFINEMENT.md` Section 7: "Director comm = HTTP POST curl (no tools.agentToAgent)"
- Pattern: `curl -X POST http://127.0.0.1:18789/hooks/agent -d '{"agentId": "budget-cfo", "sessionKey": "hook:budget-cfo", "message": "..."}'`
- This is already how n8n → Director communication works; Director → Director uses same pattern
- No special MCP tools needed for Director-to-Director communication

### Workspace Files: Auto-Loaded by Gateway

**Decision:** SOUL.md, HEARTBEAT.md, and AGENTS.md in a Director's workspace are automatically loaded by the gateway. No explicit configuration needed.

- `ARCHITECTURE_REFINEMENT.md` Section 9: "Workspace files auto-loaded (SOUL.md, HEARTBEAT.md, AGENTS.md)"
- bootstrap.sh seeds SOUL.md and HEARTBEAT.md for Automation Supervisor's workspace on first deploy
- add-director.sh seeds SOUL.md and HEARTBEAT.md for Budget CFO and Business Researcher
- cmp-based versioning: if repo version differs from container version, update the file (not just seed-if-missing)
- AGENTS.md provides inter-agent protocol — already seeded in Phase 6 (06-02)

### COMPANY_MEMORY.md: Single extraPaths Patch

**Decision:** COMPANY_MEMORY.md is indexed via `agents.defaults.memorySearch.extraPaths`. No QMD collections.

- Single jq patch in bootstrap.sh appends COMPANY_MEMORY.md path to `agents.defaults.memorySearch.extraPaths`
- This makes it searchable by ALL agents without per-Director config
- Path: `${WORKSPACE_DIR}/COMPANY_MEMORY.md` (main agent's workspace)
- Idempotent: check if path already in extraPaths array (by membership, not length) before appending

### Weekly Retrospective: OpenClaw Native Cron

**Decision:** Weekly retrospective uses OpenClaw's native cron system (`cron.enabled: true` already set).

- Main agent workspace gets a `cron/weekly-retrospective.md` file with YAML frontmatter schedule
- File-based cron is the approach; fallback to `cron.jobs` jq patch only if file-based cron doesn't work at runtime
- **VERIFY at execution time**: confirm whether OpenClaw's cron system reads from `cron/` subdirectory or only `cron.jobs` in config
- If `cron.jobs` approach is needed: the key IS valid (confirmed in ARCHITECTURE_REFINEMENT.md Section 11 note: "cron.jobs key unverified — test before committing")
- Cron runs main agent (not a Director) to distill organizational learning weekly

### Automation Supervisor: Claude Code as Execution Layer

**Decision:** Automation Supervisor uses Claude Code CLI for PTY-based infrastructure execution.

- Claude Code installed at `/data/.local/bin/claude` (on persistent volume, survives redeploys)
- Auth: copy `~/.claude/.credentials.json` and `~/.claude.json` from Mac to server container — human checkpoint required
- ANTHROPIC_API_KEY must be persisted on the container: add to BWS write loop in bootstrap.sh alongside N8N_API_KEY
- Auto-updates disabled: `DISABLE_AUTOUPDATER=1` in `/data/.claude/settings.env`
- Supervisor's SOUL.md documents when to use `claude -p` vs direct tool calls

### n8n Self-Healing Loop

**Decision:** n8n Global Error Trigger workflow POSTs to `hook:automation-supervisor` with structured error payload.

- Workflow created via n8n API (automated), activated immediately
- Payload includes: `agentId`, `sessionKey: "hook:automation-supervisor"`, structured error message with workflow name, failed node, error text, execution URL
- Setting as "Default Error Workflow" in n8n Settings may require manual UI step (API may not support it)
- Infinite loop prevention: n8n built-in (error workflow itself doesn't trigger the error trigger)

### Gateway Reload After add-director.sh

**Decision:** SIGHUP triggers config reload. Verify gateway responds before proceeding.

- After any add-director.sh invocation, send `kill -HUP $(pgrep -f openclaw-gateway)` or equivalent
- **Open question from refinement**: Does SIGHUP actually cause config reload in this OpenClaw version, or does it require container restart? Verify at 08-04 execution time.
- Fallback: `docker restart <container>` if SIGHUP doesn't work
- Post-reload verification: ping the new Director's hook endpoint and confirm 200 response before marking done

### SOUL.md Content for Directors

**Decision:** Director SOUL.md files must reflect session persistence model.

- Must say: "Check your session context first — you may have prior context from earlier work"
- Must NOT say: "You wake fresh each session" or imply stateless operation
- Must include escalation taxonomy and the Director's domain scope
- Automation Supervisor SOUL.md includes: Claude Code usage guidance, self-healing loop awareness, Director intake process overview

### QMD References in SOUL.md / ARCHITECTURE_PLAN.md

**Decision:** Any reference to "QMD search" in delivered artifacts maps to `memory_search` tool call.

- SOUL.md, HEARTBEAT.md, AGENTS.md templates must use `memory_search` not "QMD query"
- This fixes the HIGH contradiction identified in quick-11 verification
- `ARCHITECTURE_PLAN.md` Section 8 "Cross-Agent Query Protocol via QMD" → implement as `memory_search` calls

### Claude's Discretion

- HEARTBEAT.md exact content for Budget CFO and Business Researcher (Automation Supervisor's is more detailed)
- RETROSPECTIVE_PROTOCOL.md exact structure (main agent uses this when weekly cron fires)
- Exact escalation taxonomy wording in Director SOUL.md files (follow ARCHITECTURE_PLAN.md spirit)
- Whether to use a `skill` wrapper or raw `script` for add-director.sh (open question — use script, promote to skill later if needed)

</decisions>

<specifics>
## Specific Ideas

- **"No drift" principle**: ARCHITECTURE_REFINEMENT.md is the canonical source of truth where it disagrees with ARCHITECTURE_PLAN.md. Plans should cite ARCHITECTURE_REFINEMENT.md section numbers when implementing a refined decision.
- **Automation Supervisor is special**: It's the only Director seeded in bootstrap.sh. It's the entry point for the self-healing loop. Its SOUL.md is the most detailed.
- **add-director.sh is the Director creation primitive**: Every future Director goes through this script. It must be idempotent (check if agent already exists before adding).
- **Session key convention**: `hook:<agent-id>` for persistent session, `hook:<agent-id>:<task-id>` for isolated task. Directors use their persistent key by default; spawn namespaced keys only for parallel/isolated work.
- **MEMORY.md in hook sessions**: Per ARCHITECTURE_REFINEMENT.md Section 12, it's unknown whether MEMORY.md is auto-loaded in hook-triggered sessions. Verify at execution time and document the finding.
- **Commit size discipline**: Per project pattern, each plan should produce 1-2 atomic commits with clear subjects.

</specifics>

<deferred>
## Deferred Ideas

- **Canonical n8n data feeds** (email.received, monarch.transaction, calendar, Notion changes) — built on-demand by Directors after they're running via Director Intake Process. NOT Phase 8 scope.
- **n8n microservice layer** (full canonical data feed architecture from ARCHITECTURE_PLAN.md Sections 5-7) — out of scope for Phase 8, built organically after Directors are live
- **QMD at scale** — ARCHITECTURE_REFINEMENT.md notes "QMD's advantage matters at scale." Revisit when workspace grows beyond ~1000 files and memorySearch retrieval quality degrades.
- **Tailscale integration** — Phase 7, not a dependency for Phase 8. Can be executed independently.
- **Schema registry** (mentioned in ARCHITECTURE_PLAN.md Section 3d) — deferred until Directors need it; no blocking dependency for Phase 8.
- **n8n-specialist Claude Code project** — exists separately from this phase; not part of Phase 8 deployment.

</deferred>

---

## Open Questions (from ARCHITECTURE_REFINEMENT.md Section 12)

These were unresolved at architecture time. Verify at execution time and document findings in plan summaries:

1. **MEMORY.md in hook sessions**: Does OpenClaw auto-load MEMORY.md for sessions triggered via hooks (not chat)? If not, how do Directors persist learned patterns?
2. **Gateway reload**: Does `kill -HUP` on the gateway process actually reload config, or does it require container restart?
3. **add-director.sh as skill vs script**: Decided: implement as script at `scripts/add-director.sh`. Promote to skill if Directors need to invoke it themselves (future phase).
4. **HEARTBEAT.md vs BOOT.md**: `ARCHITECTURE_REFINEMENT.md` uses "HEARTBEAT.md" — this is the name used in Phase 8. BOOT.md is older naming (pre-Phase 6). Use HEARTBEAT.md.

---

*Phase: 08-the-organization-director-workforce*
*Context gathered: 2026-02-22*
