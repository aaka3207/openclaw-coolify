---
phase: quick-1
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - SOUL.md
  - BOOTSTRAP.md
  - skills/web-utils/SKILL.md
  - Dockerfile
  - scripts/install-browser-deps.sh
autonomous: true
must_haves:
  truths:
    - "SOUL.md reflects LAN-only deployment with no references to cloudflared or vercel"
    - "SOUL.md uses /data/ paths instead of /root/ or ~/"
    - "SOUL.md documents Memory Architecture (QMD session-level + NOVA long-term)"
    - "BOOTSTRAP.md references correct scraping tools without Cloudflare bypass mentions"
    - "SKILL.md for web-utils no longer lists botasaurus as a dependency"
    - "Dockerfile installs all browser/tool deps that were in install-browser-deps.sh"
    - "Go install in Dockerfile is architecture-aware (amd64/arm64)"
    - "Docker image builds successfully"
  artifacts:
    - path: "SOUL.md"
      provides: "LAN-only agent behavioral rules with memory architecture"
    - path: "BOOTSTRAP.md"
      provides: "Accurate first-boot orientation"
    - path: "skills/web-utils/SKILL.md"
      provides: "Correct dependency listing for web-utils skill"
    - path: "Dockerfile"
      provides: "Self-contained image with all runtime deps baked in"
  key_links:
    - from: "SOUL.md"
      to: "scripts/bootstrap.sh"
      via: "Path references (/data/, /app/scripts/)"
      pattern: "/data/|/app/scripts/"
    - from: "Dockerfile"
      to: "scripts/install-browser-deps.sh"
      via: "Deps moved from post-deploy into image build"
      pattern: "chromium|docker-ce-cli|golang"
---

<objective>
Update SOUL.md, BOOTSTRAP.md, and web-utils SKILL.md to reflect LAN-only reality (remove cloudflared/vercel references, fix paths, add memory architecture). Move all deps from install-browser-deps.sh into the Dockerfile so the image is self-contained.

Purpose: The current docs have stale upstream references to public access tools we removed in Phase 1. The Dockerfile should be self-contained rather than requiring a post-deploy script for essential deps.
Output: Updated SOUL.md, BOOTSTRAP.md, SKILL.md, Dockerfile. install-browser-deps.sh either removed or converted to a thin shim.
</objective>

<execution_context>
@./.claude/get-shit-done/workflows/execute-plan.md
@./.claude/get-shit-done/templates/summary.md
</execution_context>

<context>
@SOUL.md
@BOOTSTRAP.md
@Dockerfile
@scripts/install-browser-deps.sh
@scripts/bootstrap.sh
@skills/web-utils/SKILL.md
@CLAUDE.md
</context>

<tasks>

<task type="auto">
  <name>Task 1: Update SOUL.md and BOOTSTRAP.md for LAN-only reality</name>
  <files>SOUL.md, BOOTSTRAP.md, skills/web-utils/SKILL.md</files>
  <action>
**SOUL.md changes:**

1. **Remove cloudflared references:**
   - Line 127: Remove "developer tools (vercel, cloudflared, uv, etc.)" -- replace with "developer tools (uv, gh, etc.)"
   - Lines 131-148: Remove the "Cloudflare Tunnel (only if requested)" example and the `npm install -g vercel` line from Node/Next.js example
   - Lines 254-263: Rewrite "Public Access Rules" section to reflect LAN-only:
     ```
     ## LAN Access Rules
     - Default: LAN-only access via Coolify reverse proxy
     - No public tunnels or cloud deploys -- this is a home server
     - Sandbox containers are accessible only from the local network
     - Gateway binds to LAN (configured in openclaw.json gateway.bind = "lan")
     ```
   - Lines 280-384: Rewrite "Recovery & Auto-Restart Protocol" section:
     - Remove all references to "Cloudflare tunnels", "public URLs", "tunnel_auto_restart"
     - Remove "Restart Cloudflare tunnels" and "Extract new public URLs" from recovery steps
     - Keep: container recovery, service process restart, health monitoring
     - Update state schema example to remove `public_url` and `tunnel_auto_restart` fields
     - Recovery script responsibilities: remove tunnel-related items

