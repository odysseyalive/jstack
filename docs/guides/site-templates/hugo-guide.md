# Hugo Portfolio Template Guide

> Deploy lightning-fast static sites with Hugo and Tailwind CSS

## Overview

The Hugo Portfolio template provides a blazing-fast foundation for:
- **Personal portfolios** showcasing your work
- **Blogs** with rich content and SEO optimization
- **Documentation sites** with clear navigation
- **Marketing sites** with optimal performance

**Tech Stack**:
- Hugo static site generator (latest)
- Tailwind CSS for styling
- HugoMods Docker images
- Markdown content management
- CDN-optimized output

---

## Quick Deploy

```bash
# Deploy with defaults:
./jstack.sh --add-site myportfolio.com --template hugo-portfolio

# Your site will be live at:
# https://myportfolio.com (with SSL automatically configured)
```

**Deploy time**: ~2 minutes ⚡

---

## Template Structure

```
templates/hugo-portfolio/
├── site.json                 # Site configuration
├── docker-compose.yml        # Hugo build container
├── config.toml               # Hugo configuration
├── content/                  # Markdown content
│   ├── _index.md            # Home page content
│   ├── about.md             # About page
│   ├── posts/               # Blog posts
│   └── portfolio/           # Portfolio items
├── layouts/                  # HTML templates
│   ├── _default/            # Default layouts
│   ├── partials/            # Reusable components
│   └── shortcodes/          # Custom shortcodes
├── static/                   # Static assets
│   ├── images/              # Images and media
│   ├── css/                 # Additional styles
│   └── js/                  # JavaScript files
├── themes/                   # Hugo theme
├── assets/                   # Source assets (processed by Hugo)
├── data/                     # Data files (YAML, JSON)
└── docs/                     # Template documentation
```

---

## Customization Guide

### 1. Basic Configuration (site.json)

```json
{
  "domain": "myportfolio.com",
  "template": "hugo-portfolio",
  "site": {
    "title": "My Portfolio",
    "description": "Personal portfolio and blog",
    "author": "Your Name"
  },
  "build": {
    "environment": "production",
    "minify": true,
    "cache_bust": true
  },
  "features": {
    "blog": true,
    "portfolio": true,
    "contact_form": true
  }
}
```

### 2. Hugo Configuration (config.toml)

```toml
baseURL = "https://myportfolio.com"
languageCode = "en-us"
title = "My Portfolio"
theme = "portfolio-theme"

[params]
  author = "Your Name"
  description = "Personal portfolio and blog"
  email = "hello@myportfolio.com"
  github = "yourusername"
  linkedin = "yourprofile"

[markup]
  [markup.goldmark]
    [markup.goldmark.renderer]
      unsafe = true

[menu]
  [[menu.main]]
    name = "Home"
    url = "/"
    weight = 1
  [[menu.main]]
    name = "About"
    url = "/about/"
    weight = 2
  [[menu.main]]
    name = "Portfolio"
    url = "/portfolio/"
    weight = 3
  [[menu.main]]
    name = "Blog"
    url = "/posts/"
    weight = 4
```

### 3. Content Management

**Home Page** (`content/_index.md`):
```markdown
---
title: "Welcome to My Portfolio"
description: "I'm a web developer passionate about creating amazing experiences"
---

# Hi, I'm [Your Name] 👋

I'm a web developer passionate about creating amazing digital experiences.

## What I Do

- Frontend Development
- Backend APIs
- UI/UX Design
- Performance Optimization

[View My Work](/portfolio/) | [Read My Blog](/posts/)
```

**About Page** (`content/about.md`):
```markdown
---
title: "About Me"
description: "Learn more about my background and experience"
---

# About Me

I'm a passionate web developer with 5+ years of experience...

## Skills

- **Frontend**: React, Vue.js, TypeScript
- **Backend**: Node.js, Python, Go
- **Database**: PostgreSQL, MongoDB
- **Tools**: Docker, Git, CI/CD
```

