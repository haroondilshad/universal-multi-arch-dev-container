#!/bin/bash
# =============================================================================
# Setup MCP Configuration & Extensions for DevPod Container
# =============================================================================
# 
# Creates the Cursor MCP configuration with:
# - Review Gate V2 (always enabled - local Python from pre-installed venv)
# - ToolHive MCP Optimizer (HTTP via Docker network)
#
# Also installs extensions from .devcontainer.json in the background.
#
# Review Gate V2 is pre-installed at:
#   /home/vscode/.cursor-server/extensions/review-gate-v2-2.7.3-universal/
#
# =============================================================================

set -e

CURSOR_DIR="${HOME}/.cursor"
MCP_CONFIG="${CURSOR_DIR}/mcp.json"

mkdir -p "${CURSOR_DIR}"

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

echo "MCP config created: ${MCP_CONFIG}"
echo "  ✓ review-gate-v2 (local)"
echo "  ✓ toolhive-mcp-optimizer (http://mcp-optimizer:9900)"

# =============================================================================
# Install Extensions from .devcontainer.json
# =============================================================================

# Wait for cursor-server to become available (max 30 seconds)
CURSOR_SERVER=""
for i in $(seq 1 30); do
    CURSOR_SERVER=$(find "${HOME}/.cursor-server/bin" -name "cursor-server" -type f 2>/dev/null | head -1)
    if [ -n "$CURSOR_SERVER" ]; then
        break
    fi
    if [ "$i" -eq 1 ]; then
        echo "⏳ Waiting for cursor-server..."
    fi
    sleep 1
done

if [ -z "$CURSOR_SERVER" ]; then
    echo "⚠️  cursor-server not found after 30s, skipping extension installation"
    exit 0
fi
echo "✓ cursor-server found"

# Find .devcontainer.json in workspace
DEVCONTAINER_JSON=""
for path in "/workspaces/"*"/.devcontainer.json" "/workspace/.devcontainer.json"; do
    if [ -f "$path" ]; then
        DEVCONTAINER_JSON="$path"
        break
    fi
done

if [ -z "$DEVCONTAINER_JSON" ] || [ ! -f "$DEVCONTAINER_JSON" ]; then
    echo "⚠️  .devcontainer.json not found, skipping extension installation"
    exit 0
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo "⚠️  jq not available, skipping extension installation"
    exit 0
fi

# Extract extensions from .devcontainer.json (strip comments first)
EXTENSIONS=$(grep -v '^\s*//' "$DEVCONTAINER_JSON" | jq -r '.customizations.vscode.extensions[]? // empty' 2>/dev/null)

if [ -z "$EXTENSIONS" ]; then
    echo "ℹ️  No extensions found in .devcontainer.json"
    exit 0
fi

# Install extensions in background
echo "Installing extensions from .devcontainer.json..."
(
    for ext in $EXTENSIONS; do
        echo "  Installing: $ext"
        "$CURSOR_SERVER" --install-extension "$ext" --force 2>/dev/null || true
    done
    echo "  ✓ Extension installation complete"
) &

echo "  → Extensions installing in background"
