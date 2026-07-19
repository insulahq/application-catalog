FROM php:8.4-apache-bookworm

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpng-dev libjpeg62-turbo-dev libfreetype6-dev \
    libicu-dev libzip-dev curl \
  && docker-php-ext-configure gd --with-freetype --with-jpeg \
  && docker-php-ext-install -j$(nproc) \
    gd pdo_mysql mysqli intl zip opcache bcmath \
  && a2enmod rewrite headers expires remoteip \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Real client IP recovery behind the platform's Traefik reverse proxy: rewrite
# REMOTE_ADDR (seen by PHP) and %a/%h (logs) from X-Forwarded-For so apps see
# the real visitor instead of the Traefik pod IP (10.42.x.x). See remoteip.conf.
COPY remoteip.conf /etc/apache2/conf-enabled/remoteip.conf

# PHP production settings
RUN cp /usr/local/etc/php/php.ini-production /usr/local/etc/php/conf.d/production.ini

# Run as non-root
RUN useradd -u 1000 -ms /bin/bash webuser \
  && chown -R webuser:webuser /var/www/html

WORKDIR /var/www/html

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD curl -f http://localhost/ || exit 1
