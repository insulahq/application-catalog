# Hardened nginx via Minimus (distroless, non-root uid 1000, listens on :8080).
#
# A tiny static Go entrypoint (worker-entry.go) sets `worker_processes` from the
# pod's cgroup CPU limit (ceil of cores) before exec'ing nginx. nginx's stock
# `worker_processes auto` counts HOST cores and badly over-provisions CPU-limited
# tenant pods; this makes the worker count track the actual CPU allocation.
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
RUN CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /nginx-workers worker-entry.go

FROM reg.mini.dev/nginx:1.31.2
COPY --from=build /nginx-workers /usr/local/bin/nginx-workers
COPY --from=build /nginx.conf /etc/nginx/nginx.conf
COPY nginx.conf /etc/nginx/conf.d/nginx.default.conf
COPY --chown=1000:1000 docroot/ /var/www/html/

EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/nginx-workers"]
