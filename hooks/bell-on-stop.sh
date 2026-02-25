#!/bin/bash
# Ring terminal bell when Claude is waiting for human input.
# Skip if the user is already active in Ghostty.
FRONTMOST=$(osascript -e 'tell application "System Events" to name of first application process whose frontmost is true' 2>/dev/null)
if [ "$FRONTMOST" != "ghostty" ]; then
    printf '\a' > /dev/tty 2>/dev/null
fi
exit 0
