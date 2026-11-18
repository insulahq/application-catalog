FROM rust:1.85-slim

# Upgrade the base's own packages first: upstream rebuilds a floating tag on its
# own schedule, and a tag nobody rebuilds any more keeps its CVEs.
RUN apt-get update && apt-get upgrade -y --no-install-recommends \
  && apt-get install -y --no-install-recommends \
    ca-certificates curl pkg-config libssl-dev \
  && rm -rf /var/lib/apt/lists/* \
  && useradd -u 1000 -ms /bin/bash webuser \
  && mkdir -p /app && chown -R webuser:webuser /app

WORKDIR /app

USER webuser

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD curl -fsS http://localhost:8080/health || exit 1

# Idle fallback when no compiled Rust binary is present. See nodejs/Dockerfile.
CMD ["sh", "-c", "if [ -x /app/app ]; then exec /app/app; else echo '[runtime] No /app/app binary — idle. Build your Rust app to /app/app and restart.'; exec sleep infinity; fi"]
