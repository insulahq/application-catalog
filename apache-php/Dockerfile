# Apache + PHP-FPM runtime for the Insula platform.
#
# Based on serversideup/php rather than the bare official php image: their
# entrypoint is what implements the PHP_* tuning knobs the catalog manifest
# exposes to tenants (PHP_MEMORY_LIMIT, PHP_UPLOAD_MAX_FILE_SIZE, …), the
# non-root www-data runtime, port 8080 and the /healthcheck endpoint. Basing
# on it keeps that contract intact; we only add what tenants' applications
# need on top.
#
# Why we build at all instead of using serversideup directly: their image
# ships a deliberately minimal extension set (no gd, imap, intl, bcmath,
# soap, … and no mysqli at all on the nginx-alpine variant), which fails a
# large share of real PHP applications. Platform architecture §2.8 calls for
# shipping one fat image covering the common cases.
ARG PHP_VERSION=8.4
FROM serversideup/php:${PHP_VERSION}-fpm-apache

USER root

# Extensions. The authoritative list of what MUST be present in the finished
# image lives in scripts/required-php-extensions.txt and is asserted by
# scripts/check-php-extensions.sh in CI — keep the two in sync.
#
# install-php-extensions ships in the base image; it resolves build deps,
# compiles, enables, then removes the build deps again.
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

# Real client IP + scheme-aware redirects behind the platform's Traefik
# ingress. Appended to the END of the upstream vhost templates so our
# directives win over the Cloudflare-oriented defaults baked into them,
# while leaving the upstream file otherwise untouched (minimal drift).
COPY vhost-extra.conf /etc/apache2/insula/vhost-extra.conf
RUN for tpl in http https; do \
      printf '\n# --- Insula platform overrides ---\nInclude /etc/apache2/insula/vhost-extra.conf\n' \
        >> "/etc/apache2/vhost-templates/${tpl}.conf"; \
    done

USER www-data
