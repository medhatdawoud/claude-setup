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

        # Format token count for git status line (will be populated later)
        GIT_BRANCH_BASE="$(printf ' \033[90m/\033[0m \033[32m🌿 \033[37m%s\033[0m' "$BRANCH")"
    fi
fi

# Resolve Claude config directory (respects CLAUDE_CONFIG_DIR env var)
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"

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
    BAR_FILLED=""
    [ "$FILLED" -gt 0 ] && BAR_FILLED=$(printf '%0.s━' $(seq 1 $FILLED 2>/dev/null))
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
    # Pricing per million tokens
    case "$MODEL_ID" in
        *"opus-4-5"*|*"opus-4-6"*)
            INPUT_COST_PER_M=5.00
            OUTPUT_COST_PER_M=25.00
            CACHE_WRITE_COST_PER_M=6.25
            CACHE_READ_COST_PER_M=0.50
            ;;
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
            INPUT_COST_PER_M=1.00
            OUTPUT_COST_PER_M=5.00
            CACHE_WRITE_COST_PER_M=1.25
            CACHE_READ_COST_PER_M=0.10
            ;;
        *)
            INPUT_COST_PER_M=3.00
            OUTPUT_COST_PER_M=15.00
            CACHE_WRITE_COST_PER_M=3.75
            CACHE_READ_COST_PER_M=0.30
            ;;
    esac

    # Calculate session cost from JSONL (includes all token types: input, cache_write, cache_read, output)
    SESSION_ID=$(echo "$input" | jq -r '.session_id // "unknown"')
    SESSION_JSONL=$(find "$CLAUDE_DIR/projects" -name "${SESSION_ID}.jsonl" 2>/dev/null | head -1)
    if [ -n "$SESSION_JSONL" ]; then
        TOTAL_COST=$(jq -r '
            select(.type == "assistant" and .message.id != null) |
            [.timestamp,
             .message.id,
             (.message.model // ""),
             (.message.usage.input_tokens // 0),
             (.message.usage.cache_creation_input_tokens // 0),
             (.message.usage.cache_read_input_tokens // 0),
             (.message.usage.output_tokens // 0)] | @tsv
        ' "$SESSION_JSONL" 2>/dev/null | \
        sort -t"	" -k1,1 | awk -F"	" '
            function cost(model, inp, cc, cr, out) {
                if (model ~ /opus-4-[56]/)
                    return (inp/1e6)*5 + (cc/1e6)*6.25 + (cr/1e6)*0.5 + (out/1e6)*25
                else if (model ~ /opus-4/)
                    return (inp/1e6)*15 + (cc/1e6)*18.75 + (cr/1e6)*1.5 + (out/1e6)*75
                else if (model ~ /haiku/)
                    return (inp/1e6)*1 + (cc/1e6)*1.25 + (cr/1e6)*0.1 + (out/1e6)*5
                else
                    return (inp/1e6)*3 + (cc/1e6)*3.75 + (cr/1e6)*0.3 + (out/1e6)*15
            }
            !seen[$2]++ { total += cost($3, $4, $5, $6, $7) }
            END { printf "%.3f", total+0 }
        ')
    else
        # Fallback: basic cost without cache tokens
        INPUT_COST=$(echo "$TOTAL_INPUT $INPUT_COST_PER_M" | awk '{printf "%.4f", ($1 / 1000000) * $2}')
        OUTPUT_COST=$(echo "$TOTAL_OUTPUT $OUTPUT_COST_PER_M" | awk '{printf "%.4f", ($1 / 1000000) * $2}')
        TOTAL_COST=$(echo "$INPUT_COST $OUTPUT_COST" | awk '{printf "%.3f", $1 + $2}')
    fi

    # Format token count
    TOTAL_TOKENS=$((TOTAL_INPUT + TOTAL_OUTPUT))
    if [ $TOTAL_TOKENS -ge 1000000 ]; then
        TOKEN_DISPLAY=$(echo "$TOTAL_TOKENS" | awk '{printf "%.1fM", $1/1000000}')
    elif [ $TOTAL_TOKENS -ge 1000 ]; then
        TOKEN_DISPLAY=$(echo "$TOTAL_TOKENS" | awk '{printf "%.1fK", $1/1000}')
    else
        TOKEN_DISPLAY="$TOTAL_TOKENS"
    fi

    # Calculate today's total cost by scanning JSONL files (same source as ccusage)
    TODAY_DATE=$(date +%Y-%m-%d)
    TODAY_CACHE="$CLAUDE_DIR/usage-today-cache.json"
    CACHE_AGE=60  # seconds TTL

    # Compute UTC start/end of local "today" for correct timezone-aware filtering
    # JSONL timestamps are UTC; local today may span two UTC dates
    TODAY_EPOCH=$(date -j -f "%Y-%m-%d %H:%M:%S" "$TODAY_DATE 00:00:00" "+%s" 2>/dev/null || \
                  date -d "$TODAY_DATE" "+%s" 2>/dev/null)
    TOMORROW_EPOCH=$((TODAY_EPOCH + 86400))
    TODAY_UTC=$(date -j -r "$TODAY_EPOCH" -u "+%Y-%m-%dT%H:%M:%S" 2>/dev/null || \
                date -u -d "@$TODAY_EPOCH" "+%Y-%m-%dT%H:%M:%S" 2>/dev/null)
    TOMORROW_UTC=$(date -j -r "$TOMORROW_EPOCH" -u "+%Y-%m-%dT%H:%M:%S" 2>/dev/null || \
                   date -u -d "@$TOMORROW_EPOCH" "+%Y-%m-%dT%H:%M:%S" 2>/dev/null)

    # Check if cache is valid (same day, within TTL)
    CACHE_VALID=0
    if [ -f "$TODAY_CACHE" ]; then
        CACHE_DATE=$(jq -r '.date // ""' "$TODAY_CACHE" 2>/dev/null)
        CACHE_TS=$(jq -r '.computed_at // 0' "$TODAY_CACHE" 2>/dev/null)
        NOW_TS=$(date +%s)
        if [ "$CACHE_DATE" = "$TODAY_DATE" ] && [ $((NOW_TS - CACHE_TS)) -lt $CACHE_AGE ]; then
            CACHE_VALID=1
        fi
    fi

    if [ "$CACHE_VALID" = "1" ]; then
        TODAY_TOTAL_RAW=$(jq -r '.total' "$TODAY_CACHE" 2>/dev/null)
        TODAY_TOKENS_RAW=$(jq -r '.tokens // 0' "$TODAY_CACHE" 2>/dev/null)
    else
        TODAY_SCAN_RAW=$(find "$CLAUDE_DIR/projects" -name "*.jsonl" -print0 2>/dev/null | \
            xargs -0 jq -r --arg today_utc "$TODAY_UTC" --arg tomorrow_utc "$TOMORROW_UTC" '
                select(
                    .type == "assistant" and
                    .message.id != null and
                    .timestamp >= $today_utc and
                    .timestamp < $tomorrow_utc
                ) |
                [.timestamp,
                 .message.id,
                 (.message.model // ""),
                 (.message.usage.input_tokens // 0),
                 (.message.usage.cache_creation_input_tokens // 0),
                 (.message.usage.cache_read_input_tokens // 0),
                 (.message.usage.output_tokens // 0)] | @tsv
            ' 2>/dev/null | \
            sort -t"	" -k1,1 | awk -F"	" '
                function cost(model, inp, cc, cr, out) {
                    if (model ~ /opus-4-[56]/)
                        return (inp/1e6)*5 + (cc/1e6)*6.25 + (cr/1e6)*0.5 + (out/1e6)*25
                    else if (model ~ /opus-4/)
                        return (inp/1e6)*15 + (cc/1e6)*18.75 + (cr/1e6)*1.5 + (out/1e6)*75
                    else if (model ~ /haiku/)
                        return (inp/1e6)*1 + (cc/1e6)*1.25 + (cr/1e6)*0.1 + (out/1e6)*5
                    else
                        return (inp/1e6)*3 + (cc/1e6)*3.75 + (cr/1e6)*0.3 + (out/1e6)*15
                }
                !seen[$2]++ { total += cost($3, $4, $5, $6, $7); tokens += $4+$5+$6+$7 }
                END { printf "%.3f\t%d", total+0, tokens+0 }
            ')
        TODAY_TOTAL_RAW=$(printf '%s' "$TODAY_SCAN_RAW" | cut -f1)
        TODAY_TOKENS_RAW=$(printf '%s' "$TODAY_SCAN_RAW" | cut -f2)
        NOW_TS=$(date +%s)
        printf '{"date":"%s","total":%s,"tokens":%s,"computed_at":%s}\n' \
            "$TODAY_DATE" "${TODAY_TOTAL_RAW:-0}" "${TODAY_TOKENS_RAW:-0}" "$NOW_TS" > "$TODAY_CACHE"
    fi

    TODAY_TOTAL=$(printf "%.3f" "${TODAY_TOTAL_RAW:-0}")

    # Build git status with session tokens and cost
    TOKEN_PART="$(printf ' \033[90m|\033[0m 🔸 \033[33m%s\033[0m 💰 \033[32m$%s\033[0m' "$TOKEN_DISPLAY" "$TOTAL_COST")"
    if ! command git diff --quiet 2>/dev/null || ! command git diff --cached --quiet 2>/dev/null; then
        GIT_STATUS="${GIT_BRANCH_BASE}${DIFF_DISPLAY}$(printf ' \033[33m*\033[0m')${TOKEN_PART}"
    else
        GIT_STATUS="${GIT_BRANCH_BASE}${TOKEN_PART}"
    fi

    METRICS=$(printf ' \033[90m|\033[0m \033[35m%d%%\033[0m %s' "$CONTEXT_PCT" "$CONTEXT_INFO")
fi

# Append rtk gain savings
RTK_GAIN_OUTPUT=$(rtk gain 2>/dev/null)
RTK_SAVED=$(echo "$RTK_GAIN_OUTPUT" | grep -oE 'Tokens saved:[[:space:]]+[0-9.]+[KMB]?' | grep -oE '[0-9.]+[KMB]?')
RTK_PCT=$(echo "$RTK_GAIN_OUTPUT" | grep -oE 'Tokens saved:.*\(([0-9.]+%)\)' | grep -oE '[0-9.]+%')
if [ -n "$RTK_SAVED" ] && [ -n "$RTK_PCT" ]; then
    METRICS="${METRICS}$(printf ' \033[90m|\033[0m ✂️ \033[32m%s (%s)\033[0m' "$RTK_SAVED" "$RTK_PCT")"
else
    METRICS="${METRICS}$(printf ' \033[90m|\033[0m ✂️ \033[90m0\033[0m')"
fi

# Append model name before today section
if [ -n "$MODEL_NAME" ] && [ "$MODEL_NAME" != "null" ]; then
    METRICS="${METRICS}$(printf ' \033[90m|\033[0m 🧠 \033[96m%s\033[0m' "$MODEL_NAME")"
fi

# Append today's stats at the end
if [ "${TODAY_TOKENS_RAW:-0}" -gt 0 ] 2>/dev/null; then
    if [ "$TODAY_TOKENS_RAW" -ge 1000000 ]; then
        TODAY_TOKEN_DISPLAY=$(echo "$TODAY_TOKENS_RAW" | awk '{printf "%.1fM", $1/1000000}')
    elif [ "$TODAY_TOKENS_RAW" -ge 1000 ]; then
        TODAY_TOKEN_DISPLAY=$(echo "$TODAY_TOKENS_RAW" | awk '{printf "%.1fK", $1/1000}')
    else
        TODAY_TOKEN_DISPLAY="$TODAY_TOKENS_RAW"
    fi
    METRICS="${METRICS}$(printf ' \033[90m|\033[0m Today: \033[37m(🔸 \033[33m%s\033[0m 💰 \033[32m$%s\033[37m)\033[0m' "$TODAY_TOKEN_DISPLAY" "$TODAY_TOTAL")"
fi

printf '\033[36m%s\033[0m%s%s' "$DIR_NAME" "$GIT_STATUS" "$METRICS"
