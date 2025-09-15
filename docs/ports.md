# JStack Port Allocation

## Core Services (Reserved Ports)

| Service | External Port | Internal Port | Purpose |
|---------|---------------|---------------|---------|
| nginx | 80 | 8080 | HTTP (ACME challenges, redirects) |
| nginx | 443 | 8443 | HTTPS (main SSL proxy) |
| n8n | 5678 | 5678 | n8n workflow automation |
| supabase-db | 5432 | 5432 | PostgreSQL database |
| supabase-studio | 3001 | 3000 | Supabase Studio dashboard |
| supabase-kong | 8000 | 8000 | API Gateway (HTTP) |
| supabase-kong | 8001 | 8443 | API Gateway (HTTPS) |
| chrome | 3000 | 3000 | Browserless Chrome |

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

**Avoid these occupied ports:**
- 80, 443 (nginx proxy)
- 3000, 3001 (supabase-studio, chrome)
- 5432, 5678 (database, n8n)
- 8000, 8001 (supabase-kong)
- 8080, 8443 (nginx internal)

## Usage with --install-site

```bash
# Your site's .env file:
DOMAIN=mysite.example.com
PORT=4003                    # Choose an available port
CONTAINER=mysite_app         # Optional for Docker networking
```