# Fix: Opus 4.5/4.6 Pricing in Statusline

## Problem
Statusline today-total was ~2x higher than ccusage for the same day. User reported the mismatch.

## Root Cause
`statusline.sh` used `*"opus-4"*` pattern which matched `claude-opus-4-6` and applied old opus-4 pricing ($15/$75/$18.75/$1.5 per million). The actual pricing for opus-4-5 and opus-4-6 is $5/$25/$6.25/$0.5 per million (3x cheaper).

Confirmed via LiteLLM pricing DB (the source ccusage fetches live from GitHub).

## Fix
Added `*"opus-4-5"*|*"opus-4-6"*` pattern BEFORE the generic `*"opus-4"*` in:
1. The `case` statement (session cost display)
2. Both `awk` cost functions (session JSONL scan and today-total JSONL scan)

Kept `*"opus-4"*` as fallback for legacy `claude-opus-4-20250514` model ($15/$75).

## Verification
After fix, statusline matches ccusage to $0.000 difference.

## Key Findings
- ccusage fetches live pricing from `https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json`
- ccusage deduplicates by `message.id:requestId` composite key (our `message.id`-only gives same results since no messages have same id with different requestIds)
- ccusage's offline pricing cache doesn't have opus-4-6; it relies on live fetch
- Opus-4 ($15/$75) vs Opus-4-5/4-6 ($5/$25) pricing distinction is important

## Commit
d05339e
