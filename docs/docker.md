# Docker & Containers Guide

JStack uses Docker to package each service in its own container. Think of containers like separate apartments in a building—each service has its own space but they can communicate when needed.

## Why Docker?

**No conflicts:** Each service runs in isolation with its own dependencies
**Easy updates:** Update one service without breaking others
**Consistent environment:** Works the same on any Debian 12 server
**Simple backup:** All your data is in organized folders

## Understanding Your Containers

### What's Running
- See all containers and their status
```bash
docker-compose ps
```
- See resource usage
```bash
docker stats
```
- See which ports are exposed
```bash
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
- Start all services
```bash
./jstack.sh up
```
- Start all services (docker-compose)
```bash
docker-compose up -d
```
- Stop all services
```bash
./jstack.sh down
```
- Stop all services (docker-compose)
```bash
docker-compose down
```
- Restart specific service
```bash
docker-compose restart nginx
```

### Checking Logs
- View logs for all services
```bash
docker-compose logs
```
- View logs for specific service
```bash
docker-compose logs n8n
```
- Follow logs in real-time
```bash
docker-compose logs -f supabase-db
```
- View last 50 lines
```bash
docker-compose logs --tail=50 nginx
```

### Getting Into Containers
- Open shell in NGINX container
```bash
docker-compose exec nginx /bin/bash
```
- Run one-off command in container
```bash
docker-compose exec supabase-db psql -U postgres
```
- Check NGINX configuration
```bash
docker-compose exec nginx nginx -t
```

## Data Persistence - Where Your Stuff Lives

JStack maps container data to your workspace so nothing gets lost:
```bash
./data/supabase/     # Database files
```
```bash
./data/n8n/          # Workflow data
```
```bash
./data/chrome/       # Browser cache/data
```
```bash
./nginx/conf.d/      # Website configs
```
```bash
./nginx/ssl/         # SSL certificates
```
```bash
./logs/              # Application logs
```

**Key insight:** Even if you delete all containers, your data stays safe in these folders.

## Container Lifecycle Management

### Updating Services
- Pull latest images
```bash
docker-compose pull
```
- Recreate containers with new images
```bash
docker-compose up -d --force-recreate
```

### Rebuilding After Changes
- Rebuild and restart everything
```bash
docker-compose down
```
```bash
docker-compose up -d --build
```

### Cleaning Up
- Remove stopped containers
```bash
docker container prune
```
- Remove unused images (frees disk space)
```bash
docker image prune
```
- Remove unused volumes (be careful!)
```bash
docker volume prune
```

## Network Communication
- View networks
```bash
docker network ls
```
- Inspect JStack network
```bash
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
- Real-time stats
```bash
docker stats
```
- Container details
```bash
docker-compose top
```

### Limit Resources (edit docker-compose.yml)
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
- Check what's wrong
```bash
docker-compose logs [service-name]
```
- Check if ports are already used
```bash
netstat -tlnp | grep :80
```
```bash
netstat -tlnp | grep :443
```

### Permission Issues
- Fix workspace permissions
```bash
./scripts/core/fix_workspace_permissions.sh
```
- Check file ownership
```bash
ls -la data/
```

### Out of Disk Space
- See disk usage
```bash
df -h
```
- Clean up Docker
```bash
docker system prune -a
```

### Database Connection Issues
- Check if database is accepting connections
```bash
docker-compose exec supabase-db pg_isready
```
- Connect to database directly
```bash
docker-compose exec supabase-db psql -U postgres
```

## Docker Compose Commands Cheat Sheet
- Start services in background
```bash
docker-compose up -d
```
- Stop and remove containers
```bash
docker-compose down
```
- View service status
```bash
docker-compose ps
```
- Follow logs for all services
```bash
docker-compose logs -f
```
- Restart specific service
```bash
docker-compose restart [service]
```
- Rebuild service from scratch
```bash
docker-compose up -d --build [service]
```
- Scale service (run multiple instances)
```bash
docker-compose up -d --scale n8n=2
```

## Security Best Practices
- Rootless containers: JStack services run as non-root users where possible
- Network isolation: Containers only expose necessary ports
- Volume mounting: Only specific directories are accessible
- No privileged mode: Containers can't access host system features

## Backup Strategy
- Regular backups
```bash
./jstack.sh --backup
```
- Data folders
```bash
cp -r data/ nginx/ logs/ backups/
```
- Docker configs
```bash
cp docker-compose.yml .env backups/
```

## Advanced Tips
### Custom Environment Variables (create .env in project root)
```bash
N8N_BASIC_AUTH_USER=yourusername
```
```bash
N8N_BASIC_AUTH_PASSWORD=yourpassword
```
```bash
SUPABASE_USER=dbuser
```
```bash
SUPABASE_PASSWORD=dbpassword
```
### Adding New Services (edit docker-compose.yml)
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
- Check status
```bash
docker-compose ps
```
# Look for "healthy" status in output

Remember: Containers are temporary, data is permanent. Focus on managing your data, and let Docker handle the infrastructure.