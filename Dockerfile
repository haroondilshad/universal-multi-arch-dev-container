# =============================================================================
# Universal Multi-Arch Dev Container with Review Gate V2
# =============================================================================
# 
# This image provides a complete development environment with:
# - Docker-in-Docker support via moby-engine (fully baked in - no feature needed)
# - Node.js LTS with yarn, pnpm, Bun
# - Go 1.21+ 
# - Python 3 with pip and venv
# - Review Gate V2 MCP server pre-installed
#
# Optimizations applied:
# - Combined RUN commands to reduce layers (~1.1GB savings)
# - Use --no-install-recommends and --no-cache-dir
# - Removed redundant Docker tools (use moby packages only)
# - USE_EU_MIRRORS build arg for faster EU builds
#
# Build:
#   docker buildx build --platform linux/amd64,linux/arm64 -t haroondilshad/ubuntu-devcontainer:latest --push .
#
# =============================================================================

FROM mcr.microsoft.com/devcontainers/base:ubuntu

# =============================================================================
# Configure Fast European (German) Mirrors - FAU Erlangen (Optional)
# =============================================================================
# Set USE_EU_MIRRORS=true for EU-based builds, skip for CI (US-based runners)
# Tested at 0.221s for 19MB package index vs 30s+ on default mirrors from EU
ARG USE_EU_MIRRORS=true
RUN if [ "$USE_EU_MIRRORS" = "true" ]; then \
        ARCH=$(dpkg --print-architecture) && \
        if [ "$ARCH" = "arm64" ]; then \
            sed -i 's|http://ports.ubuntu.com/ubuntu-ports|http://ftp.fau.de/ubuntu-ports|g' /etc/apt/sources.list.d/*.sources 2>/dev/null || \
            sed -i 's|http://ports.ubuntu.com/ubuntu-ports|http://ftp.fau.de/ubuntu-ports|g' /etc/apt/sources.list 2>/dev/null || true; \
        else \
            sed -i 's|http://archive.ubuntu.com/ubuntu|http://ftp.fau.de/ubuntu|g' /etc/apt/sources.list.d/*.sources 2>/dev/null || \
            sed -i 's|http://archive.ubuntu.com/ubuntu|http://ftp.fau.de/ubuntu|g' /etc/apt/sources.list 2>/dev/null || true; \
        fi; \
    fi

# =============================================================================
# Install ALL dependencies in a single layer
# =============================================================================
RUN apt-get update && apt-get install -y --no-install-recommends \
    # Basic tools
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    unzip \
    pigz \
    iptables \
    wget \
    jq \
    # Python
    python3 \
    python3-pip \
    python3-venv \
    && rm -rf /var/lib/apt/lists/*

# =============================================================================
# Install Docker (moby-engine) - Single optimized layer
# =============================================================================
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/ubuntu/$(lsb_release -rs)/prod $(lsb_release -cs) main" > /etc/apt/sources.list.d/microsoft-prod.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
        moby-engine \
        moby-cli \
        moby-buildx \
        moby-compose \
    && rm -rf /var/lib/apt/lists/* && \
    # Configure iptables
    update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true && \
    # Create docker group and add vscode user
    (grep -e "^docker:" /etc/group > /dev/null 2>&1 || groupadd -r docker) && \
    usermod -aG docker vscode

# =============================================================================
# Install Node.js, Yarn, pnpm, Bun - Single layer
# =============================================================================
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/* && \
    # Enable corepack for yarn/pnpm
    corepack enable && \
    corepack prepare yarn@stable pnpm@latest --activate && \
    # Install Bun
    curl -fsSL https://bun.sh/install | bash && \
    mv /root/.bun /home/vscode/.bun && \
    chown -R vscode:vscode /home/vscode/.bun && \
    ln -s /home/vscode/.bun/bin/bun /usr/local/bin/bun

# =============================================================================
# Install Go - Single layer
# =============================================================================
RUN ARCH=$(dpkg --print-architecture) && \
    GO_VERSION="1.21.5" && \
    if [ "$ARCH" = "arm64" ]; then GO_ARCH="arm64"; else GO_ARCH="amd64"; fi && \
    wget -q "https://go.dev/dl/go${GO_VERSION}.linux-${GO_ARCH}.tar.gz" -O /tmp/go.tar.gz && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && \
    rm /tmp/go.tar.gz && \
    ln -s /usr/local/go/bin/go /usr/bin/go

# =============================================================================
# Docker-in-Docker Startup Script
# =============================================================================
COPY <<'DOCKER_INIT' /usr/local/share/docker-init.sh
#!/bin/sh
set -e
AZURE_DNS_AUTO_DETECTION="${AZURE_DNS_AUTO_DETECTION:-true}"
DOCKER_DEFAULT_ADDRESS_POOL="${DOCKER_DEFAULT_ADDRESS_POOL:-}"

dockerd_start="$(cat << 'INNEREOF'
    find /run /var/run -iname 'docker*.pid' -delete 2>/dev/null || :
    find /run /var/run -iname 'container*.pid' -delete 2>/dev/null || :
    export container=docker
    if [ -d /sys/kernel/security ] && ! mountpoint -q /sys/kernel/security; then
        mount -t securityfs none /sys/kernel/security || true
    fi
    if ! mountpoint -q /tmp; then mount -t tmpfs none /tmp; fi
    if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
        mkdir -p /sys/fs/cgroup/init
        xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs 2>/dev/null || :
        sed -e 's/ / +/g' -e 's/^/+/' < /sys/fs/cgroup/cgroup.controllers > /sys/fs/cgroup/cgroup.subtree_control
    fi
    CUSTOMDNS=""
    if grep -qi 'internal.cloudapp.net' /etc/resolv.conf 2>/dev/null && [ "${AZURE_DNS_AUTO_DETECTION}" = "true" ]; then
        CUSTOMDNS="--dns 168.63.129.16"
    fi
    DEFAULT_ADDRESS_POOL=""
    [ -n "$DOCKER_DEFAULT_ADDRESS_POOL" ] && DEFAULT_ADDRESS_POOL="--default-address-pool $DOCKER_DEFAULT_ADDRESS_POOL"
    ( dockerd --storage-driver=vfs $CUSTOMDNS $DEFAULT_ADDRESS_POOL > /tmp/dockerd.log 2>&1 ) &
INNEREOF
)"

sudo_if() { if [ "$(id -u)" -ne 0 ]; then sudo "$@"; else "$@"; fi; }
retry=0; docker_ok="false"
until [ "${docker_ok}" = "true" ] || [ "${retry}" -eq "5" ]; do
    if [ "$(id -u)" -ne 0 ]; then sudo /bin/sh -c "${dockerd_start}"; else eval "${dockerd_start}"; fi
    for i in 1 2 3 4 5; do sleep 1; docker info > /dev/null 2>&1 && docker_ok="true" && break; done
    if [ "${docker_ok}" != "true" ] && [ "${retry}" != "4" ]; then
        sudo_if pkill dockerd 2>/dev/null || true; sudo_if pkill containerd 2>/dev/null || true
    fi
    retry=$((retry + 1))
done
exec "$@"
DOCKER_INIT

RUN chmod +x /usr/local/share/docker-init.sh

# =============================================================================
# Review Gate V2 Extension
# =============================================================================
COPY extensions/review-gate-v2/ /home/vscode/.cursor-server/extensions/review-gate-v2-2.7.3-universal/
COPY extensions/review_gate_v2_mcp.py /home/vscode/.cursor-server/extensions/review-gate-v2-2.7.3-universal/

RUN python3 -m venv /home/vscode/.cursor-server/extensions/review-gate-v2-2.7.3-universal/venv && \
    /home/vscode/.cursor-server/extensions/review-gate-v2-2.7.3-universal/venv/bin/pip install --no-cache-dir --upgrade pip && \
    /home/vscode/.cursor-server/extensions/review-gate-v2-2.7.3-universal/venv/bin/pip install --no-cache-dir \
        "mcp>=1.9.2" \
        "Pillow>=10.0.0" \
        asyncio \
        "typing-extensions>=4.14.0" && \
    # Fix ownership in same layer
    chown -R vscode:vscode /home/vscode/.cursor-server

# =============================================================================
# MCP Configuration & Extension Installation Scripts
# =============================================================================
COPY scripts/setup-mcp-config.sh /usr/local/bin/setup-mcp-config
COPY scripts/install-extensions-background.sh /usr/local/bin/install-extensions-background
RUN chmod +x /usr/local/bin/setup-mcp-config /usr/local/bin/install-extensions-background

# =============================================================================
# Final Configuration
# =============================================================================
RUN mkdir -p /home/vscode/.local/share/pnpm \
             /home/vscode/.bun/install/cache \
             /home/vscode/.cursor && \
    chown -R vscode:vscode /home/vscode

# Set environment variables
ENV BUN_INSTALL=/home/vscode/.bun \
    PATH=/home/vscode/.bun/bin:$PATH \
    DOCKER_BUILDKIT=1

CMD ["sleep", "infinity"]
