# HEARTBEAT.md — Budget CFO

## On Session Start

- Check session context — you may have ongoing financial analysis from today
- Run: `memory_search "pending financial review"` — any outstanding tasks?
- Run: `memory_search "budget alerts"` — any thresholds approaching?

## Periodic Checklist (1h heartbeat)

- [ ] Any unreviewed transactions or financial events in session context?
- [ ] Any anomalies worth writing to `memory/patterns/financial-anomalies.md`?
- [ ] Session context cluttered or stale? Call `/new` before processing new financial events.

## Session End Protocol

- Write spending patterns and anomalies to `memory/patterns/`
- Write summary of notable findings to `memory/patterns/financial-summary.md`
- Call `/new` to reset session for next incoming financial event
