# SSL Certificate Handling Update Tasklist

## **Project Overview**
Modify the jstack.sh --install process to create nginx files for main subdomains with port 80 traffic only initially, then run certbot for each subdomain individually, and finally update configs to redirect port 80 to 443 with proper HTTPS server blocks.

## **Current SSL Process Analysis**

The current system has:
1. **Complex combined approach**: `setup_service_subdomains_ssl.sh` generates nginx configs with both HTTP and HTTPS blocks simultaneously
2. **All-in-one certificate acquisition**: Attempts to get certificates for all subdomains (api, studio, n8n, chrome) at once using multi-domain certificates
3. **Late-stage redirect enablement**: `enable_https_redirects.sh` modifies existing configs after certificate acquisition
4. **Potential startup issues**: nginx may fail to start if SSL certificate references exist but certificates aren't available

## **SSL Certificate Handling Update Tasklist**

### **Phase 0: Configuration Migration (PREREQUISITE)**

#### **0.1 Extract HTTPS Server Blocks from setup_service_subdomains_ssl.sh**
- [ ] **Copy port 443 server block configurations** from `setup_service_subdomains_ssl.sh` to `enable_https_redirects.sh`
  - Extract HTTPS server blocks for: default.conf, api.$DOMAIN.conf, studio.$DOMAIN.conf, n8n.$DOMAIN.conf
  - Preserve all SSL certificate references, security headers, and proxy configurations
  - Include WebSocket support configurations for each service
  - Maintain service-specific authentication (e.g., Studio HTTP Basic Auth)

#### **0.2 Update enable_https_redirects.sh Structure**
- [ ] **Restructure enable_https_redirects.sh** to handle HTTPS server block addition
  - Create functions for each subdomain HTTPS configuration
  - Add certificate validation before applying HTTPS blocks
  - Implement per-domain HTTPS activation logic
  - Add error handling for missing certificates

#### **0.3 Validate Configuration Preservation**
- [ ] **Ensure no configuration loss** during migration
  - Verify all security headers are preserved
  - Confirm proxy pass configurations remain intact
  - Check SSL certificate path references are correct
  - Validate service-specific settings (auth, timeouts, etc.)

#### **0.4 Fix Pattern Matching Mismatch (CRITICAL)**
- [ ] **Audit sed patterns in enable_https_redirects.sh** vs actual generated content
  - Current `enable_https_redirects.sh` expects: `# Serve landing page during setup` and `index index.html;`
  - Actual `setup_service_subdomains_ssl.sh` generates: `return 301 https://\$host\$request_uri;` already
  - **Problem**: Scripts are misaligned - no landing pages to replace
- [ ] **Design consistent HTTP server block approach**
  - Option A: Modify `setup_service_subdomains_ssl.sh` to generate landing pages initially
  - Option B: Modify `enable_https_redirects.sh` to work with existing redirect patterns
  - **Recommendation**: Option A - serve landing pages during setup, add redirects later

### **Phase 1: Modify jstack.sh --install Process for HTTP-Only nginx Configs**

#### **1.1 Update setup_service_subdomains_ssl.sh**
- [ ] **Modify `generate_nginx_configs()` function** to create HTTP-only server blocks initially
  - Remove HTTPS server blocks (443) from initial generation  
  - Keep only port 80 server blocks with ACME challenge support
  - Remove SSL certificate references from initial configs
  - Ensure landing pages are served during setup phase

#### **1.2 Update full_stack_install.sh Integration**
- [ ] **Modify SSL setup call** in `full_stack_install.sh`
  - Change SSL setup to HTTP-only mode initially: `setup_service_subdomains_ssl.sh --http-only`
  - Remove direct SSL certificate acquisition from main install flow
  - Defer SSL certificate acquisition to separate phase

#### **1.3 Review nginx Configuration Changes**
- [ ] **Review updated HTTP-only nginx configs** for correctness
  - Verify port 80 blocks are properly configured
  - Confirm ACME challenge endpoints are accessible
  - Check that no SSL references remain in HTTP configs

### **Phase 2: Individual Subdomain Certificate Acquisition**

#### **2.0 Add CHROME_URL Configuration Support**
- [ ] **Add `CHROME_URL="chrome.example.com"` to `jstack.config.default`** to match other service URL configurations (N8N_URL, SUPABASE_API_URL, SUPABASE_STUDIO_URL)
- [ ] **Update `full_stack_install.sh` certbot loop** to include chrome subdomain:
  - Change: `for SUBDOMAIN in "api.$DOMAIN" "n8n.$DOMAIN" "studio.$DOMAIN"; do`
  - To: `for SUBDOMAIN in "api.$DOMAIN" "n8n.$DOMAIN" "studio.$DOMAIN" "chrome.$DOMAIN"; do`
- [ ] **Ensure chrome subdomain is included** in DNS prerequisites and rate limiting considerations

#### **2.1 Create Iterative Certificate Acquisition Process**
- [ ] **Modify certificate acquisition logic** to process subdomains individually
  - Replace multi-domain certificate approach with individual domain certificates
  - Create loop for each subdomain: `api.$DOMAIN`, `studio.$DOMAIN`, `n8n.$DOMAIN`, `chrome.$DOMAIN`
  - Add certificate acquisition retry logic with proper error handling
  - Implement DNS resolution checking before certificate requests

#### **2.2 Certificate Storage and Organization**
- [ ] **Update certificate file structure**
  - Ensure individual certificate directories: `/etc/letsencrypt/live/api.example.com/`, etc.
  - Update nginx volume mounts to support individual certificates
  - Fix certificate file permissions for nginx container access (user 101)

