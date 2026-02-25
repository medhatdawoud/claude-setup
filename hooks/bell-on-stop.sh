#!/bin/bash
# Ring terminal bell when Claude is waiting for human input
printf '\a' > /dev/tty 2>/dev/null
exit 0
