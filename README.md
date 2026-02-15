# Claude Code Configuration

This repository contains my personal Claude Code configuration, including system prompts, custom agents, skills, and setup scripts for portability across machines.

## What's Included

- **CLAUDE.md** - Global instructions and behavioral rules for Claude Code
- **statusline.sh** - Custom shell statusline integration
- **agents/** - Custom agent definitions:
  - code-review-specialist.md
  - react-frontend-builder.md
  - secure-backend-builder.md
  - tech-researcher.md
- **journal/** - Historical session summaries
- **skills/** - Skill definitions (contains symlink to external .agents directory)
- **setup.sh** - Automated setup script for new machines
- **claude_desktop_config.example.json** - MCP server configuration template

## Prerequisites

### External Dependencies

The `skills/` folder contains a symlink to `../../.agents/skills/remotion-best-practices`. You have two options:

1. **Keep symlink** (recommended if you have .agents directory):
   - Ensure you have the `.agents` directory structure set up
   - The symlink will point to the correct location

2. **Copy skill content into repo**:
   - Copy the actual skill file into this repo's `skills/` directory
   - Remove the symlink dependency

3. **Remove the skill**:
   - If not needed, delete the symlink

## Quick Setup (New Machine)

1. Clone this repository:
   ```bash
   git clone <your-repo-url> ~/.claude
   cd ~/.claude
   ```

2. Run the automated setup script:
   ```bash
   ./setup.sh
   ```

   The script will:
   - Create symlinks from this repo to `~/.claude/`
   - Optionally copy MCP config template
   - Create required directories
   - Backup any existing files

3. Configure MCP servers (if you copied the template):
   ```bash
   # Edit the MCP config and add your API keys
   open ~/Library/Application\ Support/Claude/claude_desktop_config.json
   ```

4. Verify the setup:
   ```bash
   ls -la ~/.claude
   # Should show symlinks pointing to this repo
   ```

## Manual Setup

If you prefer manual setup:

1. Create symlinks:
   ```bash
   cd ~
   ln -sf ~/.claude/CLAUDE.md ~/.claude/CLAUDE.md
   ln -sf ~/.claude/statusline.sh ~/.claude/statusline.sh
   ln -sf ~/.claude/agents ~/.claude/agents
   ln -sf ~/.claude/journal ~/.claude/journal
   ln -sf ~/.claude/skills ~/.claude/skills
   ```

2. Create required directories:
   ```bash
   mkdir -p ~/.claude/plans
   mkdir -p ~/.claude/cache
   ```

3. Copy MCP config template (optional):
   ```bash
   mkdir -p ~/Library/Application\ Support/Claude
   cp ~/.claude/claude_desktop_config.example.json \
      ~/Library/Application\ Support/Claude/claude_desktop_config.json
   ```

## Updating Configuration

Since the setup uses symlinks, changes are automatic:

```bash
cd ~/.claude
git pull
# Changes are immediately available to Claude Code
```

To commit your changes:

```bash
cd ~/.claude
git add -A
git commit -m "Update configuration"
git push
```

## Security Notes

### MCP Configuration

The `claude_desktop_config.json` file is **excluded from version control** because it often contains API keys and secrets.

- The repo includes `claude_desktop_config.example.json` as a template
- Always review the example file before committing to ensure no secrets are included
- On new machines, copy the example and fill in your actual API keys

### Before Committing

Always check for secrets:

```bash
git grep -i 'api.*key\|secret\|token'
```

## What's Not Included (Excluded by .gitignore)

These directories contain session-specific or temporary data:

- `history.jsonl` - Session history
- `debug/` - Debug logs
- `plans/` - Plan files (temporary artifacts)
- `projects/` - Project snapshots (belong in actual repos)
- `session-env/`, `shell-snapshots/`, `todos/`, `paste-cache/` - Session artifacts
- `plugins/` - Downloaded marketplace data
- `cache/`, `file-history/` - Cached/generated data
- `stats-cache.json`, `statsig/`, `telemetry/` - Analytics
- `settings.json` - User-specific settings

## Directory Structure

```
~/.claude/
├── CLAUDE.md                      # Global instructions
├── statusline.sh                  # Shell integration
├── setup.sh                       # Setup script
├── README.md                      # This file
├── .gitignore                     # Exclusions
├── claude_desktop_config.example.json  # MCP template
├── agents/                        # Custom agents
│   ├── code-review-specialist.md
│   ├── react-frontend-builder.md
│   ├── secure-backend-builder.md
│   └── tech-researcher.md
├── journal/                       # Session summaries
│   └── *.md
└── skills/                        # Skill definitions
    └── remotion-best-practices -> ../../.agents/skills/remotion-best-practices
```

## Troubleshooting

### Symlinks not working

Check that symlinks point to correct locations:
```bash
ls -la ~/.claude
```

If broken, re-run `./setup.sh` or create symlinks manually.

### MCP servers not loading

1. Check config file exists:
   ```bash
   cat ~/Library/Application\ Support/Claude/claude_desktop_config.json
   ```

2. Verify JSON syntax is valid

3. Check MCP server paths and API keys

### Skills symlink broken

If `skills/remotion-best-practices` symlink is broken:
- Copy the actual skill file into `skills/` directory
- Or set up the `.agents` directory structure at the expected location

## Contributing (Personal Use)

This is a personal configuration repo, but if you want to adapt it:

1. Fork this repo
2. Customize CLAUDE.md, agents, and skills for your needs
3. Update README with your setup
4. Share with your other machines

## License

Personal configuration - use as you like.
