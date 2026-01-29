#!/bin/bash
# =============================================================================
# Install Extensions Background Service
# =============================================================================
# 
# Spawns a completely detached background process that:
# 1. Monitors for cursor-server to become available (up to 5 minutes)
# 2. Installs extensions from .devcontainer.json
# 3. Logs to /tmp/install-extensions.log
#
# This script returns immediately - the work happens in background.
#
# =============================================================================

LOG_FILE="/tmp/install-extensions.log"
LOCK_FILE="/tmp/install-extensions.lock"

# Check if already running
if [ -f "$LOCK_FILE" ]; then
    pid=$(cat "$LOCK_FILE" 2>/dev/null)
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
        echo "Extension installer already running (PID $pid)"
        exit 0
    fi
fi

# Spawn completely detached background process using nohup + disown
nohup bash -c '
LOG_FILE="/tmp/install-extensions.log"
LOCK_FILE="/tmp/install-extensions.lock"
MAX_WAIT=300

echo $$ > "$LOCK_FILE"

log() {
    echo "[$(date +%H:%M:%S)] $1" >> "$LOG_FILE"
}

log "Extension installer started (PID $$)"

# Wait for cursor-server (check every 10 seconds)
CURSOR_SERVER=""
waited=0
while [ $waited -lt $MAX_WAIT ]; do
    CURSOR_SERVER=$(find "${HOME}/.cursor-server/bin" -name "cursor-server" -type f 2>/dev/null | head -1)
    if [ -n "$CURSOR_SERVER" ]; then
        break
    fi
    sleep 10
    waited=$((waited + 10))
    log "Waiting for cursor-server... (${waited}s)"
done

if [ -z "$CURSOR_SERVER" ]; then
    log "cursor-server not found after ${MAX_WAIT}s, exiting"
    rm -f "$LOCK_FILE"
    exit 1
fi

log "cursor-server found: $CURSOR_SERVER"

# Find .devcontainer.json
DEVCONTAINER_JSON=""
for path in "/workspaces/"*"/.devcontainer.json" "/workspace/.devcontainer.json"; do
    if [ -f "$path" ]; then
        DEVCONTAINER_JSON="$path"
        break
    fi
done

if [ -z "$DEVCONTAINER_JSON" ] || [ ! -f "$DEVCONTAINER_JSON" ]; then
    log ".devcontainer.json not found"
    rm -f "$LOCK_FILE"
    exit 1
fi

log "Config: $DEVCONTAINER_JSON"

# Check jq
if ! command -v jq &> /dev/null; then
    log "jq not available"
    rm -f "$LOCK_FILE"
    exit 1
fi

# Extract extensions (strip comments)
EXTENSIONS=$(grep -v "^\s*//" "$DEVCONTAINER_JSON" | jq -r ".customizations.vscode.extensions[]? // empty" 2>/dev/null)

if [ -z "$EXTENSIONS" ]; then
    log "No extensions in config"
    rm -f "$LOCK_FILE"
    exit 0
fi

EXT_COUNT=$(echo "$EXTENSIONS" | wc -l | tr -d " ")
log "Installing $EXT_COUNT extensions..."

installed=0
for ext in $EXTENSIONS; do
    log "  -> $ext"
    if "$CURSOR_SERVER" --install-extension "$ext" --force >> "$LOG_FILE" 2>&1; then
        installed=$((installed + 1))
    fi
done

log "Done: $installed/$EXT_COUNT extensions installed"
log "NOTE: Reload Cursor window (Cmd+Shift+P -> Developer: Reload Window) to activate extensions"
rm -f "$LOCK_FILE"
' > /dev/null 2>&1 &

disown

echo "Extension installer started in background"
echo "  Log: $LOG_FILE"
