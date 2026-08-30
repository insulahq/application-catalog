#!/usr/bin/env bash
# Assert that a built PHP runtime image carries every extension the platform
# promises. Run against the LOCALLY BUILT image before it is pushed, so a
# regression never reaches a tenant.
#
# Usage: scripts/check-php-extensions.sh <image-ref>
#
# Why this exists: the catalog silently shipped a PHP runtime with no gd, no
# imap and no intl for months because nothing asserted the extension set. A
# list in a Dockerfile is a wish; `php -m` of the built artefact is the fact.
set -euo pipefail

image="${1:-}"
if [ -z "$image" ]; then
  echo "usage: $0 <image-ref>" >&2
  exit 2
fi

script_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
list_file="$script_dir/required-php-extensions.txt"

if [ ! -f "$list_file" ]; then
  echo "FAIL: required-php-extensions.txt not found next to $0" >&2
  exit 2
fi

echo "Checking PHP extensions in $image"

# `php -m` prints two sections ([PHP Modules] / [Zend Modules]). Keep both —
# OPcache only appears by its Zend name.
actual="$(docker run --rm --entrypoint php "$image" -m \
  | grep -vE '^\[|^$' \
  | tr '[:upper:]' '[:lower:]' \
  | sort -u)"

if [ -z "$actual" ]; then
  echo "FAIL: could not read 'php -m' from $image" >&2
  exit 1
fi

missing=""
while IFS= read -r ext; do
  # strip comments and surrounding whitespace, skip blanks
  ext="${ext%%#*}"
  ext="$(printf '%s' "$ext" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
  [ -n "$ext" ] || continue
  # `Zend OPcache` loses its space in the normalisation above; do the same to
  # the haystack so the comparison stays whole-entry rather than substring.
  if ! printf '%s\n' "$actual" | tr -d ' ' | grep -qx "$ext"; then
    missing="$missing $ext"
  fi
done < "$list_file"

if [ -n "$missing" ]; then
  echo "FAIL: $image is missing required PHP extension(s):" >&2
  for m in $missing; do echo "  - $m" >&2; done
  echo >&2
  echo "Present in the image:" >&2
  printf '%s\n' "$actual" | tr '\n' ' ' >&2
  echo >&2
  exit 1
fi

count="$(printf '%s\n' "$actual" | wc -l | tr -d ' ')"
echo "OK: all required extensions present ($count modules total)"
