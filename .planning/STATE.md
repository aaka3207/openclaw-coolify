# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-14)

**Core value:** A secure, self-hosted AI agent that runs on my home server with proper secrets management and persistent memory — accessible only from my LAN.
**Current focus:** Entrypoint fix (gosu) → then Phase 5: n8n Integration

## Current Position

Phase: 4 of 5 (Memory System — partially working)
Plan: 04-01 complete, 04-02 blocked (hooks), catch-up workaround validated
Status: NOVA catch-up script works when cron daemon runs. Entrypoint fix needed for reliability.
Last activity: 2026-02-16 — Build fixes, NOVA catch-up validated, entrypoint analysis complete

Progress: [██████████████░░░░░░] 75% (3/5 phases complete, Phase 4 partial, Phase 5 planned)

## Performance Metrics

**Velocity:**
- Total plans completed: 6
- Average duration: ~30 min
- Total execution time: ~3 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-lan-deployment | 2 | ~1 hr | ~30 min |
| 02-matrix-integration | 2 | ~1 hr | ~30 min |
| 03-secrets-management | 1 (quick) | ~20 min | ~20 min |
| 04-memory-system | 1 | ~40 min | ~40 min |

*Updated after each plan completion*

## Accumulated Context

### Decisions

Decisions are logged in PROJECT.md Key Decisions table.
Recent decisions affecting current work:

