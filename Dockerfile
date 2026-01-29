# =============================================================================
# Universal Multi-Arch Dev Container with Review Gate V2
# =============================================================================
# 
# This image provides a complete development environment with:
# - Docker-in-Docker support via moby-engine (fully baked in - no feature needed)
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

# =============================================================================
# Configure Fast European (German) Mirrors
# =============================================================================
# Use German mirrors for much faster apt operations in EU region
# This eliminates the slow ports.ubuntu.com delays (~30s+ savings)

RUN ARCH=$(dpkg --print-architecture) && \
    if [ "$ARCH" = "arm64" ]; then \
        # ARM64 uses ports.ubuntu.com - switch to German mirror
        sed -i 's|http://ports.ubuntu.com/ubuntu-ports|http://de.ports.ubuntu.com/ubuntu-ports|g' /etc/apt/sources.list.d/*.sources 2>/dev/null || \
        sed -i 's|http://ports.ubuntu.com/ubuntu-ports|http://de.ports.ubuntu.com/ubuntu-ports|g' /etc/apt/sources.list 2>/dev/null || true; \
    else \
        # AMD64 uses archive.ubuntu.com - switch to German mirror
        sed -i 's|http://archive.ubuntu.com/ubuntu|http://de.archive.ubuntu.com/ubuntu|g' /etc/apt/sources.list.d/*.sources 2>/dev/null || \
        sed -i 's|http://archive.ubuntu.com/ubuntu|http://de.archive.ubuntu.com/ubuntu|g' /etc/apt/sources.list 2>/dev/null || true; \
    fi

# Install dependencies for repo setup
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    unzip \
    pigz \
    iptables \
    wget \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Add Microsoft package repo for moby-engine (Docker)
RUN mkdir -p /etc/apt/keyrings && \
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /etc/apt/keyrings/microsoft.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/ubuntu/$(lsb_release -rs)/prod $(lsb_release -cs) main" | tee /etc/apt/sources.list.d/microsoft-prod.list

# Install moby-engine, moby-cli, and moby-buildx (complete Docker daemon)
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        moby-engine \
        moby-cli \
        moby-buildx \
        moby-compose \
    && rm -rf /var/lib/apt/lists/*

# Swap to legacy iptables for Docker compatibility
RUN update-alternatives --set iptables /usr/sbin/iptables-legacy 2>/dev/null || true && \
    update-alternatives --set ip6tables /usr/sbin/ip6tables-legacy 2>/dev/null || true

# Create docker group and add vscode user
RUN if ! grep -e "^docker:" /etc/group > /dev/null 2>&1; then groupadd -r docker; fi && \
    usermod -aG docker vscode

# Install Docker Compose plugin standalone binary (latest v2)
RUN mkdir -p /usr/local/lib/docker/cli-plugins && \
    ARCH=$(uname -m) && \
    COMPOSE_VERSION="2.32.4" && \
    curl -fsSL "https://github.com/docker/compose/releases/download/v${COMPOSE_VERSION}/docker-compose-linux-${ARCH}" -o /usr/local/lib/docker/cli-plugins/docker-compose && \
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose && \
    # Also create /usr/local/bin symlink for docker-compose command
    ln -sf /usr/local/lib/docker/cli-plugins/docker-compose /usr/local/bin/docker-compose

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
# Docker-in-Docker Pre-installed Components (Fully Baked In)
# =============================================================================
# All Docker components pre-installed - no feature download needed at runtime

# Install Docker Buildx (standalone - in addition to moby-buildx for redundancy)
RUN mkdir -p /usr/libexec/docker/cli-plugins && \
    ARCH=$(dpkg --print-architecture) && \
    BUILDX_VERSION="0.21.1" && \
    curl -fsSL "https://github.com/docker/buildx/releases/download/v${BUILDX_VERSION}/buildx-v${BUILDX_VERSION}.linux-${ARCH}" \
        -o /usr/libexec/docker/cli-plugins/docker-buildx && \
    chmod +x /usr/libexec/docker/cli-plugins/docker-buildx && \
    # Set proper ownership for docker group
    chown -R root:docker /usr/libexec/docker && \
    chmod -R g+r+w /usr/libexec/docker

# Install compose-switch for docker-compose v1 compatibility
RUN ARCH=$(dpkg --print-architecture) && \
    COMPOSE_SWITCH_VERSION="1.0.5" && \
    curl -fsSL "https://github.com/docker/compose-switch/releases/download/v${COMPOSE_SWITCH_VERSION}/docker-compose-linux-${ARCH}" \
        -o /usr/local/bin/compose-switch && \
    chmod +x /usr/local/bin/compose-switch

# =============================================================================
# Docker-in-Docker Startup Script (docker-init.sh)
# =============================================================================
# This script handles cgroup configuration, DNS detection, and dockerd startup
# Based on the official devcontainers/features docker-in-docker implementation

COPY <<'DOCKER_INIT' /usr/local/share/docker-init.sh
#!/bin/sh
#-------------------------------------------------------------------------------------------------------------
# Docker-in-Docker initialization script
# Handles cgroup v2 nesting, DNS configuration, and dockerd startup
#-------------------------------------------------------------------------------------------------------------

set -e

AZURE_DNS_AUTO_DETECTION="${AZURE_DNS_AUTO_DETECTION:-true}"
DOCKER_DEFAULT_ADDRESS_POOL="${DOCKER_DEFAULT_ADDRESS_POOL:-}"

dockerd_start="$(cat << 'INNEREOF'
    # Clean up stale PID files
    find /run /var/run -iname 'docker*.pid' -delete 2>/dev/null || :
    find /run /var/run -iname 'container*.pid' -delete 2>/dev/null || :

    export container=docker

    # Mount securityfs if needed
    if [ -d /sys/kernel/security ] && ! mountpoint -q /sys/kernel/security; then
        mount -t securityfs none /sys/kernel/security || {
            echo >&2 'Could not mount /sys/kernel/security.'
            echo >&2 'AppArmor detection and --privileged mode might break.'
        }
    fi

    # Mount /tmp if needed
    if ! mountpoint -q /tmp; then
        mount -t tmpfs none /tmp
    fi

    # Configure cgroup v2 nesting
    set_cgroup_nesting() {
        if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
            mkdir -p /sys/fs/cgroup/init
            xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs 2>/dev/null || :
            sed -e 's/ / +/g' -e 's/^/+/' < /sys/fs/cgroup/cgroup.controllers \
                > /sys/fs/cgroup/cgroup.subtree_control
        fi
    }

    # Retry cgroup nesting setup
    retry_cgroup_nesting=0
    until [ "${retry_cgroup_nesting}" -eq "5" ]; do
        set +e
        set_cgroup_nesting
        if [ $? -ne 0 ]; then
            echo "(*) cgroup v2: Failed to enable nesting, retrying..."
        else
            break
        fi
        retry_cgroup_nesting=$((retry_cgroup_nesting + 1))
        set -e
    done

    # Handle Azure DNS detection
    set +e
    if grep -qi 'internal.cloudapp.net' /etc/resolv.conf 2>/dev/null; then
        if [ "${AZURE_DNS_AUTO_DETECTION}" = "true" ]; then
            echo "Setting dockerd Azure DNS."
            CUSTOMDNS="--dns 168.63.129.16"
        fi
    else
        echo "Not setting dockerd DNS manually."
        CUSTOMDNS=""
    fi
    set -e

    # Configure address pool if specified
    if [ -n "$DOCKER_DEFAULT_ADDRESS_POOL" ]; then
        DEFAULT_ADDRESS_POOL="--default-address-pool $DOCKER_DEFAULT_ADDRESS_POOL"
    else
        DEFAULT_ADDRESS_POOL=""
    fi

    # Start dockerd
    ( dockerd $CUSTOMDNS $DEFAULT_ADDRESS_POOL > /tmp/dockerd.log 2>&1 ) &
INNEREOF
)"

sudo_if() {
    COMMAND="$*"
    if [ "$(id -u)" -ne 0 ]; then
        sudo $COMMAND
    else
        $COMMAND
    fi
}

retry_docker_start_count=0
docker_ok="false"

until [ "${docker_ok}" = "true" ] || [ "${retry_docker_start_count}" -eq "5" ]; do
    # Start dockerd
    if [ "$(id -u)" -ne 0 ]; then
        sudo /bin/sh -c "${dockerd_start}"
    else
        eval "${dockerd_start}"
    fi

    # Wait for docker to be ready
    retry_count=0
    until [ "${docker_ok}" = "true" ] || [ "${retry_count}" -eq "5" ]; do
        sleep 1s
        set +e
        docker info > /dev/null 2>&1 && docker_ok="true"
        set -e
        retry_count=$((retry_count + 1))
    done

    if [ "${docker_ok}" != "true" ] && [ "${retry_docker_start_count}" != "4" ]; then
        echo "(*) Failed to start docker, retrying..."
        set +e
        sudo_if pkill dockerd
        sudo_if pkill containerd
        set -e
    fi

    retry_docker_start_count=$((retry_docker_start_count + 1))
done

# Execute passed commands
exec "$@"
DOCKER_INIT

RUN chmod +x /usr/local/share/docker-init.sh && \
    chown vscode:root /usr/local/share/docker-init.sh

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

# Set environment variables
ENV BUN_INSTALL=/home/vscode/.bun
ENV PATH=$BUN_INSTALL/bin:$PATH
ENV DOCKER_BUILDKIT=1

# Default command - sleep infinity for devcontainer
CMD ["sleep", "infinity"]
