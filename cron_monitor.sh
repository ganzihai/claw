#!/bin/bash

CRON_FILE="/var/www/html/cron/maccms_cron"
LAST_MODIFIED=""

while true; do
    if [ -f "$CRON_FILE" ]; then
        CURRENT_MODIFIED=$(stat -c %Y "$CRON_FILE" 2>/dev/null)
        if [ "$CURRENT_MODIFIED" != "$LAST_MODIFIED" ]; then
            echo "Crontab file changed. Reloading..."
            crontab "$CRON_FILE"
            LAST_MODIFIED="$CURRENT_MODIFIED"
        fi
    fi
    sleep 30
done