- Security hardening: All audit findings fixed before deployment (completed)
- LAN-only deployment: No public exposure, reduces attack surface (completed)
- Fork workflow: aaka3207/openclaw-coolify origin, essamamdani/openclaw-coolify upstream (active)
- Remove deployment tools for LAN-only setup: Vercel and Cloudflare removed (01-01, completed)
- Bare-minimum Dockerfile: Heavy deps moved to post-deploy script (01-02, completed)
- Direct port mapping (18789:18789) bypasses Traefik (01-02, completed)
- allowInsecureAuth for HTTP-only gateway access (01-02, completed)
- Pin openclaw@2026.2.13: version 2026.2.14 has scope bug (#16820) causing operator.read failures (01-02, completed)
- Loopback onboarding pattern: switch bind→loopback, onboard, switch back→lan (01-02, completed)
- Post-deploy optional deps deferred to Phase 2 (user decision)
- Use stock matrix plugin (global:matrix v2026.2.14) — user-installed extension has import path incompatibility with 2026.2.13 core (02, completed)
- Password auth with env var interpolation for Matrix config — OpenClaw handles token management (02, completed)
- E2EE enabled for Matrix — required because Element encrypts DMs by default (02, completed)
- Pairing-based access control for Matrix DMs (dm.policy: "pairing") (02, completed)
- BWS secrets as quick task: fetch-bws-secrets.sh + bootstrap.sh source, no cron (03, completed)
- NOVA Memory with standalone postgres-memory (not Synapse PG): safer isolation (04-01, completed)
- hooks.token required when hooks.enabled=true: pre-generate in config template (04-01, completed)
- nova-relationships is a separate repo cloned to /data/nova-relationships/ (04-01, completed)
- `message:received` hook event NOT IMPLEMENTED in OpenClaw 2026.2.13 — hooks register but never fire (04, BLOCKER)

### Lessons Learned (Phase 1)

- Coolify Restart vs Redeploy: Restart reuses image (seconds), Redeploy rebuilds (10-15+ min). Always Restart for config changes.
- Device auto-approval only works for loopback (127.0.0.1), NOT Docker network IPs. Must temporarily bind=loopback for CLI onboarding.
- openclaw.json caching: bootstrap.sh only generates if file missing. Must manually delete cached config to pick up changes.
- chown -R causes HDD stalls — use non-recursive.
- Docker CLI guard needed when deps are post-deploy.
- OpenClaw 2026.2.14 has scope bug (#16820) — pin to 2026.2.13.

### Lessons Learned (Phase 2)

- Stock matrix plugin (global:matrix) works even though it's v2026.2.14 — the scope bug only affects core, not plugins.
- User-installed extensions from `openclaw plugins install` may have import path incompatibilities with pinned core versions. Use stock plugins when available.
- Matrix E2EE must be enabled (`channels.matrix.encryption: true`) because Element encrypts DMs by default.
- OpenClaw supports `${VAR_NAME}` interpolation in openclaw.json — use for credentials instead of hardcoding.
- Remove `/data/.openclaw/extensions/<plugin>` to avoid duplicate plugin warnings when stock plugin exists.
- Synapse was healthy all along despite Coolify showing "degraded:unhealthy" — always verify with actual health checks.
- `sudo` required for docker commands on the server (user not in docker group).

### Lessons Learned (Phase 3)

- BWS secrets injection works via `source /data/.openclaw/secrets.env` in bootstrap.sh. Env vars are only visible to the gateway process tree, NOT to `docker exec` sessions.
- No cron needed for BWS refresh — secrets refresh on every container restart.

### Lessons Learned (Phase 4)

- OpenClaw 2026.2.13 does NOT implement `message:received` hook event — it's listed as "planned future event" in docs. Hooks register (OpenClaw doesn't validate event names) but never fire.
- hooks.enabled=true REQUIRES hooks.token — gateway crashes without it. Must pre-generate token.
- NOVA Memory ecosystem is split: `nova-memory` (hooks, schema) + `nova-relationships` (entity-resolver). The semantic-recall hook has hardcoded `../../../nova-relationships/` import path.
- Entity-resolver deps (pg package) must be npm installed in `lib/entity-resolver/` subdirectory — no root package.json.
- Coolify restart via API can fail with container name conflict. Use `docker restart` directly on server or deploy API.
- `docker exec` cannot see env vars set via `source` in bootstrap.sh — they're only in the gateway process tree.
- OpenClaw has native cron system (`cron.enabled: true` in openclaw.json) separate from system cron.

### Pending Todos

- ~~Run post-deploy script for optional deps~~ (DONE: deps baked into Dockerfile via quick-1)
- ~~Resolve `message:received` hook event blocker~~ (WORKAROUND: catch-up cron works, hooks still blocked)
- **Replace `su` with `gosu` entrypoint** — root cause of PATH/cron/crash issues (see analysis below)
- **Upgrade OpenClaw to 2026.2.15** — scope bug #16820 fixed, safe for our LAN setup
- **Fix stale SOUL.md on volume** — bootstrap skips copy if exists, volume has pre-hardening version
- Fix duplicate matrix plugin warning (spams every 30s)
- Start cron daemon reliably after deploys (blocked on entrypoint fix)

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 1 | Update SOUL.md, BOOTSTRAP.md, web-utils skill, and move install-browser-deps into Dockerfile | 2026-02-16 | `f4c0740` | [1-update-soul-md-bootstrap-md-web-utils-sk](./quick/1-update-soul-md-bootstrap-md-web-utils-sk/) |
| 2 | Move heavy installs to cached stage, remove @hyperbrowser/agent, fix sandbox crash loop | 2026-02-16 | `c39a0ad` | N/A (direct commits) |

### Blockers/Concerns

**Phase 1:** COMPLETE
**Phase 2:** COMPLETE
**Phase 3:** COMPLETE

**Phase 4 (BLOCKED):**
- `message:received` hook event is "planned future event" — NOT IMPLEMENTED in 2026.2.13
- 2026.2.14 may support it but has scope bug (#16820) — catch-22
- semantic-recall shows `✗ missing` in hooks list (6/7 ready) — likely unresolved dep
- Entity count is 0 — no memories being extracted (because hooks never fire)
- All infrastructure is ready: PostgreSQL + pgvector (66 tables), 3 hooks installed, nova-relationships cloned, ANTHROPIC_API_KEY in BWS

## Session Continuity

Last session: 2026-02-16 — Quick task 1: SOUL.md/Dockerfile updates for LAN-only + self-contained image
Stopped at: Completed quick-1 plan (SOUL.md, BOOTSTRAP.md, SKILL.md, Dockerfile updates)
Resume at: Decide path forward for hook event support (upgrade, wait, or workaround)
Resume file: None

### Key Details
- Container: `openclaw-ukwkggw4o8go0wgg804oc4oo-185052814424`
- App UUID: `ukwkggw4o8go0wgg804oc4oo`
- Server LAN IP: 192.168.1.100
- Gateway URL: http://192.168.1.100:18789
- Gateway token: `b934d627a0dcc6a08c4e7a156067f865e54dba925beb0047`
- OpenClaw version: 2026.2.13 (pinned)
- Matrix homeserver: https://matrix.aakashe.org
- Bot Matrix ID: @bot:matrix.aakashe.org
- Bot device ID: LAXYMRZYNG

### Key Commits (Quick Tasks)
- `93a19ec` — SOUL.md/BOOTSTRAP.md/SKILL.md LAN-only updates
- `3b2b0d5` — Bake browser/tool deps into Dockerfile
- `fa809a8` — Verify ARM64 Go checksum, update CLAUDE.md

### Key Commits (Phase 3-4)
- `2459ee4` — BWS secrets auto-injection in bootstrap.sh
- `25dd80c` — postgres-memory service with pgvector
- `410874b` — NOVA Memory installation in bootstrap.sh
- `e4a8eb6` — Fix hooks.token gateway crash
- `ea0e61e` — Clone nova-relationships repo
- `ff8a7ee` — Install entity-resolver npm deps
- `270b118` — Enable OpenClaw built-in cron engine

---
*State initialized: 2026-02-14*
*Last updated: 2026-02-16 (quick-1 complete)*
