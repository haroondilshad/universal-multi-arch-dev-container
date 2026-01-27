# Universal Multi-Arch Dev Container

A multi-architecture development container image with pre-installed tools and Review Gate V2 MCP server.

## Features

- **Multi-Architecture**: Supports both `linux/amd64` and `linux/arm64` (Oracle Cloud, Apple Silicon)
- **Docker-in-Docker**: moby-engine pre-installed for container development
- **Node.js**: LTS version with yarn, pnpm, and bun
- **Go**: Version 1.21.5
- **Python 3**: With pip and venv support
- **Review Gate V2**: Pre-installed MCP server for Cursor integration
- **ToolHive Ready**: Pre-configured for ToolHive MCP Optimizer

## Usage

### In DevContainer (VS Code / Cursor)

```json
{
  "name": "My Project",
  "image": "haroondilshad/ubuntu-devcontainer:latest",
  "runArgs": ["--network=toolhive-external"],
  "postCreateCommand": "setup-mcp-config"
}
```

### In DevPod

Use the shared devcontainer configuration from the toolhive project:

```bash
cp path/to/toolhive/scripts/devcontainer.shared.json .devcontainer.json
devpod up .
```

## Pre-installed Components

### Review Gate V2 MCP Server

Location: `/home/vscode/.cursor-server/extensions/review-gate-v2-2.7.3-universal/`

The Review Gate V2 MCP server is pre-installed with its Python virtual environment ready to use. The `setup-mcp-config` script automatically configures Cursor to use it.

### MCP Configuration Script

The `setup-mcp-config` script creates `~/.cursor/mcp.json` with:

- **review-gate-v2**: Local Python MCP server for interactive development
- **toolhive-mcp-optimizer**: HTTP-based MCP router for ToolHive servers

```bash
# Full configuration (Review Gate + ToolHive)
setup-mcp-config

# ToolHive only (no Review Gate)
setup-mcp-config --optimizer-only
```

## Building

### Local Build

```bash
docker build -t haroondilshad/ubuntu-devcontainer:latest .
```

### Multi-Arch Build & Push

```bash
docker buildx build \
  --platform linux/amd64,linux/arm64 \
  -t haroondilshad/ubuntu-devcontainer:latest \
  --push .
```

### Automated Build

The image is automatically built and pushed to Docker Hub on every push to `main` branch via GitHub Actions.

## File Structure

```
.
├── Dockerfile                    # Main image definition
├── extensions/
│   └── review_gate_v2_mcp.py    # Review Gate V2 MCP server script
├── scripts/
│   └── setup-mcp-config.sh      # MCP configuration setup script
└── .github/
    └── build.yaml               # GitHub Actions CI/CD
```

## Integration with ToolHive

This image is designed to work with ToolHive for a complete MCP development environment:

1. **Host Setup**: ToolHive runs on the Oracle host with MCP servers
2. **DevPod**: Uses this image connected to `toolhive-external` network
3. **MCP Access**: 
   - Review Gate V2 runs locally in the container
   - Other MCP servers accessed via ToolHive Optimizer

## License

MIT License
