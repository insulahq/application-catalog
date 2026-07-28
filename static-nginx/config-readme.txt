Custom NGINX configuration for this static site.

This folder is your NGINX config directory — it exists because you set the
`NGINX_CONF_DIR` environment variable on this deployment. It is loaded into the
default server block and is NEVER web-accessible (visitors cannot download it).

WHAT TO DO
  Drop one or more `*.conf` files into this folder. They are loaded with:

      include <this folder>/*.conf;

  which runs INSIDE the default `server { ... }` block, so put server-context
  directives here — for example:

      # custom-headers.conf
      add_header X-Frame-Options "SAMEORIGIN";
      add_header X-Content-Type-Options "nosniff";

      # spa-fallback.conf  (single-page apps)
      location /app/ {
          try_files $uri $uri/ /app/index.html;
      }

      # redirect.conf
      location = /old-page.html {
          return 301 /new-page.html;
      }

NOTES
  * Leave this folder empty (just this README) to keep the built-in default.
  * Do NOT redefine `location /` or add a `server { ... }` block here — both
    already exist in the default config and NGINX would refuse to start with a
    duplicate. Use specific paths instead (e.g. `location /api/`).
  * `/health` is reserved for the platform's readiness probe.
  * NGINX reads config only at startup, so RESTART the workload after adding or
    editing files here. Your static files are served live and need no restart.
  * To turn this off, clear the NGINX_CONF_DIR variable.

This README is ignored by the `*.conf` include (it is not a .conf file) and is
recreated automatically if deleted.
