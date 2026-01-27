# =============================================================================
# Universal Multi-Arch Dev Container with Review Gate V2
# =============================================================================
# 
# This image provides a complete development environment with:
# - Docker-in-Docker support via moby-engine
# - Node.js LTS with yarn, pnpm
# - Go 1.21+ 
# - Python 3 with pip and venv
# - Review Gate V2 MCP server pre-installed
#
# Build:
#   docker buildx build --platform linux/amd64,linux/arm64 -t haroondilshad/ubuntu-devcontainer:latest --push .
#
# =============================================================================

FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Install dependencies for repo setup
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    unzip \
    && rm -rf /var/lib/apt/lists/*

# Add Microsoft package repo for moby-engine (Docker)
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/ubuntu/$(lsb_release -rs)/prod $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/microsoft-prod.list

# Install moby-engine (Docker daemon)
RUN apt-get update && \
    apt-get install -y moby-engine && \
    rm -rf /var/lib/apt/lists/*

# Install Docker Compose plugin standalone binary
RUN mkdir -p /usr/local/lib/docker/cli-plugins && \
    ARCH=$(uname -m) && \
    curl -L "https://github.com/docker/compose/releases/download/v2.19.1/docker-compose-linux-${ARCH}" -o /usr/local/lib/docker/cli-plugins/docker-compose && \
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Install Node LTS
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# Install Yarn (uses corepack in Node 16+)
RUN corepack enable && corepack prepare yarn@stable --activate

# Install pnpm (uses corepack in Node 16+)
RUN corepack prepare pnpm@latest --activate

# Install Bun
RUN curl -fsSL https://bun.sh/install | bash && \
    mv /root/.bun /home/vscode/.bun && \
    chown -R vscode:vscode /home/vscode/.bun && \
    ln -s /home/vscode/.bun/bin/bun /usr/local/bin/bun

# Install Go (multi-arch compatible)
RUN ARCH=$(dpkg --print-architecture) && \
    GO_VERSION="1.21.5" && \
    if [ "$ARCH" = "arm64" ]; then GO_ARCH="arm64"; else GO_ARCH="amd64"; fi && \
    wget -q "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" && \
    tar -C /usr/local -xzf "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" && \
    rm "go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" && \
    ln -s /usr/local/go/bin/go /usr/bin/go

# Install Python with venv support
RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Docker-in-Docker Pre-installed Components
# =============================================================================
# Pre-install buildx and compose-switch to avoid download during container start

# Install Docker Buildx (pre-download for faster startup)
RUN mkdir -p /usr/local/lib/docker/cli-plugins && \
    ARCH=$(dpkg --print-architecture) && \
    BUILDX_VERSION="0.31.0" && \
    curl -L "https://github.com/docker/buildx/releases/download/v${BUILDX_VERSION}/buildx-v${BUILDX_VERSION}.linux-${ARCH}" \
        -o /usr/local/lib/docker/cli-plugins/docker-buildx && \
    chmod +x /usr/local/lib/docker/cli-plugins/docker-buildx

# Install compose-switch for docker-compose v1 compatibility
RUN ARCH=$(dpkg --print-architecture) && \
    COMPOSE_SWITCH_VERSION="1.0.5" && \
    curl -L "https://github.com/docker/compose-switch/releases/download/v${COMPOSE_SWITCH_VERSION}/docker-compose-linux-${ARCH}" \
        -o /usr/local/bin/compose-switch && \
    chmod +x /usr/local/bin/compose-switch

# =============================================================================
# Review Gate V2 Extension (Complete with VSIX contents)
# =============================================================================
# Pre-install complete Review Gate V2 extension so it's ready immediately

# Create extension directory
RUN mkdir -p /home/vscode/.cursor-server/extensions/review-gate-v2-2.7.3-universal

# Copy all extension files (extracted from VSIX)
COPY extensions/review-gate-v2/ /home/vscode/.cursor-server/extensions/review-gate-v2-2.7.3-universal/

# Copy the MCP server script
COPY extensions/review_gate_v2_mcp.py /home/vscode/.cursor-server/extensions/review-gate-v2-2.7.3-universal/

# Create virtual environment and install MCP dependencies
RUN python3 -m venv /home/vscode/.cursor-server/extensions/review-gate-v2-2.7.3-universal/venv && \
    /home/vscode/.cursor-server/extensions/review-gate-v2-2.7.3-universal/venv/bin/pip install --upgrade pip && \
    /home/vscode/.cursor-server/extensions/review-gate-v2-2.7.3-universal/venv/bin/pip install \
        "mcp>=1.9.2" \
        "Pillow>=10.0.0" \
        asyncio \
        "typing-extensions>=4.14.0"

# Fix ownership
RUN chown -R vscode:vscode /home/vscode/.cursor-server

# =============================================================================
# MCP Configuration Setup Script
# =============================================================================
# Script to create ~/.cursor/mcp.json with Review Gate + ToolHive Optimizer

COPY scripts/setup-mcp-config.sh /usr/local/bin/setup-mcp-config
RUN chmod +x /usr/local/bin/setup-mcp-config

# =============================================================================
# Final Configuration
# =============================================================================

# Create common directories for package managers
RUN mkdir -p /home/vscode/.local/share/pnpm \
    && mkdir -p /home/vscode/.bun/install/cache \
    && mkdir -p /home/vscode/.cursor \
    && chown -R vscode:vscode /home/vscode

# Set environment
ENV BUN_INSTALL=/home/vscode/.bun
ENV PATH=$BUN_INSTALL/bin:$PATH

CMD ["sleep", "infinity"]
