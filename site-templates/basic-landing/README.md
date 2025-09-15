# Basic Landing Page Template

A simple static HTML landing page template using nginx.

## Usage

1. Copy this template to your site directory:
   ```bash
   cp -r site-templates/basic-landing my-landing-site
   cd my-landing-site
   ```

2. Configure your site:
   ```bash
   cp .env.example .env
   # Edit .env with your domain and settings
   ```

3. Customize the content:
   - Edit `site-root/public_html/index.html`
   - Add your own styles and content

4. Deploy with JStack:
   ```bash
   ./jstack.sh --install-site ./my-landing-site/
   ```

## Features

- ✅ Static HTML served by nginx
- ✅ Responsive design
- ✅ Clean, professional layout
- ✅ Easy to customize
- ✅ Production-ready SSL via JStack

## Files

- `docker-compose.yml` - Container configuration
- `.env.example` - Environment variables template
- `site-root/public_html/` - Your website files
- `site.config` - JStack template configuration