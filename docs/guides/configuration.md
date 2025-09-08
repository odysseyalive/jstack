# 🔧 Configuration Guide - Edit Config Files with Confidence

**⏱️ 10 minutes** | **🟢 Beginner Friendly**

> **Learn how to safely edit JarvisJR configuration files to customize your AI Second Brain setup.**

## 🎯 What You'll Learn

After this guide, you'll be able to:
- ✅ Understand the two-file configuration system
- ✅ Safely edit configuration without breaking anything
- ✅ Customize domains, email, and security settings
- ✅ Validate your changes before deployment

---

## 📋 The Two-File Configuration System

JarvisJR uses a smart two-file approach:

```
jstack.config.default  ← Version-controlled defaults (don't edit!)
jstack.config          ← Your custom settings (this is what you edit!)
```

### 🛡️ Why This System?
- **Safe**: Your customizations never get overwritten by updates
- **Simple**: Only edit what you need to change
- **Reliable**: Defaults are always available as fallback

---

## 🚀 Quick Configuration (2 Minutes)

### Step 1: Create Your Configuration File
```bash
# Copy the template (only needed once)
cp jstack.config.default jstack.config
```

### Step 2: Edit Required Settings
```bash
# Open in your favorite editor
nano jstack.config
# or
vim jstack.config
# or  
code jstack.config  # VS Code
```

### Step 3: Edit These Two Required Lines
```bash
# ⚠️ REQUIRED: Your domain name (without https://)
DOMAIN=your-domain.com

# ⚠️ REQUIRED: Your email for SSL certificates
EMAIL=your-email@domain.com
```

### Step 4: Save and Validate
```bash
# Test your configuration
./jstack.sh --validate-config

# ✅ You should see: "Configuration validation passed"
```

**🎉 That's it! You're ready to deploy.**

---

## 🔍 Understanding Configuration Options

### 🏠 **Domain & SSL Settings**
```bash
# Your main domain (REQUIRED)
DOMAIN=mycompany.com

# Your email for Let's Encrypt SSL (REQUIRED)  
EMAIL=admin@mycompany.com

# Subdomain prefixes (optional - use defaults)
N8N_SUBDOMAIN=n8n          # Creates: n8n.mycompany.com
SUPABASE_SUBDOMAIN=api     # Creates: api.mycompany.com  
STUDIO_SUBDOMAIN=studio    # Creates: studio.mycompany.com
```

### 🔒 **Security Settings** (Optional)
```bash
# Supabase database password (auto-generated if empty)
SUPABASE_DB_PASSWORD=""

# JWT secret for API security (auto-generated if empty)
SUPABASE_JWT_SECRET=""

# Chrome browser security (recommended: keep default)
CHROME_NO_SANDBOX=false
```

### 🐳 **Container Resource Limits** (Optional)
```bash
# Memory limits (adjust based on your server)
POSTGRES_MEMORY_LIMIT=4g    # Database memory
N8N_MEMORY_LIMIT=2g         # N8N workflow engine  
CHROME_MEMORY_LIMIT=4g      # Browser automation
CHROME_MAX_INSTANCES=5      # Concurrent browsers
```

### 📊 **Monitoring & Logging** (Optional)
```bash
# Enable debug mode (more verbose logging)
DEBUG_MODE=false

# Log retention (days)
LOG_RETENTION_DAYS=30

# Enable performance monitoring
ENABLE_METRICS=true
```

---

## 🎨 Customization Examples

### Example 1: Basic Business Setup
```bash
# Essential settings for a business deployment
DOMAIN=mycompany.com
EMAIL=it@mycompany.com
N8N_SUBDOMAIN=workflows
SUPABASE_SUBDOMAIN=data
STUDIO_SUBDOMAIN=admin
```

### Example 2: Development/Testing Setup
```bash
# Settings for a development environment
DOMAIN=test.mycompany.com
EMAIL=dev@mycompany.com  
DEBUG_MODE=true
POSTGRES_MEMORY_LIMIT=2g
N8N_MEMORY_LIMIT=1g
```

### Example 3: High-Performance Setup
```bash
# Settings for a high-traffic deployment
DOMAIN=automation.mycompany.com
EMAIL=admin@mycompany.com
POSTGRES_MEMORY_LIMIT=8g
N8N_MEMORY_LIMIT=4g
CHROME_MEMORY_LIMIT=8g
CHROME_MAX_INSTANCES=10
ENABLE_METRICS=true
```

