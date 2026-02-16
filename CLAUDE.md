# OpenClaw-Coolify Security Hardening

## Project Overview
Forked from `essamamdani/openclaw-coolify`. This fork applies security hardening to address critical vulnerabilities identified in a comprehensive security audit.

**Deployment target**: Coolify self-hosted

## Security Hardening Progress

### Phase 1: Critical Fixes
- [x] Lock down Docker socket proxy (remove POST, EXEC, NETWORKS overrides)
- [x] Fix SQL injection in sandbox manager (sanitize/validate inputs in db.sh)
- [x] Move recovery scripts out of agent-writable workspace
- [x] Stop printing auth token to stdout/logs
- [x] Remove "Force" bypass from SOUL.md

### Phase 2: High-Severity Fixes
- [x] Add SSRF protection to web scraping (scrape.sh URL validation)
- [x] Validate container IDs in recovery script
- [x] Fix GATEWAY_TRUSTED_PROXIES (change from '*' to Docker CIDR)
- [x] Harden device approval (openclaw-approve.sh)
- [x] Harden browser-use scraper against prompt injection
- [x] Remove Cloudflare bypass tooling
- [x] Pin SearXNG base image

### Phase 3: Dockerfile Hardening
- [x] Add non-root runtime user
- [x] Pin install versions + integrity checks (Go checksum, uv, bun)
- [x] Remove NPM_CONFIG_UNSAFE_PERM

### Phase 4: Cleanup & Network Isolation
- [x] Add Docker network isolation (internal + proxy networks)
- [x] Isolate deployment credentials (write to files, unset from env)
- [x] Fix SearXNG settings (safe_search: 1)
- [x] Remove .DS_Store from repo

## Architecture Notes

- **Docker socket proxy** (`tecnativa/docker-socket-proxy:0.2.0`): Mediates all Docker API access. Allows CONTAINERS + IMAGES + VOLUMES for sandbox creation. EXEC and global POST are disabled.
- **Recovery scripts**: Execute from `/app/scripts/` (image path, read-only), never from workspace.
- **Credentials**: Core AI keys (OPENAI, ANTHROPIC) stay as env vars. Deployment tokens (VERCEL, CF_TUNNEL) are written to credential files at boot and unset from environment.
- **SOUL.md**: Behavioral constraints for the AI agent. Prose-only, not technically enforced. The "Force" bypass has been removed. Forbidden targets are absolute.
- **Network isolation**: `internal` network (no external access) for docker-proxy, searxng, registry. `proxy` network for openclaw outbound API calls.
- **Non-root**: Container runs as `openclaw` user. Scripts in `/app/scripts/` are owned by root (read-only to openclaw).
- **Browser deps**: Chromium, docker CLI, Go, gh, uv, playwright are baked into the Docker image via the `browser-deps` build stage. The post-deploy script `install-browser-deps.sh` is no longer needed.

## Key Files

| File | Purpose |
|------|---------|
| `docker-compose.yaml` | Service definitions, proxy config, networks |
| `Dockerfile` | Multi-stage build, runtime user, install pins |
| `scripts/bootstrap.sh` | Container entrypoint, config generation, credential isolation |
| `scripts/recover_sandbox.sh` | Sandbox recovery with container ID validation |
| `scripts/monitor_sandbox.sh` | 5-min health check loop (references /app/scripts/) |
| `scripts/openclaw-approve.sh` | Device approval with interactive confirmation |
| `skills/sandbox-manager/scripts/db.sh` | SQLite helper with sanitize_sql/validate_identifier |
| `skills/sandbox-manager/scripts/create_sandbox.sh` | Sandbox creation with input validation |
| `skills/sandbox-manager/scripts/delete_sandbox.sh` | Sandbox deletion with input validation |
| `skills/web-utils/scripts/scrape.sh` | Web scraping with SSRF protection |
| `skills/web-utils/scripts/scrape_botasaurus.py` | Browser scraping (CF bypass removed) |
| `skills/web-utils/scripts/scrape_browser_use.py` | AI scraper (injection-hardened prompt) |
| `scripts/install-browser-deps.sh` | Deprecated -- deps baked into Dockerfile |
| `SOUL.md` | AI agent behavioral rules (no bypass mechanism) |

## Testing After Changes

1. Deploy to Coolify, confirm gateway starts
2. Create sandbox: `create_sandbox.sh --stack nextjs --title "test"`
3. Verify `docker exec` from openclaw container fails
4. Verify auth token not in `docker logs`
5. Verify SSRF blocked: `scrape.sh http://docker-proxy:2375/`
6. Verify SQL injection blocked: title with `'; DROP TABLE` rejected
7. Verify recovery rejects non-openclaw container IDs
8. Verify `openclaw-approve` prompts for confirmation
9. Verify docker image builds: `docker build -t openclaw-test .`
