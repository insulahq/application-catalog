# Official Catalog

The **default, first-party catalog** for the [Insula](https://github.com/insulahq/insula)
Kubernetes hosting platform. It ships the platform **primitives** — language runtimes,
databases, and services — that tenants build their workloads on. Every entry is deployed via a
Helm chart.

This repository is seeded **active** on every fresh install and is the source of truth for
runtime/database/service catalog entries.

## What's here

| Type | Entries |
|------|---------|
| **runtime** | `apache-php`, `apache-php-office`, `nginx-php`, `nodejs`, `bun-latest`, `python-312`, `ruby-33`, `golang-122`, `java-21`, `dotnet-8`, `rust-stable` |
| **database** | `mariadb`, `mysql`, `postgresql`, `mongodb-7` |
| **service** | `redis-7`, `memcached-alpine` |
| **static** | `static-nginx` (code `nginx`), `static-apache` (code `apache`) |

## What's *not* here — self-contained application stacks

Bundled applications (WordPress, Nextcloud, Gitea, Immich, n8n, Discourse, …) live in the
separate, **opt-in** [`insulahq/application-catalog-community`](https://github.com/insulahq/application-catalog-community)
repository. Add it under **Applications → Repositories** in the admin panel if you want them.

This keeps the default catalog lean, fully first-party, and hardenable — every image here is one
we build and control.

## Layout

```
<entry>/
  manifest.json   # catalog metadata (type, components, versions, parameters)
  chart/          # Helm chart
  icon.png
  Dockerfile      # buildable runtimes/static only (databases/services use upstream images)
catalog.json      # index: ordered list of entry slugs
schema/           # manifest JSON schema
scripts/          # validate / format tooling
```

## Images

Buildable runtime/static images publish to **`ghcr.io/insulahq/application-catalog/<entry>`** via
`.github/workflows/build-images.yml` (tags: `<git-sha>`, `<chart-tag>`, `latest`). Databases and
services reference upstream public images directly.

Each image is rebuilt when its own files change and again every Monday, without
the layer cache, so it picks up the OS-package fixes its base and its
`apk upgrade` / `apt-get upgrade` step pull in. A weekly rebuild republishes the
moving tags (`<chart-tag>`, `latest`) and takes the immutable tag
`<git-sha>-<run-id>`. Only an image whose build cannot work is left out (named,
with the reason, in `SCHEDULE_SKIP` in the workflow); no image is skipped
because it is stable.

The two PHP runtimes are built once per supported PHP version, so their tags are
`8.3` / `8.4` / `8.5` (immutable form: `<php>-<git-sha>`, or `<php>-<git-sha>-<run-id>`
for a weekly rebuild), with `latest` tracking
the manifest's `isDefault` version. They are built `FROM serversideup/php`, which
keeps the `PHP_*` tuning knobs, the non-root runtime, port 8080 and `/healthcheck`
that the manifests depend on, and add the extension set real applications need —
gd, imagick, imap, intl, soap, ldap, bcmath, gmp, exif, xsl, mysqli, pgsql,
memcached and apcu among them.

The authoritative list is **`scripts/required-php-extensions.txt`**, asserted
against `php -m` of every built image by `scripts/check-php-extensions.sh` before
it is pushed. Add an extension to both Dockerfiles *and* that list. Because we
build these ourselves we also own their base-image patch cadence; the weekly
rebuild above covers them.

## Real client IP

Workloads are reached through the platform's Traefik pod, so the TCP peer is a
pod address and the visitor's address (v4 or v6) arrives in `X-Forwarded-For`.
The web-serving images resolve it for you; the runtime images run *your*
program, so your framework has to trust the header. Per-runtime guidance and the
reasoning — including why gunicorn's `--forwarded-allow-ips` is **not** the
answer — are in [REAL_CLIENT_IP.md](REAL_CLIENT_IP.md).

## Validate

```bash
npm ci
npm run format:check
npm run validate
```
