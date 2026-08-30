#!/usr/bin/env bash
# test-real-client-ip.sh — the web-serving images must resolve the REAL client
# address, and must not let a client forge it.
#
# WHY
#   Requests reach these containers from the platform's Traefik pod, never
#   directly from the internet. Without real-IP handling every visitor on earth
#   is logged as one pod address (10.42.x.x) and PHP sees that same value in
#   $_SERVER['REMOTE_ADDR'] — so tenant rate-limiting, geo-logic, audit logs and
#   abuse blocking all collapse to a single client. Measured on a live
#   dual-stack cluster before the fix: an IPv6 visitor logged as
#       10.42.171.175 … "2a01:…:aaa8::1"
#   with the true address present only as an X-Forwarded-For field.
#
# THE RULES PINNED HERE
#   1. A single X-Forwarded-For entry becomes the client address.
#   2. Traefik APPENDS the peer it observed, so the chain is
#      "<what the client sent>, <real client>" — the RIGHT-most untrusted entry
#      is the truth. A forged prefix must NOT win, or any tenant rate limit can
#      be bypassed with one header.
#   3. IPv6 clients work identically (the platform serves v6 on the public edge
#      while routing IPv4 internally, so the v6 address arrives only in XFF).
#   4. With no XFF at all, the peer address is used — no crash, no empty value.
#
# Runs the REAL shipped configs against real nginx / httpd / php-fpm.
# Requires docker. Exit 0 all pass · 1 a case failed · 77 docker unavailable.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v docker >/dev/null 2>&1 || { echo "SKIP (77): docker not available"; exit 77; }

# Bind-mount sources must be visible to the DOCKER DAEMON, which may be in a
# different mount namespace than this shell (DinD): stage under the repo, not
# /tmp, or the mount silently becomes an empty directory.
WORK="$ROOT/.realip-test.$$"
CLEAN=(ripn-$$ ripa-$$)
cleanup() { docker rm -f "${CLEAN[@]}" >/dev/null 2>&1 || true; rm -rf "$WORK"; }
trap cleanup EXIT
mkdir -p "$WORK"

fails=0
chk() { if [[ "$3" == "$2" ]]; then printf '  ✓ %-44s %s\n' "$1" "$3"
        else printf '  ✗ %-44s got %s, want %s\n' "$1" "$3" "$2"; fails=$((fails+1)); fi; }
# Drive from a SIBLING container so the peer is a bridge address (RFC1918) —
# the same shape as Traefik's pod IP, i.e. a trusted proxy. Driving from the
# host would arrive from a non-trusted address and the test would prove nothing.
hit() { docker run --rm curlimages/curl:latest -s -m 10 "$@" 2>/dev/null; }
ipof() { docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$1" 2>/dev/null; }

echo "── static-nginx ──"
echo ok > "$WORK/index.html"
docker run -d --name "ripn-$$" -v "$ROOT/static-nginx/nginx.conf:/etc/nginx/conf.d/default.conf:ro" \
  -v "$WORK:/var/www/html" nginx:alpine \
  sh -c 'mkdir -p /etc/nginx/user-include && nginx -g "daemon off;"' >/dev/null
sleep 3; N=$(ipof "ripn-$$")
hit -o /dev/null -H 'X-Forwarded-For: 203.0.113.7'          "http://$N:8080/" >/dev/null
hit -o /dev/null -H 'X-Forwarded-For: 9.9.9.9, 203.0.113.8' "http://$N:8080/" >/dev/null
hit -o /dev/null -H 'X-Forwarded-For: 2001:db8::1'          "http://$N:8080/" >/dev/null
hit -o /dev/null                                            "http://$N:8080/" >/dev/null
sleep 1; L=$(docker logs "ripn-$$" 2>/dev/null | grep -F 'GET /' | tail -4)
chk "single XFF"           "203.0.113.7" "$(sed -n 1p <<<"$L" | awk '{print $1}')"
chk "forged prefix ignored" "203.0.113.8" "$(sed -n 2p <<<"$L" | awk '{print $1}')"
chk "IPv6 client"          "2001:db8::1" "$(sed -n 3p <<<"$L" | awk '{print $1}')"
P=$(sed -n 4p <<<"$L" | awk '{print $1}')
case "$P" in 10.*|172.*|192.168.*) printf '  ✓ %-44s %s\n' "no XFF falls back to peer" "$P" ;;
  *) printf '  ✗ %-44s %s\n' "no XFF falls back to peer" "$P"; fails=$((fails+1)) ;; esac

echo "── static-apache ──"
docker run -d --name "ripa-$$" -v "$ROOT/static-apache/httpd.conf:/usr/local/apache2/conf/httpd.conf:ro" \
  httpd:2.4-alpine sh -c 'adduser -D -u 1000 webuser 2>/dev/null; echo ok > /usr/local/apache2/htdocs/index.html; httpd-foreground' >/dev/null
sleep 3; A=$(ipof "ripa-$$")
hit -o /dev/null -H 'X-Forwarded-For: 203.0.113.7'          "http://$A/" >/dev/null
hit -o /dev/null -H 'X-Forwarded-For: 9.9.9.9, 203.0.113.8' "http://$A/" >/dev/null
hit -o /dev/null -H 'X-Forwarded-For: 2001:db8::1'          "http://$A/" >/dev/null
sleep 1; AL=$(docker logs "ripa-$$" 2>/dev/null | grep -F 'GET /' | tail -3)
chk "single XFF"            "203.0.113.7" "$(sed -n 1p <<<"$AL" | awk '{print $1}')"
chk "forged prefix ignored" "203.0.113.8" "$(sed -n 2p <<<"$AL" | awk '{print $1}')"
chk "IPv6 client"           "2001:db8::1" "$(sed -n 3p <<<"$AL" | awk '{print $1}')"
grep -q 'via=' <<<"$AL" && printf '  ✓ %-44s %s\n' "delivering proxy still logged" "$(grep -o 'via=[^ ]*' <<<"$AL" | head -1)" \
  || { printf '  ✗ %-44s\n' "delivering proxy still logged"; fails=$((fails+1)); }

# The PHP runtimes (apache-php / nginx-php) are NOT tested here any more.
# They no longer ship a standalone config file to mount — the real-IP handling
# now lives inside the built image (an appended vhost include for Apache, a
# rewritten real_ip_header for NGINX). Testing a config file we no longer ship
# would prove nothing about the artefact, so the equivalent assertions run in
# .github/workflows/build-images.yml against the actual built image, right
# after the extension check. See the "Assert real client IP" step there.
echo
if (( fails > 0 )); then echo "❌ test-real-client-ip: $fails case(s) failed" >&2; exit 1; fi
echo "✅ test-real-client-ip: images resolve the true client address and reject forged X-Forwarded-For."
