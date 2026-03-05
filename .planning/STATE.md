# Project State

## Project Reference

See: .planning/PROJECT.md (updated 2026-02-14)

**Core value:** A secure, self-hosted AI agent that runs on my home server with proper secrets management and persistent memory — accessible only from my LAN (and via Tailscale for off-LAN HTTPS access).
**Current focus:** Steady-state operations. No active phase. Future work via quick tasks.

## Current Position

Phase: 8 COMPLETE — all phases done
Plan: All plans complete. Post-Phase 8 simplifications applied.
Status: 3 Directors live (main, budget-cfo, business-researcher). automation-supervisor retired. Main agent owns n8n directly. Lead screening workflow running autonomously every 30 min.
Last activity: 2026-03-05 - Quick task 14: updated planning docs to reflect post-Phase-8 reality.

Progress: [████████████████████] ALL PHASES COMPLETE — Steady-State Operations

## Performance Metrics

**Velocity:**
- Total plans completed: 15+ (8 phases × 2+ plans each, plus quick tasks)
- Average duration: ~28 min
- Total execution time: ~5 hours

**By Phase:**

| Phase | Plans | Total | Avg/Plan |
|-------|-------|-------|----------|
| 01-lan-deployment | 2 | ~1 hr | ~30 min |
| 02-matrix-integration | 2 | ~1 hr | ~30 min |
| 03-secrets-management | 1 (quick) | ~20 min | ~20 min |
| 04-memory-system | 1 | ~40 min | ~40 min |
| 05-n8n-integration | 1 | ~8 min | ~8 min |
| Phase 07-tailscale-integration P01 | 178 | 3 tasks | 4 files |
| Phase 08-director-workforce P01 | ~25 min | 4 tasks | 9 files |

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
- [Phase 07-tailscale-integration]: Tailscale userspace networking (no NET_ADMIN/tun device): binary copy from official image, state persisted to /data/tailscale/
- [Phase 07-tailscale-integration]: gateway.bind=loopback + tailscale.mode=serve replaces TEMP mode=remote patches (CHANGELOG #22582 workaround removed)
- [Phase 08-01]: automation-supervisor is the only Director hardcoded in bootstrap.sh; all others use add-director.sh lifecycle script
- [Phase 08-01]: ANTHROPIC_API_KEY NOT in BWS loop — Claude Code uses OAuth subscription auth (claude auth login), not API key
- [Phase 08-01]: COMPANY_MEMORY.md indexed via agents.defaults.memorySearch.extraPaths — single patch makes it searchable by all agents; QMD not used
- [Phase 08-01]: File-based cron (workspace/cron/) behavior unverified — OPEN QUESTION at deploy time
- [Post-Phase 8 - 2026-03]: automation-supervisor retired — main agent owns n8n directly via n8n-manager skill (commit 7406d8a)
- [Post-Phase 8 - 2026-03]: All workspace file seeding removed from bootstrap.sh — agent owns its workspace entirely (commit 3fb579c)
- [Post-Phase 8 - 2026-03]: gateway tool denied globally for all agents (commit ee32594)
- [Post-Phase 8 - 2026-03]: analyst Directors (budget-cfo, business-researcher) restricted: deny exec/write/edit/apply_patch — read and communicate only (commit ee32594)
- [Post-Phase 8 - 2026-03]: OpenClaw upgraded to 2026.3.2 (commit 903d625)
- [Post-Phase 8 - 2026-03]: container_name: openclaw added to docker-compose.yaml for stable naming

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

### Lessons Learned (Post-Phase 8)

- automation-supervisor separation proved unnecessary overhead at current scale — main agent handles n8n directly with fewer failure modes.
- Workspace file seeding creates "bootstrap overwrites agent changes" conflicts — agent-owned workspace (seed-once) is cleaner.
- Analyst Director security restrictions (no exec/write) are important — prevents accidental or injected code execution.
- container_name: openclaw is essential for stable `docker logs openclaw` and script references — container name changes every Coolify deploy without it.

### Pending Todos

- ~~Run post-deploy script for optional deps~~ (DONE: deps baked into Dockerfile via quick-1)
- ~~Resolve `message:received` hook event blocker~~ (WORKAROUND: catch-up cron works, hooks still blocked)
- ~~**Replace `su` with `gosu` entrypoint**~~ (DONE: entrypoint.sh runs as root, drops to openclaw via gosu)
- ~~**Upgrade OpenClaw to 2026.2.15**~~ (DONE: scope bug #16820 fixed)
- ~~**Fix stale SOUL.md on volume**~~ (DONE: bootstrap.sh now uses cmp to update when repo version differs)
- ~~Fix duplicate matrix plugin warning~~ (DONE: entrypoint.sh removes stale /data/.openclaw/extensions/matrix)
- ~~Start cron daemon reliably after deploys~~ (DONE: entrypoint.sh runs cron as root before dropping privileges)
- ~~Execute Phase 6 plan 06-01~~ (DONE: memorySearch + subagents patches committed, deploy in progress)
- ~~Execute Phase 6 plans (06-02, 06-03)~~ (DONE)
- ~~**Sub-agent temp patch**~~ (DONE: committed in bootstrap.sh — gateway.mode=remote + remote.token + --allow-unconfigured). Remove when CHANGELOG #22582 ships (watch next release after 2026.2.21-2).
- ~~Push committed changes: SOUL.md (ACIP), BOOTSTRAP.md (persistence rules)~~ (DONE)
- Remove debug logging (ERR trap, extra echo statements) from bootstrap.sh once fully stable
- Install mcpporter skill: `npx playbooks add skill openclaw/skills --skill mcporter`
- n8n Global Error Handler: verify it routes errors correctly to main agent (current: active but routing TBD)
- WhatsApp health monitor: restarting every 15-30 min (hit 3/hr limit) — investigate if WhatsApp is needed or disable

### Agent Workspace Audit (2026-03-05)

**Audit scope**: Files modified in last 7 days in `/var/lib/docker/volumes/ukwkggw4o8go0wgg804oc4oo_openclaw-data/_data/openclaw-workspace/`

**Active agents**: main, budget-cfo, business-researcher (automation-supervisor retired)

**Files the agent created/modified autonomously this week:**

| File/Directory | Activity |
|----------------|----------|
| `agents/LeadScreeningAgent.md` | Agent created its own sub-agent spec document for lead screening |
| `leads/today.jsonl` | Live output file — lead screening results, updated every 30 min |
| `leads/archive/2026-03-04.jsonl` | Previous day's leads archived automatically |
| `monitor.log` (795 KB) | n8n workflow monitoring log, continuously appended |
| `recovery.log` (567 KB) | Recovery/retry log, continuously appended |
| `skills/mcp-myfitnesspal/SKILL.md` | Agent built a new MCP skill for MyFitnessPal |
| `skills/metamcp-tools/SKILL.md` | Agent built a MetaMCP tools skill |
| `state/metamcp/tools-*.json` | MetaMCP tool state tracking files (diff, latest, prev, tmp) |
| `state/openclaw_release.json` | OpenClaw release tracking (checked v2026.3.2 = latest) |

**Key finding**: The main agent is running a live **lead screening workflow** — it scans newsletters via an Email Hub n8n workflow every 30 minutes and writes qualified leads (companies/contacts matching Akashe Strategies ICP) to `leads/today.jsonl`. It created `agents/LeadScreeningAgent.md` as its own operational document. The agent also built new skills autonomously: mcp-myfitnesspal and metamcp-tools.

**Container logs (last 30 min)**: Lead scanning running on 30-min cadence. Recent scans at 17:41, 18:11, 18:41, 19:11 UTC found no new leads (batch contents: concert alerts, grocery deals, loan offers, LinkedIn job alerts). WhatsApp health monitor restarting frequently (hitting 3/hr rate limit) — investigate.

**OpenClaw version on server**: v2026.3.2 (latest as of check on 2026-03-05)

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
| 8 | Save sub-agent mode=remote patch, isSecureWebSocketUrl findings, upstream fix #22582 tracking | 2026-02-22 | `a108b7d` | [8-make-sure-this-whole-implementation-is-s](./quick/8-make-sure-this-whole-implementation-is-s/) |
| 9 | Workspace symlink fix + sub-agent announce-back (dangerouslyDisableDeviceAuth TEMP) + QMD path | 2026-02-22 | `c35dbe2` | [9-fix-workspace-symlink-sub-agent-announce](./quick/9-fix-workspace-symlink-sub-agent-announce/) |
| 10 | Audit: file path fixes from quick-9 + 06-02-PLAN.md vs bootstrap.sh reality — gap analysis | 2026-02-22 | `d561835` | [10-did-we-follow-the-plan-on-file-path-fixe](./quick/10-did-we-follow-the-plan-on-file-path-fixe/) |
| 11 | Verify Phase 8 plans against ARCHITECTURE_PLAN.md + ARCHITECTURE_REFINEMENT.md | 2026-02-22 | `9796fca` | [11-verify-against-the-two-primary-architect](./quick/11-verify-against-the-two-primary-architect/) |
| 12 | Phase 8 memory handling gap analysis — Director memory setup, memory_search availability, AGENTS.md gaps | 2026-02-23 | `a64afa8` | [12-let-s-look-at-our-plan-and-prior-researc](./quick/12-let-s-look-at-our-plan-and-prior-researc/) |
| 13 | (undocumented — session between 12 and 14) | - | - | - |
| 14 | Update all planning docs to reflect post-Phase-8 reality + agent workspace audit | 2026-03-05 | TBD | [14-update-the-overall-plan-to-follow-that-l](./quick/14-update-the-overall-plan-to-follow-that-l/) |

### Blockers/Concerns

**All phases: COMPLETE**

**Active operational concerns:**
- WhatsApp health monitor hitting 3/hr restart rate limit — investigate if WhatsApp is needed or disable (not part of any planned phase, likely leftover from early exploration)
- n8n Global Error Handler: active but routing to TBD destination — verify it reaches main agent correctly

## Session Continuity

Last session: 2026-03-05 — Quick task 14: Updated ROADMAP.md, STATE.md, ARCHITECTURE_PLAN.md, ARCHITECTURE_REFINEMENT.md to reflect post-Phase-8 reality. Conducted agent workspace audit via SSH. Confirmed automation-supervisor retired, main agent running lead screening every 30 min, 3 new skills built autonomously.
Stopped at: Planning docs updated. All commits pushed.
Resume at: No active work. Next work is on-demand — check with Ameer on priorities.

### Key Details
- Container: `openclaw-ukwkggw4o8go0wgg804oc4oo-203702516523` (as of 2026-03-05; changes on redeploy)
- App UUID: `ukwkggw4o8go0wgg804oc4oo`
- Server LAN IP: 192.168.1.100
- Gateway URL: http://192.168.1.100:18789
- Tailscale URL: https://openclaw-server.tailad0efc.ts.net/
- Gateway token: `b0397f99db9ce994e4067d0c92acab229442e36fea02352f799f24ba607214f7`
- OpenClaw version: 2026.3.2 (latest as of 2026-03-05)
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

### Key Commits (Post-Phase 8 Simplifications)
- `7406d8a` — Retire automation-supervisor, add n8n TOOLS.md to main agent
- `328fb1a` — Switch main agent workspace files to seed-once mode
- `3fb579c` — Remove all workspace file seeding
- `ee32594` — Deny gateway tool globally, restrict analyst Directors
- `903d625` — Upgrade OpenClaw to 2026.3.2

---
*State initialized: 2026-02-14*
*Last updated: 2026-03-05 — All phases complete, post-Phase-8 simplifications documented, agent workspace audited*
