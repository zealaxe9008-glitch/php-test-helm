#!/usr/bin/env sh
set -e

cd /var/www/html

if [ ! -f .env ]; then
    cp .env.example .env 2>/dev/null || true
fi

# Generate app key if empty
if ! grep -q "^APP_KEY=base64:" .env 2>/dev/null; then
    php artisan key:generate --force || true
fi

# Ensure storage is writable (in case of mounted volumes)
chown -R www-data:www-data storage bootstrap/cache 2>/dev/null || true

exec "$@"


