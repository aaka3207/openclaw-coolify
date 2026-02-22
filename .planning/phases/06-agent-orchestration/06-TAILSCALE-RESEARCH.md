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

## Decision Summary: Tailscale for This Deployment

| Question | Answer | Confidence |
|----------|--------|-----------|
| Is Tailscale needed for sub-agent spawning? | **No** — loopback patch already solves it | HIGH |
| Would `gateway.bind=tailnet` solve sub-agents without loopback patch? | Likely no — Tailscale IPs probably not whitelisted by `isSecureWebSocketUrl` | MEDIUM |
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
