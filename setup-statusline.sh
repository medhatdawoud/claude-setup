#!/bin/bash
# Sets up the Claude Code status line: symlink + settings.json entry
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

if ! command -v jq &>/dev/null; then
    echo "ERROR: jq is required but not installed. Install it first (e.g. brew install jq)."
    exit 1
fi

# Symlink statusline.sh (skip if repo IS the .claude dir)
if [ "$REPO_DIR" = "$CLAUDE_DIR" ]; then
    echo "Repo is already the Claude config dir — skipping symlink."
else
    TARGET="$CLAUDE_DIR/statusline.sh"
    if [ -e "$TARGET" ] && [ ! -L "$TARGET" ]; then
        BACKUP="${TARGET}.backup.$(date +%Y%m%d_%H%M%S)"
        echo "Backing up existing file: $TARGET -> $BACKUP"
        mv "$TARGET" "$BACKUP"
    fi
    ln -sf "$REPO_DIR/statusline.sh" "$TARGET"
    echo "Symlinked: $TARGET -> $REPO_DIR/statusline.sh"
fi

# Patch settings.json with statusLine entry (preserves all other keys)
SETTINGS="$CLAUDE_DIR/settings.json"
[ ! -f "$SETTINGS" ] && echo '{}' > "$SETTINGS"
jq --arg dir "$CLAUDE_DIR" \
    '.statusLine = {"type": "command", "command": ("bash " + $dir + "/statusline.sh")}' \
    "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
echo "Updated settings.json: statusLine points to $CLAUDE_DIR/statusline.sh"

echo ""
echo "Configure statusline sections (Enter = yes, default all on):"

ask() {
    local label="$1" flag="$2"
    read -r -p "  Include $label? [Y/n]: " ans
    [[ "${ans:-y}" =~ ^[Yy] ]] && echo "${flag}=1" || echo "${flag}=0"
}

CONF="$CLAUDE_DIR/statusline.conf"
{
    ask "git branch + diff" STATUSLINE_GIT
    ask "session tokens + cost" STATUSLINE_SESSION
    ask "context window bar" STATUSLINE_CONTEXT
    ask "RTK savings" STATUSLINE_RTK
    ask "model name" STATUSLINE_MODEL
    ask "today tokens + cost" STATUSLINE_TODAY
    ask "monthly cost" STATUSLINE_MONTH
} > "$CONF"

echo "Config written to $CONF"
echo ""
echo "Status line setup complete. Restart Claude Code to apply."
