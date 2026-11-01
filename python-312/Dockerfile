FROM python:3.12-slim

# Upgrade the base's own packages first: upstream rebuilds a floating tag on its
# own schedule, and a tag nobody rebuilds any more keeps its CVEs.
RUN apt-get update && apt-get upgrade -y --no-install-recommends \
  && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/* \
    && pip install --no-cache-dir gunicorn \
    && useradd -u 1000 -ms /bin/bash webuser \
    && mkdir -p /app && chown -R webuser:webuser /app

WORKDIR /app

USER webuser

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD curl -fsS http://localhost:8000/health || exit 1

# Idle fallback when no Python app is present. See nodejs/Dockerfile.
CMD ["sh", "-c", "if [ -f /app/app.py ] || [ -f /app/wsgi.py ]; then exec gunicorn --bind 0.0.0.0:8000 --workers 2 ${WSGI_MODULE:-app:app}; else echo '[runtime] No /app/app.py or /app/wsgi.py — idle. Mount your Flask/Django app and restart.'; exec sleep infinity; fi"]
