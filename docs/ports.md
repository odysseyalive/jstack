# jstack Port Allocation

## Core Services (Reserved Ports)

| Service | External Port | Internal Port | Purpose |
|---------|---------------|---------------|---------|
| nginx | 80 | 80 | HTTP (ACME challenges, redirects) |
| nginx | 443 | 443 | HTTPS (main SSL proxy) |

## Site Template Ports

| Template | Port | Purpose |
|----------|------|---------|
| node-mdx-tailwind | 4000 | Node.js with MDX and Tailwind |
| basic-landing | 4001 | Static HTML landing page |
| lamp-mariadb | 4002 | LAMP stack with MariaDB |

## Available Ports for Custom Sites

**Recommended ranges:**
- **4003-4999**: Static sites and simple web servers
- **6000-6999**: Node.js applications
- **7000-7999**: Python/Flask/Django applications
- **9000-9999**: Other custom applications

**Avoid:**
- 80, 443 (nginx)

Anything else is fair game — but check `docker-compose.override.yml` and any
existing `sites/*/docker-compose.yml` files before claiming a port.

## Usage with --install-site

```bash
# Your site's .env file:
DOMAIN=mysite.example.com
PORT=4003                    # Choose an available port
CONTAINER=mysite_app         # Optional for Docker networking
```
