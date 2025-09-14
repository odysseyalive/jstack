# Site Templates Guide

JStack includes ready-to-deploy site templates you can customize and launch in minutes. Here’s how to use them and create your own.

## Available Templates

### Basic Landing Page
- Copy template
```bash
cp -r site-templates/basic-landing sites/my-landing-page
```
- Edit content
```bash
nano sites/my-landing-page/site-root/public_html/index.html
```
- Deploy site
```bash
./jstack.sh --install-site sites/my-landing-page
```

### LAMP with MariaDB
- Copy template
```bash
cp -r site-templates/lamp-mariadb sites/my-php-app
```
- Configure database
```bash
cp sites/my-php-app/.env.example sites/my-php-app/.env
```
```bash
nano sites/my-php-app/.env
```
- Deploy site
```bash
./jstack.sh --install-site sites/my-php-app
```

### Node.js with MDX and Tailwind
- Copy template
```bash
cp -r site-templates/node-mdx-tailwind sites/my-node-app
```
- Install dependencies
```bash
cd sites/my-node-app/site-root
```
```bash
npm install
```
- Configure and deploy
```bash
cd ../../..
```
```bash
./jstack.sh --install-site sites/my-node-app
```

## Customizing Templates

### Basic Landing Page
- Edit content
```bash
nano sites/my-landing-page/site-root/public_html/index.html
```
### LAMP Template
- Configure database credentials
```bash
nano sites/my-php-app/.env
```
### Node.js Template
- Install additional packages
```bash
cd sites/my-node-app/site-root
```
```bash
npm install express-session passport mongoose
```

- Create .env file
```bash
echo "API_KEY=your-api-key" > sites/my-node-app/.env
```
```bash
echo "DATABASE_URL=your-database-url" >> sites/my-node-app/.env
```

## Creating Custom Templates
- Create template directory
```bash
mkdir -p site-templates/my-custom-template/site-root/public_html
```
- Create site.config
```bash
cat > site-templates/my-custom-template/site.config << EOF
SITE_NAME="my-custom-template"
DOMAIN="custom.yourdomain.com"
PORT="8080"
SSL_ENABLED="true"
CONTAINER_NAME="jstack-custom-template"
EOF
```
- Add your application files
```bash
cp -r /your/app/* site-templates/my-custom-template/site-root/public_html/
```

## Site Deployment Process
- Copy template to sites directory
```bash
cp -r site-templates/template-name sites/my-site
```
- Customize configuration
```bash
nano sites/my-site/site.config
```
- Edit application files
```bash
nano sites/my-site/site-root/...
```
- Deploy
```bash
./jstack.sh --install-site sites/my-site
```

## Managing Deployed Sites
- See all running containers
```bash
docker-compose ps
```
- Site logs
```bash
docker-compose logs jstack-my-site
```
- Check accessibility
```bash
curl -I https://my-site.yourdomain.com
```
- Update site content/files
```bash
nano sites/my-site/site-root/public_html/index.html
```
- Rebuild and redeploy
```bash
docker-compose build jstack-my-site
```
```bash
docker-compose up -d jstack-my-site
```
- Remove site container
```bash
docker-compose stop jstack-my-site
```
```bash
docker-compose rm jstack-my-site
```
- Remove NGINX config
```bash
rm nginx/conf.d/my-site.yourdomain.com.conf
```
- Restart NGINX
```bash
docker-compose restart nginx
```

## Best Practices
- Use environment variables for sensitive data
- Keep templates updated
- Use non-root users in Dockerfiles
- Optimize images, assets, and caching
- Document your templates
- Test thoroughly in dev before deploying to production