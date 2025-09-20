FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Install dependencies for repo setup
RUN apt-get update && apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

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
    curl -L "https://github.com/docker/compose/releases/download/v2.19.1/docker-compose-linux-$(uname -m)" -o /usr/local/lib/docker/cli-plugins/docker-compose && \
    chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# Install Node LTS
RUN curl -fsSL https://deb.nodesource.com/setup_lts.x | bash - && \
    apt-get install -y nodejs

# Install Yarn (uses corepack in Node 16+)
RUN corepack enable && corepack prepare yarn@stable --activate

# Install pnpm (uses corepack in Node 16+)
RUN corepack prepare pnpm@latest --activate

# Install Go 1.21 for ARM64
RUN wget https://go.dev/dl/go1.25.1.darwin-arm64.tar.gz && \
    tar -C /usr/local -xzf go1.25.1.darwin-arm64.tar.gz && \
    rm go1.25.1.darwin-arm64.tar.gz && \
    ln -s /usr/local/go/bin/go /usr/bin/go

# Install latest Python
RUN apt-get update && apt-get install -y python3 python3-pip && rm -rf /var/lib/apt/lists/*

CMD ["sleep", "infinity"]
