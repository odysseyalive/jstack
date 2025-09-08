#!/bin/bash
# Dry-Run Output Validation Framework
# Systematic validation and scoring methodology for JStack dry-run operations

set -e

# Get script directory and source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

# Load configuration
load_config
export_config

# ═══════════════════════════════════════════════════════════════════════════════
# 📊 VALIDATION FRAMEWORK CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

# Scoring weights (total must equal 100)
readonly TECHNICAL_ACCURACY_WEIGHT=30
readonly IMPLEMENTATION_ALIGNMENT_WEIGHT=25
readonly COMPLETENESS_WEIGHT=20
readonly USER_EXPERIENCE_WEIGHT=15
readonly DOCUMENTATION_QUALITY_WEIGHT=10

# Scoring thresholds
readonly EXCELLENT_THRESHOLD=90
readonly GOOD_THRESHOLD=75
readonly ACCEPTABLE_THRESHOLD=60
readonly NEEDS_IMPROVEMENT_THRESHOLD=40

# Validation results storage
VALIDATION_RESULTS=()
VALIDATION_SCORE=0
VALIDATION_ISSUES=()
VALIDATION_RECOMMENDATIONS=()

# ═══════════════════════════════════════════════════════════════════════════════
# 🔍 CORE VALIDATION FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Capture dry-run output for analysis
capture_dry_run_output() {
    local operation="$1"
    local output_file="$2"
    
    log_info "Capturing dry-run output for operation: $operation"
    
    case "$operation" in
        "install")
            DRY_RUN=true bash "${PROJECT_ROOT}/jstack.sh" --dry-run > "$output_file" 2>&1 || true
            ;;
        "uninstall")
            DRY_RUN=true bash "${PROJECT_ROOT}/jstack.sh" --dry-run --uninstall > "$output_file" 2>&1 || true
            ;;
        "backup")
            DRY_RUN=true bash "${PROJECT_ROOT}/jstack.sh" --dry-run --backup test-backup > "$output_file" 2>&1 || true
            ;;
        "sync")
            DRY_RUN=true bash "${PROJECT_ROOT}/jstack.sh" --dry-run --sync > "$output_file" 2>&1 || true
            ;;
        "ssl")
            DRY_RUN=true bash "${PROJECT_ROOT}/jstack.sh" --dry-run --configure-ssl > "$output_file" 2>&1 || true
            ;;
        *)
            log_error "Unknown operation: $operation"
            return 1
            ;;
    esac
    
    if [[ -f "$output_file" ]]; then
        log_success "Dry-run output captured: $output_file ($(wc -l < "$output_file") lines)"
        return 0
    else
        log_error "Failed to capture dry-run output"
        return 1
    fi
}

# Validate technical accuracy of dry-run output
validate_technical_accuracy() {
    local output_file="$1"
    local operation="$2"
    local score=0
    local max_score=100
    
    log_info "Validating technical accuracy for $operation"
    
    # Check for variable substitution issues
    if ! grep -q '\$[A-Z_]*}' "$output_file" && ! grep -q '\${[^}]*}' "$output_file"; then
        score=$((score + 25))
        log_success "✓ No variable substitution issues found"
    else
        local var_issues=$(grep -o '\$[A-Z_]*}' "$output_file" | wc -l)
        log_error "✗ Variable substitution issues found: $var_issues instances"
        VALIDATION_ISSUES+=("Variable substitution problems in $operation dry-run output")
    fi
    
    # Check for proper service names and ports
    if grep -q "$SERVICE_USER" "$output_file" && grep -q "$BASE_DIR" "$output_file"; then
        score=$((score + 25))
        log_success "✓ Service configuration variables properly populated"
    else
        log_error "✗ Service configuration variables missing or empty"
        VALIDATION_ISSUES+=("Service configuration variables not populated in $operation")
    fi
    
    # Check for domain and subdomain references
    if grep -q "$DOMAIN" "$output_file" && grep -q "$SUPABASE_SUBDOMAIN" "$output_file"; then
        score=$((score + 25))
        log_success "✓ Domain configuration properly referenced"
    else
        log_error "✗ Domain configuration missing or incomplete"
        VALIDATION_ISSUES+=("Domain configuration not properly referenced in $operation")
    fi
    
    # Check for proper resource specifications
    if grep -q "Memory Usage" "$output_file" || grep -q "memory" "$output_file"; then
        score=$((score + 25))
        log_success "✓ Resource specifications included"
    else
        log_warning "△ Limited resource information in output"
        score=$((score + 10))
    fi
    
    log_info "Technical accuracy score: $score/$max_score"
    return $score
}

