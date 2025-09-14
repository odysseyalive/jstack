# Service Architecture Guide

JStack gives you four powerful services that work together to create your AI Second Brain. Here's what each one does and how to manage them.

## The Four Core Services

### 🤖 n8n - Your Automation Brain
**What it does:** Creates workflows that connect your apps, automate tasks, and process data while you sleep.

**Access:** `https://n8n.yourdomain.com` (replace with your actual domain)
**Default credentials:** Set during installation

**Common use cases:**
- Auto-respond to emails based on keywords
- Sync data between different apps
- Generate reports and send them automatically
- Monitor websites and alert you to changes

**Managing n8n:**
- Check if n8n is running
```bash
./jstack.sh status
```
- Restart n8n if it's acting up
```bash
docker-compose restart n8n
```
- View n8n logs
```bash
docker-compose logs n8n
```

**Data location:** Your workflows are stored in `data/n8n/` - back this up!

### 🗄️ Supabase - Your Database Powerhouse
**What it does:** Stores all your data securely with a built-in admin dashboard and APIs.

**Access:** `https://studio.yourdomain.com` (replace with your actual domain)
**Default credentials:** Set during installation

**What you'll use it for:**
- Store customer data, orders, content
- Create real-time apps and dashboards
- Manage user authentication
- Run SQL queries and view data

**Managing Supabase:**
- Check database status
```bash
./jstack.sh status
```
- Restart Supabase stack
```bash
docker-compose restart supabase-db supabase-kong supabase-auth supabase-rest supabase-realtime supabase-storage supabase-meta
```
- View database logs
```bash
docker-compose logs supabase-db
```

**Data location:** Your database is stored in `data/supabase/` - this is critical to back up!

### 🌐 NGINX - Your Web Traffic Director
**What it does:** Routes web traffic, handles SSL certificates, and serves your websites.

**Access:** Runs automatically in the background
**Config location:** `nginx/conf.d/`

**What it manages:**
- SSL certificates for secure HTTPS
- Domain routing to correct services
- Security headers and rate limiting
- Static file serving

**Managing NGINX:**
- Restart NGINX after config changes
```bash
docker-compose restart nginx
```
- Check NGINX configuration
```bash
docker-compose exec nginx nginx -t
```
- View access logs
```bash
docker-compose logs nginx
```

**Config files:** All your site configs are in `nginx/conf.d/` - customize these for your domains.

### 🕷️ Chrome - Your Web Scraping Engine
**What it does:** Runs a headless Chrome browser for automation, testing, and data extraction.

**Access:** Used by n8n and other services (not directly accessed)
**Port:** Internal container communication

**Common uses:**
- Screenshot websites automatically
- Fill out forms and submit data
- Extract data from web pages
- Test your websites

**Managing Chrome:**
- Restart Chrome service
```bash
docker-compose restart chrome
```
- View Chrome logs
```bash
docker-compose logs chrome
```

**Data location:** Temporary data stored in `data/chrome/`

## Service Dependencies

Understanding how services connect helps with troubleshooting:

```
NGINX (Port 80/443) 
├── Routes to n8n (Port 5678)
├── Routes to Supabase Studio (Port 8000)
└── Routes to your sites

n8n workflows can:
├── Connect to Supabase database
├── Use Chrome for web automation
└── Send data anywhere via webhooks

Supabase provides:
├── Database for n8n workflow data
├── APIs for your sites
└── Real-time data sync
```

## Quick Health Checks

- Check all services at once
```bash
./jstack.sh status
```
- Check specific service status
```bash
docker-compose ps
```
- View logs for specific service
```bash
docker-compose logs [service-name]
```
- Restart everything if something's broken
```bash
./jstack.sh restart
```

## Service URLs Cheat Sheet
Replace `yourdomain.com` with your actual domain:
- n8n Workflows: `https://n8n.yourdomain.com`
- Supabase Studio: `https://studio.yourdomain.com`
- Your Main Site: `https://yourdomain.com`
- API Endpoints: `https://api.yourdomain.com`

## Next Steps
- New to automation? Start with simple n8n workflows
- Need a database? Explore Supabase's built-in table editor
- Want to add sites? Check out [site-templates.md](site-templates.md)
- Having issues? See [troubleshooting.md](troubleshooting.md)

Your services are now working 24/7. Focus on building workflows and managing data—JStack handles the infrastructure.