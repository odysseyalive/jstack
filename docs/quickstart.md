# jstack Quickstart

## Prerequisites

- Debian 12 server you control
- A domain name pointing at the server
- A user in the `docker` group with `sudo` access
- Docker + docker-compose v1 installed (`docker compose` v2 also works)

## 1. Clone and configure

```bash
git clone https://github.com/odysseyalive/jstack.git
cd jstack
cp jstack.config.default jstack.config
nano jstack.config   # set DOMAIN and EMAIL
```

Only `DOMAIN` and `EMAIL` are required.

## 2. Install

```bash
bash jstack.sh --install
```

This:

1. Installs system dependencies (Docker tooling, fail2ban, etc.).
2. Creates `nginx/`, `nginx/certbot/`, and log dirs.
3. Brings up nginx + certbot via `docker-compose.yml`.
4. Acquires a Let's Encrypt cert for your base `DOMAIN`.
5. Sets up fail2ban and log rotation.

## 3. Deploy a site

Drop your site under `sites/<domain>/` with its own `Dockerfile` and
`docker-compose.yml`. See [site-templates.md](site-templates.md) for the
expected shape — or copy one of the bundled examples in `site-templates/`.

Then install it:

```bash
bash jstack.sh --install-site sites/<domain>
```

This brings up your site container, writes an nginx config, and acquires SSL.

To redeploy after rebuilding the image:

```bash
bash jstack.sh deploy <site-domain>
```

## 4. Day-to-day operation

```bash
bash jstack.sh up        # start nginx + certbot + any defined sites
bash jstack.sh down
bash jstack.sh restart
bash jstack.sh status
bash jstack.sh diagnostics <service>
bash jstack.sh validate
bash jstack.sh --dry-run up
```

## Troubleshooting

- Install log: `logs/install.log`
- Per-domain TLS / HTTPS check: `bash jstack.sh diagnostics <domain>`
- Permission issues on data dirs: `bash scripts/core/fix_workspace_permissions.sh`
- See [troubleshooting.md](troubleshooting.md) for common failure modes.
