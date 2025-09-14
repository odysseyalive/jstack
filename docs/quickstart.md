# JStack Quickstart

## Prerequisites
- Debian 12 system
- Docker and Docker Compose installed
- NGINX installed and running

## Project Setup
1. Clone the repository and enter the project directory:
   ```bash
   git clone <repo-url>
   cd jstack
   ```
2. Review and edit `jstack.config.default` for your environment.
3. Copy a site template from `site-templates/` to `sites/your-site`, customize `.env` and `docker-compose.yml`.

## Usage
- Install a new site:
  ```bash
  ./jstack.sh --install-site sites/your-site
  ```
- Start all services:
  ```bash
  ./jstack.sh up
  ```
- Stop all services:
  ```bash
  ./jstack.sh down
  ```
- Run diagnostics:
  ```bash
  ./jstack.sh diagnostics <service>
  ```
- Run compliance checks:
  ```bash
  ./jstack.sh compliance <service>
  ```
- Validate config:
  ```bash
  ./jstack.sh validate
  ```
- Dry-run mode:
  ```bash
  ./jstack.sh --dry-run up
  ```

## Troubleshooting
- Check logs in the `logs/` directory.
- Ensure Docker and NGINX are running and you have permissions.
- For issues with site templates, verify `.env` and `docker-compose.yml` are present and correct.

## Documentation
- See `README.md` for full details and advanced usage.
