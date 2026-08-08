# Real client IP behind the platform ingress

Requests reach a workload from the platform's Traefik pod, never directly from
the internet. The TCP peer your app sees is therefore a **pod address**
(`10.42.x.x`), not the visitor. The visitor's address — IPv4 **or** IPv6 —
arrives in the `X-Forwarded-For` header.

This is not an IPv6 quirk. The platform serves IPv6 on the public edge and routes
IPv4 inside the cluster, so a v6 visitor's address *cannot* survive as a TCP peer
by construction; v4 visitors are equally masked. IPv6 only made it obvious.

If your app reads the peer address directly (`REMOTE_ADDR`, `req.socket.remoteAddress`,
`r.RemoteAddr`, …) then **every visitor on earth looks like one internal address**:
rate-limiting, geo-logic, audit logs, abuse blocking and "last login IP" all break.

## Where this is already handled for you

| Image | Status |
|---|---|
| `nginx-php`, `static-nginx` | ✅ `set_real_ip_from` + `real_ip_header` + `real_ip_recursive` |
| `static-apache`, `apache-php` | ✅ `mod_remoteip` with `RemoteIPHeader` / `RemoteIPTrustedProxy` |

`$_SERVER['REMOTE_ADDR']` in PHP, and the access-log client field, are the real
visitor on those images. Nothing to do.

## Where YOUR application must opt in

The runtime images (`nodejs`, `bun-latest`, `python-312`, `ruby-33`, `java-21`,
`dotnet-8`, `golang-122`, `rust-stable`) run **your** program directly — there is
no web server in the image to rewrite the address for you, so the framework has
to trust the header.

> There is no generic image-level switch for this. Notably, gunicorn's
> `--forwarded-allow-ips` does **not** rewrite `REMOTE_ADDR` — it governs
> `X-Forwarded-Proto` handling (`secure_scheme_headers`). Verified empirically:
> with `--forwarded-allow-ips="*"`, `REMOTE_ADDR` still reported the peer.
> Use your framework's proxy middleware instead.

Trust only private ranges — `10.0.0.0/8`, `172.16.0.0/12`, `192.168.0.0/16` and
`fd00::/8` (the dual-stack pod CIDR's IPv6 ULA). Traefik **appends** the peer it
observed, so the real client is the right-most untrusted entry; trusting
everything (`trust proxy: true`, `*`) lets a visitor forge their own address by
sending the header themselves — which would make any rate limit bypassable.

**Node.js / Express**
```js
app.set('trust proxy', ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', 'fd00::/8']);
// req.ip is now the visitor
```

**Python / Django** — `SecurityMiddleware` plus a proxy-aware middleware, or
Werkzeug's `ProxyFix` for Flask:
```python
from werkzeug.middleware.proxy_fix import ProxyFix
app.wsgi_app = ProxyFix(app.wsgi_app, x_for=1, x_proto=1, x_host=1)
```

**Ruby on Rails** — already correct: `ActionDispatch::RemoteIp` is on by default
and treats private ranges as proxies, so `request.remote_ip` is the visitor.

**Java / Spring Boot**
```
SERVER_FORWARD_HEADERS_STRATEGY=framework
```

**.NET / ASP.NET Core**
```
ASPNETCORE_FORWARDEDHEADERS_ENABLED=true
```

**Go / Rust** — parse it yourself; take the **last** entry of `X-Forwarded-For`,
or use your framework's proxy middleware (e.g. `echo.ExtractIPFromXFFHeader`).

## Community application stacks

The self-contained app stacks (WordPress, Nextcloud, Gitea, BookStack, …) live in
the opt-in [community catalog](https://github.com/insulahq/application-catalog-community)
and are a different situation: we do not build those images, so the lever is each
app's own trusted-proxy setting, applied in its `manifest.json`. Per-app status —
which are configured for you, which are already correct by their framework's
defaults, and which need an action inside the app — is in that repo's
[REAL_CLIENT_IP.md](https://github.com/insulahq/application-catalog-community/blob/main/REAL_CLIENT_IP.md).

## Checking it works

Deploy, hit your site, and confirm your logs show a public address rather than
`10.42.x.x`. From a v6-capable host, `curl -6 https://<your-domain>/` should show
the v6 address, not the pod IP.
