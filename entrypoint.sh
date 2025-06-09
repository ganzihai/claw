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


# --- 2. Set permissions for the mounted volume ---
# Ensures that the web server and other services can write to the volume
chown -R www-data:www-data /var/www/html
chown -R mysql:mysql /var/www/html/mysql_data


# --- 3. Initialize MySQL Database if not already initialized ---
if [ -z "$(ls -A /var/www/html/mysql_data)" ]; then
    echo "INFO: MySQL data directory is empty. Initializing database..."
    # Using --initialize-insecure to not generate a random root password.
    # You should set a password immediately after first login.
    mysqld --initialize-insecure --user=mysql --datadir=/var/www/html/mysql_data
    echo "INFO: Database initialized."
else
    echo "INFO: MySQL data directory already exists. Skipping initialization."
fi

echo "INFO: Starting all services via Supervisor..."

# Execute the command passed to the script (CMD from Dockerfile)
exec "$@"
