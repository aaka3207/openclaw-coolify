# syntax=docker/dockerfile:1
# Multi-stage build for optimal caching with BuildKit
# Each stage builds on the previous, with COPY . . only in the final stage
# BuildKit features: cache mounts, parallel builds, improved layer caching
#
# Cache invalidation strategy:
#   base/runtimes/browser-deps: only rebuild when system deps change (~15-20 min)
#   openclaw: only rebuild when openclaw/mcporter version changes (~2-3 min)
#   final: rebuilds on every git push (just COPY . .)

# Stage 1: Base system dependencies (rarely changes)
# Pinned to node:20 to prevent --pull from busting cache when lts tag moves
FROM node:22-bookworm-slim AS base

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

# Python packages for document processing
# NOTE: botasaurus removed (CF bypass tool), browser-use + playwright removed (massive dep tree, build timeouts)
RUN pip3 install --break-system-packages \
    ipython csvkit openpyxl python-docx pypdf

# cron + postgresql-client + BWS CLI (cached here to avoid rebuilding on every code change)
ARG BWS_VERSION=1.0.0
RUN apt-get update && apt-get install -y --no-install-recommends cron postgresql-client && rm -rf /var/lib/apt/lists/* && \
    BWS_ARCH=$(dpkg --print-architecture) && \
    if [ "$BWS_ARCH" = "amd64" ]; then BWS_ARCH="x86_64"; fi && \
    curl -fsSL "https://github.com/bitwarden/sdk-sm/releases/download/bws-v${BWS_VERSION}/bws-${BWS_ARCH}-unknown-linux-gnu-${BWS_VERSION}.zip" -o /tmp/bws.zip && \
    unzip -o /tmp/bws.zip -d /usr/local/bin/ && \
    chmod +x /usr/local/bin/bws && \
    rm /tmp/bws.zip

# ClawHub + QMD (rarely change — pin here so openclaw upgrades don't bust this layer)
# NOTE: @hyperbrowser/agent removed — 18min install + crashes build container on HDD
RUN --mount=type=cache,target=/data/.bun/install/cache \
    bun install -g clawhub && \
    bun install -g https://github.com/tobi/qmd && \
    npm install -g tsx && \
    mkdir -p /app/node_modules && ln -sf /usr/local/lib/node_modules/tsx /app/node_modules/tsx

# Stage 3: OpenClaw + MCP tools (thin layer — only rebuilds when versions change)
# Separated from browser-deps so upgrading openclaw doesn't rebuild chromium/Go/pip (~15 min saved)
FROM browser-deps AS openclaw-install

ARG OPENCLAW_BETA=false
ENV OPENCLAW_BETA=${OPENCLAW_BETA} \
    OPENCLAW_NO_ONBOARD=1

RUN --mount=type=cache,target=/data/.npm \
    if [ "$OPENCLAW_BETA" = "true" ]; then \
    npm install -g openclaw@beta; \
    else \
    npm install -g openclaw@2026.2.19; \
    fi && \
    npm install -g mcporter@0.7.3 && \
    if command -v openclaw >/dev/null 2>&1; then \
    echo "✅ openclaw binary found"; \
    else \
    echo "❌ OpenClaw install failed (binary 'openclaw' not found)"; \
    exit 1; \
    fi

# Stage 4: Final application stage (changes on every git push)
FROM openclaw-install AS final

WORKDIR /app

# Copy everything (obeying .dockerignore)
# This is the only layer that changes on code updates
COPY . .

# Specialized symlinks, permissions, and /data directory
RUN ln -sf /data/.claude/bin/claude /usr/local/bin/claude 2>/dev/null || true && \
    ln -sf /app/scripts/openclaw-approve.sh /usr/local/bin/openclaw-approve && \
    chmod +x /app/scripts/*.sh /usr/local/bin/openclaw-approve && \
    mkdir -p /data

# PATH (includes /usr/sbin for cron, /usr/local/go/bin for Go)
ENV PATH="/usr/local/go/bin:/usr/local/bin:/usr/sbin:/usr/bin:/bin:/data/.local/bin:/data/.npm-global/bin:/data/.bun/bin:/data/.bun/install/global/bin:/data/.claude/bin"

EXPOSE 18789
CMD ["bash", "/app/scripts/bootstrap.sh"]
