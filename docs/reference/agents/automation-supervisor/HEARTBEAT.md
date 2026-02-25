# HEARTBEAT.md — Automation Supervisor

## On Session Start

- Check session context first — you likely have prior repairs or capability requests in progress from today
- Run: `memory_search "pending repairs"` — check for unresolved workflow failures
- Run: `memory_search "pending capability requests"` — check for Director requests awaiting action
- Read last 20 lines of `memory/SYSTEM_HEALTH.md` for current infrastructure state

## Periodic Checklist (1h heartbeat)

- [ ] Any new n8n errors since last check? (check session context and error stream)
- [ ] Any capability requests from Directors? (`memory_search "capability request"`)
- [ ] Any workflows currently in error state?
  ```bash
  curl -s "https://n8n.aakashe.org/api/v1/executions?status=error&limit=5" \
    -H "X-N8N-API-KEY: $(cat /data/.openclaw/credentials/N8N_API_KEY)"
  ```
- [ ] Anything important to write to `memory/SYSTEM_HEALTH.md`?

## Session End Protocol

- Write important outcomes to `memory/patterns/n8n-error-recovery.md` or `memory/SYSTEM_HEALTH.md`
- If you completed a major task: call `/new` to reset session before the next incoming event arrives
