#!/bin/bash
# Sets up the Claude Code status line: symlink + settings.json entry
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
YES_ALL=0
[ "$1" = "-y" ] && YES_ALL=1

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
echo ""

CONF="$CLAUDE_DIR/statusline.conf"
> "$CONF"

ask() {
    local label="$1" flag="$2" example="$3"
    if [ "$YES_ALL" = "1" ]; then
        echo "  Include $label? (e.g. $example) [Y/n]: Y"
        echo "${flag}=1" >> "$CONF"
        return
    fi
    read -r -p "  Include $label? (e.g. $example) [Y/n]: " ans
    [[ "${ans:-y}" =~ ^[Yy] ]] && echo "${flag}=1" >> "$CONF" || echo "${flag}=0" >> "$CONF"
}

ask_rtk() {
    if [ "$YES_ALL" = "1" ]; then
        echo "  Include RTK savings? (e.g. ✂️ 1.5M (5.5%)) [Y/n]: Y"
        if ! command -v rtk &>/dev/null; then
            echo ""
            echo "  WARNING: rtk is not installed."
            echo "  Install:  brew install rtk"
            echo "  Activate: rtk init -g --auto-patch"
            echo "  Verify:   rtk gain"
            echo ""
        fi
        echo "STATUSLINE_RTK=1" >> "$CONF"
        return
    fi
    read -r -p "  Include RTK savings? (e.g. ✂️ 1.5M (5.5%)) [Y/n]: " ans
    if [[ "${ans:-y}" =~ ^[Yy] ]]; then
        if ! command -v rtk &>/dev/null; then
            echo ""
            echo "  WARNING: rtk is not installed."
            echo "  Install:  brew install rtk"
            echo "  Activate: rtk init -g --auto-patch"
            echo "  Verify:   rtk gain"
            echo ""
            read -r -p "  Keep RTK enabled (assuming you will install it)? [Y/n]: " confirm
            [[ "${confirm:-y}" =~ ^[Yy] ]] && echo "STATUSLINE_RTK=1" >> "$CONF" || echo "STATUSLINE_RTK=0" >> "$CONF"
        else
            echo "STATUSLINE_RTK=1" >> "$CONF"
        fi
    else
        echo "STATUSLINE_RTK=0" >> "$CONF"
    fi
}

ask "current directory"     STATUSLINE_DIR          "/ my-project"
ask "git branch + diff"     STATUSLINE_GIT          "🌿 main +5 -2"
ask "session tokens + cost" STATUSLINE_SESSION       "🔸 12.3K 💰 \$0.042"
ask "context window bar"    STATUSLINE_CONTEXT       "23% ━━━─────────"
ask_rtk
ask "session time"          STATUSLINE_SESSION_TIME  "⏱️ 42m"
ask "memory usage"          STATUSLINE_MEM           "🔋 8.2/32GB"
ask "model name"            STATUSLINE_MODEL         "🧠 Sonnet 4.6"
ask "today tokens + cost"   STATUSLINE_TODAY         "Today: (🔸 45.2K 💰 \$0.156)"
ask "monthly cost"          STATUSLINE_MONTH         "Month: \$12.34"

echo ""
echo "Config written to $CONF"
echo ""
echo "Status line setup complete. Restart Claude Code to apply."
