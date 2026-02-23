# Phase 8 Architecture Verification Report
**Date**: 2026-02-22 | **Scope**: 08-01 through 08-05 vs ARCHITECTURE_PLAN.md + ARCHITECTURE_REFINEMENT.md

---

## Summary Assessment

Phase 8 plans cover the core agent infrastructure (Automation Supervisor registration, workspace seeding, Claude Code PTY, n8n error trigger, Director onboarding via add-director.sh). They are **MISSING** the entire n8n microservice/data feed layer (email.received, monarch.transaction, calendar.event, krisp.meeting), the schema registry JSON files, several operational protocols, and contain 3 direct contradictions with the architecture documents.

**Overall verdict**: Plans are NOT ready for execution as-is. Resolve contradictions first; add missing microservice layer before or alongside Phase 8.

---

## 1. Coverage Matrix — ARCHITECTURE_PLAN.md Sections

| Architecture Section | Plan(s) | Status |
|---|---|---|
| 1. Org Chart (main agent, Supervisor, Budget CFO, Business Researcher, Workflow Workers) | 08-01, 08-04 | Partial — Supervisor seeded in 08-01; CFO/BR onboarded via add-director.sh in 08-04; Workflow Workers correctly identified as sessions_spawn (not agents.list) per REFINEMENT |
| 2. Communication Model (session keys, Director-to-Director, escalation to main) | 08-01 (SOUL.md), 08-03, 08-04 | Partial — session keys defined in SOUL.md; hook routing tested in 08-04/08-05; Director-to-Director pattern documented in SOUL.md but no plan verifies it end-to-end |
| 3. The Automation Supervisor (reasoning mode, execution mode, self-healing, QMD memory) | 08-01 (SOUL.md, HEARTBEAT.md), 08-02 (Claude Code), 08-03 (error trigger) | Partial — reasoning mode and Claude Code PTY covered; self-healing loop is partially covered (error trigger in 08-03, pattern recording in SOUL.md); QMD memory references contradict REFINEMENT (see Contradictions) |
| 4. The n8n Microservice Layer (canonical data feeds: email.received, monarch.transaction, calendar.event, krisp.meeting) | NONE | **GAP — BLOCKING** (see Gap 1) |
| 5. Schema Registry (email.received.json, monarch.transaction.json, calendar.event.json) | NONE | **GAP — BLOCKING** (see Gap 2) |
| 6. Memory Architecture (per-agent memory, COMPANY_MEMORY.md, weekly retrospective) | 08-01 (COMPANY_MEMORY.md, extraPaths, cron), 08-04 (Director workspaces) | Partial — COMPANY_MEMORY.md and extraPaths covered in 08-01; Director memory dirs seeded by add-director.sh in 08-04; Director HEARTBEAT.md missing for CFO/BR (see Gap 9); memory/patterns/ templates missing (see Gap 10) |
| 7. Escalation Taxonomy (Class 1-4) | 08-01 (Supervisor SOUL.md) | Covered — escalation taxonomy documented in SOUL.md spec |
| 8. Token Efficiency via QMD / Cross-Agent Query Protocol | NONE | **GAP — Degraded** (see Gap 6) |
| 9. Supervisor Health Monitoring (main agent heartbeat check) | NONE | **GAP — Degraded** (see Gap 4) |
| 10. Director Intake Process (5-step structured onboarding, ONBOARDING.md) | 08-04 (partial — runs add-director.sh) | **GAP — Degraded** (see Gap 5) — 08-04 runs add-director.sh but does NOT implement structured intake or ONBOARDING.md |
| 11. Infrastructure Requirements (agents.list entries, n8n feeds, schema registry, COMPANY_MEMORY.md, Claude Code) | 08-01 (agents.list, COMPANY_MEMORY.md), 08-02 (Claude Code), 08-03 (error trigger) | Partial — agent registration and Claude Code covered; n8n canonical feeds and schema registry NOT covered (Gaps 1 and 2) |
| 12. What This Is Not (scope limitations) | N/A | N/A — not an implementation target |

**Coverage Count:**
- Fully covered: 1 (Section 7 — Escalation Taxonomy)
- Partially covered: 6 (Sections 1, 2, 3, 6, 10, 11)
- Not covered — BLOCKING: 2 (Sections 4 and 5)
- Not covered — Degraded: 3 (Sections 8, 9, 10 partial)
- Not applicable: 1 (Section 12)

---

## 2. ARCHITECTURE_REFINEMENT.md Compliance

| Refinement Section | Plan(s) | Status |
|---|---|---|
| 1. Repo is core infra only (bootstrap.sh seeds only Supervisor; Directors created by main agent via add-director.sh) | 08-01 | Covered — 08-01 explicitly omits budget-cfo, business-researcher, workflow-worker from bootstrap.sh |
| 2. Director Registration Mechanism (add-director.sh: validates input, idempotent, locks/unlocks config, SIGHUP) | 08-01 (Task 1) | Covered — add-director.sh spec fully described in 08-01 Task 1 |
| 3. Memory System: Built-in memorySearch, NOT QMD | 08-01 (extraPaths patch) | **Partial — Contradiction** (see Contradiction 1) — 08-01 SOUL.md Task 1 references "QMD search" in self-healing loop despite Refinement Section 3 explicitly ruling out QMD |
| 4. Cross-Agent Shared Memory (COMPANY_MEMORY.md via agents.defaults.memorySearch.extraPaths) | 08-01 (Task 2) | Covered — bootstrap.sh jq patch for extraPaths documented in 08-01 Task 2 |
| 5. Sessions Are Persistent (hook POSTs resume existing session; 4AM daily reset; session vs memory files) | 08-01 (SOUL.md), 08-04 (SOUL.md instructions) | **Partial — Contradiction** (see Contradiction 3) — SOUL.md spec in 08-01 oversimplifies session persistence |
| 6. Workflow Workers Are sessions_spawn, Not agents.list | 08-05 (verification checklist confirms no workflow-worker in agents.list) | Covered — 08-05 explicitly verifies workflow-worker is absent; no plan adds it |
| 7. Director-to-Director Communication (HTTP POST via Bash, no agentToAgent config needed) | 08-01 (SOUL.md documents curl pattern), 08-04 | Covered — SOUL.md documents curl POST pattern; no agentToAgent config added |
| 8. Session Routing (who decides new vs resume: sender, Director, main agent) | 08-01 (SOUL.md partial), 08-04 | **Partial — Contradiction** (see Contradiction 3) — protocol simplified in SOUL.md vs what Refinement Section 8 specifies |
| 9. Workspace Files Auto-Loaded at Session Start (AGENTS.md, SOUL.md, HEARTBEAT.md auto-injected) | 08-01 (HEARTBEAT.md for Supervisor) | Partial — Supervisor HEARTBEAT.md covered; Budget CFO and Business Researcher HEARTBEAT.md missing (Gap 9); AGENTS.md not created in any plan (Gap 7) |
| 10. Automation Supervisor Is Special (only Director seeded by bootstrap.sh; richer SOUL.md requirements) | 08-01 | Covered — 08-01 dedicates full Task 1 to specialized Supervisor SOUL.md with all required sections |
| 11. What Changes in Phase 8 Plans (plan-by-plan change table) | 08-01 through 08-05 | Partial — changes from Refinement Section 11 are applied in the plans, but not all (add-director.sh as skill question unresolved — see Gap 8) |
| 12. Open Questions (4 unresolved questions before execution) | NONE | **GAP — Risk** (see Gap 8) — all 4 open questions are unresolved; plans make assumptions that may be wrong |

**Compliance Count:**
- Fully compliant: 5 (Sections 1, 2, 4, 6, 7, 10)
- Partially compliant with contradictions: 3 (Sections 3, 5, 8)
- Partially compliant with gaps: 2 (Sections 9, 11)
- Not addressed — Risk: 1 (Section 12)

---

## 3. Gaps (Architecture describes it, no plan covers it)

---

### GAP 1: Canonical Data Feeds (ARCHITECTURE_PLAN.md Section 4) — BLOCKING

**What the architecture describes**: Section 4 specifies 4 canonical n8n data feeds that all Director data consumption flows through:
- `email.received` — merge + normalize Gmail (3 inboxes) → enrich → publish event
- `monarch.transaction.new` — Monarch data via n8n
- `calendar.event.created` — Google Calendar
- `krisp.meeting.completed` — Krisp webhook

Architecture principle: "No Director ever touches raw API credentials. All external data flows through standardized n8n microservices owned by the Automation Supervisor."

**Which architecture section**: Section 4 (The n8n Microservice Layer)

**Impact**: **BLOCKING** — Budget CFO and Business Researcher have session keys and SOUL.md but no data to consume. Without email.received, the CFO cannot reconcile expenses; without monarch.transaction.new, the CFO has no transaction events; without calendar.event.created, the Business Researcher cannot process meetings. The Directors are shells with no inputs.

**What the plans do**: 08-03 creates the error handler workflow only (n8n's Global Error Trigger → OpenClaw hooks). None of the 4 canonical feeds are created in any plan (08-01 through 08-05).

**Suggested fix**: Add a new plan 08-06 (Canonical Data Feeds) OR add tasks to 08-03 for each feed. Each feed needs its own n8n workflow: trigger → normalize → enrich → HTTP POST to Director session key. Start with email.received (highest value, consumed by both Directors).

---

### GAP 2: Schema Registry JSON Files (ARCHITECTURE_PLAN.md Section 5) — BLOCKING

**What the architecture describes**: Section 5 specifies the schema registry at `Automation Supervisor workspace/memory/schemas/` with named JSON schema files:
- `memory/schemas/email.received.json`
- `memory/schemas/monarch.transaction.json`
- `memory/schemas/calendar.event.json`

These are the contracts that enforce event standardization across the microservice layer.

**Which architecture section**: Section 5 (Schema Registry)

**Impact**: **BLOCKING** — Without schema files, the canonical feeds cannot be built with enforced shapes. The Supervisor's capability registry (capabilities.md) is seeded empty, but the schema files that define the event contracts are never created. When the Supervisor eventually builds feeds, it will have no documented schema to build against.

**What the plans do**: 08-01 Task 1 creates `memory/schemas/capabilities.md` (the capability registry) but no JSON schema files. No plan creates email.received.json, monarch.transaction.json, or calendar.event.json.

**Suggested fix**: Add schema file creation to the canonical feeds plan (proposed 08-06), or add it as a task to 08-01. The schema files are templates — they can be authored before the actual n8n feeds exist, enabling parallel development.

---

### GAP 3: Microservice Design Principles Enforcement (ARCHITECTURE_PLAN.md Section 4) — Degraded

**What the architecture describes**: Section 4 specifies 4 microservice design principles:
1. Standardize first
2. Enrich at ingestion
3. Event-driven (subscribe, don't poll)
4. **Git-versioned — every workflow change is committed before deployment**

The git-versioning principle means n8n workflows should live in the git repo and be deployed via API, not created ad-hoc through the UI.

**Which architecture section**: Section 4, Microservice Design Principles

**Impact**: Degraded — 08-03 creates the error handler via n8n API without committing the workflow JSON to the repo. Any workflow created this way lives only in n8n's database; it is not git-versioned, cannot be reviewed, and is lost if n8n is reset. The enrichment pipeline (principle 2) has no plan.

**Suggested fix**: Add a `workflows/` directory to the repo and commit workflow JSON before deploying. Add to 08-03's Task 1 an instruction to save the workflow JSON to `workflows/openclaw-error-handler.json` before deploying. Extend to canonical feeds plan (08-06).

---

### GAP 4: Supervisor Health Monitoring by Main Agent (ARCHITECTURE_PLAN.md Section 9) — Degraded

**What the architecture describes**: "The Main Agent runs a periodic heartbeat check on the Automation Supervisor. If the Supervisor is unresponsive or in a broken state, the Main Agent escalates directly to Ameer (Class 2 escalation)."

The Supervisor maintains `memory/SYSTEM_HEALTH.md` as "the first thing the Main Agent reads during health checks."

**Which architecture section**: Section 9 (Supervisor Health Monitoring)

**Impact**: Degraded — If the Automation Supervisor crashes or enters a broken state, the Main Agent will not detect it until the weekly retrospective cron fires (Sunday 10 AM). Class 2 escalation requires authorization — undetected Supervisor failure means no self-healing for potentially 7 days.

**What the plans do**: 08-01 adds a weekly-retrospective cron (Sundays 10 AM) to the main agent. No plan configures a separate, frequent heartbeat check on the Supervisor. The weekly retrospective checks SYSTEM_HEALTH.md as one of multiple steps (not a dedicated health check).

**Suggested fix**: Add a second OpenClaw cron job (e.g., daily or every 6 hours) with a targeted SYSTEM_HEALTH.md check message to the main agent's session. This is a 5-line jq patch in bootstrap.sh, addition to 08-01 Task 2.

---

### GAP 5: Director Intake Process / ONBOARDING.md (ARCHITECTURE_PLAN.md Section 10) — Degraded

**What the architecture describes**: Section 10 defines a 5-step structured intake process for new Directors:
1. Main agent drafts a brief (domain, data needs, capability requirements)
2. Automation Supervisor responds (what infrastructure exists, what needs building, what gaps)
3. Ameer reviews and approves
4. Supervisor builds required n8n microservices, registers capabilities, updates schema registry
5. Director onboarded with `ONBOARDING.md` seeded — "the transcript of the intake meeting, the full capability surface, what was explicitly excluded and why"

**Which architecture section**: Section 10 (Director Intake Process)

**Impact**: Degraded — 08-04 runs add-director.sh to register Budget CFO and Business Researcher but skips steps 1-4 entirely. The ONBOARDING.md file (the Director's "what I have access to" document) is never created. Directors come online without documented context about what capabilities were built for them and why certain things were excluded.

**What the plans do**: 08-04 is the "human-guided" Director creation plan. It calls add-director.sh manually (or via main agent) and asks the user to customize SOUL.md via vi. There is no structured brief, no Supervisor response, no Ameer review step, and no ONBOARDING.md.

**Suggested fix**: Add an ONBOARDING.md template to `docs/directors/` and have add-director.sh seed it. For the first two Directors (Budget CFO, Business Researcher), manually author their ONBOARDING.md as part of 08-04 to establish the pattern.

---

### GAP 6: Token Efficiency / Cross-Agent Query Protocol (ARCHITECTURE_PLAN.md Section 8) — Degraded

**What the architecture describes**: Section 8 establishes "The Rule: Never Read What You Can Query" with a specific cross-agent query protocol:
1. Run a targeted `memory_search` query first
2. Only escalate to reading a full file if the query returns nothing useful
3. Sub-agents summarize findings concisely before reporting back — never return raw file contents

This protocol should be enforced via the AGENTS.md (org-wide) document so all Directors follow it.

**Which architecture section**: Section 8 (Token Efficiency via QMD)

**Impact**: Degraded — Without this protocol documented in a place Directors always load (AGENTS.md or SOUL.md), individual Directors may dump full files (COMPANY_MEMORY.md, capabilities.md) into context instead of using memory_search. This grows worse as the workforce scales.

**What the plans do**: No plan creates an AGENTS.md file for any Director, and no plan documents the query protocol where it will be auto-loaded at session start. The Supervisor's SOUL.md focuses on self-healing, escalation, and Claude Code PTY — not the cross-agent query protocol.

**Suggested fix**: Resolve Gap 7 (create AGENTS.md) first, then add the "Never Read What You Can Query" protocol and the 3-step cross-agent query process to AGENTS.md. This is documented in the right place for all Directors to auto-load.

---

### GAP 7: AGENTS.md Org-Wide Protocol File (ARCHITECTURE_REFINEMENT.md Section 9) — Degraded

**What the architecture describes**: ARCHITECTURE_REFINEMENT.md Section 9 states: "AGENTS.md (org-wide protocol) is always in context for every Director — no need to re-read it." AGENTS.md is one of the files auto-injected at every session start.

Phase 6 Plan 06-02 seeded AGENTS.md into the main agent workspace. However, there is no AGENTS.md for individual Director workspaces — each Director needs one in their own workspace directory so OpenClaw auto-injects it.

**Which architecture section**: ARCHITECTURE_REFINEMENT.md Section 9

**Impact**: Degraded — Directors start every session without the org-wide protocol document. They cannot reference communication patterns, escalation taxonomy, session routing rules, or the cross-agent query protocol without being explicitly told in their SOUL.md (which inflates SOUL.md with redundant information).

**What the plans do**: 08-01 creates SOUL.md and HEARTBEAT.md for the Automation Supervisor workspace. 08-04 calls add-director.sh which seeds a minimal SOUL.md stub. No plan creates AGENTS.md for any Director workspace (neither Supervisor nor CFO/BR).

**Suggested fix**: Create `docs/directors/AGENTS.md` in the repo containing org-wide protocols (communication patterns, escalation taxonomy, query protocol, session routing rules). In 08-01 Task 2, seed AGENTS.md to the Supervisor workspace alongside SOUL.md. In add-director.sh, seed AGENTS.md to every new Director workspace automatically.

---

### GAP 8: REFINEMENT Open Questions Unresolved (ARCHITECTURE_REFINEMENT.md Section 12) — Risk

**What the architecture describes**: ARCHITECTURE_REFINEMENT.md Section 12 explicitly states 4 open questions that "should be verified before execution":
1. **MEMORY.md in hook sessions** — Do webhook-triggered Director sessions count as "private" (MEMORY.md loads) or "shared/group" (MEMORY.md suppressed)?
2. **Gateway reload mechanism** — Does patching agents.list + `chmod 444` require a full restart, or does the gateway hot-reload on SIGHUP?
3. **add-director.sh as a skill vs raw script** — Should this be packaged as an OpenClaw skill for discoverability, or a raw `/app/scripts/` script?
4. **HEARTBEAT.md vs BOOT.md** — Are these different things? BOOT.md is listed as "first run only" — does HEARTBEAT.md run every session or also first-run-only?

**Which architecture section**: ARCHITECTURE_REFINEMENT.md Section 12

**Impact**: Risk — Plans make assumptions about each:
- **Q1 assumption**: 08-01 seeds MEMORY.md-like files assuming they'll load in hook sessions. If sessions are "shared/group", MEMORY.md is suppressed and Director context degrades silently.
- **Q2 assumption**: 08-04 sends SIGHUP to reload the gateway after add-director.sh patches agents.list. If SIGHUP is not supported and a full restart is required, Director creation will silently fail until container restart.
- **Q3 assumption**: Plans use raw `/app/scripts/add-director.sh` (image path). If the Supervisor can't execute raw scripts from the image path, the Director creation mechanism breaks.
- **Q4 assumption**: Plans create HEARTBEAT.md expecting it fires every session. If it only fires on BOOT (first run only), the Supervisor's session-start checklist never runs after initial boot.

**Suggested fix**: Add a Task 0 (pre-flight) to 08-01 that tests each open question against the live container before executing any configuration changes. Document the findings and update plan assumptions accordingly before proceeding.

---

### GAP 9: Director-Specific HEARTBEAT.md (ARCHITECTURE_REFINEMENT.md Section 9) — Cosmetic

**What the architecture describes**: ARCHITECTURE_REFINEMENT.md Section 9 states HEARTBEAT.md is auto-loaded at every session start and is "the right place for session-start checklists." Implication: each Director should have a domain-specific HEARTBEAT.md.

ARCHITECTURE_REFINEMENT.md Section 10 explicitly specifies the Supervisor's HEARTBEAT.md. By extension, Budget CFO and Business Researcher should also have HEARTBEAT.md files with domain-relevant checklists.

**Which architecture section**: ARCHITECTURE_REFINEMENT.md Sections 9, 10

**Impact**: Cosmetic — Budget CFO and Business Researcher will function without HEARTBEAT.md, but they will miss session-start guidance (e.g., "on wake: run memory_search for pending transactions, check if monarch.transaction feed is active").

**What the plans do**: 08-01 creates Supervisor HEARTBEAT.md. 08-04 creates Director SOUL.md stubs via add-director.sh but no HEARTBEAT.md. No plan creates HEARTBEAT.md for Budget CFO or Business Researcher.

**Suggested fix**: Add HEARTBEAT.md templates to `docs/directors/budget-cfo/` and `docs/directors/business-researcher/` in the repo. Update add-director.sh to optionally accept a HEARTBEAT.md source path and seed it during Director creation.

---

### GAP 10: Director-Specific memory/patterns/ Directory Seeding (ARCHITECTURE_PLAN.md Section 6) — Cosmetic

**What the architecture describes**: Section 6 (Memory Architecture) specifies:
- Budget CFO: Financial memory at `memory/patterns/`
- Business Researcher: Research memory at `memory/patterns/`

These directories should ideally be pre-seeded with an empty template so the Directors know where to write their patterns.

**Which architecture section**: ARCHITECTURE_PLAN.md Section 6 (Memory Architecture)

**Impact**: Cosmetic — Directories will be created on first write by the Director. However, without a template file, new Directors have no guidance on the expected format for recording patterns.

**What the plans do**: 08-01 seeds `memory/patterns/n8n-error-recovery.md` for the Automation Supervisor. 08-04's add-director.sh creates the workspace directory but the spec (08-01 Task 1) does not mention seeding memory/patterns/ templates for other Directors.

**Suggested fix**: Update add-director.sh to create `memory/patterns/` and seed a `memory/patterns/README.md` template explaining the format. Low effort, high organizational value.

---

## 4. Contradictions (Plan says X, architecture says Y)

---

### CONTRADICTION 1: QMD References in Supervisor SOUL.md — Risk: HIGH

**Where in the plans**: 08-01 Task 1, Supervisor SOUL.md spec, Self-Healing Loop section:
```
## Self-Healing Loop
When you receive an n8n error webhook:
1. Check memory/patterns/n8n-error-recovery.md for known fix (QMD search)
```

Additionally, ARCHITECTURE_PLAN.md Section 3d is titled "QMD Memory for Pattern Evolution" and describes QMD cross-workflow pattern recognition.

**What the architecture says**: ARCHITECTURE_REFINEMENT.md Section 3 explicitly and completely rules out QMD:
> "Stay on built-in memorySearch. QMD is not our backend."
> "Decision: Stay on built-in memorySearch."

ARCHITECTURE_REFINEMENT.md supersedes ARCHITECTURE_PLAN.md where noted. Section 3 of the Refinement document directly applies to Section 3d of the Architecture Plan.

**Impact**: Risk — If the SOUL.md is seeded with "QMD search" instructions, the Automation Supervisor will attempt to use QMD, which is not configured. The correct tool is `memory_search` (built-in). This will cause the Supervisor to either fail silently or produce confusing errors when trying to follow its own protocol.

**Required fix before execution**: In the Supervisor SOUL.md, replace every reference to "QMD search" with `memory_search`. The self-healing loop step should read:
```
1. Run: memory_search "error signature or workflow name" in memory/patterns/n8n-error-recovery.md
```

Also review SOUL.md Section 3d references (if any) and remove all QMD terminology.

---

### CONTRADICTION 2: Cron Config Key Structure (`cron.jobs`) — Risk: HIGH

**Where in the plans**: 08-01 Task 2, weekly retrospective cron patch:
```bash
jq '.cron.jobs = ((.cron.jobs // []) + [{
  "name": "weekly-retrospective",
  "schedule": "0 10 * * 0",
  ...
}])' "$CONFIG_FILE"
```

**What the architecture says**: Neither ARCHITECTURE_PLAN.md nor ARCHITECTURE_REFINEMENT.md specifies the exact JSON path for OpenClaw's cron configuration. ARCHITECTURE_PLAN.md Section 11 mentions "COMPANY_MEMORY.md + weekly cron" as a new infrastructure item but does not document the config schema.

**The problem**: MEMORY.md (project memory) notes: "OpenClaw has native cron system (`cron.enabled: true` in openclaw.json)." But `cron.jobs` as a key structure is speculative — it is not confirmed from OpenClaw documentation. MEMORY.md also states: "OpenClaw strictly validates openclaw.json — unknown keys CRASH the gateway."

If `cron.jobs` is not a valid OpenClaw config key (e.g., the actual key is `cron.schedules`, `hooks.cron`, or agent-level cron), the jq patch will write an invalid key that crashes the gateway on next start.

**Impact**: Risk: HIGH — A gateway crash on deploy is the worst possible failure mode: it takes down ALL agents and the hooks endpoint simultaneously.

**Required verification before execution**: Test `cron.jobs` against a running container before committing 08-01 changes. Check OpenClaw source or docs for the exact cron config schema. If `cron.jobs` is invalid, identify the correct key and update the bootstrap.sh patch.

---

### CONTRADICTION 3: Session Protocol in SOUL.md vs ARCHITECTURE_REFINEMENT.md Section 5 and 8 — Risk: MEDIUM

**Where in the plans**: 08-01 Task 1, Supervisor SOUL.md spec, Session Protocol section:
```
## Session Protocol
- Sessions are persistent. Check your session context first — you likely have prior work in progress.
- Read memory files when starting a genuinely new task or after a 4AM reset.
- After completing a major task:
  1. Write outcome to memory/patterns/ or memory/SYSTEM_HEALTH.md
  2. Call /new to reset your session for clean context
  3. Confirm completion to main agent
```

**What the architecture says**: ARCHITECTURE_REFINEMENT.md Sections 5 and 8 specify a more nuanced 3-decision-point model for session routing:

Section 5:
> "SOUL.md should NOT say 'you wake fresh each session.' It should say: check your session context first — you likely have prior work in progress."

Section 8 (Session Routing — Who Decides New vs Resume):
> Three decision points: **Sender** (fixed key = resume; namespaced key = new), **Director itself** (calls /new or /reset), **Main agent** (sends /new first)
> SessionKey patterns: `hook:automation-supervisor` (event stream, always resume) vs `hook:automation-supervisor:task-<id>` (isolated task, new context)

**The discrepancy**: The SOUL.md spec in 08-01 documents the Director's own role (call /new after major task) but omits the Sender decision point (namespaced sessionKey = new session) and the Main Agent decision point (main sends /new before delegating an isolated task). A Supervisor relying only on its SOUL.md will not know to handle `hook:automation-supervisor:task-<id>` differently from `hook:automation-supervisor`.

**Impact**: Risk: MEDIUM — The Supervisor may contaminate isolated task sessions with event stream context, or fail to recognize that a namespaced sessionKey signals a fresh context request from the main agent.

**Required fix**: Add the full 3-decision-point session routing to the SOUL.md spec:
```
## Session Routing
- Incoming sessionKey = hook:automation-supervisor → your event stream, always resume, accumulate context
- Incoming sessionKey = hook:automation-supervisor:task-<id> → isolated task from main agent, treat as fresh context
- Main agent may send /new before a delegation message to ensure clean state
```

---

## 5. Summary

| Category | Count |
|---|---|
| Architecture sections fully covered | 1 |
| Architecture sections partially covered | 6 |
| Architecture sections not covered — BLOCKING | 2 |
| Architecture sections not covered — Degraded | 3 |
| Refinement sections fully compliant | 5 |
| Refinement sections partially compliant (with gaps or contradictions) | 5 |
| Refinement sections not addressed — Risk | 1 |
| Gaps total | 10 |
| Gaps — BLOCKING | 2 |
| Gaps — Degraded | 5 |
| Gaps — Risk | 1 |
| Gaps — Cosmetic | 2 |
| Contradictions | 3 |
| Contradictions — Risk HIGH | 2 |
| Contradictions — Risk MEDIUM | 1 |
| Open questions unresolved (from REFINEMENT Section 12) | 4 |

### Go / No-Go Assessment

**Before executing ANY Phase 8 plan:**
1. Resolve Contradiction 2 (cron.jobs schema) — HIGH risk of gateway crash
2. Resolve Contradiction 1 (QMD → memory_search in SOUL.md) — will cause Supervisor to malfunction

**Before calling Phase 8 "done":**
3. Address Gap 1 (canonical data feeds) and Gap 2 (schema registry) — Directors are shells without data
4. Answer the 4 open questions from REFINEMENT Section 12 (Gap 8) and update plan assumptions

**Can be deferred post-Phase 8:**
5. Gaps 3, 4, 5, 6, 7 (degraded operational quality — system works but sub-optimally)
6. Gaps 9 and 10 (cosmetic — Director HEARTBEAT.md and memory templates)

**Overall**: Plans 08-01 through 08-05 build the skeleton (agent registration, Claude Code, hook routing) but NOT the nervous system (data feeds, schema registry, health monitoring, intake process). The skeleton is a prerequisite but insufficient for an operational Organization.

---

*Report produced: 2026-02-22*
*Analyzed: ARCHITECTURE_PLAN.md v2.0 + ARCHITECTURE_REFINEMENT.md + 08-01 through 08-05 PLAN.md*
