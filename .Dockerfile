
# Use official PHP 8.3 image with FPM
FROM php:8.3-fpm

# Install system dependencies and PHP extensions needed
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsqlite3-dev \
    libzip-dev \
    zlib1g-dev \
    unzip \
    zip \
    && docker-php-ext-configure zip \
    && docker-php-ext-install pdo_sqlite mbstring zip \
    && rm -rf /var/lib/apt/lists/*

# Set working directory
WORKDIR /var/www/html

# Copy composer.lock and composer.json
COPY composer.lock composer.json /var/www/html/

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

# Copy the rest of the app (so artisan and full codebase are available for composer scripts)
COPY . /var/www/html

# Install PHP dependencies (now that artisan exists)
RUN composer install --no-dev --prefer-dist --no-interaction --optimize-autoloader

# Ensure storage and bootstrap/cache are writable
RUN chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache

# Expose port 9000 (PHP-FPM default)
EXPOSE 9000

CMD ["php-fpm"]

