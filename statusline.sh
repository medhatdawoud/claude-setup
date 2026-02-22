#!/bin/bash
input=$(cat)

DIR=$(echo "$input" | jq -r '.workspace.current_dir')
DIR_NAME=$(basename "$DIR")

# Get git branch if in a git repo
cd "$DIR" 2>/dev/null
if command git rev-parse --git-dir > /dev/null 2>&1; then
    BRANCH=$(command git symbolic-ref --short HEAD 2>/dev/null || command git rev-parse --short HEAD 2>/dev/null)
    if [ -n "$BRANCH" ]; then
        # Get diff stats for uncommitted changes (staged + unstaged)
        DIFF_STATS=$(command git diff --numstat HEAD 2>/dev/null | awk '{added+=$1; deleted+=$2} END {print added, deleted}')
        ADDITIONS=$(echo "$DIFF_STATS" | awk '{print $1}')
        DELETIONS=$(echo "$DIFF_STATS" | awk '{print $2}')

        # Build diff display
        DIFF_DISPLAY=""
        if [ -n "$ADDITIONS" ] && [ "$ADDITIONS" != "0" ]; then
            DIFF_DISPLAY="${DIFF_DISPLAY}$(printf ' \033[32m+%s\033[0m' "$ADDITIONS")"
        fi
        if [ -n "$DELETIONS" ] && [ "$DELETIONS" != "0" ]; then
            DIFF_DISPLAY="${DIFF_DISPLAY}$(printf ' \033[31m-%s\033[0m' "$DELETIONS")"
        fi

        # Check if there are uncommitted changes
        if ! command git diff --quiet 2>/dev/null || ! command git diff --cached --quiet 2>/dev/null; then
            GIT_STATUS="$(printf ' \033[90m/\033[0m \033[32m🌿 \033[37m%s\033[0m' "$BRANCH")${DIFF_DISPLAY}$(printf ' \033[33m*\033[0m')"
        else
            GIT_STATUS="$(printf ' \033[90m/\033[0m \033[32m🌿 \033[37m%s\033[0m' "$BRANCH")"
        fi
    fi
fi

# Calculate context usage, tokens, and cost
METRICS=""
MODEL_ID=$(echo "$input" | jq -r '.model.id')
MODEL_NAME=$(echo "$input" | jq -r '.model.display_name')
CONTEXT_WINDOW=$(echo "$input" | jq -r '.context_window')

