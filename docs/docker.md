# Docker & Containers Guide

JStack uses Docker to package each service in its own container. Think of containers like separate apartments in a building—each service has its own space but they can communicate when needed.

## Why Docker?

**No conflicts:** Each service runs in isolation with its own dependencies
**Easy updates:** Update one service without breaking others
**Consistent environment:** Works the same on any Debian 12 server
**Simple backup:** All your data is in organized folders

## Understanding Your Containers

### What's Running
```bash
# See all containers and their status
docker-compose ps

# See resource usage
docker stats

# See which ports are exposed
docker-compose port [service-name]
```

### Container Names in JStack
- `jstack-nginx` - Web server and reverse proxy
- `jstack-n8n` - Automation workflows
- `jstack-supabase-db` - PostgreSQL database
- `jstack-supabase-*` - Supabase microservices
- `jstack-chrome` - Headless browser

## Essential Docker Commands

### Starting and Stopping
```bash
# Start all services
./jstack.sh up
# OR
docker-compose up -d

# Stop all services
./jstack.sh down
# OR
docker-compose down

# Restart specific service
docker-compose restart nginx
```

### Checking Logs
```bash
# View logs for all services
docker-compose logs

# View logs for specific service
docker-compose logs n8n

# Follow logs in real-time
docker-compose logs -f supabase-db

# View last 50 lines
docker-compose logs --tail=50 nginx
```

### Getting Into Containers
```bash
# Open shell in NGINX container
docker-compose exec nginx /bin/bash

# Run one-off command in container
docker-compose exec supabase-db psql -U postgres

# Check NGINX configuration
docker-compose exec nginx nginx -t
```

## Data Persistence - Where Your Stuff Lives

JStack maps container data to your workspace so nothing gets lost:

```bash
./data/supabase/     # Database files
./data/n8n/          # Workflow data  
./data/chrome/       # Browser cache/data
./nginx/conf.d/      # Website configs
./nginx/ssl/         # SSL certificates
./logs/              # Application logs
```

**Key insight:** Even if you delete all containers, your data stays safe in these folders.

## Container Lifecycle Management

### Updating Services
```bash
# Pull latest images
docker-compose pull

# Recreate containers with new images
docker-compose up -d --force-recreate
```

### Rebuilding After Changes
```bash
# Rebuild and restart everything
docker-compose down
docker-compose up -d --build
```

### Cleaning Up
```bash
# Remove stopped containers
docker container prune

# Remove unused images (frees disk space)
docker image prune

# Remove unused volumes (be careful!)
docker volume prune
```

## Network Communication

Containers talk to each other using internal networks:

```bash
# View networks
docker network ls

# Inspect JStack network
docker network inspect jstack_default
```

**Internal hostnames:**
- `nginx` - Web server
- `n8n` - Automation service
- `supabase-db` - Database
- `chrome` - Browser service

This means n8n can connect to the database using `supabase-db:5432` instead of external IPs.

## Resource Management

### Monitor Resource Usage
```bash
# Real-time stats
docker stats

# Container details
docker-compose top
```

### Limit Resources (if needed)
Edit `docker-compose.yml` to add limits:
```yaml
services:
  n8n:
    deploy:
      resources:
        limits:
          memory: 512M
          cpus: '0.5'
```

## Troubleshooting Docker Issues

### Container Won't Start
```bash
# Check what's wrong
docker-compose logs [service-name]

# Check if ports are already used
netstat -tlnp | grep :80
netstat -tlnp | grep :443
```

### Permission Issues
```bash
# Fix workspace permissions
./scripts/core/fix_workspace_permissions.sh

# Check file ownership
ls -la data/
```

### Out of Disk Space
```bash
# See disk usage
df -h

# Clean up Docker
docker system prune -a
```

### Database Connection Issues
```bash
# Check if database is accepting connections
docker-compose exec supabase-db pg_isready

# Connect to database directly
docker-compose exec supabase-db psql -U postgres
```

## Docker Compose Commands Cheat Sheet

```bash
# Start services in background
docker-compose up -d

# Stop and remove containers
docker-compose down

# View service status
docker-compose ps

# Follow logs for all services
docker-compose logs -f

# Restart specific service
docker-compose restart [service]

# Rebuild service from scratch
docker-compose up -d --build [service]

# Scale service (run multiple instances)
docker-compose up -d --scale n8n=2
```

## Security Best Practices

**Rootless containers:** JStack services run as non-root users where possible
**Network isolation:** Containers only expose necessary ports
**Volume mounting:** Only specific directories are accessible
**No privileged mode:** Containers can't access host system features

## Backup Strategy

Your containers are disposable—your data isn't:
1. **Regular backups:** Use `./jstack.sh --backup`
2. **Data folders:** Copy `data/`, `nginx/`, `logs/` directories
3. **Docker configs:** Keep `docker-compose.yml` and `.env` files safe

## Advanced Tips

### Custom Environment Variables
Create `.env` file in project root:
```bash
N8N_BASIC_AUTH_USER=yourusername
N8N_BASIC_AUTH_PASSWORD=yourpassword
SUPABASE_USER=dbuser
SUPABASE_PASSWORD=dbpassword
```

### Adding New Services
Edit `docker-compose.yml` to add services:
```yaml
services:
  your-app:
    image: your-app:latest
    ports:
      - "3000:3000"
    volumes:
      - "./data/your-app:/app/data"
```

### Health Checks
Services have built-in health checks. Check status:
```bash
docker-compose ps
# Look for "healthy" status
```

Remember: Containers are temporary, data is permanent. Focus on managing your data, and let Docker handle the infrastructure.