# Phase 6 Supplement: Tailscale Integration for Sub-Agent Spawning — Research

**Researched:** 2026-02-22
**Domain:** OpenClaw Tailscale bind mode, Docker Tailscale sidecar pattern, sub-agent URL security logic
**Confidence:** MEDIUM (OpenClaw Tailscale docs confirmed via official source; isSecureWebSocketUrl behavior reasoned from code + docs, not directly verified from source; Docker Tailscale sidecar pattern HIGH — well-documented official pattern)

---

## Summary

The goal is to fix sub-agent spawning, which currently fails because OpenClaw's `sessions_spawn` security check blocks `ws://10.0.1.20:18789` (plaintext ws:// to a non-loopback LAN IP). The current workaround — `gateway.remote.url = "ws://127.0.0.1:18789"` in bootstrap.sh — explicitly patches a loopback URL that passes the security check.

Research confirms the current loopback patch IS the right, minimal fix. It is already in production and working (06-01 COMPLETE per MEMORY.md). The question posed in this research — "should we implement Tailscale via bind=tailnet?" — has a clear answer: **No, not as a fix for sub-agent spawning. The loopback patch already solved it.**

Tailscale remains useful for a different purpose: giving the MacBook browser-control node a stable, encrypted path to the gateway independent of LAN IP. This is a separate, optional enhancement.

This document covers both: (1) why the Tailscale approach is not needed for sub-agents, (2) how Tailscale would work if added for MacBook access, and (3) the minimal Docker implementation if pursued.

**Primary recommendation:** Keep the loopback patch (`gateway.remote.url = "ws://127.0.0.1:18789"`) for sub-agents — it is correct and already working. If Tailscale is desired for MacBook connectivity, add a **sidecar container** with the official `tailscale/tailscale` image; do not install tailscaled inside the openclaw container.

---

## Critical Finding: Current Loopback Patch Is Correct and Sufficient

From OpenClaw issue #19004 and the `call-pduzpefz.js` source code documented in the original bug report:

```javascript
// When gateway.bind = "lan":
// Gateway listens on 0.0.0.0 (accepts loopback AND LAN IP connections)
// BUT: buildGatewayConnectionDetails() resolves to LAN IP for sub-agents
// -> isSecureWebSocketUrl(ws://10.0.1.20:18789) = FAILS (plaintext to non-loopback)

// The fix already in bootstrap.sh:
// gateway.remote.url = "ws://127.0.0.1:18789"
// -> sub-agents read this URL and use it directly
// -> isSecureWebSocketUrl(ws://127.0.0.1:18789) = PASSES (loopback exception)
```

The `gateway.remote.url` key is documented as the "Remote gateway WebSocket/HTTPS URL" — when set, it overrides `buildGatewayConnectionDetails()` resolution logic. Sub-agents use this URL directly rather than computing from bind mode.

**Confidence on loopback exception:** HIGH — official OpenClaw security docs state: "Device pairing is auto-approved for local connects (loopback or the gateway host's own tailnet address)." The WebChat docs confirm `http://127.0.0.1` is a secure context. These together confirm the loopback bypass in `isSecureWebSocketUrl`.

---

## What gateway.bind = "tailnet" Actually Does

From official OpenClaw docs (`docs.openclaw.ai/gateway/tailscale`) and DeepWiki:

| Setting | Gateway Listens On | URL for sub-agents |
|---------|-------------------|-------------------|
| `bind: "lan"` | `0.0.0.0:18789` | Resolves to LAN IP (e.g., `ws://10.0.1.20:18789`) — FAILS security check |
| `bind: "loopback"` | `127.0.0.1:18789` | Resolves to `ws://127.0.0.1:18789` — PASSES |
| `bind: "tailnet"` | Tailscale IP (e.g., `100.97.87.117:18789`) | Resolves to `ws://100.97.87.117:18789` |

For `bind: "tailnet"`, the question is whether `isSecureWebSocketUrl(ws://100.97.87.117:18789)` passes. Research finding:

- Official docs describe tailnet bind as "direct Tailnet bind (no HTTPS, no Serve/Funnel)" using `ws://` (not `wss://`)
- Security docs note: "device pairing is auto-approved for loopback or the gateway host's own tailnet address"
- This implies **the Tailscale IP is not automatically trusted by the security check** — only loopback is
- The security check likely checks: `url.startsWith('wss://')` OR `url.hostname === '127.0.0.1'` OR `url.hostname === 'localhost'`
- A Tailscale 100.x.x.x IP over plaintext `ws://` would NOT qualify as secure under this logic

**Conclusion:** Even if Tailscale were installed and `gateway.bind = "tailnet"` were set, sub-agents would likely still fail the security check, because they would use `ws://100.97.87.117:18789` (plaintext, non-loopback). The loopback patch is the correct fix regardless.

**Confidence:** MEDIUM — based on reasoning from docs and code patterns, not direct source inspection. This is the most likely interpretation but cannot be fully confirmed without reading the `isSecureWebSocketUrl` source.

---

## OpenClaw Tailscale Config Schema

From official docs (`github.com/openclaw/openclaw/blob/main/docs/gateway/tailscale.md`):

```json
{
  "gateway": {
    "bind": "tailnet",
    "tailscale": {
      "mode": "off",
      "resetOnExit": false
    },
    "auth": { "mode": "token", "token": "your-token" }
  }
}
```

### gateway.tailscale.mode options

| Mode | Behavior | Use Case |
|------|----------|----------|
| `"off"` | No Tailscale automation (default) | Manual tailscale CLI control |
| `"serve"` | Tailscale Serve — gateway stays on `127.0.0.1`, Tailscale proxies with HTTPS | Best for MacBook access with HTTPS |
| `"funnel"` | Tailscale Funnel — public internet via HTTPS | Remote access from anywhere |

### gateway.bind options

| Mode | Address | Notes |
|------|---------|-------|
| `"loopback"` | `127.0.0.1` | Default, most secure |
| `"lan"` | Primary LAN IPv4 (auto-detected) | Current setting, causes sub-agent issue |
| `"tailnet"` | Tailscale IPv4 | Requires tailscale installed + logged in |
| `"auto"` | LAN if available, else loopback | |
| `"custom"` | `gateway.customBindHost` | **INVALID — causes gateway crash** |

### Important: bind=tailnet + LAN access

When `gateway.bind = "tailnet"`:
- Gateway ONLY listens on the Tailscale IP (100.x.x.x)
- LAN port `192.168.1.100:18789` is NOT accessible
- "loopback (`http://127.0.0.1:18789`) will not work in this mode"
- MacBook must be on the same Tailnet to connect

**This means: switching to bind=tailnet breaks MacBook LAN access unless MacBook also runs Tailscale.**

