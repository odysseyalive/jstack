# Next.js Business Template Guide

> Deploy modern React applications with server-side rendering and production optimizations

## Overview

The Next.js Business template provides a production-ready foundation for:
- **Business websites** with dynamic content
- **Web applications** with API integration
- **E-commerce sites** with server-side rendering
- **Marketing sites** with optimal SEO

**Tech Stack**:
- Next.js 14 with App Router
- Node.js 22 Alpine (97% smaller image)
- TypeScript for type safety
- Tailwind CSS for styling
- Production optimizations built-in

---

## Quick Deploy

```bash
# Deploy with defaults:
./jstack.sh --add-site mybusiness.com --template nextjs-business

# Your site will be live at:
# https://mybusiness.com (with SSL automatically configured)
```

**Deploy time**: ~3 minutes

---

## Template Structure

```
templates/nextjs-business/
├── site.json                 # Site configuration
├── docker-compose.yml        # Container orchestration
├── Dockerfile                # Multi-stage build
├── package.json              # Dependencies
├── next.config.js            # Next.js configuration
├── tailwind.config.js        # Tailwind CSS setup
├── tsconfig.json             # TypeScript configuration
├── src/
│   ├── app/                  # App Router (Next.js 13+)
│   │   ├── layout.tsx        # Root layout
│   │   ├── page.tsx          # Home page
│   │   └── api/              # API routes
│   ├── components/           # Reusable React components
│   ├── lib/                  # Utility functions
│   └── styles/               # Global styles
├── public/                   # Static assets
├── docs/                     # Template documentation
└── scripts/                  # Build and deployment scripts
```

---

## Customization Guide

### 1. Basic Configuration (site.json)

Edit the main configuration file:

```json
{
  "domain": "mybusiness.com",
  "template": "nextjs-business",
  "app": {
    "name": "My Business",
    "description": "Professional business website",
    "environment": "production"
  },
  "ssl": {
    "enabled": true,
    "force_https": true
  },
  "resources": {
    "memory_limit": "512m",
    "cpu_limit": "0.5"
  },
  "features": {
    "api_routes": true,
    "static_export": false,
    "image_optimization": true
  }
}
```

### 2. Application Code

**Home Page** (`src/app/page.tsx`):
```tsx
export default function Home() {
  return (
    <main className="min-h-screen bg-white">
      <h1 className="text-4xl font-bold text-center py-20">
        Welcome to My Business
      </h1>
    </main>
  );
}
```

**Layout** (`src/app/layout.tsx`):
```tsx
export const metadata = {
  title: 'My Business',
  description: 'Professional business website',
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}
```

### 3. API Routes

Create API endpoints in `src/app/api/`:

```typescript
// src/app/api/contact/route.ts
export async function POST(request: Request) {
  const data = await request.json();
  
  // Process contact form
  console.log('Contact form:', data);
  
  return Response.json({ success: true });
}
```

### 4. Components

Add reusable components in `src/components/`:

```tsx
// src/components/Header.tsx
export default function Header() {
  return (
    <header className="bg-blue-600 text-white p-4">
      <h1 className="text-2xl font-bold">My Business</h1>
    </header>
  );
}
```

---

## Advanced Configuration

### Environment Variables

Configure environment variables in `docker-compose.yml`:

```yaml
services:
  nextjs-app:
    environment:
      - NODE_ENV=production
      - NEXT_PUBLIC_API_URL=https://api.mybusiness.com
      - DATABASE_URL=${DATABASE_URL}
      - SUPABASE_URL=${SUPABASE_URL}
      - SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}
```

### Database Integration

Connect to JarvisJR's PostgreSQL database:

```typescript
// src/lib/database.ts
import { createClient } from '@supabase/supabase-js';

const supabase = createClient(
  process.env.SUPABASE_URL!,
  process.env.SUPABASE_ANON_KEY!
);

export { supabase };
```

### Custom Build Process

Modify the build process in `Dockerfile`:

```dockerfile
# Multi-stage build for optimal size
FROM node:22-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci --only=production

FROM node:22-alpine AS runner
WORKDIR /app
COPY --from=builder /app/node_modules ./node_modules
COPY . .
RUN npm run build

EXPOSE 3000
CMD ["npm", "start"]
```

---

## Performance Optimizations

### Built-in Optimizations

The template includes:
- **97% image size reduction** with multi-stage builds
- **Static asset optimization** with Next.js Image component
- **Code splitting** with App Router
- **Tree shaking** for minimal bundle size
- **Compression** via NGINX proxy

### Custom Optimizations

