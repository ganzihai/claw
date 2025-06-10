# =========================================================================
# STAGE 1: Reference the CloudSaver image
# =========================================================================
FROM jiangrui1994/cloudsaver:latest AS cloudsaver_stage

# =========================================================================
# STAGE 2: Main build stage for the fat image (FINAL SHOWSTOPPER FIX)
# =========================================================================
FROM ubuntu:22.04

# --- Environment and Arguments ---
ARG DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai
ENV LANG C.UTF-8
ENV LC_ALL C.UTF-8

# --- 1. Install Base Packages & Dependencies ---
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    software-properties-common git openssh-server sudo curl wget cron nano tar gzip unzip sshpass \
    python3 python3-pip python3-dev build-essential \
    nginx supervisor mysql-server && \
    # 先添加PHP仓库，确保能安装PHP 7.4
    add-apt-repository ppa:ondrej/php -y && \
    # 安装Node.js
    curl -fsSL https://deb.nodesource.com/setup_18.x | bash - && \
    apt-get update && \
    apt-get install -y --no-install-recommends \
    nodejs \
    php7.4-fpm php7.4-mysql php7.4-gd php7.4-curl php7.4-mbstring php7.4-xml php7.4-zip \
    php7.4-bcmath php7.4-soap php7.4-intl php7.4-readline && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

# --- 2. Install Go Language Environment ---
RUN wget https://go.dev/dl/go1.24.4.linux-amd64.tar.gz -O /tmp/go.tar.gz && \
    tar -C /usr/local -xzf /tmp/go.tar.gz && rm /tmp/go.tar.gz
ENV PATH="/usr/local/go/bin:${PATH}"

# --- 3. Integrate CloudSaver (FINAL FIX: Rebuild native modules) ---
COPY --from=cloudsaver_stage /app /opt/cloudsaver/
# Remove the incompatible Alpine-compiled modules and rebuild them on Ubuntu
RUN cd /opt/cloudsaver && \
    rm -rf node_modules && \
    npm install --omit=dev

# --- 4. Configure Services ---
COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY services.conf /var/www/html/supervisor/conf.d/services.conf
RUN mkdir -p /var/log/supervisor
COPY nginx-maccms.conf /etc/nginx/sites-available/maccms
RUN ln -s /etc/nginx/sites-available/maccms /etc/nginx/sites-enabled/maccms && rm /etc/nginx/sites-enabled/default

# --- 5. Configure PHP, MySQL and SSH ---
RUN sed -i 's|;*php_admin_value\[open_basedir\]\s*=\s*.*|;php_admin_value[open_basedir] = none|' /etc/php/7.4/fpm/pool.d/www.conf && \
    sed -i 's/;daemonize = yes/daemonize = no/' /etc/php/7.4/fpm/php-fpm.conf && \
    sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config && \
    sed -i 's|datadir\s*=\s*/var/lib/mysql|datadir = /var/www/html/mysql_data|' /etc/mysql/mysql.conf.d/mysqld.cnf && \
    sed -i 's|#bind-address\s*=\s*127.0.0.1|bind-address = 127.0.0.1|' /etc/mysql/mysql.conf.d/mysqld.cnf

# --- 6. PHP-FPM Optimization ---
RUN sed -i 's/pm = dynamic/pm = dynamic/' /etc/php/7.4/fpm/pool.d/www.conf && \
    sed -i 's/pm.max_children = 5/pm.max_children = 50/' /etc/php/7.4/fpm/pool.d/www.conf && \
    sed -i 's/pm.start_servers = 2/pm.start_servers = 5/' /etc/php/7.4/fpm/pool.d/www.conf && \
    sed -i 's/pm.min_spare_servers = 1/pm.min_spare_servers = 5/' /etc/php/7.4/fpm/pool.d/www.conf && \
    sed -i 's/pm.max_spare_servers = 3/pm.max_spare_servers = 35/' /etc/php/7.4/fpm/pool.d/www.conf && \
    echo "pm.max_requests = 500" >> /etc/php/7.4/fpm/pool.d/www.conf

# --- 7. MySQL Optimization ---
RUN echo "[mysqld]" >> /etc/mysql/conf.d/mysql-optimization.cnf && \
    echo "character-set-server = utf8mb4" >> /etc/mysql/conf.d/mysql-optimization.cnf && \
    echo "collation-server = utf8mb4_unicode_ci" >> /etc/mysql/conf.d/mysql-optimization.cnf && \
    echo "innodb_buffer_pool_size = 256M" >> /etc/mysql/conf.d/mysql-optimization.cnf

# --- 8. Setup Scripts and Entrypoint ---
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# --- 9. Create necessary directories ---
RUN mkdir -p /var/www/html/supervisor/conf.d

# --- 10. Final Steps ---
EXPOSE 80
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["/usr/bin/supervisord", "-n", "-c", "/etc/supervisor/supervisord.conf"]