Current bootstrap.sh explicitly uses `"bind": "lan"` in the generated config and the `gateway.remote.url` loopback patch. Switching to `bind: "tailnet"` would require:
1. tailscaled running inside container
2. MacBook added to same Tailnet
3. MacBook connects via Tailscale IP instead of LAN IP

---

## Tailscale for MacBook Access (Optional Enhancement)

If Tailscale is desired for MacBook → server connectivity (browser control, stable IP), here is the implementation pattern.

### Recommended: Sidecar Container Pattern (NOT baking into openclaw container)

The correct Docker pattern is a **sidecar container** that shares its network namespace with openclaw. This is Tailscale's official recommended Docker approach.

**Why sidecar over baking into openclaw container:**
- Openclaw container does not restart on Tailscale auth failures — Tailscale service restarts independently
- State is isolated to tailscale container's volume — not mixed with openclaw's `/data` volume
- No Dockerfile changes required — zero rebuild cost for Tailscale updates
- tailscaled manages its own lifecycle without bootstrap.sh changes
- Industry-standard Docker pattern; widely documented

**Why NOT baking tailscaled into the openclaw container:**
- tailscaled requires `NET_ADMIN` capability and `/dev/net/tun` device — currently not in docker-compose.yaml
- Installing tailscaled in bootstrap.sh adds ~30-60s to startup time (APT install)
- Tailscale state mixed with openclaw `/data` volume complicates recovery
- Gateway startup depends on Tailscale login completing — creates fragile dependency

### Sidecar docker-compose.yaml changes

```yaml
services:
  tailscale:
    image: tailscale/tailscale:latest   # pin to specific version in production
    hostname: openclaw-server           # tailnet machine name
    restart: unless-stopped
    environment:
      - TS_AUTHKEY=${TS_AUTHKEY}        # from Coolify env vars
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_EXTRA_ARGS=--accept-routes   # optional: accept subnet routes
    volumes:
      - tailscale-state:/var/lib/tailscale
    cap_add:
      - net_admin
      - sys_module
    devices:
      - /dev/net/tun:/dev/net/tun
    networks:
      - proxy                           # needs outbound internet to reach Tailscale control

  openclaw:
    # ... existing config unchanged ...
    # ADD: network_mode shares tailscale container's network namespace
    # OR: leave openclaw on its own network and just use tailscale for MacBook node only
```

**Decision point:** The sidecar sidecar does NOT need `network_mode: service:tailscale`. That pattern is for when you want the openclaw container to route ALL its traffic through Tailscale (useful for funnel/serve). For just "MacBook can reach server via Tailscale IP," you simply need the MacBook to run Tailscale and connect to the same tailnet — the server's tailscale container gets a 100.x.x.x IP that the MacBook can reach directly.

### What stays the same with sidecar approach

- `gateway.bind = "lan"` stays unchanged
- `gateway.remote.url = "ws://127.0.0.1:18789"` patch stays unchanged
- Port `0.0.0.0:18789:18789` stays in docker-compose.yaml
- MacBook can still access via `192.168.1.100:18789` (LAN, unchanged)
- MacBook can ALSO access via `100.x.x.x:18789` (Tailscale IP, new)
- Sub-agents continue using loopback patch — no change needed

### What changes with sidecar approach

- New tailscale service in docker-compose.yaml
- New `tailscale-state` volume in docker-compose.yaml volumes section
- New `TS_AUTHKEY` env var in Coolify environment settings
- MacBook installs Tailscale and joins the same tailnet

### Tailscale auth key strategy

| Key Type | Expiry | Use Case |
|----------|--------|----------|
| Reusable auth key | 90 days max (but node persists after key expires) | Simple, generate in Tailscale admin |
| OAuth client secret | Never expires | Best for automated Docker deployment |
| Ephemeral key | Node deleted when container stops | CI/CD, NOT for permanent server |

**For this deployment:** Use an OAuth client secret (`TS_AUTHKEY=tskey-client-...`) with `TS_EXTRA_ARGS=--advertise-tags=tag:server` (requires creating a tag in Tailscale admin). Nodes tagged this way never expire and can reconnect after container restart without re-auth.

Alternatively: use a reusable, non-ephemeral auth key. Once the state volume is populated on first run, the auth key is no longer needed (node key auto-renews). Key expiry does not disconnect existing nodes.

### tailscale-state volume behavior

```yaml
volumes:
  tailscale-state:    # Docker named volume
```

- First boot: tailscaled authenticates with `TS_AUTHKEY`, stores node state at `TS_STATE_DIR=/var/lib/tailscale`
- Subsequent boots: tailscaled reads existing state, reconnects to tailnet without re-auth
- Coolify `docker restart`: state persists in named volume — no re-auth needed
- Coolify redeploy (new container): named volume is reused — state persists
- **Critical:** `TS_STATE_DIR` must point to the mounted volume path. Without volume mount, every restart requires re-auth with `TS_AUTHKEY`

### Getting the Tailscale IP for OpenClaw config

After sidecar deployment, the Tailscale IP is assigned dynamically. To use `gateway.bind = "tailnet"`, bootstrap.sh would need:

```bash
# Wait for tailscaled, then get IP
TAILSCALE_IP=$(tailscale ip -4 2>/dev/null || true)
if [ -n "$TAILSCALE_IP" ]; then
  jq --arg ip "$TAILSCALE_IP" '.gateway.bind = "tailnet"' ...
fi
```

This adds complexity. Since the sidecar approach keeps the gateway on LAN, this is not needed.

---

## MacBook Browser Control: Tailscale vs LAN

From MEMORY.md: "Mac Browser Control: COMPLETE — script: scripts/connect-mac-node.sh"

The current MacBook connection uses `http://192.168.1.100:18789` (LAN IP). This works when MacBook and server are on the same WiFi/LAN. Tailscale adds the ability to connect when NOT on the same LAN — useful if the MacBook is used remotely or on a different network.

For the home server LAN-only deployment described in the context, Tailscale for MacBook connectivity is a nice-to-have, not a requirement. The primary motivation was sub-agent spawning — which is already solved.

---

## Alternatives Considered

### Alternative 1: gateway.bind = "loopback" (simpler than current lan)

**What it does:** Gateway only listens on 127.0.0.1. Sub-agents automatically use `ws://127.0.0.1:18789` without needing the `gateway.remote.url` override.

**Problem:** MacBook cannot connect to `192.168.1.100:18789` at all — the port would not be listening on the LAN interface.

**Verdict:** Not viable for current setup — MacBook access is required.

### Alternative 2: socat LAN→loopback forwarding inside container

**What it does:** `socat TCP-LISTEN:18789,fork TCP:127.0.0.1:18789 &` — relay external LAN connections to internal loopback gateway.

**Problem:** Adds another background process with no supervision; socat not in image; fragile.

**Verdict:** Worse than the existing loopback patch. Rejected.

### Alternative 3: tailscale.mode = "serve" with gateway.bind = "loopback"

