# Main Domain Configuration Fix - Detailed Task List

## **Problem Summary**
JStack installation process has an architectural gap: while subdomains (`api.example.com`, `studio.example.com`, `n8n.example.com`) get proper nginx configurations during `--install`, the **main domain** (`example.com`) does NOT get its own configuration file. This causes:

1. **Mount Error**: Missing `nginx/conf.d` directory causes Docker mount failures
2. **Architectural Issue**: Main domain relies on catch-all `default.conf` instead of explicit configuration
3. **Inconsistency**: Subdomains get proper HTTP→HTTPS phases, main domain doesn't
4. **Professional Gap**: Main domain should have explicit configuration like subdomains

## **PHASE 1: IMMEDIATE FIX (Critical Priority)**

### **Task 1.1: Create Missing Directory Structure**
- [ ] **Create nginx/conf.d directory**: `mkdir -p nginx/conf.d`
- [ ] **Verify other required directories exist**:
  - [ ] `nginx/certbot/www`
  - [ ] `nginx/certbot/conf` 
  - [ ] `sites/default/html`
- [ ] **Test Docker startup**: `docker-compose up -d`
- [ ] **Verify all containers start**: `docker-compose ps`
- [ ] **Test main domain access**: `curl -I http://localhost:8080`

**Success Criteria**: Docker containers start without mount errors, nginx serves the landing page.

## **PHASE 2: ARCHITECTURAL FIX (High Priority)**

### **Task 2.1: Enhance Main Domain Configuration Generation**
- [ ] **Modify `scripts/core/setup_service_subdomains_ssl.sh`**
- [ ] **Add new function `generate_main_domain_config()`**:
  ```bash
  generate_main_domain_config() {
    local domain="$DOMAIN"
    local nginx_conf_dir="nginx/conf.d"
    
    log "Creating main domain config: ${domain}.conf..."
    cat >"${nginx_conf_dir}/${domain}.conf" <<EOF
  # Main Domain Configuration for ${domain} - JStack
  
  # HTTP server for ACME challenges
  server {
      listen 80;
      server_name ${domain};
      
      # ACME challenge location for Let's Encrypt
      location /.well-known/acme-challenge/ {
          root /var/www/certbot;
      }
  EOF
  
    # Add location based on SSL_MODE
    if [[ "$SSL_MODE" == "http-only" ]]; then
      cat >>"$nginx_conf_dir/${domain}.conf" <<EOF
  
      # Serve landing page during setup
      location / {
          root /usr/share/nginx/html/default;
          index index.html;
      }
  }
  EOF
    else
      cat >>"$nginx_conf_dir/${domain}.conf" <<EOF
  
      # Redirect all other traffic to HTTPS
      location / {
          return 301 https://\$host\$request_uri;
      }
  }
  
  # HTTPS server
  server {
      listen 443 ssl;
      server_name ${domain};
      ssl_certificate /etc/letsencrypt/live/${domain}/fullchain.pem;
      ssl_certificate_key /etc/letsencrypt/live/${domain}/privkey.pem;
  
      # Security headers
      add_header X-Frame-Options SAMEORIGIN;
      add_header X-Content-Type-Options nosniff;
      add_header X-XSS-Protection "1; mode=block";
      add_header Strict-Transport-Security "max-age=31536000; includeSubDomains";
  
      # Serve landing page or redirect as needed
      location / {
          root /usr/share/nginx/html/default;
          index index.html;
      }
  }
  EOF
    fi
    
    log "✓ Generated main domain config for $domain (mode: $SSL_MODE)"
  }
  ```

### **Task 2.2: Integrate Main Domain Config into Generation Process**
- [ ] **Update `generate_nginx_configs()` function** in `setup_service_subdomains_ssl.sh`
- [ ] **Add call to `generate_main_domain_config()` BEFORE subdomain configs**:
  ```bash
  generate_nginx_configs() {
    log "Generating NGINX configuration files for domain: $DOMAIN (mode: $SSL_MODE)"
    
    local nginx_conf_dir="nginx/conf.d"
    mkdir -p "$nginx_conf_dir"
    
    # Generate main domain config FIRST
    generate_main_domain_config
    
    # Generate default.conf (catch-all)
    log "Creating default.conf..."
    # ... existing default.conf code ...
    
    # Generate subdomain configs
    # ... existing subdomain generation code ...
  }
  ```

### **Task 2.3: Update SSL Certificate Process**
- [ ] **Verify main domain is included in SSL cert request**
- [ ] **Check `bootstrap_ssl_certificates()` function includes main domain**
- [ ] **Ensure domain list**: `"${DOMAIN} api.${DOMAIN} studio.${DOMAIN} n8n.${DOMAIN}"`

### **Task 2.4: Test Two-Phase SSL Process**
- [ ] **Test HTTP-only phase**: `setup_service_subdomains_ssl.sh --http-only`
  - [ ] Verify main domain config created with landing page
  - [ ] Verify ACME challenges work on main domain
