#!/bin/bash
# SubagentStop hook: calculates subagent cost and adds it to the daily total in usage-log.json.
# Receives JSON on stdin with agent_id and agent_transcript_path.
# Exits 0 silently in all cases to avoid interfering with Claude.

input=$(cat)

AGENT_ID=$(echo "$input" | jq -r '.agent_id // empty')
TRANSCRIPT_PATH=$(echo "$input" | jq -r '.agent_transcript_path // empty')

# Exit silently if required fields are missing or transcript doesn't exist
[ -z "$AGENT_ID" ] || [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ] && exit 0

USAGE_LOG="$HOME/.claude/usage-log.json"
TODAY_DATE=$(date +%Y-%m-%d)
CUTOFF_DATE=$(date -j -v-7d +%Y-%m-%d 2>/dev/null || date -d "7 days ago" +%Y-%m-%d 2>/dev/null)

# Initialize or migrate log (old format check matches statusline.sh guard)
if [ ! -f "$USAGE_LOG" ] || ! jq -e 'has("sessions")' "$USAGE_LOG" >/dev/null 2>&1; then
    echo '{"sessions":{},"daily":{},"subagent_sessions":{}}' > "$USAGE_LOG"
fi

# Skip if this agent was already processed (prevents double-counting on re-run)
if jq -e --arg aid "$AGENT_ID" 'has("subagent_sessions") and (.subagent_sessions | has($aid))' "$USAGE_LOG" >/dev/null 2>&1; then
    exit 0
fi

# Parse transcript JSONL:
# - Keep only entries with a message.id (actual API responses)
# - Deduplicate by message.id (same response can appear under multiple event types)
# - Sum token counts across unique messages
# - Take model from first entry that has one
TRANSCRIPT_DATA=$(jq -sc '
    [.[] | select(.message.id != null and .message.id != "")] |
    reduce .[] as $e (
        {"seen": {}, "entries": []};
        if .seen[$e.message.id]
        then .
        else .seen[$e.message.id] = true | .entries += [$e]
        end
    ) |
    .entries |
    {
        "model": (map(select(.message.model != null and .message.model != "")) | first | .message.model // ""),
        "input_tokens": (map(.message.usage.input_tokens // 0) | add // 0),
        "cache_creation_tokens": (map(.message.usage.cache_creation_input_tokens // 0) | add // 0),
        "cache_read_tokens": (map(.message.usage.cache_read_input_tokens // 0) | add // 0),
        "output_tokens": (map(.message.usage.output_tokens // 0) | add // 0)
    }
' "$TRANSCRIPT_PATH" 2>/dev/null)

[ -z "$TRANSCRIPT_DATA" ] && exit 0

MODEL_ID=$(echo "$TRANSCRIPT_DATA" | jq -r '.model // ""')
INPUT_TOKENS=$(echo "$TRANSCRIPT_DATA" | jq -r '.input_tokens')
CACHE_CREATE=$(echo "$TRANSCRIPT_DATA" | jq -r '.cache_creation_tokens')
CACHE_READ=$(echo "$TRANSCRIPT_DATA" | jq -r '.cache_read_tokens')
OUTPUT_TOKENS=$(echo "$TRANSCRIPT_DATA" | jq -r '.output_tokens')

# Pricing table (matches statusline.sh)
case "$MODEL_ID" in
    *"opus-4"*)
        INPUT_COST_PER_M=15.00
        OUTPUT_COST_PER_M=75.00
        CACHE_WRITE_COST_PER_M=18.75
        CACHE_READ_COST_PER_M=1.50
        ;;
    *"sonnet-4"*)
        INPUT_COST_PER_M=3.00
        OUTPUT_COST_PER_M=15.00
        CACHE_WRITE_COST_PER_M=3.75
        CACHE_READ_COST_PER_M=0.30
        ;;
    *"sonnet"*|*"claude-3-5"*)
        INPUT_COST_PER_M=3.00
        OUTPUT_COST_PER_M=15.00
        CACHE_WRITE_COST_PER_M=3.75
        CACHE_READ_COST_PER_M=0.30
        ;;
    *"haiku"*)
        INPUT_COST_PER_M=0.80
        OUTPUT_COST_PER_M=4.00
        CACHE_WRITE_COST_PER_M=1.00
        CACHE_READ_COST_PER_M=0.08
        ;;
    *)
        INPUT_COST_PER_M=3.00
        OUTPUT_COST_PER_M=15.00
        CACHE_WRITE_COST_PER_M=3.75
        CACHE_READ_COST_PER_M=0.30
        ;;
esac

# Calculate total cost for this subagent
COST=$(echo "$INPUT_TOKENS $CACHE_CREATE $CACHE_READ $OUTPUT_TOKENS $INPUT_COST_PER_M $OUTPUT_COST_PER_M $CACHE_WRITE_COST_PER_M $CACHE_READ_COST_PER_M" | awk '{
    printf "%.6f", ($1/1000000)*$5 + ($2/1000000)*$7 + ($3/1000000)*$8 + ($4/1000000)*$6
}')

# Update usage-log.json: record agent cost, accumulate into daily, prune old entries
jq --arg aid "$AGENT_ID" --arg cost "$COST" --arg today "$TODAY_DATE" --arg cutoff "$CUTOFF_DATE" '
    ($cost | tonumber) as $c |
    if has("subagent_sessions") | not then . + {"subagent_sessions": {}} else . end |
    .subagent_sessions[$aid] = $c |
    .daily[$today] = ((.daily[$today] // 0) + $c) |
    .daily |= with_entries(select(.key >= $cutoff))
' "$USAGE_LOG" > "${USAGE_LOG}.tmp" 2>/dev/null && mv "${USAGE_LOG}.tmp" "$USAGE_LOG"

exit 0