**Blog Posts** (`content/posts/my-first-post.md`):
```markdown
---
title: "My First Blog Post"
date: 2024-01-15
draft: false
tags: ["web development", "hugo"]
categories: ["blog"]
image: "/images/post-1.jpg"
---

This is my first blog post using Hugo...

<!-- more -->

## Introduction

Hugo is an amazing static site generator...
```

**Portfolio Items** (`content/portfolio/project-1.md`):
```markdown
---
title: "E-commerce Platform"
date: 2024-01-10
draft: false
technologies: ["React", "Node.js", "PostgreSQL"]
github: "https://github.com/username/project"
demo: "https://project-demo.com"
image: "/images/projects/ecommerce.jpg"
featured: true
---

A full-stack e-commerce platform built with modern technologies...

## Features

- User authentication
- Product catalog
- Shopping cart
- Payment integration
```

---

## Tailwind CSS Integration

### Setup

The template includes native Tailwind CSS integration:

```toml
# config.toml
[build]
  writeStats = true
  
[[module.mounts]]
  source = "assets"
  target = "assets"

[[module.mounts]]
  source = "node_modules/tailwindcss"
  target = "assets/css/tailwindcss"
```

### Custom Styles

**Main stylesheet** (`assets/css/main.css`):
```css
@tailwind base;
@tailwind components;
@tailwind utilities;

@layer base {
  body {
    @apply font-sans text-gray-900;
  }
  
  h1, h2, h3, h4, h5, h6 {
    @apply font-bold text-gray-900;
  }
}

@layer components {
  .btn {
    @apply px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 transition-colors;
  }
  
  .card {
    @apply bg-white rounded-lg shadow-md p-6 hover:shadow-lg transition-shadow;
  }
}
```

### Tailwind Configuration (`tailwind.config.js`):
```javascript
module.exports = {
  content: [
    './content/**/*.{html,js,md}',
    './layouts/**/*.html',
    './themes/**/layouts/**/*.html',
  ],
  theme: {
    extend: {
      colors: {
        primary: {
          50: '#eff6ff',
          500: '#3b82f6',
          900: '#1e3a8a',
        }
      },
      fontFamily: {
        'sans': ['Inter', 'system-ui', 'sans-serif'],
      }
    },
  },
  plugins: [
    require('@tailwindcss/typography'),
    require('@tailwindcss/forms'),
  ],
}
```

---

## Layout Templates

### Base Layout (`layouts/_default/baseof.html`)

```html
<!DOCTYPE html>
<html lang="{{ .Site.Language.Lang }}">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{{ if .Title }}{{ .Title }} - {{ end }}{{ .Site.Title }}</title>
  <meta name="description" content="{{ .Description | default .Site.Params.description }}">
  
  {{ $styles := resources.Get "css/main.css" | postCSS | minify | fingerprint }}
  <link rel="stylesheet" href="{{ $styles.Permalink }}">
</head>
<body class="min-h-screen bg-gray-50">
  {{ partial "header.html" . }}
  
  <main class="container mx-auto px-4 py-8">
    {{ block "main" . }}{{ end }}
  </main>
  
  {{ partial "footer.html" . }}
</body>
</html>
```

### Header Partial (`layouts/partials/header.html`)

```html
<header class="bg-white shadow-sm">
  <nav class="container mx-auto px-4 py-6">
    <div class="flex justify-between items-center">
      <a href="/" class="text-2xl font-bold text-gray-900">
        {{ .Site.Title }}
      </a>
      
      <div class="hidden md:flex space-x-8">
        {{ range .Site.Menus.main }}
          <a href="{{ .URL }}" class="text-gray-600 hover:text-gray-900 transition-colors">
            {{ .Name }}
          </a>
        {{ end }}
      </div>
      
      <!-- Mobile menu button -->
      <button class="md:hidden" onclick="toggleMobileMenu()">
        <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 6h16M4 12h16M4 18h16"></path>
        </svg>
      </button>
    </div>
  </nav>
</header>
```