- [ ] **Test SSL phase**: `setup_service_subdomains_ssl.sh --with-ssl`
  - [ ] Verify main domain config updated with HTTPS
  - [ ] Verify SSL certificate works on main domain
  - [ ] Verify HTTP→HTTPS redirect works

## **PHASE 3: INSTALLATION PROCESS INTEGRATION (Medium Priority)**

### **Task 3.1: Update Full Stack Installation**
- [ ] **Verify `scripts/core/full_stack_install.sh` calls subdomain SSL setup**
- [ ] **Ensure main domain gets configured during `--install` process**
- [ ] **Test complete installation flow**:
  - [ ] Fresh environment test
  - [ ] `./jstack.sh --install`
  - [ ] Verify main domain configuration created
  - [ ] Verify SSL works on main domain

### **Task 3.2: Update Site Installation Process**
- [ ] **Review `--install-site` functionality in `jstack.sh`**
- [ ] **Ensure main domain config doesn't conflict with site installations**
- [ ] **Consider main domain behavior options**:
  - [ ] Default landing page (current)
  - [ ] Redirect to primary site/service
  - [ ] Custom main domain configuration

## **PHASE 4: DOCUMENTATION AND VALIDATION (Low Priority)**

### **Task 4.1: Update Documentation**
- [ ] **Update README.md** with main domain configuration details
- [ ] **Document main domain behavior** in installation guide
- [ ] **Add troubleshooting section** for main domain issues

### **Task 4.2: Create Validation Tests**
- [ ] **Add main domain validation** to existing checks
- [ ] **Create test script** for complete domain setup
- [ ] **Test edge cases**:
  - [ ] Main domain same as subdomain
  - [ ] Multiple main domain configurations
  - [ ] Main domain SSL certificate issues

## **PHASE 5: FUTURE ENHANCEMENTS (Future Priority)**

### **Task 5.1: Main Domain Customization**
- [ ] **Add main domain template options**
- [ ] **Support custom main domain applications**
- [ ] **Add main domain routing options**

### **Task 5.2: Configuration Management**
- [ ] **Add main domain behavior to jstack.config**
- [ ] **Support different main domain modes**:
  - [ ] Landing page mode (current)
  - [ ] Redirect mode
  - [ ] Application mode
  - [ ] Custom mode

## **IMPLEMENTATION PRIORITY ORDER**

1. **🔴 CRITICAL (Do First)**: Phase 1 - Immediate Fix
2. **🟡 HIGH (Do Next)**: Phase 2 - Architectural Fix  
3. **🟢 MEDIUM**: Phase 3 - Installation Integration
4. **🔵 LOW**: Phase 4 - Documentation
5. **⚪ FUTURE**: Phase 5 - Enhancements

## **SUCCESS CRITERIA**

### **Phase 1 Success**
- ✅ Docker containers start without errors
- ✅ Nginx serves content on main domain
- ✅ No mount errors in Docker logs

### **Phase 2 Success**  
- ✅ Main domain gets explicit nginx configuration
- ✅ Main domain supports HTTP-only and with-ssl modes
- ✅ Main domain gets proper SSL certificates
- ✅ HTTP→HTTPS redirects work on main domain

### **Complete Success**
- ✅ `./jstack.sh --install` configures main domain properly
- ✅ Main domain behavior consistent with subdomains
- ✅ SSL setup works end-to-end for all domains
- ✅ Professional, maintainable domain configuration

## **TECHNICAL NOTES**

### **File Locations**
- **Main Script**: `scripts/core/setup_service_subdomains_ssl.sh`
- **Installation**: `scripts/core/full_stack_install.sh`
- **Entry Point**: `jstack.sh`
- **Config**: `jstack.config` / `jstack.config.default`
- **Docker**: `docker-compose.yml`

### **Key Functions to Modify**
- `generate_nginx_configs()` - Add main domain generation
- `bootstrap_ssl_certificates()` - Verify main domain inclusion
- `validate_nginx_mounts()` - Already handles required directories

### **Testing Commands**
```bash
# Test immediate fix
mkdir -p nginx/conf.d && docker-compose up -d

# Test HTTP-only config generation
./scripts/core/setup_service_subdomains_ssl.sh --http-only

# Test SSL config generation  
./scripts/core/setup_service_subdomains_ssl.sh --with-ssl

# Test complete installation
./jstack.sh --install

# Validate main domain
curl -I http://example.com
curl -I https://example.com
```

## **RISK MITIGATION**

### **Backup Strategy**
- [ ] Backup existing nginx configs before modifications
- [ ] Save current docker-compose.yml state
- [ ] Document rollback procedure

### **Testing Strategy**
- [ ] Test on development environment first
- [ ] Incremental implementation (phase by phase)
- [ ] Validate each phase before proceeding

### **Rollback Plan**
- [ ] Keep original scripts backed up
- [ ] Document how to revert changes
- [ ] Test rollback procedure

---

**Created**: Planning phase analysis of nginx mount error and main domain configuration gap
**Priority**: Phase 1 (Critical) → Phase 2 (High) → Phase 3 (Medium)
**Impact**: Fixes immediate Docker errors + Improves architectural consistency