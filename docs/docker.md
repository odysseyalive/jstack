# Docker & Containers

jstack uses Docker to run nginx + certbot as the core stack, and each site
under `sites/<domain>/` runs its own container(s). Sites can bring their own
backing services (databases, queues, etc.) in their own `docker-compose.yml`.

## Containers you'll see

The core stack:

- `jstack_nginx_1` — reverse proxy on 80/443
- `jstack_certbot_1` — Let's Encrypt renewal loop

Plus one or more site containers (defined under `sites/<domain>/` or in your
local `docker-compose.override.yml`).

## Essential commands

### Status

```bash
docker-compose ps                        # service status from jstack's compose
docker ps                                # all running containers
docker stats                             # live CPU/memory
```

### Start / stop / restart

```bash
./jstack.sh up                           # start core + sites
./jstack.sh down
./jstack.sh restart
docker-compose restart nginx             # restart just nginx
```

### Logs

```bash
docker-compose logs                      # all core services
docker-compose logs -f nginx             # follow nginx logs
docker-compose logs --tail=50 certbot
```

For a site:

```bash
docker-compose -f sites/<domain>/docker-compose.yml logs -f
```

### Shell into a container

```bash
docker-compose exec nginx /bin/bash
docker-compose exec nginx nginx -t       # validate nginx config
```

## Data persistence

Anything mounted to your workspace survives container restarts/recreates:

```
./nginx/conf.d/             # Site nginx configs
./nginx/certbot/conf/       # Let's Encrypt certs
./nginx/logs/               # Access + error logs
./sites/<domain>/           # Site source + data
```

Anything in a named Docker volume (or only inside a container layer) does NOT.

## Network

All core + site containers share a single Docker bridge network. nginx can
proxy to any other container by its container name:

```nginx
proxy_pass http://my-site-container:3000;
```

```bash
docker network ls
docker network inspect jstack_default
```

## Lifecycle

### Update images

```bash
docker-compose pull
docker-compose up -d --force-recreate
```

### Rebuild

```bash
docker-compose down
docker-compose up -d --build
```

### Cleanup

```bash
docker container prune                   # stopped containers
docker image prune                       # unused images
docker volume prune                      # unused volumes — careful
docker system prune -a                   # full cleanup
```

## Troubleshooting

### Container won't start

```bash
docker-compose logs [service-name]
netstat -tlnp | grep :80
netstat -tlnp | grep :443
```

### Permission issues

```bash
./scripts/core/fix_workspace_permissions.sh
ls -la sites/<domain>/
```

### Out of disk

```bash
df -h
docker system prune -a
```

## Adding services for a site

If a site needs a database, queue, or anything else, declare it in the site's
own `sites/<domain>/docker-compose.yml`:

```yaml
services:
  my-site-app:
    build: .
    environment:
      - DATABASE_URL=postgres://postgres@my-site-db:5432/mydb

  my-site-db:
    image: postgres:16
    volumes:
      - ./data/db:/var/lib/postgresql/data
```

The compose file gets included in `bash jstack.sh up` automatically via
`--install-site`.

## Security defaults

- Containers run as non-root where possible
- Only nginx exposes ports to the host (80/443)
- Sites talk to each other and to backing services via the internal docker
  network — they don't need host-port mappings unless you want external access

## Backup

```bash
./jstack.sh --backup                     # built-in backup
cp -r nginx/conf.d nginx/certbot/conf sites/ backups/   # manual
```

Sites with their own databases should run their own pg_dump / mysqldump on a
schedule (see [automation.md](automation.md)).