**What it does:** Gateway on loopback, Tailscale Serve proxies HTTPS traffic from Tailnet to loopback. Sub-agents use loopback. MacBook connects via Tailscale HTTPS.

**Problem:** tailscale CLI must be installed and `tailscale serve` must be running. MacBook must be on Tailnet. LAN access without Tailscale would no longer work.

**Verdict:** Best Tailscale mode if MacBook LAN access is being replaced by Tailscale, but requires full Tailscale setup and MacBook enrollment.

### Alternative 4: gateway.remote.url loopback patch (CURRENT, WORKING)

**What it does:** Sub-agents read `gateway.remote.url = "ws://127.0.0.1:18789"` and bypass the bind-mode IP resolution. Gateway still listens on LAN. MacBook connects via LAN IP as before.

**Verdict:** Correct and working. Already deployed. No changes needed for sub-agent spawning.

---

## Don't Hand-Roll

| Problem | Don't Build | Use Instead |
|---------|-------------|-------------|
| Tailscale state persistence | Custom state management in bootstrap.sh | Named Docker volume + TS_STATE_DIR env var |
| tailscaled process supervision | nohup/background script | Sidecar container with `restart: unless-stopped` |
| Tailscale node auth | Scripted tailscale login in bootstrap.sh | TS_AUTHKEY env var in docker-compose |
| Getting tailscale IP for config | ip addr parsing, curl to metadata | `tailscale ip -4` command (available after login) |

---

## Common Pitfalls

### Pitfall 1: gateway.bind = "tailnet" breaks LAN access
**What goes wrong:** After switching bind mode, MacBook gets connection refused on `192.168.1.100:18789`.
**Why it happens:** "bind=tailnet" means the gateway ONLY listens on the Tailscale IP (100.x.x.x), not on 0.0.0.0.
**How to avoid:** Keep `bind: "lan"` unless MacBook is also enrolled in Tailscale and browser control script is updated to use Tailscale IP.
**Warning signs:** MacBook sees "connection refused" on LAN port after config change.

### Pitfall 2: Tailscale state not persisted
**What goes wrong:** Every container restart requires manual `tailscale login` or re-auth.
**Why it happens:** `TS_STATE_DIR` points to a non-persistent path inside the container (e.g., `/tmp/`), or the volume is not mounted.
**How to avoid:** Always mount a named volume to `TS_STATE_DIR=/var/lib/tailscale`. Verify with `docker volume inspect`.
**Warning signs:** Container restarts fine but Tailscale shows "logged out" status; TS_AUTHKEY must be re-used.

### Pitfall 3: Tailscale sidecar needs outbound internet
**What goes wrong:** tailscaled cannot reach Tailscale control servers — stays "connecting" forever.
**Why it happens:** The `internal: true` Docker network blocks external traffic. Tailscale sidecar must be on the `proxy` network (external), not the `internal` network.
**How to avoid:** Add `networks: [proxy]` to the tailscale sidecar service, NOT `internal`.
**Warning signs:** `tailscale status` shows "NeedsLogin" but state file exists; container logs show "dial tcp: i/o timeout" to Tailscale control IPs.

### Pitfall 4: kernel mode in Docker requires capabilities
**What goes wrong:** tailscaled fails with "cannot create TUN device" or exits immediately.
**Why it happens:** Kernel networking mode needs `cap_add: [net_admin, sys_module]` and `/dev/net/tun` device access.
**How to avoid:** Always include capabilities in the sidecar docker-compose config. Alternatively, use `TS_USERSPACE=true` for userspace networking (default in official image — no capabilities needed).
**Warning signs:** tailscaled container exits with code 1; logs show "open /dev/net/tun: no such file or directory".

### Pitfall 5: "gateway.bind = custom" crash
**What goes wrong:** Gateway fails to start with "Unrecognized key" or "invalid bind value".
**Why it happens:** OpenClaw Control UI can write `"custom"` as a bind value — but it is not a valid gateway schema value and crashes the gateway.
**How to avoid:** Never use `bind: "custom"`. If it appears, edit the volume directly. bootstrap.sh patch should remove it.
**Warning signs:** Gateway restart loop; volume openclaw.json shows `"bind": "custom"`.

---

## Code Examples

### Minimal Tailscale sidecar docker-compose fragment (Confidence: HIGH — official pattern)

```yaml
# Source: tailscale.com/kb/1282/docker + tailscale.com/blog/docker-tailscale-guide

services:
  tailscale:
    image: tailscale/tailscale:stable  # pin to stable tag
    hostname: openclaw-server
    restart: unless-stopped
    environment:
      - TS_AUTHKEY=${TS_AUTHKEY}
      - TS_STATE_DIR=/var/lib/tailscale
      - TS_USERSPACE=false              # kernel mode (requires cap_add below)
    volumes:
      - tailscale-state:/var/lib/tailscale
    cap_add:
      - net_admin
      - sys_module
    devices:
      - /dev/net/tun:/dev/net/tun
    networks:
      - proxy                           # must have outbound internet

volumes:
  tailscale-state:
```

### Checking Tailscale sidecar IP after startup

```bash
# From server (Tailscale sidecar is a separate container)
sudo docker exec <tailscale_container_name> tailscale ip -4
# Output: 100.x.x.x

# From server: verify tailscale status
sudo docker exec <tailscale_container_name> tailscale status
# Shows: self IP, other tailnet devices
```

### OpenClaw tailscale config (for Serve mode, NOT needed for current setup)

```json
// Source: github.com/openclaw/openclaw/blob/main/docs/gateway/tailscale.md
// tailnet-only Serve (gateway stays on loopback):
{
  "gateway": {
    "bind": "loopback",
    "tailscale": {
      "mode": "serve",
      "resetOnExit": false
    }
  }
}

// Direct tailnet bind (gateway on Tailscale IP):
{
  "gateway": {
    "bind": "tailnet",
    "tailscale": {
      "mode": "off"
    },
    "auth": { "mode": "token", "token": "..." }
  }
}
```

### Current bootstrap.sh gateway.remote.url patch (the working fix)

```bash
# Source: bootstrap.sh (already in production)
# This is the correct fix for sub-agent spawning — Tailscale is not needed for this
REMOTE_URL=$(jq -r '.gateway.remote.url // empty' "$CONFIG_FILE" 2>/dev/null)
if [ -z "$REMOTE_URL" ] || [ "$REMOTE_URL" != "ws://127.0.0.1:${OPENCLAW_GATEWAY_PORT:-18789}" ]; then
  jq ".gateway.remote = {\"url\": \"ws://127.0.0.1:${OPENCLAW_GATEWAY_PORT:-18789}\"}" \
    "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
  echo "[config] Set gateway.remote.url=ws://127.0.0.1:... (sub-agent loopback)"
fi
```

---

## State of the Art

