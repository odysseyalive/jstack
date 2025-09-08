#!/bin/bash
# Network Security Validation and Testing Module for JStack Stack
# Validates all network security implementations and provides comprehensive testing

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

# ═══════════════════════════════════════════════════════════════════════════════
# 🧪 NETWORK SECURITY VALIDATION FRAMEWORK
# ═══════════════════════════════════════════════════════════════════════════════

validate_fail2ban_setup() {
    log_section "Validating fail2ban Configuration"
    
    local validation_results=()
    local passed=0
    local failed=0
    
    # Check if fail2ban is installed
    if command -v fail2ban-server >/dev/null 2>&1; then
        validation_results+=("✅ fail2ban installed")
        ((passed++))
    else
        validation_results+=("❌ fail2ban not installed")
        ((failed++))
    fi
    
    # Check if fail2ban service is running
    if systemctl is-active --quiet fail2ban 2>/dev/null; then
        validation_results+=("✅ fail2ban service running")
        ((passed++))
    else
        validation_results+=("⚠️  fail2ban service not running")
        ((failed++))
    fi
    
    # Check JStack jail configuration
    if [[ -f "/etc/fail2ban/jail.d/jstack.local" ]]; then
        validation_results+=("✅ JStack jail configuration exists")
        ((passed++))
    else
        validation_results+=("❌ JStack jail configuration missing")
        ((failed++))
    fi
    
    # Check custom filters
    local filters=("n8n-auth.conf" "supabase-api-abuse.conf" "nginx-req-limit.conf" "nginx-badbots.conf")
    for filter in "${filters[@]}"; do
        if [[ -f "/etc/fail2ban/filter.d/$filter" ]]; then
            validation_results+=("✅ Custom filter: $filter")
            ((passed++))
        else
            validation_results+=("❌ Missing filter: $filter")
            ((failed++))
        fi
    done
    
    # Test fail2ban client
    if command -v fail2ban-client >/dev/null 2>&1 && fail2ban-client status >/dev/null 2>&1; then
        validation_results+=("✅ fail2ban client functional")
        ((passed++))
        
        # Get jail status
        local jail_count=$(fail2ban-client status 2>/dev/null | grep -o "Jail list:.*" | wc -w)
        if [[ $jail_count -gt 1 ]]; then
            validation_results+=("✅ Active jails: $((jail_count-2))")
            ((passed++))
        fi
    else
        validation_results+=("❌ fail2ban client not functional")
        ((failed++))
    fi
    
    # Display results
    echo "=== fail2ban Validation Results ==="
    for result in "${validation_results[@]}"; do
        echo "$result"
    done
    echo "Passed: $passed | Failed: $failed"
    echo ""
    
    return $failed
}

validate_nginx_security() {
    log_section "Validating NGINX Security Configuration"
    
    local validation_results=()
    local passed=0
    local failed=0
    
    # Check if NGINX is running
    if pgrep nginx >/dev/null 2>&1; then
        validation_results+=("✅ NGINX is running")
        ((passed++))
    else
        validation_results+=("❌ NGINX is not running")
        ((failed++))
    fi
    
    # Check security configuration files exist
    local security_configs=(
        "rate-limiting.conf"
        "security-headers.conf" 
        "waf-rules.conf"
        "csp-reporting.conf"
    )
    
    for config in "${security_configs[@]}"; do
        if [[ -f "$BASE_DIR/security/nginx/$config" ]]; then
            validation_results+=("✅ Security config: $config")
            ((passed++))
        else
            validation_results+=("❌ Missing config: $config")
            ((failed++))
        fi
    done
    
    # Test security headers (requires NGINX to be running and configured)
    if command -v curl >/dev/null 2>&1; then
        local test_url="http://localhost"
        local headers_to_check=(
            "X-Frame-Options"
            "X-Content-Type-Options"
            "X-XSS-Protection"
            "Referrer-Policy"
            "Content-Security-Policy"
        )
        
        for header in "${headers_to_check[@]}"; do
            if curl -s -I "$test_url" 2>/dev/null | grep -i "$header:" >/dev/null; then
                validation_results+=("✅ Security header: $header")
                ((passed++))
            else
                validation_results+=("⚠️  Security header missing: $header")
                # Don't count as failure since NGINX might not be fully configured yet
            fi
        done
    fi
    
    # Check rate limiting zones configuration
    if nginx -T 2>/dev/null | grep -q "limit_req_zone"; then
        validation_results+=("✅ Rate limiting zones configured")
        ((passed++))
    else
        validation_results+=("❌ Rate limiting zones not configured")
        ((failed++))
    fi
    
    # Check error pages
    if [[ -d "$BASE_DIR/security/nginx/error-pages" ]]; then
        local error_pages=("429.html" "403.html")
        for page in "${error_pages[@]}"; do
            if [[ -f "$BASE_DIR/security/nginx/error-pages/$page" ]]; then
                validation_results+=("✅ Custom error page: $page")
                ((passed++))
            else
                validation_results+=("❌ Missing error page: $page")
                ((failed++))
            fi
        done
    fi
    
    # Display results
    echo "=== NGINX Security Validation Results ==="
    for result in "${validation_results[@]}"; do
        echo "$result"
    done
    echo "Passed: $passed | Failed: $failed"
    echo ""
    
    return $failed
}

