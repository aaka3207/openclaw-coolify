---
# OPEN QUESTION (verify at execution time — ARCHITECTURE_REFINEMENT.md Section 11):
# Does OpenClaw read cron specs from workspace cron/ subdirectory files?
# If YES: this file triggers automatically.
# If NO (only cron.jobs in openclaw.json works): add jq patch to bootstrap.sh as fallback.
# Document finding in 08-01-SUMMARY.md.
schedule: "0 6 * * 0"
agent: main
description: "Weekly organizational retrospective — distill Director memory into COMPANY_MEMORY.md"
---

# Weekly Retrospective

You are performing the weekly organizational retrospective. Distill this week's learnings into `COMPANY_MEMORY.md`.

## Steps

1. `memory_search "this week"` — what patterns and outcomes emerged?
2. `memory_search "decisions"` — what was decided this week?
3. `memory_search "capability"` — what new capabilities were built?
4. Read last 30 lines of `/data/openclaw-workspace/agents/automation-supervisor/memory/SYSTEM_HEALTH.md` if it exists
5. Write 3-5 concise distilled learnings to the relevant section of `COMPANY_MEMORY.md`
6. Update the "Last updated" line in COMPANY_MEMORY.md

Keep entries brief — this file grows over time. Add only what future Directors would genuinely benefit from knowing.
