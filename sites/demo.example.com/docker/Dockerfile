# Multi-stage build for Hugo with Tailwind CSS
FROM hugomods/hugo:base AS builder

# Set working directory
WORKDIR /src

# Copy Hugo site files
COPY src/ ./

# Install Node.js dependencies for Tailwind CSS
RUN npm ci

# Build Hugo site with optimizations
RUN hugo --gc --minify --cleanDestinationDir

# Production stage with NGINX
FROM nginx:1.25-alpine AS runner

# Create non-root user for security (rootless execution)
RUN addgroup -g 1001 -S nginx-site && \
    adduser -S -D -H -u 1001 -h /var/cache/nginx -s /sbin/nologin -G nginx-site -g nginx-site nginx-site

# Copy built site from builder stage
COPY --from=builder --chown=nginx-site:nginx-site /src/public /usr/share/nginx/html

# Copy custom NGINX configuration
COPY --chown=nginx-site:nginx-site docker/nginx.conf /etc/nginx/nginx.conf
COPY --chown=nginx-site:nginx-site docker/default.conf /etc/nginx/conf.d/default.conf

# Set proper permissions
RUN chown -R nginx-site:nginx-site /var/cache/nginx && \
    chown -R nginx-site:nginx-site /var/log/nginx && \
    chown -R nginx-site:nginx-site /etc/nginx/conf.d && \
    chown -R nginx-site:nginx-site /usr/share/nginx/html && \
    touch /var/run/nginx.pid && \
    chown nginx-site:nginx-site /var/run/nginx.pid

# Switch to non-root user
USER nginx-site

# Expose port
EXPOSE 8080

# Health check for container orchestration
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8080/ || exit 1

# Start NGINX
CMD ["nginx", "-g", "daemon off;"]