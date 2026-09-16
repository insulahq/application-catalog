# Apache + PHP with the document toolchain Moodle (and other LMS/DMS apps) shell
# out to. Everything web-facing — extensions, vhost templates, multi-host
# includes, real-client-IP handling, the PHP_* tuning knobs — comes from
# apache-php unchanged; this image only adds binaries.
#
# Why a separate image instead of adding these to apache-php: LibreOffice is
# +343 MB and Ghostscript +96 MB (measured on Debian 13), which every plain PHP
# tenant would otherwise pull to run a WordPress site that never converts a
# document. Tenants opt in by choosing this runtime.
#
# Why FROM the published apache-php rather than serversideup directly: the two
# images must not drift. A second copy of the extension list, the vhost
# overrides and the FPM pool hardening is a second thing to keep in sync, and
# the last time an extension quietly went missing it took months to notice.
# build-images.yml therefore builds this image AFTER apache-php, per PHP version.
ARG PHP_VERSION=8.4
FROM ghcr.io/insulahq/application-catalog/apache-php:${PHP_VERSION}

USER root

# The -nogui LibreOffice packages skip the GTK/X11 stack, which a headless
# converter never uses. Java is deliberately NOT installed: Writer/Calc/Impress
# to PDF does not need it, and default-jre-headless is another ~150 MB plus a
# second security-update surface.
#
# Fonts matter for correctness, not looks: without metric-compatible faces,
# LibreOffice substitutes and a converted page paginates differently from what
# the student submitted.
#
# Paths are what Moodle's Site administration → System paths defaults expect,
# so a fresh install needs no reconfiguration:
#   ghostscript    -> /usr/bin/gs         (pathtogs; Annotate PDF feedback)
#   poppler-utils  -> /usr/bin/pdftoppm   (pathtopdftoppm; editpdf alternative)
#   graphviz       -> /usr/bin/dot        (pathtodot)
#   aspell         -> /usr/bin/aspell     (aspellpath)
#   python3        -> /usr/bin/python3    (pathtopython)
# ClamAV is intentionally absent — antivirus_clamav speaks tcpsocket, so one
# shared clamd Service beats a scanner plus a 300 MB signature database in
# every tenant's image.
RUN set -eux; \
    apt-get update; \
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      ghostscript \
      poppler-utils \
      libreoffice-writer-nogui \
      libreoffice-calc-nogui \
      libreoffice-impress-nogui \
      fonts-liberation \
      fonts-dejavu-core \
      graphviz \
      aspell \
      aspell-en \
      python3 \
    ; \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Moodle's default pathtounoconv is /usr/bin/unoconv, so that is where the shim
# goes — a tenant who changes nothing gets a working converter. See the script
# header for why this is a shim and exactly which unoconv behaviours it has to
# reproduce.
COPY unoconv /usr/bin/unoconv
RUN set -eux; \
    chmod 0755 /usr/bin/unoconv; \
    ln -sf /usr/bin/unoconv /usr/local/bin/unoconv; \
    # Fail the build, not a tenant's assignment, if the shim stops satisfying
    # the two checks Moodle gates every conversion on. The real end-to-end
    # conversion runs in CI (scripts/check-office-tools.sh) as www-data.
    /usr/bin/unoconv --version | grep -qE 'unoconv [0-9]+\.[0-9]+'; \
    /usr/bin/unoconv --show 2>&1 >/dev/null | grep -q '\[\.pdf\]'; \
    test -x /usr/bin/gs; \
    test -x /usr/bin/pdftoppm

USER www-data
