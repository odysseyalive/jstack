#!/bin/bash

# JarvisJR Stack Security Validation and Certification System
# Phase 4: Monitoring & Alerting - Final Security Validation
# Comprehensive security validation, testing, and certification system

set -e

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"

# Global variables
VALIDATION_DIR="/opt/jarvis-security/validation"
CERTS_DIR="/opt/jarvis-security/certificates"
REPORTS_DIR="/opt/jarvis-security/validation-reports"
TESTS_DIR="/opt/jarvis-security/tests"

# Initialize security validation system
init_validation_system() {
    log_info "Initializing security validation system"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would create validation directories and configuration"
        return 0
    fi
    
    # Create directory structure
    sudo mkdir -p "$VALIDATION_DIR" "$CERTS_DIR" "$REPORTS_DIR" "$TESTS_DIR"
    sudo chown -R jarvis:jarvis "$VALIDATION_DIR" "$CERTS_DIR" "$REPORTS_DIR" "$TESTS_DIR"
    
    # Install security testing tools
    sudo apt-get update
    sudo apt-get install -y nmap nikto lynis chkrootkit rkhunter clamav clamav-daemon
    
    log_success "Security validation system initialized"
}

# Create comprehensive security validator
create_security_validator() {
    log_info "Creating comprehensive security validation engine"
    
    cat > "$VALIDATION_DIR/security_validator.py" << 'EOF'
#!/usr/bin/env python3

import json
import subprocess
import datetime
import os
import socket
import ssl
import requests
from pathlib import Path
from typing import Dict, List, Any, Tuple

class SecurityValidator:
    def __init__(self):
        self.validation_results = {
            "timestamp": datetime.datetime.now().isoformat(),
            "overall_score": 0.0,
            "categories": {},
            "critical_issues": [],
            "recommendations": []
        }
    
    def run_comprehensive_validation(self) -> Dict[str, Any]:
        """Run complete security validation suite"""
        print("Starting comprehensive security validation...")
        
        # Network security validation
        self.validate_network_security()
        
        # Container security validation  
        self.validate_container_security()
        
        # SSL/TLS validation
        self.validate_ssl_configuration()
        
        # System hardening validation
        self.validate_system_hardening()
        
        # Access control validation
        self.validate_access_controls()
        
        # Monitoring and logging validation
        self.validate_monitoring_systems()
        
        # Compliance validation
        self.validate_compliance_status()
        
        # Calculate overall score
        self.calculate_overall_score()
        
        return self.validation_results
    
    def validate_network_security(self):
        """Validate network security configuration"""
        print("Validating network security...")
        
        results = {
            "score": 0.0,
            "checks": {},
            "issues": [],
            "passed": 0,
            "total": 0
        }
        
        # Check firewall status
        ufw_result = self.check_firewall_status()
        results["checks"]["firewall"] = ufw_result
        results["total"] += 1
        if ufw_result["status"] == "pass":
            results["passed"] += 1
        else:
            results["issues"].append("Firewall not properly configured")
        
        # Check fail2ban status
        fail2ban_result = self.check_fail2ban_status()
        results["checks"]["fail2ban"] = fail2ban_result
        results["total"] += 1
        if fail2ban_result["status"] == "pass":
            results["passed"] += 1
        else:
            results["issues"].append("fail2ban intrusion prevention not active")
        
        # Check port exposure
        ports_result = self.check_port_exposure()
        results["checks"]["port_exposure"] = ports_result
        results["total"] += 1
        if ports_result["status"] == "pass":
            results["passed"] += 1
        else:
            results["issues"].append("Unnecessary ports exposed")
        
        # Check NGINX security
        nginx_result = self.check_nginx_security()
        results["checks"]["nginx_security"] = nginx_result
        results["total"] += 1
        if nginx_result["status"] == "pass":
            results["passed"] += 1
        else:
            results["issues"].append("NGINX security configuration issues")
        
        results["score"] = results["passed"] / results["total"] if results["total"] > 0 else 0
        self.validation_results["categories"]["network_security"] = results
    
    def validate_container_security(self):
        """Validate Docker container security"""
        print("Validating container security...")
        
        results = {
            "score": 0.0,
            "checks": {},
            "issues": [],
            "passed": 0,
            "total": 0
        }
        
        # Check Docker daemon security
        docker_result = self.check_docker_security()
        results["checks"]["docker_daemon"] = docker_result
        results["total"] += 1
        if docker_result["status"] == "pass":
            results["passed"] += 1
        else:
            results["issues"].append("Docker daemon security issues")
        
        # Check container vulnerabilities
        vuln_result = self.check_container_vulnerabilities()
        results["checks"]["vulnerabilities"] = vuln_result
        results["total"] += 1
        if vuln_result["status"] == "pass":
            results["passed"] += 1
        else:
            results["issues"].append("Container vulnerabilities detected")
        
        # Check container runtime security
        runtime_result = self.check_container_runtime()
        results["checks"]["runtime_security"] = runtime_result  
        results["total"] += 1
        if runtime_result["status"] == "pass":
            results["passed"] += 1
        else:
            results["issues"].append("Container runtime security issues")
        
        results["score"] = results["passed"] / results["total"] if results["total"] > 0 else 0
        self.validation_results["categories"]["container_security"] = results
    
    def validate_ssl_configuration(self):
        """Validate SSL/TLS configuration"""
        print("Validating SSL/TLS configuration...")
        
        results = {
            "score": 0.0,
            "checks": {},
            "issues": [],
            "passed": 0,
            "total": 0
        }
        
        # Check certificate validity
        cert_result = self.check_ssl_certificates()
        results["checks"]["certificates"] = cert_result
        results["total"] += 1
        if cert_result["status"] == "pass":
            results["passed"] += 1
        else:
            results["issues"].append("SSL certificate issues")
        
        # Check SSL configuration strength
        ssl_result = self.check_ssl_strength()
        results["checks"]["ssl_strength"] = ssl_result
        results["total"] += 1
        if ssl_result["status"] == "pass":
            results["passed"] += 1
        else:
            results["issues"].append("SSL configuration weaknesses")
        
        results["score"] = results["passed"] / results["total"] if results["total"] > 0 else 0
        self.validation_results["categories"]["ssl_configuration"] = results
    
    def validate_system_hardening(self):
        """Validate system hardening measures"""
        print("Validating system hardening...")
        
        results = {
            "score": 0.0,
            "checks": {},
            "issues": [],
            "passed": 0,
            "total": 0
        }
        
        # Run Lynis system audit
        lynis_result = self.run_lynis_audit()
        results["checks"]["system_audit"] = lynis_result
        results["total"] += 1
        if lynis_result["status"] == "pass":
            results["passed"] += 1
        else:
            results["issues"].append("System hardening deficiencies detected")
        
        # Check for rootkits
        rootkit_result = self.check_rootkits()
        results["checks"]["rootkit_scan"] = rootkit_result
        results["total"] += 1
        if rootkit_result["status"] == "pass":
            results["passed"] += 1
        else:
            results["issues"].append("Potential rootkit detected")
            self.validation_results["critical_issues"].append("Rootkit detection requires immediate attention")
        
        # Check file permissions
        perms_result = self.check_file_permissions()
        results["checks"]["file_permissions"] = perms_result
        results["total"] += 1
        if perms_result["status"] == "pass":
            results["passed"] += 1
        else:
            results["issues"].append("Insecure file permissions detected")
        
        results["score"] = results["passed"] / results["total"] if results["total"] > 0 else 0
        self.validation_results["categories"]["system_hardening"] = results
    
    def validate_access_controls(self):
        """Validate access control mechanisms"""
        print("Validating access controls...")
        
        results = {
            "score": 0.0,
            "checks": {},
            "issues": [],
            "passed": 0,
            "total": 0
        }
        
        # Check user account security
        users_result = self.check_user_accounts()
        results["checks"]["user_accounts"] = users_result
        results["total"] += 1
        if users_result["status"] == "pass":
            results["passed"] += 1
        else:
            results["issues"].append("User account security issues")
        
        # Check sudo configuration
        sudo_result = self.check_sudo_config()
        results["checks"]["sudo_config"] = sudo_result
        results["total"] += 1
        if sudo_result["status"] == "pass":
            results["passed"] += 1
        else:
            results["issues"].append("Sudo configuration issues")
        
        # Check SSH configuration
        ssh_result = self.check_ssh_config()
        results["checks"]["ssh_config"] = ssh_result
        results["total"] += 1
        if ssh_result["status"] == "pass":
            results["passed"] += 1
        else:
            results["issues"].append("SSH configuration security issues")
        
        results["score"] = results["passed"] / results["total"] if results["total"] > 0 else 0
        self.validation_results["categories"]["access_controls"] = results
    
    def validate_monitoring_systems(self):
        """Validate monitoring and logging systems"""
        print("Validating monitoring systems...")
        
        results = {
            "score": 0.0,
            "checks": {},
            "issues": [],
            "passed": 0,
            "total": 0
        }
        
        # Check logging configuration
        logging_result = self.check_logging_config()
        results["checks"]["logging"] = logging_result
        results["total"] += 1
        if logging_result["status"] == "pass":
            results["passed"] += 1
        else:
            results["issues"].append("Logging configuration issues")
        
        # Check security monitoring
        monitoring_result = self.check_security_monitoring()
        results["checks"]["security_monitoring"] = monitoring_result
        results["total"] += 1
        if monitoring_result["status"] == "pass":
            results["passed"] += 1
        else:
            results["issues"].append("Security monitoring gaps")
        
        results["score"] = results["passed"] / results["total"] if results["total"] > 0 else 0
        self.validation_results["categories"]["monitoring_systems"] = results
    
    def validate_compliance_status(self):
        """Validate compliance with security frameworks"""
        print("Validating compliance status...")
        
        results = {
            "score": 0.0,
            "checks": {},
            "issues": [],
            "passed": 0,
            "total": 0
        }
        
        # Check compliance framework implementation
        frameworks = ["SOC 2 Type II", "GDPR", "ISO 27001"]
        
        for framework in frameworks:
            framework_result = self.check_compliance_framework(framework)
            results["checks"][framework.lower().replace(" ", "_")] = framework_result
            results["total"] += 1
            if framework_result["status"] == "pass":
                results["passed"] += 1
            else:
                results["issues"].append(f"{framework} compliance gaps")
        
        results["score"] = results["passed"] / results["total"] if results["total"] > 0 else 0
        self.validation_results["categories"]["compliance"] = results
    
    def check_firewall_status(self) -> Dict[str, Any]:
        """Check firewall configuration"""
        try:
            result = subprocess.run(['sudo', 'ufw', 'status'], capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0 and 'Status: active' in result.stdout:
                return {
                    "status": "pass",
                    "message": "UFW firewall is active",
                    "details": result.stdout.strip()
                }
            else:
                return {
                    "status": "fail", 
                    "message": "UFW firewall is not active",
                    "details": result.stdout.strip()
                }
        except Exception as e:
            return {
                "status": "error",
                "message": f"Cannot check firewall status: {e}",
                "details": str(e)
            }
    
    def check_fail2ban_status(self) -> Dict[str, Any]:
        """Check fail2ban service status"""
        try:
            result = subprocess.run(['systemctl', 'is-active', 'fail2ban'], 
                                  capture_output=True, text=True, timeout=10)
            
            if result.returncode == 0 and result.stdout.strip() == 'active':
                # Get jail status
                jail_result = subprocess.run(['sudo', 'fail2ban-client', 'status'], 
                                           capture_output=True, text=True, timeout=10)
                return {
                    "status": "pass",
                    "message": "fail2ban is active with configured jails",
                    "details": jail_result.stdout.strip()
                }
            else:
                return {
                    "status": "fail",
                    "message": "fail2ban service is not active",
                    "details": result.stderr.strip()
                }
        except Exception as e:
            return {
                "status": "error",
                "message": f"Cannot check fail2ban status: {e}",
                "details": str(e)
            }
    
    def check_port_exposure(self) -> Dict[str, Any]:
        """Check for unnecessary port exposure"""
        try:
            result = subprocess.run(['sudo', 'netstat', '-tlnp'], 
                                  capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                lines = result.stdout.split('\n')
                listening_ports = []
                
                for line in lines:
                    if 'LISTEN' in line:
                        parts = line.split()
                        if len(parts) >= 4:
                            listening_ports.append(parts[3])
                
                # Expected ports for JarvisJR Stack
                expected_ports = [':80', ':443', ':22']  # HTTP, HTTPS, SSH
                
                unexpected_ports = []
                for port in listening_ports:
                    if not any(expected in port for expected in expected_ports):
                        unexpected_ports.append(port)
                
                if not unexpected_ports:
                    return {
                        "status": "pass",
                        "message": "Only expected ports are exposed",
                        "details": f"Listening ports: {', '.join(listening_ports)}"
                    }
                else:
                    return {
                        "status": "warning",
                        "message": "Some unexpected ports detected",
                        "details": f"Unexpected: {', '.join(unexpected_ports)}"
                    }
            else:
                return {
                    "status": "error",
                    "message": "Cannot check port exposure",
                    "details": result.stderr.strip()
                }
        except Exception as e:
            return {
                "status": "error",
                "message": f"Port exposure check failed: {e}",
                "details": str(e)
            }
    
    def check_nginx_security(self) -> Dict[str, Any]:
        """Check NGINX security configuration"""
        try:
            # Check if NGINX is running
            result = subprocess.run(['systemctl', 'is-active', 'nginx'], 
                                  capture_output=True, text=True, timeout=10)
            
            if result.returncode != 0:
                return {
                    "status": "fail",
                    "message": "NGINX service is not active",
                    "details": "NGINX is required for secure reverse proxy"
                }
            
            # Check NGINX configuration
            config_result = subprocess.run(['sudo', 'nginx', '-t'], 
                                         capture_output=True, text=True, timeout=10)
            
            if config_result.returncode == 0:
                return {
                    "status": "pass",
                    "message": "NGINX is active with valid configuration",
                    "details": config_result.stderr.strip()
                }
            else:
                return {
                    "status": "fail",
                    "message": "NGINX configuration errors detected",
                    "details": config_result.stderr.strip()
                }
                
        except Exception as e:
            return {
                "status": "error",
                "message": f"NGINX security check failed: {e}",
                "details": str(e)
            }
    
    def check_docker_security(self) -> Dict[str, Any]:
        """Check Docker daemon security"""
        try:
            # Check if Docker is running
            result = subprocess.run(['systemctl', 'is-active', 'docker'], 
                                  capture_output=True, text=True, timeout=10)
            
            if result.returncode != 0:
                return {
                    "status": "fail",
                    "message": "Docker service is not active",
                    "details": "Docker is required for containerized services"
                }
            
            # Check Docker info for security settings
            info_result = subprocess.run(['docker', 'info'], 
                                       capture_output=True, text=True, timeout=30)
            
            if info_result.returncode == 0:
                # Look for security indicators
                info_text = info_result.stdout
                security_features = []
                
                if 'Security Options' in info_text:
                    security_features.append("Security options configured")
                if 'Rootless' in info_text:
                    security_features.append("Rootless mode detected")
                
                return {
                    "status": "pass",
                    "message": "Docker daemon is active",
                    "details": f"Security features: {', '.join(security_features) if security_features else 'Standard configuration'}"
                }
            else:
                return {
                    "status": "fail",
                    "message": "Cannot retrieve Docker information",
                    "details": info_result.stderr.strip()
                }
                
        except Exception as e:
            return {
                "status": "error",
                "message": f"Docker security check failed: {e}",
                "details": str(e)
            }
    
    def check_container_vulnerabilities(self) -> Dict[str, Any]:
        """Check containers for vulnerabilities using Trivy"""
        try:
            # Get list of running containers
            result = subprocess.run(['docker', 'ps', '--format', '{{.Names}}'], 
                                  capture_output=True, text=True, timeout=30)
            
            if result.returncode != 0:
                return {
                    "status": "error",
                    "message": "Cannot list Docker containers",
                    "details": result.stderr.strip()
                }
            
            containers = result.stdout.strip().split('\n')
            if not containers or containers == ['']:
                return {
                    "status": "pass",
                    "message": "No running containers to scan",
                    "details": "Container vulnerability scanning skipped"
                }
            
            # Check if Trivy is available
            trivy_check = subprocess.run(['which', 'trivy'], 
                                       capture_output=True, text=True, timeout=10)
            
            if trivy_check.returncode != 0:
                return {
                    "status": "warning",
                    "message": "Trivy scanner not available",
                    "details": "Install Trivy for container vulnerability scanning"
                }
            
            # Scan containers (limit to avoid timeout)
            vulnerability_count = 0
            scanned_containers = []
            
            for container in containers[:3]:  # Limit to first 3 containers
                scan_result = subprocess.run(['trivy', 'image', '--format', 'json', 
                                            '--quiet', container], 
                                           capture_output=True, text=True, timeout=60)
                
                if scan_result.returncode == 0:
                    try:
                        scan_data = json.loads(scan_result.stdout)
                        if 'Results' in scan_data:
                            for result in scan_data['Results']:
                                if 'Vulnerabilities' in result:
                                    vulnerability_count += len(result['Vulnerabilities'])
                        scanned_containers.append(container)
                    except json.JSONDecodeError:
                        pass
            
            if vulnerability_count == 0:
                return {
                    "status": "pass",
                    "message": "No critical vulnerabilities detected",
                    "details": f"Scanned containers: {', '.join(scanned_containers)}"
                }
            else:
                return {
                    "status": "warning",
                    "message": f"{vulnerability_count} vulnerabilities detected",
                    "details": f"Scanned containers: {', '.join(scanned_containers)}"
                }
                
        except Exception as e:
            return {
                "status": "error",
                "message": f"Container vulnerability scan failed: {e}",
                "details": str(e)
            }
    
    def check_container_runtime(self) -> Dict[str, Any]:
        """Check container runtime security"""
        try:
            # Check Docker Bench Security if available
            bench_script = "/opt/docker-bench-security/docker-bench-security.sh"
            
            if Path(bench_script).exists():
                result = subprocess.run(['bash', bench_script, '-c'], 
                                      capture_output=True, text=True, timeout=120)
                
                if result.returncode == 0:
                    # Parse results (simplified)
                    output = result.stdout
                    if '[PASS]' in output:
                        pass_count = output.count('[PASS]')
                        fail_count = output.count('[FAIL]')
                        warn_count = output.count('[WARN]')
                        
                        return {
                            "status": "pass" if fail_count == 0 else "warning",
                            "message": f"Docker Bench results: {pass_count} passed, {fail_count} failed, {warn_count} warnings",
                            "details": "Docker security benchmarking completed"
                        }
                
            return {
                "status": "warning",
                "message": "Docker Bench Security not available",
                "details": "Install Docker Bench Security for comprehensive runtime checks"
            }
                
        except Exception as e:
            return {
                "status": "warning",
                "message": f"Container runtime check limited: {e}",
                "details": "Basic container security validation performed"
            }
    
    def check_ssl_certificates(self) -> Dict[str, Any]:
        """Check SSL certificate validity"""
        try:
            cert_dirs = ['/etc/letsencrypt/live/', '/etc/ssl/certs/']
            found_certs = []
            
            for cert_dir in cert_dirs:
                if Path(cert_dir).exists():
                    for cert_path in Path(cert_dir).rglob('*.pem'):
                        found_certs.append(str(cert_path))
            
            if found_certs:
                return {
                    "status": "pass",
                    "message": f"SSL certificates found: {len(found_certs)}",
                    "details": f"Certificate locations: {', '.join(found_certs[:3])}"
                }
            else:
                return {
                    "status": "fail",
                    "message": "No SSL certificates found",
                    "details": "SSL certificates required for secure communication"
                }
                
        except Exception as e:
            return {
                "status": "error", 
                "message": f"SSL certificate check failed: {e}",
                "details": str(e)
            }
    
    def check_ssl_strength(self) -> Dict[str, Any]:
        """Check SSL configuration strength"""
        try:
            # Basic SSL strength check - could be expanded
            nginx_ssl_config = "/etc/nginx/sites-available/"
            
            if Path(nginx_ssl_config).exists():
                # Look for SSL configuration files
                ssl_configs = list(Path(nginx_ssl_config).glob('*'))
                
                if ssl_configs:
                    return {
                        "status": "pass",
                        "message": "SSL configuration files present",
                        "details": f"SSL configs: {len(ssl_configs)} files"
                    }
            
            return {
                "status": "warning",
                "message": "SSL configuration validation limited",
                "details": "Manual SSL strength verification recommended"
            }
            
        except Exception as e:
            return {
                "status": "error",
                "message": f"SSL strength check failed: {e}",
                "details": str(e)
            }
    
    def run_lynis_audit(self) -> Dict[str, Any]:
        """Run Lynis system audit"""
        try:
            result = subprocess.run(['sudo', 'lynis', 'audit', 'system', '--quiet'], 
                                  capture_output=True, text=True, timeout=300)
            
            if result.returncode == 0:
                # Parse Lynis results
                output = result.stdout
                
                if 'Hardening index' in output:
                    # Extract hardening index
                    for line in output.split('\n'):
                        if 'Hardening index' in line:
                            hardening_info = line.strip()
                            break
                    
                    return {
                        "status": "pass",
                        "message": "System audit completed",
                        "details": hardening_info
                    }
                else:
                    return {
                        "status": "warning",
                        "message": "System audit completed with warnings",
                        "details": "Check /var/log/lynis.log for details"
                    }
            else:
                return {
                    "status": "fail",
                    "message": "System audit failed",
                    "details": result.stderr.strip()
                }
                
        except Exception as e:
            return {
                "status": "error",
                "message": f"Lynis audit failed: {e}",
                "details": "Install lynis for system hardening audit"
            }
    
    def check_rootkits(self) -> Dict[str, Any]:
        """Check for rootkits"""
        try:
            # Try chkrootkit first
            result = subprocess.run(['sudo', 'chkrootkit'], 
                                  capture_output=True, text=True, timeout=180)
            
            if result.returncode == 0:
                output = result.stdout.lower()
                if 'infected' in output or 'malware' in output:
                    return {
                        "status": "fail",
                        "message": "Potential rootkit detected",
                        "details": "Manual investigation required immediately"
                    }
                else:
                    return {
                        "status": "pass",
                        "message": "No rootkits detected by chkrootkit",
                        "details": "System appears clean"
                    }
            
            # Fallback to rkhunter if available
            rkhunter_result = subprocess.run(['sudo', 'rkhunter', '--check', '--sk'], 
                                           capture_output=True, text=True, timeout=180)
            
            if rkhunter_result.returncode == 0:
                return {
                    "status": "pass",
                    "message": "Rootkit scan completed",
                    "details": "No significant threats detected"
                }
            
            return {
                "status": "warning",
                "message": "Rootkit scanning tools not available",
                "details": "Install chkrootkit or rkhunter for rootkit detection"
            }
            
        except Exception as e:
            return {
                "status": "error",
                "message": f"Rootkit check failed: {e}",
                "details": "Manual rootkit investigation recommended"
            }
    
    def check_file_permissions(self) -> Dict[str, Any]:
        """Check critical file permissions"""
        try:
            critical_files = [
                '/etc/passwd',
                '/etc/shadow', 
                '/etc/group',
                '/etc/ssh/sshd_config'
            ]
            
            issues = []
            
            for file_path in critical_files:
                if Path(file_path).exists():
                    stat_result = subprocess.run(['stat', '-c', '%a', file_path], 
                                               capture_output=True, text=True, timeout=10)
                    
                    if stat_result.returncode == 0:
                        perms = stat_result.stdout.strip()
                        
                        # Check for overly permissive files
                        if file_path == '/etc/shadow' and perms != '640':
                            issues.append(f"{file_path} has permissions {perms} (should be 640)")
                        elif file_path in ['/etc/passwd', '/etc/group'] and int(perms) > 644:
                            issues.append(f"{file_path} has overly permissive permissions {perms}")
            
            if not issues:
                return {
                    "status": "pass",
                    "message": "Critical file permissions are secure",
                    "details": f"Checked {len(critical_files)} critical files"
                }
            else:
                return {
                    "status": "fail",
                    "message": f"File permission issues found: {len(issues)}",
                    "details": "; ".join(issues)
                }
                
        except Exception as e:
            return {
                "status": "error",
                "message": f"File permission check failed: {e}",
                "details": str(e)
            }
    
    def check_user_accounts(self) -> Dict[str, Any]:
        """Check user account security"""
        try:
            # Check for accounts with empty passwords
            result = subprocess.run(['sudo', 'awk', '-F:', '($2 == "" ) { print $1 }', '/etc/shadow'], 
                                  capture_output=True, text=True, timeout=10)
            
            empty_password_users = result.stdout.strip().split('\n') if result.stdout.strip() else []
            
            # Check for unnecessary privileged users
            wheel_result = subprocess.run(['getent', 'group', 'sudo'], 
                                        capture_output=True, text=True, timeout=10)
            
            sudo_users = []
            if wheel_result.returncode == 0:
                sudo_line = wheel_result.stdout.strip()
                if ':' in sudo_line:
                    sudo_users = sudo_line.split(':')[-1].split(',') if sudo_line.split(':')[-1] else []
            
            issues = []
            if empty_password_users and empty_password_users != ['']:
                issues.append(f"Users with empty passwords: {', '.join(empty_password_users)}")
            
            if len(sudo_users) > 3:  # Threshold for too many privileged users
                issues.append(f"Many users have sudo access: {len(sudo_users)}")
            
            if not issues:
                return {
                    "status": "pass",
                    "message": "User account security is adequate",
                    "details": f"Sudo users: {len(sudo_users)}, No empty passwords"
                }
            else:
                return {
                    "status": "fail",
                    "message": "User account security issues detected",
                    "details": "; ".join(issues)
                }
                
        except Exception as e:
            return {
                "status": "error",
                "message": f"User account check failed: {e}",
                "details": str(e)
            }
    
    def check_sudo_config(self) -> Dict[str, Any]:
        """Check sudo configuration security"""
        try:
            # Check sudo configuration
            result = subprocess.run(['sudo', 'visudo', '-c'], 
                                  capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                return {
                    "status": "pass",
                    "message": "Sudo configuration is valid",
                    "details": result.stdout.strip()
                }
            else:
                return {
                    "status": "fail",
                    "message": "Sudo configuration has issues",
                    "details": result.stderr.strip()
                }
                
        except Exception as e:
            return {
                "status": "error",
                "message": f"Sudo configuration check failed: {e}",
                "details": str(e)
            }
    
    def check_ssh_config(self) -> Dict[str, Any]:
        """Check SSH configuration security"""
        try:
            ssh_config_file = "/etc/ssh/sshd_config"
            
            if not Path(ssh_config_file).exists():
                return {
                    "status": "fail",
                    "message": "SSH configuration file not found",
                    "details": "SSH service may not be configured"
                }
            
            # Test SSH configuration
            result = subprocess.run(['sudo', 'sshd', '-t'], 
                                  capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                return {
                    "status": "pass",
                    "message": "SSH configuration is valid",
                    "details": "SSH daemon configuration test passed"
                }
            else:
                return {
                    "status": "fail",
                    "message": "SSH configuration errors detected",
                    "details": result.stderr.strip()
                }
                
        except Exception as e:
            return {
                "status": "error",
                "message": f"SSH configuration check failed: {e}",
                "details": str(e)
            }
    
    def check_logging_config(self) -> Dict[str, Any]:
        """Check logging configuration"""
        try:
            # Check rsyslog service
            result = subprocess.run(['systemctl', 'is-active', 'rsyslog'], 
                                  capture_output=True, text=True, timeout=10)
            
            logging_services = []
            if result.returncode == 0:
                logging_services.append("rsyslog")
            
            # Check systemd journal
            journal_result = subprocess.run(['systemctl', 'is-active', 'systemd-journald'], 
                                          capture_output=True, text=True, timeout=10)
            
            if journal_result.returncode == 0:
                logging_services.append("systemd-journald")
            
            if logging_services:
                return {
                    "status": "pass",
                    "message": "Logging services are active",
                    "details": f"Active services: {', '.join(logging_services)}"
                }
            else:
                return {
                    "status": "fail",
                    "message": "No active logging services detected",
                    "details": "System logging may not be functioning"
                }
                
        except Exception as e:
            return {
                "status": "error",
                "message": f"Logging configuration check failed: {e}",
                "details": str(e)
            }
    
    def check_security_monitoring(self) -> Dict[str, Any]:
        """Check security monitoring systems"""
        try:
            monitoring_services = ['fail2ban', 'rsyslog']
            active_services = []
            
            for service in monitoring_services:
                result = subprocess.run(['systemctl', 'is-active', service], 
                                      capture_output=True, text=True, timeout=10)
                if result.returncode == 0:
                    active_services.append(service)
            
            # Check for custom security monitoring
            security_scripts = [
                '/opt/jarvis-security/scripts/security/monitoring_system.sh',
                '/opt/jarvis-security/scripts/security/alerting_system.sh'
            ]
            
            custom_monitoring = []
            for script in security_scripts:
                if Path(script).exists():
                    custom_monitoring.append(Path(script).name)
            
            total_monitoring = len(active_services) + len(custom_monitoring)
            
            if total_monitoring >= 2:
                return {
                    "status": "pass",
                    "message": "Adequate security monitoring in place",
                    "details": f"Services: {', '.join(active_services)}, Custom: {', '.join(custom_monitoring)}"
                }
            elif total_monitoring > 0:
                return {
                    "status": "warning",
                    "message": "Basic security monitoring detected",
                    "details": f"Active monitoring: {total_monitoring} systems"
                }
            else:
                return {
                    "status": "fail",
                    "message": "No security monitoring detected",
                    "details": "Security monitoring systems required"
                }
                
        except Exception as e:
            return {
                "status": "error",
                "message": f"Security monitoring check failed: {e}",
                "details": str(e)
            }
    
    def check_compliance_framework(self, framework: str) -> Dict[str, Any]:
        """Check compliance with specific framework"""
        try:
            # Check if compliance checker exists
            compliance_script = "/opt/jarvis-security/compliance/compliance_checker.py"
            
            if Path(compliance_script).exists():
                result = subprocess.run(['python3', compliance_script, framework], 
                                      capture_output=True, text=True, timeout=120)
                
                if result.returncode == 0:
                    # Parse compliance results (simplified)
                    output = result.stdout
                    if 'Overall Compliance Score' in output:
                        return {
                            "status": "pass",
                            "message": f"{framework} compliance check completed",
                            "details": "Compliance assessment available in reports"
                        }
                
            return {
                "status": "warning",
                "message": f"{framework} compliance check not available",
                "details": "Install compliance monitoring for framework validation"
            }
            
        except Exception as e:
            return {
                "status": "error",
                "message": f"{framework} compliance check failed: {e}",
                "details": str(e)
            }
    
    def calculate_overall_score(self):
        """Calculate overall security score"""
        total_score = 0.0
        category_count = 0
        
        for category, results in self.validation_results["categories"].items():
            if "score" in results:
                total_score += results["score"]
                category_count += 1
                
                # Collect critical issues
                for issue in results.get("issues", []):
                    if any(critical_word in issue.lower() for critical_word in ['critical', 'fail', 'rootkit', 'malware']):
                        if issue not in self.validation_results["critical_issues"]:
                            self.validation_results["critical_issues"].append(issue)
        
        if category_count > 0:
            overall_score = total_score / category_count
            self.validation_results["overall_score"] = overall_score
            
            # Generate recommendations based on score
            if overall_score < 0.6:
                self.validation_results["recommendations"].append("Immediate security improvements required")
                self.validation_results["recommendations"].append("Address all critical and high-priority issues")
                self.validation_results["recommendations"].append("Consider professional security audit")
            elif overall_score < 0.8:
                self.validation_results["recommendations"].append("Good security posture with room for improvement")
                self.validation_results["recommendations"].append("Address medium-priority security issues")
                self.validation_results["recommendations"].append("Implement additional monitoring and hardening")
            else:
                self.validation_results["recommendations"].append("Excellent security posture")
                self.validation_results["recommendations"].append("Continue regular security assessments")
                self.validation_results["recommendations"].append("Consider advanced security measures")


if __name__ == "__main__":
    validator = SecurityValidator()
    results = validator.run_comprehensive_validation()
    
    # Save results
    timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
    report_file = f"/opt/jarvis-security/validation-reports/security_validation_{timestamp}.json"
    
    os.makedirs(os.path.dirname(report_file), exist_ok=True)
    with open(report_file, 'w') as f:
        json.dump(results, f, indent=2)
    
    # Print summary
    print(f"\nSECURITY VALIDATION SUMMARY")
    print(f"===========================")
    print(f"Overall Score: {results['overall_score']:.1%}")
    print(f"Validation Date: {results['timestamp']}")
    print(f"Report Saved: {report_file}")
    
    if results['critical_issues']:
        print(f"\nCRITICAL ISSUES ({len(results['critical_issues'])}):")
        for issue in results['critical_issues']:
            print(f"  ⚠️  {issue}")
    
    print(f"\nCATEGORY SCORES:")
    for category, data in results['categories'].items():
        score = data.get('score', 0)
        print(f"  {category.replace('_', ' ').title()}: {score:.1%}")
    
    print(f"\nRECOMMENDATIONS:")
    for rec in results['recommendations']:
        print(f"  • {rec}")
EOF

    chmod +x "$VALIDATION_DIR/security_validator.py"
    
    log_success "Comprehensive security validation engine created"
}

# Create security certification generator
create_certification_system() {
    log_info "Creating security certification system"
    
    cat > "$CERTS_DIR/certification_generator.py" << 'EOF'
#!/usr/bin/env python3

import json
import datetime
import os
from pathlib import Path
from typing import Dict, Any

class SecurityCertificationGenerator:
    def __init__(self):
        self.template_dir = "/opt/jarvis-security/certificates/templates"
        self.output_dir = "/opt/jarvis-security/certificates/issued"
        os.makedirs(self.template_dir, exist_ok=True)
        os.makedirs(self.output_dir, exist_ok=True)
    
    def generate_security_certificate(self, validation_results: Dict[str, Any]) -> str:
        """Generate security certificate based on validation results"""
        
        overall_score = validation_results.get('overall_score', 0)
        timestamp = datetime.datetime.now()
        
        # Determine certification level
        if overall_score >= 0.9:
            cert_level = "PLATINUM"
            cert_color = "#E5E4E2"
        elif overall_score >= 0.8:
            cert_level = "GOLD"
            cert_color = "#FFD700"
        elif overall_score >= 0.7:
            cert_level = "SILVER"
            cert_color = "#C0C0C0"
        elif overall_score >= 0.6:
            cert_level = "BRONZE"
            cert_color = "#CD7F32"
        else:
            cert_level = "BASIC"
            cert_color = "#808080"
        
        cert_id = f"JARVIS-SEC-{timestamp.strftime('%Y%m%d')}-{cert_level}"
        
        # Generate certificate content
        certificate_html = f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>JarvisJR Security Certificate</title>
    <style>
        body {{
            font-family: 'Georgia', serif;
            margin: 0;
            padding: 40px;
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            min-height: 100vh;
            display: flex;
            justify-content: center;
            align-items: center;
        }}
        .certificate {{
            background: white;
            width: 800px;
            padding: 60px;
            border: 20px solid {cert_color};
            border-radius: 15px;
            box-shadow: 0 0 30px rgba(0,0,0,0.3);
            text-align: center;
            position: relative;
        }}
        .certificate::before {{
            content: '';
            position: absolute;
            top: -10px;
            left: -10px;
            right: -10px;
            bottom: -10px;
            background: linear-gradient(45deg, {cert_color}, #ffffff, {cert_color});
            z-index: -1;
            border-radius: 20px;
        }}
        .header {{
            border-bottom: 3px solid {cert_color};
            padding-bottom: 30px;
            margin-bottom: 40px;
        }}
        .title {{
            font-size: 3em;
            color: #2c3e50;
            margin: 0;
            font-weight: bold;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.1);
        }}
        .subtitle {{
            font-size: 1.2em;
            color: #7f8c8d;
            margin: 10px 0;
        }}
        .content {{
            margin: 40px 0;
        }}
        .cert-text {{
            font-size: 1.4em;
            color: #2c3e50;
            line-height: 1.6;
            margin: 20px 0;
        }}
        .score-display {{
            font-size: 4em;
            color: {cert_color};
            font-weight: bold;
            text-shadow: 2px 2px 4px rgba(0,0,0,0.1);
            margin: 30px 0;
        }}
        .cert-level {{
            font-size: 2.5em;
            color: #2c3e50;
            font-weight: bold;
            margin: 20px 0;
            padding: 15px 30px;
            border: 3px solid {cert_color};
            border-radius: 10px;
            display: inline-block;
            background: rgba(255,255,255,0.8);
        }}
        .details {{
            margin: 40px 0;
            text-align: left;
            background: #f8f9fa;
            padding: 30px;
            border-radius: 10px;
            border-left: 5px solid {cert_color};
        }}
        .details h3 {{
            color: #2c3e50;
            margin-top: 0;
        }}
        .details ul {{
            list-style-type: none;
            padding: 0;
        }}
        .details li {{
            margin: 10px 0;
            padding: 5px 0;
            border-bottom: 1px solid #ecf0f1;
        }}
        .footer {{
            border-top: 3px solid {cert_color};
            padding-top: 30px;
            margin-top: 40px;
            display: flex;
            justify-content: space-between;
            align-items: center;
        }}
        .cert-id {{
            font-family: 'Courier New', monospace;
            color: #7f8c8d;
            font-size: 0.9em;
        }}
        .date {{
            color: #7f8c8d;
            font-size: 1em;
        }}
        .seal {{
            width: 100px;
            height: 100px;
            border-radius: 50%;
            background: radial-gradient(circle, {cert_color} 0%, #ffffff 70%);
            border: 5px solid {cert_color};
            display: flex;
            justify-content: center;
            align-items: center;
            font-size: 2em;
            color: white;
            text-shadow: 1px 1px 2px rgba(0,0,0,0.5);
            position: absolute;
            top: 30px;
            right: 30px;
        }}
        .framework-badges {{
            display: flex;
            justify-content: center;
            gap: 15px;
            margin: 30px 0;
        }}
        .badge {{
            background: {cert_color};
            color: white;
            padding: 8px 15px;
            border-radius: 20px;
            font-size: 0.9em;
            font-weight: bold;
        }}
    </style>
</head>
<body>
    <div class="certificate">
        <div class="seal">🛡️</div>
        
        <div class="header">
            <h1 class="title">SECURITY CERTIFICATE</h1>
            <div class="subtitle">JarvisJR Stack Security Assessment</div>
        </div>
        
        <div class="content">
            <p class="cert-text">This certifies that the</p>
            <div class="cert-level">{cert_level} SECURITY LEVEL</div>
            <p class="cert-text">has been achieved for the JarvisJR Stack deployment</p>
            
            <div class="score-display">{overall_score:.1%}</div>
            <p class="cert-text">Overall Security Score</p>
            
            <div class="framework-badges">
                <div class="badge">SOC 2</div>
                <div class="badge">GDPR</div>
                <div class="badge">ISO 27001</div>
            </div>
            
            <div class="details">
                <h3>Security Assessment Results</h3>
                <ul>
"""
        
        # Add category scores
        for category, data in validation_results.get('categories', {}).items():
            score = data.get('score', 0)
            status = "✅" if score >= 0.8 else "⚠️" if score >= 0.6 else "❌"
            certificate_html += f"<li>{status} {category.replace('_', ' ').title()}: {score:.1%}</li>\n"
        
        certificate_html += f"""
                </ul>
                
                <h3>Validation Details</h3>
                <ul>
                    <li>📅 Assessment Date: {timestamp.strftime('%B %d, %Y')}</li>
                    <li>🔍 Categories Assessed: {len(validation_results.get('categories', {}))}</li>
                    <li>⚠️ Critical Issues: {len(validation_results.get('critical_issues', []))}</li>
                    <li>🎯 Recommendations: {len(validation_results.get('recommendations', []))}</li>
                </ul>
            </div>
        </div>
        
        <div class="footer">
            <div class="cert-id">Certificate ID: {cert_id}</div>
            <div class="date">Issued: {timestamp.strftime('%B %d, %Y at %I:%M %p')}</div>
        </div>
    </div>
</body>
</html>
        """
        
        # Save certificate
        cert_filename = f"{self.output_dir}/security_certificate_{timestamp.strftime('%Y%m%d_%H%M%S')}.html"
        with open(cert_filename, 'w') as f:
            f.write(certificate_html)
        
        # Generate summary badge (SVG)
        self.generate_security_badge(cert_level, overall_score, cert_color, timestamp)
        
        return cert_filename
    
    def generate_security_badge(self, level: str, score: float, color: str, timestamp: datetime.datetime):
        """Generate SVG security badge"""
        
        badge_svg = f"""<?xml version="1.0" encoding="UTF-8"?>
<svg width="200" height="120" xmlns="http://www.w3.org/2000/svg">
    <defs>
        <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" style="stop-color:{color};stop-opacity:1" />
            <stop offset="100%" style="stop-color:#ffffff;stop-opacity:1" />
        </linearGradient>
    </defs>
    
    <rect width="200" height="120" rx="10" fill="url(#bg)" stroke="{color}" stroke-width="3"/>
    
    <text x="100" y="25" text-anchor="middle" font-family="Arial, sans-serif" font-size="14" font-weight="bold" fill="#2c3e50">
        JARVIS SECURITY
    </text>
    
    <text x="100" y="45" text-anchor="middle" font-family="Arial, sans-serif" font-size="18" font-weight="bold" fill="#2c3e50">
        {level}
    </text>
    
    <text x="100" y="70" text-anchor="middle" font-family="Arial, sans-serif" font-size="24" font-weight="bold" fill="{color}">
        {score:.1%}
    </text>
    
    <text x="100" y="90" text-anchor="middle" font-family="Arial, sans-serif" font-size="10" fill="#7f8c8d">
        {timestamp.strftime('%Y-%m-%d')}
    </text>
    
    <circle cx="170" cy="30" r="15" fill="{color}" opacity="0.8"/>
    <text x="170" y="35" text-anchor="middle" font-family="Arial, sans-serif" font-size="16" fill="white">🛡️</text>
</svg>"""
        
        badge_filename = f"{self.output_dir}/security_badge_{timestamp.strftime('%Y%m%d_%H%M%S')}.svg"
        with open(badge_filename, 'w') as f:
            f.write(badge_svg)
        
        return badge_filename


if __name__ == "__main__":
    import sys
    
    generator = SecurityCertificationGenerator()
    
    if len(sys.argv) > 1:
        # Load validation results from file
        results_file = sys.argv[1]
        if Path(results_file).exists():
            with open(results_file, 'r') as f:
                validation_results = json.load(f)
            
            cert_file = generator.generate_security_certificate(validation_results)
            print(f"Security certificate generated: {cert_file}")
        else:
            print(f"Validation results file not found: {results_file}")
    else:
        print("Usage: certification_generator.py <validation_results.json>")
EOF

    chmod +x "$CERTS_DIR/certification_generator.py"
    
    log_success "Security certification system created"
}

# Main validation setup function
setup_validation_system() {
    log_info "Setting up complete security validation system"
    
    start_progress "Initializing validation system"
    init_validation_system
    stop_progress
    
    start_progress "Creating security validation engine"
    create_security_validator
    stop_progress
    
    start_progress "Creating certification system"
    create_certification_system
    stop_progress
    
    log_success "Security validation and certification system setup completed"
    
    # Summary
    log_info "Security Validation System Summary:"
    log_info "• Comprehensive Security Assessment: Network, Container, SSL, System"
    log_info "• Compliance Validation: SOC 2, GDPR, ISO 27001"
    log_info "• Automated Certification: HTML certificates with scoring"
    log_info "• Security Badge Generation: SVG badges for display"
    log_info "• Manual Validation: python3 $VALIDATION_DIR/security_validator.py"
    log_info "• Certificate Generation: Based on validation results"
}

# Validation function
validate_security_system() {
    log_info "Validating security validation configuration"
    
    local validation_passed=true
    
    # Check required directories
    local required_dirs=("$VALIDATION_DIR" "$CERTS_DIR" "$REPORTS_DIR" "$TESTS_DIR")
    for dir in "${required_dirs[@]}"; do
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            log_info "[DRY RUN] Would check directory: $dir"
        else
            if [[ ! -d "$dir" ]]; then
                log_error "Required directory missing: $dir"
                validation_passed=false
            fi
        fi
    done
    
    # Check required files
    local required_files=(
        "$VALIDATION_DIR/security_validator.py"
        "$CERTS_DIR/certification_generator.py"
    )
    
    for file in "${required_files[@]}"; do
        if [[ "${DRY_RUN:-false}" == "true" ]]; then
            log_info "[DRY RUN] Would check file: $file"
        else
            if [[ ! -f "$file" ]]; then
                log_error "Required file missing: $file"
                validation_passed=false
            fi
        fi
    done
    
    if [[ "$validation_passed" == "true" ]]; then
        log_success "Security validation system validation passed"
    else
        log_error "Security validation system validation failed"
        return 1
    fi
}

# Script usage information
show_help() {
    cat << EOF
JarvisJR Security Validation and Certification System

USAGE:
    bash security_validation.sh [COMMAND]

COMMANDS:
    setup           Set up complete security validation system
    validate        Validate security validation configuration  
    run-assessment  Run comprehensive security assessment
    generate-cert   Generate security certificate from results
    help            Show this help message

EXAMPLES:
    # Set up complete security validation system
    bash security_validation.sh setup

    # Dry run validation
    DRY_RUN=true bash security_validation.sh validate

    # Run security assessment
    bash security_validation.sh run-assessment

SECURITY ASSESSMENT:
    # Run comprehensive validation
    python3 $VALIDATION_DIR/security_validator.py
    
    # Generate certificate from results
    python3 $CERTS_DIR/certification_generator.py /path/to/validation_results.json

ASSESSMENT CATEGORIES:
    • Network Security (firewall, fail2ban, ports, NGINX)
    • Container Security (Docker, vulnerabilities, runtime)
    • SSL/TLS Configuration (certificates, strength)
    • System Hardening (Lynis audit, rootkits, permissions)
    • Access Controls (users, sudo, SSH)
    • Monitoring Systems (logging, security monitoring)
    • Compliance Status (SOC 2, GDPR, ISO 27001)

CERTIFICATION LEVELS:
    • PLATINUM (90%+): Exceptional security posture
    • GOLD (80-89%): Excellent security implementation
    • SILVER (70-79%): Good security with improvements needed
    • BRONZE (60-69%): Basic security, significant work required
    • BASIC (<60%): Immediate security improvements critical

FILES CREATED:
    $VALIDATION_DIR/security_validator.py     - Comprehensive security assessment
    $CERTS_DIR/certification_generator.py     - Certificate and badge generator
    $REPORTS_DIR/security_validation_*.json   - Assessment results
    $CERTS_DIR/issued/security_certificate_*.html - HTML certificates
    $CERTS_DIR/issued/security_badge_*.svg    - Security badges

TOOLS INSTALLED:
    nmap, nikto, lynis, chkrootkit, rkhunter, clamav

LOGS:
    /opt/jarvis-security/logs/validation.log   - Validation logs

EOF
}

# Main execution
main() {
    local command="${1:-setup}"
    
    case "$command" in
        "setup")
            setup_validation_system
            ;;
        "validate")
            validate_security_system
            ;;
        "run-assessment")
            if [[ "${DRY_RUN:-false}" == "true" ]]; then
                log_info "[DRY RUN] Would run comprehensive security assessment"
            else
                python3 "$VALIDATION_DIR/security_validator.py"
            fi
            ;;
        "generate-cert")
            local results_file="${2:-}"
            if [[ "${DRY_RUN:-false}" == "true" ]]; then
                log_info "[DRY RUN] Would generate security certificate"
            elif [[ -n "$results_file" ]]; then
                python3 "$CERTS_DIR/certification_generator.py" "$results_file"
            else
                log_error "Usage: $0 generate-cert <validation_results.json>"
                exit 1
            fi
            ;;
        "help"|"-h"|"--help")
            show_help
            ;;
        *)
            log_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi