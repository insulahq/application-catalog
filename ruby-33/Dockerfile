FROM ruby:3.3-alpine

# Upgrade the base's own packages first: upstream rebuilds a floating tag on its
# own schedule, and a tag nobody rebuilds any more keeps its CVEs.
RUN apk upgrade --no-cache \
  && apk add --no-cache \
    build-base \
    libpq-dev \
    mariadb-dev \
    tzdata \
    curl \
  && gem install bundler puma \
  && rm -rf /var/cache/apk/*

RUN adduser -D -u 1000 webuser \
  && mkdir -p /app && chown -R webuser:webuser /app

WORKDIR /app

USER webuser

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -q --spider http://localhost:3000/health || exit 1

# Idle fallback when no Gemfile / app code is staged. See nodejs/Dockerfile
# for the rationale.
CMD ["sh", "-c", "if [ -f /app/config/puma.rb ] && [ -f /app/Gemfile ]; then exec bundle exec puma -C config/puma.rb; else echo '[runtime] No /app/config/puma.rb + /app/Gemfile — idle. Mount your Rails/Sinatra app and restart the deployment.'; exec sleep infinity; fi"]
