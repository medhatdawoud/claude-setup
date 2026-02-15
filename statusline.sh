#!/bin/bash
input=$(cat)

DIR=$(echo "$input" | jq -r '.workspace.current_dir')
DIR_NAME=$(basename "$DIR")

# Get git branch if in a git repo
cd "$DIR" 2>/dev/null
if command git rev-parse --git-dir > /dev/null 2>&1; then
    BRANCH=$(command git symbolic-ref --short HEAD 2>/dev/null || command git rev-parse --short HEAD 2>/dev/null)
    if [ -n "$BRANCH" ]; then
        # Check if there are uncommitted changes
        if ! command git diff --quiet 2>/dev/null || ! command git diff --cached --quiet 2>/dev/null; then
            GIT_STATUS=" $(printf '\033[34mgit:(\033[31m%s\033[34m) \033[33m✗\033[0m' "$BRANCH")"
        else
            GIT_STATUS=" $(printf '\033[34mgit:(\033[31m%s\033[34m)\033[0m' "$BRANCH")"
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

    # Calculate current context percentage
    if [ "$CURRENT_USAGE" != "null" ]; then
        INPUT_TOKENS=$(echo "$CURRENT_USAGE" | jq -r '.input_tokens')
        CACHE_CREATE=$(echo "$CURRENT_USAGE" | jq -r '.cache_creation_input_tokens')
        CACHE_READ=$(echo "$CURRENT_USAGE" | jq -r '.cache_read_input_tokens')
        CURRENT_CONTEXT=$((INPUT_TOKENS + CACHE_CREATE + CACHE_READ))
        CONTEXT_PCT=$((CURRENT_CONTEXT * 100 / WINDOW_SIZE))
        CONTEXT_INFO=$(printf '\033[35m%d%%\033[0m' "$CONTEXT_PCT")
    else
        CONTEXT_INFO=$(printf '\033[35m0%%\033[0m')
    fi

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

    METRICS=$(printf ' \033[90m|\033[0m \033[96m%s\033[0m \033[90m|\033[0m ctx: %s \033[90m|\033[0m \033[33m%s\033[0m tok \033[90m|\033[0m cost: \033[32m$%s\033[0m' "$MODEL_NAME" "$CONTEXT_INFO" "$TOKEN_DISPLAY" "$TOTAL_COST")
fi

# Green arrow + cyan directory + git info + metrics (matching robbyrussell theme)
printf '\033[32m➜\033[0m  \033[36m%s\033[0m%s%s' "$DIR_NAME" "$GIT_STATUS" "$METRICS"
