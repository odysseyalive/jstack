# Service Architecture

jstack has two containers and nothing else built-in: **nginx** and **certbot**.
Everything else (n8n, databases, headless browsers, etc.) is the responsibility
of an individual site under `sites/<domain>/` — that site brings its own
containers in its own `docker-compose.yml`.

## nginx — reverse proxy

**Role:** Listens on 80/443, routes traffic to your sites, handles TLS
termination.

- Active site configs: `nginx/conf.d/`
- Cert volume: `nginx/certbot/conf` (mounted at `/etc/letsencrypt`)
- Logs: `nginx/logs/`

Common ops:

```bash
docker-compose exec nginx nginx -t        # validate config
docker-compose exec nginx nginx -s reload # apply config without restart
docker-compose restart nginx              # restart container
docker-compose logs nginx                 # tail logs
```

## certbot — Let's Encrypt automation

**Role:** Acquires and renews SSL certs. Renewal loop runs every 12h inside
the container.

```bash
docker-compose exec certbot certbot certificates       # list certs + expiry
docker-compose exec certbot certbot renew --dry-run    # test renewal
```

## Per-site services

If your site needs a database, a queue, or any other service, bundle it into
the site's own `sites/<domain>/docker-compose.yml`. The site's compose file
joins the same docker network as nginx automatically — nginx can proxy to it
by container name.

Example site structure:

```
sites/my-site.com/
├── Dockerfile
├── docker-compose.yml      # defines my-site-app + any backing services (postgres, redis, etc.)
├── .env                    # DOMAIN, PORT, CONTAINER
└── app/                    # site source
```

`bash jstack.sh --install-site sites/my-site.com` will:

1. Bring up the site's compose.
2. Generate `nginx/conf.d/my-site.com.conf` pointing at the site's container.
3. Acquire a Let's Encrypt cert for `my-site.com`.

See [site-templates.md](site-templates.md) for ready-to-copy templates
(static, LAMP, Node).

## Quick health checks

```bash
bash jstack.sh status                    # all services jstack knows about
docker-compose ps                        # raw docker view
docker-compose logs [service-name]
bash jstack.sh restart                   # restart everything
```
