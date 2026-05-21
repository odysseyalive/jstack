# jstack — Server-Side Hosting for Individual Websites

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=flat&logo=docker&logoColor=white)](https://www.docker.com/)
[![Debian](https://img.shields.io/badge/Debian-D70A53?style=flat&logo=debian&logoColor=white)](https://www.debian.org/)
[![NGINX](https://img.shields.io/badge/nginx-%23009639.svg?style=flat&logo=nginx&logoColor=white)](https://nginx.org/)

jstack is a Docker-based hosting stack that turns a single Debian server into
a multi-site host. The whole thing is **nginx + certbot + a deploy workflow
for per-site containers**. Nothing else. No n8n, no Supabase, no headless
Chrome — bring your own services if you want them.

## What you get

- **nginx** reverse proxy on 80/443 with a shared Let's Encrypt cert volume
- **certbot** companion container with automatic renewal
- **fail2ban** + log rotation
- A site-deploy workflow: drop a `docker-compose.yml` under `sites/<domain>/`,
  run one command, get nginx + SSL wired up automatically

That's it.

## Quick start

1. **Prepare the server.** Debian 12, Docker + docker-compose installed, a
   user in the `docker` group. See [docs/quickstart.md](docs/quickstart.md)
   for the full bootstrap.

2. **Clone and configure:**

   ```bash
   git clone https://github.com/odysseyalive/jstack.git
   cd jstack
   cp jstack.config.default jstack.config
   nano jstack.config   # set DOMAIN and EMAIL
   ```

3. **Run the install:**

   ```bash
   bash jstack.sh --install
   ```

   This brings up nginx + certbot, acquires a Let's Encrypt cert for your
   base domain, and sets up fail2ban + log rotation.

4. **Deploy a site.** Drop your site under `sites/<domain>/` with a
   `Dockerfile` and `docker-compose.yml` (see
   [docs/site-templates.md](docs/site-templates.md)). Then:

   ```bash
   bash jstack.sh --install-site sites/<domain>
   ```

   This brings up the container, writes an nginx config, and acquires SSL.

## Operating the stack

```bash
bash jstack.sh up                     # start nginx + certbot
bash jstack.sh down                   # stop everything
bash jstack.sh restart
bash jstack.sh status
bash jstack.sh deploy <site-domain>   # restart a site container after rebuild
```

### Diagnostics and validation

```bash
bash jstack.sh diagnostics <service>
bash jstack.sh compliance <service>
bash jstack.sh validate
bash jstack.sh --dry-run
```

## Layout

```
jstack/
├── docker-compose.yml              # nginx + certbot
├── docker-compose.override.yml     # per-server overrides + site service defs (gitignored)
├── nginx/conf.d/                   # active nginx site configs (mounted into nginx)
├── sites/<domain>/                 # per-site source + Dockerfile + docker-compose.yml
├── site-templates/                 # scaffolds for new sites
├── scripts/
│   ├── core/                       # core install + maintenance scripts
│   └── services/site_template_lifecycle.sh
├── jstack.sh                       # entrypoint
└── jstack.config(.default)         # DOMAIN/EMAIL
```

## Documentation

- **[Quickstart](docs/quickstart.md)** — bootstrap walkthrough
- **[Service architecture](docs/services.md)** — nginx + certbot
- **[Configuration](docs/configuration.md)** — `jstack.config` reference
- **[Docker layout](docs/docker.md)**
- **[SSL & security](docs/security.md)**
- **[Site templates](docs/site-templates.md)**
- **[Backup & recovery](docs/backup.md)**
- **[Troubleshooting](docs/troubleshooting.md)**

## License

MIT.
