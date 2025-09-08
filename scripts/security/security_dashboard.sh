#!/bin/bash

# JarvisJR Stack Security Dashboard and Reporting System
# Phase 4: Monitoring & Alerting - Security Metrics Dashboard
# Provides comprehensive security metrics collection, dashboard generation, and automated reporting

set -e

# Source common utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
source "${PROJECT_ROOT}/scripts/lib/common.sh"

# Global variables
METRICS_DIR="/opt/jarvis-security/metrics"
DASHBOARD_DIR="/opt/jarvis-security/dashboard"
REPORTS_DIR="/opt/jarvis-security/reports"
WEB_DIR="/var/www/jarvis-security"
RETENTION_DAYS=90

# Initialize security dashboard system
init_dashboard() {
    log_info "Initializing security dashboard system"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would create dashboard directories and configuration"
        return 0
    fi
    
    # Create directory structure
    sudo mkdir -p "$METRICS_DIR" "$DASHBOARD_DIR" "$REPORTS_DIR" "$WEB_DIR"
    sudo chown -R jarvis:jarvis "$METRICS_DIR" "$DASHBOARD_DIR" "$REPORTS_DIR"
    sudo chown -R www-data:www-data "$WEB_DIR"
    
    # Install required packages
    sudo apt-get update
    sudo apt-get install -y python3-pip python3-venv jq bc sqlite3 cron
    
    # Create Python virtual environment for dashboard
    python3 -m venv "$DASHBOARD_DIR/venv"
    source "$DASHBOARD_DIR/venv/bin/activate"
    pip install flask plotly pandas numpy sqlite3 jinja2
    
    log_success "Dashboard system initialized successfully"
}

