# Nginx Container Mount Error - Fix Checklist

## **Problem Summary**
Nginx container failing to start due to missing directory structure for Docker volume mounts:
```
ERROR: Cannot start service nginx: failed to create task for container: 
error mounting "/home/jarvis/jstack/sites/default/html" to rootfs at "/usr/share/nginx/html/default"
```

## **Root Cause**
- Missing `./sites/default/html` directory that docker-compose.yml tries to mount as read-only volume
- Docker cannot create mount point when source directory doesn't exist

## **IMMEDIATE FIXES (Critical Priority)**

### **Fix 1: Create Missing Directory Structure**
- [ ] Create the missing directory: `mkdir -p sites/default/html`
- [ ] Set proper permissions: `chmod -R 755 sites/default/html`
- [ ] Create default landing page: `echo "<html><body><h1>JStack Loading...</h1></body></html>" > sites/default/html/index.html`
- [ ] Test directory exists: `ls -la sites/default/html/`
- [ ] Verify file permissions: `ls -la sites/default/html/index.html`

### **Fix 2: Validate Other Required Directories**
- [ ] Check `./nginx/conf.d` exists: `ls -la nginx/conf.d/` 
- [ ] Check `./nginx/certbot/www` exists: `ls -la nginx/certbot/www/`
- [ ] Check `./nginx/certbot/conf` exists: `ls -la nginx/certbot/conf/`
- [ ] Check `./data/supabase` exists: `ls -la data/supabase/`
- [ ] Check `./data/n8n` exists: `ls -la data/n8n/`
- [ ] Check `./data/chrome` exists: `ls -la data/chrome/`

### **Fix 3: Test Nginx Container Startup**
- [ ] Run `docker-compose up nginx` to test nginx service only
- [ ] Check nginx container logs: `docker-compose logs nginx`
- [ ] Verify nginx is running: `docker-compose ps nginx`
- [ ] Test nginx health: `curl -I http://localhost:8080` (if accessible)

## **SHORT-TERM IMPROVEMENTS (High Priority)**

### **Update Installation Scripts**
- [ ] **Update `full_stack_install.sh`**: Add directory creation before docker-compose
- [ ] Add directory creation function:
  ```bash
  create_required_directories() {
    log "Creating required directory structure..."
    mkdir -p sites/default/html
    mkdir -p nginx/conf.d
    mkdir -p nginx/certbot/{www,conf}
    mkdir -p data/{supabase,n8n,chrome}
    chmod -R 755 sites/default/html
    echo "<html><body><h1>JStack Loading...</h1></body></html>" > sites/default/html/index.html
    log "✓ Directory structure created"
  }
  ```
- [ ] Call `create_required_directories` before docker operations
- [ ] Test updated installation script with `--dry-run`

### **Update SSL Scripts**
- [ ] **Update `setup_service_subdomains_ssl.sh`**: Add directory validation
- [ ] Add mount point validation function:
  ```bash
  validate_nginx_mounts() {
    local required_dirs=("sites/default/html" "nginx/conf.d" "nginx/certbot/www")
    for dir in "${required_dirs[@]}"; do
      if [[ ! -d "$dir" ]]; then
        log "ERROR: Required directory missing: $dir"
        return 1
      fi
    done
    log "✓ All nginx mount directories exist"
  }
  ```
- [ ] Call validation before nginx operations
- [ ] Test SSL scripts with directory validation

## **MEDIUM-TERM ENHANCEMENTS (Medium Priority)**

### **Add Comprehensive Pre-flight Checks**
- [ ] Create `scripts/core/validate_environment.sh` script
- [ ] Include checks for:
  - [ ] All required directories
  - [ ] Docker and docker-compose availability
  - [ ] Port availability (80, 443, 8080, 8443)
  - [ ] Disk space requirements
  - [ ] File permissions
- [ ] Integrate validation into main installation flow

### **Enhance Error Handling**
- [ ] Add specific error messages for missing directories
- [ ] Provide clear instructions for manual directory creation
- [ ] Add automatic recovery suggestions
- [ ] Log detailed information about mount failures

### **Update Documentation**
- [ ] Document required directory structure in README.md
- [ ] Add troubleshooting section for mount errors
- [ ] Create pre-installation checklist
- [ ] Update installation instructions with prerequisites

## **LONG-TERM IMPROVEMENTS (Low Priority)**

### **Docker Configuration Enhancements**
- [ ] Consider using named volumes instead of bind mounts for some directories
- [ ] Add health checks for all volume mounts
- [ ] Implement graceful degradation for missing optional mounts

### **Automated Setup**
- [ ] Create setup wizard script
- [ ] Add interactive directory creation
- [ ] Implement automated environment validation
- [ ] Add rollback capabilities for failed installations

## **TESTING CHECKLIST**

### **After Immediate Fixes**
- [ ] `docker-compose up nginx` works without errors
- [ ] All containers start successfully: `docker-compose up -d`
- [ ] Services are accessible on expected ports
- [ ] SSL script integration works with nginx running

### **After Script Updates**
- [ ] Installation script creates all required directories
- [ ] SSL scripts validate mount points before proceeding
- [ ] Error handling provides clear guidance
- [ ] Dry-run mode shows directory creation steps

### **After Full Implementation**
- [ ] Fresh installation on clean system works
- [ ] All services start without manual intervention
- [ ] Error recovery works for common failure scenarios
- [ ] Documentation matches actual behavior

## **SUCCESS CRITERIA**
- ✅ Nginx container starts without mount errors
- ✅ All JStack services start successfully
- ✅ SSL setup process works end-to-end
- ✅ Installation is reproducible and reliable
- ✅ Clear error messages for common issues

## **RISK MITIGATION**
- **Backup current configuration** before making changes
- **Test each fix incrementally** to isolate issues
- **Document all changes** for potential rollback
- **Test on clean environment** to validate complete fix