2. **Fix paths -- replace ~ and /root/ with /data/:**
   - Line 189: `~/.openclaw/state/sandboxes.json` -> `/data/.openclaw/state/sandboxes.json`
   - Line 194: `~/.openclaw/state/sandboxes.json` -> `/data/.openclaw/state/sandboxes.json`
   - Line 300: `~/.openclaw/state/sandboxes.json` -> `/data/.openclaw/state/sandboxes.json`
   - Line 328: same pattern
   - Any other `~/` references -> `/data/`

3. **Add Memory Architecture section** after the "Web Operations Protocol" section (after line 279), before Recovery:
   ```
   ## Memory Architecture

   OpenClaw uses a two-tier memory system:

   **Session-Level (QMD):**
   - In-session context via qmd (bun global package)
   - Tracks conversation flow, working memory, session artifacts
   - Ephemeral -- scoped to the current session

   **Long-Term (NOVA Memory):**
   - PostgreSQL-backed persistent memory via NOVA Memory system
   - Stores: entities, relationships, facts, session summaries
   - Processes session transcripts every 5 minutes via cron catch-up
   - Location: /data/clawd/nova-memory/
   - Status: Infrastructure deployed, hook-based real-time capture blocked
     (OpenClaw 2026.2.13 does not implement message:received hook event)
   ```

4. **Line 172**: Remove the warning about not exposing ports via -p. Replace with:
   `Note: Sandbox containers are accessible via the Docker network. No port publishing (-p) needed -- Coolify handles routing.`

5. **State schema (lines 204-219)**: Remove `public` field from the example. Keep the rest.

**BOOTSTRAP.md changes:**

- Line 23: Replace the entire line with:
  `- **Deep Scrape**: Use `/app/skills/web-utils/scripts/scrape.sh` for web_fetch (supports curl and headless browser modes).`
  Remove the botasaurus/Cloudflare bypass reference entirely.

**skills/web-utils/SKILL.md changes:**

- Remove the `botasaurus` entry from the `install` list in the frontmatter (lines 13-16)
- Remove the `@steipete/summarize` entry (line 11-12) -- summarize.sh uses a different approach now
- Update `requires.bins` if needed to reflect actual dependencies
  </action>
  <verify>
Run these checks:
```bash
# No cloudflare references remaining
grep -i -c 'cloudflare\|cloudflared\|tunnel' SOUL.md  # should be 0
grep -i -c 'cloudflare\|botasaurus' BOOTSTRAP.md  # should be 0

# No vercel references remaining
grep -i -c 'vercel' SOUL.md  # should be 0

# No /root/ or bare ~/ paths
grep -c '/root/' SOUL.md  # should be 0
grep -cP '~/(?!\.)' SOUL.md  # should be 0 (allow ~/.openclaw style -> but those should be /data/.openclaw)

# Memory Architecture section exists
grep -c 'Memory Architecture' SOUL.md  # should be >= 1

# SKILL.md no longer references botasaurus
grep -c 'botasaurus' skills/web-utils/SKILL.md  # should be 0
```
  </verify>
  <done>
SOUL.md is fully updated for LAN-only with correct /data/ paths, no cloudflared/vercel references, and includes Memory Architecture section. BOOTSTRAP.md has no stale botasaurus/cloudflare references. SKILL.md lists only actual dependencies.
  </done>
</task>

<task type="auto">
  <name>Task 2: Move install-browser-deps.sh contents into Dockerfile</name>
  <files>Dockerfile, scripts/install-browser-deps.sh</files>
  <action>
**Dockerfile restructure -- add a new `browser-deps` stage between `runtimes` and `dependencies`:**

