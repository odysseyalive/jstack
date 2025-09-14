# Site Templates Guide

JStack includes ready-to-deploy site templates that you can customize and launch in minutes. Here's how to use them and create your own.

## Available Templates

### Basic Landing Page
**Location:** `site-templates/basic-landing/`
**Best for:** Simple marketing pages, coming soon pages, basic company sites

**What's included:**
- Single HTML page with modern styling
- Contact form placeholder
- SEO-optimized structure
- Responsive design

**Deploy it:**
```bash
# Copy template to sites directory
cp -r site-templates/basic-landing sites/my-landing-page

# Edit the content
nano sites/my-landing-page/site-root/public_html/index.html

# Deploy
./jstack.sh --install-site sites/my-landing-page
```

### LAMP with MariaDB
**Location:** `site-templates/lamp-mariadb/`
**Best for:** PHP applications, WordPress, traditional web apps

**What's included:**
- PHP 8.x with Apache
- MariaDB database
- phpMyAdmin for database management
- Sample PHP application

**Deploy it:**
```bash
# Copy template
cp -r site-templates/lamp-mariadb sites/my-php-app

# Configure database
cp sites/my-php-app/.env.example sites/my-php-app/.env
nano sites/my-php-app/.env

# Deploy
./jstack.sh --install-site sites/my-php-app
```

### Node.js with MDX and Tailwind
**Location:** `site-templates/node-mdx-tailwind/`
**Best for:** Modern web apps, blogs, documentation sites, React applications

**What's included:**
- Node.js server with Express
- MDX support for content
- Tailwind CSS for styling
- Hot reloading in development

**Deploy it:**
```bash
# Copy template
cp -r site-templates/node-mdx-tailwind sites/my-node-app

# Install dependencies
cd sites/my-node-app/site-root
npm install

# Configure and deploy
cd ../../..
./jstack.sh --install-site sites/my-node-app
```

## Template Structure

### Understanding Template Layout

Each template follows this structure:
```
site-templates/template-name/
├── site.config              # Site configuration
├── Dockerfile               # Container definition
├── README.md                # Template documentation
├── .env.example            # Environment variables template
└── site-root/              # Your website files
    ├── public_html/        # Web-accessible files
    ├── package.json        # Node.js dependencies (if applicable)
    └── server.js           # Application server (if applicable)
```

### Site Configuration File

The `site.config` file tells JStack how to deploy your site:

```bash
# Example site.config
SITE_NAME="my-awesome-site"
DOMAIN="awesome.yourdomain.com"
PORT="3000"
SSL_ENABLED="true"
CONTAINER_NAME="jstack-awesome-site"
```

**Configuration options:**
- `SITE_NAME`: Internal name for your site
- `DOMAIN`: The domain where site will be accessible
- `PORT`: Internal container port
- `SSL_ENABLED`: Whether to enable HTTPS
- `CONTAINER_NAME`: Docker container name

## Customizing Templates

### Basic Landing Page Customization

**Edit the content:**
```bash
# Main page content
nano sites/my-landing-page/site-root/public_html/index.html

# Update title, description, content
# Add your logo, colors, contact info
```

**Add custom styling:**
```html
<!-- In the <head> section -->
<style>
  .hero { background: linear-gradient(45deg, #your-colors); }
  .cta-button { background: #your-brand-color; }
</style>
```

### LAMP Template Customization

**Database setup:**
```bash
# Configure database credentials
nano sites/my-php-app/.env
```

```env
MYSQL_ROOT_PASSWORD=your-secure-root-password
MYSQL_DATABASE=your_app_database
MYSQL_USER=your_app_user
MYSQL_PASSWORD=your-secure-password
```

**Add PHP application:**
```bash
# Replace sample with your PHP code
rm sites/my-php-app/site-root/public_html/index.php
cp -r /path/to/your/php/app/* sites/my-php-app/site-root/public_html/
```

### Node.js Template Customization

**Install additional packages:**
```bash
cd sites/my-node-app/site-root
npm install express-session passport mongoose
```

**Customize the server:**
```javascript
// Edit server.js
const express = require('express');
const app = express();

// Add your routes
app.get('/api/data', (req, res) => {
  res.json({ message: 'Your API endpoint' });
});

// Your custom middleware
app.use('/admin', require('./routes/admin'));
```

**Add environment variables:**
```bash
# Create .env file
echo "API_KEY=your-api-key" > sites/my-node-app/.env
echo "DATABASE_URL=your-database-url" >> sites/my-node-app/.env
```

## Creating Custom Templates

### Template Creation Steps

1. **Create template directory:**
```bash
mkdir -p site-templates/my-custom-template/site-root/public_html
```

2. **Create site.config:**
```bash
cat > site-templates/my-custom-template/site.config << EOF
SITE_NAME="my-custom-template"
DOMAIN="custom.yourdomain.com"
PORT="8080"
SSL_ENABLED="true"
CONTAINER_NAME="jstack-custom-template"
EOF
```