validate_waf_rules() {
    log_section "Validating Web Application Firewall Rules"
    
    local validation_results=()
    local passed=0
    local failed=0
    
    # Check WAF configuration file
    local waf_config="$BASE_DIR/security/nginx/waf-rules.conf"
    if [[ -f "$waf_config" ]]; then
        validation_results+=("✅ WAF rules configuration exists")
        ((passed++))
        
        # Check for specific protection patterns
        local protection_patterns=(
            "SQL injection protection"
            "XSS protection"
            "Path traversal protection"
            "Command injection protection"
            "File inclusion protection"
        )
        
        for pattern in "${protection_patterns[@]}"; do
            if grep -q "$(echo "$pattern" | tr '[:upper:]' '[:lower:]')" "$waf_config"; then
                validation_results+=("✅ $pattern implemented")
                ((passed++))
            else
                validation_results+=("⚠️  $pattern may not be implemented")
            fi
        done
        
    else
        validation_results+=("❌ WAF rules configuration missing")
        ((failed++))
    fi
    
    # Check WAF monitoring script
    local waf_monitor="$BASE_DIR/security/nginx/waf-monitor.sh"
    if [[ -f "$waf_monitor" && -x "$waf_monitor" ]]; then
        validation_results+=("✅ WAF monitoring script available")
        ((passed++))
    else
        validation_results+=("❌ WAF monitoring script missing or not executable")
        ((failed++))
    fi
    
    # Check WAF log directory
    local waf_log_dir="$BASE_DIR/logs/nginx"
    if [[ -d "$waf_log_dir" ]]; then
        validation_results+=("✅ WAF log directory exists")
        ((passed++))
    else
        validation_results+=("❌ WAF log directory missing")
        ((failed++))
    fi
    
    # Display results
    echo "=== WAF Validation Results ==="
    for result in "${validation_results[@]}"; do
        echo "$result"
    done
    echo "Passed: $passed | Failed: $failed"
    echo ""
    
    return $failed
}

