#!/bin/bash
# Ring bell when Claude is waiting for human input.
printf '\a' > /dev/tty 2>/dev/null
afplay /System/Library/Sounds/Funk.aiff 2>/dev/null &
exit 0
