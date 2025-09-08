#!/bin/bash
# JStack Template Validation Framework
# Validates site templates for security, structure, and configuration compliance

set -e
source "${PROJECT_ROOT}/scripts/lib/common.sh"

# Template validation functions
validate_template_structure() {
    local template_path="$1"
    local template_name=$(basename "$template_path")
    
    log_info "Validating template structure: $template_name"
    
    # Check required files
    local required_files=(
        "template.json"
        "docker/Dockerfile"
        "nginx/site.conf.template"
    )
    
    for file in "${required_files[@]}"; do
        if [[ ! -f "$template_path/$file" ]]; then
            log_error "Missing required file: $file"
            return 1
        fi
    done
    
    # Check template.json schema
    if command -v jq &> /dev/null; then
        if ! jq empty "$template_path/template.json" 2>/dev/null; then
            log_error "Invalid JSON in template.json"
            return 1
        fi
        
        # Validate against schema
        local schema_path="${PROJECT_ROOT}/templates/shared/schema/template.schema.json"
        if [[ -f "$schema_path" ]] && command -v jsonschema &> /dev/null; then
            if ! jsonschema -i "$template_path/template.json" "$schema_path" 2>/dev/null; then
                log_error "template.json does not conform to schema"
                return 1
            fi
        fi
    fi
    
    log_success "Template structure validation passed"
    return 0
}

validate_template_security() {
    local template_path="$1"
    local template_name=$(basename "$template_path")
    
    log_info "Validating template security: $template_name"
    
    # Check Dockerfile security
    local dockerfile="$template_path/docker/Dockerfile"
    if [[ -f "$dockerfile" ]]; then
        # Check for rootless execution
        if ! grep -q "USER.*[^0]" "$dockerfile" && ! grep -q "user:.*[^0]" "$dockerfile"; then
            log_error "Dockerfile must specify non-root user"
            return 1
        fi
        
        # Check for --privileged flag (should not be present)
        if grep -q "\--privileged" "$dockerfile"; then
            log_error "Dockerfile contains privileged escalation"
            return 1
        fi
        
        # Check for no-new-privileges
        local compose_file="$template_path/docker/docker-compose.yml"
        if [[ -f "$compose_file" ]]; then
            if ! grep -q "no-new-privileges:true" "$compose_file"; then
                log_warning "Docker Compose should include no-new-privileges:true"
            fi
        fi
    fi
    
    # Check NGINX configuration
    local nginx_conf="$template_path/nginx/site.conf.template"
    if [[ -f "$nginx_conf" ]]; then
        # Check for security headers
        local security_headers=(
            "X-Frame-Options"
            "X-Content-Type-Options"
            "X-XSS-Protection"
            "Strict-Transport-Security"
        )
        
        for header in "${security_headers[@]}"; do
            if ! grep -q "$header" "$nginx_conf"; then
                log_warning "NGINX config missing security header: $header"
            fi
        done
        
        # Check for rate limiting
        if ! grep -q "limit_req" "$nginx_conf"; then
            log_warning "NGINX config should include rate limiting"
        fi
    fi
    
    log_success "Template security validation passed"
    return 0
}

validate_template_config() {
    local template_path="$1"
    local template_name=$(basename "$template_path")
    
    log_info "Validating template configuration: $template_name"
    
    # Parse template.json
    local template_json="$template_path/template.json"
    if [[ ! -f "$template_json" ]]; then
        log_error "template.json not found"
        return 1
    fi
    
    # Extract and validate required fields
    local name version type
    if command -v jq &> /dev/null; then
        name=$(jq -r '.name // empty' "$template_json")
        version=$(jq -r '.version // empty' "$template_json")
        type=$(jq -r '.type // empty' "$template_json")
        
        if [[ -z "$name" ]]; then
            log_error "Template name is required"
            return 1
        fi
        
        if [[ -z "$version" ]]; then
            log_error "Template version is required"
            return 1
        fi
        
        if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
            log_error "Template version must follow semantic versioning"
            return 1
        fi
        
        if [[ -z "$type" ]]; then
            log_error "Template type is required"
            return 1
        fi
        
        # Validate Docker configuration
        local docker_image=$(jq -r '.docker.image // empty' "$template_json")
        if [[ -z "$docker_image" ]]; then
            log_error "Docker image is required"
            return 1
        fi
        
        # Validate NGINX configuration
        local nginx_template=$(jq -r '.nginx.template // empty' "$template_json")
        if [[ -z "$nginx_template" ]]; then
            log_error "NGINX template type is required"
            return 1
        fi
    fi
    
    log_success "Template configuration validation passed"
    return 0
}

