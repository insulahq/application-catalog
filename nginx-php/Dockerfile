# NGINX + PHP-FPM runtime for the Insula platform.
#
# Based on serversideup/php for the same reasons as apache-php: their
# entrypoint implements the PHP_*/NGINX_* knobs the catalog manifest exposes,
# the non-root runtime, port 8080 and /healthcheck. See apache-php/Dockerfile
# for the full rationale.
#
# Note the alpine base ships an even leaner extension set than the Debian
# one — it has no mysqli at all, only pdo_mysql, which breaks WordPress and
# most legacy PHP outright.
ARG PHP_VERSION=8.4
FROM serversideup/php:${PHP_VERSION}-fpm-nginx-alpine

USER root

# Extensions — keep in sync with apache-php/Dockerfile and
# scripts/required-php-extensions.txt (asserted by CI).
RUN install-php-extensions \
      apcu \
      bcmath \
      bz2 \
      calendar \
      exif \
      ftp \
      gd \
      gettext \
      gmp \
      imagick \
      imap \
      intl \
      ldap \
      memcached \
      mysqli \
      pgsql \
      shmop \
      soap \
      sockets \
      sysvsem \
      xsl \
 && rm -rf /tmp/* /var/tmp/*

# Real client IP behind the platform's Traefik ingress. The upstream image
# already trusts the private CIDRs (the pod network lives in 10.0.0.0/8) and
# already sets `absolute_redirect off`, so the only wrong piece is the header
# name — it defaults to Cloudflare's, which no request here carries. Rewrite
# that one line rather than adding a second directive: nginx rejects a
# duplicate real_ip_header in the same context.
RUN sed -i 's|^real_ip_header .*|real_ip_header X-Forwarded-For;|' \
      /etc/nginx/server-opts.d/remoteip.conf \
 && grep -q '^real_ip_header X-Forwarded-For;$' /etc/nginx/server-opts.d/remoteip.conf

USER www-data