# Create security metrics collection system
create_metrics_collector() {
    log_info "Creating security metrics collector"
    
    cat > "$METRICS_DIR/collect_metrics.py" << 'EOF'
#!/usr/bin/env python3

import json
import sqlite3
import subprocess
import datetime
import os
import re
from pathlib import Path

class SecurityMetricsCollector:
    def __init__(self, db_path="/opt/jarvis-security/metrics/security_metrics.db"):
        self.db_path = db_path
        self.init_database()
    
    def init_database(self):
        """Initialize SQLite database for metrics storage"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Security events table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS security_events (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                event_type TEXT NOT NULL,
                severity TEXT NOT NULL,
                source_ip TEXT,
                target_service TEXT,
                event_count INTEGER DEFAULT 1,
                details TEXT
            )
        ''')
        
        # Failed login attempts
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS failed_logins (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                ip_address TEXT NOT NULL,
                service TEXT NOT NULL,
                username TEXT,
                attempt_count INTEGER DEFAULT 1
            )
        ''')
        
        # Container security metrics
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS container_metrics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                container_name TEXT NOT NULL,
                vulnerability_count INTEGER DEFAULT 0,
                compliance_score REAL DEFAULT 0.0,
                resource_usage TEXT
            )
        ''')
        
        # Network security metrics
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS network_metrics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
                blocked_ips INTEGER DEFAULT 0,
                suspicious_requests INTEGER DEFAULT 0,
                firewall_drops INTEGER DEFAULT 0,
                ssl_errors INTEGER DEFAULT 0
            )
        ''')
        
        conn.commit()
        conn.close()
    
    def collect_fail2ban_metrics(self):
        """Collect fail2ban statistics"""
        try:
            result = subprocess.run(['sudo', 'fail2ban-client', 'status'], 
                                  capture_output=True, text=True, timeout=10)
            if result.returncode == 0:
                # Parse jail status
                jails = re.findall(r'Jail list:\s*(.*)', result.stdout)
                if jails:
                    jail_names = [j.strip() for j in jails[0].split(',')]
                    
                    for jail in jail_names:
                        jail_result = subprocess.run(['sudo', 'fail2ban-client', 'status', jail],
                                                   capture_output=True, text=True, timeout=5)
                        if jail_result.returncode == 0:
                            banned = re.search(r'Currently banned:\s*(\d+)', jail_result.stdout)
                            total_banned = re.search(r'Total banned:\s*(\d+)', jail_result.stdout)
                            
                            if banned and total_banned:
                                self.store_network_metric('fail2ban_banned', int(banned.group(1)))
                                self.store_network_metric('fail2ban_total', int(total_banned.group(1)))
        except Exception as e:
            print(f"Error collecting fail2ban metrics: {e}")
    
    def collect_docker_metrics(self):
        """Collect Docker container security metrics"""
        try:
            # Get container list
            result = subprocess.run(['docker', 'ps', '--format', '{{.Names}}'],
                                  capture_output=True, text=True, timeout=10)
            if result.returncode == 0:
                containers = result.stdout.strip().split('\n')
                
                for container in containers:
                    if container:
                        # Run Trivy scan for vulnerabilities
                        trivy_result = subprocess.run(['trivy', 'image', '--format', 'json', 
                                                     '--quiet', container],
                                                    capture_output=True, text=True, timeout=30)
                        
                        vuln_count = 0
                        if trivy_result.returncode == 0:
                            try:
                                trivy_data = json.loads(trivy_result.stdout)
                                if 'Results' in trivy_data:
                                    for result in trivy_data['Results']:
                                        if 'Vulnerabilities' in result:
                                            vuln_count += len(result['Vulnerabilities'])
                            except json.JSONDecodeError:
                                pass
                        
                        self.store_container_metric(container, vuln_count)
        except Exception as e:
            print(f"Error collecting Docker metrics: {e}")
    
    def collect_system_metrics(self):
        """Collect system security metrics"""
        try:
            # Check for suspicious processes
            ps_result = subprocess.run(['ps', 'aux'], capture_output=True, text=True, timeout=10)
            suspicious_count = 0
            
            if ps_result.returncode == 0:
                suspicious_patterns = ['cryptominer', 'botnet', 'backdoor', 'malware']
                for line in ps_result.stdout.lower().split('\n'):
                    for pattern in suspicious_patterns:
                        if pattern in line:
                            suspicious_count += 1
            
            self.store_security_event('suspicious_processes', 'medium', None, 'system', 
                                    suspicious_count, f"Found {suspicious_count} suspicious processes")
            
            # Check failed SSH attempts
            auth_log = Path('/var/log/auth.log')
            if auth_log.exists():
                with open(auth_log, 'r') as f:
                    lines = f.readlines()[-1000:]  # Last 1000 lines
                    failed_attempts = len([line for line in lines if 'Failed password' in line])
                    self.store_security_event('ssh_failures', 'high', None, 'ssh',
                                            failed_attempts, f"SSH failed attempts: {failed_attempts}")
        except Exception as e:
            print(f"Error collecting system metrics: {e}")
    
    def store_security_event(self, event_type, severity, source_ip, target_service, count, details):
        """Store security event in database"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute('''
            INSERT INTO security_events (event_type, severity, source_ip, target_service, event_count, details)
            VALUES (?, ?, ?, ?, ?, ?)
        ''', (event_type, severity, source_ip, target_service, count, details))
        conn.commit()
        conn.close()
    
    def store_container_metric(self, container_name, vuln_count):
        """Store container security metric"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        cursor.execute('''
            INSERT INTO container_metrics (container_name, vulnerability_count)
            VALUES (?, ?)
        ''', (container_name, vuln_count))
        conn.commit()
        conn.close()
    
    def store_network_metric(self, metric_type, value):
        """Store network security metric"""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        if metric_type == 'fail2ban_banned':
            cursor.execute('INSERT INTO network_metrics (blocked_ips) VALUES (?)', (value,))
        elif metric_type == 'fail2ban_total':
            cursor.execute('UPDATE network_metrics SET blocked_ips = ? WHERE id = (SELECT MAX(id) FROM network_metrics)', (value,))
        
        conn.commit()
        conn.close()
    
    def run_collection(self):
        """Run complete metrics collection cycle"""
        print(f"Starting metrics collection at {datetime.datetime.now()}")
        
        self.collect_fail2ban_metrics()
        self.collect_docker_metrics()
        self.collect_system_metrics()
        
        print("Metrics collection completed")

if __name__ == "__main__":
    collector = SecurityMetricsCollector()
    collector.run_collection()
EOF

    chmod +x "$METRICS_DIR/collect_metrics.py"
    
    log_success "Security metrics collector created"
}

# Create web dashboard application
create_web_dashboard() {
    log_info "Creating web dashboard application"
    
    cat > "$DASHBOARD_DIR/dashboard_app.py" << 'EOF'
#!/usr/bin/env python3

from flask import Flask, render_template, jsonify
import sqlite3
import json
import datetime
from pathlib import Path
import plotly.graph_objs as go
import plotly.utils

app = Flask(__name__)
DB_PATH = "/opt/jarvis-security/metrics/security_metrics.db"

def get_db_connection():
    """Get database connection"""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn

@app.route('/')
def dashboard():
    """Main dashboard page"""
    return render_template('dashboard.html')

@app.route('/api/metrics/summary')
def metrics_summary():
    """Get summary metrics for dashboard"""
    conn = get_db_connection()
    
    # Get recent security events count
    events_count = conn.execute('''
        SELECT COUNT(*) as count FROM security_events 
        WHERE timestamp > datetime('now', '-24 hours')
    ''').fetchone()['count']
    
    # Get total vulnerabilities
    vulns_result = conn.execute('''
        SELECT SUM(vulnerability_count) as total 
        FROM container_metrics 
        WHERE timestamp > datetime('now', '-24 hours')
    ''').fetchone()
    total_vulns = vulns_result['total'] if vulns_result['total'] else 0
    
    # Get blocked IPs
    blocked_ips = conn.execute('''
        SELECT MAX(blocked_ips) as blocked 
        FROM network_metrics 
        WHERE timestamp > datetime('now', '-24 hours')
    ''').fetchone()
    blocked_count = blocked_ips['blocked'] if blocked_ips['blocked'] else 0
    
    # Get critical events
    critical_events = conn.execute('''
        SELECT COUNT(*) as count FROM security_events 
        WHERE severity = 'critical' AND timestamp > datetime('now', '-24 hours')
    ''').fetchone()['count']
    
    conn.close()
    
    return jsonify({
        'security_events_24h': events_count,
        'total_vulnerabilities': total_vulns,
        'blocked_ips': blocked_count,
        'critical_events': critical_events,
        'last_updated': datetime.datetime.now().isoformat()
    })

@app.route('/api/metrics/timeline')
def metrics_timeline():
    """Get metrics timeline data"""
    conn = get_db_connection()
    
    # Security events over time
    events = conn.execute('''
        SELECT DATE(timestamp) as date, COUNT(*) as count, severity
        FROM security_events 
        WHERE timestamp > datetime('now', '-30 days')
        GROUP BY DATE(timestamp), severity
        ORDER BY date
    ''').fetchall()
    
    # Convert to format for plotting
    timeline_data = {}
    for event in events:
        date = event['date']
        if date not in timeline_data:
            timeline_data[date] = {'critical': 0, 'high': 0, 'medium': 0, 'low': 0}
        timeline_data[date][event['severity']] = event['count']
    
    conn.close()
    
    return jsonify(timeline_data)

@app.route('/api/metrics/containers')
def container_metrics():
    """Get container security metrics"""
    conn = get_db_connection()
    
    containers = conn.execute('''
        SELECT container_name, 
               AVG(vulnerability_count) as avg_vulns,
               MAX(vulnerability_count) as max_vulns,
               COUNT(*) as scan_count
        FROM container_metrics 
        WHERE timestamp > datetime('now', '-7 days')
        GROUP BY container_name
    ''').fetchall()
    
    conn.close()
    
    return jsonify([dict(row) for row in containers])

@app.route('/api/metrics/threats')
def threat_metrics():
    """Get threat analysis data"""
    conn = get_db_connection()
    
    # Top threat types
    threats = conn.execute('''
        SELECT event_type, COUNT(*) as count, AVG(event_count) as avg_count
        FROM security_events 
        WHERE timestamp > datetime('now', '-7 days')
        GROUP BY event_type
        ORDER BY count DESC
        LIMIT 10
    ''').fetchall()
    
    # Geographic threat distribution (simulated)
    geo_threats = conn.execute('''
        SELECT source_ip, COUNT(*) as count
        FROM security_events 
        WHERE source_ip IS NOT NULL 
        AND timestamp > datetime('now', '-7 days')
        GROUP BY source_ip
        ORDER BY count DESC
        LIMIT 20
    ''').fetchall()
    
    conn.close()
    
    return jsonify({
        'threat_types': [dict(row) for row in threats],
        'geographic': [dict(row) for row in geo_threats]
    })

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080, debug=False)
EOF

    # Create HTML template
    mkdir -p "$DASHBOARD_DIR/templates"
    cat > "$DASHBOARD_DIR/templates/dashboard.html" << 'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>JarvisJR Security Dashboard</title>
    <script src="https://cdn.plot.ly/plotly-latest.min.js"></script>
    <style>
        body { font-family: Arial, sans-serif; margin: 0; padding: 20px; background: #f5f5f5; }
        .header { background: #2c3e50; color: white; padding: 20px; border-radius: 5px; margin-bottom: 20px; }
        .metrics-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); gap: 20px; margin-bottom: 30px; }
        .metric-card { background: white; padding: 20px; border-radius: 5px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); text-align: center; }
        .metric-value { font-size: 2em; font-weight: bold; color: #3498db; }
        .metric-label { color: #7f8c8d; margin-top: 5px; }
        .chart-container { background: white; padding: 20px; border-radius: 5px; box-shadow: 0 2px 5px rgba(0,0,0,0.1); margin-bottom: 20px; }
        .critical { color: #e74c3c; }
        .high { color: #f39c12; }
        .medium { color: #f1c40f; }
        .low { color: #27ae60; }
        .last-updated { text-align: right; color: #7f8c8d; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🛡️ JarvisJR Security Dashboard</h1>
        <p>Real-time security monitoring and threat analysis</p>
    </div>
    
    <div class="metrics-grid">
        <div class="metric-card">
            <div class="metric-value" id="events-24h">-</div>
            <div class="metric-label">Security Events (24h)</div>
        </div>
        <div class="metric-card">
            <div class="metric-value critical" id="critical-events">-</div>
            <div class="metric-label">Critical Events</div>
        </div>
        <div class="metric-card">
            <div class="metric-value" id="vulnerabilities">-</div>
            <div class="metric-label">Total Vulnerabilities</div>
        </div>
        <div class="metric-card">
            <div class="metric-value" id="blocked-ips">-</div>
            <div class="metric-label">Blocked IPs</div>
        </div>
    </div>
    
    <div class="chart-container">
        <h3>Security Events Timeline (30 days)</h3>
        <div id="timeline-chart"></div>
    </div>
    
    <div class="chart-container">
        <h3>Container Security Status</h3>
        <div id="container-chart"></div>
    </div>
    
    <div class="chart-container">
        <h3>Threat Analysis</h3>
        <div id="threat-chart"></div>
    </div>
    
    <div class="last-updated">
        Last updated: <span id="last-update">-</span>
    </div>

    <script>
        // Auto-refresh dashboard every 30 seconds
        setInterval(loadDashboard, 30000);
        loadDashboard();
        
        function loadDashboard() {
            loadSummaryMetrics();
            loadTimelineChart();
            loadContainerChart();
            loadThreatChart();
        }
        
        function loadSummaryMetrics() {
            fetch('/api/metrics/summary')
                .then(response => response.json())
                .then(data => {
                    document.getElementById('events-24h').textContent = data.security_events_24h;
                    document.getElementById('critical-events').textContent = data.critical_events;
                    document.getElementById('vulnerabilities').textContent = data.total_vulnerabilities;
                    document.getElementById('blocked-ips').textContent = data.blocked_ips;
                    document.getElementById('last-update').textContent = new Date(data.last_updated).toLocaleString();
                });
        }
        
        function loadTimelineChart() {
            fetch('/api/metrics/timeline')
                .then(response => response.json())
                .then(data => {
                    const dates = Object.keys(data);
                    const critical = dates.map(date => data[date].critical || 0);
                    const high = dates.map(date => data[date].high || 0);
                    const medium = dates.map(date => data[date].medium || 0);
                    const low = dates.map(date => data[date].low || 0);
                    
                    const traces = [
                        { x: dates, y: critical, name: 'Critical', type: 'scatter', stackgroup: 'one', fillcolor: '#e74c3c' },
                        { x: dates, y: high, name: 'High', type: 'scatter', stackgroup: 'one', fillcolor: '#f39c12' },
                        { x: dates, y: medium, name: 'Medium', type: 'scatter', stackgroup: 'one', fillcolor: '#f1c40f' },
                        { x: dates, y: low, name: 'Low', type: 'scatter', stackgroup: 'one', fillcolor: '#27ae60' }
                    ];
                    
                    Plotly.newPlot('timeline-chart', traces, {
                        title: 'Security Events by Severity',
                        xaxis: { title: 'Date' },
                        yaxis: { title: 'Event Count' }
                    });
                });
        }
        
        function loadContainerChart() {
            fetch('/api/metrics/containers')
                .then(response => response.json())
                .then(data => {
                    const containers = data.map(item => item.container_name);
                    const vulnerabilities = data.map(item => item.avg_vulns);
                    
                    const trace = {
                        x: containers,
                        y: vulnerabilities,
                        type: 'bar',
                        marker: { color: '#3498db' }
                    };
                    
                    Plotly.newPlot('container-chart', [trace], {
                        title: 'Average Vulnerabilities per Container',
                        xaxis: { title: 'Container' },
                        yaxis: { title: 'Vulnerability Count' }
                    });
                });
        }
        
        function loadThreatChart() {
            fetch('/api/metrics/threats')
                .then(response => response.json())
                .then(data => {
                    const labels = data.threat_types.map(item => item.event_type);
                    const values = data.threat_types.map(item => item.count);
                    
                    const trace = {
                        labels: labels,
                        values: values,
                        type: 'pie'
                    };
                    
                    Plotly.newPlot('threat-chart', [trace], {
                        title: 'Threat Distribution by Type'
                    });
                });
        }
    </script>
</body>
</html>
EOF

    log_success "Web dashboard application created"
}

# Create automated reporting system
create_reporting_system() {
    log_info "Creating automated reporting system"
    
    cat > "$REPORTS_DIR/generate_report.py" << 'EOF'
#!/usr/bin/env python3

import sqlite3
import datetime
import json
import smtplib
import os
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from email.mime.base import MIMEBase
from email import encoders
from pathlib import Path

class SecurityReporter:
    def __init__(self, config_file="/opt/jarvis-security/config/reporting.json"):
        self.config_file = config_file
        self.db_path = "/opt/jarvis-security/metrics/security_metrics.db"
        self.load_config()
    
    def load_config(self):
        """Load reporting configuration"""
        default_config = {
            "email": {
                "enabled": False,
                "smtp_server": "localhost",
                "smtp_port": 587,
                "username": "",
                "password": "",
                "from_email": "security@jarvisjr.local",
                "to_emails": []
            },
            "reports": {
                "daily": True,
                "weekly": True,
                "monthly": True
            },
            "thresholds": {
                "critical_events": 5,
                "high_events": 20,
                "vulnerability_count": 50
            }
        }
        
        if Path(self.config_file).exists():
            with open(self.config_file, 'r') as f:
                self.config = json.load(f)
        else:
            self.config = default_config
            os.makedirs(os.path.dirname(self.config_file), exist_ok=True)
            with open(self.config_file, 'w') as f:
                json.dump(default_config, f, indent=2)
    
    def generate_daily_report(self):
        """Generate daily security report"""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        
        # Get yesterday's date
        yesterday = (datetime.datetime.now() - datetime.timedelta(days=1)).strftime('%Y-%m-%d')
        
        # Security events summary
        events = conn.execute('''
            SELECT severity, COUNT(*) as count
            FROM security_events 
            WHERE DATE(timestamp) = ?
            GROUP BY severity
        ''', (yesterday,)).fetchall()
        
        # Container vulnerabilities
        containers = conn.execute('''
            SELECT container_name, MAX(vulnerability_count) as vulns
            FROM container_metrics 
            WHERE DATE(timestamp) = ?
            GROUP BY container_name
        ''', (yesterday,)).fetchall()
        
        # Network metrics
        network = conn.execute('''
            SELECT MAX(blocked_ips) as blocked, MAX(suspicious_requests) as suspicious
            FROM network_metrics 
            WHERE DATE(timestamp) = ?
        ''', (yesterday,)).fetchone()
        
        conn.close()
        
        # Generate report
        report = {
            'date': yesterday,
            'type': 'daily',
            'summary': {
                'total_events': sum(row['count'] for row in events),
                'events_by_severity': {row['severity']: row['count'] for row in events},
                'container_vulnerabilities': {row['container_name']: row['vulns'] for row in containers},
                'network_metrics': {
                    'blocked_ips': network['blocked'] if network else 0,
                    'suspicious_requests': network['suspicious'] if network else 0
                }
            }
        }
        
        return report
    
    def generate_weekly_report(self):
        """Generate weekly security report"""
        conn = sqlite3.connect(self.db_path)
        conn.row_factory = sqlite3.Row
        
        # Get last 7 days
        week_ago = (datetime.datetime.now() - datetime.timedelta(days=7)).strftime('%Y-%m-%d')
        
        # Trending analysis
        events_trend = conn.execute('''
            SELECT DATE(timestamp) as date, severity, COUNT(*) as count
            FROM security_events 
            WHERE timestamp > ?
            GROUP BY DATE(timestamp), severity
            ORDER BY date
        ''', (week_ago,)).fetchall()
        
        # Top threat sources
        top_threats = conn.execute('''
            SELECT source_ip, event_type, COUNT(*) as count
            FROM security_events 
            WHERE timestamp > ? AND source_ip IS NOT NULL
            GROUP BY source_ip, event_type
            ORDER BY count DESC
            LIMIT 10
        ''', (week_ago,)).fetchall()
        
        conn.close()
        
        report = {
            'date_range': f"{week_ago} to {datetime.datetime.now().strftime('%Y-%m-%d')}",
            'type': 'weekly',
            'trends': [dict(row) for row in events_trend],
            'top_threats': [dict(row) for row in top_threats]
        }
        
        return report
    
    def format_report_html(self, report_data):
        """Format report as HTML email"""
        if report_data['type'] == 'daily':
            return self.format_daily_html(report_data)
        elif report_data['type'] == 'weekly':
            return self.format_weekly_html(report_data)
    
    def format_daily_html(self, report):
        """Format daily report as HTML"""
        html = f"""
        <html>
        <head>
            <style>
                body {{ font-family: Arial, sans-serif; }}
                .header {{ background: #2c3e50; color: white; padding: 15px; }}
                .summary {{ background: #ecf0f1; padding: 15px; margin: 10px 0; }}
                .critical {{ color: #e74c3c; }}
                .high {{ color: #f39c12; }}
                .medium {{ color: #f1c40f; }}
                .low {{ color: #27ae60; }}
                table {{ border-collapse: collapse; width: 100%; }}
                th, td {{ border: 1px solid #ddd; padding: 8px; text-align: left; }}
                th {{ background-color: #34495e; color: white; }}
            </style>
        </head>
        <body>
            <div class="header">
                <h2>🛡️ JarvisJR Daily Security Report</h2>
                <p>Date: {report['date']}</p>
            </div>
            
            <div class="summary">
                <h3>Executive Summary</h3>
                <p>Total security events: <strong>{report['summary']['total_events']}</strong></p>
                
                <h4>Events by Severity:</h4>
                <ul>
        """
        
        for severity, count in report['summary']['events_by_severity'].items():
            html += f'<li class="{severity}"><strong>{severity.capitalize()}</strong>: {count} events</li>'
        
        html += """
                </ul>
            </div>
            
            <h3>Container Security Status</h3>
            <table>
                <tr><th>Container</th><th>Vulnerabilities</th></tr>
        """
        
        for container, vulns in report['summary']['container_vulnerabilities'].items():
            html += f"<tr><td>{container}</td><td>{vulns}</td></tr>"
        
        html += f"""
            </table>
            
            <h3>Network Security</h3>
            <p>Blocked IPs: <strong>{report['summary']['network_metrics']['blocked_ips']}</strong></p>
            <p>Suspicious Requests: <strong>{report['summary']['network_metrics']['suspicious_requests']}</strong></p>
            
            <p><em>Generated at {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</em></p>
        </body>
        </html>
        """
        
        return html
    
    def send_email_report(self, report_data, subject):
        """Send report via email"""
        if not self.config['email']['enabled']:
            print("Email reporting is disabled")
            return
        
        try:
            msg = MIMEMultipart()
            msg['From'] = self.config['email']['from_email']
            msg['To'] = ', '.join(self.config['email']['to_emails'])
            msg['Subject'] = subject
            
            html_content = self.format_report_html(report_data)
            msg.attach(MIMEText(html_content, 'html'))
            
            # Add JSON report as attachment
            json_report = json.dumps(report_data, indent=2)
            attachment = MIMEBase('application', 'json')
            attachment.set_payload(json_report.encode())
            encoders.encode_base64(attachment)
            attachment.add_header('Content-Disposition', f'attachment; filename="security_report_{report_data['type']}.json"')
            msg.attach(attachment)
            
            # Send email
            server = smtplib.SMTP(self.config['email']['smtp_server'], self.config['email']['smtp_port'])
            if self.config['email']['username']:
                server.starttls()
                server.login(self.config['email']['username'], self.config['email']['password'])
            
            server.send_message(msg)
            server.quit()
            
            print(f"Report sent successfully to {len(self.config['email']['to_emails'])} recipients")
            
        except Exception as e:
            print(f"Failed to send email report: {e}")
    
    def run_daily_report(self):
        """Generate and send daily report"""
        report = self.generate_daily_report()
        
        # Save to file
        filename = f"/opt/jarvis-security/reports/daily_report_{report['date']}.json"
        with open(filename, 'w') as f:
            json.dump(report, f, indent=2)
        
        # Send email if configured
        self.send_email_report(report, f"JarvisJR Daily Security Report - {report['date']}")
        
        return report
    
    def run_weekly_report(self):
        """Generate and send weekly report"""
        report = self.generate_weekly_report()
        
        # Save to file
        filename = f"/opt/jarvis-security/reports/weekly_report_{datetime.datetime.now().strftime('%Y%m%d')}.json"
        with open(filename, 'w') as f:
            json.dump(report, f, indent=2)
        
        # Send email if configured
        self.send_email_report(report, f"JarvisJR Weekly Security Report - {report['date_range']}")
        
        return report

if __name__ == "__main__":
    import sys
    
    reporter = SecurityReporter()
    
    if len(sys.argv) > 1:
        report_type = sys.argv[1]
        if report_type == 'daily':
            reporter.run_daily_report()
        elif report_type == 'weekly':
            reporter.run_weekly_report()
        else:
            print("Usage: generate_report.py [daily|weekly]")
    else:
        reporter.run_daily_report()
EOF

    chmod +x "$REPORTS_DIR/generate_report.py"
    
    log_success "Automated reporting system created"
}

# Set up cron jobs for automated reporting
setup_reporting_cron() {
    log_info "Setting up automated reporting cron jobs"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would install cron jobs for automated reporting"
        return 0
    fi
    
    # Create cron job for daily reports (6 AM)
    cat > "/tmp/jarvis_security_cron" << EOF
# JarvisJR Security Reporting
0 6 * * * /usr/bin/python3 $REPORTS_DIR/generate_report.py daily >> /opt/jarvis-security/logs/reporting.log 2>&1
0 6 * * 1 /usr/bin/python3 $REPORTS_DIR/generate_report.py weekly >> /opt/jarvis-security/logs/reporting.log 2>&1
*/5 * * * * /usr/bin/python3 $METRICS_DIR/collect_metrics.py >> /opt/jarvis-security/logs/metrics.log 2>&1
EOF
    
    sudo crontab -u jarvis "/tmp/jarvis_security_cron"
    rm "/tmp/jarvis_security_cron"
    
    log_success "Automated reporting cron jobs installed"
}

# Create systemd service for web dashboard
create_dashboard_service() {
    log_info "Creating dashboard systemd service"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would create systemd service for dashboard"
        return 0
    fi
    
    cat > "/tmp/jarvis-security-dashboard.service" << EOF
[Unit]
Description=JarvisJR Security Dashboard
After=network.target

[Service]
Type=simple
User=jarvis
Group=jarvis
WorkingDirectory=$DASHBOARD_DIR
Environment=PYTHONPATH=$DASHBOARD_DIR
ExecStart=$DASHBOARD_DIR/venv/bin/python dashboard_app.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    sudo mv "/tmp/jarvis-security-dashboard.service" "/etc/systemd/system/"
    sudo systemctl daemon-reload
    sudo systemctl enable jarvis-security-dashboard
    
    log_success "Dashboard systemd service created"
}

# Configure NGINX for dashboard access
configure_dashboard_nginx() {
    log_info "Configuring NGINX for security dashboard"
    
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log_info "[DRY RUN] Would configure NGINX for dashboard access"
        return 0
    fi
    
    cat > "/tmp/security-dashboard.conf" << EOF
server {
    listen 80;
    server_name security.${DOMAIN};
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name security.${DOMAIN};
    
    ssl_certificate /etc/letsencrypt/live/${DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${DOMAIN}/privkey.pem;
    
    # Security headers
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    
    # Basic auth for additional security
    auth_basic "JarvisJR Security Dashboard";
    auth_basic_user_file /etc/nginx/htpasswd.security;
    
    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        # Rate limiting
        limit_req zone=api burst=20 nodelay;
    }
    
    # API endpoints with stricter rate limiting
    location /api/ {
        proxy_pass http://127.0.0.1:8080;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        
        limit_req zone=strict burst=10 nodelay;
    }
}
EOF

    sudo mv "/tmp/security-dashboard.conf" "/etc/nginx/sites-available/"
    sudo ln -sf "/etc/nginx/sites-available/security-dashboard.conf" "/etc/nginx/sites-enabled/"
    
    # Create htpasswd file for basic auth
    if ! sudo test -f "/etc/nginx/htpasswd.security"; then
        echo "admin:$(openssl passwd -apr1 'JarvisSecure2024!')" | sudo tee /etc/nginx/htpasswd.security > /dev/null
        log_info "Dashboard password: JarvisSecure2024! (change this!)"
    fi
    
    sudo nginx -t && sudo systemctl reload nginx
    
    log_success "NGINX configuration for dashboard completed"
}

# Main dashboard setup function
setup_dashboard_system() {
    log_info "Setting up complete security dashboard system"
    
    start_progress "Initializing security dashboard system"
    init_dashboard
    stop_progress
    
    start_progress "Creating metrics collection system"
    create_metrics_collector
    stop_progress
    
    start_progress "Creating web dashboard application"
    create_web_dashboard
    stop_progress
    
    start_progress "Creating automated reporting system"
    create_reporting_system
    stop_progress
    
    start_progress "Setting up automated reporting cron jobs"
    setup_reporting_cron
    stop_progress
    
    start_progress "Creating dashboard systemd service"
    create_dashboard_service
    stop_progress
    
    start_progress "Configuring NGINX for dashboard access"
    configure_dashboard_nginx
    stop_progress
    
    log_success "Security dashboard system setup completed"
    
    # Summary
    log_info "Dashboard System Summary:"
    log_info "• Metrics Collection: Every 5 minutes via cron"
    log_info "• Daily Reports: Generated at 6:00 AM"
    log_info "• Weekly Reports: Generated Mondays at 6:00 AM"
    log_info "• Web Dashboard: https://security.${DOMAIN:-your-domain.com}"
    log_info "• Dashboard Login: admin / JarvisSecure2024!"
    log_info "• Service: systemctl status jarvis-security-dashboard"
}

# Dry run validation
validate_dashboard_setup() {
    log_info "Validating security dashboard configuration"
    
    local validation_passed=true
    
    # Check required directories
    local required_dirs=("$METRICS_DIR" "$DASHBOARD_DIR" "$REPORTS_DIR" "$WEB_DIR")
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
        "$METRICS_DIR/collect_metrics.py"
        "$DASHBOARD_DIR/dashboard_app.py"
        "$DASHBOARD_DIR/templates/dashboard.html"
        "$REPORTS_DIR/generate_report.py"
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
        log_success "Dashboard system validation passed"
    else
        log_error "Dashboard system validation failed"
        return 1
    fi
}

# Script usage information
show_help() {
    cat << EOF
JarvisJR Security Dashboard System

USAGE:
    bash security_dashboard.sh [COMMAND]

COMMANDS:
    setup           Set up complete dashboard system
    validate        Validate dashboard configuration
    help            Show this help message

EXAMPLES:
    # Set up complete dashboard system
    bash security_dashboard.sh setup

    # Dry run validation
    DRY_RUN=true bash security_dashboard.sh validate

CONFIGURATION:
    The script uses configuration from jstack.config for domain settings.
    Dashboard will be available at: https://security.your-domain.com

FILES CREATED:
    /opt/jarvis-security/metrics/collect_metrics.py    - Metrics collector
    /opt/jarvis-security/dashboard/dashboard_app.py    - Web dashboard
    /opt/jarvis-security/reports/generate_report.py    - Report generator
    /etc/systemd/system/jarvis-security-dashboard.service - System service
    /etc/nginx/sites-available/security-dashboard.conf    - NGINX config

SERVICES:
    systemctl status jarvis-security-dashboard    - Dashboard service
    crontab -u jarvis -l                         - Automated tasks

LOGS:
    /opt/jarvis-security/logs/metrics.log        - Metrics collection
    /opt/jarvis-security/logs/reporting.log      - Report generation
    journalctl -u jarvis-security-dashboard      - Dashboard service logs

EOF
}

# Main execution
main() {
    local command="${1:-setup}"
    
    case "$command" in
        "setup")
            setup_dashboard_system
            ;;
        "validate")
            validate_dashboard_setup
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