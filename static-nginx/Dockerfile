# nginx on the official Alpine image, running as non-root uid 1000 and
# listening on :8080.
#
# It follows nginx's 1.31 line: the base is the floating `nginx:1.31-alpine`
# tag, so each weekly rebuild picks up nginx's newest 1.31 patch release and
# Alpine's package fixes, and publishes as `static-nginx:1.31` (the chart tag).
# Deployments made before the line existed run `static-nginx:1.31.2`, which is
# no longer rebuilt; the manifest's `1.31.x` version upgrades them from
# `1.31.2`. (Before that, the base was Minimus's reg.mini.dev/nginx, which
# stopped serving anonymous pulls, so the image could no longer be rebuilt.)
#
# A tiny static Go entrypoint (worker-entry.go):
#   1. optionally wires a tenant NGINX config dir (NGINX_CONF_DIR) into the
#      server block — seeding a README and refusing to serve it, and
#   2. sets `worker_processes` from the pod's cgroup CPU limit (ceil of cores)
#      before exec'ing nginx. nginx's stock `worker_processes auto` counts HOST
#      cores and badly over-provisions CPU-limited tenant pods.
#
# Build context is this directory (build-images.yml: context = static-nginx/).
FROM nginx:1.31-alpine AS base

FROM golang:1.27-alpine AS build
WORKDIR /src
# Start from the base image's OWN nginx.conf (no maintained copy that can
# drift) and change only what running as uid 1000 needs:
#   - drop `worker_processes`, so the entrypoint can set it via `-g` without a
#     duplicate;
#   - drop `user`, which only a root master can act on (nginx warns otherwise);
#   - move the pid file from root-owned /run to /tmp. `nginx -s reload`, which
#     the platform execs after a multi-host change, reads it from here.
COPY --from=base /etc/nginx/nginx.conf /nginx.conf
RUN sed -i -e '/^[[:space:]]*worker_processes/d' \
           -e '/^[[:space:]]*user[[:space:]]/d' \
           -e 's#^pid[[:space:]].*#pid        /tmp/nginx.pid;#' /nginx.conf \
  && grep -q '^pid        /tmp/nginx.pid;$' /nginx.conf
COPY worker-entry.go .
# config-readme.txt is //go:embed-ed into the entrypoint so it can be seeded into
# the tenant's NGINX_CONF_DIR at runtime for in-place guidance.
COPY config-readme.txt config-readme.txt
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /nginx-workers worker-entry.go

FROM nginx:1.31-alpine
# Upgrade the base's own packages first: upstream rebuilds its tags on its own
# schedule, and between those rebuilds its packages are only as current as our
# own (weekly) rebuild.
# Then remove the stock site (a second server on port 80), give the runtime
# uid nginx's temp dirs, and name uid 1000 the way the other runtimes do.
RUN apk upgrade --no-cache \
  && rm -f /etc/nginx/conf.d/default.conf \
  && adduser -D -H -u 1000 -s /sbin/nologin webuser \
  && chown -R 1000:1000 /var/cache/nginx
COPY --from=build /nginx-workers /usr/local/bin/nginx-workers
COPY --from=build /nginx.conf /etc/nginx/nginx.conf
COPY nginx.conf /etc/nginx/conf.d/nginx.default.conf
# Writable include dir. nginx.default.conf does
# `include /etc/nginx/user-include/*.conf;` inside the server block; when
# NGINX_CONF_DIR is set the entrypoint writes a glue file here (owned by the
# runtime uid).
COPY --chown=1000:1000 user-include/ /etc/nginx/user-include/
COPY --chown=1000:1000 docroot/ /var/www/html/

# Multi-host: an include dir the platform mounts a ConfigMap over, plus the
# directives every generated site shares. The include glob matches nothing
# until something is mounted, and a wildcard include matching no files is not
# an error in nginx — so this is inert on a single-site deployment.
COPY sites-include.conf /etc/nginx/conf.d/zz-insula-sites.conf
COPY site-common.conf /etc/nginx/insula/site-common.conf
COPY --chown=1000:1000 sites.d/ /etc/nginx/insula/sites.d/

USER 1000
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/nginx-workers"]
