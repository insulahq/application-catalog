FROM oven/bun:1.2

# oven/bun base image already has user `bun` at UID 1000 — reuse rather
# than creating a conflicting webuser.
USER root
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
  && rm -rf /var/lib/apt/lists/* \
  && mkdir -p /app && chown -R bun:bun /app

WORKDIR /app
USER bun

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD curl -fsS http://localhost:3000/health || exit 1

# Idle fallback when no Bun app is present. See nodejs/Dockerfile.
CMD ["sh", "-c", "if [ -f /app/index.ts ] || [ -f /app/index.js ]; then exec bun run /app/index.ts 2>/dev/null || exec bun run /app/index.js; else echo '[runtime] No /app/index.{ts,js} — idle. Mount your Bun app and restart.'; exec sleep infinity; fi"]
