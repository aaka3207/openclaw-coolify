#!/usr/bin/env bash
# Post-deploy script to install optional dependencies.
# Run as root: docker exec -u root <container> bash /app/scripts/install-browser-deps.sh
set -e

echo "=== Installing optional dependencies ==="

# ---- System packages (apt-get) ----
echo ">> Installing system packages..."
apt-get update && apt-get install -y --no-install-recommends \
    chromium \
    ffmpeg \
    imagemagick \
    pandoc \
    poppler-utils \
    graphviz \
    && rm -rf /var/lib/apt/lists/*

# ---- Docker CE CLI ----
echo ">> Installing Docker CLI..."
install -m 0755 -d /etc/apt/keyrings && \
    curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && \
    chmod a+r /etc/apt/keyrings/docker.asc && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/debian \
    $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
    tee /etc/apt/sources.list.d/docker.list > /dev/null && \
    apt-get update && \
    apt-get install -y docker-ce-cli && \
    rm -rf /var/lib/apt/lists/*

# ---- Go ----
echo ">> Installing Go..."
GO_VERSION=1.23.4
GO_SHA256=6924efde5de86fe277676e929dc9917d466efa02fb934197bc2eba35d5680971
curl -L "https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz" -o /tmp/go.tar.gz && \
    echo "${GO_SHA256}  /tmp/go.tar.gz" | sha256sum -c - && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && \
    rm /tmp/go.tar.gz

# ---- GitHub CLI ----
echo ">> Installing GitHub CLI..."
mkdir -p -m 755 /etc/apt/keyrings && \
    wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null && \
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null && \
    apt-get update && \
    apt-get install -y gh && \
    rm -rf /var/lib/apt/lists/*

# ---- uv (Python tool manager) ----
echo ">> Installing uv..."
UV_VERSION=0.5.14
curl -LsSf "https://astral.sh/uv/${UV_VERSION}/install.sh" -o /tmp/uv-install.sh && \
    UV_INSTALL_DIR="/usr/local/bin" sh /tmp/uv-install.sh && rm /tmp/uv-install.sh

# ---- Python packages ----
echo ">> Installing Python packages..."
pip3 install ipython csvkit openpyxl python-docx pypdf botasaurus browser-use playwright --break-system-packages
playwright install-deps

# ---- Claude CLI ----
echo ">> Installing Claude CLI..."
curl -fsSL https://claude.ai/install.sh -o /tmp/claude-install.sh && \
    bash /tmp/claude-install.sh && rm /tmp/claude-install.sh

# ---- Bun packages (as openclaw user → /data/.bun) ----
echo ">> Installing bun packages..."
su - openclaw -c 'export BUN_INSTALL="/data/.bun" && export PATH="/data/.bun/bin:$PATH" && bun install -g https://github.com/tobi/qmd && bun install -g @hyperbrowser/agent'

# ---- Add Go to PATH for openclaw user ----
echo 'export PATH="/usr/local/go/bin:$PATH"' >> /data/.bashrc 2>/dev/null || true

echo "=== All optional dependencies installed successfully ==="