# Validate implementation alignment
validate_implementation_alignment() {
    local output_file="$1"
    local operation="$2"
    local score=0
    local max_score=100
    
    log_info "Validating implementation alignment for $operation"
    
    case "$operation" in
        "install")
            # Check for proper phase structure
            if grep -q "SYSTEM SETUP PHASE" "$output_file" && \
               grep -q "CONTAINER DEPLOYMENT PHASE" "$output_file" && \
               grep -q "SSL CONFIGURATION PHASE" "$output_file"; then
                score=$((score + 40))
                log_success "✓ Installation phases properly documented"
            else
                log_error "✗ Installation phase structure incomplete"
                VALIDATION_ISSUES+=("Installation phase documentation incomplete")
            fi
            
            # Check for service dependency order
            if grep -q "dependency order" "$output_file"; then
                score=$((score + 30))
                log_success "✓ Service dependencies mentioned"
            else
                log_warning "△ Service dependencies not explicitly mentioned"
                score=$((score + 15))
            fi
            
            # Check for health checks
            if grep -q "health check" "$output_file"; then
                score=$((score + 30))
                log_success "✓ Health check validation mentioned"
            else
                log_warning "△ Health check validation not mentioned"
                score=$((score + 10))
            fi
            ;;
        "uninstall")
            # Check for comprehensive cleanup steps
            if grep -q "containers" "$output_file" && \
               grep -q "volumes" "$output_file" && \
               grep -q "SSL certificates" "$output_file"; then
                score=$((score + 50))
                log_success "✓ Comprehensive cleanup steps documented"
            else
                log_error "✗ Cleanup steps incomplete"
                VALIDATION_ISSUES+=("Uninstallation cleanup steps incomplete")
            fi
            
            # Check for backup preservation
            if grep -q "Preserving backups" "$output_file" || grep -q "backups" "$output_file"; then
                score=$((score + 50))
                log_success "✓ Backup preservation mentioned"
            else
                log_warning "△ Backup preservation not clearly stated"
                score=$((score + 20))
            fi
            ;;
        *)
            # Generic validation for other operations
            score=75  # Default good score for other operations
            log_info "Generic alignment validation applied"
            ;;
    esac
    
    log_info "Implementation alignment score: $score/$max_score"
    return $score
}

# Validate completeness of information
validate_completeness() {
    local output_file="$1"
    local operation="$2"
    local score=0
    local max_score=100
    
    log_info "Validating completeness for $operation"
    
    # Check for clear operation identification
    if grep -iq "dry.run" "$output_file"; then
        score=$((score + 20))
        log_success "✓ Dry-run mode clearly identified"
    else
        log_error "✗ Dry-run mode not clearly identified"
        VALIDATION_ISSUES+=("Dry-run mode identification missing in $operation")
    fi
    
    # Check for structured output sections
    local sections=$(grep -c "═══" "$output_file" 2>/dev/null || echo 0)
    if [[ $sections -ge 3 ]]; then
        score=$((score + 20))
        log_success "✓ Well-structured output with clear sections"
    else
        log_warning "△ Limited output structure"
        score=$((score + 10))
    fi
    
    # Check for actionable next steps
    if grep -q "TO PROCEED" "$output_file" || grep -q "Next steps" "$output_file"; then
        score=$((score + 20))
        log_success "✓ Actionable next steps provided"
    else
        log_warning "△ Limited guidance on next steps"
        score=$((score + 10))
    fi
    
    # Check for resource requirements
    if grep -q "EXPECTED RESOURCES" "$output_file" || grep -q "Requirements" "$output_file"; then
        score=$((score + 20))
        log_success "✓ Resource requirements documented"
    else
        log_warning "△ Resource requirements not detailed"
        score=$((score + 5))
    fi
    
    # Check for access information
    if grep -q "ACCESS ENDPOINTS" "$output_file" || grep -q "endpoints" "$output_file"; then
        score=$((score + 20))
        log_success "✓ Access information provided"
    else
        log_warning "△ Access information limited"
        score=$((score + 10))
    fi
    
    log_info "Completeness score: $score/$max_score"
    return $score
}

