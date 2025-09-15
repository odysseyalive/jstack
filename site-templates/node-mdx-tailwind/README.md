# Node.js + MDX + Tailwind Template

A modern Node.js web application template with Express server, ready for MDX and Tailwind CSS.

## Usage

1. Copy this template to your site directory:
   ```bash
   cp -r site-templates/node-mdx-tailwind my-node-app
   cd my-node-app
   ```

2. Configure your site:
   ```bash
   cp .env.example .env
   # Edit .env with your domain and settings
   ```

3. Customize your application:
   - Edit `site-root/server.js` for backend logic
   - Edit `site-root/public/index.html` for frontend
   - Add dependencies to `site-root/package.json`

4. Deploy with JStack:
   ```bash
   ./jstack.sh --install-site ./my-node-app/
   ```

## Features

- ✅ Node.js 18 with Express server
- ✅ Static file serving from `/public`
- ✅ Dynamic port configuration
- ✅ Docker containerized
- ✅ Production-ready SSL via JStack
- ✅ Ready for MDX and Tailwind CSS integration

## Development

- Server entry: `site-root/server.js`
- Static files: `site-root/public/`
- Dependencies: `site-root/package.json`

## Container Details

- **Base image**: `node:18-alpine`
- **Port**: 4000 (configurable via PORT env var)
- **Working directory**: `/app`
- **Volume mount**: `./site-root:/app`