**Image Optimization**:
```tsx
import Image from 'next/image';

export default function Hero() {
  return (
    <Image
      src="/hero-image.jpg"
      alt="Hero"
      width={1200}
      height={600}
      priority
      className="w-full h-auto"
    />
  );
}
```

**Dynamic Imports**:
```tsx
import dynamic from 'next/dynamic';

const HeavyComponent = dynamic(() => import('./HeavyComponent'), {
  loading: () => <p>Loading...</p>,
});
```

---

## SEO Configuration

### Metadata API

```tsx
// src/app/about/page.tsx
export const metadata = {
  title: 'About Us - My Business',
  description: 'Learn more about our company and mission',
  keywords: 'business, services, about',
  openGraph: {
    title: 'About Us - My Business',
    description: 'Learn more about our company and mission',
    url: 'https://mybusiness.com/about',
    siteName: 'My Business',
    images: ['/og-image.jpg'],
  },
};
```

### Sitemap Generation

```typescript
// src/app/sitemap.ts
export default function sitemap() {
  return [
    {
      url: 'https://mybusiness.com',
      lastModified: new Date(),
      changeFrequency: 'yearly' as const,
      priority: 1,
    },
    {
      url: 'https://mybusiness.com/about',
      lastModified: new Date(),
      changeFrequency: 'monthly' as const,
      priority: 0.8,
    },
  ];
}
```

---

## Testing and Deployment

### Local Development

```bash
# Copy template locally:
cp -r templates/nextjs-business/ ~/my-business/

# Edit configuration:
cd ~/my-business/
nano site.json

# Test locally with Docker:
docker-compose up --build
```

### Validation

```bash
# Validate template before deployment:
./jstack.sh --validate-template ~/my-business/

# Dry run deployment:
./jstack.sh --add-site mybusiness.com --template ~/my-business/ --dry-run
```

### Production Deployment

```bash
# Deploy to production:
./jstack.sh --add-site mybusiness.com --template ~/my-business/

# Monitor deployment:
docker logs nextjs-mybusiness-com

# Test site:
curl -I https://mybusiness.com
```

---

## Common Use Cases

### Business Website

```tsx
// Professional business landing page
export default function BusinessHome() {
  return (
    <div className="min-h-screen">
      <Hero />
      <Services />
      <About />
      <Contact />
    </div>
  );
}
```

### E-commerce Integration

```tsx
// Product catalog with Supabase
async function getProducts() {
  const { data } = await supabase.from('products').select('*');
  return data;
}

export default async function Products() {
  const products = await getProducts();
  
  return (
    <div className="grid grid-cols-1 md:grid-cols-3 gap-6">
      {products?.map(product => (
        <ProductCard key={product.id} product={product} />
      ))}
    </div>
  );
}
```

### API Integration

```typescript
// Contact form with email integration
export async function POST(request: Request) {
  const { name, email, message } = await request.json();
  
  // Send email via N8N workflow
  await fetch(`${process.env.N8N_WEBHOOK_URL}/contact`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ name, email, message }),
  });
  
  return Response.json({ success: true });
}
```

---

## Troubleshooting

### Common Issues

**Build fails during deployment**:
```bash
# Check build logs:
docker logs nextjs-mybusiness-com

# Common fixes:
# 1. Check package.json for correct dependencies
# 2. Verify TypeScript configuration
# 3. Ensure all imports are correct
```

**Site not loading**:
```bash
# Check container status:
docker ps | grep mybusiness

# Check NGINX configuration:
./jstack.sh --test-nginx mybusiness.com

# View detailed logs:
./jstack.sh --logs --service mybusiness.com
```

**API routes not working**:
- Ensure API routes are in `src/app/api/` directory
- Check route handlers export correct HTTP methods
- Verify CORS configuration if needed

### Performance Issues

```bash
# Check resource usage:
docker stats nextjs-mybusiness-com

# Increase memory limit in site.json:
{
  "resources": {
    "memory_limit": "1g",
    "cpu_limit": "1.0"
  }
}
```

---

## Next Steps

1. **🎨 [Styling Guide](../styling.md)** - Advanced Tailwind CSS patterns
2. **🔒 [Security Best Practices](../../reference/security.md#nextjs-security)** - Secure your Next.js app
3. **📊 [Analytics Setup](../analytics.md)** - Track site performance
4. **🚀 [CI/CD Integration](../../reference/cicd.md)** - Automated deployments
5. **🔄 [Backup Strategy](../backup-recovery.md#nextjs-backups)** - Protect your application

**Need help?** Join the [AI Productivity Hub](https://www.skool.com/ai-productivity-hub) community!