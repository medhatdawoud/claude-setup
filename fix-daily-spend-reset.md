# Fix: Daily Spend Not Resetting for Long Sessions

## Context

The statusline script tracks daily spending via `~/.claude/usage-log.json`. Sessions that stay open across midnight have their entire cumulative cost attributed to the new day because the log entry's `timestamp` gets refreshed on every update, but the `cost` remains the full session cumulative cost.

**File:** `statusline.sh` (lines 120-141)

## Root Cause

Current data model: `{session_id, cost, timestamp}`

On every statusline refresh (line 132-134), the script replaces the session entry with the current timestamp. The "today" filter (line 137-139) sums all entries with `timestamp >= today_start`. A session that started yesterday with $5 gets a fresh timestamp today, so the full $5 shows as "today" spend.

## Fix

Extend the data model to: `{session_id, cost, timestamp, day_start_cost, date}`

- `day_start_cost`: the cumulative cost at the start of the current day (carryover)
- `date`: the date string (YYYY-MM-DD) when this entry was last updated

**Update logic:**
1. Look up existing entry for this session
2. If entry exists and its `date` matches today -> update `cost` and `timestamp` only
3. If entry exists and its `date` is different -> set `day_start_cost = old cost`, set `date = today`, update `cost` and `timestamp`
4. If no entry exists -> create with `day_start_cost = 0`, `date = today`

**Today's total calculation:**
- Filter entries where `date == today`
- Sum `(cost - day_start_cost)` for each

**Auto-prune:** Remove entries where `date` is older than 7 days.

## Technical Reasoning

- Using `date` string (YYYY-MM-DD) instead of comparing timestamps avoids timezone edge cases with midnight calculations
- `day_start_cost` is simpler than storing per-day cost deltas or a history array
- Pruning by date string comparison is straightforward and avoids stale data accumulation
- All jq operations remain a single pipeline per step to avoid temp file proliferation

## Verification

1. Check current `usage-log.json` before and after running the script
2. Manually test by setting a fake "yesterday" date on an entry and verifying today's cost excludes the carryover
3. Verify the log gets pruned of entries older than 7 days
