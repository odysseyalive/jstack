# jstack.sh --install Process Documentation

## 1. System Requirements Validation
- **Script**: `validate_system_requirements.sh`
  - Checks Node.js version (≥ 18.0.0)
  - Verifies Docker daemon is running via `docker info`
  - Confirms required ports (80, 443) are available using `lsof -i :80` and `lsof -i :443`
  - Validates OS compatibility (Linux)

## 2. Dependency Installation
- **Script**: `install_dependencies.sh`
  - Executes `npm install` in the project root
  - Validates `package.json` exists and is valid JSON
  - Handles dependency resolution and installation
  - Updates `node_modules` directory
  - Checks for missing dependencies via `npm ls`

## 3. Service Configuration
- **Script**: `configure_dependencies.sh`
  - Sets up Docker networks for services using `docker network create jstack-network`
  - Configures environment variables (e.g., `DB_PASSWORD`, `DB_HOST`)
  - Initializes service containers with correct ports
  - Creates necessary data volumes for persistent storage

## 4. SSL Certificate Setup
- **Script**: `setup_ssl_certbot.sh`
  - Generates Let's Encrypt certificates using Certbot
    - Runs `certbot certonly --nginx -d jstack.example.com`
    - Validates certificate chain with `openssl x509 -in /etc/letsencrypt/live/jstack.example.com/fullchain.pem -noout -text`
  - Configures Nginx to use HTTPS
    - Updates `/etc/nginx/sites-available/jstack.example.com`
    - Runs `nginx -t` to test configuration
  - Validates certificate expiration
    - Checks expiration via `openssl x509 -in /etc/letsencrypt/live/jstack.example.com/fullchain.pem -noout -dates`
  - Updates firewall rules for HTTPS traffic

## 5. Service Subdomain Configuration
- **Script**: `setup_service_subdomains_ssl.sh`
  - Adds DNS entries for service subdomains (e.g., `api.jstack.example`, `admin.jstack.example`)
  - Configures SSL for each subdomain
    - Runs `certbot certonly --nginx -d api.jstack.example`
    - Updates Nginx configuration for each subdomain
  - Updates Nginx configuration for subdomains
    - Creates `/etc/nginx/sites-available/api.jstack.example`
    - Creates `/etc/nginx/sites-available/admin.jstack.example`
  - Tests SSL connectivity for each subdomain
    - Uses `curl -k https://api.jstack.example` to verify

## 6. Post-Install Validation
- **Script**: `post_install_checks.sh`
  - Validates Docker service health status
    - Checks service status via `docker ps --format '{{.Names}}'`
  - Checks SSL certificate validity
    - Runs `openssl x509 -in /etc/letsencrypt/live/jstack.example.com/fullchain.pem -noout -dates`
  - Tests API endpoints for functionality
    - Makes HTTP requests to `/api/health`
  - Confirms all services are running
    - Verifies Docker container statuses

## 7. Service Activation
- **Script**: `service_container.sh`
  - Starts all Docker services
    - Runs `docker-compose up -d`
  - Handles service health checks
    - Uses `docker healthcheck` for each service
  - Ensures services are responsive
    - Checks response times via `curl -sS http://api.jstack.example/health`
  - Logs service startup status
    - Writes to `/var/log/jstack/service_start.log`

## 8. HTTPS Redirect Configuration
- **Script**: `enable_https_redirects.sh`
  - Configures Nginx to redirect HTTP → HTTPS
    - Updates `/etc/nginx/sites-available/jstack.example.com` with `return 301 $scheme://example.com$request_uri;`
  - Validates redirect behavior
    - Tests with `curl -I http://jstack.example.com`
  - Updates firewall rules to allow HTTPS traffic
    - Runs `ufw allow 443/tcp`
  - Tests redirect functionality
    - Verifies `http://jstack.example.com` redirects to `https://jstack.example.com`

## 9. Final Verification
- **Script**: `dry_run_preview.sh`
  - Runs a dry preview of the installation
    - Simulates service startup without actual installation
  - Validates all components are working
    - Checks Docker services, SSL, API endpoints
  - Generates installation summary report
    - Outputs to `/var/log/jstack/install_summary.txt`
  - Outputs success/failure status
    - Prints `Installation successful` or `Installation failed`

> **Security Note**: All scripts follow the project's security and configuration standards from CRUSH.md, including SSL certificate validation, environment variable management, and service isolation.