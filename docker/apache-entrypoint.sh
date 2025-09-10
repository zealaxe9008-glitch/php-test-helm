#!/usr/bin/env bash
set -euo pipefail

cd /var/www/html

if [ ! -f .env ]; then
  cp .env.example .env 2>/dev/null || true
fi

# Generate APP_KEY if not present
if ! grep -q "^APP_KEY=base64:" .env 2>/dev/null; then
  php artisan key:generate --force || true
fi

# Force file-based sessions to avoid DB requirement in container
if ! grep -q "^SESSION_DRIVER=" .env 2>/dev/null; then
  echo "SESSION_DRIVER=file" >> .env
fi

# Prefer file cache during container runtime
if ! grep -q "^CACHE_STORE=" .env 2>/dev/null; then
  echo "CACHE_STORE=file" >> .env
fi

# Ensure runtime env for cache and session
export CACHE_STORE=file
export SESSION_DRIVER=file

# Clear any cached config/routes/packages and re-discover packages
CACHE_STORE=file php artisan optimize:clear || true
CACHE_STORE=file php artisan package:discover --ansi || true

# Permissions for runtime dirs
chown -R www-data:www-data storage bootstrap/cache || true
find storage -type d -exec chmod 775 {} \; || true
find bootstrap/cache -type d -exec chmod 775 {} \; || true

exec apache2-foreground


