# Multi-stage Dockerfile for Laravel 12 (PHP 8.3, Vite)

# ---------- Base PHP build stage (extensions + composer) ----------
FROM php:8.3-fpm AS php-base

# Install system dependencies and PHP extensions
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    unzip \
    zip \
    libonig-dev \
    libsqlite3-dev \
    libzip-dev \
    zlib1g-dev \
    && docker-php-ext-configure zip \
    && docker-php-ext-install pdo_sqlite mbstring zip \
    && rm -rf /var/lib/apt/lists/*

# Install Composer
RUN curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer

WORKDIR /var/www/html

# Copy full app first so artisan is available if needed, but we will avoid running scripts during install
COPY . /var/www/html

# Composer install with dev dependencies for local/dev usage; avoid scripts
ENV COMPOSER_ALLOW_SUPERUSER=1
RUN composer install --prefer-dist --no-interaction --no-progress --no-scripts --optimize-autoloader

# ---------- Frontend build stage (Vite) ----------
FROM node:20-alpine AS frontend
WORKDIR /app

COPY package.json package-lock.json* /app/
RUN npm ci || npm install

COPY resources /app/resources
COPY vite.config.js /app/vite.config.js
COPY --from=php-base /var/www/html/public /app/public

RUN npm run build

# ---------- Final runtime image ----------
FROM php:8.3-fpm AS runtime

WORKDIR /var/www/html

# Copy application source, vendor, and built assets
COPY --from=php-base /var/www/html /var/www/html
COPY --from=php-base /usr/local/bin/composer /usr/local/bin/composer
COPY --from=frontend /app/public/build /var/www/html/public/build

# Ensure storage and cache are writable
RUN chown -R www-data:www-data /var/www/html/storage /var/www/html/bootstrap/cache \
    && find /var/www/html/storage -type d -exec chmod 775 {} \; \
    && find /var/www/html/bootstrap/cache -type d -exec chmod 775 {} \;

# Environment defaults (override at runtime as needed)
ENV APP_ENV=production \
    APP_DEBUG=false \
    PHP_OPCACHE_VALIDATE_TIMESTAMPS=0

COPY docker/entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# Expose Laravel dev server port
EXPOSE 8000

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["php","artisan","serve","--host=0.0.0.0","--port=8000"]


