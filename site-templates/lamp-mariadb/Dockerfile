# LAMP stack with MariaDB
FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

ARG DBUSER
ARG DBPASS

RUN apt-get update && \
    apt-get install -y apache2 mariadb-server php libapache2-mod-php php-mysql && \
    apt-get clean && rm -rf /var/lib/apt/lists/*

# Configure MariaDB
RUN service mysql start && \
    mysql -e "CREATE DATABASE IF NOT EXISTS lampdb;" && \
    mysql -e "CREATE USER IF NOT EXISTS '$DBUSER'@'localhost' IDENTIFIED BY '$DBPASS';" && \
    mysql -e "GRANT ALL PRIVILEGES ON lampdb.* TO '$DBUSER'@'localhost';" && \
    mysql -e "FLUSH PRIVILEGES;"

VOLUME ["/var/www/html"]

EXPOSE 80 3306

CMD service mysql start && apachectl -D FOREGROUND