# Validate user experience quality
validate_user_experience() {
    local output_file="$1"
    local operation="$2"
    local score=0
    local max_score=100
    
    log_info "Validating user experience for $operation"
    
    # Check for clear, friendly language
    if grep -q "🧪\|📋\|🏗️\|🐳\|🔒\|🔄" "$output_file"; then
        score=$((score + 25))
        log_success "✓ User-friendly formatting with emojis"
    else
        log_warning "△ Plain text output, could be more engaging"
        score=$((score + 10))
    fi
    
    # Check for warning messages where appropriate
    if [[ "$operation" == "uninstall" ]] && grep -q "⚠️\|WARNING\|careful" "$output_file"; then
        score=$((score + 25))
        log_success "✓ Appropriate warnings for destructive operations"
    elif [[ "$operation" != "uninstall" ]]; then
        score=$((score + 25))
        log_success "✓ No unnecessary warnings for non-destructive operations"
    else
        log_warning "△ Insufficient warnings for destructive operation"
        score=$((score + 10))
    fi
    
    # Check for logical information flow
    local line_count=$(wc -l < "$output_file")
    if [[ $line_count -ge 20 && $line_count -le 80 ]]; then
        score=$((score + 25))
        log_success "✓ Appropriate information density"
    elif [[ $line_count -gt 80 ]]; then
        log_warning "△ Output may be too verbose"
        score=$((score + 15))
    else
        log_warning "△ Output may be too brief"
        score=$((score + 10))
    fi
    
    # Check for consistent formatting
    if grep -q "   •" "$output_file"; then
        score=$((score + 25))
        log_success "✓ Consistent bullet formatting"
    else
        log_warning "△ Inconsistent or missing bullet formatting"
        score=$((score + 10))
    fi
    
    log_info "User experience score: $score/$max_score"
    return $score
}

# Validate documentation quality
validate_documentation_quality() {
    local output_file="$1"
    local operation="$2"
    local score=0
    local max_score=100
    
    log_info "Validating documentation quality for $operation"
    
    # Check for examples and usage instructions
    if grep -q "Examples\|Usage\|Run:" "$output_file"; then
        score=$((score + 30))
        log_success "✓ Usage examples provided"
    else
        log_warning "△ Limited usage examples"
        score=$((score + 10))
    fi
    
    # Check for configuration references
    if grep -q "config\|Config\|DOMAIN\|EMAIL" "$output_file"; then
        score=$((score + 30))
        log_success "✓ Configuration requirements mentioned"
    else
        log_warning "△ Configuration requirements not clear"
        score=$((score + 10))
    fi
    
    # Check for troubleshooting guidance
    if grep -q "log\|Log\|debug\|Debug" "$output_file"; then
        score=$((score + 20))
        log_success "✓ Troubleshooting guidance included"
    else
        log_warning "△ Limited troubleshooting guidance"
        score=$((score + 5))
    fi
    
    # Check for clear command syntax
    if grep -q "\$0 --" "$output_file"; then
        score=$((score + 20))
        log_success "✓ Clear command syntax examples"
    else
        log_warning "△ Command syntax could be clearer"
        score=$((score + 10))
    fi
    
    log_info "Documentation quality score: $score/$max_score"
    return $score
}

