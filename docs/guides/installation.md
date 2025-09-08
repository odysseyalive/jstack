# 🚀 Complete Installation Guide - Step-by-Step

**⏱️ 15 minutes** | **🟢 Beginner Friendly**

> **Get your complete AI Second Brain infrastructure running from zero to production-ready in 15 minutes.**

## 🎯 What You'll Achieve

After this guide, you'll have:

- ✅ Complete AI automation infrastructure running
- ✅ N8N workflow builder accessible via web
- ✅ Supabase database with real-time APIs
- ✅ Enterprise security with SSL certificates
- ✅ Monitoring and backup systems active

---

## 📋 Before You Start

### ✅ **Requirements Checklist**

**Server Requirements:**

- ✅ Ubuntu 20.04+ or Debian 11+ server
- ✅ 4GB+ RAM (8GB recommended for production)
- ✅ 20GB+ free disk space  
- ✅ Sudo/root access
- ✅ Internet connection

**Domain & Email:**

- ✅ Domain name you own (e.g., `mycompany.com`)
- ✅ DNS A record pointing to your server IP
- ✅ Email address you control for SSL certificates

### 🌐 **DNS Setup (5 minutes)**

Point these subdomains to your server IP:

```
yourdomain.com        → Your Server IP
n8n.yourdomain.com    → Your Server IP  
api.yourdomain.com    → Your Server IP
studio.yourdomain.com → Your Server IP
```

**Quick DNS Test:**

```bash
# Replace with your domain and server IP
dig yourdomain.com
# Should return your server's IP address
```

---

## 🚀 Installation Steps

### Step 1: Server Preparation (2 minutes)

```bash
# Update your system
sudo apt update && sudo apt upgrade -y

# Install required packages
sudo apt install -y curl git wget software-properties-common

# Install Docker (if not already installed)
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Re-login to apply Docker permissions
exit
# SSH back into your server
```

### Step 2: Download jstack (1 minute)

```bash
# Clone the repository
git clone https://github.com/odysseyalive/jstack.git
cd jstack

# Make the main script executable
chmod +x jstack.sh

# Verify download
ls -la jstack.sh
# Should show executable permissions
```

### Step 3: Configuration (2 minutes)

```bash
# Copy configuration template
cp jstack.config.default jstack.config

# Edit with your favorite editor
nano jstack.config
```

**⚠️ Edit These Required Lines:**

```bash
# Replace with your actual domain and email
DOMAIN=yourdomain.com
EMAIL=your-email@yourdomain.com
```

**🔍 Optional Customizations:**

```bash
# Customize subdomain prefixes (optional)
N8N_SUBDOMAIN=workflows    # Creates workflows.yourdomain.com
SUPABASE_SUBDOMAIN=data    # Creates data.yourdomain.com
STUDIO_SUBDOMAIN=admin     # Creates admin.yourdomain.com
```

**💾 Save and Exit** (Ctrl+X, Y, Enter in nano)

### Step 4: Validate Configuration (1 minute)

```bash
# Test your configuration
./jstack.sh --validate

# ✅ You should see: "Pre-deployment validation passed"
# ❌ If errors, check DNS settings and configuration
```

### Step 5: Deploy! (5-10 minutes) ☕

```bash
# Deploy complete infrastructure  
./jstack.sh

# 🎉 The script will:
# - Download and configure all containers
# - Set up SSL certificates automatically
# - Configure security systems
# - Start all services
# - Run health checks
```

**📊 What You'll See:**

- Colored progress logs showing each step
- Docker container downloads and configurations  
- SSL certificate generation (may take 2-3 minutes)
- Service startup and health checks
- Final success message with access URLs

### Step 6: Verify Installation (2 minutes)

```bash
# Check all services are running
./jstack.sh --status

# Test web access
curl -k https://yourdomain.com
# Should return webpage content
```

**🌐 Access Your Services:**
Open these URLs in your browser:

