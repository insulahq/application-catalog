#!/bin/sh
###################################################
# 60-insula-multihost.sh
###################################################
# Renders the directives shared by every generated multi-host site into
# /etc/nginx/insula/site-common.conf.
#
# Why this is generated at STARTUP rather than baked into the image: the PHP
# location block carries three values the tenant controls through environment
# variables (NGINX_FASTCGI_BUFFERS, NGINX_FASTCGI_BUFFER_SIZE and
# PHP_MAX_EXECUTION_TIME, which becomes fastcgi_read_timeout). A static file
# would silently give multi-host sites nginx's defaults instead of the tenant's
# settings — the stock single-site server would honour PHP_MAX_EXECUTION_TIME
# and its neighbours on the same pod would not.
#
# Sourced by docker-php-serversideup-entrypoint after 10-init-webserver-config,
# so NGINX_* and PHP_* are already resolved.
script_name="insula-multihost"

insula_sites_dir="/etc/nginx/insula"

if [ ! -d "$insula_sites_dir" ]; then
    echo "👉 $script_name: $insula_sites_dir not present, skipping."
    return 0
fi

# Listen lines must match the stock server's address family selection. nginx
# matches server_name only among blocks listening on the SAME address, so a
# site listening on one family while the stock server listens on both is
# unreachable over the other — a half-working site that looks like a DNS fault.
insula_listen="listen ${NGINX_HTTP_PORT};
listen [::]:${NGINX_HTTP_PORT};"
case "${NGINX_LISTEN_IP_PROTOCOL}" in
    ipv4) insula_listen="listen ${NGINX_HTTP_PORT};" ;;
    ipv6) insula_listen="listen [::]:${NGINX_HTTP_PORT};" ;;
esac

cat > "$insula_sites_dir/site-common.conf" <<INSULA_SITE_COMMON
# GENERATED AT CONTAINER STARTUP by /etc/entrypoint.d/60-insula-multihost.sh.
# Edits are lost on restart — change the deployment's environment instead.
${insula_listen}

index index.html index.htm index.php;
charset utf-8;

# No symlink following out of a site. A symlink inside one site's folder
# pointing at a sibling's is served by NGINX directly — open_basedir and
# disable_functions are PHP controls and never see such a request, so both are
# bypassed. Reproduced against this image: the sibling's config file came back
# as text/plain with PHP never invoked. `location ~ \.php$` matches the
# REQUESTED name, not the target, so any other extension skips FPM entirely.
#
# `from=$document_root` checks the components below the document root, where
# such a symlink sits, without failing on a link higher up the mount path.
# `if_not_owner` would be a no-op here: every file has the same runtime uid.
#
# COST, deliberately accepted: an app shipping a symlink under its document
# root (Laravel's `public/storage`) stops resolving it — use a real directory.
# Neither nginx nor Apache can express "symlinks that stay inside the app
# root", and the alternative is no isolation between sites on one instance.
disable_symlinks on from=\$document_root;

# TLS terminates at Traefik and this server listens on a plain HTTP port, so an
# absolute redirect would send the browser to the wrong scheme and an unexposed
# port. Same reason the stock server sets this.
absolute_redirect off;

# Security headers and the dotfile/backup-file denials the stock server gets.
# Included rather than restated so a multi-host site cannot end up with a
# weaker posture than the single-site server in the same image.
include /etc/nginx/server-opts.d/*.conf;

location / {
    try_files \$uri \$uri/ /index.php?\$query_string;
}

# Block PHP execution in the storage directory to stop an uploaded PHP file
# from running. Reference: Livewire arbitrary file upload (GHSA-29cq-5w36-x7w3).
location ~* ^/storage/.*\.php\$ {
    deny all;
}

location ~ \.php\$ {
    fastcgi_pass   127.0.0.1:9000;
    fastcgi_index  index.php;
    fastcgi_param  SCRIPT_FILENAME  \$document_root\$fastcgi_script_name;
    # fastcgi_params carries the platform's REQUEST_SCHEME / HTTPS /
    # SERVER_PORT fixes, so a site reports the visitor's scheme like the stock
    # server does.
    include        fastcgi_params;
    # SERVER_NAME must be the hostname the VISITOR used, not the matched
    # server_name directive. nginx passes the directive by default, which for a
    # wildcard site means every visitor to *.apps.example.test would see
    # SERVER_NAME "*.apps.example.test" — not a hostname at all, and any
    # framework building URLs from it emits links nobody can follow. \$host is
    # the request's Host header (falling back to server_name when absent).
    # This is the nginx counterpart of `UseCanonicalName Off` on apache-php;
    # it must come AFTER the include, which is where the default is set.
    fastcgi_param  SERVER_NAME      \$host;
    # Per-site PHP sandbox (open_basedir). A VARIABLE, not a literal, because
    # nginx inherits fastcgi_param from an outer level ONLY when the inner
    # level declares none — and this location declares several, so a
    # server-level param would be silently dropped. Every generated server
    # block sets it; a server that did not would be an UNSET variable, which
    # nginx treats as a startup error, taking down every site in the pod
    # rather than one. The platform's renderer therefore always emits it.
    fastcgi_param  PHP_ADMIN_VALUE  \$insula_php_admin;
    fastcgi_buffers ${NGINX_FASTCGI_BUFFERS};
    fastcgi_buffer_size ${NGINX_FASTCGI_BUFFER_SIZE};
    fastcgi_read_timeout ${PHP_MAX_EXECUTION_TIME};
}
INSULA_SITE_COMMON

if [ "$LOG_OUTPUT_LEVEL" = "debug" ]; then
    echo "👉 $script_name: wrote $insula_sites_dir/site-common.conf"
fi
