# LAMP Stack with PHP 8.2, Apache, and security optimizations
FROM php:8.2-apache

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    curl \
    libpng-dev \
    libonig-dev \
    libxml2-dev \
    libzip-dev \
    zip \
    unzip \
    default-mysql-client \
    && rm -rf /var/lib/apt/lists/*

# Install PHP extensions
RUN docker-php-ext-install \
    pdo_mysql \
    mbstring \
    exif \
    pcntl \
    bcmath \
    gd \
    zip \
    intl \
    opcache

# Install Composer
COPY --from=composer:latest /usr/bin/composer /usr/bin/composer

# Enable Apache modules
RUN a2enmod rewrite ssl headers expires

# Create non-root user for file operations (rootless patterns)
RUN groupadd -g 1001 webuser && \
    useradd -r -u 1001 -g webuser webuser

# Set working directory
WORKDIR /var/www/html

# Copy PHP configuration
COPY docker/php.ini /usr/local/etc/php/conf.d/custom.ini
COPY docker/opcache.ini /usr/local/etc/php/conf.d/opcache.ini

# Copy Apache configuration
COPY docker/apache2.conf /etc/apache2/apache2.conf
COPY docker/000-default.conf /etc/apache2/sites-available/000-default.conf

# Copy application files
COPY src/ /var/www/html/

# Install PHP dependencies if composer.json exists
RUN if [ -f composer.json ]; then \
        composer install --no-dev --optimize-autoloader --no-interaction; \
    fi

# Set proper permissions for security
RUN chown -R webuser:www-data /var/www/html && \
    chmod -R 755 /var/www/html && \
    find /var/www/html -type f -exec chmod 644 {} \; && \
    chmod -R 775 /var/www/html/storage /var/www/html/bootstrap/cache 2>/dev/null || true

# Create health check script
COPY docker/health.php /var/www/html/health.php
RUN chmod 644 /var/www/html/health.php

# Security: Remove sensitive files
RUN rm -f /var/www/html/.env.example \
          /var/www/html/composer.json \
          /var/www/html/composer.lock \
          /var/www/html/package.json \
          /var/www/html/webpack.mix.js 2>/dev/null || true

# Set final permissions
RUN chown -R www-data:www-data /var/www/html /var/log/apache2 /var/run/apache2

# Switch to www-data user for security (rootless execution)
USER www-data

# Expose port
EXPOSE 80

# Health check for container orchestration
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD curl -f http://localhost/health.php || exit 1

# Start Apache in foreground
CMD ["apache2-foreground"]