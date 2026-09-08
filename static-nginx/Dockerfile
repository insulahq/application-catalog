# Hardened nginx via Minimus (distroless, non-root uid 1000, listens on :8080).
#
# A tiny static Go entrypoint (worker-entry.go):
#   1. optionally wires a tenant NGINX config dir (NGINX_CONF_DIR) into the
#      server block — seeding a README and refusing to serve it, and
#   2. sets `worker_processes` from the pod's cgroup CPU limit (ceil of cores)
#      before exec'ing nginx. nginx's stock `worker_processes auto` counts HOST
#      cores and badly over-provisions CPU-limited tenant pods.
#
# Build context is this directory (build-images.yml: context = static-nginx/).
FROM reg.mini.dev/nginx:1.31.2 AS base

FROM golang:1.23-alpine AS build
WORKDIR /src
# Strip `worker_processes` from the base image's OWN nginx.conf (no maintained
# copy that can drift) so the entrypoint can set it via `-g` without a duplicate.
COPY --from=base /etc/nginx/nginx.conf /nginx.conf
RUN sed -i '/^[[:space:]]*worker_processes/d' /nginx.conf
COPY worker-entry.go .
# config-readme.txt is //go:embed-ed into the entrypoint so it can be seeded into
# the tenant's NGINX_CONF_DIR at runtime for in-place guidance.
COPY config-readme.txt config-readme.txt
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /nginx-workers worker-entry.go

FROM reg.mini.dev/nginx:1.31.2
COPY --from=build /nginx-workers /usr/local/bin/nginx-workers
COPY --from=build /nginx.conf /etc/nginx/nginx.conf
COPY nginx.conf /etc/nginx/conf.d/nginx.default.conf
# Writable include dir. nginx.default.conf does
# `include /etc/nginx/user-include/*.conf;` inside the server block; when
# NGINX_CONF_DIR is set the entrypoint writes a glue file here (owned by the
# runtime uid). A distroless base has no shell, so the dir is created via COPY.
COPY --chown=1000:1000 user-include/ /etc/nginx/user-include/
COPY --chown=1000:1000 docroot/ /var/www/html/

# Multi-host: an include dir the platform mounts a ConfigMap over, plus the
# directives every generated site shares. The include glob matches nothing
# until something is mounted, and a wildcard include matching no files is not
# an error in nginx — so this is inert on a single-site deployment.
#
# A distroless base has no shell, so sites.d is created by COPYing an empty
# marker into it rather than with mkdir.
COPY sites-include.conf /etc/nginx/conf.d/zz-insula-sites.conf
COPY site-common.conf /etc/nginx/insula/site-common.conf
COPY --chown=1000:1000 sites.d/ /etc/nginx/insula/sites.d/

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/nginx-workers"]