```dockerfile
# Stage 2.5: Browser and tool dependencies (rarely changes, large layer)
FROM runtimes AS browser-deps

# System packages for browser automation and document processing
RUN apt-get update && apt-get install -y --no-install-recommends \
    chromium \
    ffmpeg \
    imagemagick \
    pandoc \
    poppler-utils \
    graphviz \
    && rm -rf /var/lib/apt/lists/*

# Docker CE CLI (for sandbox management via docker-proxy)
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y docker-ce-cli && \
    rm -rf /var/lib/apt/lists/*

# Go (architecture-aware install with SHA256 verification)
ARG GO_VERSION=1.23.4
ARG GO_SHA256_AMD64=6924efde5de86fe277676e929dc9917d466efa02fb934197bc2eba35d5680971
ARG GO_SHA256_ARM64=16e5017863a7f6071f8f4f0c29a19f3b3c97f01a8e30e99901c4f00ef0195d47
RUN GO_ARCH=$(dpkg --print-architecture) && \
    if [ "$GO_ARCH" = "amd64" ]; then GO_SHA256="$GO_SHA256_AMD64"; \
    elif [ "$GO_ARCH" = "arm64" ]; then GO_SHA256="$GO_SHA256_ARM64"; \
    else echo "Unsupported architecture: $GO_ARCH" && exit 1; fi && \
    curl -L "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" -o /tmp/go.tar.gz && \
    echo "${GO_SHA256}  /tmp/go.tar.gz" | sha256sum -c - && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && \
    rm /tmp/go.tar.gz

# GitHub CLI
RUN mkdir -p -m 755 /etc/apt/keyrings && \
    wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null && \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && \
    apt-get install -y gh && \
    rm -rf /var/lib/apt/lists/*

# uv (Python tool manager, pinned version)
ARG UV_VERSION=0.5.14
RUN curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" -o /tmp/uv-install.sh && \
    UV_INSTALL_DIR="/usr/local/bin" sh /tmp/uv-install.sh && rm /tmp/uv-install.sh

# Python packages for web scraping and document processing
# NOTE: botasaurus removed (CF bypass tool), browser-use kept for AI-driven scraping
RUN pip3 install --break-system-packages \
    ipython csvkit openpyxl python-docx pypdf \
    browser-use playwright

# Playwright system deps (installs browser support libraries for chromium)
RUN playwright install-deps
```

**Update `dependencies` stage** to inherit from `browser-deps` instead of `runtimes`:
```dockerfile
FROM browser-deps AS dependencies
```

**Update final stage PATH** to include Go:
Add `/usr/local/go/bin` to the ENV PATH line (line 109).

**Do NOT include:**
- `botasaurus` python package (CF bypass tool, removed in security hardening)
- `claude CLI` install (`curl -fsSL https://claude.ai/install.sh`) -- OpenClaw already provides Claude capabilities; the symlink at line 98 handles the claude binary if user installs it manually to /data/.claude/bin/
- `@steipete/summarize` bun package -- summarize.sh handles this differently

**DO include the bun packages in `dependencies` stage** (after openclaw install, as openclaw user context):
Add after the openclaw install block:
```dockerfile
# Bun global packages (qmd for session memory, hyperbrowser for web agent)
RUN --mount=type=cache,target=/data/.bun/install/cache \
    bun install -g https://github.com/tobi/qmd && \
    bun install -g @hyperbrowser/agent
```

**Update `scripts/install-browser-deps.sh`:** Replace contents with a message explaining deps are now baked into the Docker image:
```bash
#!/usr/bin/env bash
echo "All browser dependencies are now baked into the Docker image."
echo "This script is no longer needed. See Dockerfile stages: base -> runtimes -> browser-deps -> dependencies -> final"
exit 0
```

**Also update bootstrap.sh** lines 194-200: Remove the conditional docker CLI check that skips sandbox setup. Since docker CLI is now in the image, the check is unnecessary. Change to:
```bash
# Sandbox setup (docker CLI is baked into image)
[ -f scripts/sandbox-setup.sh ] && bash scripts/sandbox-setup.sh
[ -f scripts/sandbox-browser-setup.sh ] && bash scripts/sandbox-browser-setup.sh
```
  </action>
  <verify>
