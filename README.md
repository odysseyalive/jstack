# 🧠 JStack - AI Second Brain Infrastructure

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Docker](https://img.shields.io/badge/docker-%230db7ed.svg?style=flat&logo=docker&logoColor=white)](https://www.docker.com/)
[![Debian](https://img.shields.io/badge/Debian-D70A53?style=flat&logo=debian&logoColor=white)](https://www.debian.org/)
[![NGINX](https://img.shields.io/badge/nginx-%23009639.svg?style=flat&logo=nginx&logoColor=white)](https://nginx.org/)

> **Transform your business with AI automation that works while you sleep. Get your complete AI Second Brain running in 15 minutes.**

## What is JStack?

JStack is your AI Second Brain—a modular Bash-driven system for deploying and managing web services, automations, and sites on Debian 12 using Docker and NGINX. It’s designed to save you time, automate repetitive tasks, and give you full control over your infrastructure and data. If you’re tired of manual server setup, endless config headaches, and worrying about security, JStack is here to make your life easier. You get a complete, production-ready stack in minutes, not hours.

JStack is built for real-world business owners, developers, and automation enthusiasts. You don’t need to be a DevOps expert—just follow the steps, and let JStack handle the heavy lifting. Your data stays yours, your workflows run 24/7, and you can focus on what matters.

## 🚀 Quick Start

Ready to get started? Check out [docs/quickstart.md](docs/quickstart.md) for a step-by-step guide. You’ll be up and running in 15 minutes or less. All you need is a Debian 12 server, a domain name, and sudo access.

## Features

- One-command install: Docker, Docker Compose, NGINX, Certbot (SSL), and Fail2ban
- Modular service management: n8n, Supabase, NGINX, Chrome/Puppeteer, site templates
- Secure by default: environment-based secrets, production configs, firewall, SSL, fail2ban, rootless containers
- Dry-run mode: preview every action before you commit
- Diagnostics, compliance, backup/restore, multi-site support
- Site template lifecycle management and rapid deployment
- Integrated config validation and propagation
- Health monitoring, logging, and automatic restarts

## Usage

### Standard Installation (Recommended for Most Users)

1. **Create a dedicated jarvis user and add it to the docker group (run as root):**

 ```bash
 adduser jarvis
 ```

2. **Add your user to the docker group:**

 ```bash
 usermod -aG docker jarvis
 ```

3. **Switch to your jarvis user (login shell):**

 ```bash
 su - jarvis
 ```

4. **Clone the repository:**

 ```bash
 git clone https://github.com/odysseyalive/jstack.git
 ```

5. **Navigate to the directory:**

 ```bash
 cd jstack
 ```

6. **Refresh sudo credentials:**

 ```bash
 sudo -v
 ```

7. **Install and configure the full stack:**

 ```bash
 ./jstack.sh --install
 ```

### Service Management

**Start/stop services:**

```bash
./jstack.sh up
./jstack.sh down
./jstack.sh restart
./jstack.sh status
```

### Diagnostics & Validation

**Run diagnostics and compliance checks:**

```bash
./jstack.sh diagnostics <service>
./jstack.sh compliance <service>
./jstack.sh validate
```

**Validate setup before making changes:**

```bash
./jstack.sh --dry-run
```

### Advanced Site Deployment (For Power Users)

Want to deploy a custom site from a template? Copy a template to `sites/your-site`, edit the config, and run:

```bash
./jstack.sh --install-site sites/your-site
```

This is for advanced users who want to go beyond the default stack and launch custom web apps or landing pages.

## Documentation

New to JStack? These guides will help you understand each component:

- **[Quickstart Guide](docs/quickstart.md)** - Step-by-step installation walkthrough
- **[Service Architecture](docs/services.md)** - Understanding n8n, Supabase, NGINX, and Chrome
- **[Docker & Containers](docs/docker.md)** - How JStack uses Docker for isolation and management
- **[SSL & Security](docs/security.md)** - Certificates, fail2ban, and security best practices
- **[Site Templates](docs/site-templates.md)** - Creating and deploying custom sites
- **[Backup & Recovery](docs/backup.md)** - Data protection and disaster recovery
- **[Troubleshooting](docs/troubleshooting.md)** - Common issues and solutions

## Security & Operations

- SSL certificates via Certbot (Let's Encrypt) for all domains
- NGINX reverse proxy with security headers and rate limiting
- Fail2ban for SSH and NGINX protection
- Automated backups and restore
- Health checks and compliance validation
- Rootless containers and network isolation

## Troubleshooting & Support

If you hit a snag, don’t panic. Check logs in the `logs/` directory:

```bash
cat logs/install.log
```

Validate your setup:

```bash
./jstack.sh --dry-run
```

Restart services:

```bash
./jstack.sh --restart-services
```

For template issues, make sure `.env` and `docker-compose.yml` are present and correct in your site directory.

Need help? Open a [GitHub Issue](https://github.com/odysseyalive/jstack/issues) or join the [AI Productivity Hub](https://www.skool.com/ai-productivity-hub) community.

## Advanced & Customization

JStack is built to be extended. Add new site templates in `site-templates/`, customize your config in `jstack.config.default`, and extend scripts in `scripts/core/` and `scripts/services/` to fit your needs. Power users can automate anything—from landing pages to full SaaS apps.

## Workspace Directory Structure & Volume Mapping

All service data, configs, logs, and SSL certs are mapped to your working directory for easy access, backup, and portability. No system directories are used—everything is managed in your workspace.

```
/home/francis/lab/jstack/
├── data/
│   ├── supabase/        # Supabase Postgres data
│   ├── n8n/             # n8n workflow data
│   └── chrome/          # Chrome/Puppeteer data
├── nginx/
│   ├── conf.d/          # NGINX site configs
│   ├── nginx.conf       # Main NGINX config
│   └── ssl/             # SSL certs (Certbot)
├── site-templates/      # Site template sources
├── sites/               # Deployed custom sites
├── backups/             # Automated backups
├── logs/                # Install and service logs
├── scripts/core/        # Core automation scripts
├── scripts/services/    # Service lifecycle scripts
├── jstack.config.default# User config
├── docker-compose.yml   # Service orchestration
└── ...
```

### Docker Volume Mapping

- Supabase: `./data/supabase:/var/lib/postgresql/data`
- n8n: `./data/n8n:/home/node/.n8n`
- Chrome: `./data/chrome:/data`
- NGINX: `./nginx/conf.d:/etc/nginx/conf.d`, `./nginx/nginx.conf:/etc/nginx/nginx.conf:ro`, `./nginx/ssl:/etc/letsencrypt`
- Site templates: `./site-templates:/usr/share/nginx/html:ro`

### Permission Requirements

- All workspace files are owned by the deploying user and in the `docker` group.
- Run `scripts/core/fix_workspace_permissions.sh` after install/restore to fix any permission issues.
- Containers run as non-root where possible for security.

### Backup & Restore

- All backups are stored in `backups/` and include only workspace-mapped data.
- Restore by extracting backup files into your workspace and running permission fix script.

### Troubleshooting

- If a service cannot access its data/config, check directory ownership and permissions.
- Use `cat logs/install.log` for install and error logs.
- For permission issues, run:

  ```bash
  ./scripts/core/fix_workspace_permissions.sh
  ```

### References

- [Docker Volumes](https://docs.docker.com/storage/volumes/)
- [NGINX Config](https://nginx.org/en/docs/)
- [Certbot with Docker](https://certbot.eff.org/instructions)

## License

MIT — Commercial use, modification, and distribution permitted. No strings attached.

