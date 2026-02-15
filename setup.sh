#!/bin/bash
# Setup Claude Code configuration on new machine

set -e  # Exit on error

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
CLAUDE_DIR="$HOME/.claude"
CLAUDE_DESKTOP_CONFIG="$HOME/Library/Application Support/Claude"

echo "Setting up Claude Code configuration..."
echo ""

# Create .claude directory if it doesn't exist
mkdir -p "$CLAUDE_DIR"

# Backup existing files if they exist
backup_if_exists() {
    local file="$1"
    if [ -e "$file" ] && [ ! -L "$file" ]; then
        local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"
        echo "Backing up existing file: $file -> $backup"
        mv "$file" "$backup"
    fi
}

# Symlink files
echo "Creating symlinks..."
backup_if_exists "$CLAUDE_DIR/CLAUDE.md"
ln -sf "$REPO_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"

backup_if_exists "$CLAUDE_DIR/statusline.sh"
ln -sf "$REPO_DIR/statusline.sh" "$CLAUDE_DIR/statusline.sh"

backup_if_exists "$CLAUDE_DIR/agents"
ln -sf "$REPO_DIR/agents" "$CLAUDE_DIR/agents"

backup_if_exists "$CLAUDE_DIR/journal"
ln -sf "$REPO_DIR/journal" "$CLAUDE_DIR/journal"

backup_if_exists "$CLAUDE_DIR/skills"
ln -sf "$REPO_DIR/skills" "$CLAUDE_DIR/skills"

# Setup MCP config (if example exists and user wants to copy)
if [ -f "$REPO_DIR/claude_desktop_config.example.json" ]; then
    mkdir -p "$CLAUDE_DESKTOP_CONFIG"
    echo ""
    read -p "Copy MCP config template? (y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cp "$REPO_DIR/claude_desktop_config.example.json" "$CLAUDE_DESKTOP_CONFIG/claude_desktop_config.json"
        echo "MCP config copied to: $CLAUDE_DESKTOP_CONFIG/claude_desktop_config.json"
        echo "WARNING: Edit this file to add your API keys and configure your MCP servers"
    fi
fi

# Create required directories
mkdir -p "$CLAUDE_DIR/plans"
mkdir -p "$CLAUDE_DIR/cache"

echo ""
echo "Setup complete!"
echo ""
echo "IMPORTANT NOTES:"
echo "1. The skills/ folder has a symlink to ../../.agents/skills/remotion-best-practices"
echo "   Make sure you have the .agents directory set up at the appropriate location"
echo "2. If you copied the MCP config, edit it to add your API keys"
echo "3. Your original files (if any) were backed up with .backup.TIMESTAMP extension"
echo ""
echo "You can now use Claude Code with your custom configuration."
