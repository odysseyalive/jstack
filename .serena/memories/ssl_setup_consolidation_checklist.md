# SSL Setup Script Consolidation - Comprehensive Checklist

## **Objective**
Consolidate the two-phase SSL setup process into a single script (`setup_service_subdomains_ssl.sh`) that can handle both HTTP-only and full HTTPS configurations based on parameters.

## **Current Problem Analysis**
- ❌ `full_stack_install.sh` never calls `setup_service_subdomains_for_certbot.sh`
- ❌ `setup_service_subdomains_ssl.sh` has SSL bootstrap functionality disabled
- ❌ Nginx configs are generated with HTTPS sections that reference non-existent certificates
- ❌ `--install-site` workflow is broken due to disabled SSL functions
- ❌ Two separate scripts create maintenance overhead and potential inconsistencies

## **Solution Overview**
Create a single script that accepts parameters to control SSL section generation:
- `--http-only`: Generate HTTP configs for ACME challenges only
- `--with-ssl`: Generate full HTTP + HTTPS configs after certificates exist

## **Implementation Checklist**

### **Phase 1: Script Parameter Handling**
- [ ] Modify `setup_service_subdomains_ssl.sh` to accept command-line parameters
- [ ] Add parameter parsing logic for `--http-only` and `--with-ssl` flags
- [ ] Add usage/help documentation for the new parameters
- [ ] Set default behavior (currently generates full configs)

### **Phase 2: Conditional Config Generation**
- [ ] Modify `generate_nginx_configs()` function to conditionally generate HTTPS sections
- [ ] Update `default.conf` generation logic
- [ ] Update `api.${DOMAIN}.conf` generation logic  
- [ ] Update `studio.${DOMAIN}.conf` generation logic
- [ ] Update `n8n.${DOMAIN}.conf` generation logic
- [ ] Ensure HTTP sections (port 80) are always generated for ACME challenges

### **Phase 3: Re-enable SSL Bootstrap Functionality**
- [ ] Uncomment and fix the `bootstrap_ssl_certificates()` function call
- [ ] Test SSL certificate acquisition logic
- [ ] Ensure proper error handling for failed certificate requests
- [ ] Verify self-signed certificate fallback works correctly

### **Phase 4: Update Installation Process**
- [ ] Modify `full_stack_install.sh` to call the script in two phases:
  - [ ] Phase 1: `setup_service_subdomains_ssl.sh --http-only`
  - [ ] Phase 2: `setup_service_subdomains_ssl.sh --with-ssl` (after certbot)
- [ ] Remove duplicate SSL certificate logic from `full_stack_install.sh`
- [ ] Ensure proper nginx restart sequence between phases

### **Phase 5: Fix Certificate Path Consistency**
- [ ] Decide on certificate strategy:
  - [ ] Option A: Multi-domain certificates (single cert for all subdomains)
  - [ ] Option B: Individual certificates per subdomain
- [ ] Update nginx config templates to use consistent certificate paths
- [ ] Update certbot commands to match chosen strategy
- [ ] Verify certificate file permissions are set correctly

### **Phase 6: Fix --install-site Workflow**
- [ ] Update `jstack.sh` `--install-site` logic to work with new script
- [ ] Test `generate_site_nginx_config()` function
- [ ] Test `install_site_ssl_certificate()` function
- [ ] Ensure new site domains are properly added to certificates

### **Phase 7: Clean Up Obsolete Scripts**
- [ ] Evaluate if `setup_service_subdomains_for_certbot.sh` can be removed
- [ ] Update any references to the old script in documentation
- [ ] Remove duplicate functions between scripts

### **Phase 8: Testing & Validation**
- [ ] Test HTTP-only config generation produces valid nginx configs
- [ ] Test nginx starts successfully with HTTP-only configs
- [ ] Test ACME challenge endpoints are accessible
- [ ] Test certificate acquisition works with HTTP-only configs
- [ ] Test full config generation produces valid nginx configs with SSL
- [ ] Test nginx reloads/restarts successfully after SSL config update
- [ ] Test `--install-site` workflow end-to-end
- [ ] Test certificate renewal process

### **Phase 9: Documentation Updates**
- [ ] Update script header comments with new usage examples
- [ ] Update any installation documentation referencing the old process
- [ ] Document the new two-phase calling convention
- [ ] Update troubleshooting guides if needed

## **Key Technical Decisions Needed**

### **Certificate Strategy**
- **Multi-domain approach**: Single certificate with multiple SANs (current `bootstrap_ssl_certificates()`)
  - ✅ More efficient for Let's Encrypt rate limits
  - ❌ All domains must be ready simultaneously
  
- **Individual certificate approach**: Separate certificate per subdomain (current `full_stack_install.sh`)
  - ✅ Domains can be added incrementally
  - ❌ More complex certificate management

### **Config Template Strategy**
- **Option A**: Single template with conditional sections
- **Option B**: Separate templates for HTTP-only vs full configs
- **Recommendation**: Option A for consistency

## **Risk Assessment**
- **Low Risk**: Parameter handling and conditional config generation
- **Medium Risk**: SSL certificate acquisition logic changes
- **High Risk**: Changes to main installation flow in `full_stack_install.sh`

## **Success Criteria**
- [ ] Single script handles both HTTP-only and full SSL configurations
- [ ] `jstack.sh --install` works end-to-end without SSL errors
- [ ] `jstack.sh --install-site` works for adding new sites
- [ ] Nginx starts successfully in both phases
- [ ] SSL certificates are acquired successfully
- [ ] All subdomains are accessible via HTTPS after installation
- [ ] No duplicate code between scripts

## **Rollback Plan**
- Keep backup of current `setup_service_subdomains_ssl.sh`
- Keep current `setup_service_subdomains_for_certbot.sh` until testing complete
- Test changes in isolated environment before production use