# ═══════════════════════════════════════════════════════════════════════════════
# 📈 SCORING AND REPORTING FUNCTIONS
# ═══════════════════════════════════════════════════════════════════════════════

# Calculate overall validation score
calculate_overall_score() {
    local tech_score=$1
    local impl_score=$2
    local completeness_score=$3
    local ux_score=$4
    local doc_score=$5
    
    local weighted_score=$(( 
        (tech_score * TECHNICAL_ACCURACY_WEIGHT / 100) +
        (impl_score * IMPLEMENTATION_ALIGNMENT_WEIGHT / 100) +
        (completeness_score * COMPLETENESS_WEIGHT / 100) +
        (ux_score * USER_EXPERIENCE_WEIGHT / 100) +
        (doc_score * DOCUMENTATION_QUALITY_WEIGHT / 100)
    ))
    
    echo $weighted_score
}

# Generate quality assessment
get_quality_assessment() {
    local score=$1
    
    if [[ $score -ge $EXCELLENT_THRESHOLD ]]; then
        echo "EXCELLENT"
    elif [[ $score -ge $GOOD_THRESHOLD ]]; then
        echo "GOOD"
    elif [[ $score -ge $ACCEPTABLE_THRESHOLD ]]; then
        echo "ACCEPTABLE"
    elif [[ $score -ge $NEEDS_IMPROVEMENT_THRESHOLD ]]; then
        echo "NEEDS IMPROVEMENT"
    else
        echo "POOR"
    fi
}

# Generate recommendations based on scores
generate_recommendations() {
    local tech_score=$1
    local impl_score=$2
    local completeness_score=$3
    local ux_score=$4
    local doc_score=$5
    
    if [[ $tech_score -lt $GOOD_THRESHOLD ]]; then
        VALIDATION_RECOMMENDATIONS+=("Improve technical accuracy: Fix variable substitution and configuration references")
    fi
    
    if [[ $impl_score -lt $GOOD_THRESHOLD ]]; then
        VALIDATION_RECOMMENDATIONS+=("Enhance implementation alignment: Ensure dry-run output matches actual implementation steps")
    fi
    
    if [[ $completeness_score -lt $GOOD_THRESHOLD ]]; then
        VALIDATION_RECOMMENDATIONS+=("Increase completeness: Add more detailed information about operations and requirements")
    fi
    
    if [[ $ux_score -lt $GOOD_THRESHOLD ]]; then
        VALIDATION_RECOMMENDATIONS+=("Improve user experience: Enhance formatting, warnings, and information density")
    fi
    
    if [[ $doc_score -lt $GOOD_THRESHOLD ]]; then
        VALIDATION_RECOMMENDATIONS+=("Enhance documentation quality: Add more examples, usage instructions, and troubleshooting guidance")
    fi
}

# ═══════════════════════════════════════════════════════════════════════════════
# 📊 MAIN VALIDATION WORKFLOW
# ═══════════════════════════════════════════════════════════════════════════════