if [ "$CONTEXT_WINDOW" != "null" ]; then
    TOTAL_INPUT=$(echo "$CONTEXT_WINDOW" | jq -r '.total_input_tokens')
    TOTAL_OUTPUT=$(echo "$CONTEXT_WINDOW" | jq -r '.total_output_tokens')
    WINDOW_SIZE=$(echo "$CONTEXT_WINDOW" | jq -r '.context_window_size')
    CURRENT_USAGE=$(echo "$CONTEXT_WINDOW" | jq '.current_usage')

    # Calculate current context as a thin progress bar (12 chars = ~8.3% per segment)
    BAR_WIDTH=12
    if [ "$CURRENT_USAGE" != "null" ]; then
        INPUT_TOKENS=$(echo "$CURRENT_USAGE" | jq -r '.input_tokens')
        CACHE_CREATE=$(echo "$CURRENT_USAGE" | jq -r '.cache_creation_input_tokens')
        CACHE_READ=$(echo "$CURRENT_USAGE" | jq -r '.cache_read_input_tokens')
        CURRENT_CONTEXT=$((INPUT_TOKENS + CACHE_CREATE + CACHE_READ))
        CONTEXT_PCT=$((CURRENT_CONTEXT * 100 / WINDOW_SIZE))
        FILLED=$((CONTEXT_PCT * BAR_WIDTH / 100))
    else
        CONTEXT_PCT=0
        FILLED=0
    fi
    EMPTY=$((BAR_WIDTH - FILLED))
    BAR_FILLED=$(printf '%0.s━' $(seq 1 $FILLED 2>/dev/null))
    BAR_EMPTY=$(printf '%0.s─' $(seq 1 $EMPTY 2>/dev/null))
    # Color: green <50%, yellow 50-79%, red 80%+
    if [ "$CONTEXT_PCT" -ge 80 ]; then
        BAR_COLOR='\033[31m'
    elif [ "$CONTEXT_PCT" -ge 50 ]; then
        BAR_COLOR='\033[33m'
    else
        BAR_COLOR='\033[32m'
    fi
    CONTEXT_INFO=$(printf '%b%s\033[90m%s\033[0m' "$BAR_COLOR" "$BAR_FILLED" "$BAR_EMPTY")

    # Calculate session cost based on model pricing
    # Pricing per million tokens (as of Jan 2025)
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

    # Calculate cost (tokens / 1,000,000 * price)
    INPUT_COST=$(echo "$TOTAL_INPUT $INPUT_COST_PER_M" | awk '{printf "%.4f", ($1 / 1000000) * $2}')
    OUTPUT_COST=$(echo "$TOTAL_OUTPUT $OUTPUT_COST_PER_M" | awk '{printf "%.4f", ($1 / 1000000) * $2}')
    TOTAL_COST=$(echo "$INPUT_COST $OUTPUT_COST" | awk '{printf "%.3f", $1 + $2}')

    # Format token count
    TOTAL_TOKENS=$((TOTAL_INPUT + TOTAL_OUTPUT))
    if [ $TOTAL_TOKENS -ge 1000000 ]; then
        TOKEN_DISPLAY=$(echo "$TOTAL_TOKENS" | awk '{printf "%.1fM", $1/1000000}')
    elif [ $TOTAL_TOKENS -ge 1000 ]; then
        TOKEN_DISPLAY=$(echo "$TOTAL_TOKENS" | awk '{printf "%.1fK", $1/1000}')
    else
        TOKEN_DISPLAY="$TOTAL_TOKENS"
    fi

    # Track and calculate today's total usage
    USAGE_LOG="$HOME/.claude/usage-log.json"
    SESSION_ID=$(echo "$input" | jq -r '.session_id // "unknown"')
    TIMESTAMP=$(date +%s)
    TODAY_START=$(date -j -v0H -v0M -v0S +%s 2>/dev/null || date -d "$(date +%Y-%m-%d) 00:00:00" +%s 2>/dev/null)

    # Initialize log if it doesn't exist
    if [ ! -f "$USAGE_LOG" ]; then
        echo "[]" > "$USAGE_LOG"
    fi

    # Update usage log with current session first
    jq --arg sid "$SESSION_ID" --arg cost "$TOTAL_COST" --arg ts "$TIMESTAMP" \
       'map(select(.session_id != $sid)) + [{"session_id": $sid, "cost": ($cost | tonumber), "timestamp": ($ts | tonumber)}]' \
       "$USAGE_LOG" > "${USAGE_LOG}.tmp" 2>/dev/null && mv "${USAGE_LOG}.tmp" "$USAGE_LOG"

    # Now calculate today's total from the updated log
    TODAY_TOTAL_RAW=$(jq -r --arg today_start "$TODAY_START" \
        'map(select(.timestamp >= ($today_start | tonumber)) | .cost) | add // 0' \
        "$USAGE_LOG" 2>/dev/null || echo "0")
    TODAY_TOTAL=$(echo "$TODAY_TOTAL_RAW" | awk '{printf "%.3f", $1}')

    COST_DISPLAY=$(printf '\033[32m$%s\033[0m \033[37m(today: $%s)\033[0m' "$TOTAL_COST" "$TODAY_TOTAL")

    METRICS=$(printf ' \033[90m|\033[0m \033[35m%d%%\033[0m %s \033[90m|\033[0m ⚡ \033[33m%s\033[0m \033[90m|\033[0m 💵 %s' "$CONTEXT_PCT" "$CONTEXT_INFO" "$TOKEN_DISPLAY" "$COST_DISPLAY")
fi

# Session lifetime
DURATION_MS=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
if [ "$DURATION_MS" != "0" ] && [ "$DURATION_MS" != "null" ]; then
    DURATION_SEC=$((DURATION_MS / 1000))
    HOURS=$((DURATION_SEC / 3600))
    MINS=$(((DURATION_SEC % 3600) / 60))
    SECS=$((DURATION_SEC % 60))
    if [ $HOURS -gt 0 ]; then
        TIME_DISPLAY="${HOURS}h ${MINS}m"
    elif [ $MINS -gt 0 ]; then
        TIME_DISPLAY="${MINS}m ${SECS}s"
    else
        TIME_DISPLAY="${SECS}s"
    fi
    METRICS="${METRICS}$(printf ' \033[90m|\033[0m 🕐 \033[95m%s\033[0m' "$TIME_DISPLAY")"
fi

# Append model name at the end
if [ -n "$MODEL_NAME" ] && [ "$MODEL_NAME" != "null" ]; then
    METRICS="${METRICS}$(printf ' \033[90m|\033[0m 🧠 \033[96m%s\033[0m' "$MODEL_NAME")"
fi

printf '📂 \033[36m%s\033[0m%s%s' "$DIR_NAME" "$GIT_STATUS" "$METRICS"
