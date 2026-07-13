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
| **runtime** | `apache-php`, `nginx-php`, `nodejs`, `bun-latest`, `python-312`, `ruby-33`, `golang-122`, `java-21`, `dotnet-8`, `rust-stable` |
| **database** | `mariadb`, `mysql`, `postgresql`, `mongodb-7` |
| **service** | `redis-7`, `memcached-alpine`, `minio` |
| **static** | `static-nginx`, `static-apache` |

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

## Validate

```bash
npm ci
npm run format:check
npm run validate
```
