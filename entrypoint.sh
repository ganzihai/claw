#!/bin/bash
set -e

# --- Set permissions for the mounted volume ---
# Ensures that the web server and other services can write to the volume
chown -R www-data:www-data /var/www/html
chown -R mysql:mysql /var/www/html/mysql_data

# --- Initialize MySQL Database if not already initialized ---
if [ -z "$(ls -A /var/www/html/mysql_data)" ]; then
    echo "MySQL data directory is empty. Initializing database..."
    # Using --initialize-insecure to not generate a random root password.
    # You should set a password immediately after first login.
    mysqld --initialize-insecure --user=mysql --datadir=/var/www/html/mysql_data
    echo "Database initialized."
else
    echo "MySQL data directory already exists. Skipping initialization."
fi

echo "Starting all services via Supervisor..."

# Execute the command passed to the script (CMD from Dockerfile)
exec "$@"
