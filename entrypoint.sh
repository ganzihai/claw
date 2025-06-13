#!/bin/bash

# 设置root用户SSH密码，如果未提供则使用默认值
SSH_PASSWORD=${SSH_PASSWORD:-admin123}
echo "root:$SSH_PASSWORD" | chpasswd

# 如果MySQL数据目录不存在，则进行初始化
if [ ! -d "/var/www/html/mysql/mysql" ]; then
    echo "Initializing MySQL database..."
    mysqld --initialize-insecure --user=mysql --datadir=/var/www/html/mysql
fi

# 如果cron任务文件存在，则加载它
if [ -f "/var/www/html/cron/maccms_cron" ]; then
    echo "Loading crontab file..."
    crontab /var/www/html/cron/maccms_cron
fi

# 启动cron文件监控脚本（后台运行）
/usr/local/bin/cron_monitor.sh &

# 启动Supervisor，它将管理所有其他服务
echo "Starting supervisord..."
exec /usr/bin/supervisord -c /etc/supervisor/supervisord.conf
