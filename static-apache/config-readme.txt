Custom Apache configuration for this static site.

This folder is your Apache config directory — it exists because you set the
`APACHE_CONF_DIR` environment variable on this deployment. It is loaded into the
main server config and is NEVER web-accessible (visitors cannot download it).

WHAT TO DO
  Drop one or more `*.conf` files into this folder. They are loaded with:

      IncludeOptional <this folder>/*.conf

  which runs in the MAIN SERVER context, so put server-context directives here —
  for example:

      # custom-headers.conf
      <IfModule mod_headers.c>
          Header set X-Frame-Options "SAMEORIGIN"
          Header set X-Content-Type-Options "nosniff"
      </IfModule>

      # spa-fallback.conf  (single-page apps)
      <Directory "/usr/local/apache2/htdocs">
          RewriteEngine On
          RewriteCond %{REQUEST_FILENAME} !-f
          RewriteCond %{REQUEST_FILENAME} !-d
          RewriteRule ^ /index.html [L]
      </Directory>

      # redirect.conf
      Redirect 301 /old-page.html /new-page.html

NOTES
  * Leave this folder empty (just this README) to keep the built-in default.
  * Do NOT add a `<VirtualHost>` block or a second `Listen` directive — the
    default config already serves this site and Apache would refuse to start or
    would shadow it. Use `<Directory>`, `<Location>`, `Redirect`, `Rewrite*`,
    and `Header` directives instead.
  * You can also use a `.htaccess` file in your web root — `AllowOverride All`
    is already enabled — which needs NO restart. Use this folder for directives
    `.htaccess` cannot express (e.g. `Alias`, `Header always`, `<Location>`).
  * `/health` is reserved for the platform's readiness probe.
  * Apache reads config only at startup, so RESTART the workload after adding or
    editing files here. Your static files are served live and need no restart.
  * If anything in this folder is invalid, the whole folder is IGNORED and the
    site restarts on the default config rather than going down. The reason is
    printed in the workload logs — look for `[apache-entry]`.
  * To turn this off, clear the APACHE_CONF_DIR variable.

This README is ignored by the `*.conf` include (it is not a .conf file) and is
recreated automatically if deleted.
