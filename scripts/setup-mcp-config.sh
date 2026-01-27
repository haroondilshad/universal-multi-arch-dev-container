#!/bin/bash
# =============================================================================
# Setup MCP Configuration for DevPod Container
# =============================================================================
# 
# This script creates the Cursor MCP configuration with:
# - Review Gate V2 (local Python execution from pre-installed venv)
# - ToolHive MCP Optimizer (HTTP via Docker network)
#
# The Review Gate V2 extension is pre-installed in the base image at:
#   /home/vscode/.cursor-server/extensions/review-gate-v2-2.7.3-universal/
#
# Usage:
#   setup-mcp-config              # Creates MCP config with both servers
#   setup-mcp-config --optimizer-only  # Only ToolHive optimizer (no Review Gate)
#
# =============================================================================

set -e

CURSOR_DIR="${HOME}/.cursor"
MCP_CONFIG="${CURSOR_DIR}/mcp.json"
REVIEW_GATE_DIR="/home/vscode/.cursor-server/extensions/review-gate-v2-2.7.3-universal"

# Parse arguments
INCLUDE_REVIEW_GATE=true
for arg in "$@"; do
    case $arg in
        --optimizer-only)
            INCLUDE_REVIEW_GATE=false
            ;;
        --help|-h)
            echo "Usage: setup-mcp-config [--optimizer-only]"
            echo ""
            echo "Creates ~/.cursor/mcp.json with MCP server configuration"
            echo ""
            echo "Options:"
            echo "  --optimizer-only  Only configure ToolHive MCP Optimizer"
            exit 0
            ;;
    esac
done

# Create cursor directory
mkdir -p "${CURSOR_DIR}"

# Check if Review Gate is available
if [ "$INCLUDE_REVIEW_GATE" = true ] && [ ! -f "${REVIEW_GATE_DIR}/venv/bin/python" ]; then
    echo "Warning: Review Gate V2 not found at ${REVIEW_GATE_DIR}"
    echo "Falling back to optimizer-only configuration"
    INCLUDE_REVIEW_GATE=false
fi

# Generate MCP configuration
if [ "$INCLUDE_REVIEW_GATE" = true ]; then
    cat > "${MCP_CONFIG}" << 'EOF'
{
  "mcpServers": {
    "review-gate-v2": {
      "command": "/home/vscode/.cursor-server/extensions/review-gate-v2-2.7.3-universal/venv/bin/python",
      "args": [
        "/home/vscode/.cursor-server/extensions/review-gate-v2-2.7.3-universal/review_gate_v2_mcp.py"
      ],
      "env": {
        "PYTHONPATH": "/home/vscode/.cursor-server/extensions/review-gate-v2-2.7.3-universal",
        "PYTHONUNBUFFERED": "1",
        "REVIEW_GATE_MODE": "cursor_integration"
      }
    },
    "toolhive-mcp-optimizer": {
      "url": "http://mcp-optimizer:9900/mcp",
      "type": "http"
    }
  }
}
EOF
    echo "MCP configuration created with Review Gate V2 + ToolHive Optimizer"
else
    cat > "${MCP_CONFIG}" << 'EOF'
{
  "mcpServers": {
    "toolhive-mcp-optimizer": {
      "url": "http://mcp-optimizer:9900/mcp",
      "type": "http"
    }
  }
}
EOF
    echo "MCP configuration created with ToolHive Optimizer only"
fi

echo "MCP config: ${MCP_CONFIG}"
echo ""
echo "Available MCP servers:"
if [ "$INCLUDE_REVIEW_GATE" = true ]; then
    echo "  ✓ review-gate-v2 (local Python)"
fi
echo "  ✓ toolhive-mcp-optimizer (http://mcp-optimizer:9900)"
echo ""
echo "DevPod ready!"