# Validate single operation
validate_operation() {
    local operation="$1"
    local output_file="/tmp/jstack_dryrun_${operation}_$$.txt"
    
    log_section "Validating $operation Operation"
    
    # Capture dry-run output
    if ! capture_dry_run_output "$operation" "$output_file"; then
        log_error "Failed to capture dry-run output for $operation"
        return 1
    fi
    
    # Run validation checks
    validate_technical_accuracy "$output_file" "$operation"
    local tech_score=$?
    
    validate_implementation_alignment "$output_file" "$operation"
    local impl_score=$?
    
    validate_completeness "$output_file" "$operation"
    local completeness_score=$?
    
    validate_user_experience "$output_file" "$operation"
    local ux_score=$?
    
    validate_documentation_quality "$output_file" "$operation"
    local doc_score=$?
    
    # Calculate overall score
    local overall_score=$(calculate_overall_score $tech_score $impl_score $completeness_score $ux_score $doc_score)
    local quality_assessment=$(get_quality_assessment $overall_score)
    
    # Generate recommendations
    generate_recommendations $tech_score $impl_score $completeness_score $ux_score $doc_score
    
    # Store results
    VALIDATION_RESULTS+=("$operation:$overall_score:$quality_assessment:$tech_score:$impl_score:$completeness_score:$ux_score:$doc_score")
    
    # Report results
    log_section "$operation Validation Results"
    echo "Overall Score: $overall_score/100 ($quality_assessment)"
    echo "Technical Accuracy: $tech_score/100"
    echo "Implementation Alignment: $impl_score/100"
    echo "Completeness: $completeness_score/100"
    echo "User Experience: $ux_score/100"
    echo "Documentation Quality: $doc_score/100"
    
    # Clean up temporary file
    rm -f "$output_file"
    
    return 0
}

# Validate all operations
validate_all_operations() {
    local operations=("install" "uninstall" "backup" "sync" "ssl")
    
    log_section "🔍 Comprehensive Dry-Run Validation"
    
    for operation in "${operations[@]}"; do
        validate_operation "$operation" || log_warning "Validation failed for $operation"
        echo ""
    done
    
    # Generate comprehensive report
    generate_comprehensive_report
}