### Portfolio List (`layouts/portfolio/list.html`)

```html
{{ define "main" }}
<div class="max-w-6xl mx-auto">
  <h1 class="text-4xl font-bold mb-8">{{ .Title }}</h1>
  
  <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-8">
    {{ range .Pages }}
      <div class="card group">
        {{ if .Params.image }}
          <img src="{{ .Params.image }}" alt="{{ .Title }}" class="w-full h-48 object-cover rounded-t-lg">
        {{ end }}
        
        <div class="p-6">
          <h2 class="text-xl font-bold mb-2">{{ .Title }}</h2>
          <p class="text-gray-600 mb-4">{{ .Summary }}</p>
          
          {{ if .Params.technologies }}
            <div class="flex flex-wrap gap-2 mb-4">
              {{ range .Params.technologies }}
                <span class="px-2 py-1 bg-blue-100 text-blue-800 text-sm rounded">{{ . }}</span>
              {{ end }}
            </div>
          {{ end }}
          
          <div class="flex gap-4">
            {{ if .Params.demo }}
              <a href="{{ .Params.demo }}" class="btn btn-sm">Live Demo</a>
            {{ end }}
            {{ if .Params.github }}
              <a href="{{ .Params.github }}" class="btn btn-outline btn-sm">GitHub</a>
            {{ end }}
          </div>
        </div>
      </div>
    {{ end }}
  </div>
</div>
{{ end }}
```

---

## Advanced Features

### Contact Form Integration

```html
<!-- layouts/partials/contact-form.html -->
<form action="https://n8n.{{ .Site.BaseURL }}/webhook/contact" method="POST" class="space-y-6">
  <div>
    <label for="name" class="block text-sm font-medium text-gray-700">Name</label>
    <input type="text" id="name" name="name" required class="mt-1 block w-full rounded-md border-gray-300 shadow-sm">
  </div>
  
  <div>
    <label for="email" class="block text-sm font-medium text-gray-700">Email</label>
    <input type="email" id="email" name="email" required class="mt-1 block w-full rounded-md border-gray-300 shadow-sm">
  </div>
  
  <div>
    <label for="message" class="block text-sm font-medium text-gray-700">Message</label>
    <textarea id="message" name="message" rows="4" required class="mt-1 block w-full rounded-md border-gray-300 shadow-sm"></textarea>
  </div>
  
  <button type="submit" class="btn">Send Message</button>
</form>
```

### Search Functionality

```javascript
// static/js/search.js
document.addEventListener('DOMContentLoaded', function() {
  fetch('/index.json')
    .then(response => response.json())
    .then(data => {
      const searchInput = document.getElementById('search');
      const searchResults = document.getElementById('search-results');
      
      searchInput.addEventListener('input', function(e) {
        const query = e.target.value.toLowerCase();
        const results = data.filter(item => 
          item.title.toLowerCase().includes(query) ||
          item.content.toLowerCase().includes(query)
        );
        
        displayResults(results);
      });
    });
});
```

### Image Optimization

```html
<!-- Use Hugo's image processing -->
{{ $image := resources.Get "images/hero.jpg" }}
{{ $resized := $image.Resize "1200x600 webp" }}
<img src="{{ $resized.RelPermalink }}" alt="Hero image" class="w-full h-auto">
```

---

## SEO Optimization

### Meta Tags (`layouts/partials/head.html`)

