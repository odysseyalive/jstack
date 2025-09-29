Phase 2: Nginx Configuration Switch

1. Current nginx config analysis:
   - Verify existing nginx.conf and subdomain configs (api.jstack.example, admin.jstack.example)
   - Check for HTTP→HTTPS redirect rules in current configs

2. Script comparison:
   - `enable_https_redirects.sh` handles top-level HTTP→HTTPS redirects
   - `setup_service_subdomains_ssl.sh` adds SSL for subdomains (api/admin) with their own redirects

3. Critical steps:
   - Backup current nginx configs before deletion
   - Delete outdated nginx configs (api.jstack.example, admin.jstack.example)
   - Run `setup_service_subdomains_ssl.sh` to generate new subdomain configs
   - Validate redirects using `curl -I http://api.jstack.example`

4. Potential pitfalls:
   - Existing redirects may conflict with new subdomain configs
   - Certbot certificates might need revalidation after switch
   - Firewall rules (ufw) may need adjustment for HTTPS traffic

5. Verification plan:
   - Test HTTP→HTTPS redirects for all subdomains
   - Validate certificate expiration via `openssl x509`
   - Confirm service health via `docker ps` and API endpoints

6. Documentation updates:
   - Update README.md to reflect new script
   - Add note in installation docs about subdomain SSL configuration

7. Safety checks:
   - Run dry run first (`./jstack.sh --dry-run`)
   - Ensure no live services are affected during switch