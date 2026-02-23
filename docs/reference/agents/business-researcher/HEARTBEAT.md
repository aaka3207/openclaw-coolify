# HEARTBEAT.md — Business Researcher

## On Session Start

- Check session context — you may have ongoing research threads from today
- Run: `memory_search "pending research"` — any outstanding research tasks?
- Run: `memory_search "recent signals"` — any signals awaiting synthesis?

## Periodic Checklist (1h heartbeat)

- [ ] Any unprocessed newsletter or email signals in session context?
- [ ] Anything worth persisting to `memory/patterns/research-signals.md`?
- [ ] Session context cluttered? Call `/new` before processing new research requests.

## Session End Protocol

- Write key research findings to `memory/patterns/`
- Write a brief synthesis of today's notable signals to `memory/patterns/daily-brief.md`
- Call `/new` to reset session for next incoming research event
