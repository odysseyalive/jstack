#!/bin/bash

# JStack Automated Incident Response System
# Phase 4: Monitoring & Alerting - Incident Response Workflows
# Provides automated incident detection, response, and recovery workflows

set -e

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"

# Global variables
INCIDENT_DIR="/opt/jstack-security/incidents"
RESPONSE_DIR="/opt/jstack-security/response"
PLAYBOOKS_DIR="/opt/jstack-security/playbooks"
QUARANTINE_DIR="/opt/jstack-security/quarantine"

# Initialize incident response system
init_incident_response() {
    log_info "Initializing automated incident response system"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would create incident response directories and configuration"
        return 0
    fi
    
    # Create directory structure
    sudo mkdir -p "$INCIDENT_DIR" "$RESPONSE_DIR" "$PLAYBOOKS_DIR" "$QUARANTINE_DIR"
    sudo chown -R jarvis:jarvis "$INCIDENT_DIR" "$RESPONSE_DIR" "$PLAYBOOKS_DIR" "$QUARANTINE_DIR"
    
    # Install required packages
    sudo apt-get update
    sudo apt-get install -y jq curl sqlite3 systemd
    
    log_success "Incident response system initialized"
}

# Create incident response database
create_incident_database() {
    log_info "Creating incident response database"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would create incident response database"
        return 0
    fi
    
    cat > "$INCIDENT_DIR/create_db.sql" << 'EOF'
-- Incident Response Database Schema

CREATE TABLE IF NOT EXISTS incidents (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    incident_id TEXT UNIQUE NOT NULL,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    severity TEXT NOT NULL CHECK (severity IN ('critical', 'high', 'medium', 'low')),
    category TEXT NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    source_ip TEXT,
    target_resource TEXT,
    status TEXT DEFAULT 'open' CHECK (status IN ('open', 'investigating', 'contained', 'resolved', 'closed')),
    assigned_to TEXT,
    playbook_used TEXT,
    response_actions TEXT,
    resolution_time INTEGER,
    lessons_learned TEXT,
    created_by TEXT DEFAULT 'automated_system'
);

CREATE TABLE IF NOT EXISTS response_actions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    incident_id TEXT NOT NULL,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    action_type TEXT NOT NULL,
    action_description TEXT,
    result TEXT,
    automated BOOLEAN DEFAULT 1,
    FOREIGN KEY (incident_id) REFERENCES incidents (incident_id)
);

CREATE TABLE IF NOT EXISTS threat_indicators (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    indicator_type TEXT NOT NULL CHECK (indicator_type IN ('ip', 'domain', 'hash', 'signature')),
    indicator_value TEXT NOT NULL,
    threat_level TEXT CHECK (threat_level IN ('critical', 'high', 'medium', 'low')),
    first_seen DATETIME DEFAULT CURRENT_TIMESTAMP,
    last_seen DATETIME DEFAULT CURRENT_TIMESTAMP,
    incident_count INTEGER DEFAULT 1,
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'expired', 'whitelisted')),
    notes TEXT
);

CREATE TABLE IF NOT EXISTS quarantine_items (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    incident_id TEXT NOT NULL,
    item_type TEXT NOT NULL CHECK (item_type IN ('file', 'process', 'network', 'user')),
    item_identifier TEXT NOT NULL,
    quarantine_timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    release_timestamp DATETIME,
    status TEXT DEFAULT 'quarantined' CHECK (status IN ('quarantined', 'released', 'deleted')),
    quarantine_reason TEXT,
    FOREIGN KEY (incident_id) REFERENCES incidents (incident_id)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_incidents_timestamp ON incidents(timestamp);
CREATE INDEX IF NOT EXISTS idx_incidents_severity ON incidents(severity);
CREATE INDEX IF NOT EXISTS idx_incidents_status ON incidents(status);
CREATE INDEX IF NOT EXISTS idx_response_incident ON response_actions(incident_id);
CREATE INDEX IF NOT EXISTS idx_indicators_type ON threat_indicators(indicator_type);
CREATE INDEX IF NOT EXISTS idx_indicators_value ON threat_indicators(indicator_value);
EOF

    sqlite3 "$INCIDENT_DIR/incidents.db" < "$INCIDENT_DIR/create_db.sql"
    rm "$INCIDENT_DIR/create_db.sql"
    
    log_success "Incident response database created"
}