3. **Create Dockerfile:**
```dockerfile
FROM nginx:alpine

# Copy website files
COPY site-root/public_html /usr/share/nginx/html

# Copy custom nginx config if needed
COPY nginx.conf /etc/nginx/nginx.conf

EXPOSE 80
CMD ["nginx", "-g", "daemon off;"]
```

4. **Add your application:**
```bash
# Add your website files
cp -r /your/app/* site-templates/my-custom-template/site-root/public_html/
```

### Python Flask Template Example

**Create Flask template:**
```bash
mkdir -p site-templates/flask-app/site-root
cd site-templates/flask-app
```

**Create site.config:**
```bash
cat > site.config << EOF
SITE_NAME="flask-app"
DOMAIN="app.yourdomain.com"
PORT="5000"
SSL_ENABLED="true"
CONTAINER_NAME="jstack-flask-app"
EOF
```

**Create Dockerfile:**
```dockerfile
FROM python:3.9-slim

WORKDIR /app
COPY site-root/requirements.txt .
RUN pip install -r requirements.txt

COPY site-root/ .

EXPOSE 5000
CMD ["python", "app.py"]
```

**Create Flask app:**
```python
# site-root/app.py
from flask import Flask, render_template

app = Flask(__name__)

@app.route('/')
def home():
    return render_template('index.html')

@app.route('/api/status')
def status():
    return {'status': 'healthy'}

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000)
```

**Create requirements.txt:**
```
Flask==2.3.3
gunicorn==21.2.0
```

## Site Deployment Process

### Standard Deployment

**Deploy any template:**
```bash
# 1. Copy template to sites directory
cp -r site-templates/template-name sites/my-site

# 2. Customize configuration
nano sites/my-site/site.config

# 3. Edit application files
nano sites/my-site/site-root/...

# 4. Deploy
./jstack.sh --install-site sites/my-site
```

### Advanced Deployment Options

**Deploy with custom domain:**
```bash
# Edit site.config before deployment
echo "DOMAIN=custom.yourdomain.com" > sites/my-site/site.config

# JStack will automatically create NGINX config and SSL
./jstack.sh --install-site sites/my-site
```

**Deploy with environment variables:**
```bash
# Create .env file in site directory
echo "API_KEY=your-secret-key" > sites/my-site/.env
echo "DATABASE_URL=postgresql://..." >> sites/my-site/.env

./jstack.sh --install-site sites/my-site
```

## Managing Deployed Sites

### View Running Sites

**Check site status:**
```bash
# See all running containers
docker-compose ps

# Check specific site
docker-compose logs jstack-my-site

# Check site accessibility
curl -I https://my-site.yourdomain.com
```

### Update Deployed Sites

**Update site content:**
```bash
# Edit files in sites/my-site/site-root/
nano sites/my-site/site-root/public_html/index.html

# Rebuild and redeploy
docker-compose build jstack-my-site
docker-compose up -d jstack-my-site
```

**Update site configuration:**
```bash
# Edit site.config
nano sites/my-site/site.config

# Redeploy
./jstack.sh --install-site sites/my-site
```

### Remove Sites

**Stop and remove site:**
```bash
# Stop site container
docker-compose stop jstack-my-site

# Remove container
docker-compose rm jstack-my-site

# Remove NGINX configuration
rm nginx/conf.d/my-site.yourdomain.com.conf

# Restart NGINX
docker-compose restart nginx
```

## Site Template Best Practices

### Security
- Never commit secrets to template files
- Use environment variables for sensitive data
- Keep templates updated with security patches
- Use non-root users in Dockerfiles when possible

### Performance
- Optimize images and assets
- Use multi-stage Docker builds for smaller images
- Enable gzip compression in NGINX
- Implement proper caching headers

### Maintainability
- Document your templates thoroughly
- Use consistent naming conventions
- Keep templates simple and focused
- Version your custom templates with git

### SEO and Accessibility
- Include proper meta tags
- Use semantic HTML
- Ensure mobile responsiveness
- Add proper alt text for images

## Integration with JStack Services

### Connect to Supabase
```javascript
// In your Node.js application
const { createClient } = require('@supabase/supabase-js');

const supabase = createClient(
  'https://studio.yourdomain.com',
  process.env.SUPABASE_ANON_KEY
);
```

### Use n8n Webhooks
```javascript
// Trigger n8n workflows from your site
const response = await fetch('https://n8n.yourdomain.com/webhook/your-webhook-id', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ formData })
});
```

### Chrome/Puppeteer Integration
```javascript
// Generate PDFs or screenshots
const response = await fetch('https://chrome.yourdomain.com/screenshot', {
  method: 'POST',
  body: JSON.stringify({ url: 'https://your-site.com' })
});
```

Your templates are now ready for production. Focus on building great content—JStack handles the infrastructure.