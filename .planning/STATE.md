# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-14)

**Core value:** A secure, self-hosted AI agent that runs on my home server with proper secrets management and persistent memory — accessible only from my LAN.
**Current focus:** Phase 6: Agent Orchestration -- IN PROGRESS

## Current Position

Phase: 6 of 6 (Agent Orchestration -- IN PROGRESS)
Plan: 06-01 created, 06-02 created, 06-03 created (not yet executed)
Status: Phase 6 plans written and revised. Pending execution.
Last activity: 2026-02-22 - Quick task 8: Save sub-agent mode=remote patch + isSecureWebSocketUrl findings

Progress: [████████████████████] 83% (5/6 phases complete, 6th in progress)

## Performance Metrics

**Velocity:**
- Total plans completed: 7
- Average duration: ~28 min
- Total execution time: ~3.1 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-lan-deployment | 2 | ~1 hr | ~30 min |
| 02-matrix-integration | 2 | ~1 hr | ~30 min |
| 03-secrets-management | 1 (quick) | ~20 min | ~20 min |
| 04-memory-system | 1 | ~40 min | ~40 min |
| 05-n8n-integration | 1 | ~8 min | ~8 min |

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
- Pin openclaw@2026.2.13: version 2026.2.14 has scope bug (#16820) causing operator.read failures (01-02, completed). **Upgraded to 2026.2.15** — scope bug fixed.
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
- HOOKS_TOKEN separate from gateway TOKEN for independent rotation via BWS (05-01, completed)
- N8N_API_KEY follows credential isolation pattern: file + unset (05-01, completed)
- jq patch block enables hooks on existing configs without config deletion (05-01, completed)

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
- ~~**Replace `su` with `gosu` entrypoint**~~ (DONE: entrypoint.sh runs as root, drops to openclaw via gosu)
- ~~**Upgrade OpenClaw to 2026.2.15**~~ (DONE: scope bug #16820 fixed)
- ~~**Fix stale SOUL.md on volume**~~ (DONE: bootstrap.sh now uses cmp to update when repo version differs)
- ~~Fix duplicate matrix plugin warning~~ (DONE: entrypoint.sh removes stale /data/.openclaw/extensions/matrix)
- ~~Start cron daemon reliably after deploys~~ (DONE: entrypoint.sh runs cron as root before dropping privileges)
- Matrix plugin missing `@vector-im/matrix-bot-sdk` — upstream 2026.2.15 issue, not our bug
- Remove debug logging (ERR trap, extra echo statements) from bootstrap.sh once fully stable
- Verify NOVA memory catch-up cron is running under gosu/openclaw user
- Install mcpporter skill: `npx playbooks add skill openclaw/skills --skill mcporter`
- Upgrade OpenClaw to 2026.2.19 (security fix: path containment for plugins/hooks)
- ~~Execute Phase 6 plan 06-01~~ (DONE: memorySearch + subagents patches committed, deploy in progress)
- Execute Phase 6 plans (06-02, 06-03) — 06-02 now unblocked
- ~~**Sub-agent temp patch**~~ (DONE: committed in bootstrap.sh — gateway.mode=remote + remote.token + --allow-unconfigured). Remove when CHANGELOG #22582 ships (watch next release after 2026.2.21-2).
- Push committed changes: SOUL.md (ACIP), BOOTSTRAP.md (persistence rules)

### Quick Tasks Completed

| # | Description | Date | Commit | Directory |
|---|-------------|------|--------|-----------|
| 1 | Update SOUL.md, BOOTSTRAP.md, web-utils skill, and move install-browser-deps into Dockerfile | 2026-02-16 | `f4c0740` | [1-update-soul-md-bootstrap-md-web-utils-sk](./quick/1-update-soul-md-bootstrap-md-web-utils-sk/) |
| 2 | Move heavy installs to cached stage, remove @hyperbrowser/agent, fix sandbox crash loop | 2026-02-16 | `c39a0ad` | N/A (direct commits) |
| 3 | Gosu entrypoint + OpenClaw 2026.2.15 upgrade + NOVA permission/config fixes | 2026-02-16 | `b730f37` | N/A (direct commits) |
| 4 | Research Claude Max vs Anthropic API compatibility for OpenClaw | 2026-02-21 | `a167a44` | [4-i-want-to-research-using-the-anthropic-c](./quick/4-i-want-to-research-using-the-anthropic-c/) |
| 5 | Research QMD memory system: capabilities, live deployment status, comparison vs NOVA + built-in | 2026-02-21 | `512600f` | [5-research-how-to-make-openclaw-qmd-memory](./quick/5-research-how-to-make-openclaw-qmd-memory/) |
| 6 | Execute Phase 6 Plan 06-01: memorySearch + subagents jq patches, NOVA cron disabled | 2026-02-22 | `83491f3` | [6-what-now](./quick/6-what-now/) |
| 7 | save to memory: sub-agent spawning fix, useAccessGroups, config lock pattern | 2026-02-22 | `2faae71` | [7-save-to-memory](./quick/7-save-to-memory/) |
| 8 | Save sub-agent mode=remote patch, isSecureWebSocketUrl findings, upstream fix #22582 tracking | 2026-02-22 | (this commit) | [8-make-sure-this-whole-implementation-is-s](./quick/8-make-sure-this-whole-implementation-is-s/) |

### Blockers/Concerns

**Phase 1:** COMPLETE
**Phase 2:** COMPLETE
**Phase 3:** COMPLETE

**Phase 6 (Agent Orchestration — PLANNED):**
- Plans written: 06-01 (task router), 06-02 (sub-agent memory isolation), 06-03 (NOVA filter + session types)
- Architecture research done: claudedocs/openclaw-agent-memory-architecture.md
- Not yet executed

**Phase 4 (PARTIAL — infrastructure deployed, hooks still blocked):**
- `message:received` hook event still NOT IMPLEMENTED in 2026.2.15 — workaround via catch-up cron
- Now running OpenClaw 2026.2.15 (scope bug #16820 fixed)
- Matrix plugin has missing dep `@vector-im/matrix-bot-sdk` — upstream issue in 2026.2.15
- NOVA Memory infrastructure deployed: PostgreSQL + pgvector (66 tables), 3 hooks installed, postgres.json generated
- Catch-up cron workaround active (every 5 min) for memory extraction
- If persistent permission issues arise, fallback plan: revert to running as root

### Lessons Learned (Gosu Migration)

- Switching from root to non-root user requires chowning ALL persistent volume directories — files created by previous root-based runs are owned by root.
- `gosu` preserves ENV (no PAM reset), solving the PATH loss from `su openclaw`.
- `set -eE` + ERR trap is invaluable for debugging silent bash failures — shows exact line number.
- NOVA memory v2.1 changed to require `~/.openclaw/postgres.json` config file instead of PGHOST/PGPORT env vars.
- Coolify generates `command: ["bash", "/app/scripts/bootstrap.sh"]` which becomes args to ENTRYPOINT — entrypoint.sh ignores these args (uses exec gosu).
- `crontab -` as non-root user may trigger ERR trap but is non-fatal inside conditional blocks.
- Recursive chown of large dirs on HDD causes stalls — use non-recursive for top-level, recursive only for small dirs.

## Session Continuity

Last session: 2026-02-22 — Debugged sub-agent isSecureWebSocketUrl failure. Root cause: gateway.mode must be "remote" to activate remote.url lookup in sessions_spawn. Tailscale doesn't help (non-loopback IPs fail check). Applied TEMP patch (mode=remote + remote.token + --allow-unconfigured) and committed to git. Upstream fix tracked: CHANGELOG #22582 (not yet shipped as of 2026.2.21-2).
Stopped at: bootstrap.sh committed. Sub-agents reaching gateway in live container (device pairing partially resolved).
Resume at: Execute 06-02-PLAN.md (AGENTS.md + memory/patterns/).
Resume file: None

### Key Details
- Container: `openclaw-ukwkggw4o8go0wgg804oc4oo-185052814424`
- App UUID: `ukwkggw4o8go0wgg804oc4oo`
- Server LAN IP: 192.168.1.100
- Gateway URL: http://192.168.1.100:18789
- Gateway token: `b934d627a0dcc6a08c4e7a156067f865e54dba925beb0047`
- OpenClaw version: 2026.2.17 (upgraded from 2026.2.15). 2026.2.19 available — security fix (path containment), upgrade recommended.
- Matrix homeserver: https://matrix.aakashe.org
- Bot Matrix ID: @bot:matrix.aakashe.org
- Bot device ID: LAXYMRZYNG
- SSH: ameer@192.168.1.100 (password auth, `-o PreferredAuthentications=password`)

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

### Key Commits (Gosu Entrypoint Migration)
- `5a19b70` — Initial gosu entrypoint + OpenClaw 2026.2.15 upgrade
- `64e7a64` — Debug: add error tracing to entrypoint and bootstrap
- `222d8aa` — Fix: chown .openclaw dir so openclaw user can read config
- `b553d98` — Fix: generate postgres.json for nova-memory v2.1, fix nova dir ownership
- `b730f37` — Fix: chown workspace/scripts dirs for nova agent-install chmod

### Key Commits (Phase 5)
- `fa36650` — Enable hooks endpoint, BWS token support, N8N_API_KEY credential isolation
- `a85e29d` — n8n-manager SKILL.md and n8n-api.sh base wrapper
- `a8679b2` — Action scripts: list, create, execute, activate workflows

---
*State initialized: 2026-02-14*
*Last updated: 2026-02-20 (Phase 6 plans created, ACIP installed)*
