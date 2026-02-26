# RTK

RTK is a token-optimizing CLI proxy that wraps common commands to reduce token usage and track costs.

## How it works

A `PreToolUse:Bash` hook transparently rewrites commands to their `rtk` equivalents before execution. You do NOT need to manually prefix commands with `rtk` — the hook handles this automatically.

Commands covered: `git`, `gh`, `cargo`, `cat`, `grep`, `rg`, `ls`, `tree`, `find`, `diff`, `head`, `vitest`, `tsc`, `eslint`, `prettier`, `playwright`, `prisma`, `docker`, `kubectl`, `curl`, `wget`, `pnpm`, `pytest`, `ruff`, `pip`, `go`, and more.

Unrecognized commands fall back to `rtk proxy <cmd>` for tracking.

## Statusline

Token savings are displayed in the statusline via `rtk gain`.

## Notes

- If `rtk` is not installed, the hook exits silently and commands run normally
- Never manually prefix commands with `rtk` — the hook does it