---

## ⚠️ Important Configuration Notes

### 🚫 **Never Edit These Files**
- `jstack.config.default` - Gets overwritten on updates
- Any file in `.git/` - Version control system files
- `docker-compose.yml` - Generated automatically

### ✅ **Safe to Customize**
- `jstack.config` - Your personal configuration
- Files in `/home/jarvis/jarvis-stack/` after deployment

### 🔐 **Security Best Practices**
1. **Use Strong Passwords**: If setting manual passwords, use 20+ random characters
2. **Keep Email Private**: Use a real email you control for SSL certificate notifications
3. **Domain Security**: Ensure your domain DNS is properly configured and secure

---

## 🔧 Advanced Configuration

### Environment-Specific Settings
```bash
# Production
ENVIRONMENT=production
ENABLE_BACKUPS=true
BACKUP_RETENTION_DAYS=90

# Staging  
ENVIRONMENT=staging
DEBUG_MODE=true
ENABLE_BACKUPS=false

# Development
ENVIRONMENT=development
DEBUG_MODE=true
ENABLE_METRICS=false
```

### Integration Settings
```bash
# Webhook URLs for external notifications
SLACK_WEBHOOK_URL=""
DISCORD_WEBHOOK_URL=""

# SMTP settings for email notifications
SMTP_HOST=""
SMTP_PORT=587
SMTP_USER=""
SMTP_PASSWORD=""
```

---

## 🧪 Testing Your Configuration

### Validation Commands
```bash
# Basic validation
./jstack.sh --validate-config

# Test DNS resolution  
./jstack.sh --test-dns

# Dry run deployment (test without changes)
./jstack.sh --dry-run

# Comprehensive pre-deployment check
./jstack.sh --pre-check
```

### 🔍 **What Gets Validated**
- ✅ Domain format and DNS resolution
- ✅ Email format validation
- ✅ Resource limit sanity checks  
- ✅ Required directory permissions
- ✅ Docker service availability
- ✅ Port availability (80, 443)

---

## 🚨 Troubleshooting Configuration Issues

### Problem: "Domain validation failed"
```bash
# Check DNS settings
dig your-domain.com
nslookup your-domain.com

# Ensure A record points to your server IP
```

### Problem: "Email validation failed"  
```bash
# Check email format (no spaces, valid format)
echo "admin@mycompany.com" | grep -E '^[^@]+@[^@]+\.[^@]+$'
```

### Problem: "Port already in use"
```bash
# Check what's using port 80/443
sudo netstat -tlnp | grep :80
sudo netstat -tlnp | grep :443

# Stop conflicting services
sudo systemctl stop apache2  # or nginx
```

### Problem: "Permission denied"
```bash
# Fix file permissions
chmod 600 jstack.config
sudo chown $USER:$USER jstack.config
```

---

## 🔄 Updating Configuration After Deployment

### Safe Configuration Updates
```bash
# 1. Edit your configuration
nano jstack.config

# 2. Validate changes
./jstack.sh --validate-config

# 3. Apply changes (restarts affected services)
./jstack.sh --update-config

# 4. Verify services are running
./jstack.sh --status
```

### 🚨 **Changes Requiring Full Restart**
These changes require `./jstack.sh --restart`:
- Domain name changes
- Memory limit changes
- Major security setting changes

### ✅ **Changes Applied Automatically**
These changes are applied immediately:
- Email address updates
- Debug mode toggles
- Monitoring settings

---

## 🎓 Next Steps

**Configuration Complete! 🎉**

### What's Next?
1. **🚀 [Deploy JarvisJR](installation.md#step-4-deploy)** - Run the installation
2. **🧠 [Create First Workflow](first-workflow.md)** - Build your first automation
3. **🛡️ [Service Management](service-management.md)** - Learn to manage your system

### Need More Help?
- **📞 [Troubleshooting Guide](troubleshooting.md)** - Fix common issues
- **🔍 [Configuration Reference](../reference/configuration-ref.md)** - Complete settings list
- **💬 [Community Support](https://www.skool.com/ai-productivity-hub)** - Get help from users

---

**[⬅️ Back to Installation Guide](installation.md)** | **[➡️ Continue to Deployment](installation.md#step-4-deploy)**