```html
<head>
  <!-- Basic meta tags -->
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>{{ if .Title }}{{ .Title }} - {{ end }}{{ .Site.Title }}</title>
  <meta name="description" content="{{ .Description | default .Site.Params.description }}">
  
  <!-- Open Graph -->
  <meta property="og:title" content="{{ .Title | default .Site.Title }}">
  <meta property="og:description" content="{{ .Description | default .Site.Params.description }}">
  <meta property="og:type" content="{{ if .IsPage }}article{{ else }}website{{ end }}">
  <meta property="og:url" content="{{ .Permalink }}">
  {{ if .Params.image }}
    <meta property="og:image" content="{{ .Params.image | absURL }}">
  {{ end }}
  
  <!-- Twitter Cards -->
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="{{ .Title | default .Site.Title }}">
  <meta name="twitter:description" content="{{ .Description | default .Site.Params.description }}">
  
  <!-- Structured data -->
  {{ if .IsPage }}
    <script type="application/ld+json">
    {
      "@context": "https://schema.org",
      "@type": "BlogPosting",
      "headline": "{{ .Title }}",
      "author": {
        "@type": "Person",
        "name": "{{ .Site.Params.author }}"
      },
      "datePublished": "{{ .Date.Format "2006-01-02" }}",
      "description": "{{ .Description }}"
    }
    </script>
  {{ end }}
</head>
```

---

## Performance Optimization

### Build Configuration

```toml
# config.toml
[minify]
  disableCSS = false
  disableHTML = false
  disableJS = false
  disableJSON = false
  disableSVG = false
  disableXML = false

[imaging]
  resampleFilter = "CatmullRom"
  quality = 75
  anchor = "smart"

[caches]
  [caches.getjson]
    dir = ":cacheDir/:project"
    maxAge = "1h"
  [caches.getcsv]
    dir = ":cacheDir/:project"
    maxAge = "1h"
```

### Image Processing

```html
<!-- Responsive images with Hugo -->
{{ $image := resources.Get .Params.image }}
{{ $small := $image.Resize "400x" }}
{{ $medium := $image.Resize "800x" }}
{{ $large := $image.Resize "1200x" }}

<picture>
  <source media="(max-width: 400px)" srcset="{{ $small.RelPermalink }}">
  <source media="(max-width: 800px)" srcset="{{ $medium.RelPermalink }}">
  <img src="{{ $large.RelPermalink }}" alt="{{ .Title }}" class="w-full h-auto">
</picture>
```

---

## Deployment and Testing

### Local Development

```bash
# Copy template locally:
cp -r templates/hugo-portfolio/ ~/my-portfolio/

# Edit configuration:
cd ~/my-portfolio/
nano config.toml

# Test locally:
docker-compose up --build
# Site available at http://localhost:1313
```

### Content Workflow

```bash
# Add new blog post:
hugo new posts/my-new-post.md

# Add portfolio item:
hugo new portfolio/new-project.md

# Build site:
hugo --minify
```

### Deployment

```bash
# Validate template:
./jstack.sh --validate-template ~/my-portfolio/

# Deploy:
./jstack.sh --add-site myportfolio.com --template ~/my-portfolio/
```

---

## Troubleshooting

### Common Issues

**Build fails**:
```bash
# Check Hugo version and theme compatibility
# Verify config.toml syntax
# Ensure all required frontmatter is present
```

**Images not loading**:
```bash
# Check image paths in content
# Verify images are in static/ or assets/ directory
# Check Hugo image processing configuration
```

**Styling issues**:
```bash
# Verify Tailwind CSS configuration
# Check PostCSS processing
# Ensure CSS files are properly linked
```

---

## Next Steps

1. **🎨 [Hugo Themes](https://themes.gohugo.io/)** - Browse additional themes
2. **📝 [Content Management](../content-management.md)** - Advanced content strategies
3. **🚀 [Performance Tuning](../../reference/performance.md#static-sites)** - Optimize further
4. **📊 [Analytics Integration](../analytics.md)** - Track site performance
5. **🔍 [SEO Advanced](../seo-guide.md)** - Improve search rankings

**Need help?** Join the [Hugo Community](https://discourse.gohugo.io/) and [AI Productivity Hub](https://www.skool.com/ai-productivity-hub)!