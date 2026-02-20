#!/bin/bash
# =============================================================================
# Setup Claude-Mem for DevPod Container
# =============================================================================
#
# Runs during postCreateCommand to configure claude-mem hooks and plugins.
# Requires bind mounts: ~/claude-mem, ~/.claude-mem, ~/.claude/plugins, ~/.cursor/hooks
#
# =============================================================================

set -e

CLAUDE_MEM_DIR="${HOME}/claude-mem"
BUN="${HOME}/.bun/bin/bun"
HOOKS_JSON="${HOME}/.cursor/hooks.json"

# Skip if claude-mem not mounted
if [ ! -d "$CLAUDE_MEM_DIR" ]; then
    echo "claude-mem not mounted, skipping"
    exit 0
fi

# Install claude-mem Cursor hooks
if [ -x "$BUN" ] && [ -f "$CLAUDE_MEM_DIR/plugin/scripts/worker-service.cjs" ]; then
    (cd "$CLAUDE_MEM_DIR" && "$BUN" run cursor:install -- user 2>/dev/null || true)
    echo "  ✓ claude-mem hooks installed"
fi

# Fix plugins symlink (bind-mounted path differs from host)
mkdir -p "${HOME}/.claude/plugins/marketplaces/thedotmack"
ln -sf "$CLAUDE_MEM_DIR/plugin/package.json" \
    "${HOME}/.claude/plugins/marketplaces/thedotmack/package.json" 2>/dev/null || true
echo "  ✓ plugin symlink created"

# Register context injection hook if not already present
if [ -f "$HOOKS_JSON" ]; then
    INJECT_SCRIPT="${HOME}/.cursor/hooks/claude-mem-context-inject.sh"
    if [ -f "$INJECT_SCRIPT" ]; then
        python3 -c "
import json, os
p = os.path.expanduser('$HOOKS_JSON')
d = json.load(open(p))
h = {'command': 'bash $INJECT_SCRIPT'}
hooks = d.get('hooks', {}).get('beforeSubmitPrompt', [])
if not any(x.get('command', '').endswith('context-inject.sh') for x in hooks):
    hooks.append(h)
    d.setdefault('hooks', {})['beforeSubmitPrompt'] = hooks
    json.dump(d, open(p, 'w'), indent=2)
    print('  ✓ context injection hook registered')
else:
    print('  ✓ context injection hook already registered')
" 2>/dev/null || true
    fi
fi

echo "claude-mem setup complete"
