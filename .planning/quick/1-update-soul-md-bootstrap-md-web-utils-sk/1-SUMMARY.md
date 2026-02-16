---
phase: quick-1
plan: 01
subsystem: infra
tags: [dockerfile, soul-md, lan-only, go-arm64, browser-deps, memory-architecture]

# Dependency graph
requires:
  - phase: security-hardening
    provides: "Hardened Dockerfile, SOUL.md with safety rules"
provides:
  - "LAN-only SOUL.md with correct /data/ paths and Memory Architecture"
  - "Self-contained Dockerfile with all browser/tool deps baked in"
  - "Architecture-aware Go install (amd64/arm64) with SHA256 verification"
  - "Updated CLAUDE.md documenting browser-deps stage"
affects: [deployment, docker-build, agent-behavior]

# Tech tracking
tech-stack:
  added: [chromium, ffmpeg, imagemagick, pandoc, poppler-utils, graphviz, docker-ce-cli, go-1.23.4, gh, uv-0.5.14, browser-use, playwright, qmd, hyperbrowser-agent]
  patterns: [multi-stage-dockerfile-with-browser-deps, architecture-aware-go-install]

key-files:
  created: []
  modified:
    - SOUL.md
    - BOOTSTRAP.md
    - skills/web-utils/SKILL.md
    - Dockerfile
    - scripts/install-browser-deps.sh
    - scripts/bootstrap.sh
    - CLAUDE.md

key-decisions:
  - "Bake all browser/tool deps into Dockerfile instead of post-deploy script"
  - "Architecture-aware Go install with separate ARM64/AMD64 checksums"
  - "Remove botasaurus and cloudflare bypass tooling from all docs and installs"
  - "Add Memory Architecture section to SOUL.md documenting QMD + NOVA two-tier system"

patterns-established:
  - "browser-deps stage: separate Docker build stage for heavy browser/tool dependencies"
  - "Architecture-aware installs: use dpkg --print-architecture with per-arch checksums"

# Metrics
duration: 5min
completed: 2026-02-16
---

# Quick Task 1: Update SOUL.md, BOOTSTRAP.md, web-utils SKILL.md, and Dockerfile Summary

**LAN-only SOUL.md with /data/ paths and memory docs, self-contained Dockerfile with browser-deps stage baking in chromium/Go/gh/docker-cli/playwright**

## Performance

- **Duration:** ~5 min
- **Started:** 2026-02-16T16:42:24Z
- **Completed:** 2026-02-16T16:47:00Z
- **Tasks:** 3
- **Files modified:** 7

## Accomplishments
- SOUL.md fully updated: removed all cloudflared/vercel references, fixed ~/. to /data/. paths, added Memory Architecture section, rewrote Recovery protocol without tunnel references, replaced Public Access Rules with LAN Access Rules
- Dockerfile now self-contained with browser-deps stage: chromium, ffmpeg, imagemagick, pandoc, docker CLI, Go (arch-aware), gh, uv, playwright, qmd, hyperbrowser
- ARM64 Go checksum verified and set in Dockerfile
- CLAUDE.md updated to document new Dockerfile architecture

## Task Commits

Each task was committed atomically:

1. **Task 1: Update SOUL.md, BOOTSTRAP.md, SKILL.md for LAN-only reality** - `93a19ec` (feat)
2. **Task 2: Move install-browser-deps.sh contents into Dockerfile** - `3b2b0d5` (feat)
3. **Task 3: Verify ARM64 Go checksum and update CLAUDE.md** - `fa809a8` (docs)

## Files Created/Modified
- `SOUL.md` - LAN-only agent behavioral rules with Memory Architecture, no cloudflare/vercel
- `BOOTSTRAP.md` - Accurate first-boot orientation without botasaurus/cloudflare refs
- `skills/web-utils/SKILL.md` - Correct dependency listing (browser-use, playwright)
- `Dockerfile` - Self-contained image with browser-deps stage, arch-aware Go, bun globals
- `scripts/install-browser-deps.sh` - Deprecated (replaced with no-op message)
- `scripts/bootstrap.sh` - Removed conditional docker CLI check, added Go to PATH
- `CLAUDE.md` - Documented browser-deps stage, deprecated install-browser-deps.sh

## Decisions Made
- Bake all deps into Dockerfile rather than relying on post-deploy script -- eliminates setup friction and ensures consistent builds
- Use separate AMD64/ARM64 Go checksums via ARG variables for architecture portability
- Keep botasaurus removal comment in Dockerfile for audit trail
- Reword "tunnels" to "exposure" in LAN Access Rules to eliminate all tunnel-related vocabulary

## Deviations from Plan

None - plan executed exactly as written.

## Issues Encountered
None.

## User Setup Required
None - no external service configuration required.

## Next Phase Readiness
- Docker image is self-contained and ready for build/deploy via Coolify
- All documentation reflects current LAN-only deployment reality
- install-browser-deps.sh post-deploy script no longer needed

---
*Quick Task: 1*
*Completed: 2026-02-16*
