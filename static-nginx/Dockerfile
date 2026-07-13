# Hardened nginx via Minimus (distroless, non-root uid 1000, listens on :8080).
# The base has NO shell, so there are no RUN steps — docroot + config via COPY only.
# Minimus's nginx.conf already `include`s /etc/nginx/conf.d/*.conf and ships a default
# server at conf.d/nginx.default.conf; we overwrite THAT file so there is exactly one
# default_server on :8080.
FROM reg.mini.dev/nginx:1.31.2

COPY nginx.conf /etc/nginx/conf.d/nginx.default.conf
COPY --chown=1000:1000 docroot/ /var/www/html/

EXPOSE 8080
# No HEALTHCHECK: distroless has no wget; Kubernetes httpGet probes cover liveness/readiness.
