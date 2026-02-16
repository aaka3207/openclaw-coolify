# syntax=docker/dockerfile:1
# Multi-stage build for optimal caching with BuildKit
# Each stage builds on the previous, with COPY . . only in the final stage
# BuildKit features: cache mounts, parallel builds, improved layer caching

# Stage 1: Base system dependencies (rarely changes)
FROM node:lts-bookworm-slim AS base

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive \
    PIP_ROOT_USER_ACTION=ignore

# Install Core & Power Tools + Docker CLI (client only)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    wget \
    git \
    build-essential \
    software-properties-common \
    python3 \
    python3-pip \
    python3-venv \
    jq \
    lsof \
    openssl \
    ca-certificates \
    gnupg \
    ripgrep fd-find fzf bat \
    sqlite3 \
    pass \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Stage 2: Language runtimes and package managers
FROM base AS runtimes

ENV BUN_INSTALL_NODE=0 \
    BUN_INSTALL="/data/.bun" \
    PATH="/data/.bun/bin:/data/.bun/install/global/bin:$PATH"

# Install Bun (pinned version)
ARG BUN_VERSION=1.1.42
RUN curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}"

# Configure QMD Persistence
ENV XDG_CACHE_HOME="/data/.cache"

# Debian aliases
RUN ln -s /usr/bin/fdfind /usr/bin/fd || true && \
    ln -s /usr/bin/batcat /usr/bin/bat || true

# Stage 3: Application dependencies (package installations)
FROM runtimes AS dependencies

# OpenClaw install
ARG OPENCLAW_BETA=false
ENV OPENCLAW_BETA=${OPENCLAW_BETA} \
    OPENCLAW_NO_ONBOARD=1

# Install ClawHub with BuildKit cache mount for faster rebuilds
RUN --mount=type=cache,target=/data/.bun/install/cache \
    bun install -g clawhub

# Install OpenClaw with npm cache mount
RUN --mount=type=cache,target=/data/.npm \
    if [ "$OPENCLAW_BETA" = "true" ]; then \
    npm install -g openclaw@beta; \
    else \
    npm install -g openclaw@2026.2.13; \
    fi && \
    if command -v openclaw >/dev/null 2>&1; then \
    echo "✅ openclaw binary found"; \
    else \
    echo "❌ OpenClaw install failed (binary 'openclaw' not found)"; \
    exit 1; \
    fi

# Stage 4: Final application stage (changes frequently)
FROM dependencies AS final

WORKDIR /app

# Copy everything (obeying .dockerignore)
# This is the only layer that changes on code updates
COPY . .

# Install cron + BWS CLI (in final stage to preserve cached base layers)
ARG BWS_VERSION=1.0.0
RUN apt-get update && apt-get install -y --no-install-recommends cron postgresql-client && rm -rf /var/lib/apt/lists/* && \
    BWS_ARCH=$(dpkg --print-architecture) && \
    if [ "$BWS_ARCH" = "amd64" ]; then BWS_ARCH="x86_64"; fi && \
    curl -fsSL "https://github.com/bitwarden/sdk-sm/releases/download/bws-v${BWS_VERSION}/bws-${BWS_ARCH}-unknown-linux-gnu-${BWS_VERSION}.zip" -o /tmp/bws.zip && \
    unzip -o /tmp/bws.zip -d /usr/local/bin/ && \
    chmod +x /usr/local/bin/bws && \
    rm /tmp/bws.zip

# Specialized symlinks and permissions
RUN ln -sf /data/.claude/bin/claude /usr/local/bin/claude 2>/dev/null || true && \
    ln -sf /app/scripts/openclaw-approve.sh /usr/local/bin/openclaw-approve && \
    chmod +x /app/scripts/*.sh /usr/local/bin/openclaw-approve

# SECURITY: Create non-root user for runtime
RUN groupadd -r openclaw && useradd -r -g openclaw -d /data -s /bin/bash openclaw && \
    mkdir -p /data && chown openclaw:openclaw /data && \
    # Scripts must be readable but not writable by openclaw user
    chown -R root:root /app/scripts/ && chmod -R 755 /app/scripts/

# FINAL PATH
ENV PATH="/usr/local/bin:/usr/bin:/bin:/data/.local/bin:/data/.npm-global/bin:/data/.bun/bin:/data/.bun/install/global/bin:/data/.claude/bin"

EXPOSE 18789
# Start as root to fix volume permissions, start cron daemon, then drop to openclaw
CMD ["bash", "-c", "chown -R openclaw:openclaw /data/.local /data/.cache /data/.config 2>/dev/null; chown -R openclaw:openclaw /data/.openclaw/agents 2>/dev/null; cron; exec su openclaw -s /bin/bash -c 'bash /app/scripts/bootstrap.sh'"]
