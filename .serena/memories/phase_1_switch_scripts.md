Phase 1: Switching from setup_service_subdomains_ssl.sh to setup_service_subdomains_for_certbot.sh

1. Verify current script paths and existence:
   - Confirm setup_service_subdomains_ssl.sh exists in scripts/core/
   - Confirm setup_service_subdomains_for_certbot.sh exists in scripts/core/

2. Compare script contents:
   - Use diff to identify key differences between the two scripts
   - Focus on certificate management sections (e.g., certbot, nginx, openssl commands)

3. Prepare for replacement:
   - Create backup of current script (setup_service_subdomains_ssl.sh)
   - Ensure no dependencies on the old script are present in other files

4. Update script references:
   - Check all other scripts and configuration files for references to the old script
   - Replace any references with the new script

5. Initial validation:
   - Run dry run of new script to check for errors
   - Verify certificate renewal and subdomain setup works as expected

6. Document changes:
   - Update README.md to reflect new script
   - Add note in installation documentation about the switch