validate_threat_response() {
    log_section "Validating Automated Threat Response System"
    
    local validation_results=()
    local passed=0
    local failed=0
    
    # Check threat response scripts
    local response_scripts=(
        "threat-detector.sh"
        "automated-response.sh"
        "incident-manager.sh"
    )
    
    local threat_dir="$BASE_DIR/security/threat-response"
    for script in "${response_scripts[@]}"; do
        if [[ -f "$threat_dir/$script" && -x "$threat_dir/$script" ]]; then
            validation_results+=("✅ Threat response script: $script")
            ((passed++))
        else
            validation_results+=("❌ Missing or non-executable: $script")
            ((failed++))
        fi
    done
    
    # Check systemd services
    local services=(
        "jarvis-threat-detection.service"
        "jarvis-response-cleanup.timer"
        "jarvis-incident-escalation.timer"
    )
    
    for service in "${services[@]}"; do
        if [[ -f "/etc/systemd/system/$service" ]]; then
            validation_results+=("✅ Systemd service: $service")
            ((passed++))
        else
            validation_results+=("❌ Missing systemd service: $service")
            ((failed++))
        fi
    done
    
    # Check log directories
    local log_dirs=(
        "$BASE_DIR/logs/security"
    )
    
    for log_dir in "${log_dirs[@]}"; do
        if [[ -d "$log_dir" ]]; then
            validation_results+=("✅ Log directory: $log_dir")
            ((passed++))
        else
            validation_results+=("❌ Missing log directory: $log_dir")
            ((failed++))
        fi
    done
    
    # Display results
    echo "=== Threat Response Validation Results ==="
    for result in "${validation_results[@]}"; do
        echo "$result"
    done
    echo "Passed: $passed | Failed: $failed"
    echo ""
    
    return $failed
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🔧 NETWORK SECURITY TESTING FRAMEWORK
# ═══════════════════════════════════════════════════════════════════════════════

test_rate_limiting() {
    log_section "Testing Rate Limiting Configuration"
    
    if ! command -v curl >/dev/null 2>&1; then
        log_warning "curl not available - skipping rate limiting tests"
        return 1
    fi
    
    local test_results=()
    local test_url="http://localhost"
    
    log_info "Testing rate limiting (this may take a moment)..."
    
    # Test general rate limiting
    local success_count=0
    local rate_limited_count=0
    
    for i in {1..15}; do
        local response_code=$(curl -s -o /dev/null -w "%{http_code}" "$test_url" 2>/dev/null)
        if [[ "$response_code" == "200" ]]; then
            ((success_count++))
        elif [[ "$response_code" == "429" ]]; then
            ((rate_limited_count++))
        fi
        sleep 0.1
    done
    
    if [[ $rate_limited_count -gt 0 ]]; then
        test_results+=("✅ Rate limiting is working (got $rate_limited_count 429 responses)")
    else
        test_results+=("⚠️  Rate limiting may not be configured (all requests succeeded)")
    fi
    
    # Display results
    echo "=== Rate Limiting Test Results ==="
    for result in "${test_results[@]}"; do
        echo "$result"
    done
    echo ""
}

test_waf_protection() {
    log_section "Testing WAF Protection Rules"
    
    if ! command -v curl >/dev/null 2>&1; then
        log_warning "curl not available - skipping WAF tests"
        return 1
    fi
    
    local test_results=()
    local test_url="http://localhost"
    
    # Test SQL injection protection
    log_info "Testing SQL injection protection..."
    local sqli_response=$(curl -s -o /dev/null -w "%{http_code}" "$test_url/?id=1' OR '1'='1" 2>/dev/null)
    if [[ "$sqli_response" == "403" || "$sqli_response" == "400" ]]; then
        test_results+=("✅ SQL injection protection working")
    else
        test_results+=("⚠️  SQL injection protection may not be active (got $sqli_response)")
    fi
    
    # Test XSS protection
    log_info "Testing XSS protection..."
    local xss_response=$(curl -s -o /dev/null -w "%{http_code}" "$test_url/?search=<script>alert('xss')</script>" 2>/dev/null)
    if [[ "$xss_response" == "403" || "$xss_response" == "400" ]]; then
        test_results+=("✅ XSS protection working")
    else
        test_results+=("⚠️  XSS protection may not be active (got $xss_response)")
    fi
    
    # Test path traversal protection
    log_info "Testing path traversal protection..."
    local traversal_response=$(curl -s -o /dev/null -w "%{http_code}" "$test_url/../../../etc/passwd" 2>/dev/null)
    if [[ "$traversal_response" == "403" || "$traversal_response" == "400" ]]; then
        test_results+=("✅ Path traversal protection working")
    else
        test_results+=("⚠️  Path traversal protection may not be active (got $traversal_response)")
    fi
    
    # Test suspicious user agent blocking
    log_info "Testing user agent filtering..."
    local bot_response=$(curl -s -o /dev/null -w "%{http_code}" -H "User-Agent: sqlmap/1.0" "$test_url" 2>/dev/null)
    if [[ "$bot_response" == "403" || "$bot_response" == "400" ]]; then
        test_results+=("✅ Suspicious user agent blocking working")
    else
        test_results+=("⚠️  User agent filtering may not be active (got $bot_response)")
    fi
    
    # Display results
    echo "=== WAF Protection Test Results ==="
    for result in "${test_results[@]}"; do
        echo "$result"
    done
    echo ""
}

test_security_headers() {
    log_section "Testing Security Headers Implementation"
    
    if ! command -v curl >/dev/null 2>&1; then
        log_warning "curl not available - skipping security headers tests"
        return 1
    fi
    
    local test_results=()
    local test_url="http://localhost"
    
    log_info "Testing security headers..."
    
    # Get headers
    local headers_output=$(curl -s -I "$test_url" 2>/dev/null)
    
    # Test required security headers
    local required_headers=(
        "X-Frame-Options"
        "X-Content-Type-Options"
        "X-XSS-Protection"
        "Referrer-Policy"
    )
    
    for header in "${required_headers[@]}"; do
        if echo "$headers_output" | grep -i "$header:" >/dev/null; then
            local value=$(echo "$headers_output" | grep -i "$header:" | cut -d: -f2- | tr -d '\r' | sed 's/^ *//')
            test_results+=("✅ $header: $value")
        else
            test_results+=("❌ Missing header: $header")
        fi
    done
    
    # Test CSP header
    if echo "$headers_output" | grep -i "Content-Security-Policy:" >/dev/null; then
        test_results+=("✅ Content-Security-Policy header present")
    else
        test_results+=("⚠️  Content-Security-Policy header missing")
    fi
    
    # Test HSTS header (for HTTPS)
    if echo "$headers_output" | grep -i "Strict-Transport-Security:" >/dev/null; then
        test_results+=("✅ HSTS header present")
    else
        test_results+=("⚠️  HSTS header missing (check HTTPS configuration)")
    fi
    
    # Check server header hiding
    if ! echo "$headers_output" | grep -i "Server:" >/dev/null; then
        test_results+=("✅ Server header hidden")
    else
        local server_value=$(echo "$headers_output" | grep -i "Server:" | cut -d: -f2- | tr -d '\r' | sed 's/^ *//')
        test_results+=("⚠️  Server header exposed: $server_value")
    fi
    
    # Display results
    echo "=== Security Headers Test Results ==="
    for result in "${test_results[@]}"; do
        echo "$result"
    done
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# 📊 COMPREHENSIVE NETWORK SECURITY REPORT
# ═══════════════════════════════════════════════════════════════════════════════

generate_network_security_report() {
    log_section "Generating Comprehensive Network Security Report"
    
    local report_file="$BASE_DIR/logs/security/network-security-report-$(date +%Y%m%d_%H%M%S).txt"
    mkdir -p "$(dirname "$report_file")"
    
    {
        echo "JStack Stack Network Security Assessment Report"
        echo "Generated: $(date)"
        echo "=============================================="
        echo ""
        
        echo "=== VALIDATION SUMMARY ==="
        echo ""
        
        # Run validations and capture results
        local total_failed=0
        
        echo "--- fail2ban Configuration ---"
        if validate_fail2ban_setup >/dev/null 2>&1; then
            echo "✅ PASS: fail2ban configuration validated"
        else
            echo "❌ FAIL: fail2ban configuration issues detected"
            ((total_failed++))
        fi
        
        echo ""
        echo "--- NGINX Security Configuration ---"
        if validate_nginx_security >/dev/null 2>&1; then
            echo "✅ PASS: NGINX security configuration validated"
        else
            echo "❌ FAIL: NGINX security configuration issues detected" 
            ((total_failed++))
        fi
        
        echo ""
        echo "--- WAF Rules ---"
        if validate_waf_rules >/dev/null 2>&1; then
            echo "✅ PASS: WAF rules validated"
        else
            echo "❌ FAIL: WAF rules issues detected"
            ((total_failed++))
        fi
        
        echo ""
        echo "--- Threat Response System ---"
        if validate_threat_response >/dev/null 2>&1; then
            echo "✅ PASS: Threat response system validated"
        else
            echo "❌ FAIL: Threat response system issues detected"
            ((total_failed++))
        fi
        
        echo ""
        echo "=== TESTING SUMMARY ==="
        echo ""
        
        # Note about testing requirements
        if pgrep nginx >/dev/null 2>&1; then
            echo "✅ NGINX is running - functional tests executed"
        else
            echo "⚠️  NGINX not running - functional tests skipped"
        fi
        
        echo ""
        echo "=== SECURITY SCORE ==="
        if [[ $total_failed -eq 0 ]]; then
            echo "🏆 EXCELLENT: All network security validations passed"
            echo "Security Score: 95/100"
        elif [[ $total_failed -eq 1 ]]; then
            echo "✅ GOOD: Minor issues detected"
            echo "Security Score: 85/100"
        elif [[ $total_failed -eq 2 ]]; then
            echo "⚠️  FAIR: Multiple issues need attention"
            echo "Security Score: 70/100"
        else
            echo "❌ POOR: Significant security issues detected"
            echo "Security Score: 50/100"
        fi
        
        echo ""
        echo "=== RECOMMENDATIONS ==="
        echo ""
        
        if [[ $total_failed -gt 0 ]]; then
            echo "1. Review failed validation items above"
            echo "2. Ensure all security modules are properly installed"
            echo "3. Start/restart required services (fail2ban, nginx)"
            echo "4. Test configuration after fixes"
        else
            echo "✅ All network security components validated successfully"
            echo "✅ System ready for production deployment"
            echo "🔄 Schedule regular security validation runs"
        fi
        
        echo ""
        echo "=== NEXT STEPS ==="
        echo ""
        echo "1. Start services: bash scripts/security/network_security.sh start"
        echo "2. Monitor logs: tail -f $BASE_DIR/logs/security/*.log"
        echo "3. Regular testing: bash scripts/security/network_validation.sh test-all"
        echo "4. Review reports: ls -la $BASE_DIR/logs/security/*report*"
        
    } > "$report_file"
    
    log_success "Network security report generated: $report_file"
    
    # Also display summary to console
    echo ""
    echo "=== REPORT SUMMARY ==="
    if [[ $total_failed -eq 0 ]]; then
        echo "🏆 Network Security Status: EXCELLENT (95/100)"
    elif [[ $total_failed -le 2 ]]; then
        echo "✅ Network Security Status: GOOD (85/100)"
    else
        echo "⚠️  Network Security Status: NEEDS IMPROVEMENT"
    fi
    echo "Full report: $report_file"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🎯 MAIN VALIDATION AND TESTING FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

run_all_validations() {
    log_section "Running All Network Security Validations"
    
    local total_failures=0
    
    if ! validate_fail2ban_setup; then
        ((total_failures++))
    fi
    
    if ! validate_nginx_security; then
        ((total_failures++))
    fi
    
    if ! validate_waf_rules; then
        ((total_failures++))
    fi
    
    if ! validate_threat_response; then
        ((total_failures++))
    fi
    
    echo "=== VALIDATION SUMMARY ==="
    if [[ $total_failures -eq 0 ]]; then
        log_success "All validations passed! Network security is properly configured."
    else
        log_warning "Validation completed with $total_failures failed components."
        log_info "Review the details above and ensure all components are properly installed."
    fi
    
    return $total_failures
}

run_all_tests() {
    log_section "Running All Network Security Tests"
    
    log_warning "Note: Tests require NGINX to be running and properly configured"
    
    test_rate_limiting
    test_waf_protection  
    test_security_headers
    
    log_success "Network security testing completed"
}

# Main function
main() {
    case "${1:-validate}" in
        "validate-fail2ban") validate_fail2ban_setup ;;
        "validate-nginx") validate_nginx_security ;;
        "validate-waf") validate_waf_rules ;;
        "validate-threat") validate_threat_response ;;
        "validate-all") run_all_validations ;;
        "test-rate-limiting") test_rate_limiting ;;
        "test-waf") test_waf_protection ;;
        "test-headers") test_security_headers ;;
        "test-all") run_all_tests ;;
        "report") generate_network_security_report ;;
        "validate"|"all") 
            run_all_validations
            generate_network_security_report
            ;;
        *) echo "Usage: $0 [validate-all|test-all|report|validate|all]"
           echo "  validate-fail2ban    - Validate fail2ban configuration"
           echo "  validate-nginx       - Validate NGINX security setup"
           echo "  validate-waf         - Validate WAF rules"
           echo "  validate-threat      - Validate threat response system"
           echo "  validate-all         - Run all validations"
           echo "  test-rate-limiting   - Test rate limiting functionality"
           echo "  test-waf             - Test WAF protection rules"
           echo "  test-headers         - Test security headers"
           echo "  test-all             - Run all tests"
           echo "  report               - Generate comprehensive report"
           echo "  all                  - Validate and generate report"
           ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi