#!/usr/bin/env bash
# Assert that a built apache-php-office image can actually do the work Moodle
# asks of it. Run against the LOCALLY BUILT image before it is pushed.
#
# Usage: scripts/check-office-tools.sh <image-ref>
#
# Why this exists, and why it converts a real file rather than checking that the
# packages are installed: "ghostscript is in the Dockerfile" and "a teacher can
# annotate a submission" are different claims, and the gap between them is where
# an image like this fails — a LibreOffice that cannot write its user profile, a
# shim whose --show output Moodle's parser cannot read, a PDF that comes out
# zero bytes. The checks live in scripts/office-tools-probe.sh and run inside
# the image as www-data.
#
# The probe is piped over stdin instead of bind-mounted so this works against a
# remote Docker daemon, where a -v path would resolve on the daemon's host.
set -euo pipefail

image="${1:-}"
if [ -z "$image" ]; then
  echo "usage: $0 <image-ref>" >&2
  exit 2
fi

script_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
probe="$script_dir/office-tools-probe.sh"

if [ ! -f "$probe" ]; then
  echo "FAIL: office-tools-probe.sh not found next to $0" >&2
  exit 2
fi

echo "Checking office toolchain in $image"
docker run --rm -i --entrypoint /bin/bash "$image" -s < "$probe"
