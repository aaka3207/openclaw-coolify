# OpenClaw-Coolify Security Audit Report

**Target**: essamamdani/openclaw-coolify (upstream, pre-hardening)
**Date**: 2026-02-14
**Auditor**: Claude Code (Opus 4.6)
**Scope**: Full stack — Docker composition, shell scripts, AI agent configuration, web scraping, sandbox management

---

## Executive Summary

The OpenClaw-Coolify stack provides an AI-powered development agent with Docker sandbox capabilities. The audit identified **12 CRITICAL**, **9 HIGH**, and **6 MEDIUM** severity findings. The most significant risk is a **composite attack chain**: AI agent prompt injection -> credential theft -> recovery script modification -> persistent cron execution -> privileged container creation -> full host compromise.

---

## Findings by Severity

### CRITICAL (12)

#### C1: Docker Socket Proxy Over-Permissioned
- **File**: `docker-compose.yaml`
- **Issue**: `POST: 1` grants global write access to Docker API, bypassing all granular permissions. Combined with `EXEC: 1`, allows arbitrary command execution in any container on the host.
- **Impact**: Full container escape. Attacker can `docker exec` into Coolify containers, create privileged containers with host filesystem mounts, stop/remove infrastructure containers.
- **Fix Applied**: Removed `POST: 1`, `EXEC: 1`, `NETWORKS: 1`. Kept granular `CONTAINERS: 1`, `IMAGES: 1`, added `VOLUMES: 1`.