```bash
# Build the Docker image (this is the real test)
cd /Users/ameerakashe/Documents/repos/openclaw-coolify && docker build -t openclaw-test .

# If build succeeds, verify key binaries exist in the image
docker run --rm openclaw-test which docker   # should return /usr/bin/docker or similar
docker run --rm openclaw-test which go       # should return /usr/local/go/bin/go
docker run --rm openclaw-test which gh       # should return path to gh
docker run --rm openclaw-test which chromium # should return path to chromium
docker run --rm openclaw-test python3 -c "import playwright; print('ok')"
docker run --rm openclaw-test uv --version

# Verify Go architecture detection works
docker run --rm openclaw-test go version

# Verify botasaurus is NOT installed
docker run --rm openclaw-test python3 -c "import botasaurus" 2>&1 | grep -q "ModuleNotFoundError"

# Clean up
docker rmi openclaw-test
```
  </verify>
  <done>
Dockerfile builds successfully with all browser/tool deps baked in. Go install is architecture-aware. install-browser-deps.sh is replaced with a no-op message. bootstrap.sh no longer conditionally skips sandbox setup based on docker CLI presence. No botasaurus or cloudflare bypass tools included.
  </done>
</task>

<task type="auto">
  <name>Task 3: Verify ARM64 Go checksum and update CLAUDE.md</name>
  <files>Dockerfile, CLAUDE.md</files>
  <action>
**Verify the ARM64 Go checksum** by fetching it from the official Go downloads page:
```bash
curl -sL "https://go.dev/dl/?mode=json" | jq -r '.[] | select(.version == "go1.23.4") | .files[] | select(.os == "linux" and .arch == "arm64") | .sha256'
```
Update the `GO_SHA256_ARM64` ARG in the Dockerfile with the verified value. If the JSON API does not return results, fetch the checksum from `https://go.dev/dl/go1.23.4.linux-arm64.tar.gz.sha256` or the Go downloads page.

**Update CLAUDE.md:**
- In "Key Files" table, add entry for `scripts/install-browser-deps.sh` noting it is "Deprecated -- deps baked into Dockerfile"
- In "Architecture Notes" section, add a bullet: "Browser deps (chromium, docker CLI, Go, gh, uv, playwright) are baked into the Docker image via the `browser-deps` build stage. The post-deploy script `install-browser-deps.sh` is no longer needed."
- Update the "Testing After Changes" section to add: `8. Verify docker image builds: docker build -t openclaw-test .`
  </action>
  <verify>
```bash
# Verify the ARM64 checksum was fetched and is a valid 64-char hex string
grep 'GO_SHA256_ARM64' Dockerfile | grep -E '[a-f0-9]{64}'

# Verify CLAUDE.md mentions browser-deps stage
grep -c 'browser-deps' CLAUDE.md  # should be >= 1

# Verify no stale references to install-browser-deps as "required"
grep -c 'run post-deploy\|run install-browser' CLAUDE.md  # should be 0
```
  </verify>
  <done>
ARM64 Go checksum is verified and correct in Dockerfile. CLAUDE.md reflects the new Dockerfile architecture with browser-deps stage and marks install-browser-deps.sh as deprecated.
  </done>
</task>

</tasks>

<verification>
Full verification after all tasks:
1. `grep -ri 'cloudflare\|cloudflared\|vercel' SOUL.md BOOTSTRAP.md` returns nothing
2. `grep -r 'botasaurus' SOUL.md BOOTSTRAP.md skills/web-utils/SKILL.md` returns nothing
3. `grep '/root/' SOUL.md` returns nothing
4. `grep 'Memory Architecture' SOUL.md` returns a match
5. `docker build -t openclaw-test .` succeeds
6. Key binaries (docker, go, gh, chromium, uv) present in image
7. Go is architecture-aware in Dockerfile (dpkg --print-architecture pattern)
</verification>

<success_criteria>
- SOUL.md is LAN-only, /data/-pathed, cloudflare-free, and includes Memory Architecture
- BOOTSTRAP.md has no stale references
- SKILL.md lists only real dependencies
- Dockerfile is self-contained with all deps baked in (no post-deploy script needed)
- Go install handles both amd64 and arm64 with verified checksums
- Docker image builds successfully
</success_criteria>

<output>
After completion, create `.planning/quick/1-update-soul-md-bootstrap-md-web-utils-sk/1-SUMMARY.md`
</output>
