#!/bin/bash

# 定义目标文件路径
CRON_FILE="/var/www/html/cron/maccms_cron"
CRON_MD5_FILE="/tmp/maccms_cron.md5"

# 确保目录存在
mkdir -p /var/www/html/cron

# 如果cron文件不存在，创建一个空文件
if [ ! -f "$CRON_FILE" ]; then
    touch "$CRON_FILE"
    echo "创建了空的cron文件: $CRON_FILE"
fi

# 如果MD5文件不存在，创建一个
if [ ! -f "$CRON_MD5_FILE" ]; then
    md5sum "$CRON_FILE" > "$CRON_MD5_FILE"
    # 首次加载cron任务
    crontab "$CRON_FILE"
    echo "首次加载cron任务: $(date)"
    exit 0
fi

# 检查文件是否有变化
OLD_MD5=$(cat "$CRON_MD5_FILE")
NEW_MD5=$(md5sum "$CRON_FILE")

if [ "$OLD_MD5" != "$NEW_MD5" ]; then
    # 文件已更改，更新cron任务
    echo "$NEW_MD5" > "$CRON_MD5_FILE"
    
    # 检查cron文件格式是否正确
    if crontab -l 2>/dev/null | crontab -; then
        # 加载新的cron任务
        crontab "$CRON_FILE"
        echo "cron任务已更新: $(date)" >> /var/log/cron_monitor.log
    else
        echo "cron文件格式错误，未更新: $(date)" >> /var/log/cron_monitor.log
    fi
fi