# Create incident response engine
create_response_engine() {
    log_info "Creating incident response engine"
    
    cat > "$RESPONSE_DIR/incident_handler.py" << 'EOF'
#!/usr/bin/env python3

import json
import sqlite3
import subprocess
import datetime
import os
import uuid
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from pathlib import Path
from typing import Dict, List, Any

class IncidentResponseEngine:
    def __init__(self, db_path="/opt/jstack-security/incidents/incidents.db"):
        self.db_path = db_path
        self.playbooks_dir = "/opt/jstack-security/playbooks"
        self.quarantine_dir = "/opt/jstack-security/quarantine"
        
    def create_incident(self, severity: str, category: str, title: str, 
                       description: str = "", source_ip: str = None, 
                       target_resource: str = None) -> str:
        """Create a new security incident"""
        incident_id = f"INC-{datetime.datetime.now().strftime('%Y%m%d')}-{str(uuid.uuid4())[:8].upper()}"
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO incidents 
            (incident_id, severity, category, title, description, source_ip, target_resource)
            VALUES (?, ?, ?, ?, ?, ?, ?)
        ''', (incident_id, severity, category, title, description, source_ip, target_resource))
        
        conn.commit()
        conn.close()
        
        print(f"Incident created: {incident_id}")
        
        # Trigger automated response
        self.trigger_automated_response(incident_id)
        
        return incident_id
    
    def trigger_automated_response(self, incident_id: str):
        """Trigger automated response based on incident details"""
        incident = self.get_incident(incident_id)
        if not incident:
            return
        
        print(f"Triggering automated response for incident: {incident_id}")
        
        # Determine appropriate playbook
        playbook = self.select_playbook(incident)
        if playbook:
            self.execute_playbook(incident_id, playbook)
        
        # Send notifications
        self.send_incident_notification(incident)
        
        # Update incident status
        self.update_incident_status(incident_id, 'investigating')
    
    def select_playbook(self, incident: Dict[str, Any]) -> str:
        """Select appropriate response playbook based on incident details"""
        category = incident['category'].lower()
        severity = incident['severity'].lower()
        
        # Map incident types to playbooks
        playbook_mapping = {
            'brute_force': 'brute_force_response.json',
            'intrusion_attempt': 'intrusion_response.json',
            'malware': 'malware_response.json',
            'data_breach': 'data_breach_response.json',
            'ddos': 'ddos_response.json',
            'unauthorized_access': 'access_response.json'
        }
        
        playbook_file = playbook_mapping.get(category)
        if playbook_file:
            playbook_path = f"{self.playbooks_dir}/{playbook_file}"
            if Path(playbook_path).exists():
                return playbook_path
        
        # Default to generic response for critical/high severity
        if severity in ['critical', 'high']:
            return f"{self.playbooks_dir}/generic_high_severity.json"
        else:
            return f"{self.playbooks_dir}/generic_response.json"
    
    def execute_playbook(self, incident_id: str, playbook_path: str):
        """Execute incident response playbook"""
        try:
            with open(playbook_path, 'r') as f:
                playbook = json.load(f)
            
            print(f"Executing playbook: {playbook['name']}")
            
            for step in playbook.get('steps', []):
                action_result = self.execute_response_action(incident_id, step)
                self.log_response_action(incident_id, step['type'], 
                                       step['description'], action_result)
                
                # Stop execution if critical step fails
                if step.get('critical', False) and not action_result:
                    print(f"Critical step failed: {step['description']}")
                    break
            
            # Update incident with playbook used
            self.update_incident(incident_id, {'playbook_used': playbook['name']})
            
        except Exception as e:
            print(f"Error executing playbook: {e}")
            self.log_response_action(incident_id, 'error', f"Playbook execution failed: {e}", False)
    
    def execute_response_action(self, incident_id: str, step: Dict[str, Any]) -> bool:
        """Execute individual response action"""
        action_type = step['type']
        
        try:
            if action_type == 'block_ip':
                return self.block_ip_address(step['target'])
            
            elif action_type == 'quarantine_file':
                return self.quarantine_file(incident_id, step['target'])
            
            elif action_type == 'stop_service':
                return self.stop_service(step['target'])
            
            elif action_type == 'isolate_container':
                return self.isolate_container(step['target'])
            
            elif action_type == 'collect_logs':
                return self.collect_logs(step.get('sources', []))
            
            elif action_type == 'send_alert':
                return self.send_alert(step['message'], step.get('urgency', 'medium'))
            
            elif action_type == 'backup_evidence':
                return self.backup_evidence(incident_id, step.get('sources', []))
            
            else:
                print(f"Unknown action type: {action_type}")
                return False
                
        except Exception as e:
            print(f"Action execution failed: {e}")
            return False
    
    def block_ip_address(self, ip_address: str) -> bool:
        """Block IP address using fail2ban"""
        try:
            # Add IP to fail2ban jail
            result = subprocess.run(['sudo', 'fail2ban-client', 'set', 'jarvis-web-protection', 'banip', ip_address],
                                  capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                print(f"Successfully blocked IP: {ip_address}")
                
                # Add to threat indicators
                self.add_threat_indicator('ip', ip_address, 'high', f"Blocked due to incident response")
                
                return True
            else:
                print(f"Failed to block IP {ip_address}: {result.stderr}")
                return False
                
        except Exception as e:
            print(f"Error blocking IP {ip_address}: {e}")
            return False
    
    def quarantine_file(self, incident_id: str, file_path: str) -> bool:
        """Quarantine suspicious file"""
        try:
            if not Path(file_path).exists():
                print(f"File not found for quarantine: {file_path}")
                return False
            
            # Create quarantine directory for this incident
            quarantine_path = f"{self.quarantine_dir}/{incident_id}"
            os.makedirs(quarantine_path, exist_ok=True)
            
            # Move file to quarantine
            quarantine_file = f"{quarantine_path}/{Path(file_path).name}"
            subprocess.run(['sudo', 'mv', file_path, quarantine_file], check=True)
            
            # Log quarantine action
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            cursor.execute('''
                INSERT INTO quarantine_items (incident_id, item_type, item_identifier, quarantine_reason)
                VALUES (?, 'file', ?, 'Suspicious file quarantined during incident response')
            ''', (incident_id, quarantine_file))
            conn.commit()
            conn.close()
            
            print(f"File quarantined: {file_path} -> {quarantine_file}")
            return True
            
        except Exception as e:
            print(f"Error quarantining file {file_path}: {e}")
            return False
    
    def stop_service(self, service_name: str) -> bool:
        """Stop system service"""
        try:
            result = subprocess.run(['sudo', 'systemctl', 'stop', service_name],
                                  capture_output=True, text=True, timeout=30)
            
            if result.returncode == 0:
                print(f"Successfully stopped service: {service_name}")
                return True
            else:
                print(f"Failed to stop service {service_name}: {result.stderr}")
                return False
                
        except Exception as e:
            print(f"Error stopping service {service_name}: {e}")
            return False
    
    def isolate_container(self, container_name: str) -> bool:
        """Isolate Docker container by stopping it"""
        try:
            # Stop the container
            result = subprocess.run(['docker', 'stop', container_name],
                                  capture_output=True, text=True, timeout=60)
            
            if result.returncode == 0:
                print(f"Container isolated (stopped): {container_name}")
                
                # Log quarantine action
                conn = sqlite3.connect(self.db_path)
                cursor = conn.cursor()
                cursor.execute('''
                    INSERT INTO quarantine_items (incident_id, item_type, item_identifier, quarantine_reason)
                    VALUES (?, 'container', ?, 'Container isolated during incident response')
                ''', (container_name, container_name, 'Container isolation'))
                conn.commit()
                conn.close()
                
                return True
            else:
                print(f"Failed to isolate container {container_name}: {result.stderr}")
                return False
                
        except Exception as e:
            print(f"Error isolating container {container_name}: {e}")
            return False
    
    def collect_logs(self, log_sources: List[str]) -> bool:
        """Collect logs for evidence"""
        try:
            timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
            evidence_dir = f"/opt/jstack-security/evidence/logs_{timestamp}"
            os.makedirs(evidence_dir, exist_ok=True)
            
            for source in log_sources:
                if Path(source).exists():
                    dest_file = f"{evidence_dir}/{Path(source).name}"
                    subprocess.run(['sudo', 'cp', source, dest_file], check=True)
                    print(f"Collected log: {source}")
            
            print(f"Logs collected to: {evidence_dir}")
            return True
            
        except Exception as e:
            print(f"Error collecting logs: {e}")
            return False
    
    def send_alert(self, message: str, urgency: str = 'medium') -> bool:
        """Send alert notification"""
        try:
            # Use the existing alerting system
            alert_script = "/opt/jstack-security/scripts/send_alert.sh"
            if Path(alert_script).exists():
                subprocess.run(['bash', alert_script, urgency, message], check=True)
                return True
            else:
                print(f"Alert: [{urgency.upper()}] {message}")
                return True
                
        except Exception as e:
            print(f"Error sending alert: {e}")
            return False
    
    def backup_evidence(self, incident_id: str, sources: List[str]) -> bool:
        """Backup evidence for incident"""
        try:
            evidence_dir = f"/opt/jstack-security/evidence/{incident_id}"
            os.makedirs(evidence_dir, exist_ok=True)
            
            for source in sources:
                if Path(source).exists():
                    if Path(source).is_file():
                        dest_file = f"{evidence_dir}/{Path(source).name}"
                        subprocess.run(['sudo', 'cp', source, dest_file], check=True)
                    else:
                        dest_dir = f"{evidence_dir}/{Path(source).name}"
                        subprocess.run(['sudo', 'cp', '-r', source, dest_dir], check=True)
            
            print(f"Evidence backed up to: {evidence_dir}")
            return True
            
        except Exception as e:
            print(f"Error backing up evidence: {e}")
            return False
    
    def get_incident(self, incident_id: str) -> Dict[str, Any]:
        """Get incident details"""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        cursor = conn.cursor()
        
        cursor.execute('SELECT * FROM incidents WHERE incident_id = ?', (incident_id,))
        result = cursor.fetchone()
        conn.close()
        
        return dict(result) if result else None
    
    def update_incident_status(self, incident_id: str, status: str):
        """Update incident status"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute('UPDATE incidents SET status = ? WHERE incident_id = ?', (status, incident_id))
        conn.commit()
        conn.close()
    
    def update_incident(self, incident_id: str, updates: Dict[str, Any]):
        """Update incident with multiple fields"""
        if not updates:
            return
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        set_clause = ', '.join([f"{key} = ?" for key in updates.keys()])
        values = list(updates.values()) + [incident_id]
        
        cursor.execute(f'UPDATE incidents SET {set_clause} WHERE incident_id = ?', values)
        conn.commit()
        conn.close()
    
    def log_response_action(self, incident_id: str, action_type: str, description: str, result: bool):
        """Log response action taken"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO response_actions (incident_id, action_type, action_description, result)
            VALUES (?, ?, ?, ?)
        ''', (incident_id, action_type, description, str(result)))
        
        conn.commit()
        conn.close()
    
    def add_threat_indicator(self, indicator_type: str, value: str, threat_level: str, notes: str = ""):
        """Add threat indicator to database"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Check if indicator already exists
        cursor.execute('SELECT * FROM threat_indicators WHERE indicator_value = ?', (value,))
        existing = cursor.fetchone()
        
        if existing:
            # Update last seen and increment count
            cursor.execute('''
                UPDATE threat_indicators 
                SET last_seen = CURRENT_TIMESTAMP, incident_count = incident_count + 1
                WHERE indicator_value = ?
            ''', (value,))
        else:
            # Insert new indicator
            cursor.execute('''
                INSERT INTO threat_indicators 
                (indicator_type, indicator_value, threat_level, notes)
                VALUES (?, ?, ?, ?)
            ''', (indicator_type, value, threat_level, notes))
        
        conn.commit()
        conn.close()
    
    def send_incident_notification(self, incident: Dict[str, Any]):
        """Send incident notification"""
        subject = f"Security Incident: {incident['incident_id']} - {incident['severity'].upper()}"
        message = f"""
