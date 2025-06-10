#!/bin/bash

# 定义目标文件路径
CRON_FILE="/var/www/html/cron/maccms_cron"
CRON_MD5_FILE="/tmp/maccms_cron.md5"
LOG_FILE="/var/log/cron_monitor.log"

# 记录日志函数
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
    echo "$1"
}

# 确保日志文件存在
touch "$LOG_FILE"

# 确保目录存在
mkdir -p /var/www/html/cron

# 如果cron文件不存在，创建一个空文件
if [ ! -f "$CRON_FILE" ]; then
    touch "$CRON_FILE"
    log_message "创建了空的cron文件: $CRON_FILE"
fi

# 检查cron文件权限
if [ "$(stat -c %a "$CRON_FILE")" != "644" ]; then
    chmod 644 "$CRON_FILE"
    log_message "修正了cron文件权限: $CRON_FILE"
fi

# 如果MD5文件不存在，创建一个
if [ ! -f "$CRON_MD5_FILE" ]; then
    md5sum "$CRON_FILE" > "$CRON_MD5_FILE"
    # 首次加载cron任务
    if [ -s "$CRON_FILE" ]; then  # 检查文件是否为空
        if crontab "$CRON_FILE" 2>/dev/null; then
            log_message "首次加载cron任务成功"
        else
            log_message "首次加载cron任务失败，请检查cron文件格式"
        fi
    else
        log_message "cron文件为空，跳过首次加载"
    fi
    exit 0
fi

# 检查文件是否有变化
OLD_MD5=$(cat "$CRON_MD5_FILE")
NEW_MD5=$(md5sum "$CRON_FILE")

if [ "$OLD_MD5" != "$NEW_MD5" ]; then
    # 文件已更改，更新MD5
    echo "$NEW_MD5" > "$CRON_MD5_FILE"
    log_message "检测到cron文件变化"
    
    # 检查cron文件是否为空
    if [ ! -s "$CRON_FILE" ]; then
        # 文件为空，清除所有cron任务
        crontab -r 2>/dev/null
        log_message "cron文件为空，已清除所有cron任务"
        exit 0
    fi
    
    # 检查cron文件格式是否正确
    if crontab -l 2>/dev/null | crontab -; then
        # 加载新的cron任务
        if crontab "$CRON_FILE" 2>/dev/null; then
            log_message "cron任务已成功更新"
        else
            log_message "cron任务更新失败，请检查cron文件格式"
        fi
    else
        log_message "cron文件格式错误，未更新"
    fi
else
    # 文件未变化，不做任何操作
    exit 0
fi
