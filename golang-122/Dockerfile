FROM golang:1.22-alpine

# Upgrade the base's own packages first: upstream rebuilds a floating tag on its
# own schedule, and a tag nobody rebuilds any more keeps its CVEs.
RUN apk upgrade --no-cache \
  && apk add --no-cache git ca-certificates curl \
  && adduser -D -u 1000 webuser \
  && mkdir -p /app && chown -R webuser:webuser /app

WORKDIR /app

USER webuser

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -q --spider http://localhost:8080/health || exit 1

# Idle fallback when no compiled Go binary is present. See nodejs/Dockerfile
# for the rationale. Customers upload a `server` binary or compile in-pod.
CMD ["sh", "-c", "if [ -x /app/server ]; then exec /app/server; else echo '[runtime] No /app/server binary — idle. Build your Go app to /app/server and restart.'; exec sleep infinity; fi"]
