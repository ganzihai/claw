# 多阶段构建 - 基于Ubuntu 22.04的集成开发环境镜像
# 严格遵循项目规范：单一镜像架构，单一卷持久化(/var/www/html/)

# ================================
# 第一阶段：基础环境构建
# ================================
FROM ubuntu:22.04 as base

# 设置环境变量，避免交互式安装
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Asia/Shanghai

# 【修改】在这里添加 git, lsof, iproute2
RUN apt-get update && apt-get install -y \
    openssh-server sudo curl wget cron nano tar gzip unzip sshpass \
    supervisor tzdata ca-certificates software-properties-common \
    apt-transport-https gnupg2 lsb-release net-tools \
    build-essential \
    git lsof iproute2 \
    && rm -rf /var/lib/apt/lists/*

# 设置时区
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# ================================
# 第二阶段：Web服务环境 (Apache + PHP 7.4.33)
# ================================
FROM base as web-env

# 添加PHP 7.4源并安装Apache和PHP
RUN add-apt-repository ppa:ondrej/php && \
    apt-get update && \
    apt-get install -y \
    apache2 php7.4 php7.4-fpm php7.4-mysql php7.4-curl php7.4-gd \
    php7.4-mbstring php7.4-xml php7.4-zip php7.4-json php7.4-opcache \
    php7.4-readline php7.4-common php7.4-cli libapache2-mod-php7.4 \
    && rm -rf /var/lib/apt/lists/*

# 启用Apache模块
RUN a2enmod rewrite php7.4 ssl headers proxy proxy_http

# 复制Apache虚拟主机配置文件
COPY apache/000-default.conf /etc/apache2/sites-available/000-default.conf
COPY apache/wordpress.conf /etc/apache2/sites-available/wordpress.conf

# 启用新的虚拟主机
RUN echo "Listen 8888" >> /etc/apache2/ports.conf && \
    a2ensite wordpress.conf

# ================================
# 第三阶段：数据库环境 (MySQL)
# ================================
FROM web-env as db-env

RUN apt-get update && \
    echo 'mysql-server mysql-server/root_password password temp_password' | debconf-set-selections && \
    echo 'mysql-server mysql-server/root_password_again password temp_password' | debconf-set-selections && \
    apt-get install -y mysql-server && \
    rm -rf /var/lib/apt/lists/*

RUN mkdir -p /var/www/html/mysql && \
    chown mysql:mysql /var/www/html/mysql

RUN sed -i 's|datadir.*=.*|datadir = /var/www/html/mysql|g' /etc/mysql/mysql.conf.d/mysqld.cnf && \
    sed -i 's|bind-address.*=.*|bind-address = 0.0.0.0|g' /etc/mysql/mysql.conf.d/mysqld.cnf

# ================================
# 第四阶段：开发环境 (Python + Node.js + Go)
# ================================
FROM db-env as dev-env

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    python3.10 python3.10-dev python3.10-venv python3-pip \
    && rm -rf /var/lib/apt/lists/*

RUN ln -sf /usr/bin/python3.10 /usr/bin/python && \
    ln -sf /usr/bin/pip3 /usr/bin/pip

RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

RUN npm install -g pnpm

RUN wget https://go.dev/dl/go1.24.4.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go1.24.4.linux-amd64.tar.gz && \
    rm go1.24.4.linux-amd64.tar.gz

ENV PATH=$PATH:/usr/local/go/bin
ENV GOPATH=/var/www/html/go
ENV GOPROXY=https://goproxy.cn,direct

# ================================
# 第五阶段：最终镜像配置
# ================================
FROM dev-env as final

RUN mkdir /var/run/sshd && \
    sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    sed -i 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' /etc/pam.d/sshd && \
    echo 'Port 22' >> /etc/ssh/sshd_config

RUN mkdir -p /var/www/html/{maccms,cron,supervisor/conf.d,mysql,go,python_venv,node_modules,ssl,blog} && \
    mkdir -p /var/log/supervisor

RUN chown -R www-data:www-data /var/www/html && \
    chown mysql:mysql /var/www/html/mysql && \
    chmod 755 /var/www/html

# 复制配置文件和脚本
COPY supervisord.conf /etc/supervisor/supervisord.conf
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
COPY cron_monitor.sh /usr/local/bin/cron_monitor.sh

# 赋予脚本执行权限
RUN chmod +x /usr/local/bin/entrypoint.sh && \
    chmod +x /usr/local/bin/cron_monitor.sh

WORKDIR /var/www/html
EXPOSE 80
VOLUME ["/var/www/html"]
CMD ["/usr/local/bin/entrypoint.sh"]