- **🧠 AI Workflows**: `https://n8n.yourdomain.com`
- **📊 Database Admin**: `https://studio.yourdomain.com`  
- **🔍 API Access**: `https://api.yourdomain.com`

---

## 🎉 Success Verification

### ✅ **Installation Complete When:**

1. **All Services Show "Running"**

   ```bash
   ./jstack.sh --status
   # Should show all services as "active (running)"
   ```

2. **Web Interfaces Load**
   - N8N loads with login screen
   - Supabase Studio loads with project dashboard
   - No SSL certificate warnings in browser

3. **Health Check Passes**

   ```bash  
   ./jstack.sh --health-check
   # Should report "All systems healthy"
   ```

### 🎯 **Your Access Information**

**Service URLs:**

- **N8N Workflows**: `https://n8n.yourdomain.com`
- **Supabase Studio**: `https://studio.yourdomain.com`
- **Supabase API**: `https://api.yourdomain.com`

**Generated Passwords:**

```bash
# View your generated passwords
./jstack.sh --show-credentials

# Or check the deployment log
$1

---

## 🌐 Deploy Websites (Optional)

Now that jstack is running, you can deploy production websites using built-in templates:

### 🚀 **Quick Site Deployment**

```bash
# Deploy a Next.js business site:
./jstack.sh --add-site mybusiness.com --template nextjs-business

# Deploy a Hugo portfolio:
./jstack.sh --add-site myportfolio.com --template hugo-portfolio

# Deploy a LAMP web application:
./jstack.sh --add-site myapp.com --template lamp-webapp
```

### 📚 **Available Templates**

| Template | Best For | Tech Stack | Deploy Time |
|----------|----------|------------|-------------|
| **nextjs-business** | Business sites, web apps | Next.js, React, Node.js | ~3 minutes |
| **hugo-portfolio** | Blogs, portfolios, docs | Hugo, Tailwind CSS | ~2 minutes |
| **lamp-webapp** | PHP apps, WordPress, CMSs | PHP 8.2, Apache, MariaDB | ~4 minutes |

### ⚙️ **Custom Site Deployment**

```bash
# Copy template for customization:
cp -r templates/nextjs-business/ ~/my-custom-site/

# Edit configuration and code:
cd ~/my-custom-site/
nano site.json  # Basic settings
nano src/app/page.tsx  # Next.js customization

# Deploy customized template:
./jstack.sh --add-site mysite.com --template ~/my-custom-site/
```

### 🔍 **Template Management**

```bash
# List all deployed sites:
./jstack.sh --list-sites

# Remove a site:
./jstack.sh --remove-site old-site.com

# Validate template before deployment:
./jstack.sh --validate-template templates/nextjs-business/
```

**📚 Learn More**: [Complete Site Templates Guide →](site-templates.md)

---

## 📱 First Login & Setup

### Step 1: N8N Workflow Builder

1. Visit `https://n8n.yourdomain.com`
2. Create your admin account (first user becomes admin)
3. Explore the visual workflow builder
4. **📚 Next**: [Create Your First Workflow](first-workflow.md)

### Step 2: Supabase Database Studio  

1. Visit `https://studio.yourdomain.com`
2. Login with generated credentials (shown in deployment log)
3. Explore your PostgreSQL database interface
4. **📊 Tip**: This is where your workflow data is stored

### Step 3: API Access (For Developers)

1. Visit `https://api.yourdomain.com`
2. Note the API endpoints and documentation
3. Use these APIs to integrate with external applications

---

## 🔒 Security Setup (Automatic!)

**🛡️ What's Already Protected:**

- ✅ **SSL Encryption** - All traffic encrypted with Let's Encrypt certificates
- ✅ **Firewall Protection** - UFW configured with minimal required ports
- ✅ **Intrusion Prevention** - fail2ban actively blocking threats  
- ✅ **Container Isolation** - All services run in isolated Docker containers
- ✅ **Automated Monitoring** - Real-time security monitoring active
- ✅ **Regular Updates** - Security patches applied automatically

