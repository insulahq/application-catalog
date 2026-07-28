FROM httpd:2.4-alpine

# Enable useful modules
COPY httpd.conf /usr/local/apache2/conf/httpd.conf

# Writable include dir. httpd.conf does
# `IncludeOptional conf/user-include/*.conf`; when APACHE_CONF_DIR is set the
# entrypoint writes a glue file here that includes the tenant's own directory.
COPY user-include/ /usr/local/apache2/conf/user-include/

# config-readme.txt is seeded into the tenant's APACHE_CONF_DIR at runtime so
# the guidance sits where they work (file manager / SFTP).
COPY config-readme.txt /usr/local/share/apache-config-readme.txt
COPY docker-entrypoint.sh /usr/local/bin/apache-entry

RUN adduser -D -u 1000 webuser \
  && chown -R webuser:webuser /usr/local/apache2/htdocs \
  && chmod +x /usr/local/bin/apache-entry

WORKDIR /usr/local/apache2/htdocs

EXPOSE 80

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -q --spider http://localhost/ || exit 1

ENTRYPOINT ["/usr/local/bin/apache-entry"]
CMD ["httpd-foreground"]
