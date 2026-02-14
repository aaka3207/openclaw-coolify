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
    pandoc \
    poppler-utils \
    ffmpeg \
    imagemagick \
    graphviz \
    sqlite3 \
    pass \
    chromium \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Stage 2: System CLI tools (change occasionally)
FROM base AS system-tools

# Install Docker CE CLI (Latest) to support API 1.44+
RUN install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y docker-ce-cli && \
    rm -rf /var/lib/apt/lists/*

# Install Go (pinned with checksum verification)
ARG GO_VERSION=1.23.4
ARG GO_SHA256=6924efde5de86fe277676e929dc9917d466efa02fb934197bc2eba35d5680971
RUN curl -L "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o go.tar.gz && \
    echo "${GO_SHA256}  go.tar.gz" | sha256sum -c - && \
    tar -C /usr/local -xzf go.tar.gz && \
    rm go.tar.gz

# Install GitHub CLI (gh)
RUN mkdir -p -m 755 /etc/apt/keyrings && \
    wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null && \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && \
    apt-get install -y gh && \
    rm -rf /var/lib/apt/lists/*

# Install uv (Python tool manager, pinned version)
ENV UV_INSTALL_DIR="/usr/local/bin"
ARG UV_VERSION=0.5.14
RUN curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" -o /tmp/uv-install.sh && \
    sh /tmp/uv-install.sh && rm /tmp/uv-install.sh

# Stage 3: Language runtimes and package managers (change sometimes)
FROM system-tools AS runtimes

ENV BUN_INSTALL_NODE=0 \
    BUN_INSTALL="/data/.bun" \
    PATH="/usr/local/go/bin:/data/.bun/bin:/data/.bun/install/global/bin:$PATH"

# Install Bun (pinned version)
ARG BUN_VERSION=1.1.42
RUN curl -fsSL https://bun.sh/install | bash -s "bun-v${BUN_VERSION}"

# Python tools
RUN pip3 install ipython csvkit openpyxl python-docx pypdf botasaurus browser-use playwright --break-system-packages && \
    playwright install-deps

# Configure QMD Persistence
ENV XDG_CACHE_HOME="/data/.cache"

# Debian aliases
RUN ln -s /usr/bin/fdfind /usr/bin/fd || true && \
    ln -s /usr/bin/batcat /usr/bin/bat || true

# Stage 4: Application dependencies (package installations)
FROM runtimes AS dependencies

# OpenClaw install
ARG OPENCLAW_BETA=false
ENV OPENCLAW_BETA=${OPENCLAW_BETA} \
    OPENCLAW_NO_ONBOARD=1

# Install QMD with BuildKit cache mount for faster rebuilds
RUN --mount=type=cache,target=/data/.bun/install/cache \
    bun install -g https://github.com/tobi/qmd && hash -r && \
    bun pm -g untrusted && \
    bun install -g @hyperbrowser/agent clawhub

# Install OpenClaw with npm cache mount
RUN --mount=type=cache,target=/data/.npm \
    if [ "$OPENCLAW_BETA" = "true" ]; then \
    npm install -g openclaw@beta; \
    else \
    npm install -g openclaw; \
    fi && \
    if command -v openclaw >/dev/null 2>&1; then \
    echo "✅ openclaw binary found"; \
    else \
    echo "❌ OpenClaw install failed (binary 'openclaw' not found)"; \
    exit 1; \
    fi

# AI Tool Suite & ClawHub (download then execute for auditability)
RUN curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh && \
    bash /tmp/claude-install.sh && rm /tmp/claude-install.sh

# Stage 5: Final application stage (changes frequently)
FROM dependencies AS final

WORKDIR /app

# Copy everything (obeying .dockerignore)
# This is the only layer that changes on code updates
COPY . .

# Specialized symlinks and permissions
RUN ln -sf /data/.claude/bin/claude /usr/local/bin/claude 2>/dev/null || true && \
    ln -sf /app/scripts/openclaw-approve.sh /usr/local/bin/openclaw-approve && \
    chmod +x /app/scripts/*.sh /usr/local/bin/openclaw-approve

# SECURITY: Create non-root user for runtime
RUN groupadd -r openclaw && useradd -r -g openclaw -d /data -s /bin/bash openclaw && \
    mkdir -p /data && chown -R openclaw:openclaw /data && \
    # Scripts must be readable but not writable by openclaw user
    chown -R root:root /app/scripts/ && chmod -R 755 /app/scripts/

# FINAL PATH
ENV PATH="/usr/local/go/bin:/usr/local/bin:/usr/bin:/bin:/data/.local/bin:/data/.npm-global/bin:/data/.bun/bin:/data/.bun/install/global/bin:/data/.claude/bin"

USER openclaw
EXPOSE 18789
CMD ["bash", "/app/scripts/bootstrap.sh"]