#### C2: Wildcard Trusted Proxies
- **File**: `docker-compose.yaml`
- **Issue**: `GATEWAY_TRUSTED_PROXIES: '*'` trusts all IP addresses for proxy headers (X-Forwarded-For, X-Real-IP).
- **Impact**: Any internet source can spoof their IP address, bypassing IP-based access controls and audit logging.
- **Fix Applied**: Restricted to `172.16.0.0/12,192.168.100.0/24` (Docker internal + user's LAN).

#### C3: SQL Injection in Shell Scripts
- **Files**: `skills/sandbox-manager/scripts/create_sandbox.sh`, `delete_sandbox.sh`, `db.sh`
- **Issue**: User-controlled input (sandbox names, stack names, ports) interpolated directly into SQLite3 queries without sanitization.
- **Impact**: Arbitrary SQL execution. Attacker can read/modify/delete all sandbox records, potentially inject shell commands via SQLite `.system`.
- **Fix Applied**: Added `sanitize_sql()`, `validate_identifier()`, `validate_port()` functions in `db.sh`. All inputs validated and sanitized before query construction.

#### C4: SSRF in Web Scraping
- **File**: `skills/web-utils/scripts/scrape.sh`
- **Issue**: No URL validation. AI agent can scrape internal Docker hostnames (`docker-proxy`, `registry`, `searxng`), private IPs, and cloud metadata endpoints (`169.254.169.254`).
- **Impact**: Access to Docker API via proxy, internal service enumeration, cloud credential theft via metadata endpoint, internal network mapping.
- **Fix Applied**: Added `validate_url()` with blocked hostnames, private IP ranges, and DNS rebinding protection (resolves hostname and checks resolved IP).

#### C5: Cloudflare Bypass in Scraper
- **File**: `skills/web-utils/scripts/scrape_botasaurus.py`
- **Issue**: `bypass_cloudflare=True` and `google_get()` function designed to circumvent security controls.
- **Impact**: Legal liability, ToS violations, potential IP banning. Signals intent to bypass security measures.
- **Fix Applied**: Removed `bypass_cloudflare=True`, replaced `google_get` with standard `driver.get(url)`.

#### C6: Prompt Injection Vulnerability in AI Agent
- **File**: `SOUL.md`
- **Issue**: Contains a "Force" bypass mechanism allowing users to override safety constraints. Forbidden targets list uses relative paths easily circumvented by symlinks.
- **Impact**: AI agent can be socially engineered to access credentials, modify system files, execute arbitrary Docker commands beyond intended scope.
- **Fix Applied**: Removed "Force" bypass entirely. Changed forbidden paths to absolute (`/data/.openclaw/`, `/app/scripts/`). Hardened system prompt.

#### C7: Credentials Exposed in Environment
- **File**: `scripts/bootstrap.sh`
- **Issue**: `GITHUB_TOKEN`, `VERCEL_TOKEN`, `CF_TUNNEL_TOKEN` remain in environment after use. Any process or AI agent with `env` access can read all credentials.
- **Impact**: Credential theft via `printenv`, `/proc/self/environ`, or AI agent prompt injection.
- **Fix Applied**: Credentials written to individual files in `$OPENCLAW_STATE/credentials/` (chmod 600), then `unset` from environment.

#### C8: Auth Token Printed to Stdout
- **File**: `scripts/bootstrap.sh`
- **Issue**: Access token displayed via `echo` to container logs, visible in Coolify dashboard, Docker logs, and any log aggregation.
- **Impact**: Token exposure to anyone with log access. Persistent in log files.
- **Fix Applied**: Token written to `$OPENCLAW_STATE/access.txt` (chmod 600) instead of stdout.

#### C9: Recovery Scripts Writable by AI Agent
- **Files**: `scripts/recover_sandbox.sh`, `scripts/monitor_sandbox.sh`
- **Issue**: Recovery scripts copied to workspace directory (`$WORKSPACE_DIR`) where the AI agent has write access, then executed by bootstrap with elevated context.
- **Impact**: AI agent modifies recovery script -> script runs on next container restart -> persistent code execution outside sandbox.
- **Fix Applied**: Recovery scripts run from `/app/scripts/` (read-only, owned by root). Old copies in workspace are deleted.

#### C10: No Container Validation in Recovery
- **File**: `scripts/recover_sandbox.sh`
- **Issue**: Recovery script restarts containers based on database records without verifying the container is actually managed by OpenClaw.
- **Impact**: If an attacker injects a container ID into the database (via SQL injection or direct DB access), recovery script will start arbitrary containers.
- **Fix Applied**: Added `validate_container_id()` (format check) and `verify_managed_container()` (checks `openclaw.managed=true` label).

#### C11: Unpinned Base Images and Dependencies
- **File**: `Dockerfile`
- **Issue**: No version pinning for Go, uv, Bun. `NPM_CONFIG_UNSAFE_PERM=true` allows npm scripts to run as root.
- **Impact**: Supply chain attack. Compromised upstream package installs malware during build. Unsafe perm allows npm lifecycle scripts to modify system files.
- **Fix Applied**: Pinned Go 1.23.4 with SHA256 verification, uv 0.5.14, Bun 1.1.42. Removed `NPM_CONFIG_UNSAFE_PERM=true`.

#### C12: Container Runs as Root
- **File**: `Dockerfile`
- **Issue**: No `USER` directive. Container processes run as root inside the container.
- **Impact**: If any container escape occurs, attacker has root on the host (with Docker socket access). Root inside container can modify any file including scripts.
- **Fix Applied**: Created `openclaw` user/group. `/app/scripts/` owned by root (read-only). `/data/` owned by openclaw. `USER openclaw` directive added.

### HIGH (9)

#### H1: No Network Segmentation
- **File**: `docker-compose.yaml`
- **Issue**: All services on the default bridge network. Every container can reach every other container.
- **Impact**: Compromised sandbox can directly access docker-proxy, SearXNG admin interface, registry, and gateway.
- **Fix Applied**: Created `internal` (no internet) and `proxy` networks. Docker-proxy on internal only. Services assigned to appropriate networks.

#### H2: Unsanitized Container Labels
- **File**: `skills/sandbox-manager/scripts/create_sandbox.sh`
- **Issue**: User-provided sandbox title used in container name and labels without sanitization.
- **Impact**: Docker API injection via crafted container names, potential command injection.
- **Fix Applied**: Input validated with `validate_identifier()` before use in Docker commands. Added `openclaw.managed=true` label for provenance tracking.

#### H3: SearXNG Unpinned Image
- **File**: `searxng/Dockerfile`
- **Issue**: Base image not pinned to specific version/digest.
- **Impact**: Supply chain risk — compromised upstream image affects all rebuilds.
- **Fix Applied**: Pinned to `searxng/searxng:2026.2.13-97e572728`.

#### H4: Browser-Use Agent Prompt Injection
- **File**: `skills/web-utils/scripts/scrape_browser_use.py`
- **Issue**: AI-driven browser agent receives user-controlled task prompts without injection protection.
- **Impact**: Malicious web content could hijack the browser agent to navigate to internal services, exfiltrate data, or perform unintended actions.
- **Fix Applied**: Hardened system prompt with injection-resistant instructions. Agent told to ignore embedded instructions in web content.

#### H5: Insecure CLI Installation Pattern
- **File**: `Dockerfile`
- **Issue**: `curl | sh` pattern for Claude and Kimi CLI installation. Downloads and immediately executes untrusted code.
- **Impact**: MITM or compromised CDN serves malicious installer.
- **Fix Applied**: Changed to download-then-execute pattern (download to file, then execute). Combined with pinned versions.

#### H6: Docker-Proxy Internet Access
- **File**: `docker-compose.yaml`
- **Issue**: Docker-proxy container on default network has internet access.
- **Impact**: If proxy is compromised, it can exfiltrate data or receive C2 commands.
- **Fix Applied**: Moved to `internal` network (no internet route).

#### H7: Excessive SearXNG Permissions
- **File**: `searxng/Dockerfile`
- **Issue**: `chown -R searxng:searxng /etc/ssl/certs` gives SearXNG ownership of system SSL certificates.
- **Impact**: SearXNG process can replace CA certificates, enabling MITM of HTTPS connections from the container.
- **Fix Applied**: Removed the `chown` command.

#### H8: Monitor Script Path Traversal
- **File**: `scripts/monitor_sandbox.sh`
- **Issue**: References recovery script by relative/workspace path that AI agent can modify.
- **Impact**: AI agent replaces recovery script, monitor executes malicious version on next health check cycle.
- **Fix Applied**: Changed `RECOVERY_SCRIPT` to absolute path `/app/scripts/recover_sandbox.sh`.

#### H9: No Approval Gate for Destructive Operations
- **File**: Bootstrap flow
- **Issue**: No mechanism for human approval before destructive operations (deployments, deletions).
- **Fix Applied**: Added `scripts/openclaw-approve.sh` with interactive confirmation and `OPENCLAW_AUTO_APPROVE_FIRST` env var for initial headless setup.

### MEDIUM (6)

#### M1: Bash History Excessive Size
- **File**: `scripts/bootstrap.sh`
- **Issue**: `HISTSIZE=50000` and `HISTFILESIZE=50000` — 50K lines of command history persisted.
- **Impact**: Credential leakage if secrets are ever typed in commands. Large attack surface for history-based reconnaissance.

#### M2: Permissive CORS Configuration
- **File**: Gateway configuration
- **Issue**: CORS headers may be overly permissive depending on gateway config.
- **Impact**: Cross-origin attacks against the OpenClaw web interface.

#### M3: No Rate Limiting on API
- **File**: Gateway/bootstrap configuration
- **Issue**: No rate limiting on the authenticated API endpoints.
- **Impact**: Brute-force attacks against auth tokens, resource exhaustion.

#### M4: Debug/Development Artifacts
- **Files**: Various
- **Issue**: Development-oriented configurations left in production (verbose logging, debug endpoints).
- **Impact**: Information disclosure, expanded attack surface.

#### M5: No TLS Between Internal Services
- **File**: `docker-compose.yaml`
- **Issue**: All inter-service communication is plaintext HTTP.
- **Impact**: On a shared Docker host, another container on the same network could sniff traffic.

#### M6: Large Attack Surface from Dependencies
- **File**: `Dockerfile`
- **Issue**: Chromium, Playwright, multiple Python packages, Node.js, Go, Bun — massive dependency tree.
- **Impact**: Each dependency is a potential vulnerability. Large image size increases build time and storage.

---

## Composite Attack Chain

The most concerning finding is the combination of vulnerabilities enabling a full host compromise:

```
1. Prompt Injection (C6)
   AI agent receives crafted input exploiting "Force" bypass

2. Credential Theft (C7)
   Agent reads credentials from environment via printenv/env

3. Script Modification (C9)
   Agent modifies recover_sandbox.sh in workspace directory

4. Persistent Execution (C9 + H8)
   Modified recovery script executes on next container restart
   Recovery script contains: docker run --privileged -v /:/host ...

5. Container Escape (C1)
   POST:1 + EXEC:1 on docker-proxy allows creating privileged containers

6. Host Compromise
   Privileged container with host filesystem mount = root on host
```

**Post-Hardening**: This chain is broken at steps 1 (Force bypass removed), 2 (credentials isolated to files), 3 (scripts run from read-only /app/scripts/), and 5 (POST and EXEC disabled on proxy).

---

## Hardening Summary

All CRITICAL and HIGH findings have been remediated across 3 commits:
1. **Phase 1-4 implementation**: Core hardening across 15+ files
2. **SearXNG image fix**: Pinned to valid Docker Hub tag
3. **Go checksum + volume cleanup**: Verified SHA256, removed conflicting /root/ mounts

See `CLAUDE.md` in repo root for implementation details and testing checklist.
