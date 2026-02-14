#!/usr/bin/env bash
# Post-deploy script to install optional heavy dependencies.
# Run as root: docker exec -u root <container> bash /app/scripts/install-browser-deps.sh
set -e

echo "Installing optional dependencies..."

# Heavy system packages (moved out of Dockerfile to reduce build time)
apt-get update && apt-get install -y --no-install-recommends \
    chromium \
    ffmpeg \
    imagemagick \
    pandoc \
    poppler-utils \
    graphviz \
    && rm -rf /var/lib/apt/lists/*

# Python packages (browser automation)
pip3 install browser-use playwright --break-system-packages
playwright install-deps

# Bun package (install as openclaw user so it goes to /data/.bun)
su - openclaw -c 'export BUN_INSTALL="/data/.bun" && export PATH="/data/.bun/bin:$PATH" && bun install -g @hyperbrowser/agent'

echo "All optional dependencies installed successfully."
