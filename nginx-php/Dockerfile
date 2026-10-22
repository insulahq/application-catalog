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
ARG PHP_VERSION=8.5
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
# takes its real-IP rules from /etc/nginx/trusted-proxy/${TRUSTED_PROXY}.conf,
# included by the stock server, and defaults to `cloudflare` — whose
# CF-Connecting-IP header no request here carries. `local` is the preset this
# platform needs: it trusts the private ranges (the pod network lives in
# 10.0.0.0/8), reads X-Forwarded-For and walks the chain right to left, so a
# forged prefix never wins.
#
# Asserted, not assumed: upstream already moved this once (it used to be
# server-opts.d/remoteip.conf, which this file rewrote with sed), and that
# move broke every build of this image. The next move has to fail here too
# rather than ship a runtime that logs Traefik as every visitor. The multi-host
# sites include the same preset — see entrypoint-multihost.sh.
ENV TRUSTED_PROXY=local
RUN grep -q '^real_ip_header X-Forwarded-For;$' /etc/nginx/trusted-proxy/local.conf \
 && grep -q '^real_ip_recursive on;$' /etc/nginx/trusted-proxy/local.conf \
 && grep -q '^set_real_ip_from 10.0.0.0/8;$' /etc/nginx/trusted-proxy/local.conf \
 && for t in http https; do \
      grep -qF 'include /etc/nginx/trusted-proxy/${TRUSTED_PROXY}.conf;' \
        "/etc/nginx/site-opts.d/$t.conf.template" \
        || { echo "site-opts.d/$t.conf.template no longer includes the trusted-proxy preset — upstream layout changed"; exit 1; }; \
    done

# Scheme the VISITOR used. The trusted-proxy preset above fixes WHO the client is; this
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

# Multi-host: an include dir the platform mounts a ConfigMap over, plus a
# startup-generated file holding the directives every site shares. Generated at
# startup rather than baked in because the PHP location carries three
# tenant-controlled values (NGINX_FASTCGI_BUFFERS, NGINX_FASTCGI_BUFFER_SIZE
# and PHP_MAX_EXECUTION_TIME); a static copy would hand multi-host sites
# nginx's defaults while the stock server honoured the tenant's settings.
#
# The include glob matches nothing until something is mounted, and a wildcard
# include matching no files is not an error in nginx, so this is inert on a
# single-site deployment.
COPY sites-include.conf /etc/nginx/conf.d/zz-insula-sites.conf
COPY entrypoint-multihost.sh /etc/entrypoint.d/60-insula-multihost.sh
RUN mkdir -p /etc/nginx/insula/sites.d \
 && chown -R www-data:www-data /etc/nginx/insula \
 && chmod +x /etc/entrypoint.d/60-insula-multihost.sh

# That script writes site-common.conf through an UNQUOTED heredoc, so a stray
# backtick in it — even in a comment — runs as a command at every container
# start ("location: not found" in the pod log was how this surfaced). Render it
# once here and fail on any stderr, then drop the render: the real one is
# written at startup from the deployment's environment.
RUN err=$(sh /etc/entrypoint.d/60-insula-multihost.sh 2>&1 >/dev/null) \
 && rm -f /etc/nginx/insula/site-common.conf \
 && if [ -n "$err" ]; then \
      echo "60-insula-multihost.sh wrote to stderr while rendering:"; echo "$err"; exit 1; \
    fi


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