**🔍 Security Dashboard:**

```bash
# View security status
./jstack.sh --security-status

# Check recent security events  
./jstack.sh --security-logs

# Run security scan
./jstack.sh --security-scan
```

---

## 🛠️ Post-Installation Tasks

### 🔄 **System Updates**

```bash
# Update jstack to latest version
./jstack.sh --update

# Update system packages  
sudo apt update && sudo apt upgrade -y

# Restart services if needed
./jstack.sh --restart
```

### 💾 **Backup Setup** (Recommended)

```bash
# Create your first backup
./jstack.sh --backup

# Schedule automated backups (optional)
./jstack.sh --schedule-backups daily

# List available backups
./jstack.sh --list-backups
```

### 📊 **Monitoring Setup**

```bash
# Enable monitoring dashboard (optional)
./jstack.sh --enable-monitoring

# View system metrics
./jstack.sh --metrics

# Check system health
./jstack.sh --health-check
```

---

## 🚨 Troubleshooting Installation Issues

### ❌ **"Domain validation failed"**

```bash
# Check DNS propagation
dig yourdomain.com +short
nslookup yourdomain.com

# Wait for DNS propagation (up to 24 hours)
# Or use a DNS propagation checker online
```

### ❌ **"SSL certificate generation failed"**

```bash
# Check email is valid and you control it
# Ensure ports 80 and 443 are open:
sudo ufw status
sudo netstat -tlnp | grep :80
sudo netstat -tlnp | grep :443

# Try manual SSL generation:
./jstack.sh --ssl-only
```

### ❌ **"Docker permission denied"**

```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Log out and back in, then try again
exit
# SSH back in and retry
```

### ❌ **"Port already in use"**

```bash
# Check what's using the ports
sudo netstat -tlnp | grep :80
sudo netstat -tlnp | grep :443

# Stop conflicting services
sudo systemctl stop apache2  # or nginx
sudo systemctl disable apache2

# Retry installation
./jstack.sh
```

### ❌ **"Services won't start"**

```bash
# Check system resources
free -h
df -h

# View detailed logs
./jstack.sh --logs

# Try individual service restart
./jstack.sh --restart-n8n
./jstack.sh --restart-db
```

---

## 🎓 Next Steps

### 🧠 **Start Building Automations**

1. **[Configuration Guide](configuration.md)** - Understand your settings
2. **[First Workflow Tutorial](first-workflow.md)** - Create your first automation  
3. **[Service Management](service-management.md)** - Manage your system

### 🔧 **System Administration**

1. **[Backup & Recovery](backup-recovery.md)** - Protect your data
2. **[Troubleshooting Guide](troubleshooting.md)** - Fix common issues
3. **[Performance Tuning](../reference/performance.md)** - Optimize for scale

### 🔒 **Advanced Security**

1. **[Security Documentation](../reference/security.md)** - Enterprise security features
2. **[Compliance Guide](../reference/compliance.md)** - SOC2/GDPR/ISO27001 compliance
3. **[Monitoring Setup](../reference/monitoring.md)** - Advanced monitoring

---

## 📞 Get Help

### 🐛 **Issues?**

- **[Troubleshooting Guide](troubleshooting.md)** - Common problems solved
- **[GitHub Issues](https://github.com/odysseyalive/jstack/issues)** - Report bugs
- **[Community Support](https://www.skool.com/ai-productivity-hub)** - Get help from users

### 📧 **Enterprise Support**

- **Email**: <enterprise@jstack.com>
- **Priority Support**: Available for production deployments
- **Custom Integration**: Available for enterprise customers

---

**🎉 Congratulations! Your AI Second Brain is now running!**

**[⬅️ Back to Quick Start](../../README.md#-quick-start---new-to-ai-automation)** | **[➡️ Create First Workflow](first-workflow.md)**

