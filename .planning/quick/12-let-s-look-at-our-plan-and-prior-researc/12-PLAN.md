---
phase: quick-12
plan: "01"
type: execute
wave: 1
depends_on: []
files_modified: []
autonomous: true

must_haves:
  truths:
    - "A concrete gap list exists documenting every memory-related issue in plans 08-02 through 08-05"
    - "Each gap has a specific fix recommendation (file path + what to change)"
    - "The SOUL.md operational-vs-identity content split issue is documented with recommendation"
  artifacts:
    - path: ".planning/quick/12-let-s-look-at-our-plan-and-prior-researc/12-SUMMARY.md"
      provides: "Gap analysis with actionable fix list for Phase 8 memory handling"
  key_links: []
---

<objective>
Audit Phase 8 plans (08-02 through 08-05) and the Automation Supervisor's repo SOUL.md to identify gaps in how Director memory is handled. Produce a concrete, actionable gap list with specific fix recommendations.

Purpose: We discovered today that the live Supervisor has no MEMORY.md, no daily notes, and its SOUL.md references `memory_search` as a built-in tool that may not actually be available. The plans may have gaps around memory seeding, MEMORY.md initialization, and SOUL.md content placement.
Output: Gap analysis summary with prioritized fix list.
</objective>

<execution_context>
@./.claude/get-shit-done/workflows/execute-plan.md
@./.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@.planning/STATE.md
@.planning/phases/08-the-organization-director-workforce/08-02-PLAN.md
@.planning/phases/08-the-organization-director-workforce/08-03-PLAN.md
@.planning/phases/08-the-organization-director-workforce/08-04-PLAN.md
@.planning/phases/08-the-organization-director-workforce/08-05-PLAN.md
@.planning/phases/08-the-organization-director-workforce/08-CONTEXT.md
@.planning/phases/08-the-organization-director-workforce/08-01-SUMMARY.md
@docs/reference/agents/automation-supervisor/SOUL.md
@scripts/bootstrap.sh
</context>

<tasks>

<task type="auto">
  <name>Task 1: Audit Phase 8 plans and SOUL.md for memory handling gaps</name>
  <files></files>
  <action>
Read and analyze these files (already loaded in context), then produce a structured gap analysis covering these specific questions:

**Question 1: Do plans 08-02 through 08-05 reference `memory_search` as a tool the Supervisor can call?**
- Check each plan's task actions, verification steps, and must_haves
- Check the SOUL.md files referenced by each plan (repo versions at docs/reference/agents/)
- Note: `memory_search` IS a real built-in tool (configured in openclaw.json via `agents.defaults.memorySearch`), but it's unclear if it's available in hook-triggered sessions. Open Question #1 from 08-CONTEXT.md.

**Question 2: Do any plans seed MEMORY.md or daily notes (memory/2026-MM-DD.md) for Directors?**
- Check bootstrap.sh seeding logic for the Supervisor workspace
- Check add-director.sh for what it seeds
- Check if any plan includes creating initial MEMORY.md content
- Note: memorySearch indexes workspace `memory/` directory, so files there ARE searchable. But MEMORY.md (the persistent cross-session state file) is distinct from memory/patterns/*.md files.

**Question 3: Does the Supervisor's SOUL.md have operational content that belongs in AGENTS.md?**
- The live Supervisor's SOUL.md has accumulated session lifecycle tables, escalation taxonomy, self-healing loop protocol
- Per OpenClaw docs: SOUL.md = identity/personality, AGENTS.md = operational instructions
- The repo SOUL.md (docs/reference/agents/automation-supervisor/SOUL.md) already has this content baked in
- Is this a problem? Or is it acceptable given that SOUL.md is cmp-based (repo overwrites) while AGENTS.md is seed-once?

**Question 4: Does bootstrap.sh seed TOOLS.md for the Supervisor?**
- Check if TOOLS.md is in the cmp-based update loop alongside SOUL.md and HEARTBEAT.md
- The repo has docs/reference/agents/automation-supervisor/TOOLS.md
- SOUL.md references "Full operational guide: TOOLS.md" — if TOOLS.md isn't seeded, this reference is broken

**Question 5: Are Budget CFO and Business Researcher SOUL.md files (in 08-04) consistent with the Supervisor pattern for memory handling?**
- Do they reference memory_search?
- Do they have the same memory protocol section?
- Do they seed any initial memory/ content?

**Question 6: Does 08-05 verification check memory_search availability?**
- The automated verification suite in 08-05 Task 1 has 10 checks — does any test memory_search?
- Should it?

For each gap found, document:
- **What**: the specific gap
- **Where**: file path and plan number
- **Impact**: what breaks if not fixed
- **Fix**: specific change needed (file path + what to add/change)
- **Priority**: P1 (blocks functionality), P2 (degrades experience), P3 (nice to have)
  </action>
  <verify>
The output summary file exists and contains:
- At least 3 gaps identified (or explicit "no gaps found" with evidence)
- Each gap has What/Where/Impact/Fix/Priority
- Specific file paths for all fixes
- Clear recommendation on SOUL.md operational content question
  </verify>
  <done>
- Gap analysis complete with structured output
- Every memory-related concern from the user's additional context is addressed
- Fix recommendations are specific enough to implement without interpretation
  </done>
</task>

</tasks>

<verification>
- Summary file exists at .planning/quick/12-let-s-look-at-our-plan-and-prior-researc/12-SUMMARY.md
- All 6 questions answered with evidence
- Fix list is actionable (specific files, specific changes)
</verification>

<success_criteria>
- Concrete gap list produced covering memory_search availability, MEMORY.md seeding, SOUL.md content split, TOOLS.md seeding, Director memory consistency, and verification coverage
- Each gap has a prioritized fix recommendation
- Analysis distinguishes between "gap in plans" vs "gap in implementation" vs "not actually a gap"
</success_criteria>

<output>
After completion, create `.planning/quick/12-let-s-look-at-our-plan-and-prior-researc/12-SUMMARY.md`
</output>