| Old Approach | Current Approach | Status |
|--------------|------------------|--------|
| gateway.bind=lan (sub-agents fail) | gateway.remote.url=loopback patch | WORKING (06-01 COMPLETE) |
| LAN-only MacBook access | LAN-only (Tailscale is optional future addition) | Works for home LAN |
| Tailscale baked into container | Sidecar pattern (if Tailscale added) | Recommended if pursued |

---

## Open Questions

1. **Does `isSecureWebSocketUrl` explicitly whitelist Tailscale 100.64.x.x?**
   - What we know: Official docs confirm loopback is whitelisted. Security docs mention "loopback or the gateway host's own tailnet address" as auto-approved for device pairing.
   - What's unclear: Whether "own tailnet address" also applies to `isSecureWebSocketUrl` or only to device pairing approval. If it does, `bind=tailnet` would pass the security check for sub-agents.
   - Recommendation: This doesn't matter for the current deployment since `gateway.remote.url` already fixes sub-agents. But if someone wants to understand whether `bind=tailnet` would work without the `remote.url` patch: test it by temporarily setting `bind=tailnet` (after installing Tailscale) and triggering sub-agent spawn.

2. **Tailscale free tier vs. personal: node count limits?**
   - What we know: Tailscale free plan allows up to 3 users and 100 devices. This deployment needs: server (1) + MacBook (2). Well within free tier.
   - What's unclear: Whether Coolify's own Tailscale integration (if any) conflicts with a separate tailscale container.
   - Recommendation: Check Coolify environment for existing Tailscale setup before deploying sidecar.

3. **TS_AUTHKEY in Coolify secrets vs. env vars?**
   - What we know: `TS_AUTHKEY` is a secret that grants tailnet access. Should not be in docker-compose.yaml in plaintext.
   - What's unclear: Whether Coolify's secret injection works for the tailscale sidecar service's environment.
   - Recommendation: Add `TS_AUTHKEY` as a Coolify environment secret (same as OPENAI_API_KEY). Reference as `${TS_AUTHKEY}` in docker-compose.yaml.

---

## Root Cause: Confirmed from Source + CHANGELOG

From reading `call-pduzpefz.js` and `pi-embedded-wm4jEWuI.js` directly:

```javascript
const isRemoteMode = config.gateway?.mode === "remote";
const remote = isRemoteMode ? config.gateway?.remote : void 0;
// gateway.remote.url is ONLY read when mode === "remote"
// With mode=local (default), remoteUrl is always undefined
// → sub-agents resolve to LAN IP → ws://10.0.1.20:18789 → BLOCKED
```

`isSecureWebSocketUrl` confirmed: only passes for `wss://` OR `ws://` to `isLoopbackHost`. Tailscale IPs fail.

## Upstream Fix: UNRELEASED (as of 2026-02-22)

From `CHANGELOG.md` (main branch, unreleased section):
```
- Gateway/Scopes: include operator.read and operator.write in default operator connect
  scope bundles across CLI, Control UI, and macOS clients so write-scoped announce/
  sub-agent follow-up calls no longer hit `pairing required` disconnects on loopback
  gateways. (#22582)
```

Also in 2026.2.21 (released):
```
- Security/Network: block plaintext ws:// connections to non-loopback hosts and require
  secure websocket transport elsewhere. (#20803)  ← tightens the check, doesn't fix it
- Gateway/Pairing: tolerate legacy paired devices missing roles/scopes metadata in
  websocket upgrade checks. (#21447)  ← pairing metadata fix, not URL fix
```