#### **2.3 Review Certificate Acquisition Changes**
- [ ] **Review iterative certbot implementation** for chrome inclusion
  - Verify chrome subdomain is properly handled in loops
  - Confirm individual certificate logic is correct
  - Double-check with Context7 documentation for certbot best practices

### **Phase 3: HTTPS Configuration Deployment**

#### **3.1 Update enable_https_redirects.sh**
- [ ] **Enhance redirect enablement script** to add HTTPS server blocks
  - Modify script to add port 443 server blocks (not just redirects)
  - Update each subdomain config to include SSL certificate references
  - Add proper security headers for HTTPS blocks
  - Maintain proxy configurations for each service

#### **3.2 Progressive HTTPS Activation**
- [ ] **Implement per-domain HTTPS activation**
  - Process subdomains individually: if certificate exists, add HTTPS block
  - Skip HTTPS blocks for subdomains with failed certificate acquisition
  - Maintain HTTP access for domains without valid certificates
  - Add validation step for certificate availability before HTTPS activation

#### **3.3 Review HTTPS Configuration Changes**
- [ ] **Review enable_https_redirects.sh updates** for pattern matching fixes
  - Verify sed patterns match actual generated content
  - Confirm HTTPS blocks are correctly added
  - Double-check with Context7 for nginx SSL configuration best practices

### **Phase 4: Error Handling and Fallback Mechanisms**

#### **4.1 Certificate Acquisition Failure Handling** 
- [ ] **Implement graceful failure modes**
  - Continue installation if individual certificate acquisition fails
  - Log specific failure reasons (DNS, rate limiting, firewall)
  - Maintain HTTP-only access for failed domains
  - Provide manual certificate acquisition instructions

#### **4.2 Self-Signed Certificate Fallback**
- [ ] **Generate self-signed certificates for failed domains**
  - Create self-signed certificates as backup for failed Let's Encrypt requests
  - Add warnings about certificate validity in logs
  - Enable HTTPS with warnings rather than HTTP-only for critical services

#### **4.3 Review Error Handling Implementation**
- [ ] **Review fallback and error handling logic**
  - Verify graceful failure modes are implemented
  - Confirm logging covers failure scenarios
  - Double-check with Context7 for error handling patterns

### **Phase 5: Installation Flow Coordination**

#### **5.1 Service Readiness Integration**
- [ ] **Add service dependency checking**
  - Verify Kong/Supabase services are ready before certificate acquisition
  - Add health checks for each service before enabling HTTPS
  - Implement timeout and retry logic for service readiness

#### **5.2 Installation Process Sequencing**
- [ ] **Update installation sequence** in `full_stack_install.sh`
  1. Generate HTTP-only nginx configs
  2. Start all services with HTTP access
  3. Validate service readiness
  4. Acquire certificates per subdomain iteratively  
  5. Update configs to enable HTTPS per successful certificate
  6. Reload nginx progressively

#### **5.3 Review Installation Flow Changes**
- [ ] **Review updated installation sequencing**
  - Verify HTTP-only to HTTPS progression
  - Confirm service readiness checks are in place
  - Double-check with Context7 for installation flow best practices

## **Key Caveats and Considerations**

### **Technical Challenges**
1. **Certificate Reference Timing**: nginx configs must not reference certificates that don't exist yet
2. **Service Dependencies**: Certificate acquisition requires upstream services (Kong) to be ready
3. **DNS Prerequisites**: All subdomains must resolve before certificate requests
4. **Rate Limiting**: Let's Encrypt has strict rate limits - individual requests may be better than multi-domain
5. **Container Permissions**: Certificate files need proper ownership for nginx container (user 101)

### **Deployment Considerations**
1. **Backward Compatibility**: Ensure existing installations aren't broken
2. **Rollback Strategy**: HTTP-only mode should remain functional if HTTPS fails
3. **Monitoring**: Need visibility into which subdomains have valid certificates
4. **Security**: HTTP access should redirect to HTTPS once certificates are available

## **Discussion Notes**

### **User Input 1: Configuration Migration Priority**
- **Key Insight**: Must copy port 443 nginx settings from `setup_service_subdomains_ssl.sh` to `enable_https_redirects.sh` BEFORE deleting them
- **Rationale**: Preserve carefully crafted HTTPS server blocks to avoid losing configuration
- **Action**: Added Phase 0 as prerequisite step to handle configuration migration safely
- **Impact**: Ensures no loss of SSL configurations during the transition process

### **User Input 2: Port 80 Configuration Mismatch Identified**
- **Critical Issue**: **MISMATCH FOUND** between what `setup_service_subdomains_ssl.sh` generates and what `enable_https_redirects.sh` expects to replace
- **Current State**: 
  - `setup_service_subdomains_ssl.sh` generates HTTP server blocks that ALREADY contain HTTPS redirects (`return 301 https://\$host\$request_uri;`)
  - `enable_https_redirects.sh` looks for landing page patterns to replace: `# Serve landing page during setup`, `index index.html;`
- **Problem**: The sed patterns in `enable_https_redirects.sh` don't match what's actually generated
- **Required Fix**: Need to align HTTP server block generation with redirect replacement logic
- **Action Items Added**:
  - Phase 0.4: Audit and fix pattern matching between both scripts
  - Phase 1.1: Update HTTP server blocks to serve landing pages initially (not redirects)
  - Phase 3.1: Fix `enable_https_redirects.sh` to match actual generated content

### **User Input 3: Remove Major Testing, Focus on Review**
- **Decision**: Removed major testing items since script development is not on target server
- **New Approach**: Replace testing with review steps and Context7 documentation reference checks
- **Rationale**: Ensures code changes are reviewed for correctness without requiring live testing
- **Impact**: Tasklist now focuses on implementation review rather than validation testing

---
**Status**: Tasklist updated - Focus shifted to review and Context7 reference checks