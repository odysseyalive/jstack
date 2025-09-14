# LAMP + MariaDB Docker Template

## Environment Setup (SECURITY UPDATE)
- Hardcoded credentials are removed.
- Copy `.env.example` to `.env` before building:

```bash
cp .env.example .env
```
- Edit `.env` with your DBUSER/DBPASS.

## Features
- Apache2 web server
- MariaDB database (requires secrets via environment)
- PHP with MySQL support
- Sample `index.php` uses getenv('DBUSER')/getenv('DBPASS')

## Usage
1. Build with variables (secure usage):
   ```bash
   DBUSER=youruser DBPASS=yoursecurepass docker build -t lamp-mariadb site-templates/lamp-mariadb
   ```
2. Run the container:
   ```bash
   docker run -p 8080:80 -p 3306:3306 --env-file .env lamp-mariadb
   ```
3. Visit [http://localhost:8080](http://localhost:8080) to see the sample page.

## Volumes (recommended)
To persist database and web files, mount volumes:
```bash
docker run -p 8080:80 -p 3306:3306 \
   --env-file .env \
   -v $(pwd)/site-templates/lamp-mariadb/site-root/public_html:/var/www/html \
   -v $(pwd)/data:/var/lib/mysql \
   lamp-mariadb
```

## Customization
- Replace index.php with your own PHP app (use getenv for credentials!)
- Adjust the Dockerfile for PHP extensions/config.

## Security Notes
- Never commit secrets/.env to git!
- Credentials, secrets, and keys are always provided externally at runtime (env or .env file).