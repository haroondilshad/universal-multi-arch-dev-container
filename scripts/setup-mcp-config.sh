#!/bin/bash
# =============================================================================
# Setup MCP Configuration for DevPod Container
# =============================================================================
# 
# Creates the Cursor MCP configuration with:
# - Review Gate V2 (always enabled - local Python from pre-installed venv)
# - ToolHive MCP Optimizer (HTTP via Docker network)
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
      "url": "http://thv-serve:9900/mcp",
      "type": "http"
    }
  }
}
EOF

echo "MCP config created: ${MCP_CONFIG}"
echo "  ✓ review-gate-v2 (local)"
echo "  ✓ toolhive-mcp-optimizer (http://thv-serve:9900)"
