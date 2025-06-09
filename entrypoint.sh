#!/bin/bash
set -e

# --- 1. Set SSH Password ---
# Use the SSH_PASSWORD environment variable if it exists, otherwise use a default.
if [ -n "$SSH_PASSWORD" ]; then
    echo "INFO: Root password is being set from the SSH_PASSWORD environment variable."
    PASSWORD=$SSH_PASSWORD
else
    echo "INFO: SSH_PASSWORD environment variable not set. Using default password 'admin123'."
    PASSWORD="admin123"
fi
# Apply the password to the root user
echo "root:$PASSWORD" | chpasswd
echo "INFO: SSH root password has been set."


# --- 2. Prepare CloudSaver Environment (NEW SECTION) ---
echo "INFO: Preparing CloudSaver environment..."
# The CloudSaver app expects a 'data' directory in its CWD for config/data.
# We will symlink our persistent data dir to the location the app expects.
ln -sfn /var/www/html/cloudsaver_data /opt/cloudsaver/data
# Copy the default config file if one doesn't already exist in the persistent volume.
# The `cp -n` flag ensures we don't overwrite an existing, user-modified config.
cp -n /opt/cloudsaver/config/config.yaml /var/www/html/cloudsaver_data/config.yaml
echo "INFO: CloudSaver environment is ready."


# --- 3. Set permissions for the mounted volume ---
# This now includes the new cloudsaver directory
chown -R www-data:www-data /var/www/html
chown -R mysql:mysql /var/www/html/mysql_data


# --- 4. Initialize MySQL Database if not already initialized ---
if [ -z "$(ls -A /var/www/html/mysql_data)" ]; then
    echo "INFO: MySQL data directory is empty. Initializing database..."
    mysqld --initialize-insecure --user=mysql --datadir=/var/www/html/mysql_data
    echo "INFO: Database initialized."
else
    echo "INFO: MySQL data directory already exists. Skipping initialization."
fi

echo "INFO: Starting all services via Supervisor..."

# Execute the command passed to the script (CMD from Dockerfile)
exec "$@"