# Generate comprehensive validation report
generate_comprehensive_report() {
    local report_file="${BASE_DIR}/logs/dry_run_validation_$(date +%Y%m%d_%H%M%S).md"
    local temp_dir="/tmp"
    
    # Create report directory if it doesn't exist
    mkdir -p "$(dirname "$report_file")" 2>/dev/null || report_file="${temp_dir}/dry_run_validation_$(date +%Y%m%d_%H%M%S).md"
    
    log_section "📊 Generating Comprehensive Validation Report"
    
    cat > "$report_file" << EOF
# JStack Dry-Run Validation Report
Generated: $(date '+%Y-%m-%d %H:%M:%S')

## Executive Summary

This report provides a comprehensive analysis of JStack dry-run output quality across all supported operations.

### Validation Methodology

The validation framework evaluates five key dimensions:
- **Technical Accuracy (${TECHNICAL_ACCURACY_WEIGHT}%)**: Variable substitution, configuration references
- **Implementation Alignment (${IMPLEMENTATION_ALIGNMENT_WEIGHT}%)**: Consistency with actual implementation
- **Completeness (${COMPLETENESS_WEIGHT}%)**: Information coverage and detail level
- **User Experience (${USER_EXPERIENCE_WEIGHT}%)**: Formatting, warnings, and usability
- **Documentation Quality (${DOCUMENTATION_QUALITY_WEIGHT}%)**: Examples, usage instructions, troubleshooting

### Quality Thresholds
- **Excellent**: ≥${EXCELLENT_THRESHOLD}/100
- **Good**: ≥${GOOD_THRESHOLD}/100  
- **Acceptable**: ≥${ACCEPTABLE_THRESHOLD}/100
- **Needs Improvement**: ≥${NEEDS_IMPROVEMENT_THRESHOLD}/100
- **Poor**: <${NEEDS_IMPROVEMENT_THRESHOLD}/100

## Detailed Results

EOF

    # Add individual operation results
    for result in "${VALIDATION_RESULTS[@]}"; do
        IFS=':' read -r operation overall_score quality_assessment tech_score impl_score completeness_score ux_score doc_score <<< "$result"
        
        cat >> "$report_file" << EOF
### $operation Operation

- **Overall Score**: $overall_score/100 (**$quality_assessment**)
- **Technical Accuracy**: $tech_score/100
- **Implementation Alignment**: $impl_score/100  
- **Completeness**: $completeness_score/100
- **User Experience**: $ux_score/100
- **Documentation Quality**: $doc_score/100

EOF
    done
    
    # Add issues and recommendations
    if [[ ${#VALIDATION_ISSUES[@]} -gt 0 ]]; then
        cat >> "$report_file" << EOF
## Identified Issues

EOF
        for issue in "${VALIDATION_ISSUES[@]}"; do
            echo "- $issue" >> "$report_file"
        done
        echo "" >> "$report_file"
    fi
    
    if [[ ${#VALIDATION_RECOMMENDATIONS[@]} -gt 0 ]]; then
        cat >> "$report_file" << EOF
## Recommendations for Improvement

EOF
        for recommendation in "${VALIDATION_RECOMMENDATIONS[@]}"; do
            echo "- $recommendation" >> "$report_file"
        done
        echo "" >> "$report_file"
    fi
    
    # Calculate overall system score
    local total_score=0
    local operation_count=0
    for result in "${VALIDATION_RESULTS[@]}"; do
        IFS=':' read -r operation overall_score _ <<< "$result"
        total_score=$((total_score + overall_score))
        operation_count=$((operation_count + 1))
    done
    
    local system_average=$((total_score / operation_count))
    local system_assessment=$(get_quality_assessment $system_average)
    
    cat >> "$report_file" << EOF
## Overall System Assessment

**System Average Score**: $system_average/100 (**$system_assessment**)

### Summary
This validation framework provides systematic quality assurance for JStack dry-run operations. The scoring methodology ensures consistent evaluation across all operations while identifying specific areas for improvement.

### Next Steps
1. Address high-priority issues identified in the validation
2. Implement recommended improvements for scores below the Good threshold
3. Re-run validation after making improvements to verify fixes
4. Integrate validation into continuous integration workflow

---
Generated by JStack Dry-Run Validation Framework
EOF
    
    log_success "Comprehensive validation report generated: $report_file"
    echo ""
    echo "📊 SYSTEM VALIDATION SUMMARY"
    echo "Average Score: $system_average/100 ($system_assessment)"
    echo "Operations Validated: $operation_count"
    echo "Issues Found: ${#VALIDATION_ISSUES[@]}"
    echo "Recommendations: ${#VALIDATION_RECOMMENDATIONS[@]}"
    echo ""
    echo "📋 Full Report: $report_file"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🎯 MAIN FUNCTION AND COMMAND ROUTING
# ═══════════════════════════════════════════════════════════════════════════════

# Main function for command routing
main() {
    init_timing_system
    
    case "${1:-all}" in
        "all"|"comprehensive")
            validate_all_operations
            ;;
        "install")
            validate_operation "install"
            ;;
        "uninstall")
            validate_operation "uninstall"
            ;;
        "backup")
            validate_operation "backup"
            ;;
        "sync")
            validate_operation "sync"
            ;;
        "ssl")
            validate_operation "ssl"
            ;;
        *)
            echo "JStack Dry-Run Validation Framework"
            echo ""
            echo "Usage: $0 [OPERATION]"
            echo ""
            echo "Operations:"
            echo "  all                - Validate all operations (default)"
            echo "  comprehensive      - Alias for 'all'"
            echo "  install           - Validate installation dry-run"
            echo "  uninstall         - Validate uninstallation dry-run"
            echo "  backup            - Validate backup dry-run"
            echo "  sync              - Validate sync dry-run"
            echo "  ssl               - Validate SSL configuration dry-run"
            echo ""
            echo "Examples:"
            echo "  $0                # Validate all operations"
            echo "  $0 all            # Validate all operations with comprehensive report"
            echo "  $0 install        # Validate only installation operation"
            echo "  $0 uninstall      # Validate only uninstallation operation"
            echo ""
            echo "The validation framework evaluates:"
            echo "  • Technical accuracy and variable substitution"
            echo "  • Implementation alignment with actual code"
            echo "  • Information completeness and detail level"
            echo "  • User experience and formatting quality"
            echo "  • Documentation and guidance quality"
            echo ""
            echo "Reports are generated in: \${BASE_DIR}/logs/"
            exit 1
            ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi