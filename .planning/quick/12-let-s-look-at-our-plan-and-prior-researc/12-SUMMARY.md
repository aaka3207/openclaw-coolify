---
phase: quick-12
plan: "01"
subsystem: agent-workforce
tags: [memory, soul-md, agents-md, directors, gap-analysis, phase-8]
dependency_graph:
  requires: [08-01]
  provides: [phase-8-memory-gap-list]
  affects:
    - docs/reference/agents/automation-supervisor/SOUL.md
    - docs/reference/agents/budget-cfo/SOUL.md
    - docs/reference/agents/business-researcher/SOUL.md
    - scripts/bootstrap.sh
    - .planning/phases/08-the-organization-director-workforce/08-02-PLAN.md
    - .planning/phases/08-the-organization-director-workforce/08-04-PLAN.md
    - .planning/phases/08-the-organization-director-workforce/08-05-PLAN.md
tech_stack:
  added: []
  patterns: []
key_files:
  created:
    - .planning/quick/12-let-s-look-at-our-plan-and-prior-researc/12-SUMMARY.md
  modified: []
decisions:
  - "SOUL.md operational content is acceptable as-is given cmp-based overwrite semantics — no split needed"
  - "memory_search in SOUL.md must be qualified with file-read fallback since it requires embeddings config"
  - "MEMORY.md is explicitly excluded from Director sessions in current AGENTS.md — this is a gap for Directors"
  - "TOOLS.md IS seeded by bootstrap.sh via cmp loop — not a gap"
  - "08-05 verification suite does not test memory_search availability — low-value addition given it cannot be verified structurally"
metrics:
  duration: "~15 min"
  completed: "2026-02-23"
  tasks: 1
  files: 1
---

# Phase Quick-12 Plan 01: Phase 8 Memory Handling Gap Analysis

Audit of plans 08-02 through 08-05 and the Automation Supervisor's SOUL.md to identify gaps in Director memory handling, memory_search availability assumptions, MEMORY.md seeding, SOUL.md content placement, and TOOLS.md seeding.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Audit Phase 8 plans and SOUL.md for memory handling gaps | (see final commit) | 12-SUMMARY.md |

---

## Executive Summary

Six questions audited. Found **5 real gaps** and **1 non-issue**. The most critical issues are:

1. `memory_search` is described as unconditionally available in all SOUL.md files, but it requires embeddings config and may not be available in hook-triggered sessions.
2. `MEMORY.md` is explicitly marked "main session only" in the shared AGENTS.md — Directors in hook sessions won't load it, but there is no Director-specific AGENTS.md that explains the correct substitute behavior.
3. 08-05's verification suite has no check for `memory_search` availability — the 08-04 open question on MEMORY.md behavior is not verified by the automated suite.

---

## Question-by-Question Analysis

---

### Q1: Do plans 08-02 through 08-05 reference `memory_search` as a tool the Supervisor can call?

**Finding: YES — and the framing is problematic.**

All three Director SOUL.md files (automation-supervisor, budget-cfo, business-researcher) contain this pattern:

```
Use `memory_search` (built-in tool) for all memory queries — do NOT use QMD
```

The plans do not explicitly claim `memory_search` is available, but the SOUL.md files shipped by 08-01 and referenced in 08-04 assume it is always available. The user's live session today confirmed:

- `memory_search` requires embeddings config (`agents.defaults.memorySearch.provider` + model/API key)
- bootstrap.sh patches `memorySearch.provider = "gemini"` with `gemini-embedding-001` — this requires a Gemini API key
- Whether `memorySearch.sync.onSessionStart = true` causes indexing/search to be available in hook-triggered sessions is **unverified** (documented as Open Question #1 in 08-CONTEXT.md)

**Result:** The SOUL.md files give Directors unrealistic expectations. If Gemini API key isn't present or if session-start sync doesn't work for hook sessions, `memory_search` silently returns nothing instead of failing loudly.

---

### Q2: Do any plans seed MEMORY.md or daily notes for Directors?

**Finding: NO — and the current AGENTS.md actively excludes Directors from MEMORY.md.**

**bootstrap.sh seeding for automation-supervisor workspace:**
- Seeds: `SOUL.md`, `HEARTBEAT.md`, `TOOLS.md` (cmp-based), `AGENTS.md` (seed-once)
- Seeds: `memory/patterns/` directory (empty)
- Does NOT seed: `MEMORY.md`, `memory/YYYY-MM-DD.md` daily notes

**add-director.sh seeding for budget-cfo / business-researcher:**
- Seeds: generic `SOUL.md`, `HEARTBEAT.md`
- Does NOT seed: `AGENTS.md`, `MEMORY.md`, `memory/` directory

**The AGENTS.md problem:**
The shared AGENTS.md (seeded to main workspace and supervisor workspace) contains this explicit rule:

> **ONLY load in main session** (direct chats with your human)
> **DO NOT load in MEMORY.md** in shared contexts

This means a Director receiving a hook POST would read AGENTS.md, see "ONLY load MEMORY.md in main session", and skip it. There is no Director-specific AGENTS.md that says "hook sessions are your main session — MEMORY.md IS appropriate for you."

Furthermore, the AGENTS.md "Every Session" checklist says:
```
4. **If in MAIN SESSION** (direct chat with your human): Also read `MEMORY.md`
```

Hook sessions are NOT recognized as "main session" by this language. Directors following AGENTS.md literally would never read MEMORY.md — even though MEMORY.md is the correct long-term memory store for them.

**Daily notes** (`memory/YYYY-MM-DD.md`) are mentioned in AGENTS.md but never seeded. Directors would need to create their own `memory/` directory. The 08-04 and 08-05 verification suites check that `memory/` exists, but not that any content is in it or that Directors know how to maintain it.

---

### Q3: Does the Supervisor's SOUL.md have operational content that belongs in AGENTS.md?

**Finding: YES — but it is acceptable given the cmp-based seeding architecture.**

The repo `docs/reference/agents/automation-supervisor/SOUL.md` contains these sections that are arguably "operational" rather than "identity":

- `## Self-Healing Loop Protocol` — step-by-step procedure
- `## Director Communication` — curl command pattern
- `## Director Lifecycle (add-director.sh)` — bash commands
- `## Execution Layer` — tmux commands, tool selection logic

Per OpenClaw docs: SOUL.md = persona/tone/boundaries; AGENTS.md = operating instructions + memory management.

**However, this is NOT a problem in this deployment for the following reason:**

- SOUL.md is **cmp-based** (repo overwrites volume if different) — the operator controls SOUL.md content permanently
- AGENTS.md is **seed-once** — agents can edit their own AGENTS.md after initial seed
- If operational content were in AGENTS.md, an agent could overwrite it. In SOUL.md, the operator guarantees it stays accurate.

**Recommendation:** Keep operational content in SOUL.md intentionally. Document the rationale in a comment at the top of the file so future maintainers understand this was deliberate. The live Supervisor writing session lifecycle tables to SOUL.md during today's session is not a problem — it will be overwritten on next deploy since SOUL.md is cmp-managed. However, any useful content the live Supervisor wrote should be harvested and committed to the repo SOUL.md.

---

### Q4: Does bootstrap.sh seed TOOLS.md for the Supervisor?

**Finding: NOT A GAP — TOOLS.md IS seeded.**

bootstrap.sh contains this loop:

```bash
for doc in SOUL.md HEARTBEAT.md TOOLS.md; do
  REPO_DOC="/app/docs/reference/agents/automation-supervisor/$doc"
  DEST="$SUPERVISOR_DIR/$doc"
  if [ -f "$REPO_DOC" ]; then
    if [ ! -f "$DEST" ]; then
      cp "$REPO_DOC" "$DEST"
    elif ! cmp -s "$REPO_DOC" "$DEST"; then
      cp "$REPO_DOC" "$DEST"
    fi
  fi
done
```

`TOOLS.md` is explicitly in the cmp-based seeding loop. The file `docs/reference/agents/automation-supervisor/TOOLS.md` exists in the repo. SOUL.md's reference to "Full operational guide: `TOOLS.md`" is valid.

**Result: No gap here.**

---

### Q5: Are Budget CFO and Business Researcher SOUL.md files (in 08-04) consistent with the Supervisor pattern for memory handling?

**Finding: CONSISTENT WITH SUPERVISOR, but same gap — memory_search availability assumed unconditionally.**

Both `docs/reference/agents/budget-cfo/SOUL.md` and `docs/reference/agents/business-researcher/SOUL.md` (created in 08-04 Task 1) contain:

```
Use `memory_search` for all memory queries — do NOT use QMD or external search:
```

This is consistent with the Supervisor's SOUL.md. Both files have the same session persistence model, memory protocol, escalation taxonomy, and Director communication pattern.

**However, two additional gaps exist for budget-cfo and business-researcher specifically:**

1. **No AGENTS.md seeding in add-director.sh.** The `add-director.sh` script does NOT seed AGENTS.md for new Directors. The automation-supervisor gets a copy via bootstrap.sh's explicit seed:
   ```bash
   if [ -f "/app/AGENTS.md" ] && [ ! -f "$SUPERVISOR_DIR/AGENTS.md" ]; then
     cp "/app/AGENTS.md" "$SUPERVISOR_DIR/AGENTS.md"
   ```
   But `add-director.sh` has no equivalent. Budget CFO and Business Researcher will not have AGENTS.md in their workspace unless it is manually copied.

2. **No memory/ directory seeding in add-director.sh.** The 08-04 verify step checks:
   ```bash
   # PASS: SOUL.md, HEARTBEAT.md, AGENTS.md, memory/ in each workspace
   ```
   But add-director.sh only creates the workspace and seeds SOUL.md and HEARTBEAT.md. The `memory/` directory and `memory/patterns/` are not created.

---

### Q6: Does 08-05 verification check memory_search availability?

**Finding: NO — the 10-check automated suite does not test memory_search.**

The 08-05 Task 1 verification suite runs 10 checks:

1. agents.list count = 4
2. workflow-worker NOT in agents.list
3. Director workspaces contain expected files
4. No QMD references in SOUL.md files
5. "check your session context" language in SOUL.md files
6. Credential files exist
7. COMPANY_MEMORY.md exists and extraPaths set
8. Claude Code CLI version check
9. Hook endpoint HTTP status codes (200/202)
10. n8n Error workflow active

**None of these tests verify whether `memory_search` actually works** — not structurally possible via a shell script (it requires asking an agent at runtime). However:

- Check 7 verifies COMPANY_MEMORY.md is in extraPaths — necessary precondition for memory_search to find it
- There is no check that `agents.defaults.memorySearch.enabled = true` and the provider is configured
- There is no runtime test (e.g., send a hook message asking the Supervisor to run a memory_search and verify it returns results)

**The MEMORY.md open question** (documented in 08-CONTEXT.md as Open Question #1 and in 08-04's checkpoint instructions) is not resolved by any automated check. 08-05 asks the user to manually answer it, but the live session today revealed the answer: `memory_search` (file-based) works but the built-in tool may not be available.

---

## Gap List

### GAP 1: memory_search framing in SOUL.md files does not account for unavailability

**What:** All three SOUL.md files instruct Directors to use `memory_search` unconditionally ("Use `memory_search` for all memory queries"). No fallback behavior is specified for when it returns nothing (unavailable embeddings, unindexed files, cold index).

**Where:**
- `docs/reference/agents/automation-supervisor/SOUL.md` — Memory Protocol section
- `docs/reference/agents/budget-cfo/SOUL.md` — Memory Protocol section (08-04 Task 1)
- `docs/reference/agents/business-researcher/SOUL.md` — Memory Protocol section (08-04 Task 1)

**Impact:** Directors follow the instruction, `memory_search` returns empty (silent failure), Directors proceed without relevant memory context. No error, no warning, just degraded behavior with no feedback loop.

**Fix:**
In each SOUL.md Memory Protocol section, change the rule from:
```
Rule: query first, read files only if query returns nothing useful
```
To:
```
Rule: query first. If results are empty, fall back to direct file reads:
  - `memory/patterns/` files for domain-specific patterns
  - `MEMORY.md` (your long-term state — OK to read in Director sessions)
  - `../COMPANY_MEMORY.md` (org context, path relative to your workspace)
```

Also document the fallback in HEARTBEAT.md session-start checklist.

**Priority:** P2 — degrades memory recall without failing. Memory patterns still accessible via direct file reads if Directors know to do it.

---

### GAP 2: AGENTS.md excludes Directors from MEMORY.md

**What:** The shared AGENTS.md (seeded to both main workspace and automation-supervisor workspace) explicitly says MEMORY.md should "ONLY load in main session (direct chats with your human)" and "DO NOT load in shared contexts." Hook-triggered Director sessions are not "direct chat" by this language, so Directors following AGENTS.md literally will never read MEMORY.md.

**Where:**
- `AGENTS.md` lines 28-38 (MEMORY.md section)
- affects: automation-supervisor, budget-cfo, business-researcher (once they get AGENTS.md)

**Impact:** Directors never load MEMORY.md, losing access to their most important long-term state file. MEMORY.md files accumulate without being read. The intent of "MEMORY.md is curated long-term memory" is defeated.

**Fix Option A (preferred):** Create a Director-specific AGENTS.md template at `docs/reference/agents/director-AGENTS.md` that replaces the MEMORY.md exclusion rule with:
```
## Memory in Director Sessions

Your hook sessions ARE your main session. Load and update MEMORY.md freely:
- Read MEMORY.md at the start of every session
- Write significant findings to MEMORY.md after major tasks
- Write raw logs to memory/YYYY-MM-DD.md
- Curate MEMORY.md weekly — distill daily notes into long-term state
```

Then in bootstrap.sh's supervisor workspace seeding block, replace the main AGENTS.md copy with the Director-specific version. Similarly, have add-director.sh seed the Director-specific AGENTS.md.

**Fix Option B (simpler):** Add a Director override section at the bottom of the current AGENTS.md that says "If you are a Director receiving work via hook sessions, your hook session IS your main session for MEMORY.md purposes." This requires only one file change and no new file.

**Priority:** P1 — Directors without MEMORY.md access cannot maintain curated long-term state. They can still write to `memory/patterns/` and `memory/YYYY-MM-DD.md`, but lose the curated MEMORY.md layer.

---

### GAP 3: add-director.sh does not seed AGENTS.md or memory/ directory

**What:** `scripts/add-director.sh` creates the Director workspace directory and seeds generic SOUL.md and HEARTBEAT.md. It does NOT seed AGENTS.md or create the `memory/` directory with `memory/patterns/` subdirectory.

**Where:**
- `scripts/add-director.sh` — workspace seeding block
- Affects: budget-cfo, business-researcher (and any future Directors)

**Impact (AGENTS.md):** Director has no workspace operating instructions. Without AGENTS.md, the Director will not follow the memory protocol, session-end procedures, or safety rules. Particularly important: AGENTS.md tells Directors where to write things.

**Impact (memory/):** The 08-04 and 08-05 verification steps check for `memory/` in workspace. If add-director.sh doesn't create it, these checks will fail for new Directors.

**Fix:**
In `scripts/add-director.sh`, after the SOUL.md/HEARTBEAT.md seeding block, add:

```bash
# Seed AGENTS.md (Director-specific version, seed-once)
DIRECTOR_AGENTS_SRC="/app/docs/reference/agents/director-AGENTS.md"
if [ -f "$DIRECTOR_AGENTS_SRC" ] && [ ! -f "$WORKSPACE_DIR/AGENTS.md" ]; then
  cp "$DIRECTOR_AGENTS_SRC" "$WORKSPACE_DIR/AGENTS.md"
  echo "[add-director] Seeded AGENTS.md"
fi

# Create memory directory structure
mkdir -p "$WORKSPACE_DIR/memory/patterns"
touch "$WORKSPACE_DIR/memory/.gitkeep"
echo "[add-director] Created memory/ directory structure"
```

If a Director-specific AGENTS.md doesn't exist yet, fall back to the main AGENTS.md (same as what bootstrap.sh does for the supervisor).

**Priority:** P1 — AGENTS.md absence means Directors operate without workspace operating instructions. memory/ absence breaks verification checks.

---

### GAP 4: MEMORY.md is never initialized for any Director

**What:** No plan, no script, and no seeding logic creates an initial MEMORY.md file for any Director (automation-supervisor, budget-cfo, business-researcher).

**Where:**
- `scripts/bootstrap.sh` — supervisor workspace seeding block (lines 128-190)
- `scripts/add-director.sh` — workspace seeding block
- Plans 08-01 through 08-04 have no MEMORY.md creation step

**Impact:** Directors start with no MEMORY.md. If they follow AGENTS.md and try to read it on session start, it doesn't exist. If they try to write to it, they need to create it from scratch with no template. Over time, without an initial structure, different Directors will create inconsistent MEMORY.md formats.

**Fix:**
Create `docs/reference/agents/director-MEMORY.md` as a starter template:
```markdown
# MEMORY.md — [Agent Name]

## Active Context
(What I'm currently working on)

## Learned Patterns
(What I know about my domain that isn't in memory/patterns/)

## Known Issues
(Recurring problems, gotchas, things to watch for)

## Director Relationships
(How other Directors work, who to contact for what)
```

Then in bootstrap.sh's supervisor seeding block, add:
```bash
if [ ! -f "$SUPERVISOR_DIR/MEMORY.md" ] && [ -f "/app/docs/reference/agents/director-MEMORY.md" ]; then
  cp "/app/docs/reference/agents/director-MEMORY.md" "$SUPERVISOR_DIR/MEMORY.md"
  sed -i 's/\[Agent Name\]/Automation Supervisor/' "$SUPERVISOR_DIR/MEMORY.md"
fi
```

In add-director.sh, add a similar MEMORY.md seed with the Director's name substituted in.

**Priority:** P2 — Directors can create MEMORY.md themselves, but starting without one means the first session has no continuity anchor. Combined with Gap 2 (AGENTS.md not telling Directors to load it), this means MEMORY.md never gets used unless Directors figure it out themselves.

---

### GAP 5: 08-05 verification does not verify MEMORY.md auto-load behavior

**What:** The 08-04 checkpoint explicitly instructs the human to test MEMORY.md auto-load in hook sessions (Step 8). The 08-05 automated verification suite (10 checks) does not include any check related to memory_search or MEMORY.md behavior.

**Where:**
- `.planning/phases/08-the-organization-director-workforce/08-05-PLAN.md` — Task 1, checks 1-10

**Impact:** The open question from 08-CONTEXT.md ("Does OpenClaw auto-load MEMORY.md for hook-triggered Director sessions?") is tested in 08-04 as a human checkpoint but has no follow-up verification in 08-05. If the human checkpoint finding was "MEMORY.md is NOT auto-loaded", this should drive a fix — but 08-05 has no mechanism to enforce that fix happened.

**Fix:**
Add check 11 to 08-05 Task 1:
```bash
echo "=== 11. MEMORY.MD EXISTS IN SUPERVISOR WORKSPACE ==="
sshpass ... "sudo docker exec $CONTAINER ls /data/openclaw-workspace/agents/automation-supervisor/MEMORY.md 2>&1"
# PASS: file exists
# FAIL: No such file — MEMORY.md was never seeded (Gap 4)
```

Also add a note in the 08-05 plan's Task 2 human verification:
```
After Test A (self-healing loop), check:
Did the Supervisor's response demonstrate access to prior memory context? (Evidence of MEMORY.md or memory_search working)
```

**Priority:** P3 — verification gap, not a functional gap. The behavior will be tested informally even without this check.

---

## SOUL.md Operational Content: Recommendation

**Question 3 conclusion: Keep operational content in SOUL.md. Do NOT move it to AGENTS.md.**

Rationale:
- SOUL.md is cmp-managed (repo overwrites on redeploy) — operational procedures stay accurate
- AGENTS.md is seed-once (agent can edit) — moving operational content there means agents could accidentally corrupt their own instructions
- The live Supervisor today wrote session lifecycle tables to SOUL.md — this is expected behavior and will be reset to repo version on next deploy. Useful content from the live SOUL.md should be **harvested** and committed to `docs/reference/agents/automation-supervisor/SOUL.md` in the repo so it survives the reset.

**Action needed:** Review the live Supervisor's SOUL.md before next deploy and commit any useful improvements to the repo version.

---

## Prioritized Fix List

| # | Gap | Priority | Files to Change | Effort |
|---|-----|----------|-----------------|--------|
| 2 | AGENTS.md excludes Directors from MEMORY.md | P1 | `AGENTS.md` or new `docs/reference/agents/director-AGENTS.md` | Medium |
| 3 | add-director.sh missing AGENTS.md + memory/ seeding | P1 | `scripts/add-director.sh` | Small |
| 1 | memory_search no-fallback in SOUL.md files | P2 | `docs/reference/agents/automation-supervisor/SOUL.md`, `docs/reference/agents/budget-cfo/SOUL.md`, `docs/reference/agents/business-researcher/SOUL.md` | Small |
| 4 | MEMORY.md never initialized for Directors | P2 | `docs/reference/agents/director-MEMORY.md` (new), `scripts/bootstrap.sh`, `scripts/add-director.sh` | Small |
| 5 | 08-05 verification missing MEMORY.md check | P3 | `.planning/phases/08-the-organization-director-workforce/08-05-PLAN.md` | Tiny |
| - | TOOLS.md seeding | NOT A GAP | N/A | N/A |

---

## Deviations from Plan

None — plan executed exactly as written.

---

## Self-Check: PASSED

Files verified:
- `.planning/quick/12-let-s-look-at-our-plan-and-prior-researc/12-SUMMARY.md` — created
- All 6 questions answered with evidence
- Fix list contains specific file paths
- Each gap has What/Where/Impact/Fix/Priority