validate_template_compatibility() {
    local template_path="$1"
    local template_name=$(basename "$template_path")
    
    log_info "Validating template compatibility: $template_name"
    
    # Check JStack compatibility
    local template_json="$template_path/template.json"
    
    if command -v jq &> /dev/null; then
        # Check network compatibility
        local docker_compose="$template_path/docker/docker-compose.yml"
        if [[ -f "$docker_compose" ]]; then
            if ! grep -q "jstack-private" "$docker_compose"; then
                log_error "Docker Compose must use jstack-private network"
                return 1
            fi
        fi
        
        # Check SSL configuration
        local ssl_enabled=$(jq -r '.ssl.enabled // true' "$template_json")
        if [[ "$ssl_enabled" != "true" ]]; then
            log_warning "SSL should be enabled for production deployments"
        fi
        
        # Check compliance profile
        local compliance_profile=$(jq -r '.compliance.profile // "default"' "$template_json")
        local valid_profiles=("default" "strict" "enterprise" "healthcare" "financial")
        
        if [[ ! " ${valid_profiles[@]} " =~ " ${compliance_profile} " ]]; then
            log_error "Invalid compliance profile: $compliance_profile"
            return 1
        fi
    fi
    
    log_success "Template compatibility validation passed"
    return 0
}

validate_template() {
    local template_path="$1"
    
    if [[ -z "$template_path" ]]; then
        log_error "Template path is required"
        return 1
    fi
    
    if [[ ! -d "$template_path" ]]; then
        log_error "Template directory not found: $template_path"
        return 1
    fi
    
    log_section "Template Validation"
    log_info "Validating template: $(basename "$template_path")"
    
    # Run all validation checks
    if ! validate_template_structure "$template_path"; then
        log_error "Template structure validation failed"
        return 1
    fi
    
    if ! validate_template_security "$template_path"; then
        log_error "Template security validation failed"
        return 1
    fi
    
    if ! validate_template_config "$template_path"; then
        log_error "Template configuration validation failed"
        return 1
    fi
    
    if ! validate_template_compatibility "$template_path"; then
        log_error "Template compatibility validation failed"
        return 1
    fi
    
    log_success "Template validation completed successfully"
    return 0
}

list_available_templates() {
    local templates_dir="${PROJECT_ROOT}/templates"
    
    if [[ ! -d "$templates_dir" ]]; then
        log_error "Templates directory not found: $templates_dir"
        return 1
    fi
    
    log_info "Available templates:"
    
    for template_dir in "$templates_dir"/*; do
        if [[ -d "$template_dir" && -f "$template_dir/template.json" ]]; then
            local template_name=$(basename "$template_dir")
            local name version description
            
            if command -v jq &> /dev/null; then
                name=$(jq -r '.name // empty' "$template_dir/template.json" 2>/dev/null)
                version=$(jq -r '.version // empty' "$template_dir/template.json" 2>/dev/null)
                description=$(jq -r '.description // empty' "$template_dir/template.json" 2>/dev/null)
                
                log_info "  $template_name:"
                [[ -n "$name" ]] && log_info "    Name: $name"
                [[ -n "$version" ]] && log_info "    Version: $version"
                [[ -n "$description" ]] && log_info "    Description: $description"
            else
                log_info "  $template_name (jq not available for details)"
            fi
        fi
    done
}

# Export functions for use in other scripts
export -f validate_template
export -f validate_template_structure
export -f validate_template_security
export -f validate_template_config
export -f validate_template_compatibility
export -f list_available_templates