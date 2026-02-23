# 07-02 Summary: Deploy Verification

**Status**: COMPLETE
**Date**: 2026-02-23

## Verification Results

### 1. Control UI HTTPS (Tailscale MagicDNS) ✅
- URL: `https://openclaw-server.tailad0efc.ts.net/`
- HTTP 200 confirmed from MacBook (Tailscale peer 100.123.246.44)
- Server Tailscale IP: 100.116.73.61

### 2. Sub-agents (loopback-native) ✅
- gateway.mode=local (temp patch removed)
- gateway.remote=null (temp patch removed)
- Hooks endpoint returned 202 via Tailscale HTTPS
- Sub-agent loopback path: ws://127.0.0.1:18789 (unchanged)

### 3. Temp patches removed ✅
- gateway.mode: remote → local (confirmed in logs)
- gateway.remote: deleted (confirmed null in config)
- --allow-unconfigured: removed from exec line
- Config confirmed via jq inspection

### 4. n8n LAN-only (no Tailscale access) ✅
- n8n networks: ['coolify', 'zwsw8co4okwkwowk04ko04sg']
- No Tailscale interface in n8n container

### 5. Tailscale state persistence ✅
- State dir: /data/tailscale/ (persistent volume)
- Auth key: reusable tag:server key in TS_AUTHKEY Coolify env
- tailscale.resetOnExit=false in openclaw.json

### 6. TS_AUTHKEY in Coolify env ✅
- Added to Coolify env vars (not hardcoded in code)

## Issues Found and Fixed

### Coolify deploy stall (unrelated to Phase 7 code)
- Build completed at 01:55 UTC but Coolify's Horizon worker hung
- Fix: cancelled stalled job, empty commit re-triggered deploy
- Second build used Docker layer cache — completed in ~4 minutes

### tailscale serve --yes flag invalid in v1.94.2
- openclaw internally calls `tailscale serve --bg --yes 18789`
- `--yes` not a valid flag in tailscale v1.94.2 → serve failed on boot
- Fix: bootstrap.sh now pre-configures serve via socket before openclaw starts
- Serve config persists in /data/tailscale/ state across restarts
- Committed: fix(bootstrap) commit 1f92992

### Tailscale Serve feature not enabled on tailnet
- One-time admin console step: https://login.tailscale.com/f/serve
- Enabled manually by user; serve now active

## Final Config State
```json
{
  "bind": "loopback",
  "tailscale": { "mode": "serve", "resetOnExit": false },
  "mode": "local",
  "remote": null
}
```

## Tailscale Serve Config
```
https://openclaw-server.tailad0efc.ts.net (tailnet only)
|-- / proxy http://127.0.0.1:18789
```