Security Incident Alert

Incident ID: {incident['incident_id']}
Severity: {incident['severity'].upper()}
Category: {incident['category']}
Title: {incident['title']}
Description: {incident['description']}
Source IP: {incident.get('source_ip', 'N/A')}
Target Resource: {incident.get('target_resource', 'N/A')}
Status: {incident['status']}
Timestamp: {incident['timestamp']}

Automated response has been initiated.
        """
        
        self.send_alert(message, incident['severity'])


if __name__ == "__main__":
    import sys
    
    engine = IncidentResponseEngine()
    
    if len(sys.argv) < 2:
        print("Usage: incident_handler.py <command> [args...]")
        print("Commands:")
        print("  create <severity> <category> <title> [description] - Create incident")
        print("  respond <incident_id>                            - Trigger response")
        print("  status <incident_id> <new_status>               - Update status")
        sys.exit(1)
    
    command = sys.argv[1]
    
    if command == "create" and len(sys.argv) >= 5:
        severity = sys.argv[2]
        category = sys.argv[3] 
        title = sys.argv[4]
        description = sys.argv[5] if len(sys.argv) > 5 else ""
        
        incident_id = engine.create_incident(severity, category, title, description)
        print(f"Created incident: {incident_id}")
        
    elif command == "respond" and len(sys.argv) >= 3:
        incident_id = sys.argv[2]
        engine.trigger_automated_response(incident_id)
        
    elif command == "status" and len(sys.argv) >= 4:
        incident_id = sys.argv[2]
        new_status = sys.argv[3]
        engine.update_incident_status(incident_id, new_status)
        print(f"Updated incident {incident_id} status to: {new_status}")
        
    else:
        print("Invalid command or arguments")
EOF

    chmod +x "$RESPONSE_DIR/incident_handler.py"
    
    log_success "Incident response engine created"
}

# Create response playbooks
create_response_playbooks() {
    log_info "Creating incident response playbooks"
    
    # Brute force response playbook
    cat > "$PLAYBOOKS_DIR/brute_force_response.json" << 'EOF'
{
    "name": "Brute Force Attack Response",
    "version": "1.0",
    "description": "Automated response to brute force authentication attacks",
    "trigger_conditions": {
        "category": "brute_force",
        "severity": ["high", "critical"]
    },
    "steps": [
        {
            "type": "block_ip",
            "description": "Block source IP address",
            "target": "{{source_ip}}",
            "critical": true
        },
        {
            "type": "collect_logs",
            "description": "Collect authentication logs",
            "sources": [
                "/var/log/auth.log",
                "/var/log/fail2ban.log"
            ]
        },
        {
            "type": "send_alert",
            "description": "Send high priority alert",
            "message": "Brute force attack detected and blocked",
            "urgency": "high"
        },
        {
            "type": "backup_evidence",
            "description": "Backup attack evidence",
            "sources": [
                "/var/log/auth.log",
                "/opt/jstack-security/logs/security.log"
            ]
        }
    ]
}
EOF

    # Malware response playbook
    cat > "$PLAYBOOKS_DIR/malware_response.json" << 'EOF'
{
    "name": "Malware Incident Response",
    "version": "1.0", 
    "description": "Automated response to malware detection",
    "trigger_conditions": {
        "category": "malware",
        "severity": ["medium", "high", "critical"]
    },
    "steps": [
        {
            "type": "quarantine_file",
            "description": "Quarantine malicious file",
            "target": "{{malware_file}}",
            "critical": true
        },
        {
            "type": "isolate_container", 
            "description": "Isolate affected container",
            "target": "{{affected_container}}"
        },
        {
            "type": "collect_logs",
            "description": "Collect system and container logs",
            "sources": [
                "/var/log/syslog",
                "/var/log/docker.log"
            ]
        },
        {
            "type": "send_alert",
            "description": "Send critical alert",
            "message": "Malware detected and contained",
            "urgency": "critical"
        },
        {
            "type": "backup_evidence",
            "description": "Backup malware evidence",
            "sources": [
                "/opt/jstack-security/quarantine/",
                "/var/log/syslog"
            ]
        }
    ]
}
EOF

    # Generic high severity response
    cat > "$PLAYBOOKS_DIR/generic_high_severity.json" << 'EOF'
{
    "name": "Generic High Severity Response",
    "version": "1.0",
    "description": "Default response for high severity incidents",
    "trigger_conditions": {
        "severity": ["high", "critical"]
    },
    "steps": [
        {
            "type": "send_alert",
            "description": "Send immediate alert",
            "message": "High severity security incident detected",
            "urgency": "high"
        },
        {
            "type": "collect_logs",
            "description": "Collect relevant logs",
            "sources": [
                "/var/log/syslog",
                "/var/log/auth.log",
                "/opt/jstack-security/logs/security.log"
            ]
        },
        {
            "type": "backup_evidence",
            "description": "Backup incident evidence", 
            "sources": [
                "/var/log/",
                "/opt/jstack-security/logs/"
            ]
        }
    ]
}
EOF

    log_success "Response playbooks created"
}

# Create incident monitoring service
create_monitoring_service() {
    log_info "Creating incident monitoring service"
    
    # Create incident monitor script
    cat > "$RESPONSE_DIR/incident_monitor.py" << 'EOF'
#!/usr/bin/env python3

import time
import subprocess
import re
import sqlite3
from pathlib import Path
from incident_handler import IncidentResponseEngine

class IncidentMonitor:
    def __init__(self):
        self.engine = IncidentResponseEngine()
        self.monitored_logs = [
            "/var/log/auth.log",
            "/var/log/fail2ban.log", 
            "/opt/jstack-security/logs/security.log"
        ]
        self.last_positions = {}
        
    def monitor_logs(self):
        """Monitor logs for security incidents"""
        for log_file in self.monitored_logs:
            if Path(log_file).exists():
                self.check_log_file(log_file)
    
    def check_log_file(self, log_file: str):
        """Check log file for new security events"""
        try:
            with open(log_file, 'r') as f:
                # Get current position
                current_pos = f.tell()
                
                # Get last known position
                last_pos = self.last_positions.get(log_file, 0)
                
                # Seek to last position
                f.seek(last_pos)
                new_lines = f.readlines()
                
                # Update position
                self.last_positions[log_file] = f.tell()
                
                # Analyze new lines
                for line in new_lines:
                    self.analyze_log_line(line.strip(), log_file)
                    
        except Exception as e:
            print(f"Error monitoring {log_file}: {e}")
    
    def analyze_log_line(self, line: str, source_file: str):
        """Analyze log line for security incidents"""
        
        # Brute force detection
        if "Failed password" in line and "ssh" in line.lower():
            match = re.search(r'from (\d+\.\d+\.\d+\.\d+)', line)
            if match:
                source_ip = match.group(1)
                
                # Count recent failures from this IP
                recent_failures = self.count_recent_failures(source_ip)
                if recent_failures >= 5:  # Threshold for brute force
                    self.engine.create_incident(
                        severity="high",
                        category="brute_force", 
                        title=f"Brute force attack from {source_ip}",
                        description=f"Multiple failed SSH login attempts from {source_ip}",
                        source_ip=source_ip,
                        target_resource="SSH service"
                    )
        
        # Intrusion attempt detection
        if "POSSIBLE BREAK-IN ATTEMPT" in line or "security violation" in line.lower():
            match = re.search(r'from (\d+\.\d+\.\d+\.\d+)', line)
            source_ip = match.group(1) if match else "unknown"
            
            self.engine.create_incident(
                severity="critical",
                category="intrusion_attempt",
                title=f"Intrusion attempt detected from {source_ip}",
                description=f"Security violation detected: {line}",
                source_ip=source_ip
            )
        
        # Fail2ban actions
        if "Ban" in line and "fail2ban" in source_file:
            match = re.search(r'Ban (\d+\.\d+\.\d+\.\d+)', line)
            if match:
                source_ip = match.group(1)
                print(f"IP {source_ip} automatically banned by fail2ban")
    
    def count_recent_failures(self, ip_address: str, minutes: int = 10) -> int:
        """Count recent authentication failures from IP"""
        try:
            # Use journalctl to count recent SSH failures
            result = subprocess.run([
                'journalctl', 
                '--since', f'{minutes} minutes ago',
                '-u', 'ssh',
                '--grep', f'Failed password.*from {ip_address}'
            ], capture_output=True, text=True, timeout=30)
            
            return result.stdout.count('Failed password') if result.returncode == 0 else 0
            
        except Exception:
            return 0
    
    def run_monitoring_cycle(self):
        """Run single monitoring cycle"""
        print(f"Starting incident monitoring cycle at {time.strftime('%Y-%m-%d %H:%M:%S')}")
        
        # Monitor logs
        self.monitor_logs()
        
        # Check system status
        self.check_system_status()
        
        print("Monitoring cycle completed")
    
    def check_system_status(self):
        """Check overall system security status"""
        # Check critical services
        critical_services = ['fail2ban', 'nginx', 'docker']
        
        for service in critical_services:
            try:
                result = subprocess.run(['systemctl', 'is-active', service],
                                      capture_output=True, text=True)
                if result.returncode != 0:
                    self.engine.create_incident(
                        severity="high",
                        category="service_failure",
                        title=f"Critical service {service} not running",
                        description=f"Service {service} is inactive or failed",
                        target_resource=service
                    )
            except Exception as e:
                print(f"Error checking service {service}: {e}")
    
    def start_monitoring(self, interval: int = 60):
        """Start continuous monitoring"""
        print(f"Starting incident monitoring with {interval}s interval")
        
        try:
            while True:
                self.run_monitoring_cycle()
                time.sleep(interval)
                
        except KeyboardInterrupt:
            print("\nStopping incident monitoring")
        except Exception as e:
            print(f"Monitoring error: {e}")

if __name__ == "__main__":
    import sys
    
    monitor = IncidentMonitor()
    
    if len(sys.argv) > 1 and sys.argv[1] == "daemon":
        # Run as daemon
        monitor.start_monitoring()
    else:
        # Run single cycle
        monitor.run_monitoring_cycle()
EOF

    chmod +x "$RESPONSE_DIR/incident_monitor.py"
    
    log_success "Incident monitoring service created"
}

# Create systemd service for incident monitoring
create_incident_service() {
    log_info "Creating incident response systemd service"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would create systemd service for incident monitoring"
        return 0
    fi
    
    cat > "/tmp/jarvis-incident-monitor.service" << EOF
[Unit]
Description=jstack Incident Response Monitor
After=network.target

[Service]
Type=simple
User=jarvis
Group=jarvis
WorkingDirectory=$RESPONSE_DIR
ExecStart=/usr/bin/python3 $RESPONSE_DIR/incident_monitor.py daemon
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    sudo mv "/tmp/jarvis-incident-monitor.service" "/etc/systemd/system/"
    sudo systemctl daemon-reload
    sudo systemctl enable jarvis-incident-monitor
    
    log_success "Incident monitoring systemd service created"
}

# Main incident response setup function
setup_incident_response() {
    log_info "Setting up automated incident response system"
    
    start_progress "Initializing incident response system"
    init_incident_response
    stop_progress
    
    start_progress "Creating incident database"
    create_incident_database
    stop_progress
    
    start_progress "Creating response engine"
    create_response_engine
    stop_progress
    
    start_progress "Creating response playbooks"
    create_response_playbooks
    stop_progress
    
    start_progress "Creating monitoring service"
    create_monitoring_service
    stop_progress
    
    start_progress "Creating systemd service"
    create_incident_service
    stop_progress
    
    log_success "Automated incident response system setup completed"
    
    # Summary
    log_info "Incident Response System Summary:"
    log_info "• Automated Detection: Real-time log monitoring"
    log_info "• Response Engine: Playbook-driven automation"
    log_info "• Incident Database: SQLite with comprehensive tracking"
    log_info "• Response Actions: Block IPs, quarantine files, isolate containers"
    log_info "• Service: systemctl status jarvis-incident-monitor"
    log_info "• Manual Response: python3 $RESPONSE_DIR/incident_handler.py"
}

# Validation function
validate_incident_response() {
    log_info "Validating incident response configuration"
    
    local validation_passed=true
    
    # Check required directories
    local required_dirs=("$INCIDENT_DIR" "$RESPONSE_DIR" "$PLAYBOOKS_DIR" "$QUARANTINE_DIR")
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
        "$RESPONSE_DIR/incident_handler.py"
        "$RESPONSE_DIR/incident_monitor.py"
        "$PLAYBOOKS_DIR/brute_force_response.json"
        "$PLAYBOOKS_DIR/malware_response.json"
        "$PLAYBOOKS_DIR/generic_high_severity.json"
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
        log_success "Incident response system validation passed"
    else
        log_error "Incident response system validation failed"
        return 1
    fi
}

# Script usage information
show_help() {
    cat << EOF
jstack Automated Incident Response System

USAGE:
    bash incident_response.sh [COMMAND]

COMMANDS:
    setup           Set up complete incident response system
    validate        Validate incident response configuration
    help            Show this help message

EXAMPLES:
    # Set up complete incident response system
    bash incident_response.sh setup

    # Dry run validation
    DRY_RUN=true bash incident_response.sh validate

INCIDENT MANAGEMENT:
    # Create incident manually
    python3 $RESPONSE_DIR/incident_handler.py create high brute_force "SSH Attack" "Multiple failed logins"
    
    # Trigger response for existing incident
    python3 $RESPONSE_DIR/incident_handler.py respond INC-20250907-ABC12345
    
    # Update incident status
    python3 $RESPONSE_DIR/incident_handler.py status INC-20250907-ABC12345 resolved

MONITORING:
    # Start monitoring daemon
    python3 $RESPONSE_DIR/incident_monitor.py daemon
    
    # Run single monitoring cycle
    python3 $RESPONSE_DIR/incident_monitor.py

SYSTEM SERVICE:
    systemctl status jarvis-incident-monitor
    systemctl start jarvis-incident-monitor
    systemctl stop jarvis-incident-monitor

FILES CREATED:
    $RESPONSE_DIR/incident_handler.py        - Core incident response engine
    $RESPONSE_DIR/incident_monitor.py        - Real-time monitoring service
    $INCIDENT_DIR/incidents.db               - Incident tracking database
    $PLAYBOOKS_DIR/*.json                    - Response playbooks

LOGS:
    journalctl -u jarvis-incident-monitor    - Service logs
    /opt/jstack-security/logs/incidents.log  - Incident logs

EOF
}

# Main execution
main() {
    local command="${1:-setup}"
    
    case "$command" in
        "setup")
            setup_incident_response
            ;;
        "validate")
            validate_incident_response
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