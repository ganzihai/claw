#!/bin/bash
set -e

# --- 1. Set SSH Password ---
if [ -n "$SSH_PASSWORD" ]; then
    echo "INFO: Root password is being set from the SSH_PASSWORD environment variable."
    PASSWORD=$SSH_PASSWORD
else
    # 生成随机密码而不是使用默认密码
    PASSWORD=$(openssl rand -base64 12)
    echo "INFO: SSH_PASSWORD environment variable not set. Generated random password: $PASSWORD"
    echo "IMPORTANT: Please save this password for future SSH access!"
fi
echo "root:$PASSWORD" | chpasswd
echo "INFO: SSH root password has been set."

# --- 2. Create Runtime Directories ---
echo "INFO: Creating runtime directories..."
mkdir -p /var/run/sshd
mkdir -p /var/run/php

# --- 3. Create All Necessary Persistent Directories ---
echo "INFO: Ensuring all persistent directories exist..."
mkdir -p /var/www/html/cloudsaver_data
mkdir -p /var/www/html/mysql_data
mkdir -p /var/www/html/logs
mkdir -p /var/www/html/supervisor/conf.d
mkdir -p /var/www/html/cron

# --- 4. Prepare CloudSaver Environment ---
echo "INFO: Preparing CloudSaver environment..."
PERSISTENT_ENV_FILE="/var/www/html/cloudsaver_data/.env"
SYMLINK_PATH="/opt/cloudsaver/.env"

if [ ! -f "$PERSISTENT_ENV_FILE" ]; then
    echo "INFO: No existing .env file found. Creating a default one..."
    # 使用随机JWT密钥而不是默认值
    JWT_SECRET=$(openssl rand -hex 32)
    echo "JWT_SECRET=$JWT_SECRET" > "$PERSISTENT_ENV_FILE"
    echo "INFO: Generated random JWT_SECRET for security."
else
    echo "INFO: Existing .env file found. Skipping creation."
fi
ln -sfn "$PERSISTENT_ENV_FILE" "$SYMLINK_PATH"
echo "INFO: CloudSaver is now linked to the persistent .env file."

# --- 5. Initialize MySQL Database ---
if [ -z "$(ls -A /var/www/html/mysql_data)" ]; then
    echo "INFO: MySQL data directory is empty. Initializing database..."
    mysqld --initialize-insecure --user=mysql --datadir=/var/www/html/mysql_data
    echo "INFO: Database initialized."
else
    echo "INFO: MySQL data directory already exists. Skipping initialization."
fi

# --- 6. Set Final Permissions (FIX for Maccms) ---
echo "INFO: Setting final permissions for persistent volume..."
# This chowns the entire directory, including the maccms subdirectory
chown -R www-data:www-data /var/www/html
chown -R mysql:mysql /var/www/html/mysql_data
# 添加更严格的权限设置
find /var/www/html -type d -exec chmod 755 {} \;
find /var/www/html -type f -exec chmod 644 {} \;
chmod -R 777 /var/www/html/maccms/runtime
chmod -R 777 /var/www/html/maccms/upload
echo "INFO: Permissions set."

# --- 7. Copy Supervisor Service Config ---
if [ -f "/services.conf" ]; then
    echo "INFO: Copying supervisor service configuration..."
    cp /services.conf /var/www/html/supervisor/conf.d/
    echo "INFO: Supervisor service configuration copied."
fi

# --- 8. Health Check - Wait for MySQL to start ---
echo "INFO: Starting all services via Supervisor..."
# 启动supervisor但不阻塞进程
/usr/bin/supervisord -c /etc/supervisor/supervisord.conf

# 等待MySQL启动
echo "INFO: Waiting for MySQL to become available..."
MAX_TRIES=30
COUNTER=0
while ! mysqladmin ping -h"127.0.0.1" --silent; do
    sleep 2
    COUNTER=$((COUNTER+1))
    if [ $COUNTER -ge $MAX_TRIES ]; then
        echo "ERROR: MySQL did not become available in time. Please check logs."
        break
    fi
    echo "INFO: Still waiting for MySQL... ($COUNTER/$MAX_TRIES)"
done

if [ $COUNTER -lt $MAX_TRIES ]; then
    echo "INFO: MySQL is now available."
fi

# 保持容器运行
echo "INFO: All services started. Container is now running."
exec "$@"
