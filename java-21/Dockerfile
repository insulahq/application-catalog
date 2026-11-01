FROM eclipse-temurin:21-jre-alpine

# Upgrade the base's own packages first: upstream rebuilds a floating tag on its
# own schedule, and a tag nobody rebuilds any more keeps its CVEs.
RUN apk upgrade --no-cache \
  && apk add --no-cache curl \
  && adduser -D -u 1000 webuser \
  && mkdir -p /app && chown -R webuser:webuser /app

WORKDIR /app

USER webuser

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -q --spider http://localhost:8080/actuator/health || exit 1

# Idle fallback when no fat JAR is present. See nodejs/Dockerfile.
ENTRYPOINT ["sh", "-c"]
CMD ["if [ -f /app/app.jar ]; then exec java -jar /app/app.jar; else echo '[runtime] No /app/app.jar — idle. Mount your Spring Boot fat JAR and restart.'; exec sleep infinity; fi"]
