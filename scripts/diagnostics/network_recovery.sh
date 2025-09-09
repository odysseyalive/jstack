#!/bin/bash
# JarvisJR Stack - Network Failure Recovery and Diagnostic Tool
# Enhanced root cause analysis implementation with systematic recovery

# Set script directory and source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

# Load configuration
load_config
export_config

# ═══════════════════════════════════════════════════════════════════════════════
# 🔍 NETWORK FAILURE DIAGNOSTIC PROCEDURES
# ═══════════════════════════════════════════════════════════════════════════════

diagnose_network_failure() {
    log_section "Network Failure Diagnostic Analysis"
    
    echo ""
    echo "🔍 PHASE 3: ENHANCED ROOT CAUSE ANALYSIS RESULTS"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    # Phase 1: Docker daemon assessment
    log_info "Phase 1: Docker Daemon Assessment"
    echo "  Docker Version: $(docker --version 2>/dev/null || echo '❌ Not accessible')"
    echo "  Docker Status: $(systemctl is-active docker 2>/dev/null || echo '❌ Unknown')"
    echo "  Docker Socket: $(ls -la /var/run/docker.sock 2>/dev/null | awk '{print $1, $3, $4}' || echo '❌ Not found')"
    echo "  Docker Info: $(docker info >/dev/null 2>&1 && echo '✅ Accessible' || echo '❌ Access denied')"
    echo ""
    
    # Phase 2: Network state analysis
    log_info "Phase 2: Current Network State Analysis"
    echo "  Current Networks:"
    if docker network ls >/dev/null 2>&1; then
        docker network ls --format "    {{.Name}} ({{.Driver}}) - {{.Scope}}"
    elif sudo docker network ls >/dev/null 2>&1; then
        sudo docker network ls --format "    {{.Name}} ({{.Driver}}) - {{.Scope}}"
    else
        echo "    ❌ Cannot access Docker networks (authentication failure)"
    fi
    echo ""
    
    echo "  Expected Networks Analysis:"
    local expected_networks=("jstack_network:172.20.0.0/16" "jstack-public:172.21.0.0/16" "jstack-private:172.22.0.0/16")
    local missing_count=0
    
    for network_config in "${expected_networks[@]}"; do
        IFS=':' read -r network subnet <<< "$network_config"
        
        if docker network ls --format '{{.Name}}' 2>/dev/null | grep -q "^${network}$" || \
           sudo docker network ls --format '{{.Name}}' 2>/dev/null | grep -q "^${network}$"; then
            echo "    ✅ $network ($subnet)"
        else
            echo "    ❌ $network ($subnet) - MISSING"
            ((missing_count++))
        fi
    done
    
    if [[ $missing_count -gt 0 ]]; then
        echo ""
        echo "  🚨 ROOT CAUSE IDENTIFIED: $missing_count/3 required networks missing"
        echo "     This prevents Supabase containers from starting (external network dependency failure)"
    fi
    echo ""
    
    # Phase 3: Authentication analysis  
    log_info "Phase 3: Authentication Analysis (Primary Failure Point)"
    echo "  Current User: $(whoami)"
    echo "  Docker Group Membership: $(groups | grep -q docker && echo '✅ Yes' || echo '❌ No')"
    
    # Test different authentication methods
    if sudo -n true >/dev/null 2>&1; then
        echo "  Sudo Access: ✅ Passwordless available"
        
        if sudo -n docker network ls >/dev/null 2>&1; then
            echo "  Docker Sudo Access: ✅ Available"
        else
            echo "  Docker Sudo Access: ❌ Blocked (sudo works but Docker access fails)"
        fi
    else
        echo "  Sudo Access: ❌ Requires password (PRIMARY ROOT CAUSE)"
        echo "  Docker Sudo Access: ❌ Unavailable (depends on sudo access)"
    fi
    
    if docker network ls >/dev/null 2>&1; then
        echo "  Direct Docker Access: ✅ Available"
    else
        echo "  Direct Docker Access: ❌ Requires group membership refresh"
    fi
    echo ""
    
    # Phase 4: Setup process analysis
    log_info "Phase 4: Setup Process State Analysis"
    
    if [[ -d "/home/jarvis/jstack" ]]; then
        echo "  Service Directory: ✅ /home/jarvis/jstack exists"
        
        local subdirs=("services" "logs" "backups" "ssl")
        for subdir in "${subdirs[@]}"; do
            if [[ -d "/home/jarvis/jstack/$subdir" ]]; then
                echo "    ✅ $subdir/ exists"
            else
                echo "    ❌ $subdir/ missing (setup incomplete)"
            fi
        done
    else
        echo "  Service Directory: ❌ /home/jarvis/jstack missing (setup never started)"
    fi
    
    if [[ -f "/etc/sudoers.d/jarvis-stack" ]]; then
        echo "  Sudo Configuration: ✅ /etc/sudoers.d/jarvis-stack exists"
    else
        echo "  Sudo Configuration: ❌ Missing (explains authentication failure)"
    fi
    echo ""
    
    # Phase 5: Recovery recommendations
    log_info "Phase 5: Systematic Recovery Plan"
    echo ""
    
    if ! sudo -n docker network ls >/dev/null 2>&1; then
        echo "  🎯 PRIORITY 1: Configure Passwordless Sudo Access"
        echo "     Problem: Network creation requires sudo access but authentication fails"
        echo "     Solution: ./jstack.sh --configure-sudo"
        echo "     Alternative: Manual sudo configuration (see documentation)"
        echo ""
    fi
    
    if [[ $missing_count -gt 0 ]]; then
        echo "  🎯 PRIORITY 2: Create Missing Docker Networks"
        echo "     Problem: $missing_count/3 required networks missing"
        echo "     Solution Commands:"
        for network_config in "${expected_networks[@]}"; do
            IFS=':' read -r network subnet <<< "$network_config"
            if ! docker network ls --format '{{.Name}}' 2>/dev/null | grep -q "^${network}$" && \
               ! sudo docker network ls --format '{{.Name}}' 2>/dev/null | grep -q "^${network}$"; then
                local gateway=$(echo "$subnet" | sed 's/0\.0\/16/0.1/')
                echo "       sudo docker network create $network --driver bridge --subnet=$subnet --gateway=$gateway"
            fi
        done
        echo ""
    fi
    
    echo "  🎯 PRIORITY 3: Resume Installation Process"
    echo "     Problem: Installation stopped at network creation phase"
    echo "     Solution: ./jstack.sh --install (will skip completed phases)"
    echo ""
    
    echo "  🔍 VERIFICATION COMMANDS:"
    echo "     docker network ls | grep jstack    # Verify networks exist"
    echo "     docker ps --filter name=supabase   # Check container status after fix"
    echo ""
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🛠️ SYSTEMATIC RECOVERY IMPLEMENTATION
# ═══════════════════════════════════════════════════════════════════════════════

recover_networks() {
    log_section "Systematic Network Recovery"
    
    echo ""
    echo "🛠️ IMPLEMENTING SYSTEMATIC RECOVERY SOLUTION"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    # Step 1: Validate prerequisites
    log_info "Step 1: Validating Recovery Prerequisites"
    
    # Check Docker daemon
    if ! docker info >/dev/null 2>&1 && ! sudo docker info >/dev/null 2>&1; then
        log_error "Docker daemon not accessible - cannot proceed with recovery"
        log_info "Please ensure Docker is installed and running"
        return 1
    fi
    log_success "Docker daemon accessible"
    
    # Determine authentication method
    local docker_cmd=""
    if sudo -n docker network ls >/dev/null 2>&1; then
        docker_cmd="sudo docker"
        log_success "Using passwordless sudo for recovery"
    elif docker network ls >/dev/null 2>&1; then
        docker_cmd="docker"
        log_success "Using direct docker access for recovery"
    else
        log_warning "Recovery requires sudo authentication"
        log_info "You may be prompted for your password"
        docker_cmd="sudo docker"
    fi
    echo ""
    
    # Step 2: Create missing networks
    log_info "Step 2: Creating Missing Docker Networks"
    
    local expected_networks=("jstack_network:172.20.0.0/16:172.20.0.1" "jstack-public:172.21.0.0/16:172.21.0.1" "jstack-private:172.22.0.0/16:172.22.0.1")
    local created_count=0
    local existing_count=0
    
    for network_config in "${expected_networks[@]}"; do
        IFS=':' read -r network subnet gateway <<< "$network_config"
        
        # Check if network already exists
        if $docker_cmd network ls --format '{{.Name}}' 2>/dev/null | grep -q "^${network}$"; then
            log_info "Network '$network' already exists - skipping"
            ((existing_count++))
            continue
        fi
        
        # Create network
        log_info "Creating network '$network' ($subnet)"
        if $docker_cmd network create "$network" --driver bridge --subnet="$subnet" --gateway="$gateway" 2>/dev/null; then
            log_success "✅ Created network '$network'"
            ((created_count++))
        else
            log_error "❌ Failed to create network '$network'"
            log_info "This may prevent Supabase containers from starting"
            
            # Diagnostic information
            log_info "Troubleshooting info:"
            log_info "  Subnet conflict check: $($docker_cmd network ls --format '{{.Name}} {{.Driver}}' | grep bridge || echo 'No conflicts detected')"
            log_info "  Docker daemon status: $(systemctl is-active docker 2>/dev/null || echo 'unknown')"
        fi
    done
    echo ""
    
    # Step 3: Validate recovery success
    log_info "Step 3: Validating Network Recovery"
    
    local total_networks=0
    total_networks=$($docker_cmd network ls --format '{{.Name}}' 2>/dev/null | grep -E "^(jstack_network|jstack-public|jstack-private)$" | wc -l)
    
    if [[ "$total_networks" -eq 3 ]]; then
        log_success "✅ Network recovery successful: All 3 networks present"
        echo ""
        echo "Networks created/verified:"
        $docker_cmd network ls --format "  {{.Name}} ({{.Driver}}) - {{.Scope}}" | grep jstack
        echo ""
        
        log_success "🎉 RECOVERY COMPLETE - Supabase containers should now start successfully"
        echo ""
        log_info "Next steps:"
        log_info "  1. Test container startup: docker-compose up -d"
        log_info "  2. Resume installation: ./jstack.sh --install"
        log_info "  3. Check service health: docker ps --filter name=supabase"
        
    else
        log_warning "⚠️ Partial network recovery: $total_networks/3 networks present"
        log_info "You may need to manually resolve remaining network issues"
        
        echo ""
        echo "Current network state:"
        $docker_cmd network ls --format "  {{.Name}} ({{.Driver}}) - {{.Scope}}"
    fi
    echo ""
    
    return 0
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🔧 ENHANCED SETUP VALIDATION
# ═══════════════════════════════════════════════════════════════════════════════

validate_setup_prerequisites() {
    log_section "Setup Prerequisites Validation"
    
    echo ""
    echo "🔧 ENHANCED SETUP VALIDATION (PREVENTION MEASURES)"
    echo "═══════════════════════════════════════════════════════════════"
    echo ""
    
    local validation_passed=true
    
    # Validate sudo access
    log_info "Validating Sudo Access for Network Operations"
    if sudo -n docker network ls >/dev/null 2>&1; then
        log_success "✅ Passwordless sudo access confirmed for Docker"
    elif sudo docker network ls >/dev/null 2>&1; then
        log_warning "⚠️ Sudo access available but requires password"
        log_info "   Recommendation: Configure passwordless sudo with ./jstack.sh --configure-sudo"
    else
        log_error "❌ Sudo access unavailable for Docker operations"
        log_error "   This will cause network creation to fail during setup"
        validation_passed=false
    fi
    echo ""
    
    # Validate Docker group membership
    log_info "Validating Docker Group Membership"
    if groups | grep -q docker; then
        log_success "✅ User in docker group"
        
        # Test if group membership is active
        if docker network ls >/dev/null 2>&1; then
            log_success "✅ Docker group membership active"
        else
            log_warning "⚠️ Docker group membership exists but not active"
            log_info "   May require logout/login or newgrp docker"
        fi
    else
        log_warning "⚠️ User not in docker group"
        log_info "   Setup will rely on sudo access for Docker operations"
    fi
    echo ""
    
    # Validate network requirements
    log_info "Validating Network Requirements"
    local required_subnets=("172.20.0.0/16" "172.21.0.0/16" "172.22.0.0/16")
    
    for subnet in "${required_subnets[@]}"; do
        # Check for existing network conflicts
        if docker network ls --format '{{.Name}} {{.IPAM}}' 2>/dev/null | grep -q "$subnet" || \
           sudo docker network ls --format '{{.Name}} {{.IPAM}}' 2>/dev/null | grep -q "$subnet"; then
            log_warning "⚠️ Subnet $subnet already in use"
            log_info "   May cause network creation conflicts during setup"
        else
            log_success "✅ Subnet $subnet available"
        fi
    done
    echo ""
    
    # Overall validation result
    if $validation_passed; then
        log_success "🎉 Setup prerequisites validation PASSED"
        log_info "   System ready for JarvisJR Stack installation"
    else
        log_error "❌ Setup prerequisites validation FAILED"
        log_error "   Installation will likely fail - resolve issues first"
    fi
    echo ""
    
    return $($validation_passed && echo 0 || echo 1)
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🚀 MAIN ORCHESTRATION
# ═══════════════════════════════════════════════════════════════════════════════

main() {
    case "${1:-diagnose}" in
        "diagnose"|"analyze")
            diagnose_network_failure
            ;;
        "recover"|"fix")
            recover_networks
            ;;
        "validate"|"check")
            validate_setup_prerequisites
            ;;
        "full"|"complete")
            diagnose_network_failure
            echo ""
            read -p "Proceed with network recovery? [y/N]: " confirm
            if [[ $confirm =~ ^[Yy] ]]; then
                recover_networks
            else
                log_info "Recovery cancelled - run '$0 recover' when ready"
            fi
            ;;
        *)
            echo "JarvisJR Stack - Network Failure Recovery Tool"
            echo ""
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  diagnose    - Perform comprehensive network failure analysis"
            echo "  recover     - Execute systematic network recovery"
            echo "  validate    - Validate setup prerequisites (prevention)"
            echo "  full        - Complete analysis and recovery (interactive)"
            echo ""
            echo "Examples:"
            echo "  $0 diagnose    # Understand why Supabase containers fail"
            echo "  $0 recover     # Fix missing Docker networks"
            echo "  $0 validate    # Check system before installation"
            echo "  $0 full        # Complete diagnostic and recovery flow"
            echo ""
            exit 1
            ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi