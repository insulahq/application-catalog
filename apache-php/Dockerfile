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
COPY site-common.conf /etc/apache2/insula/site-common.conf
RUN for tpl in http https; do \
      printf '\n# --- Insula platform overrides ---\nInclude /etc/apache2/insula/vhost-extra.conf\n' \
        >> "/etc/apache2/vhost-templates/${tpl}.conf"; \
    done

# Multi-host: an empty include directory the platform mounts a ConfigMap over,
# enabled through a sites-available entry that sorts AFTER the entrypoint's
# ssl-<mode>.conf so the stock vhost stays Apache's default (catch-all).
# With nothing mounted, IncludeOptional matches no files and this is inert.
COPY sites-include.conf /etc/apache2/sites-available/zz-insula-sites.conf
RUN mkdir -p /etc/apache2/insula/sites.d \
 && a2ensite zz-insula-sites

# ── Platform defaults ────────────────────────────────────────────────────────
# These override the base image's own ENV so a tenant who configures nothing
# still gets a lean, production-shaped runtime. Every one of them is listed in
# the manifest's env_vars.configurable, so a tenant CAN raise them — which only
# works because they are set here rather than in env_vars.fixed: the deployer
# resolves fixed first and skips any key already set (k8s-deployer buildEnv
# pass 2), so a "fixed" value silently wins over the tenant's.
#
#   APACHE_DOCUMENT_ROOT=/var/www/html
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
ENV APACHE_DOCUMENT_ROOT=/var/www/html \
    PHP_FPM_PM_MAX_CHILDREN=5 \
    PHP_FPM_PM_MAX_REQUESTS=500 \
    PHP_OPCACHE_ENABLE=1 \
    PHP_OPCACHE_MEMORY_CONSUMPTION=64


# --- Per-request PHP hardening for multi-host serving -------------------------
# `open_basedir` sandboxes a site's PHP to its own app root, but it does NOT
# restrain a CHILD process: `shell_exec("cat /var/www/sites/other/config.php")`
# reads a neighbouring site straight through it. Measured, not assumed.
#
# So the sandbox is only worth anything alongside a function ban, and the ban
# belongs in the FPM POOL rather than a php.ini conf.d file: pool scope covers
# web requests only, leaving the CLI SAPI intact so composer, wp-cli, artisan
# and occ keep working over SSH and cron — which is where they are run anyway.
#
# Empty by default, so a single-site deployment is unchanged: it mounts only
# its own storage subPath and has no neighbour to reach. The platform sets the
# value on deployments with multi-host enabled, where the pod mounts the whole
# tenant volume.
ENV PHP_DISABLE_FUNCTIONS=""
RUN printf '\nphp_admin_value[disable_functions] = ${PHP_DISABLE_FUNCTIONS}\n' \
      >> /usr/local/etc/php-fpm.d/docker-php-serversideup-pool.conf \
 && grep -q 'disable_functions' /usr/local/etc/php-fpm.d/docker-php-serversideup-pool.conf

USER www-data
