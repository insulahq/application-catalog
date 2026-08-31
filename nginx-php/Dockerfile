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

# Scheme the VISITOR used. remoteip.conf above fixes WHO the client is; this
# fixes WHAT SCHEME they used, which the upstream image gets wrong behind a
# TLS-terminating proxy (nginx's $https is empty, so `HTTPS` is never sent to
# PHP). See scheme.conf for the measured symptom and the trust model.
#
# The maps must live in `http` context (conf.d), but the fastcgi_param
# overrides must live in fastcgi_params: the site's location does
# `include fastcgi_params`, and fastcgi_param does NOT merge across levels —
# a location-level set REPLACES everything inherited, so defining these at
# http context would be silently discarded.
#
# `00-` prefix so the maps are parsed before default.conf uses them.
COPY scheme.conf /etc/nginx/conf.d/00-insula-scheme.conf
RUN for f in /etc/nginx/fastcgi_params /etc/nginx/fastcgi.conf; do \
      [ -f "$f" ] || continue; \
      sed -i \
        -e 's|^\(fastcgi_param[[:space:]]\+HTTPS[[:space:]]\+\)\$https|\1$insula_https|' \
        -e 's|^\(fastcgi_param[[:space:]]\+REQUEST_SCHEME[[:space:]]\+\)\$scheme;|\1$insula_scheme;|' \
        -e 's|^\(fastcgi_param[[:space:]]\+SERVER_PORT[[:space:]]\+\)\$server_port;|\1$insula_server_port;|' \
        "$f"; \
    done \
 && for v in insula_https insula_scheme insula_server_port; do \
      grep -q "\$$v" /etc/nginx/fastcgi_params \
        || { echo "fastcgi_params was not rewired for \$$v — upstream layout changed"; exit 1; }; \
    done

# ── Platform defaults ────────────────────────────────────────────────────────
# These override the base image's own ENV so a tenant who configures nothing
# still gets a lean, production-shaped runtime. Every one of them is listed in
# the manifest's env_vars.configurable, so a tenant CAN raise them — which only
# works because they are set here rather than in env_vars.fixed: the deployer
# resolves fixed first and skips any key already set (k8s-deployer buildEnv
# pass 2), so a "fixed" value silently wins over the tenant's.
#
#   NGINX_WEBROOT=/var/www/html
#       The base image defaults to a Laravel-style .../public. The platform
#       mounts the tenant's document root at /var/www/html.
#   PHP_OPCACHE_ENABLE=1
#       Off in the base image; the platform has always wanted it on.
#   PHP_OPCACHE_MEMORY_CONSUMPTION=64   (base: 128)
#       MB of shared memory claimed at startup. 64 is ample for a typical site
#       and halves the claim inside a 128-256Mi container.
#   PHP_FPM_PM_MAX_CHILDREN=5           (base: 20)
#       The single biggest memory lever here. Each worker may grow to
#       PHP_MEMORY_LIMIT, so 20 x 256M is far beyond any tenant container.
#   PHP_FPM_PM_MAX_REQUESTS=500         (base: 0 = never recycle)
#       Recycling workers bounds leaks in long-lived PHP processes.
ENV NGINX_WEBROOT=/var/www/html \
    PHP_FPM_PM_MAX_CHILDREN=5 \
    PHP_FPM_PM_MAX_REQUESTS=500 \
    PHP_OPCACHE_ENABLE=1 \
    PHP_OPCACHE_MEMORY_CONSUMPTION=64

USER www-data
