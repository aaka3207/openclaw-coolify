---
# NOTE: Phase 9 created this file using the same format as weekly-retrospective.md.
# If weekly-retrospective.md auto-fires via workspace cron/ detection, this will too.
# If not (cron requires openclaw.json config), add a jq patch to bootstrap.sh for this schedule.
schedule: "0 6 * * 0"
agent: main
description: "Weekly memory compaction — distill past week's daily logs into memory/digests/"
---

# Weekly Memory Compaction

You are performing the weekly memory compaction. Distill this week's operational logs into a digest.

## Steps

1. List files in `memory/` matching `YYYY-MM-DD.md` from the past 7 days
2. Read each daily log from the past week
3. Identify: key decisions made, problems solved, patterns learned, user preferences noted
4. Write a concise digest to `memory/digests/YYYY-WXX.md` (create `memory/digests/` if needed):
   - Use ISO week format: e.g., `memory/digests/2026-W10.md`
   - 3-7 bullet points per category: Decisions, Problems Solved, Patterns, Preferences
   - Keep each bullet under 2 lines — this file grows over time
5. Do NOT delete or modify the daily log files — they are the permanent audit trail
6. Review `leads/` for files older than 30 days and delete them (transaction tier cleanup)

Keep entries brief. Future-you benefits from distilled signal, not raw noise.
