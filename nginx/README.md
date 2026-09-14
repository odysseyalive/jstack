# Nginx Configuration Directory

This directory contains the nginx configuration for JStack. jstack runs two containers, nginx and
certbot, and nothing else. A site that needs a database, a queue, or a headless browser brings its
own containers in `sites/<domain>/docker-compose.yml`.

## Files

- `nginx.conf` - Main nginx configuration, mounted read-only
- `conf.d/` - One config file per site, plus the catch-all `default.conf`
- `certbot/` - Let's Encrypt certificates (`certbot/conf`) and ACME challenge files (`certbot/www`), shared with the certbot container
- `htpasswd/` - Basic-auth password files, mounted read-only; never committed
- `logs/` - nginx access and error logs
- `ssl/` - Legacy directory. Some install scripts still create it, but it is not mounted into the nginx container

## Site configs in `conf.d/`

Each site gets `conf.d/<domain>.conf`, written when the site is installed by
`scripts/core/setup_service_subdomains_ssl.sh`. It starts as HTTP-only so Let's Encrypt can issue a
certificate, then is rewritten for HTTPS with an HTTP-to-HTTPS redirect.

⚠️ **Do not hand-edit a site's `<domain>.conf`.** Re-installing the site regenerates it and your change is lost.

`conf.d/default.conf` is the exception. It is the port-80 catch-all for unmatched hosts and bare-IP
requests, no script generates it, and it is maintained by hand.

Every `*.conf` in `conf.d/` is gitignored, because each server generates its own.
