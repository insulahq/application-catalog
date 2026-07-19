FROM node:22-alpine

RUN apk add --no-cache curl \
  && mkdir -p /app && chown node:node /app

WORKDIR /app

USER node

# Real client IP: this runtime executes YOUR server.js, so recovering the
# visitor's IP is app-side — the platform's Traefik ingress forwards it in
# X-Forwarded-For / X-Real-IP, but your app's socket peer is the Traefik pod
# (k3s pod CIDR 10.42.0.0/16). Configure your framework to trust the proxy:
#   Express/Koa:  app.set('trust proxy', '10.0.0.0/8, 172.16.0.0/12, 192.168.0.0/16')
#   Fastify:      { trustProxy: '10.0.0.0/8' }   // or true
# then read req.ip. Also trust your external LB's CIDR if one fronts the cluster.
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -q --spider http://localhost:3000/health || exit 1

# Idle fallback: keep the container alive when no app code is staged yet.
# The platform deploys this image as a runtime — clients drop their
# server.js into /app and restart the deployment to pick it up. Without
# this fallback the container CrashLoopBackOff'd before the user could
# upload any code.
CMD ["sh", "-c", "if [ -f /app/server.js ]; then exec node /app/server.js; else echo '[runtime] No /app/server.js — idle. Mount your app and restart the deployment.'; exec sleep infinity; fi"]
