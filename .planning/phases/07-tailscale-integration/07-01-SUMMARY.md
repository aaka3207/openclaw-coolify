---
phase: 07-tailscale-integration
plan: 01
subsystem: infrastructure
tags: [tailscale, dockerfile, bootstrap, config, docker-compose]
dependency_graph:
  requires: []
  provides: [tailscale-binaries-in-image, tailscaled-startup-in-bootstrap, gateway-bind-loopback, tailscale-mode-serve]
  affects: [Dockerfile, scripts/bootstrap.sh, docker-compose.yaml, scripts/connect-mac-node.sh]
tech_stack:
  added: [tailscale v1.94.2 (binary copy from docker.io/tailscale/tailscale)]
  patterns: [Dockerfile binary copy from official image, tailscaled userspace networking, idempotent jq config patches]
key_files:
  created: []
  modified:
    - Dockerfile
    - scripts/bootstrap.sh
    - docker-compose.yaml
    - scripts/connect-mac-node.sh
decisions:
  - Use userspace networking (--tun=userspace-networking) — no NET_ADMIN cap or /dev/net/tun needed
  - Binary copy from official tailscale image (docker.io/tailscale/tailscale:v1.94.2) — no APT repo
  - Tailscale state persisted to /data/tailscale/ on existing volume — survives restarts
  - CHANGE-ME guard in connect-mac-node.sh forces user to set tailnet name before first use
  - Runtime flag detection via 'openclaw node run --help' — adapts to future API changes
metrics:
  duration: "~3 minutes"
  completed: "2026-02-23"
  tasks_completed: 3
  files_modified: 4
---

# Phase 7 Plan 01: Tailscale Integration — Dockerfile + Bootstrap + Config Summary

Tailscale sidecar added to OpenClaw container: tailscale v1.94.2 binaries baked into Dockerfile via binary copy from official image, tailscaled started with userspace networking in bootstrap.sh before openclaw gateway, config patched to gateway.bind=loopback + tailscale.mode=serve, all 4 temporary sub-agent patches removed.

## Tasks Completed

| Task | Name | Commit | Files |
|------|------|--------|-------|
| 1 | Add tailscale-install Dockerfile stage + docker-compose env vars | `dd7440c` | Dockerfile, docker-compose.yaml |
| 2 | Update bootstrap.sh — tailscaled startup, config patches, temp patch removal | `878b3d7` | scripts/bootstrap.sh |
| 3 | Update connect-mac-node.sh for Tailscale MagicDNS URL | `5078943` | scripts/connect-mac-node.sh |

## Changes Made

### Dockerfile
- New `tailscale-install` stage between `openclaw-install` and `final`
- Copies `tailscale` and `tailscaled` binaries from `docker.io/tailscale/tailscale:v1.94.2`
- Creates `/var/run/tailscale`, `/var/cache/tailscale`, `/var/lib/tailscale` dirs
- `final` stage now builds `FROM tailscale-install` instead of `FROM openclaw-install`
- Stage order: base -> runtimes -> browser-deps -> openclaw-install -> tailscale-install -> final

### scripts/bootstrap.sh
**Tailscale startup sequence (Category A):**
- Starts tailscaled with `--tun=userspace-networking` before `exec openclaw gateway run`
- Waits for socket `/var/run/tailscale/tailscaled.sock` (up to 10s loop)
- 1s post-socket pause (daemon may not be fully ready when socket first appears)
- Daemon responsiveness check: `tailscale status >/dev/null` with warning if unresponsive
- Authenticates with `TS_AUTHKEY` + `TS_HOSTNAME` (idempotent — skips if already authenticated)
- Connection wait loop (up to 30s, polls `BackendState == "Running"`)
- Serve status diagnostic logging at startup (helps debug if openclaw's serve call fails)

**Config patches (Category B):**
- Initial config template updated: `bind=loopback`, `tailscale.mode=serve`
- New idempotent patch: sets `gateway.bind=loopback` on existing configs
- New idempotent patch: sets `gateway.tailscale.mode=serve` on existing configs
- Cleanup patch: reverts `gateway.mode=remote` to `local` on existing configs
- Cleanup patch: removes `gateway.remote` key from existing configs

**Temp patch removal (Category C):**
- Removed: `gateway.remote.url` setter patch
- Removed: `gateway.mode=remote` setter patch (TEMP from CHANGELOG #22582 workaround)
- Removed: `gateway.remote.token` setter patch
- Removed: `--allow-unconfigured` flag from `exec openclaw gateway run`
- Preserved: `useAccessGroups=false` patch (separate issue, still needed)
- Preserved: all memorySearch, subagent, heartbeat, imageModel, fallback patches

**Banner update:**
- Added Tailscale URL line to onboarding steps

### docker-compose.yaml
- Changed `OPENCLAW_GATEWAY_BIND: lan` to `OPENCLAW_GATEWAY_BIND: loopback`
- Added `TS_AUTHKEY: ${TS_AUTHKEY:-}` (user sets in Coolify env)
- Added `TS_HOSTNAME: ${TS_HOSTNAME:-openclaw-server}` (default: openclaw-server)
- Added vestigial comment to ports section (port remains but traffic routes via Tailscale)

### scripts/connect-mac-node.sh
- Replaced `GATEWAY_HOST=192.168.1.100` + `GATEWAY_PORT=18789` with Tailscale MagicDNS URL
- Default: `GATEWAY_URL=https://openclaw-server.CHANGE-ME.ts.net`
- CHANGE-ME guard: script exits with setup instructions if tailnet name not configured
- Added Tailscale connectivity check (`tailscale status`) before attempting connection
- Runtime flag detection via `openclaw node run --help`:
  - Tries `--url` first, then `--gateway-url`, then falls back to `--host/--port/--tls`
  - Current API uses `--host`/`--port`/`--tls` (verified live on 2026.2.19)
- Added proper cleanup trap and NODE_PID tracking
- Updated usage docs with prerequisites and examples

## Deviations from Plan

None — plan executed exactly as written.

## Key Decisions Made

1. **Userspace networking only**: `--tun=userspace-networking` chosen so no special Docker capabilities (NET_ADMIN, /dev/net/tun) are needed. Simpler deployment.
2. **Tailscale state in /data/tailscale/**: Reuses existing Docker volume for state persistence. No new volume needed.
3. **CHANGE-ME guard in connect-mac-node.sh**: Prevents silent connection failures when tailnet name is not set. User is guided to correct URL via `tailscale status`.
4. **Runtime flag detection**: `openclaw node run --help` is parsed at runtime, future-proofing against API changes. Falls back gracefully.

## Post-Deploy Requirements (User Actions)

Before deploying, user must:
1. Create Tailscale account at https://login.tailscale.com
2. Create `tag:server` ACL tag in Tailscale Admin -> Access Controls
3. Enable MagicDNS in Tailscale Admin -> DNS
4. Create OAuth client (scope: auth_keys write, tag: tag:server) -> get `tskey-client-...` secret
5. Add `TS_AUTHKEY=tskey-client-...` to Coolify env for openclaw service
6. Install Tailscale on MacBook (`brew install --cask tailscale`) and login with same account
7. Update `connect-mac-node.sh` CHANGE-ME placeholder with actual tailnet name (or use `GATEWAY_URL=` env)

## Self-Check: PASSED

All modified files exist. All 3 task commits verified in git log:
- `dd7440c` — Dockerfile + docker-compose.yaml changes
- `878b3d7` — bootstrap.sh changes
- `5078943` — connect-mac-node.sh changes