**Current version: 2026.2.19. Latest released: 2026.2.21-2. Fix: not yet released.**
Upgrading to 2026.2.21-2 makes things worse (more enforcement of the ws:// check).

## Temporary Patch (Until Upstream Fix Releases)

The fix: `gateway.mode = "remote"` makes the client/sub-agents use `gateway.remote.url`
(loopback) instead of resolving the LAN IP. But `mode=remote` blocks gateway startup.
Solution: pass `--allow-unconfigured` to bypass the startup check.

**Two changes to bootstrap.sh:**

1. Add patch to set `gateway.mode = "remote"`:
```bash
jq '.gateway.mode = "remote"' "$CONFIG_FILE" > "${CONFIG_FILE}.tmp" && mv ...
```

2. Add `--allow-unconfigured` to gateway start command (line 532):
```bash
exec openclaw gateway run --allow-unconfigured
```

**Effect:**
- Gateway server: `--allow-unconfigured` bypasses mode check, binds normally to `0.0.0.0:18789` (bind=lan) ✓
- Sub-agents: read config, see `mode=remote`, use `gateway.remote.url = "ws://127.0.0.1:18789"` (loopback) → passes `isSecureWebSocketUrl` ✓
- MacBook LAN access: still works via Docker port mapping → `0.0.0.0:18789` ✓

**Remove when:** OpenClaw releases the upstream fix (likely next release after 2026.2.21-2).
Watch: CHANGELOG.md for entry mentioning `sessions_spawn` + loopback + ws:// or gateway.mode.

## Decision Summary: Tailscale for This Deployment

| Question | Answer | Confidence |
|----------|--------|-----------|
| Is Tailscale needed for sub-agent spawning? | **No** — temp patch + upstream fix solves it | HIGH |
| Does `isSecureWebSocketUrl` whitelist Tailscale IPs? | **No** — only wss:// or loopback | HIGH (confirmed from source) |
| Does `bind=tailnet` break MacBook LAN access? | **Yes** — gateway only listens on Tailscale IP | HIGH |
| Is Tailscale useful for anything in this deployment? | Yes — optional: gives MacBook a stable path when off LAN | MEDIUM |
| Best pattern if Tailscale is added? | Sidecar container, NOT baked into openclaw image | HIGH |
| Does Tailscale sidecar require openclaw Dockerfile changes? | **No** — docker-compose.yaml + new volume only | HIGH |
| Does Tailscale sidecar affect existing LAN access? | **No** — LAN port still works in parallel | HIGH |

---

## Sources

### Primary (HIGH confidence)
- `github.com/openclaw/openclaw/blob/main/docs/gateway/tailscale.md` — gateway.bind modes, tailscale.mode options, serve/funnel config examples, direct tailnet bind behavior
- `docs.openclaw.ai/gateway/tailscale` — confirms same: "loopback will not work" in tailnet bind mode
- `tailscale.com/kb/1282/docker` — TS_AUTHKEY, TS_STATE_DIR, TS_USERSPACE, official Docker usage guide
- `tailscale.com/blog/docker-tailscale-guide` — full sidecar docker-compose example with cap_add, devices, volumes
- `github.com/openclaw/openclaw/issues/19004` — "CLI uses LAN IP instead of loopback for local gateway calls when bind=lan" — confirmed root cause of sub-agent issue

### Secondary (MEDIUM confidence)
- `deepwiki.com/openclaw/openclaw/3.1-gateway-configuration` — gateway bind modes table, tailscale integration options
- `deepwiki.com/openclaw/openclaw/3.4-remote-access` — gateway.remote.url as URL override for sub-agents
- `docs.openclaw.ai/gateway/security` — "loopback or the gateway host's own tailnet address" auto-approved; loopback is secure context
- `tailscale.com/kb/1112/userspace-networking` — userspace networking mode behavior, SOCKS5/HTTP proxy requirements

### Tertiary (LOW confidence — reasoning/inference)
- `isSecureWebSocketUrl` Tailscale behavior: Reasoned from docs + code patterns. Not directly verified from OpenClaw source.
- Tailscale 100.x.x.x not whitelisted by security check: Inferred from "bind=tailnet" docs showing `ws://` (not `wss://`) — security check likely requires either wss:// or loopback.

---

## Metadata

**Confidence breakdown:**
- Sub-agent loopback fix (current patch): HIGH — already in production, confirmed working
- Tailscale gateway.bind modes: HIGH — official docs
- Tailscale sidecar Docker pattern: HIGH — official Tailscale docs
- isSecureWebSocketUrl for Tailscale IPs: MEDIUM — reasoned, not source-verified
- MacBook LAN access behavior with bind=tailnet: HIGH — docs explicitly state loopback/LAN inaccessible

**Research date:** 2026-02-22
**Valid until:** 2026-03-24 (30 days — OpenClaw releases frequently; Tailscale Docker pattern is stable)

---

---

## Gap Analysis Updates (2026-02-22)

**Context for these updates:** Phase 7 has been scoped as a real implementation phase: add Tailscale Serve to the openclaw container (NOT sidecar) so the Control UI becomes accessible via HTTPS from anywhere, and remove the temporary gateway.mode=remote patches. This changes several prior recommendations. The gap analysis below addresses specific implementation questions the planner needs answered.

**The scope pivot:** The previous research recommended a sidecar container. Phase 7 decided to bake tailscale into the openclaw Dockerfile instead (new `tailscale-install` stage). This decision was driven by the requirement for `tailscale.mode=serve` integration at the gateway level — OpenClaw needs to call `tailscale serve` on the container's own tailscale daemon, which requires both tailscale CLI and tailscaled to be in the same container as openclaw.

---

### Gap 1: Dockerfile Tailscale Installation Method

**Question:** What is the correct way to install tailscale CLI + tailscaled in a Debian bookworm-slim Docker image?

**Finding:** Two viable approaches, each with tradeoffs.

**Approach A: Copy binaries from official tailscale Docker image (RECOMMENDED)**

This is the Tailscale-documented pattern for embedding in custom Dockerfiles (confirmed from `tailscale.com/kb/1107/heroku`):

```dockerfile
# In tailscale-install stage:
COPY --from=docker.io/tailscale/tailscale:v1.94.2 /usr/local/bin/tailscaled /usr/local/bin/tailscaled
COPY --from=docker.io/tailscale/tailscale:v1.94.2 /usr/local/bin/tailscale /usr/local/bin/tailscale
RUN mkdir -p /var/run/tailscale /var/cache/tailscale /var/lib/tailscale
```

This pattern:
- Pins to a specific version (v1.94.2 is current stable as of 2026-02-22 — confirmed from `pkgs.tailscale.com/stable/`)
- No APT repo setup needed — clean single-layer addition
- Both binaries included: `tailscaled` (daemon) AND `tailscale` (CLI)
- Directories needed: `/var/run/tailscale` (socket), `/var/cache/tailscale`, `/var/lib/tailscale` (state — will be overridden by volume mount)
- Does NOT need `cap_add: [net_admin]` or `/dev/net/tun` when using userspace networking (`--tun=userspace-networking`)

**Approach B: APT install from Tailscale repository**

```dockerfile
RUN curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.noarmor.gpg \
      | tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null && \
    curl -fsSL https://pkgs.tailscale.com/stable/debian/bookworm.tailscale-keyring.list \
      | tee /etc/apt/sources.list.d/tailscale.list && \
    apt-get update && apt-get install -y tailscale=1.94.2 && \
    rm -rf /var/lib/apt/lists/*
```

APT install installs BOTH tailscale CLI and tailscaled. More familiar pattern but requires adding Tailscale's APT repo to the image, slightly heavier layer.

**Recommendation: Approach A (binary copy).** Simpler, no APT repo setup, exact same binaries as official image, single pinned version string. The planner should use:

```dockerfile
FROM openclaw-install AS tailscale-install

COPY --from=docker.io/tailscale/tailscale:v1.94.2 /usr/local/bin/tailscaled /usr/local/bin/tailscaled
COPY --from=docker.io/tailscale/tailscale:v1.94.2 /usr/local/bin/tailscale /usr/local/bin/tailscale
RUN mkdir -p /var/run/tailscale /var/cache/tailscale /var/lib/tailscale
```

**Current stable version to pin:** `v1.94.2` (confirmed from `pkgs.tailscale.com/stable/` — versions listed: 1.94.2, 1.94.1, 1.92.5...)

**Confidence:** HIGH — binary copy pattern is from Tailscale's own official Heroku guide; version confirmed from official stable package index.

---

### Gap 2: Does OpenClaw Start tailscaled Itself?

**Question:** When `gateway.tailscale.mode=serve` is set, does OpenClaw start the tailscaled daemon internally, or does it expect tailscaled to already be running?

**Finding:** OpenClaw does NOT start tailscaled. It calls the `tailscale` CLI tool and expects `tailscaled` to already be running and authenticated.

From official OpenClaw docs (`docs.openclaw.ai/gateway/tailscale`) and DeepWiki analysis:
- "Tailscale Serve/Funnel requires the tailscale CLI to be installed and logged in"
- OpenClaw invokes `tailscale serve` to configure the proxy and `tailscale serve reset` on exit (when `resetOnExit: true`)
- OpenClaw verifies Tailscale identity by calling `tailscale whois <ip>` for `x-forwarded-for` header validation
- `gateway.tailscale.mode=serve` requires `gateway.bind=loopback` — OpenClaw enforces this and crashes with `"Gateway failed to start: Error: tailscale serve/funnel requires gateway bind=loopback (127.0.0.1)"` if bind is not loopback
- OpenClaw does NOT manage the tailscaled process lifecycle

**What OpenClaw does at startup with mode=serve:**
1. Validates `bind=loopback` is set (crashes if not)
2. Calls `tailscale serve` to configure HTTPS proxying to `http://127.0.0.1:${PORT}`
3. Starts the gateway bound to 127.0.0.1
4. On shutdown (if `resetOnExit: true`): calls `tailscale serve reset`

**What bootstrap.sh must do BEFORE `exec openclaw gateway run`:**
1. Start `tailscaled` as a background daemon
2. Run `tailscale up --authkey=${TS_AUTHKEY}` (or skip if already authenticated from state)
3. Wait until tailscaled is connected and ready (poll `tailscale status` or use health endpoint)
4. Then exec openclaw

**Confidence:** HIGH — multiple official sources confirm "tailscale CLI must be installed and logged in" as prerequisite. OpenClaw issues (#14542) confirm the `bind=loopback` crash. ResetOnExit behavior confirmed from DeepWiki.

---

### Gap 3: bootstrap.sh Startup Sequence

**Question:** What is the exact startup order for tailscaled + openclaw in bootstrap.sh?

**Finding:** The sequence is: start tailscaled background → authenticate → wait for ready → exec openclaw.

**Exact bootstrap.sh addition (to insert before `exec openclaw gateway run`):**

```bash
# ----------------------------
# Tailscale startup (when tailscale.mode=serve)
# ----------------------------
if command -v tailscaled >/dev/null 2>&1; then
  # Start tailscaled daemon (userspace networking — no NET_ADMIN cap needed)
  # State dir on persistent volume so node survives container restarts
  TS_STATE="/data/tailscale"
  mkdir -p "$TS_STATE"
  tailscaled --tun=userspace-networking --state="$TS_STATE/tailscaled.state" \
    --socket=/var/run/tailscale/tailscaled.sock >/tmp/tailscaled.log 2>&1 &
  TAILSCALED_PID=$!
  echo "[tailscale] Started tailscaled (PID $TAILSCALED_PID, userspace networking)"

  # Authenticate (idempotent — skips if already logged in via persisted state)
  if [ -n "${TS_AUTHKEY:-}" ]; then
    # Wait a moment for socket to be available
    sleep 2
    tailscale --socket=/var/run/tailscale/tailscaled.sock up \
      --auth-key="${TS_AUTHKEY}" \
      --hostname="${TS_HOSTNAME:-openclaw-server}" \
      --accept-routes \
      2>/dev/null || echo "[tailscale] WARNING: tailscale up failed (may already be authenticated)"
  fi

  # Wait for tailscale to be connected (up to 30s)
  TS_READY=false
  for i in $(seq 1 15); do
    if tailscale --socket=/var/run/tailscale/tailscaled.sock status --json 2>/dev/null \
        | grep -q '"BackendState":"Running"'; then
      TS_READY=true
      echo "[tailscale] Connected to tailnet"
      break
    fi
    sleep 2
  done
  if [ "$TS_READY" = "false" ]; then
    echo "[tailscale] WARNING: tailscale not connected after 30s — gateway may fail to start"
  fi
fi
```

**Key decisions in this sequence:**

1. **Userspace networking** (`--tun=userspace-networking`): Avoids need for `NET_ADMIN` cap and `/dev/net/tun`. Works inside Docker without special permissions. Container already runs as root — no permission issue.

2. **State path**: `/data/tailscale/` on the existing openclaw-data volume. This means tailscale state survives container restarts AND deploys without needing a second volume. The existing volume is already mounted at `/data`. Subdirectory isolation keeps it clean.

3. **TS_AUTHKEY env var**: Must be added to Coolify as a secret env var. bootstrap.sh reads it directly from environment (same pattern as `OPENCLAW_GATEWAY_TOKEN`). Does NOT need to go through BWS since TS_AUTHKEY is only needed at startup (once state is persisted, it is not needed again).

4. **Idempotent auth**: `tailscale up` with `--auth-key` is safe to call repeatedly — if already authenticated from persisted state, it either re-authenticates or is a no-op. The `|| echo WARNING` prevents the script from failing if tailscale is already up.

5. **Socket path**: Explicit `--socket=/var/run/tailscale/tailscaled.sock` ensures CLI commands target the correct daemon instance.

**Confidence:** MEDIUM — sequence is derived from Tailscale's official Heroku guide pattern + community patterns. The exact `--socket` flag and `--state` path behavior is standard tailscale CLI behavior (HIGH), but the specific wait-loop approach is synthesized from multiple sources (MEDIUM for the exact implementation).

---

### Gap 4: TS_STATE_DIR — Where to Persist Tailscale State

**Question:** Where should tailscale state be persisted? On the existing `/data` volume or a separate named volume?

**Finding:** Use a subdirectory of the existing openclaw-data volume: `/data/tailscale/`

**Reasoning:**
- The openclaw-data volume at `/data` already exists and persists across deploys
- No new volume declaration needed in docker-compose.yaml — reduces complexity
- The `--state` flag in tailscaled points to a file path, not a directory: `--state=/data/tailscale/tailscaled.state`
- Alternatively can use `TS_STATE=mem:` for in-memory state (no persistence, requires re-auth on each restart) — NOT recommended for permanent server

**Decision: `/data/tailscale/tailscaled.state`** (subdirectory of existing volume)

Alternative considered: separate named volume `tailscale-state`. This is cleaner in theory but adds a second volume to manage in Coolify. Not worth it when the existing volume works fine.

**What does NOT change in docker-compose.yaml:** No new volume required. The `tailscale-state` volume pattern from the sidecar research is NOT needed for the baked-in approach.

**Confidence:** HIGH — `--state` flag is standard tailscaled behavior; `/data` volume confirmed persistent from existing project setup.

---

### Gap 5: gateway.remote.url and gateway.mode=remote Removal Safety

**Question:** When we switch to `bind=loopback` + `tailscale.mode=serve`, can we safely remove `gateway.mode=remote`, `gateway.remote.url`, and `--allow-unconfigured` from bootstrap.sh?

**Finding: YES — removing them is correct and necessary when switching to bind=loopback.**

Here is why removal is safe:

**With bind=loopback + tailscale.mode=serve:**
- The gateway binds to `127.0.0.1:18789`
- Sub-agents that call `buildGatewayConnectionDetails()` will now get `ws://127.0.0.1:18789` (loopback) — this PASSES `isSecureWebSocketUrl`
- `gateway.mode=remote` is no longer needed because the loopback URL is now returned naturally by the bind mode
- `gateway.remote.url` override is no longer needed for the same reason
- `--allow-unconfigured` was only needed because `mode=remote` without full remote config caused a startup validation failure — removing `mode=remote` removes the need for this flag

**What must be removed from bootstrap.sh:**
1. The `gateway.mode=remote` patch block (lines ~342-346 in current bootstrap.sh)
2. The `gateway.remote.token` patch block (lines ~350-356)
3. The `--allow-unconfigured` flag from the `exec openclaw gateway run` command (last line)
4. The `gateway.remote.url` patch block (lines ~333-338) — the loopback URL is now implicit from bind=loopback

**What must be ADDED to bootstrap.sh:**
1. The tailscaled startup sequence (Gap 3 above)
2. A bootstrap patch to set `gateway.bind = "loopback"` (replaces `"lan"`)
3. A bootstrap patch to set `gateway.tailscale.mode = "serve"`

**What stays the same:**
- `useAccessGroups=false` patch stays — it is a separate issue unrelated to the temp patches

**Confidence:** HIGH — confirmed from OpenClaw source analysis in original gap research: `gateway.remote.url` is ONLY read when `mode=remote`. With `bind=loopback`, `buildGatewayConnectionDetails()` returns the loopback URL natively. The removal is safe.

---

### Gap 6: Docker Port Mapping with bind=loopback — CRITICAL FINDING

**Question:** With `bind=loopback`, the openclaw gateway listens on `127.0.0.1:18789` inside the container. Will the docker-compose port mapping `0.0.0.0:18789:18789` still allow LAN access (e.g., MacBook at `192.168.1.100:18789`)?

**Finding: NO — LAN access via Docker port mapping will be BROKEN with bind=loopback.**

This is a fundamental Docker networking behavior (confirmed from `docs.docker.com/engine/network/port-publishing/`):

- Docker port mapping creates a firewall rule routing traffic from the host's external interface to the container's port
- BUT: if the service inside the container only listens on `127.0.0.1` (the container's loopback), the forwarded traffic arrives on a different interface (the container's eth0) and the service refuses it
- Result: `0.0.0.0:18789:18789` in docker-compose.yaml becomes useless — LAN traffic reaches the Docker host's port 18789 but gets dropped inside the container because openclaw isn't listening on the container's eth0

**This confirms: bind=loopback + tailscale.mode=serve means LAN access is fully replaced by Tailscale access.**

The MacBook MUST be enrolled in the tailnet to access Control UI or the gateway WebSocket. `192.168.1.100:18789` will no longer work once bind switches to loopback.

**Impact on docker-compose.yaml:**
- The `ports: ["0.0.0.0:18789:18789"]` entry becomes vestigial but harmless — can be kept for explicitness or removed
- MacBook's `connect-mac-node.sh` script must be updated to use the Tailscale URL instead of LAN IP

**Impact on sub-agents:**
- Sub-agents run INSIDE the container — they connect to `ws://127.0.0.1:18789` which DOES work (same container loopback)
- No impact on sub-agent functionality

**Confidence:** HIGH — confirmed from Docker official docs and multiple community sources. The loopback binding behavior inside a container is well-established.

---

### Gap 7: MacBook Enrollment Steps

**Question:** What does the user need to do to access the gateway after Tailscale is deployed?

**Finding:** Four steps, all standard Tailscale operations.

**One-time setup (user actions):**
1. Create a Tailscale account at `login.tailscale.com` (free tier: up to 100 devices, 3 users)
2. Create an OAuth client secret in Tailscale admin console:
   - Admin → Settings → OAuth clients → Create client
   - Scope: `auth_keys` (write)
   - Tags: create tag `tag:server` and assign it
   - Copy the client secret (format: `tskey-client-...`)
3. Add to Coolify env vars: `TS_AUTHKEY=tskey-client-...`
4. Add to Coolify env vars: `TS_HOSTNAME=openclaw-server` (optional, sets tailnet machine name)

**MacBook one-time setup:**
1. Install Tailscale app: `brew install --cask tailscale` or download from `tailscale.com`
2. Login with same Tailscale account
3. Enable MagicDNS in Tailscale admin console (Admin → DNS → Enable MagicDNS)

**Accessing Control UI after setup:**
- URL format: `https://openclaw-server.your-tailnet-name.ts.net/` (MagicDNS)
- Or: `https://100.x.x.x/` (direct Tailscale IP)
- Tailscale Serve auto-configures HTTPS with a valid TLS cert — no "insecure" browser warning
- This solves the Control UI "requires HTTPS or localhost (secure context)" error completely

**Confidence:** HIGH — standard Tailscale enrollment procedure, well-documented.

---

### Gap 8: TS_AUTHKEY Strategy — OAuth vs Reusable

**Question:** Should we use an OAuth client secret or a reusable auth key?

**Finding:** OAuth client secret is the correct choice for a permanent home server.

**Comparison:**

| Property | Reusable Auth Key | OAuth Client Secret |
|----------|-------------------|---------------------|
| Key expiry | Max 90 days | Never expires |
| Node expiry | Node persists after key expires (180-day node key auto-renews) | Node never expires (tagged) |
| State persistence | Once authenticated, key not needed until state is lost | Same |
| Format | `tskey-auth-...` | `tskey-client-...` |
| Admin overhead | Must regenerate key every 90 days and update Coolify env | Zero ongoing maintenance |
| Setup complexity | Simpler (no tags required) | Requires creating tag in admin |

**Recommendation: OAuth client secret** for this permanent server deployment. Zero ongoing maintenance once set up. The state file at `/data/tailscale/tailscaled.state` persists across container restarts, so the authkey is only needed if state is lost (volume corruption, new volume).

**Reusable key is acceptable** as a simpler fallback. The 90-day key expiry does NOT disconnect the node — the node key (separate from auth key) auto-renews. The auth key only matters for initial registration and re-registration after state loss.

**BWS handling:** Since TS_AUTHKEY is only needed at bootstrap (not during operation), it should be:
- Added as a Coolify env var (same as `OPENCLAW_GATEWAY_TOKEN`)
- NOT stored in BWS — it doesn't need 5-minute refresh
- bootstrap.sh reads it from `${TS_AUTHKEY}` directly from environment
- After state is persisted, the key is not re-read until container recreation

**Confidence:** HIGH — from Tailscale official docs on auth keys and OAuth clients.

---

### Gap 9: Current Stable Tailscale Version to Pin

**Finding:** `v1.94.2` is current stable as of 2026-02-22.

Confirmed from `pkgs.tailscale.com/stable/` which lists: `1.94.2, 1.94.1, 1.92.5, 1.92.3, 1.92.2, 1.92.1, 1.90.9...`

**Dockerfile pin:** `docker.io/tailscale/tailscale:v1.94.2`

---

### Gap 10: openclaw symlink corruption — add to AGENTS.md/SOUL.md

**Finding from this session:** The agent ran `npm i -g openclaw@latest` inside the container, overwriting the symlink at `/usr/local/bin/openclaw`. bootstrap.sh restored it. This vulnerability must be documented as a rule.

**What was confirmed:**
- bootstrap.sh already has symlink restoration (lines 7-14 of current bootstrap.sh)
- AGENTS.md needs a rule: "Never run `npm install -g` or `npm i -g` in the container — this corrupts the openclaw binary"
- SOUL.md needs a rule: "Do not install global npm packages that could conflict with openclaw"

This is a Phase 7 deliverable but is about AGENTS.md/SOUL.md content, not Tailscale. It should be included in the phase plan as a separate task.

---

### Revised Architecture for Phase 7

Based on gap analysis, the architecture is:

```
Dockerfile stages:
  base → runtimes → browser-deps → openclaw-install → tailscale-install → final
                                                          ^
                                                   New stage: copies tailscale
                                                   + tailscaled binaries from
                                                   tailscale/tailscale:v1.94.2

bootstrap.sh startup sequence:
  1. Config patches (existing)
  2. tailscaled start (userspace, state=/data/tailscale/)
  3. tailscale up --auth-key=${TS_AUTHKEY} (if TS_AUTHKEY set)
  4. Wait for tailnet connected (30s timeout)
  5. exec openclaw gateway run  (NO --allow-unconfigured)

openclaw.json config changes (via bootstrap.sh patches):
  REMOVE: gateway.mode=remote
  REMOVE: gateway.remote.url + gateway.remote.token
  ADD:    gateway.bind = "loopback"
  ADD:    gateway.tailscale.mode = "serve"
  ADD:    gateway.tailscale.resetOnExit = false
  KEEP:   commands.useAccessGroups = false

docker-compose.yaml changes:
  - Remove: ports 0.0.0.0:18789:18789 (or keep as comment — vestigial)
  - No new volumes needed
  - No new services
  - Add env var: TS_AUTHKEY (Coolify secret)
  - Add env var: TS_HOSTNAME=openclaw-server (optional)
  - No cap_add or devices needed (userspace networking)

MacBook connect-mac-node.sh:
  - Update gateway URL from http://192.168.1.100:18789 to https://openclaw-server.tailnet.ts.net
```

**Confidence:** HIGH for architecture; MEDIUM for exact bootstrap.sh tailscale startup details (verified pattern from official guides, not tested).

---

### Revised Common Pitfalls (from gap analysis)

### Pitfall 6: bind=loopback breaks LAN access — Docker port mapping does NOT help
**What goes wrong:** After switching to `bind=loopback`, the MacBook gets "connection refused" on `192.168.1.100:18789` even though docker-compose still has `ports: ["0.0.0.0:18789:18789"]`.
**Why it happens:** Docker port mapping routes traffic to the container's eth0 interface. The openclaw gateway only listens on the container's loopback (127.0.0.1), which is a different interface. The forwarded traffic is rejected at the application level.
**How to avoid:** Accept that bind=loopback means LAN access is gone. MacBook must use Tailscale. Update `connect-mac-node.sh` before deploying.
**Warning signs:** `curl http://192.168.1.100:18789/health` returns "connection refused" after deploy.

### Pitfall 7: tailscaled not started before openclaw when tailscale.mode=serve
**What goes wrong:** OpenClaw crashes at startup with `"tailscale serve failed: dial unix /var/run/tailscale/tailscaled.sock: connect: no such file or directory"` or similar.
**Why it happens:** OpenClaw calls `tailscale serve` which requires a running tailscaled daemon. If bootstrap.sh starts openclaw before tailscaled is ready, the call fails.
**How to avoid:** In bootstrap.sh, start tailscaled AND wait for `tailscale status` to show `BackendState: Running` BEFORE the `exec openclaw gateway run` line.
**Warning signs:** Gateway crash on first deploy; logs show tailscale socket errors.

### Pitfall 8: tailscale state lost on container recreation
**What goes wrong:** After `docker compose down && docker compose up` or a Coolify redeploy that recreates the container, tailscale requires re-authentication.
**Why it happens:** tailscale state is on the openclaw-data volume at `/data/tailscale/`. If the volume is deleted (e.g., `docker compose down -v`), state is lost. Normal redeploys do NOT delete volumes.
**How to avoid:** Never use `-v` with `docker compose down`. Keep TS_AUTHKEY in Coolify env so re-authentication is automatic even if state is lost.
**Warning signs:** `tailscale status` shows "NeedsLogin" after restart.

### Pitfall 9: Control UI HTTPS requires MacBook on tailnet
**What goes wrong:** `allowInsecureAuth: true` in openclaw.json does NOT fix the browser's "secure context" requirement. The browser blocks WebCrypto/other APIs unless the page is served over HTTPS or from localhost.
**Why it happens:** This is a browser security policy, not an openclaw config issue. The `allowInsecureAuth` flag affects authentication token handling, not TLS. `dangerouslyDisableDeviceAuth` is not a valid key and crashes the gateway.
**How to avoid:** After Tailscale Serve is running, Control UI access is via `https://openclaw-server.tailnet.ts.net` — valid HTTPS cert automatically provided by Tailscale. Browser secure context requirement is satisfied.
**Warning signs:** Browser shows "Control UI requires HTTPS or localhost (secure context)" — this is fixed by using the Tailscale HTTPS URL, not by any openclaw config flag.

---

### Updated Don't Hand-Roll

| Problem | Don't Build | Use Instead |
|---------|-------------|-------------|
| tailscale install in Dockerfile | APT repo setup with keyring | `COPY --from=tailscale/tailscale:v1.94.2` |
| tailscaled process supervision in container | nohup/background/systemd | Already background process; Docker container keeps it alive via bootstrap.sh lifecycle |
| Wait for tailscale ready | Custom polling loop | `tailscale status --json \| grep BackendState:Running` (simple 15-iteration loop) |
| HTTPS for Control UI | nginx TLS proxy, self-signed cert | Tailscale Serve provides valid HTTPS automatically |
| Separate tailscale volume | New named volume in docker-compose.yaml | `/data/tailscale/` subdirectory of existing openclaw-data volume |

---

### Updated Sources (Gap Analysis)

### Primary (HIGH confidence)
- `tailscale.com/kb/1107/heroku` — exact `COPY --from=tailscale/tailscale:stable` Dockerfile pattern + start.sh sequence
- `pkgs.tailscale.com/stable/` — current stable version v1.94.2 confirmed
- `docs.docker.com/engine/network/port-publishing/` — Docker port mapping does NOT bypass application loopback binding
- `docs.openclaw.ai/gateway/tailscale` — OpenClaw does NOT start tailscaled; requires pre-running daemon; mode=serve requires bind=loopback
- `tailscale.com/kb/1215/oauth-clients` — OAuth client secret never expires; correct for permanent server

### Secondary (MEDIUM confidence)
- `deepwiki.com/openclaw/openclaw/3.1-gateway-configuration` — tailscale.mode=serve crashes if bind≠loopback (error message confirmed); resetOnExit behavior
- `github.com/openclaw/openclaw/issues/14542` — "gateway.bind should auto-set to loopback when tailscale.mode is serve" — confirms the hard requirement
- `tailscale.com/kb/1085/auth-keys` — reusable key 90-day limit; node persists after key expiry

### Tertiary (LOW confidence — not directly verified)
- Exact tailscale `--state` flag path behavior: inferred from standard tailscaled documentation; not tested in this specific config
- `TS_AUTH_ONCE` environment variable behavior: mentioned in search results but not directly fetched/verified

---

**Gap analysis complete: 2026-02-22**
**Addresses:** Phase 7 implementation gaps for tailscale-install Dockerfile stage, bootstrap.sh startup sequence, config patch changes, port mapping behavior, auth key strategy, and MacBook enrollment.
