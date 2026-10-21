#!/usr/bin/env bash
# Decide which apache-php image one apache-php-office leg builds on, and whether
# it builds at all. Called by build-images.yml ("Resolve base image").
#
# Inputs (environment):
#   PUSHES      "true" when this run publishes (push / schedule / dispatch on main)
#   PHP_IMAGES  the run's PHP build matrix as JSON, e.g. ["apache-php","nginx-php"]
#   BASE_REPO   ghcr.io/<owner>/<repo>/apache-php
#   PHP         this leg's PHP version, e.g. 8.4
#   SHA         the commit being built
#
# Outputs ($GITHUB_OUTPUT, or stdout when unset):
#   build=true|false
#   tag=<apache-php tag to build FROM>   (only when build=true)
#
# Why office does not simply wait for "build-php succeeded": that job is ONE
# matrix holding nginx-php too, and its result is failure if any leg fails —
# which kept every office version on a weeks-old base while only nginx-php was
# broken. Office needs exactly one thing: apache-php at its own PHP version, as
# built by this run. The immutable :<php>-<sha> tag that leg pushes is the
# proof, so check the registry for it instead of inferring it from job results.
set -euo pipefail

: "${PUSHES:?}" "${PHP_IMAGES:?}" "${BASE_REPO:?}" "${PHP:?}" "${SHA:?}"
out="${GITHUB_OUTPUT:-/dev/stdout}"

rebuilt_here=false
if jq -e 'index("apache-php") != null' <<<"$PHP_IMAGES" >/dev/null; then
  rebuilt_here=true
fi

if [ "$PUSHES" != "true" ] || [ "$rebuilt_here" != "true" ]; then
  # Pull requests and branch dispatches publish nothing, and an office-only
  # change has no new base: the published :<php> is the right base.
  echo "Building on the published ${BASE_REPO}:${PHP}"
  { echo "build=true"; echo "tag=${PHP}"; } >> "$out"
  exit 0
fi

tag="${PHP}-${SHA}"
if docker buildx imagetools inspect "${BASE_REPO}:${tag}" >/dev/null 2>&1; then
  echo "Building on ${BASE_REPO}:${tag}, published by this run"
  { echo "build=true"; echo "tag=${tag}"; } >> "$out"
  exit 0
fi

# Not an error of THIS leg: the apache-php leg either failed (and already turns
# the run red) or was cancelled by a newer run, which rebuilds office itself.
echo "::warning::apache-php ${PHP} was not published by this run (its build failed or a newer run superseded it) — not rebuilding apache-php-office ${PHP} on a stale base"
echo "build=false" >> "$out"
