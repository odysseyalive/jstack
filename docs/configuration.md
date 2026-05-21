# jstack Configuration

This guide walks through `jstack.config`. Only `DOMAIN` and `EMAIL` are
required.

## Getting started

```bash
cp jstack.config.default jstack.config
nano jstack.config
```

## Required settings

### `DOMAIN`

Your main domain:

```bash
DOMAIN="example.com"
```

- No `https://` or `www` prefix.

### `EMAIL`

Contact email for Let's Encrypt:

```bash
EMAIL="admin@example.com"
```

- Use a real address you control — Let's Encrypt sends expiry notices.

## DNS prerequisites

Before running `bash jstack.sh --install`, point your base domain at the
server:

```
example.com   A   <your-server-ip>
```

Each additional site you install via `--install-site` should have its own DNS
record pointing here.

## Other settings

```bash
SSL_COUNTRY="US"
SSL_STATE="Oregon"
SSL_CITY="Portland"
SSL_ORGANIZATION="Organization"
SSL_ORG_UNIT="Development"

NGINX_PORT=443
DRY_RUN=false
BACKUP_ENABLED=true
DEBUG=false
```

Most of these have sensible defaults and rarely need changing.

## Secrets

Site-specific secrets (DB passwords, API keys, etc.) live in
`sites/<domain>/.env`, not in `jstack.config`. They are passed into the site's
containers by its own `docker-compose.yml`.

## Validation

```bash
bash jstack.sh validate
```

Checks for common configuration mistakes.

## Common mistakes

1. **Including protocol in `DOMAIN`** — use `example.com`, not `https://example.com`.
2. **Editing `jstack.config.default`** — that's the template. Edit
   `jstack.config` instead.
3. **DNS missing at install time** — the installer acquires a cert
   immediately. If DNS hasn't propagated, cert acquisition fails (re-run
   later).
