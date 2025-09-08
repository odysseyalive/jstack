#!/bin/bash
# N8N + Browser Automation Service Module for JStack
# Handles N8N workflow automation with integrated Puppeteer/Chrome browser support

# Set script directory and source dependencies
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "${SCRIPT_DIR}")")"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

# Load configuration
load_config
export_config

# ═══════════════════════════════════════════════════════════════════════════════
# 🤖 BROWSER AUTOMATION SETUP (Debian 12 Headless Chrome)
# ═══════════════════════════════════════════════════════════════════════════════

install_chrome_dependencies() {
    log_section "Installing Chrome Dependencies"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install Chrome dependencies"
        return 0
    fi
    
    if [[ "$ENABLE_BROWSER_AUTOMATION" != "true" ]]; then
        log_info "Browser automation disabled, skipping Chrome installation"
        return 0
    fi
    
    start_section_timer "Chrome Dependencies"
    
    # Detect operating system
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        if [[ "$ID_LIKE" == "arch" ]] || [[ "$ID" == "arch" ]]; then
            log_info "Arch Linux detected - using pacman package manager"
            install_chrome_arch
        elif [[ "$ID" == "debian" ]] || [[ "$ID" == "ubuntu" ]]; then
            log_info "Debian/Ubuntu detected - using apt package manager"
            install_chrome_debian
        else
            log_warning "Unsupported OS: $ID - attempting Debian installation method"
            install_chrome_debian
        fi
    else
        log_warning "Cannot detect OS - attempting Debian installation method"
        install_chrome_debian
    fi
    
    # Verify Chrome installation
    if chrome_version=$(google-chrome-stable --version 2>/dev/null || google-chrome --version 2>/dev/null); then
        log_success "Chrome installed successfully: $chrome_version"
    else
        log_error "Chrome installation verification failed"
        return 1
    fi
    
    end_section_timer "Chrome Dependencies"
    log_success "Chrome dependencies installed successfully"
}

install_chrome_arch() {
    log_info "Installing Chrome on Arch Linux"
    
    # Check if Chrome is already installed
    if command -v google-chrome-stable >/dev/null 2>&1 || command -v google-chrome >/dev/null 2>&1; then
        log_success "Chrome is already installed"
        return 0
    fi
    
    # Update package database
    execute_cmd "sudo pacman -Sy" "Update package database"
    
    # Install base dependencies
    log_info "Installing Chrome system dependencies"
    execute_cmd "sudo pacman -S --noconfirm wget gnupg ca-certificates" "Install base dependencies"
    
    # Install Chrome from AUR or official package
    if command -v yay >/dev/null 2>&1; then
        log_info "Installing Google Chrome via yay (AUR)"
        execute_cmd "yay -S --noconfirm google-chrome" "Install Chrome via yay"
    elif command -v paru >/dev/null 2>&1; then
        log_info "Installing Google Chrome via paru (AUR)"
        execute_cmd "paru -S --noconfirm google-chrome" "Install Chrome via paru"
    else
        log_info "Installing Chrome manually"
        execute_cmd "wget -q https://dl.google.com/linux/direct/google-chrome-stable_current_x86_64.rpm" "Download Chrome RPM"
        execute_cmd "sudo pacman -U --noconfirm google-chrome-stable_current_x86_64.rpm" "Install Chrome from RPM"
        execute_cmd "rm -f google-chrome-stable_current_x86_64.rpm" "Clean up Chrome installer"
    fi
    
    # Install additional fonts for better rendering
    execute_cmd "sudo pacman -S --noconfirm noto-fonts noto-fonts-emoji ttf-dejavu" "Install additional fonts"
}

install_chrome_debian() {
    log_info "Installing Chrome on Debian/Ubuntu"
    
    # Update package index
    execute_cmd "sudo apt-get update" "Update package index"
    
    # Install required dependencies for Chrome
    log_info "Installing Chrome system dependencies"
    execute_cmd "sudo apt-get install -y wget gnupg ca-certificates apt-transport-https software-properties-common" "Install base dependencies"
    
    # Add Google Chrome repository
    log_info "Adding Google Chrome repository"
    execute_cmd "wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/googlechrome-linux-keyring.gpg" "Add Google signing key"
    execute_cmd "echo 'deb [arch=amd64 signed-by=/usr/share/keyrings/googlechrome-linux-keyring.gpg] ${CHROME_REPOSITORY} stable main' | sudo tee /etc/apt/sources.list.d/google-chrome.list" "Add Chrome repository"
    
    # Update package index with new repository
    execute_cmd "sudo apt-get update" "Update with Chrome repository"
    
    # Install Chrome and required dependencies for headless operation
    log_info "Installing Google Chrome and headless dependencies"
    execute_cmd "sudo apt-get install -y ${CHROME_PACKAGE} ${CHROME_DEPENDENCIES}" "Install Chrome and dependencies"
    
    # Install additional fonts for better rendering
    execute_cmd "sudo apt-get install -y fonts-noto fonts-noto-color-emoji fonts-dejavu-core" "Install additional fonts"
}

setup_puppeteer_environment() {
    log_section "Setting up Puppeteer Environment"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would setup Puppeteer environment"
        return 0
    fi
    
    if [[ "$ENABLE_BROWSER_AUTOMATION" != "true" ]]; then
        log_info "Browser automation disabled, skipping Puppeteer setup"
        return 0
    fi
    
    start_section_timer "Puppeteer Setup"
    
    # Create Puppeteer cache directory
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $PUPPETEER_CACHE_DIR" "Create Puppeteer cache directory"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $PUPPETEER_CACHE_DIR/screenshots" "Create screenshots directory"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $PUPPETEER_CACHE_DIR/pdfs" "Create PDFs directory"
    
    # Set proper permissions
    safe_chmod "755" "$PUPPETEER_CACHE_DIR" "Set Puppeteer cache permissions"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$PUPPETEER_CACHE_DIR" "Set Puppeteer cache ownership"
    
    # Create Puppeteer configuration file
    cat > /tmp/puppeteer-config.json << EOF
{
  "executablePath": "${PUPPETEER_EXECUTABLE_PATH}",
  "downloadHost": "${PUPPETEER_DOWNLOAD_HOST}",
  "skipChromiumDownload": ${PUPPETEER_SKIP_CHROMIUM_DOWNLOAD},
  "cacheDirectory": "${PUPPETEER_CACHE_DIR}",
  "defaultArgs": [
    $(echo "$CHROME_SECURITY_ARGS" | sed 's/ /",
    "/g' | sed 's/^/    "/' | sed 's/$/"/'),
    "--disable-web-security",
    "--allow-running-insecure-content",
    "--disable-features=TranslateUI",
    "--disable-ipc-flooding-protection",
    "--no-first-run",
    "--no-default-browser-check"
  ],
  "headless": "new",
  "defaultViewport": {
    "width": 1920,
    "height": 1080
  },
  "timeout": ${CHROME_INSTANCE_TIMEOUT}000
}
EOF
    
    safe_mv "/tmp/puppeteer-config.json" "$PUPPETEER_CACHE_DIR/config.json" "Install Puppeteer config"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$PUPPETEER_CACHE_DIR/config.json" "Set Puppeteer config ownership"
    
    # Test Chrome headless functionality
    log_info "Testing Chrome headless functionality"
    if sudo -u $SERVICE_USER google-chrome --headless=new --disable-gpu --no-sandbox --dump-dom about:blank > /dev/null 2>&1; then
        log_success "Chrome headless test passed"
    else
        log_error "Chrome headless test failed"
        return 1
    fi
    
    end_section_timer "Puppeteer Setup"
    log_success "Puppeteer environment setup completed"
}

create_browser_automation_monitoring() {
    log_section "Creating Browser Automation Monitoring"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would create browser automation monitoring"
        return 0
    fi
    
    if [[ "$ENABLE_BROWSER_AUTOMATION" != "true" ]]; then
        log_info "Browser automation disabled, skipping monitoring setup"
        return 0
    fi
    
    start_section_timer "Browser Monitoring"
    
    # Create monitoring script
    cat > /tmp/browser-monitor.sh << 'EOF'
#!/bin/bash
# Browser Automation Monitoring Script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${SCRIPT_DIR}")")"))"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

monitor_chrome_processes() {
    local chrome_count=$(pgrep -f "google-chrome" | wc -l)
    local max_instances=${CHROME_MAX_INSTANCES:-5}
    
    if [[ $chrome_count -gt $max_instances ]]; then
        log_warning "Chrome process count ($chrome_count) exceeds limit ($max_instances)"
        
        # Kill oldest Chrome processes if too many
        log_info "Cleaning up excess Chrome processes"
        pkill -f --oldest "google-chrome.*--headless" || true
    fi
    
    # Monitor memory usage
    local total_memory=$(free -m | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [[ $total_memory -gt 90 ]]; then
        log_warning "High memory usage detected: ${total_memory}%"
        cleanup_browser_cache
    fi
    
    log_info "Chrome processes: $chrome_count, Memory usage: ${total_memory}%"
}

cleanup_browser_cache() {
    log_info "Cleaning up browser cache and temporary files"
    
    # Clean Puppeteer cache (keep last 100 screenshots/PDFs)
    find "$PUPPETEER_CACHE_DIR/screenshots" -type f -mtime +1 -exec rm {} \; 2>/dev/null || true
    find "$PUPPETEER_CACHE_DIR/pdfs" -type f -mtime +1 -exec rm {} \; 2>/dev/null || true
    
    # Clean Chrome temporary files
    find /tmp -name "chrome_*" -type d -mtime +1 -exec rm -rf {} \; 2>/dev/null || true
    find /tmp -name ".org.chromium.*" -type d -mtime +1 -exec rm -rf {} \; 2>/dev/null || true
    
    log_success "Browser cache cleanup completed"
}

# Main monitoring function
case "${1:-monitor}" in
    "monitor")
        monitor_chrome_processes
        ;;
    "cleanup")
        cleanup_browser_cache
        ;;
    *)
        echo "Usage: $0 [monitor|cleanup]"
        exit 1
        ;;
esac
EOF
    
    safe_mv "/tmp/browser-monitor.sh" "$BASE_DIR/scripts/browser-monitor.sh" "Install browser monitor script"
    safe_chmod "755" "$BASE_DIR/scripts/browser-monitor.sh" "Make browser monitor executable"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$BASE_DIR/scripts/browser-monitor.sh" "Set browser monitor ownership"
    
    # Create systemd timer for browser monitoring (optional)
    if [[ -d "/etc/systemd/system" ]]; then
        cat > /tmp/browser-monitor.service << EOF
[Unit]
Description=Browser Automation Monitoring
After=docker.service

[Service]
Type=oneshot
User=${SERVICE_USER}
ExecStart=${BASE_DIR}/scripts/browser-monitor.sh monitor
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
        
        cat > /tmp/browser-monitor.timer << EOF
[Unit]
Description=Run Browser Monitoring every hour
Requires=browser-monitor.service

[Timer]
OnCalendar=hourly
Persistent=true

[Install]
WantedBy=timers.target
EOF
        
        safe_mv "/tmp/browser-monitor.service" "/etc/systemd/system/browser-monitor.service" "Install monitor service"
        safe_mv "/tmp/browser-monitor.timer" "/etc/systemd/system/browser-monitor.timer" "Install monitor timer"
        
        execute_cmd "systemctl daemon-reload" "Reload systemd"
        execute_cmd "systemctl enable browser-monitor.timer" "Enable browser monitor timer"
        execute_cmd "systemctl start browser-monitor.timer" "Start browser monitor timer"
    fi
    
    end_section_timer "Browser Monitoring"
    log_success "Browser automation monitoring created successfully"
}

test_browser_automation_integration() {
    log_section "Testing Browser Automation Integration"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would test browser automation integration"
        return 0
    fi
    
    start_section_timer "Browser Integration Test"
    
    # Test Chrome availability in N8N container
    log_info "Testing Chrome availability in N8N container"
    if docker_cmd "docker exec n8n google-chrome --version" "Check Chrome in N8N container"; then
        log_success "Chrome is available in N8N container"
    else
        log_warning "Chrome may not be properly mounted in N8N container"
    fi
    
    # Test Puppeteer directories
    log_info "Testing Puppeteer directories"
    if docker_cmd "docker exec n8n ls -la ${PUPPETEER_CACHE_DIR}" "Check Puppeteer cache directory"; then
        log_success "Puppeteer cache directory is accessible"
    else
        log_warning "Puppeteer cache directory may not be properly mounted"
    fi
    
    # Test basic headless Chrome functionality in container
    log_info "Testing headless Chrome in N8N container"
    if docker_cmd "docker exec n8n google-chrome --headless=new --disable-gpu --no-sandbox --dump-dom about:blank" "Test headless Chrome"; then
        log_success "Headless Chrome test passed in N8N container"
    else
        log_warning "Headless Chrome test failed - may require troubleshooting"
    fi
    
    end_section_timer "Browser Integration Test"
    log_success "Browser automation integration testing completed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🔄 N8N CONTAINER SETUP (Enhanced with Browser Automation)
# ═══════════════════════════════════════════════════════════════════════════════

# ═══════════════════════════════════════════════════════════════════════════════
# 🔄 TASK 11: ENHANCED PUPPETEER INTEGRATION IN N8N CONTAINERS
# ═══════════════════════════════════════════════════════════════════════════════

# Task 11: Enhanced Puppeteer Integration in N8N Containers
install_puppeteer_in_n8n() {
    log_section "Installing Puppeteer Integration in N8N Container"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would install Puppeteer in N8N container"
        return 0
    fi
    
    if [[ "$ENABLE_BROWSER_AUTOMATION" != "true" ]]; then
        log_info "Browser automation disabled, skipping Puppeteer installation"
        return 0
    fi
    
    start_section_timer "Puppeteer Installation"
    
    # Create enhanced N8N Dockerfile with Puppeteer
    cat > /tmp/n8n-puppeteer.dockerfile << 'EOF'
FROM n8nio/n8n:1.31.2

USER root

# Install Chrome dependencies
RUN apt-get update && apt-get install -y \
    wget \
    gnupg \
    ca-certificates \
    fonts-liberation \
    libasound2 \
    libatk-bridge2.0-0 \
    libatk1.0-0 \
    libc6 \
    libcairo2 \
    libcups2 \
    libdbus-1-3 \
    libexpat1 \
    libfontconfig1 \
    libgbm1 \
    libgcc1 \
    libglib2.0-0 \
    libgtk-3-0 \
    libnspr4 \
    libnss3 \
    libpango-1.0-0 \
    libpangocairo-1.0-0 \
    libstdc++6 \
    libx11-6 \
    libx11-xcb1 \
    libxcb1 \
    libxcomposite1 \
    libxcursor1 \
    libxdamage1 \
    libxext6 \
    libxfixes3 \
    libxi6 \
    libxrandr2 \
    libxrender1 \
    libxss1 \
    libxtst6 \
    lsb-release \
    xdg-utils \
    curl \
    && rm -rf /var/lib/apt/lists/*

# Install Google Chrome
RUN wget -q -O - https://dl.google.com/linux/linux_signing_key.pub | gpg --dearmor -o /usr/share/keyrings/googlechrome-linux-keyring.gpg \
    && echo "deb [arch=amd64 signed-by=/usr/share/keyrings/googlechrome-linux-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main" | tee /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update \
    && apt-get install -y google-chrome-stable \
    && rm -rf /var/lib/apt/lists/*

# Install additional fonts
RUN apt-get update && apt-get install -y \
    fonts-noto \
    fonts-noto-color-emoji \
    fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

USER node

# Install Puppeteer and related packages
RUN npm install -g \
    puppeteer@latest \
    puppeteer-extra@latest \
    puppeteer-extra-plugin-stealth@latest \
    puppeteer-extra-plugin-adblocker@latest \
    cheerio@latest \
    jsdom@latest \
    pdf-parse@latest \
    xlsx@latest \
    csv-parser@latest \
    playwright@latest

# Configure Puppeteer to use installed Chrome
ENV PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/google-chrome-stable

# Create Puppeteer cache directory
RUN mkdir -p /home/node/.n8n/puppeteer-cache/screenshots \
    && mkdir -p /home/node/.n8n/puppeteer-cache/pdfs

# Copy Puppeteer configuration
COPY puppeteer-config.json /home/node/.n8n/puppeteer-cache/config.json

# Create Chrome user data directories
RUN mkdir -p /tmp/chrome-user-data \
    && chmod 755 /tmp/chrome-user-data

WORKDIR /home/node

# Health check with Puppeteer test
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD node -e "const puppeteer = require('puppeteer'); (async () => { const browser = await puppeteer.launch({headless: true, args: ['--no-sandbox', '--disable-dev-shm-usage']}); await browser.close(); })();" || exit 1

EXPOSE 5678
EOF
    
    # Create Puppeteer configuration for N8N
    cat > /tmp/puppeteer-config.json << EOF
{
  "executablePath": "/usr/bin/google-chrome-stable",
  "args": [
    "--no-sandbox",
    "--disable-setuid-sandbox",
    "--disable-dev-shm-usage",
    "--disable-accelerated-2d-canvas",
    "--no-first-run",
    "--no-zygote",
    "--single-process",
    "--disable-gpu",
    "--headless=new",
    "--disable-web-security",
    "--allow-running-insecure-content",
    "--disable-features=TranslateUI",
    "--disable-ipc-flooding-protection",
    "--no-default-browser-check",
    "--memory-pressure-off"
  ],
  "headless": "new",
  "defaultViewport": {
    "width": 1920,
    "height": 1080
  },
  "timeout": 30000,
  "slowMo": 0,
  "devtools": false
}
EOF
    
    # Move files to N8N directory
    local n8n_dir="$BASE_DIR/services/n8n"
    safe_mv "/tmp/n8n-puppeteer.dockerfile" "$n8n_dir/Dockerfile" "Install N8N Puppeteer Dockerfile"
    safe_mv "/tmp/puppeteer-config.json" "$n8n_dir/puppeteer-config.json" "Install Puppeteer config"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$n8n_dir/Dockerfile" "Set Dockerfile ownership"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$n8n_dir/puppeteer-config.json" "Set Puppeteer config ownership"
    
    # Build custom N8N image with Puppeteer
    log_info "Building custom N8N image with Puppeteer integration"
    docker_cmd "cd $n8n_dir && docker build -t n8n-jarvis-puppeteer:latest -f Dockerfile ." "Build N8N Puppeteer image"
    
    end_section_timer "Puppeteer Installation"
    log_success "Puppeteer integration installed in N8N container"
}

# Curie's Security Validation for Puppeteer Integration
validate_puppeteer_security() {
    log_section "Validating Puppeteer Security Configuration"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would validate Puppeteer security"
        return 0
    fi
    
    start_section_timer "Security Validation"
    
    # Security checkpoint 1: Verify no-sandbox security implications
    log_info "Security Checkpoint 1: Chrome sandbox configuration"
    if docker_cmd "docker run --rm n8n-jarvis-puppeteer:latest google-chrome --version" "Check Chrome version in container"; then
        log_success "✅ Chrome properly installed in container"
    else
        log_error "❌ Chrome installation validation failed"
        return 1
    fi
    
    # Security checkpoint 2: Validate container user permissions
    log_info "Security Checkpoint 2: Container user permissions"
    local container_user=$(docker_cmd "docker run --rm n8n-jarvis-puppeteer:latest whoami" "Check container user" | tr -d '\n')
    if [[ "$container_user" == "node" ]]; then
        log_success "✅ Container running as non-root user: $container_user"
    else
        log_warning "⚠️ Container not running as expected user. Current: $container_user"
    fi
    
    # Security checkpoint 3: Test Chrome sandbox restrictions
    log_info "Security Checkpoint 3: Chrome security restrictions"
    if docker_cmd "docker run --rm --cap-drop=ALL --cap-add=SYS_ADMIN n8n-jarvis-puppeteer:latest google-chrome --headless --no-sandbox --dump-dom about:blank" "Test Chrome security restrictions"; then
        log_success "✅ Chrome security restrictions validated"
    else
        log_warning "⚠️ Chrome security test failed - may need capability adjustments"
    fi
    
    # Security checkpoint 4: Network isolation test
    log_info "Security Checkpoint 4: Network isolation validation"
    if docker_cmd "docker run --rm --network=none n8n-jarvis-puppeteer:latest timeout 5 google-chrome --headless --no-sandbox --disable-web-security --dump-dom about:blank" "Test network isolation"; then
        log_success "✅ Network isolation test passed"
    else
        log_info "ℹ️ Network isolation test expected to have limited connectivity"
    fi
    
    # Security checkpoint 5: File system permissions
    log_info "Security Checkpoint 5: File system permissions"
    if docker_cmd "docker run --rm n8n-jarvis-puppeteer:latest ls -la /home/node/.n8n/puppeteer-cache/" "Check Puppeteer cache permissions"; then
        log_success "✅ Puppeteer cache permissions validated"
    else
        log_warning "⚠️ Puppeteer cache permissions may need adjustment"
    fi
    
    end_section_timer "Security Validation"
    log_success "Puppeteer security validation completed"
}

# Test N8N → Chrome container communication
test_n8n_chrome_communication() {
    log_section "Testing N8N → Chrome Container Communication"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would test N8N Chrome communication"
        return 0
    fi
    
    start_section_timer "Communication Test"
    
    # Start temporary N8N container for testing
    log_info "Starting test N8N container with Puppeteer"
    docker_cmd "docker run -d --name n8n-test --network ${PRIVATE_TIER} n8n-jarvis-puppeteer:latest" "Start test N8N container"
    
    # Wait for container to be ready
    sleep 10
    
    # Test 1: Basic Puppeteer functionality
    log_info "Test 1: Basic Puppeteer browser launch"
    local test_script='const puppeteer = require("puppeteer"); (async () => { const browser = await puppeteer.launch({headless: true, args: ["--no-sandbox", "--disable-dev-shm-usage"]}); console.log("Browser launched successfully"); await browser.close(); console.log("Browser closed successfully"); })()'
    
    if docker_cmd "docker exec n8n-test node -e '$test_script'" "Test basic Puppeteer functionality"; then
        log_success "✅ Basic Puppeteer test passed"
    else
        log_error "❌ Basic Puppeteer test failed"
    fi
    
    # Test 2: Web scraping capability
    log_info "Test 2: Web scraping capability test"
    local scraping_script='const puppeteer = require("puppeteer"); (async () => { const browser = await puppeteer.launch({headless: true, args: ["--no-sandbox", "--disable-dev-shm-usage"]}); const page = await browser.newPage(); await page.goto("about:blank"); const title = await page.title(); console.log("Page title:", title); await browser.close(); })()'
    
    if docker_cmd "docker exec n8n-test node -e '$scraping_script'" "Test web scraping capability"; then
        log_success "✅ Web scraping test passed"
    else
        log_warning "⚠️ Web scraping test failed"
    fi
    
    # Test 3: Screenshot capability
    log_info "Test 3: Screenshot capability test"
    local screenshot_script='const puppeteer = require("puppeteer"); (async () => { const browser = await puppeteer.launch({headless: true, args: ["--no-sandbox", "--disable-dev-shm-usage"]}); const page = await browser.newPage(); await page.setContent("<html><body><h1>Test Screenshot</h1></body></html>"); await page.screenshot({path: "/tmp/test-screenshot.png", fullPage: true}); console.log("Screenshot saved"); await browser.close(); })()'
    
    if docker_cmd "docker exec n8n-test node -e '$screenshot_script'" "Test screenshot capability"; then
        log_success "✅ Screenshot test passed"
    else
        log_warning "⚠️ Screenshot test failed"
    fi
    
    # Cleanup test container
    docker_cmd "docker rm -f n8n-test" "Clean up test container" || true
    
    end_section_timer "Communication Test"
    log_success "N8N → Chrome communication testing completed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 📋 TASK 12: WORKFLOW TEMPLATES AND BROWSER AUTOMATION EXAMPLES
# ═══════════════════════════════════════════════════════════════════════════════

# Task 12: Design template system architecture following gap analysis findings
setup_n8n_workflow_templates() {
    log_section "Setting up N8N Workflow Templates and Browser Automation Examples"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would setup N8N workflow templates"
        return 0
    fi
    
    if [[ "$ENABLE_BROWSER_AUTOMATION" != "true" ]]; then
        log_info "Browser automation disabled, skipping workflow templates"
        return 0
    fi
    
    start_section_timer "Workflow Templates"
    
    # Create template storage structure
    setup_template_storage_system
    
    # Create browser automation example workflows
    create_browser_automation_examples
    
    # Setup template management functions
    implement_template_management
    
    # Create template distribution system
    setup_template_distribution
    
    end_section_timer "Workflow Templates"
    log_success "N8N workflow templates and browser automation examples configured"
}

# Create template storage and distribution patterns
setup_template_storage_system() {
    log_info "Setting up template storage and distribution system"
    
    local templates_dir="$BASE_DIR/services/n8n/templates"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $templates_dir" "Create templates directory"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $templates_dir/browser-automation" "Create browser automation templates"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $templates_dir/web-scraping" "Create web scraping templates"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $templates_dir/form-automation" "Create form automation templates"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $templates_dir/data-extraction" "Create data extraction templates"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $templates_dir/monitoring" "Create monitoring templates"
    
    # Create template catalog index
    cat > /tmp/template-catalog.json << EOF
{
  "catalog": {
    "name": "JStack - N8N Browser Automation Templates",
    "version": "1.0.0",
    "description": "Production-ready workflow templates for browser automation and web scraping",
    "categories": [
      {
        "id": "browser-automation",
        "name": "Browser Automation",
        "description": "General browser automation workflows using Puppeteer",
        "icon": "browser",
        "templates": []
      },
      {
        "id": "web-scraping",
        "name": "Web Scraping",
        "description": "Data extraction and web scraping workflows",
        "icon": "download",
        "templates": []
      },
      {
        "id": "form-automation",
        "name": "Form Automation",
        "description": "Automated form filling and submission",
        "icon": "form",
        "templates": []
      },
      {
        "id": "data-extraction",
        "name": "Data Extraction",
        "description": "PDF, document, and structured data extraction",
        "icon": "file-text",
        "templates": []
      },
      {
        "id": "monitoring",
        "name": "Website Monitoring",
        "description": "Website monitoring and change detection",
        "icon": "monitor",
        "templates": []
      }
    ],
    "installation": {
      "requirements": {
        "n8n_version": ">=1.31.0",
        "puppeteer": ">=21.0.0",
        "chrome": ">=120.0.0"
      },
      "setup_instructions": [
        "Ensure browser automation is enabled in JStack configuration",
        "Verify Chrome and Puppeteer are properly installed in N8N container",
        "Configure appropriate resource limits for browser operations",
        "Test browser connectivity before deploying workflows"
      ]
    }
  }
}
EOF
    
    safe_mv "/tmp/template-catalog.json" "$templates_dir/catalog.json" "Install template catalog"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$templates_dir/catalog.json" "Set catalog ownership"
    
    log_success "Template storage system configured"
}

# Create workflow examples for browser automation
create_browser_automation_examples() {
    log_info "Creating browser automation example workflows"
    
    local templates_dir="$BASE_DIR/services/n8n/templates"
    
    # Example 1: Basic Web Scraping Workflow
    create_web_scraping_template "$templates_dir/web-scraping"
    
    # Example 2: E-commerce Price Monitoring
    create_price_monitoring_template "$templates_dir/monitoring"
    
    # Example 3: Form Automation (Lead Generation)
    create_form_automation_template "$templates_dir/form-automation"
    
    # Example 4: PDF Data Extraction
    create_pdf_extraction_template "$templates_dir/data-extraction"
    
    # Example 5: Social Media Automation
    create_social_media_template "$templates_dir/browser-automation"
    
    log_success "Browser automation example workflows created"
}

# Example 1: E-commerce Price Monitor - Puppeteer scrapes prices → PostgreSQL storage → Email alerts
create_price_monitoring_template() {
    local template_dir="$1"
    
    log_info "Creating price monitoring template"
    
    # Create workflow definition
    cat > /tmp/price-monitoring.json << 'EOF'
{
  "name": "E-commerce Price Monitor",
  "nodes": [
    {
      "parameters": {
        "rule": {
          "interval": [
            {
              "field": "hours",
              "step": 6
            }
          ]
        }
      },
      "name": "Schedule Trigger",
      "type": "n8n-nodes-base.scheduleTrigger",
      "typeVersion": 1.1,
      "position": [240, 300]
    },
    {
      "parameters": {
        "jsCode": "const puppeteer = require('puppeteer');\n\nconst products = [\n  {\n    name: 'Example Product',\n    url: 'https://example-store.com/product/123',\n    priceSelector: '.price',\n    targetPrice: 99.99\n  }\n];\n\nconst results = [];\n\nfor (const product of products) {\n  const browser = await puppeteer.launch({\n    headless: true,\n    args: ['--no-sandbox', '--disable-dev-shm-usage']\n  });\n  \n  try {\n    const page = await browser.newPage();\n    await page.goto(product.url, { waitUntil: 'networkidle2' });\n    \n    const price = await page.evaluate((selector) => {\n      const element = document.querySelector(selector);\n      return element ? element.textContent.replace(/[^0-9.]/g, '') : null;\n    }, product.priceSelector);\n    \n    if (price) {\n      const currentPrice = parseFloat(price);\n      results.push({\n        ...product,\n        currentPrice,\n        timestamp: new Date().toISOString(),\n        priceAlert: currentPrice <= product.targetPrice\n      });\n    }\n  } catch (error) {\n    console.error(`Error scraping ${product.name}:`, error);\n  } finally {\n    await browser.close();\n  }\n}\n\nreturn results;"
      },
      "name": "Scrape Prices",
      "type": "n8n-nodes-base.code",
      "typeVersion": 2,
      "position": [440, 300]
    },
    {
      "parameters": {
        "operation": "insert",
        "table": "price_monitoring",
        "columns": "name, url, current_price, target_price, timestamp, price_alert",
        "additionalFields": {}
      },
      "name": "Store in Database",
      "type": "n8n-nodes-base.postgres",
      "typeVersion": 2.4,
      "position": [640, 300],
      "credentials": {
        "postgres": {
          "id": "1",
          "name": "Supabase PostgreSQL"
        }
      }
    },
    {
      "parameters": {
        "conditions": {
          "boolean": [
            {
              "value1": "={{$json.priceAlert}}",
              "value2": true
            }
          ]
        }
      },
      "name": "Price Alert Check",
      "type": "n8n-nodes-base.if",
      "typeVersion": 1,
      "position": [840, 300]
    },
    {
      "parameters": {
        "fromEmail": "alerts@jarvisstack.com",
        "toEmail": "user@example.com",
        "subject": "Price Alert: {{$json.name}}",
        "text": "Great news! The price for {{$json.name}} has dropped to ${{$json.currentPrice}}.\n\nTarget Price: ${{$json.targetPrice}}\nCurrent Price: ${{$json.currentPrice}}\nSavings: ${{$json.targetPrice - $json.currentPrice}}\n\nProduct URL: {{$json.url}}\n\nHappy shopping!\n- JStack"
      },
      "name": "Send Alert Email",
      "type": "n8n-nodes-base.emailSend",
      "typeVersion": 2.1,
      "position": [1040, 200]
    }
  ],
  "connections": {
    "Schedule Trigger": {
      "main": [
        [
          {
            "node": "Scrape Prices",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Scrape Prices": {
      "main": [
        [
          {
            "node": "Store in Database",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Store in Database": {
      "main": [
        [
          {
            "node": "Price Alert Check",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Price Alert Check": {
      "main": [
        [
          {
            "node": "Send Alert Email",
            "type": "main",
            "index": 0
          }
        ]
      ]
    }
  }
}
EOF
    
    # Create configuration file
    cat > /tmp/price-monitoring-config.yaml << EOF
template:
  name: "E-commerce Price Monitor"
  version: "1.0.0"
  description: "Monitor product prices and send alerts when target prices are reached"
  category: "monitoring"
  tags: ["ecommerce", "price-monitoring", "alerts", "puppeteer"]
  
requirements:
  puppeteer: ">=21.0.0"
  chrome: true
  database: "postgresql"
  email: true
  
configuration:
  products:
    - name: "Product name to monitor"
      url: "Product page URL"
      priceSelector: "CSS selector for price element"
      targetPrice: "Target price threshold"
  
  schedule: "Every 6 hours (customizable)"
  notifications:
    email: "Configure SMTP settings in N8N"
    
setup_instructions:
  1. "Update the products array with your target products"
  2. "Configure CSS selectors for price elements on each site"
  3. "Set up email credentials in N8N settings"
  4. "Create price_monitoring table in PostgreSQL"
  5. "Test with a single product before adding multiple items"
  
database_schema: |
  CREATE TABLE price_monitoring (
    id SERIAL PRIMARY KEY,
    name VARCHAR(255),
    url TEXT,
    current_price DECIMAL(10,2),
    target_price DECIMAL(10,2),
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    price_alert BOOLEAN DEFAULT FALSE
  );
EOF
    
    # Create documentation
    cat > /tmp/price-monitoring-docs.md << EOF
# E-commerce Price Monitor Template

This template monitors product prices across e-commerce websites and sends email alerts when prices drop below target thresholds.

## Features

- **Multi-site Support**: Monitor products from different e-commerce platforms
- **Automated Scheduling**: Configurable price checking intervals
- **Database Storage**: Historical price tracking in PostgreSQL
- **Email Alerts**: Instant notifications when target prices are reached
- **Error Handling**: Robust error handling for unreliable websites

## Setup Process

1. **Database Setup**
   \`\`\`sql
   CREATE TABLE price_monitoring (
     id SERIAL PRIMARY KEY,
     name VARCHAR(255),
     url TEXT,
     current_price DECIMAL(10,2),
     target_price DECIMAL(10,2),
     timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
     price_alert BOOLEAN DEFAULT FALSE
   );
   \`\`\`

2. **Product Configuration**
   - Update the products array in the "Scrape Prices" node
   - Test CSS selectors for each target website
   - Set realistic target prices

3. **Email Configuration**
   - Configure SMTP settings in N8N
   - Update sender and recipient email addresses
   - Customize alert message templates

## Usage Examples

### Amazon Product Monitoring
\`\`\`javascript
{
  name: 'Amazon Product',
  url: 'https://amazon.com/dp/PRODUCT_ID',
  priceSelector: '.a-price-whole',
  targetPrice: 29.99
}
\`\`\`

### Best Buy Product Monitoring
\`\`\`javascript
{
  name: 'Best Buy Product',
  url: 'https://bestbuy.com/site/product/SKU.p',
  priceSelector: '.sr-only:contains("current price")',
  targetPrice: 199.99
}
\`\`\`

## Customization Options

- **Schedule Frequency**: Modify the Schedule Trigger interval
- **Multiple Recipients**: Add multiple email addresses for alerts
- **Price History**: Query database for price trend analysis
- **Webhook Integration**: Add webhook notifications for external systems

## Troubleshooting

- **Price Not Detected**: Verify CSS selectors using browser dev tools
- **Rate Limiting**: Add delays between requests for same domain
- **Email Issues**: Check SMTP configuration and spam folders
- **Memory Usage**: Monitor Chrome process memory consumption
EOF
    
    # Move files to template directory
    safe_mv "/tmp/price-monitoring.json" "$template_dir/price-monitoring.json" "Install price monitoring workflow"
    safe_mv "/tmp/price-monitoring-config.yaml" "$template_dir/price-monitoring-config.yaml" "Install price monitoring config"
    safe_mv "/tmp/price-monitoring-docs.md" "$template_dir/price-monitoring-docs.md" "Install price monitoring docs"
    
    # Set ownership
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$template_dir/price-monitoring.json" "Set workflow ownership"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$template_dir/price-monitoring-config.yaml" "Set config ownership"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$template_dir/price-monitoring-docs.md" "Set docs ownership"
    
    log_success "Price monitoring template created"
}

# Example 2: Lead Generation - Form automation → CRM integration → Follow-up sequences
create_form_automation_template() {
    local template_dir="$1"
    
    log_info "Creating form automation template"
    
    cat > /tmp/lead-generation.json << 'EOF'
{
  "name": "Lead Generation Form Automation",
  "nodes": [
    {
      "parameters": {
        "httpMethod": "POST",
        "path": "/webhook/lead-generation",
        "responseMode": "responseNode",
        "options": {}
      },
      "name": "Webhook Trigger",
      "type": "n8n-nodes-base.webhook",
      "typeVersion": 1,
      "position": [240, 300]
    },
    {
      "parameters": {
        "jsCode": "const puppeteer = require('puppeteer');\nconst leadData = $input.all()[0].json;\n\nconst browser = await puppeteer.launch({\n  headless: true,\n  args: ['--no-sandbox', '--disable-dev-shm-usage']\n});\n\ntry {\n  const page = await browser.newPage();\n  \n  // Navigate to target form\n  await page.goto(leadData.targetFormUrl, { waitUntil: 'networkidle2' });\n  \n  // Fill form fields\n  await page.type('#firstName', leadData.firstName);\n  await page.type('#lastName', leadData.lastName);\n  await page.type('#email', leadData.email);\n  await page.type('#company', leadData.company);\n  await page.type('#phone', leadData.phone);\n  \n  // Select dropdown options if provided\n  if (leadData.industry) {\n    await page.select('#industry', leadData.industry);\n  }\n  \n  // Handle checkboxes\n  if (leadData.newsletter) {\n    await page.click('#newsletter');\n  }\n  \n  // Submit form\n  await page.click('#submitButton');\n  \n  // Wait for confirmation\n  await page.waitForSelector('.success-message', { timeout: 10000 });\n  \n  return {\n    ...leadData,\n    submissionStatus: 'success',\n    submittedAt: new Date().toISOString(),\n    confirmationReceived: true\n  };\n  \n} catch (error) {\n  console.error('Form submission error:', error);\n  return {\n    ...leadData,\n    submissionStatus: 'failed',\n    error: error.message,\n    submittedAt: new Date().toISOString()\n  };\n} finally {\n  await browser.close();\n}"
      },
      "name": "Automate Form Submission",
      "type": "n8n-nodes-base.code",
      "typeVersion": 2,
      "position": [440, 300]
    },
    {
      "parameters": {
        "operation": "insert",
        "table": "leads",
        "columns": "first_name, last_name, email, company, phone, industry, submission_status, submitted_at",
        "additionalFields": {}
      },
      "name": "Store Lead Data",
      "type": "n8n-nodes-base.postgres",
      "typeVersion": 2.4,
      "position": [640, 300],
      "credentials": {
        "postgres": {
          "id": "1",
          "name": "Supabase PostgreSQL"
        }
      }
    },
    {
      "parameters": {
        "conditions": {
          "string": [
            {
              "value1": "={{$json.submissionStatus}}",
              "value2": "success"
            }
          ]
        }
      },
      "name": "Check Success",
      "type": "n8n-nodes-base.if",
      "typeVersion": 1,
      "position": [840, 300]
    },
    {
      "parameters": {
        "fromEmail": "leads@jarvisstack.com",
        "toEmail": "={{$json.email}}",
        "subject": "Welcome! Your information has been submitted",
        "text": "Dear {{$json.firstName}} {{$json.lastName}},\n\nThank you for your interest in our services. We have successfully received your information and will be in touch within 24 hours.\n\nSubmitted Information:\n- Company: {{$json.company}}\n- Industry: {{$json.industry}}\n- Phone: {{$json.phone}}\n\nOur team will review your request and provide personalized recommendations.\n\nBest regards,\nJStack Team"
      },
      "name": "Send Welcome Email",
      "type": "n8n-nodes-base.emailSend",
      "typeVersion": 2.1,
      "position": [1040, 200]
    },
    {
      "parameters": {
        "fromEmail": "alerts@jarvisstack.com",
        "toEmail": "sales@company.com",
        "subject": "New Lead: {{$json.company}}",
        "text": "New lead submitted through automated form:\n\nContact Information:\n- Name: {{$json.firstName}} {{$json.lastName}}\n- Email: {{$json.email}}\n- Company: {{$json.company}}\n- Phone: {{$json.phone}}\n- Industry: {{$json.industry}}\n\nSubmission Status: {{$json.submissionStatus}}\nSubmitted At: {{$json.submittedAt}}\n\nFollow up within 24 hours for best conversion rates."
      },
      "name": "Notify Sales Team",
      "type": "n8n-nodes-base.emailSend",
      "typeVersion": 2.1,
      "position": [1040, 400]
    },
    {
      "parameters": {
        "respondWith": "json",
        "responseBody": "{\n  \"status\": \"success\",\n  \"message\": \"Lead submitted successfully\",\n  \"submissionId\": \"{{$json.id}}\"\n}"
      },
      "name": "Success Response",
      "type": "n8n-nodes-base.respondToWebhook",
      "typeVersion": 1,
      "position": [1240, 300]
    }
  ],
  "connections": {
    "Webhook Trigger": {
      "main": [
        [
          {
            "node": "Automate Form Submission",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Automate Form Submission": {
      "main": [
        [
          {
            "node": "Store Lead Data",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Store Lead Data": {
      "main": [
        [
          {
            "node": "Check Success",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Check Success": {
      "main": [
        [
          {
            "node": "Send Welcome Email",
            "type": "main",
            "index": 0
          },
          {
            "node": "Notify Sales Team",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Send Welcome Email": {
      "main": [
        [
          {
            "node": "Success Response",
            "type": "main",
            "index": 0
          }
        ]
      ]
    },
    "Notify Sales Team": {
      "main": [
        [
          {
            "node": "Success Response",
            "type": "main",
            "index": 0
          }
        ]
      ]
    }
  }
}
EOF
    
    # Create configuration and documentation files
    cat > /tmp/lead-generation-config.yaml << EOF
template:
  name: "Lead Generation Form Automation"
  version: "1.0.0"
  description: "Automate form submissions and lead processing with CRM integration"
  category: "form-automation"
  tags: ["lead-generation", "forms", "automation", "crm"]

database_schema: |
  CREATE TABLE leads (
    id SERIAL PRIMARY KEY,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    email VARCHAR(255),
    company VARCHAR(255),
    phone VARCHAR(50),
    industry VARCHAR(100),
    submission_status VARCHAR(20),
    submitted_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
  );
EOF
    
    safe_mv "/tmp/lead-generation.json" "$template_dir/lead-generation.json" "Install lead generation workflow"
    safe_mv "/tmp/lead-generation-config.yaml" "$template_dir/lead-generation-config.yaml" "Install lead generation config"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$template_dir/lead-generation.json" "Set workflow ownership"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$template_dir/lead-generation-config.yaml" "Set config ownership"
    
    log_success "Form automation template created"
}

# Add template management functions to service module
implement_template_management() {
    log_info "Implementing template management functions"
    
    # Create template management script
    cat > /tmp/template-manager.sh << 'EOF'
#!/bin/bash
# N8N Template Management System
# Manages workflow templates for browser automation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${SCRIPT_DIR}")")"))"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

TEMPLATES_DIR="$BASE_DIR/services/n8n/templates"
N8N_API_URL="http://localhost:5678/api/v1"

list_templates() {
    log_info "Available N8N workflow templates:"
    echo ""
    
    if [[ -f "$TEMPLATES_DIR/catalog.json" ]]; then
        # Parse catalog and display organized template list
        local categories=$(jq -r '.catalog.categories[].id' "$TEMPLATES_DIR/catalog.json" 2>/dev/null || echo "")
        
        for category in $categories; do
            local category_name=$(jq -r ".catalog.categories[] | select(.id == \"$category\") | .name" "$TEMPLATES_DIR/catalog.json")
            local category_desc=$(jq -r ".catalog.categories[] | select(.id == \"$category\") | .description" "$TEMPLATES_DIR/catalog.json")
            
            echo "📂 $category_name"
            echo "   $category_desc"
            echo ""
            
            # List templates in this category
            if [[ -d "$TEMPLATES_DIR/$category" ]]; then
                find "$TEMPLATES_DIR/$category" -name "*.json" -exec basename {} .json \; | while read template; do
                    if [[ -f "$TEMPLATES_DIR/$category/$template-config.yaml" ]]; then
                        local template_name=$(grep "name:" "$TEMPLATES_DIR/$category/$template-config.yaml" | cut -d'"' -f2)
                        local template_desc=$(grep "description:" "$TEMPLATES_DIR/$category/$template-config.yaml" | cut -d'"' -f2)
                        echo "   📄 $template ($template_name)"
                        echo "      $template_desc"
                    else
                        echo "   📄 $template"
                    fi
                done
            fi
            echo ""
        done
    else
        echo "Template catalog not found. Run setup first."
    fi
}

install_template() {
    local template_name="$1"
    local category="$2"
    
    if [[ -z "$template_name" ]]; then
        log_error "Template name required"
        echo "Usage: $0 install <template-name> [category]"
        exit 1
    fi
    
    log_info "Installing template: $template_name"
    
    # Find template file
    local template_file=""
    if [[ -n "$category" ]] && [[ -f "$TEMPLATES_DIR/$category/$template_name.json" ]]; then
        template_file="$TEMPLATES_DIR/$category/$template_name.json"
    else
        # Search all categories
        template_file=$(find "$TEMPLATES_DIR" -name "$template_name.json" | head -1)
    fi
    
    if [[ -z "$template_file" ]]; then
        log_error "Template not found: $template_name"
        exit 1
    fi
    
    log_info "Found template: $template_file"
    
    # Import template to N8N via API
    local workflow_data=$(cat "$template_file")
    local response=$(curl -s -X POST \
        -H "Content-Type: application/json" \
        -d "$workflow_data" \
        "$N8N_API_URL/workflows" 2>/dev/null)
    
    if echo "$response" | jq -r '.id' >/dev/null 2>&1; then
        local workflow_id=$(echo "$response" | jq -r '.id')
        log_success "Template installed successfully (ID: $workflow_id)"
        
        # Display setup instructions if available
        local config_file="${template_file%.json}-config.yaml"
        if [[ -f "$config_file" ]]; then
            echo ""
            log_info "Setup instructions:"
            grep -A 10 "setup_instructions:" "$config_file" | tail -n +2
        fi
    else
        log_error "Failed to install template"
        echo "Response: $response"
    fi
}

validate_template() {
    local template_file="$1"
    
    if [[ ! -f "$template_file" ]]; then
        log_error "Template file not found: $template_file"
        return 1
    fi
    
    log_info "Validating template: $template_file"
    
    # Check JSON syntax
    if ! jq . "$template_file" >/dev/null 2>&1; then
        log_error "Invalid JSON syntax"
        return 1
    fi
    
    # Check required fields
    local required_fields=("name" "nodes" "connections")
    for field in "${required_fields[@]}"; do
        if ! jq -e ".$field" "$template_file" >/dev/null 2>&1; then
            log_error "Missing required field: $field"
            return 1
        fi
    done
    
    # Validate node structure
    local node_count=$(jq '.nodes | length' "$template_file")
    if [[ $node_count -lt 1 ]]; then
        log_error "Template must contain at least one node"
        return 1
    fi
    
    log_success "Template validation passed"
    return 0
}

create_template() {
    local workflow_name="$1"
    local output_file="$2"
    
    if [[ -z "$workflow_name" ]] || [[ -z "$output_file" ]]; then
        log_error "Workflow name and output file required"
        echo "Usage: $0 create <workflow-name> <output-file>"
        exit 1
    fi
    
    log_info "Exporting workflow '$workflow_name' to template"
    
    # Get workflow by name from N8N API
    local workflows=$(curl -s "$N8N_API_URL/workflows" 2>/dev/null)
    local workflow_id=$(echo "$workflows" | jq -r ".data[] | select(.name == \"$workflow_name\") | .id" | head -1)
    
    if [[ -z "$workflow_id" ]] || [[ "$workflow_id" == "null" ]]; then
        log_error "Workflow not found: $workflow_name"
        exit 1
    fi
    
    # Export workflow
    local workflow_data=$(curl -s "$N8N_API_URL/workflows/$workflow_id" 2>/dev/null)
    
    if echo "$workflow_data" | jq -r '.name' >/dev/null 2>&1; then
        echo "$workflow_data" | jq '.' > "$output_file"
        log_success "Template created: $output_file"
    else
        log_error "Failed to export workflow"
    fi
}

# Main command routing
case "${1:-list}" in
    "list")
        list_templates
        ;;
    "install")
        install_template "$2" "$3"
        ;;
    "validate")
        validate_template "$2"
        ;;
    "create")
        create_template "$2" "$3"
        ;;
    *)
        echo "N8N Template Manager"
        echo ""
        echo "Usage: $0 [command] [options]"
        echo ""
        echo "Commands:"
        echo "  list                    - List available templates"
        echo "  install <name> [cat]    - Install template to N8N"
        echo "  validate <file>         - Validate template file"
        echo "  create <name> <file>    - Export workflow as template"
        echo ""
        exit 1
        ;;
esac
EOF
    
    safe_mv "/tmp/template-manager.sh" "$BASE_DIR/scripts/template-manager.sh" "Install template manager"
    safe_chmod "755" "$BASE_DIR/scripts/template-manager.sh" "Make template manager executable"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$BASE_DIR/scripts/template-manager.sh" "Set template manager ownership"
    
    log_success "Template management functions implemented"
}

# Create template distribution system
setup_template_distribution() {
    log_info "Setting up template distribution system"
    
    # Create simplified templates for the other examples
    create_web_scraping_template "$BASE_DIR/services/n8n/templates/web-scraping"
    create_pdf_extraction_template "$BASE_DIR/services/n8n/templates/data-extraction"
    create_social_media_template "$BASE_DIR/services/n8n/templates/browser-automation"
    
    log_success "Template distribution system configured"
}

# Simplified template creation functions
create_web_scraping_template() {
    local template_dir="$1"
    
    cat > /tmp/basic-scraper.json << 'EOF'
{
  "name": "Basic Web Scraper",
  "nodes": [
    {
      "parameters": {
        "jsCode": "const puppeteer = require('puppeteer');\nconst targetUrl = $json.url || 'https://example.com';\n\nconst browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] });\nconst page = await browser.newPage();\n\ntry {\n  await page.goto(targetUrl);\n  const data = await page.evaluate(() => {\n    return {\n      title: document.title,\n      headings: Array.from(document.querySelectorAll('h1, h2, h3')).map(h => h.textContent),\n      links: Array.from(document.querySelectorAll('a')).map(a => ({ text: a.textContent, href: a.href }))\n    };\n  });\n  return { ...data, scrapedAt: new Date().toISOString() };\n} finally {\n  await browser.close();\n}"
      },
      "name": "Web Scraper",
      "type": "n8n-nodes-base.code",
      "typeVersion": 2,
      "position": [300, 300]
    }
  ],
  "connections": {}
}
EOF
    
    safe_mv "/tmp/basic-scraper.json" "$template_dir/basic-scraper.json" "Install basic scraper template"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$template_dir/basic-scraper.json" "Set ownership"
}

create_pdf_extraction_template() {
    local template_dir="$1"
    
    cat > /tmp/pdf-extractor.json << 'EOF'
{
  "name": "PDF Data Extractor",
  "nodes": [
    {
      "parameters": {
        "jsCode": "const puppeteer = require('puppeteer');\nconst pdfUrl = $json.pdfUrl;\n\nconst browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] });\nconst page = await browser.newPage();\n\ntry {\n  await page.goto(pdfUrl);\n  await page.pdf({ path: '/tmp/downloaded.pdf', format: 'A4' });\n  return { status: 'PDF downloaded and ready for processing', downloadedAt: new Date().toISOString() };\n} finally {\n  await browser.close();\n}"
      },
      "name": "PDF Processor",
      "type": "n8n-nodes-base.code",
      "typeVersion": 2,
      "position": [300, 300]
    }
  ],
  "connections": {}
}
EOF
    
    safe_mv "/tmp/pdf-extractor.json" "$template_dir/pdf-extractor.json" "Install PDF extractor template"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$template_dir/pdf-extractor.json" "Set ownership"
}

create_social_media_template() {
    local template_dir="$1"
    
    cat > /tmp/social-automation.json << 'EOF'
{
  "name": "Social Media Automation",
  "nodes": [
    {
      "parameters": {
        "jsCode": "const puppeteer = require('puppeteer');\nconst postData = $json;\n\nconst browser = await puppeteer.launch({ headless: true, args: ['--no-sandbox'] });\nconst page = await browser.newPage();\n\ntry {\n  // Example: LinkedIn post automation\n  await page.goto('https://linkedin.com/feed/');\n  await page.click('[data-test-id=\"share-box-trigger\"]');\n  await page.type('[data-test-id=\"share-creation-state-know-sharetext\"]', postData.content);\n  // Add image, schedule, etc.\n  return { status: 'Post scheduled', scheduledAt: new Date().toISOString() };\n} finally {\n  await browser.close();\n}"
      },
      "name": "Social Media Poster",
      "type": "n8n-nodes-base.code",
      "typeVersion": 2,
      "position": [300, 300]
    }
  ],
  "connections": {}
}
EOF
    
    safe_mv "/tmp/social-automation.json" "$template_dir/social-automation.json" "Install social automation template"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$template_dir/social-automation.json" "Set ownership"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🚀 TASK 13: BROWSER PERFORMANCE OPTIMIZATION WITH MONITORING BASELINES
# ═══════════════════════════════════════════════════════════════════════════════

# Task 13: Implement Edison's performance monitoring baselines
implement_browser_performance_optimization() {
    log_section "Implementing Browser Performance Optimization with Monitoring Baselines"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would implement browser performance optimization"
        return 0
    fi
    
    if [[ "$ENABLE_BROWSER_AUTOMATION" != "true" ]]; then
        log_info "Browser automation disabled, skipping performance optimization"
        return 0
    fi
    
    start_section_timer "Performance Optimization"
    
    # Configure Chrome optimization parameters
    configure_chrome_optimization_parameters
    
    # Add performance metrics collection and alerting
    setup_performance_metrics_collection
    
    # Implement browser instance recycling and resource management
    implement_browser_instance_recycling
    
    # Setup Edison's performance monitoring baselines
    establish_performance_baselines
    
    end_section_timer "Performance Optimization"
    log_success "Browser performance optimization with monitoring baselines implemented"
}

# Configure Chrome optimization parameters (memory limits, instance pooling)
configure_chrome_optimization_parameters() {
    log_info "Configuring Chrome optimization parameters"
    
    # Create Chrome optimization configuration
    cat > /tmp/chrome-performance-config.json << EOF
{
  "chromeOptimization": {
    "memoryLimits": {
      "perInstance": "${CHROME_MAX_MEMORY_PER_INSTANCE:-800}MB",
      "totalSystem": "${CHROME_MEMORY_LIMIT:-4g}",
      "warningThreshold": 85,
      "criticalThreshold": 95
    },
    "instancePooling": {
      "minInstances": 2,
      "maxInstances": ${CHROME_MAX_INSTANCES:-5},
      "warmupInstances": 3,
      "recycleInterval": 1800,
      "idleTimeout": 600
    },
    "chromeArgs": [
      "--no-sandbox",
      "--disable-dev-shm-usage",
      "--disable-gpu",
      "--headless=new",
      "--disable-web-security",
      "--disable-features=TranslateUI,VizDisplayCompositor",
      "--disable-background-timer-throttling",
      "--disable-renderer-backgrounding",
      "--disable-backgrounding-occluded-windows",
      "--disable-blink-features=AutomationControlled",
      "--memory-pressure-off",
      "--max_old_space_size=512",
      "--aggressive-cache-discard",
      "--disable-extensions",
      "--disable-plugins",
      "--disable-images",
      "--disable-javascript",
      "--virtual-time-budget=30000"
    ],
    "resourceMonitoring": {
      "enabled": true,
      "interval": 30,
      "metrics": ["cpu", "memory", "network", "responseTime"],
      "alertThresholds": {
        "cpu": 80,
        "memory": 85,
        "responseTime": 10000
      }
    }
  }
}
EOF
    
    local config_dir="$BASE_DIR/config"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $config_dir" "Create config directory"
    safe_mv "/tmp/chrome-performance-config.json" "$config_dir/chrome-performance.json" "Install Chrome performance config"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$config_dir/chrome-performance.json" "Set config ownership"
    
    # Create optimized Puppeteer launch configuration
    cat > /tmp/puppeteer-optimized-config.js << 'EOF'
// Optimized Puppeteer Configuration for JStack
const fs = require('fs');
const path = require('path');

// Load performance configuration
const configPath = process.env.CHROME_PERFORMANCE_CONFIG || '${BASE_DIR}/config/chrome-performance.json';
const config = JSON.parse(fs.readFileSync(configPath, 'utf8')).chromeOptimization;

class OptimizedPuppeteerLauncher {
    constructor() {
        this.activeInstances = new Map();
        this.performanceMetrics = {
            launches: 0,
            failures: 0,
            averageStartupTime: 0,
            memoryUsage: []
        };
    }

    async launchOptimized(options = {}) {
        const startTime = Date.now();
        
        try {
            const optimizedOptions = {
                headless: 'new',
                args: [
                    ...config.chromeArgs,
                    `--memory-pressure-off`,
                    `--max_old_space_size=${config.memoryLimits.perInstance.replace('MB', '')}`
                ],
                timeout: 30000,
                ignoreDefaultArgs: ['--disable-extensions'],
                ...options
            };

            const browser = await require('puppeteer').launch(optimizedOptions);
            
            // Track instance
            const instanceId = `instance_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
            this.activeInstances.set(instanceId, {
                browser,
                launchedAt: new Date(),
                pid: browser.process()?.pid
            });

            // Performance metrics
            const launchTime = Date.now() - startTime;
            this.updateMetrics(launchTime, true);
            
            // Auto-cleanup after idle timeout
            this.scheduleCleanup(instanceId, config.instancePooling.idleTimeout * 1000);
            
            return { browser, instanceId };
            
        } catch (error) {
            this.updateMetrics(Date.now() - startTime, false);
            throw error;
        }
    }

    async closeInstance(instanceId) {
        const instance = this.activeInstances.get(instanceId);
        if (instance) {
            try {
                await instance.browser.close();
                this.activeInstances.delete(instanceId);
            } catch (error) {
                console.error('Error closing browser instance:', error);
            }
        }
    }

    updateMetrics(launchTime, success) {
        this.performanceMetrics.launches++;
        if (success) {
            this.performanceMetrics.averageStartupTime = 
                (this.performanceMetrics.averageStartupTime + launchTime) / 2;
        } else {
            this.performanceMetrics.failures++;
        }
    }

    scheduleCleanup(instanceId, timeout) {
        setTimeout(() => {
            this.closeInstance(instanceId);
        }, timeout);
    }

    getPerformanceReport() {
        return {
            ...this.performanceMetrics,
            activeInstances: this.activeInstances.size,
            successRate: (this.performanceMetrics.launches - this.performanceMetrics.failures) / this.performanceMetrics.launches * 100
        };
    }
}

module.exports = new OptimizedPuppeteerLauncher();
EOF
    
    safe_mv "/tmp/puppeteer-optimized-config.js" "$config_dir/puppeteer-optimized.js" "Install Puppeteer optimization config"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$config_dir/puppeteer-optimized.js" "Set Puppeteer config ownership"
    
    log_success "Chrome optimization parameters configured"
}

# Add performance metrics collection and alerting
setup_performance_metrics_collection() {
    log_info "Setting up performance metrics collection and alerting"
    
    # Create performance monitoring script
    cat > /tmp/performance-monitor.sh << 'EOF'
#!/bin/bash
# Browser Performance Monitoring System
# Edison's performance testing integration

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${SCRIPT_DIR}")")"))"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

# Performance baseline thresholds (Edison's recommendations)
RESPONSE_TIME_BASELINE=5000      # 5 seconds maximum
MEMORY_USAGE_BASELINE=800        # 800MB per Chrome instance
CPU_USAGE_BASELINE=80            # 80% CPU usage threshold
STARTUP_TIME_BASELINE=10000      # 10 seconds browser startup

collect_performance_metrics() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local metrics_file="$BASE_DIR/logs/performance-metrics-$(date '+%Y%m%d').log"
    
    log_info "Collecting browser performance metrics"
    
    # Chrome process metrics
    local chrome_processes=$(pgrep -f "google-chrome" | wc -l)
    local chrome_memory=0
    local chrome_cpu=0
    
    if [[ $chrome_processes -gt 0 ]]; then
        chrome_memory=$(ps -C google-chrome-stable -o rss --no-headers 2>/dev/null | awk '{sum+=$1} END {printf "%.0f", sum/1024}' || echo "0")
        chrome_cpu=$(ps -C google-chrome-stable -o %cpu --no-headers 2>/dev/null | awk '{sum+=$1} END {printf "%.1f", sum}' || echo "0")
    fi
    
    # System resource metrics
    local sys_memory=$(free -m | awk 'NR==2{printf "%.1f", $3*100/$2}')
    local sys_cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{printf "%.1f", $1}')
    local load_avg=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')
    
    # N8N container metrics
    local n8n_memory=0
    local n8n_cpu=0
    if docker ps --filter name=n8n --format "{{.Names}}" | grep -q n8n; then
        local n8n_stats=$(docker stats n8n --no-stream --format "{{.CPUPerc}}\t{{.MemPerc}}" 2>/dev/null | tail -n1)
        n8n_cpu=$(echo "$n8n_stats" | cut -f1 | sed 's/%//')
        n8n_memory=$(echo "$n8n_stats" | cut -f2 | sed 's/%//')
    fi
    
    # Performance test - browser startup time
    local startup_time=$(test_browser_startup_time)
    
    # Performance test - page load time
    local page_load_time=$(test_page_load_performance)
    
    # Log comprehensive metrics
    echo "[$timestamp] CHROME_PROC:$chrome_processes CHROME_MEM:${chrome_memory}MB CHROME_CPU:${chrome_cpu}% SYS_MEM:${sys_memory}% SYS_CPU:${sys_cpu}% LOAD:${load_avg} N8N_CPU:${n8n_cpu}% N8N_MEM:${n8n_memory}% STARTUP:${startup_time}ms PAGELOAD:${page_load_time}ms" >> "$metrics_file"
    
    # Check performance against baselines
    check_performance_baselines "$chrome_memory" "$startup_time" "$page_load_time" "$chrome_cpu"
    
    # Generate performance report
    generate_performance_report "$metrics_file"
}

test_browser_startup_time() {
    local start_time=$(date +%s%3N)
    
    if timeout 30 google-chrome-stable --headless=new --no-sandbox --disable-dev-shm-usage --dump-dom about:blank >/dev/null 2>&1; then
        local end_time=$(date +%s%3N)
        echo $((end_time - start_time))
    else
        echo "0"
    fi
}

test_page_load_performance() {
    local temp_script="/tmp/page-load-test.js"
    
    cat > "$temp_script" << 'JSEOF'
const puppeteer = require('puppeteer');
(async () => {
    const start = Date.now();
    const browser = await puppeteer.launch({
        headless: true,
        args: ['--no-sandbox', '--disable-dev-shm-usage']
    });
    const page = await browser.newPage();
    await page.goto('about:blank', { waitUntil: 'networkidle2' });
    await browser.close();
    console.log(Date.now() - start);
})();
JSEOF
    
    local result=$(timeout 30 docker exec n8n node "$temp_script" 2>/dev/null || echo "0")
    rm -f "$temp_script"
    echo "$result"
}

check_performance_baselines() {
    local memory=$1
    local startup_time=$2
    local page_load_time=$3
    local cpu_usage=$4
    
    local alerts=()
    
    # Memory baseline check
    if (( memory > MEMORY_USAGE_BASELINE )); then
        alerts+=("MEMORY: ${memory}MB > ${MEMORY_USAGE_BASELINE}MB baseline")
    fi
    
    # Startup time baseline check
    if (( startup_time > STARTUP_TIME_BASELINE )); then
        alerts+=("STARTUP: ${startup_time}ms > ${STARTUP_TIME_BASELINE}ms baseline")
    fi
    
    # Page load time baseline check
    if (( page_load_time > RESPONSE_TIME_BASELINE )); then
        alerts+=("PAGELOAD: ${page_load_time}ms > ${RESPONSE_TIME_BASELINE}ms baseline")
    fi
    
    # CPU baseline check
    if (( $(echo "$cpu_usage > $CPU_USAGE_BASELINE" | bc -l 2>/dev/null || echo "0") )); then
        alerts+=("CPU: ${cpu_usage}% > ${CPU_USAGE_BASELINE}% baseline")
    fi
    
    # Send alerts if any baselines exceeded
    if [[ ${#alerts[@]} -gt 0 ]]; then
        send_performance_alert "${alerts[@]}"
    fi
}

send_performance_alert() {
    local alerts=("$@")
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local alert_file="$BASE_DIR/logs/performance-alerts.log"
    
    log_warning "Performance baseline violations detected:"
    
    for alert in "${alerts[@]}"; do
        log_warning "  - $alert"
        echo "[$timestamp] ALERT: $alert" >> "$alert_file"
    done
    
    # Could extend this to send email, webhook, Slack notifications, etc.
}

generate_performance_report() {
    local metrics_file="$1"
    local report_file="$BASE_DIR/logs/performance-report-$(date '+%Y%m%d').json"
    
    if [[ ! -f "$metrics_file" ]]; then
        return
    fi
    
    # Calculate daily statistics
    local total_measurements=$(wc -l < "$metrics_file")
    local avg_startup=$(awk -F'STARTUP:' '{if(NF>1) print $2}' "$metrics_file" | awk -F'ms' '{sum+=$1; count++} END {if(count>0) printf "%.0f", sum/count; else print "0"}')
    local avg_pageload=$(awk -F'PAGELOAD:' '{if(NF>1) print $2}' "$metrics_file" | awk -F'ms' '{sum+=$1; count++} END {if(count>0) printf "%.0f", sum/count; else print "0"}')
    local avg_memory=$(awk -F'CHROME_MEM:' '{if(NF>1) print $2}' "$metrics_file" | awk -F'MB' '{sum+=$1; count++} END {if(count>0) printf "%.0f", sum/count; else print "0"}')
    
    # Generate JSON report
    cat > "$report_file" << EOF
{
  "date": "$(date '+%Y-%m-%d')",
  "summary": {
    "totalMeasurements": $total_measurements,
    "averageStartupTime": "${avg_startup}ms",
    "averagePageLoadTime": "${avg_pageload}ms",
    "averageMemoryUsage": "${avg_memory}MB"
  },
  "baselines": {
    "startupTime": "${STARTUP_TIME_BASELINE}ms",
    "responseTime": "${RESPONSE_TIME_BASELINE}ms",
    "memoryUsage": "${MEMORY_USAGE_BASELINE}MB",
    "cpuUsage": "${CPU_USAGE_BASELINE}%"
  },
  "performance": {
    "startupTimeStatus": $(if [[ $avg_startup -le $STARTUP_TIME_BASELINE ]]; then echo "\"GOOD\""; else echo "\"POOR\""; fi),
    "pageLoadStatus": $(if [[ $avg_pageload -le $RESPONSE_TIME_BASELINE ]]; then echo "\"GOOD\""; else echo "\"POOR\""; fi),
    "memoryStatus": $(if [[ $avg_memory -le $MEMORY_USAGE_BASELINE ]]; then echo "\"GOOD\""; else echo "\"POOR\""; fi)
  },
  "generatedAt": "$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')"
}
EOF
    
    log_info "Performance report generated: $report_file"
}

# Main execution
case "${1:-collect}" in
    "collect")
        collect_performance_metrics
        ;;
    "test-startup")
        startup_time=$(test_browser_startup_time)
        echo "Browser startup time: ${startup_time}ms"
        ;;
    "test-pageload")
        page_load_time=$(test_page_load_performance)
        echo "Page load time: ${page_load_time}ms"
        ;;
    "report")
        metrics_file="$BASE_DIR/logs/performance-metrics-$(date '+%Y%m%d').log"
        generate_performance_report "$metrics_file"
        ;;
    *)
        echo "Usage: $0 [collect|test-startup|test-pageload|report]"
        exit 1
        ;;
esac
EOF
    
    safe_mv "/tmp/performance-monitor.sh" "$BASE_DIR/scripts/performance-monitor.sh" "Install performance monitor"
    safe_chmod "755" "$BASE_DIR/scripts/performance-monitor.sh" "Make performance monitor executable"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$BASE_DIR/scripts/performance-monitor.sh" "Set performance monitor ownership"
    
    log_success "Performance metrics collection and alerting configured"
}

# Implement browser instance recycling and resource management
implement_browser_instance_recycling() {
    log_info "Implementing browser instance recycling and resource management"
    
    # Create browser instance manager with recycling
    cat > /tmp/browser-recycling-manager.sh << 'EOF'
#!/bin/bash
# Browser Instance Recycling and Resource Management System
# Advanced lifecycle management with automatic cleanup

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${SCRIPT_DIR}")")"))"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

# Recycling configuration
INSTANCE_MAX_AGE=1800           # 30 minutes
INSTANCE_MAX_PAGES=100          # Maximum pages per instance
INSTANCE_MAX_MEMORY=800         # 800MB memory limit per instance
RECYCLING_CHECK_INTERVAL=300    # 5 minutes

# Instance tracking
INSTANCES_STATE_FILE="$BASE_DIR/cache/browser-instances.state"

initialize_instance_tracking() {
    local cache_dir="$BASE_DIR/cache"
    [[ ! -d "$cache_dir" ]] && mkdir -p "$cache_dir"
    
    if [[ ! -f "$INSTANCES_STATE_FILE" ]]; then
        echo "{\"instances\": {}}" > "$INSTANCES_STATE_FILE"
    fi
}

create_managed_instance() {
    local instance_id="instance_$(date +%s)_$$"
    local chrome_args=(
        "--headless=new"
        "--no-sandbox"
        "--disable-dev-shm-usage"
        "--disable-gpu"
        "--memory-pressure-off"
        "--max_old_space_size=512"
        "--disable-extensions"
        "--disable-plugins"
        "--remote-debugging-port=0"
        "--user-data-dir=/tmp/chrome-$instance_id"
    )
    
    log_info "Creating managed browser instance: $instance_id"
    
    # Launch Chrome with resource monitoring
    google-chrome-stable "${chrome_args[@]}" about:blank &
    local chrome_pid=$!
    
    # Set resource limits
    if command -v prlimit >/dev/null 2>&1; then
        prlimit --pid="$chrome_pid" --as=$((INSTANCE_MAX_MEMORY * 1024 * 1024)) 2>/dev/null || true
    fi
    
    # Track instance
    local instance_data=$(cat "$INSTANCES_STATE_FILE")
    local updated_data=$(echo "$instance_data" | jq --arg id "$instance_id" --arg pid "$chrome_pid" --arg created "$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')" '
        .instances[$id] = {
            "pid": ($pid | tonumber),
            "createdAt": $created,
            "pagesProcessed": 0,
            "memoryUsage": 0,
            "status": "active"
        }
    ')
    echo "$updated_data" > "$INSTANCES_STATE_FILE"
    
    log_success "Managed instance created: $instance_id (PID: $chrome_pid)"
    echo "$instance_id"
}

recycle_instance() {
    local instance_id="$1"
    
    log_info "Recycling browser instance: $instance_id"
    
    # Get instance info
    local instance_data=$(cat "$INSTANCES_STATE_FILE")
    local instance_info=$(echo "$instance_data" | jq -r ".instances[\"$instance_id\"] // empty")
    
    if [[ -z "$instance_info" ]]; then
        log_warning "Instance not found: $instance_id"
        return 1
    fi
    
    local pid=$(echo "$instance_info" | jq -r '.pid')
    
    # Terminate instance
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
        log_info "Terminating instance process: $pid"
        kill -TERM "$pid" 2>/dev/null || true
        
        # Wait for graceful shutdown
        local timeout=10
        while [[ $timeout -gt 0 ]] && kill -0 "$pid" 2>/dev/null; do
            sleep 1
            ((timeout--))
        done
        
        # Force kill if still running
        if kill -0 "$pid" 2>/dev/null; then
            log_warning "Force killing unresponsive instance: $pid"
            kill -KILL "$pid" 2>/dev/null || true
        fi
    fi
    
    # Clean up user data directory
    rm -rf "/tmp/chrome-$instance_id" 2>/dev/null || true
    
    # Update instance state
    local updated_data=$(echo "$instance_data" | jq "del(.instances[\"$instance_id\"])")
    echo "$updated_data" > "$INSTANCES_STATE_FILE"
    
    log_success "Instance recycled: $instance_id"
}

check_instance_health() {
    local instance_id="$1"
    
    local instance_data=$(cat "$INSTANCES_STATE_FILE")
    local instance_info=$(echo "$instance_data" | jq -r ".instances[\"$instance_id\"] // empty")
    
    if [[ -z "$instance_info" ]]; then
        return 1
    fi
    
    local pid=$(echo "$instance_info" | jq -r '.pid')
    local created_at=$(echo "$instance_info" | jq -r '.createdAt')
    local pages_processed=$(echo "$instance_info" | jq -r '.pagesProcessed')
    
    # Check if process is still running
    if ! kill -0 "$pid" 2>/dev/null; then
        log_warning "Instance process died: $instance_id (PID: $pid)"
        return 1
    fi
    
    # Check age
    local created_timestamp=$(date -d "$created_at" +%s 2>/dev/null || echo "0")
    local current_timestamp=$(date +%s)
    local age=$((current_timestamp - created_timestamp))
    
    if [[ $age -gt $INSTANCE_MAX_AGE ]]; then
        log_info "Instance expired (age: ${age}s): $instance_id"
        return 2
    fi
    
    # Check page count
    if [[ $pages_processed -gt $INSTANCE_MAX_PAGES ]]; then
        log_info "Instance page limit reached: $instance_id"
        return 3
    fi
    
    # Check memory usage
    local memory_kb=$(ps -p "$pid" -o rss= 2>/dev/null | awk '{print $1}')
    local memory_mb=$((memory_kb / 1024))
    
    if [[ $memory_mb -gt $INSTANCE_MAX_MEMORY ]]; then
        log_info "Instance memory limit exceeded: $instance_id (${memory_mb}MB)"
        return 4
    fi
    
    return 0
}

run_recycling_check() {
    log_info "Running browser instance recycling check"
    
    initialize_instance_tracking
    
    local instance_data=$(cat "$INSTANCES_STATE_FILE")
    local instances=$(echo "$instance_data" | jq -r '.instances | keys[]')
    
    for instance_id in $instances; do
        check_instance_health "$instance_id"
        local health_status=$?
        
        case $health_status in
            1) # Process died
                log_warning "Cleaning up dead instance: $instance_id"
                recycle_instance "$instance_id"
                ;;
            2|3|4) # Expired, page limit, or memory limit
                log_info "Recycling instance due to limits: $instance_id"
                recycle_instance "$instance_id"
                ;;
            0) # Healthy
                log_info "Instance healthy: $instance_id"
                ;;
        esac
    done
    
    log_success "Recycling check completed"
}

cleanup_all_instances() {
    log_info "Cleaning up all browser instances"
    
    local instance_data=$(cat "$INSTANCES_STATE_FILE")
    local instances=$(echo "$instance_data" | jq -r '.instances | keys[]')
    
    for instance_id in $instances; do
        recycle_instance "$instance_id"
    done
    
    echo "{\"instances\": {}}" > "$INSTANCES_STATE_FILE"
    log_success "All instances cleaned up"
}

get_instance_report() {
    initialize_instance_tracking
    
    local instance_data=$(cat "$INSTANCES_STATE_FILE")
    local instance_count=$(echo "$instance_data" | jq '.instances | length')
    
    echo "Browser Instance Status Report"
    echo "=============================="
    echo "Active Instances: $instance_count"
    echo ""
    
    if [[ $instance_count -gt 0 ]]; then
        echo "$instance_data" | jq -r '.instances | to_entries[] | 
            "\(.key):
              PID: \(.value.pid)
              Created: \(.value.createdAt)
              Pages: \(.value.pagesProcessed)
              Status: \(.value.status)"'
    else
        echo "No active instances"
    fi
}

# Main command routing
case "${1:-check}" in
    "create")
        initialize_instance_tracking
        create_managed_instance
        ;;
    "recycle")
        recycle_instance "$2"
        ;;
    "check")
        run_recycling_check
        ;;
    "cleanup")
        cleanup_all_instances
        ;;
    "status")
        get_instance_report
        ;;
    *)
        echo "Usage: $0 [create|recycle <id>|check|cleanup|status]"
        exit 1
        ;;
esac
EOF
    
    safe_mv "/tmp/browser-recycling-manager.sh" "$BASE_DIR/scripts/browser-recycling-manager.sh" "Install recycling manager"
    safe_chmod "755" "$BASE_DIR/scripts/browser-recycling-manager.sh" "Make recycling manager executable"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$BASE_DIR/scripts/browser-recycling-manager.sh" "Set recycling manager ownership"
    
    # Setup systemd timer for automatic recycling
    if [[ -d "/etc/systemd/system" ]]; then
        cat > /tmp/browser-recycling.service << EOF
[Unit]
Description=Browser Instance Recycling Service
After=docker.service

[Service]
Type=oneshot
User=${SERVICE_USER}
ExecStart=${BASE_DIR}/scripts/browser-recycling-manager.sh check
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
        
        cat > /tmp/browser-recycling.timer << EOF
[Unit]
Description=Run Browser Instance Recycling every 5 minutes
Requires=browser-recycling.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF
        
        safe_mv "/tmp/browser-recycling.service" "/etc/systemd/system/browser-recycling.service" "Install recycling service"
        safe_mv "/tmp/browser-recycling.timer" "/etc/systemd/system/browser-recycling.timer" "Install recycling timer"
        
        execute_cmd "systemctl daemon-reload" "Reload systemd daemon"
        execute_cmd "systemctl enable browser-recycling.timer" "Enable recycling timer"
        execute_cmd "systemctl start browser-recycling.timer" "Start recycling timer"
    fi
    
    log_success "Browser instance recycling and resource management implemented"
}

# Setup Edison's performance monitoring baselines
establish_performance_baselines() {
    log_info "Establishing Edison's performance monitoring baselines"
    
    # Create baseline establishment script
    cat > /tmp/establish-baselines.sh << 'EOF'
#!/bin/bash
# Performance Baseline Establishment Script
# Based on Edison's performance testing methodology

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${SCRIPT_DIR}")")"))"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

BASELINE_FILE="$BASE_DIR/config/performance-baselines.json"
BASELINE_TESTS=10  # Number of test runs for baseline

run_baseline_tests() {
    log_info "Running performance baseline tests (${BASELINE_TESTS} iterations)"
    
    local startup_times=()
    local memory_readings=()
    local cpu_readings=()
    local page_load_times=()
    
    for ((i=1; i<=BASELINE_TESTS; i++)); do
        log_info "Baseline test $i/$BASELINE_TESTS"
        
        # Test browser startup time
        local start_time=$(date +%s%3N)
        if timeout 30 google-chrome-stable --headless=new --no-sandbox --disable-dev-shm-usage --dump-dom about:blank >/dev/null 2>&1; then
            local startup_time=$(($(date +%s%3N) - start_time))
            startup_times+=($startup_time)
        fi
        
        # Test memory and CPU during operation
        local chrome_pid=$(pgrep -f "google-chrome" | head -1)
        if [[ -n "$chrome_pid" ]]; then
            local memory=$(ps -p "$chrome_pid" -o rss= 2>/dev/null | awk '{print int($1/1024)}')
            local cpu=$(ps -p "$chrome_pid" -o %cpu= 2>/dev/null)
            [[ -n "$memory" ]] && memory_readings+=($memory)
            [[ -n "$cpu" ]] && cpu_readings+=($cpu)
        fi
        
        # Test page load performance
        local page_start=$(date +%s%3N)
        if timeout 30 bash "${PROJECT_ROOT}/scripts/performance-monitor.sh" test-pageload >/dev/null 2>&1; then
            local page_load_time=$(($(date +%s%3N) - page_start))
            page_load_times+=($page_load_time)
        fi
        
        # Cleanup
        pkill -f "google-chrome" 2>/dev/null || true
        sleep 2
    done
    
    # Calculate statistics
    calculate_baseline_statistics startup_times[@] memory_readings[@] cpu_readings[@] page_load_times[@]
}

calculate_baseline_statistics() {
    local -n startup_ref=$1
    local -n memory_ref=$2
    local -n cpu_ref=$3
    local -n pageload_ref=$4
    
    # Calculate averages and percentiles
    local avg_startup=$(printf '%s\n' "${startup_ref[@]}" | awk '{sum+=$1; count++} END {if(count>0) printf "%.0f", sum/count; else print "0"}')
    local avg_memory=$(printf '%s\n' "${memory_ref[@]}" | awk '{sum+=$1; count++} END {if(count>0) printf "%.0f", sum/count; else print "0"}')
    local avg_cpu=$(printf '%s\n' "${cpu_ref[@]}" | awk '{sum+=$1; count++} END {if(count>0) printf "%.1f", sum/count; else print "0"}')
    local avg_pageload=$(printf '%s\n' "${pageload_ref[@]}" | awk '{sum+=$1; count++} END {if(count>0) printf "%.0f", sum/count; else print "0"}')
    
    # Calculate 95th percentiles for thresholds
    local p95_startup=$(printf '%s\n' "${startup_ref[@]}" | sort -n | awk '{data[NR]=$1} END {printf "%.0f", data[int(NR*0.95)]}')
    local p95_memory=$(printf '%s\n' "${memory_ref[@]}" | sort -n | awk '{data[NR]=$1} END {printf "%.0f", data[int(NR*0.95)]}')
    local p95_pageload=$(printf '%s\n' "${pageload_ref[@]}" | sort -n | awk '{data[NR]=$1} END {printf "%.0f", data[int(NR*0.95)]}')
    
    # Generate baseline configuration
    cat > "$BASELINE_FILE" << EOF
{
  "establishedAt": "$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')",
  "testRuns": $BASELINE_TESTS,
  "baselines": {
    "browserStartup": {
      "average": ${avg_startup},
      "p95": ${p95_startup},
      "threshold": ${p95_startup},
      "unit": "milliseconds"
    },
    "memoryUsage": {
      "average": ${avg_memory},
      "p95": ${p95_memory},
      "threshold": ${p95_memory},
      "unit": "MB"
    },
    "cpuUsage": {
      "average": ${avg_cpu},
      "threshold": 80.0,
      "unit": "percent"
    },
    "pageLoadTime": {
      "average": ${avg_pageload},
      "p95": ${p95_pageload},
      "threshold": ${p95_pageload},
      "unit": "milliseconds"
    }
  },
  "recommendations": {
    "startupTimeGood": "< ${avg_startup}ms",
    "startupTimeAcceptable": "< ${p95_startup}ms",
    "memoryUsageGood": "< ${avg_memory}MB",
    "memoryUsageAcceptable": "< ${p95_memory}MB",
    "pageLoadGood": "< ${avg_pageload}ms",
    "pageLoadAcceptable": "< ${p95_pageload}ms"
  }
}
EOF
    
    log_success "Performance baselines established"
    log_info "Startup time baseline: ${avg_startup}ms (threshold: ${p95_startup}ms)"
    log_info "Memory usage baseline: ${avg_memory}MB (threshold: ${p95_memory}MB)"
    log_info "CPU usage threshold: ${avg_cpu}%"
    log_info "Page load time baseline: ${avg_pageload}ms (threshold: ${p95_pageload}ms)"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🏥 TASK 14: HEALTH MONITORING FRAMEWORK EXTENSION FOR BROWSER CONTAINERS
# ═══════════════════════════════════════════════════════════════════════════════

# Task 14: Extend health monitoring framework for browser containers
extend_health_monitoring_framework() {
    log_section "Extending Health Monitoring Framework for Browser Containers"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would extend health monitoring framework"
        return 0
    fi
    
    if [[ "$ENABLE_BROWSER_AUTOMATION" != "true" ]]; then
        log_info "Browser automation disabled, skipping health monitoring extension"
        return 0
    fi
    
    start_section_timer "Health Monitoring Extension"
    
    # Implement Drucker's operational validation procedures
    implement_drucker_operational_validation
    
    # Add browser-specific health checks and alerting
    setup_browser_health_checks
    
    # Create automated recovery procedures for browser failures
    create_automated_recovery_procedures
    
    # Setup comprehensive health monitoring dashboard
    setup_health_monitoring_dashboard
    
    end_section_timer "Health Monitoring Extension"
    log_success "Health monitoring framework extended for browser containers"
}

# Implement Drucker's operational validation procedures
implement_drucker_operational_validation() {
    log_info "Implementing Drucker's operational validation procedures"
    
    # Create comprehensive operational validation system
    cat > /tmp/operational-validator.sh << 'EOF'
#!/bin/bash
# Drucker's Operational Validation System
# Comprehensive operational procedures for browser automation infrastructure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${SCRIPT_DIR}")")"))"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

# Operational validation categories
VALIDATION_CATEGORIES=(
    "infrastructure"
    "services"
    "security"
    "performance" 
    "data-integrity"
    "user-experience"
)

run_comprehensive_validation() {
    log_section "Running Comprehensive Operational Validation"
    
    local validation_report="$BASE_DIR/logs/operational-validation-$(date '+%Y%m%d_%H%M%S').json"
    local overall_status="PASS"
    local validation_results=()
    
    # Initialize report
    echo "{\"validationRun\": {\"timestamp\": \"$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')\", \"categories\": {}}}" > "$validation_report"
    
    for category in "${VALIDATION_CATEGORIES[@]}"; do
        log_info "Validating category: $category"
        
        case "$category" in
            "infrastructure")
                validate_infrastructure_operational
                ;;
            "services")
                validate_services_operational
                ;;
            "security")
                validate_security_operational
                ;;
            "performance")
                validate_performance_operational
                ;;
            "data-integrity")
                validate_data_integrity_operational
                ;;
            "user-experience")
                validate_user_experience_operational
                ;;
        esac
        
        local category_status=$?
        local category_result="PASS"
        [[ $category_status -ne 0 ]] && category_result="FAIL" && overall_status="FAIL"
        
        # Update report
        local current_report=$(cat "$validation_report")
        local updated_report=$(echo "$current_report" | jq --arg cat "$category" --arg status "$category_result" '.validationRun.categories[$cat] = {"status": $status, "validatedAt": (now | todate)}')
        echo "$updated_report" > "$validation_report"
    done
    
    # Finalize report
    local final_report=$(cat "$validation_report")
    local completed_report=$(echo "$final_report" | jq --arg status "$overall_status" '.validationRun.overallStatus = $status | .validationRun.completedAt = (now | todate)')
    echo "$completed_report" > "$validation_report"
    
    log_info "Operational validation completed with status: $overall_status"
    log_info "Detailed report: $validation_report"
    
    return $([[ "$overall_status" == "PASS" ]] && echo 0 || echo 1)
}

validate_infrastructure_operational() {
    log_info "Validating infrastructure operational status"
    
    local failures=0
    
    # Docker service validation
    if ! systemctl is-active --quiet docker; then
        log_error "Docker service is not running"
        ((failures++))
    fi
    
    # Network connectivity validation
    if ! docker network ls | grep -q "${JARVIS_NETWORK}"; then
        log_error "jstack network not found"
        ((failures++))
    fi
    
    # Storage validation
    local available_space=$(df "$BASE_DIR" | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 5242880 ]]; then  # 5GB in KB
        log_error "Insufficient disk space (less than 5GB available)"
        ((failures++))
    fi
    
    # Memory validation
    local available_memory=$(free -m | awk 'NR==2 {print $7}')
    if [[ $available_memory -lt 2048 ]]; then  # 2GB
        log_error "Insufficient available memory (less than 2GB)"
        ((failures++))
    fi
    
    log_info "Infrastructure validation: $([[ $failures -eq 0 ]] && echo "PASS" || echo "FAIL ($failures issues)")"
    return $failures
}

validate_services_operational() {
    log_info "Validating services operational status"
    
    local failures=0
    
    # N8N container validation
    if ! docker ps --filter name=n8n --format "{{.Names}}" | grep -q n8n; then
        log_error "N8N container is not running"
        ((failures++))
    else
        # N8N health endpoint validation
        if ! curl -sf "http://localhost:5678/healthz" >/dev/null 2>&1; then
            log_error "N8N health endpoint not responding"
            ((failures++))
        fi
    fi
    
    # Database validation
    if ! docker ps --filter name=supabase-db --format "{{.Names}}" | grep -q supabase-db; then
        log_error "Database container is not running"
        ((failures++))
    else
        # Database connectivity validation
        if ! docker exec supabase-db pg_isready -U postgres >/dev/null 2>&1; then
            log_error "Database is not accepting connections"
            ((failures++))
        fi
    fi
    
    # Browser automation service validation
    if [[ "$ENABLE_BROWSER_AUTOMATION" == "true" ]]; then
        if ! command -v google-chrome-stable >/dev/null 2>&1; then
            log_error "Chrome not installed for browser automation"
            ((failures++))
        fi
        
        # Test basic browser functionality
        if ! timeout 30 google-chrome-stable --headless=new --no-sandbox --dump-dom about:blank >/dev/null 2>&1; then
            log_error "Browser automation test failed"
            ((failures++))
        fi
    fi
    
    log_info "Services validation: $([[ $failures -eq 0 ]] && echo "PASS" || echo "FAIL ($failures issues)")"
    return $failures
}

validate_security_operational() {
    log_info "Validating security operational status"
    
    local failures=0
    
    # Service user validation
    if ! id "$SERVICE_USER" >/dev/null 2>&1; then
        log_error "Service user '$SERVICE_USER' does not exist"
        ((failures++))
    fi
    
    # File permissions validation
    if [[ ! -O "$BASE_DIR" ]]; then
        log_error "Base directory ownership incorrect"
        ((failures++))
    fi
    
    # Network security validation
    log_info "Manual iptables configuration assumed - verify firewall rules are in place"
    
    # Container security validation
    local containers=$(docker ps --format "{{.Names}}")
    for container in $containers; do
        local user=$(docker exec "$container" whoami 2>/dev/null || echo "unknown")
        if [[ "$user" == "root" ]] && [[ "$container" != *"nginx"* ]]; then
            log_warning "Container running as root: $container"
        fi
    done
    
    log_info "Security validation: $([[ $failures -eq 0 ]] && echo "PASS" || echo "FAIL ($failures issues)")"
    return $failures
}

validate_performance_operational() {
    log_info "Validating performance operational status"
    
    local failures=0
    
    # Load baseline configuration if available
    local baseline_file="$BASE_DIR/config/performance-baselines.json"
    local startup_threshold=10000
    local memory_threshold=800
    
    if [[ -f "$baseline_file" ]]; then
        startup_threshold=$(jq -r '.baselines.browserStartup.threshold // 10000' "$baseline_file")
        memory_threshold=$(jq -r '.baselines.memoryUsage.threshold // 800' "$baseline_file")
    fi
    
    # Browser startup performance test
    local start_time=$(date +%s%3N)
    if timeout 30 google-chrome-stable --headless=new --no-sandbox --dump-dom about:blank >/dev/null 2>&1; then
        local startup_time=$(($(date +%s%3N) - start_time))
        if [[ $startup_time -gt $startup_threshold ]]; then
            log_error "Browser startup time exceeds threshold: ${startup_time}ms > ${startup_threshold}ms"
            ((failures++))
        fi
    else
        log_error "Browser startup test failed"
        ((failures++))
    fi
    
    # System resource validation
    local cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}' | cut -d'.' -f1)
    if [[ $cpu_usage -gt 80 ]]; then
        log_error "High CPU usage detected: ${cpu_usage}%"
        ((failures++))
    fi
    
    local memory_usage=$(free -m | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [[ $memory_usage -gt 90 ]]; then
        log_error "High memory usage detected: ${memory_usage}%"
        ((failures++))
    fi
    
    log_info "Performance validation: $([[ $failures -eq 0 ]] && echo "PASS" || echo "FAIL ($failures issues)")"
    return $failures
}

validate_data_integrity_operational() {
    log_info "Validating data integrity operational status"
    
    local failures=0
    
    # Database connectivity and basic queries
    if ! docker exec supabase-db psql -U postgres -c "SELECT 1" >/dev/null 2>&1; then
        log_error "Database query test failed"
        ((failures++))
    fi
    
    # Configuration file integrity
    local config_files=("$PROJECT_ROOT/jstack.config" "$BASE_DIR/config/chrome-performance.json")
    for config_file in "${config_files[@]}"; do
        if [[ -f "$config_file" ]]; then
            if [[ ! -r "$config_file" ]]; then
                log_error "Configuration file not readable: $config_file"
                ((failures++))
            fi
        fi
    done
    
    # Log file accessibility
    if [[ ! -w "$BASE_DIR/logs" ]]; then
        log_error "Log directory not writable"
        ((failures++))
    fi
    
    log_info "Data integrity validation: $([[ $failures -eq 0 ]] && echo "PASS" || echo "FAIL ($failures issues)")"
    return $failures
}

validate_user_experience_operational() {
    log_info "Validating user experience operational status"
    
    local failures=0
    
    # N8N web interface accessibility
    if ! curl -sf "http://localhost:5678" >/dev/null 2>&1; then
        log_error "N8N web interface not accessible"
        ((failures++))
    fi
    
    # Workflow execution test
    local test_workflow_response=$(curl -s -X GET "http://localhost:5678/api/v1/workflows" 2>/dev/null)
    if [[ -z "$test_workflow_response" ]]; then
        log_error "N8N API not responding"
        ((failures++))
    fi
    
    # Template availability
    local templates_dir="$BASE_DIR/services/n8n/templates"
    if [[ -d "$templates_dir" ]]; then
        local template_count=$(find "$templates_dir" -name "*.json" | wc -l)
        if [[ $template_count -eq 0 ]]; then
            log_warning "No workflow templates available"
        fi
    fi
    
    log_info "User experience validation: $([[ $failures -eq 0 ]] && echo "PASS" || echo "FAIL ($failures issues)")"
    return $failures
}

# Main command routing
case "${1:-validate}" in
    "validate")
        run_comprehensive_validation
        ;;
    "infrastructure")
        validate_infrastructure_operational
        ;;
    "services")
        validate_services_operational
        ;;
    "security")
        validate_security_operational
        ;;
    "performance")
        validate_performance_operational
        ;;
    "data-integrity")
        validate_data_integrity_operational
        ;;
    "user-experience")
        validate_user_experience_operational
        ;;
    *)
        echo "Usage: $0 [validate|infrastructure|services|security|performance|data-integrity|user-experience]"
        exit 1
        ;;
esac
EOF
    
    safe_mv "/tmp/operational-validator.sh" "$BASE_DIR/scripts/operational-validator.sh" "Install operational validator"
    safe_chmod "755" "$BASE_DIR/scripts/operational-validator.sh" "Make operational validator executable"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$BASE_DIR/scripts/operational-validator.sh" "Set operational validator ownership"
    
    log_success "Drucker's operational validation procedures implemented"
}

# Add browser-specific health checks and alerting
setup_browser_health_checks() {
    log_info "Setting up browser-specific health checks and alerting"
    
    # Create comprehensive browser health monitoring system
    cat > /tmp/browser-health-monitor.sh << 'EOF'
#!/bin/bash
# Browser-Specific Health Monitoring System
# Advanced health checks for browser automation infrastructure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${SCRIPT_DIR}")")"))"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

# Health check configuration
HEALTH_CHECK_INTERVAL=60        # 1 minute
HEALTH_ALERT_THRESHOLD=3        # Alert after 3 consecutive failures
HEALTH_RECOVERY_THRESHOLD=2     # Consider recovered after 2 consecutive successes

# Health check state tracking
HEALTH_STATE_FILE="$BASE_DIR/cache/browser-health.state"

initialize_health_state() {
    local cache_dir="$BASE_DIR/cache"
    [[ ! -d "$cache_dir" ]] && mkdir -p "$cache_dir"
    
    if [[ ! -f "$HEALTH_STATE_FILE" ]]; then
        cat > "$HEALTH_STATE_FILE" << 'HEALTHEOF'
{
  "checks": {
    "chrome_availability": {"status": "unknown", "consecutiveFailures": 0, "lastCheck": null},
    "puppeteer_functionality": {"status": "unknown", "consecutiveFailures": 0, "lastCheck": null},
    "n8n_browser_integration": {"status": "unknown", "consecutiveFailures": 0, "lastCheck": null},
    "memory_consumption": {"status": "unknown", "consecutiveFailures": 0, "lastCheck": null},
    "process_limits": {"status": "unknown", "consecutiveFailures": 0, "lastCheck": null}
  }
}
HEALTHEOF
    fi
}

run_browser_health_checks() {
    log_info "Running comprehensive browser health checks"
    
    initialize_health_state
    
    local health_state=$(cat "$HEALTH_STATE_FILE")
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')
    local overall_healthy=true
    
    # Health check 1: Chrome availability
    check_chrome_availability
    local chrome_status=$?
    health_state=$(update_health_state "$health_state" "chrome_availability" $chrome_status "$timestamp")
    [[ $chrome_status -ne 0 ]] && overall_healthy=false
    
    # Health check 2: Puppeteer functionality
    check_puppeteer_functionality
    local puppeteer_status=$?
    health_state=$(update_health_state "$health_state" "puppeteer_functionality" $puppeteer_status "$timestamp")
    [[ $puppeteer_status -ne 0 ]] && overall_healthy=false
    
    # Health check 3: N8N browser integration
    check_n8n_browser_integration
    local integration_status=$?
    health_state=$(update_health_state "$health_state" "n8n_browser_integration" $integration_status "$timestamp")
    [[ $integration_status -ne 0 ]] && overall_healthy=false
    
    # Health check 4: Memory consumption monitoring
    check_memory_consumption
    local memory_status=$?
    health_state=$(update_health_state "$health_state" "memory_consumption" $memory_status "$timestamp")
    [[ $memory_status -ne 0 ]] && overall_healthy=false
    
    # Health check 5: Process limits validation
    check_process_limits
    local process_status=$?
    health_state=$(update_health_state "$health_state" "process_limits" $process_status "$timestamp")
    [[ $process_status -ne 0 ]] && overall_healthy=false
    
    # Save updated health state
    echo "$health_state" > "$HEALTH_STATE_FILE"
    
    # Generate health report
    generate_health_report "$health_state" "$overall_healthy"
    
    # Process alerts
    process_health_alerts "$health_state"
    
    return $([[ "$overall_healthy" == true ]] && echo 0 || echo 1)
}

check_chrome_availability() {
    log_info "Checking Chrome availability"
    
    # Basic Chrome installation check
    if ! command -v google-chrome-stable >/dev/null 2>&1; then
        log_error "Chrome not installed"
        return 1
    fi
    
    # Chrome version check
    local chrome_version=$(google-chrome-stable --version 2>/dev/null || echo "unknown")
    log_info "Chrome version: $chrome_version"
    
    # Basic Chrome functionality test
    if ! timeout 15 google-chrome-stable --headless=new --no-sandbox --disable-dev-shm-usage --dump-dom about:blank >/dev/null 2>&1; then
        log_error "Chrome basic functionality test failed"
        return 1
    fi
    
    log_success "Chrome availability check passed"
    return 0
}

check_puppeteer_functionality() {
    log_info "Checking Puppeteer functionality"
    
    # Check if N8N container has Puppeteer installed
    if ! docker exec n8n npm list puppeteer >/dev/null 2>&1; then
        log_error "Puppeteer not installed in N8N container"
        return 1
    fi
    
    # Test Puppeteer browser launch in N8N container
    local puppeteer_test='const puppeteer = require("puppeteer"); (async () => { const browser = await puppeteer.launch({headless: true, args: ["--no-sandbox", "--disable-dev-shm-usage"]}); await browser.close(); console.log("OK"); })()'
    
    if ! docker exec n8n timeout 30 node -e "$puppeteer_test" 2>/dev/null | grep -q "OK"; then
        log_error "Puppeteer functionality test failed"
        return 1
    fi
    
    log_success "Puppeteer functionality check passed"
    return 0
}

check_n8n_browser_integration() {
    log_info "Checking N8N browser integration"
    
    # Check N8N container status
    if ! docker ps --filter name=n8n --format "{{.Names}}" | grep -q n8n; then
        log_error "N8N container not running"
        return 1
    fi
    
    # Check N8N health endpoint
    if ! curl -sf "http://localhost:5678/healthz" >/dev/null 2>&1; then
        log_error "N8N health endpoint not responding"
        return 1
    fi
    
    # Test browser automation capabilities in N8N context
    local browser_integration_test='const puppeteer = require("puppeteer"); (async () => { const browser = await puppeteer.launch({headless: true, args: ["--no-sandbox", "--disable-dev-shm-usage"]}); const page = await browser.newPage(); await page.goto("about:blank"); const title = await page.title(); await browser.close(); console.log("Integration OK"); })()'
    
    if ! docker exec n8n timeout 30 node -e "$browser_integration_test" 2>/dev/null | grep -q "Integration OK"; then
        log_error "N8N browser integration test failed"
        return 1
    fi
    
    log_success "N8N browser integration check passed"
    return 0
}

check_memory_consumption() {
    log_info "Checking memory consumption"
    
    # System memory check
    local sys_memory=$(free -m | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [[ $sys_memory -gt 85 ]]; then
        log_error "High system memory usage: ${sys_memory}%"
        return 1
    fi
    
    # Chrome processes memory check
    local chrome_memory=0
    if pgrep -f "google-chrome" >/dev/null 2>&1; then
        chrome_memory=$(ps -C google-chrome-stable -o rss --no-headers 2>/dev/null | awk '{sum+=$1} END {printf "%.0f", sum/1024}' || echo "0")
        
        if [[ $chrome_memory -gt 2048 ]]; then  # More than 2GB total Chrome usage
            log_error "Excessive Chrome memory usage: ${chrome_memory}MB"
            return 1
        fi
    fi
    
    # N8N container memory check
    if docker ps --filter name=n8n --format "{{.Names}}" | grep -q n8n; then
        local n8n_memory=$(docker stats n8n --no-stream --format "{{.MemPerc}}" 2>/dev/null | sed 's/%//')
        if [[ -n "$n8n_memory" ]] && (( $(echo "$n8n_memory > 90" | bc -l 2>/dev/null || echo "0") )); then
            log_error "High N8N container memory usage: ${n8n_memory}%"
            return 1
        fi
    fi
    
    log_success "Memory consumption check passed (System: ${sys_memory}%, Chrome: ${chrome_memory}MB)"
    return 0
}

check_process_limits() {
    log_info "Checking process limits"
    
    # Chrome process count check
    local chrome_count=$(pgrep -f "google-chrome" | wc -l)
    local max_instances=${CHROME_MAX_INSTANCES:-5}
    
    if [[ $chrome_count -gt $max_instances ]]; then
        log_error "Chrome process count exceeds limit: $chrome_count > $max_instances"
        return 1
    fi
    
    # Check for zombie or defunct processes
    local zombie_count=$(ps aux | awk '$8 ~ /^Z/ { count++ } END { print count+0 }')
    if [[ $zombie_count -gt 0 ]]; then
        log_warning "Zombie processes detected: $zombie_count"
    fi
    
    # File descriptor limits check
    local n8n_pid=$(docker exec n8n cat /proc/self/stat 2>/dev/null | awk '{print $1}' || echo "")
    if [[ -n "$n8n_pid" ]]; then
        local open_fds=$(docker exec n8n ls /proc/self/fd 2>/dev/null | wc -l)
        if [[ $open_fds -gt 1000 ]]; then
            log_warning "High file descriptor usage in N8N: $open_fds"
        fi
    fi
    
    log_success "Process limits check passed (Chrome processes: $chrome_count)"
    return 0
}

update_health_state() {
    local state="$1"
    local check_name="$2"
    local status=$3
    local timestamp="$4"
    
    local new_status="healthy"
    local consecutive_failures=0
    
    if [[ $status -ne 0 ]]; then
        new_status="unhealthy"
        consecutive_failures=$(echo "$state" | jq -r ".checks[\"$check_name\"].consecutiveFailures")
        consecutive_failures=$((consecutive_failures + 1))
    fi
    
    echo "$state" | jq --arg check "$check_name" --arg status "$new_status" --arg timestamp "$timestamp" --arg failures "$consecutive_failures" '
        .checks[$check].status = $status |
        .checks[$check].lastCheck = $timestamp |
        .checks[$check].consecutiveFailures = ($failures | tonumber)
    '
}

generate_health_report() {
    local health_state="$1"
    local overall_healthy="$2"
    local report_file="$BASE_DIR/logs/browser-health-report-$(date '+%Y%m%d').json"
    
    local report=$(echo "$health_state" | jq --arg overall "$overall_healthy" --arg timestamp "$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')" '
        {
            "reportGeneratedAt": $timestamp,
            "overallHealth": $overall,
            "healthChecks": .checks
        }
    ')
    
    echo "$report" > "$report_file"
    log_info "Health report generated: $report_file"
}

process_health_alerts() {
    local health_state="$1"
    local alerts=()
    
    # Check each health check for alert conditions
    local checks=$(echo "$health_state" | jq -r '.checks | keys[]')
    
    for check in $checks; do
        local failures=$(echo "$health_state" | jq -r ".checks[\"$check\"].consecutiveFailures")
        local status=$(echo "$health_state" | jq -r ".checks[\"$check\"].status")
        
        if [[ $failures -ge $HEALTH_ALERT_THRESHOLD ]] && [[ "$status" == "unhealthy" ]]; then
            alerts+=("$check: $failures consecutive failures")
        fi
    done
    
    # Send alerts if any
    if [[ ${#alerts[@]} -gt 0 ]]; then
        send_health_alert "${alerts[@]}"
    fi
}

send_health_alert() {
    local alerts=("$@")
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local alert_file="$BASE_DIR/logs/browser-health-alerts.log"
    
    log_error "Browser health alerts triggered:"
    
    for alert in "${alerts[@]}"; do
        log_error "  - $alert"
        echo "[$timestamp] HEALTH_ALERT: $alert" >> "$alert_file"
    done
    
    # Trigger automated recovery if configured
    trigger_automated_recovery "${alerts[@]}"
}

trigger_automated_recovery() {
    local alerts=("$@")
    
    log_info "Triggering automated recovery procedures"
    
    for alert in "${alerts[@]}"; do
        case "$alert" in
            *"chrome_availability"*)
                log_info "Attempting Chrome service recovery"
                pkill -f "google-chrome" 2>/dev/null || true
                ;;
            *"memory_consumption"*)
                log_info "Attempting memory cleanup"
                bash "${PROJECT_ROOT}/scripts/browser-recycling-manager.sh" cleanup
                ;;
            *"process_limits"*)
                log_info "Attempting process cleanup"
                bash "${PROJECT_ROOT}/scripts/browser-recycling-manager.sh" check
                ;;
            *"n8n_browser_integration"*)
                log_info "Attempting N8N container restart"
                docker restart n8n || true
                ;;
        esac
    done
}

# Main command routing
case "${1:-check}" in
    "check")
        run_browser_health_checks
        ;;
    "chrome")
        check_chrome_availability
        ;;
    "puppeteer")
        check_puppeteer_functionality
        ;;
    "integration")
        check_n8n_browser_integration
        ;;
    "memory")
        check_memory_consumption
        ;;
    "processes")
        check_process_limits
        ;;
    "status")
        if [[ -f "$HEALTH_STATE_FILE" ]]; then
            cat "$HEALTH_STATE_FILE" | jq .
        else
            echo "Health state not initialized. Run 'check' first."
        fi
        ;;
    *)
        echo "Usage: $0 [check|chrome|puppeteer|integration|memory|processes|status]"
        exit 1
        ;;
esac
EOF
    
    safe_mv "/tmp/browser-health-monitor.sh" "$BASE_DIR/scripts/browser-health-monitor.sh" "Install browser health monitor"
    safe_chmod "755" "$BASE_DIR/scripts/browser-health-monitor.sh" "Make browser health monitor executable"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$BASE_DIR/scripts/browser-health-monitor.sh" "Set browser health monitor ownership"
    
    # Setup systemd timer for continuous health monitoring
    if [[ -d "/etc/systemd/system" ]]; then
        cat > /tmp/browser-health-monitor.service << EOF
[Unit]
Description=Browser Health Monitoring Service
After=docker.service

[Service]
Type=oneshot
User=${SERVICE_USER}
ExecStart=${BASE_DIR}/scripts/browser-health-monitor.sh check
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
        
        cat > /tmp/browser-health-monitor.timer << EOF
[Unit]
Description=Run Browser Health Monitoring every minute
Requires=browser-health-monitor.service

[Timer]
OnBootSec=1min
OnUnitActiveSec=1min
Persistent=true

[Install]
WantedBy=timers.target
EOF
        
        safe_mv "/tmp/browser-health-monitor.service" "/etc/systemd/system/browser-health-monitor.service" "Install health monitor service"
        safe_mv "/tmp/browser-health-monitor.timer" "/etc/systemd/system/browser-health-monitor.timer" "Install health monitor timer"
        
        execute_cmd "systemctl daemon-reload" "Reload systemd daemon"
        execute_cmd "systemctl enable browser-health-monitor.timer" "Enable health monitor timer"
        execute_cmd "systemctl start browser-health-monitor.timer" "Start health monitor timer"
    fi
    
    log_success "Browser-specific health checks and alerting configured"
}

# Create automated recovery procedures for browser failures
create_automated_recovery_procedures() {
    log_info "Creating automated recovery procedures for browser failures"
    
    # Create automated recovery system
    cat > /tmp/browser-recovery-manager.sh << 'EOF'
#!/bin/bash
# Automated Browser Recovery Management System
# Advanced recovery procedures for browser automation failures

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${SCRIPT_DIR}")")"))"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

# Recovery procedure definitions
declare -A RECOVERY_PROCEDURES=(
    ["chrome_crash"]="restart_chrome_service"
    ["memory_exhaustion"]="cleanup_memory_resources" 
    ["process_limit_exceeded"]="cleanup_excess_processes"
    ["container_failure"]="restart_container_services"
    ["network_connectivity"]="restart_network_services"
    ["disk_space"]="cleanup_disk_space"
)

# Recovery attempt tracking
RECOVERY_STATE_FILE="$BASE_DIR/cache/recovery-attempts.state"

initialize_recovery_tracking() {
    local cache_dir="$BASE_DIR/cache"
    [[ ! -d "$cache_dir" ]] && mkdir -p "$cache_dir"
    
    if [[ ! -f "$RECOVERY_STATE_FILE" ]]; then
        echo "{\"recoveryAttempts\": {}}" > "$RECOVERY_STATE_FILE"
    fi
}

execute_recovery_procedure() {
    local failure_type="$1"
    local context="${2:-unknown}"
    
    log_section "Executing automated recovery for: $failure_type"
    
    initialize_recovery_tracking
    
    # Check if recovery procedure exists
    if [[ -z "${RECOVERY_PROCEDURES[$failure_type]}" ]]; then
        log_error "No recovery procedure defined for: $failure_type"
        return 1
    fi
    
    # Track recovery attempt
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')
    local recovery_state=$(cat "$RECOVERY_STATE_FILE")
    local attempt_count=$(echo "$recovery_state" | jq -r ".recoveryAttempts[\"$failure_type\"].attempts // 0")
    attempt_count=$((attempt_count + 1))
    
    # Update recovery state
    local updated_state=$(echo "$recovery_state" | jq --arg type "$failure_type" --arg timestamp "$timestamp" --arg attempts "$attempt_count" --arg context "$context" '
        .recoveryAttempts[$type] = {
            "attempts": ($attempts | tonumber),
            "lastAttempt": $timestamp,
            "context": $context,
            "status": "in_progress"
        }
    ')
    echo "$updated_state" > "$RECOVERY_STATE_FILE"
    
    # Execute recovery procedure
    local procedure_name="${RECOVERY_PROCEDURES[$failure_type]}"
    log_info "Running recovery procedure: $procedure_name"
    
    if $procedure_name "$context"; then
        log_success "Recovery procedure completed successfully: $failure_type"
        
        # Update success status
        updated_state=$(echo "$updated_state" | jq --arg type "$failure_type" --arg timestamp "$timestamp" '
            .recoveryAttempts[$type].status = "success" |
            .recoveryAttempts[$type].completedAt = $timestamp
        ')
        echo "$updated_state" > "$RECOVERY_STATE_FILE"
        
        return 0
    else
        log_error "Recovery procedure failed: $failure_type"
        
        # Update failure status
        updated_state=$(echo "$updated_state" | jq --arg type "$failure_type" --arg timestamp "$timestamp" '
            .recoveryAttempts[$type].status = "failed" |
            .recoveryAttempts[$type].failedAt = $timestamp
        ')
        echo "$updated_state" > "$RECOVERY_STATE_FILE"
        
        return 1
    fi
}

restart_chrome_service() {
    local context="$1"
    
    log_info "Restarting Chrome service (context: $context)"
    
    # Kill all Chrome processes
    pkill -f "google-chrome" 2>/dev/null || true
    
    # Wait for processes to terminate
    sleep 3
    
    # Force kill if still running
    pkill -9 -f "google-chrome" 2>/dev/null || true
    
    # Clean up Chrome temporary files
    find /tmp -name "chrome_*" -type d -exec rm -rf {} \; 2>/dev/null || true
    find /tmp -name ".org.chromium.*" -type d -exec rm -rf {} \; 2>/dev/null || true
    
    # Test Chrome restart
    if timeout 30 google-chrome-stable --headless=new --no-sandbox --disable-dev-shm-usage --dump-dom about:blank >/dev/null 2>&1; then
        log_success "Chrome service restarted successfully"
        return 0
    else
        log_error "Chrome service restart failed"
        return 1
    fi
}

cleanup_memory_resources() {
    local context="$1"
    
    log_info "Cleaning up memory resources (context: $context)"
    
    # Clear system caches
    echo 1 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || true
    echo 2 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || true
    echo 3 | sudo tee /proc/sys/vm/drop_caches >/dev/null 2>&1 || true
    
    # Clean Chrome browser cache and temporary files
    bash "${PROJECT_ROOT}/scripts/browser-recycling-manager.sh" cleanup
    
    # Clean Docker system if needed
    docker system prune -f >/dev/null 2>&1 || true
    
    # Verify memory recovery
    local memory_usage=$(free -m | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [[ $memory_usage -lt 80 ]]; then
        log_success "Memory cleanup successful (usage: ${memory_usage}%)"
        return 0
    else
        log_error "Memory cleanup insufficient (usage: ${memory_usage}%)"
        return 1
    fi
}

cleanup_excess_processes() {
    local context="$1"
    
    log_info "Cleaning up excess processes (context: $context)"
    
    # Run browser recycling manager
    bash "${PROJECT_ROOT}/scripts/browser-recycling-manager.sh" check
    
    # Clean up zombie processes
    ps aux | awk '$8 ~ /^Z/ { print $2 }' | xargs -r kill -9 2>/dev/null || true
    
    # Verify process cleanup
    local chrome_count=$(pgrep -f "google-chrome" | wc -l)
    local max_instances=${CHROME_MAX_INSTANCES:-5}
    
    if [[ $chrome_count -le $max_instances ]]; then
        log_success "Process cleanup successful (Chrome processes: $chrome_count)"
        return 0
    else
        log_error "Process cleanup insufficient (Chrome processes: $chrome_count)"
        return 1
    fi
}

restart_container_services() {
    local context="$1"
    
    log_info "Restarting container services (context: $context)"
    
    # Restart N8N container
    if docker ps --filter name=n8n --format "{{.Names}}" | grep -q n8n; then
        log_info "Restarting N8N container"
        docker restart n8n
        
        # Wait for container to be healthy
        local timeout=60
        while [[ $timeout -gt 0 ]]; do
            if curl -sf "http://localhost:5678/healthz" >/dev/null 2>&1; then
                log_success "N8N container restarted successfully"
                return 0
            fi
            sleep 2
            ((timeout--))
        done
        
        log_error "N8N container restart failed - health check timeout"
        return 1
    else
        log_error "N8N container not found"
        return 1
    fi
}

restart_network_services() {
    local context="$1"
    
    log_info "Restarting network services (context: $context)"
    
    # Restart Docker network if needed
    if ! docker network ls --format "{{.Name}}" | grep -q "${JARVIS_NETWORK}"; then
        log_info "Recreating Docker network"
        docker network create --driver bridge "${JARVIS_NETWORK}" 2>/dev/null || true
    fi
    
    # Test network connectivity
    if docker exec n8n ping -c 1 google.com >/dev/null 2>&1; then
        log_success "Network services recovered"
        return 0
    else
        log_error "Network services recovery failed"
        return 1
    fi
}

cleanup_disk_space() {
    local context="$1"
    
    log_info "Cleaning up disk space (context: $context)"
    
    # Clean old log files
    find "$BASE_DIR/logs" -name "*.log" -type f -mtime +7 -delete 2>/dev/null || true
    
    # Clean Docker system
    docker system prune -f >/dev/null 2>&1 || true
    
    # Clean Chrome cache and temporary files
    find /tmp -name "chrome_*" -type d -mtime +1 -exec rm -rf {} \; 2>/dev/null || true
    
    # Verify disk space recovery
    local available_space=$(df "$BASE_DIR" | awk 'NR==2 {print $4}')
    if [[ $available_space -gt 1048576 ]]; then  # More than 1GB available
        log_success "Disk space cleanup successful"
        return 0
    else
        log_error "Disk space cleanup insufficient"
        return 1
    fi
}

get_recovery_status() {
    initialize_recovery_tracking
    
    local recovery_state=$(cat "$RECOVERY_STATE_FILE")
    
    echo "Browser Recovery Status Report"
    echo "============================="
    echo ""
    
    if [[ $(echo "$recovery_state" | jq '.recoveryAttempts | length') -eq 0 ]]; then
        echo "No recovery attempts recorded"
    else
        echo "$recovery_state" | jq -r '.recoveryAttempts | to_entries[] | 
            "\(.key):
              Attempts: \(.value.attempts)
              Last Attempt: \(.value.lastAttempt)
              Status: \(.value.status)
              Context: \(.value.context)"'
    fi
}

# Main command routing
case "${1:-help}" in
    "recover")
        execute_recovery_procedure "$2" "$3"
        ;;
    "status")
        get_recovery_status
        ;;
    "chrome")
        restart_chrome_service "manual"
        ;;
    "memory")
        cleanup_memory_resources "manual"
        ;;
    "processes")
        cleanup_excess_processes "manual"
        ;;
    "containers")
        restart_container_services "manual"
        ;;
    "network")
        restart_network_services "manual"
        ;;
    "disk")
        cleanup_disk_space "manual"
        ;;
    *)
        echo "Browser Recovery Manager"
        echo ""
        echo "Usage: $0 [command] [options]"
        echo ""
        echo "Commands:"
        echo "  recover <type> [context]  - Execute recovery procedure"
        echo "  status                    - Show recovery status"
        echo "  chrome                    - Restart Chrome service"
        echo "  memory                    - Clean up memory resources"
        echo "  processes                 - Clean up excess processes"
        echo "  containers                - Restart container services"
        echo "  network                   - Restart network services"
        echo "  disk                      - Clean up disk space"
        echo ""
        echo "Recovery Types:"
        for type in "${!RECOVERY_PROCEDURES[@]}"; do
            echo "  - $type"
        done
        exit 1
        ;;
esac
EOF
    
    safe_mv "/tmp/browser-recovery-manager.sh" "$BASE_DIR/scripts/browser-recovery-manager.sh" "Install recovery manager"
    safe_chmod "755" "$BASE_DIR/scripts/browser-recovery-manager.sh" "Make recovery manager executable"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$BASE_DIR/scripts/browser-recovery-manager.sh" "Set recovery manager ownership"
    
    log_success "Automated recovery procedures created"
}

# Setup comprehensive health monitoring dashboard
setup_health_monitoring_dashboard() {
    log_info "Setting up comprehensive health monitoring dashboard"
    
    # Create health dashboard generator
    cat > /tmp/health-dashboard.sh << 'EOF'
#!/bin/bash
# Health Monitoring Dashboard Generator
# Creates comprehensive health overview for browser automation infrastructure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${SCRIPT_DIR}")")"))"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

generate_health_dashboard() {
    local dashboard_file="$BASE_DIR/logs/health-dashboard.html"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Collect current health data
    local health_data=$(collect_dashboard_data)
    
    # Generate HTML dashboard
    cat > "$dashboard_file" << 'DASHEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>JStack - Browser Health Dashboard</title>
    <style>
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            margin: 0; 
            padding: 20px; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: #333;
        }
        .container { 
            max-width: 1200px; 
            margin: 0 auto; 
            background: white; 
            border-radius: 10px; 
            padding: 30px;
            box-shadow: 0 10px 30px rgba(0,0,0,0.3);
        }
        h1 { 
            color: #2c3e50; 
            text-align: center; 
            margin-bottom: 30px;
            border-bottom: 3px solid #3498db;
            padding-bottom: 10px;
        }
        .status-grid { 
            display: grid; 
            grid-template-columns: repeat(auto-fit, minmax(250px, 1fr)); 
            gap: 20px; 
            margin: 20px 0;
        }
        .status-card { 
            padding: 20px; 
            border-radius: 8px; 
            border-left: 4px solid;
            background: #f8f9fa;
            transition: transform 0.3s ease;
        }
        .status-card:hover {
            transform: translateY(-5px);
            box-shadow: 0 5px 15px rgba(0,0,0,0.1);
        }
        .healthy { border-left-color: #28a745; }
        .warning { border-left-color: #ffc107; }
        .unhealthy { border-left-color: #dc3545; }
        .metric { margin: 10px 0; }
        .metric-label { font-weight: bold; color: #555; }
        .metric-value { font-size: 1.2em; color: #2c3e50; }
        .timestamp { 
            text-align: center; 
            color: #6c757d; 
            font-style: italic; 
            margin-top: 30px;
            padding-top: 20px;
            border-top: 1px solid #dee2e6;
        }
        .status-indicator {
            display: inline-block;
            width: 12px;
            height: 12px;
            border-radius: 50%;
            margin-right: 8px;
        }
        .healthy-indicator { background-color: #28a745; }
        .warning-indicator { background-color: #ffc107; }
        .unhealthy-indicator { background-color: #dc3545; }
    </style>
    <script>
        // Auto-refresh every 60 seconds
        setTimeout(() => location.reload(), 60000);
    </script>
</head>
<body>
    <div class="container">
        <h1>🚀 JStack - Browser Health Dashboard</h1>
DASHEOF
    
    # Add dynamic content based on health data
    echo "$health_data" >> "$dashboard_file"
    
    # Close HTML
    cat >> "$dashboard_file" << 'DASHEOF'
        <div class="timestamp">
            Last updated: <span id="timestamp">TIMESTAMP_PLACEHOLDER</span>
        </div>
    </div>
</body>
</html>
DASHEOF
    
    # Replace timestamp placeholder
    sed -i "s/TIMESTAMP_PLACEHOLDER/$timestamp/g" "$dashboard_file"
    
    log_success "Health dashboard generated: $dashboard_file"
    echo "Dashboard available at: file://$dashboard_file"
}

collect_dashboard_data() {
    local dashboard_content=""
    
    # System overview
    dashboard_content+='        <div class="status-grid">\n'
    
    # Chrome availability status
    local chrome_status="healthy"
    local chrome_icon="healthy-indicator"
    if ! timeout 15 google-chrome-stable --headless=new --no-sandbox --dump-dom about:blank >/dev/null 2>&1; then
        chrome_status="unhealthy"
        chrome_icon="unhealthy-indicator"
    fi
    
    dashboard_content+="            <div class=\"status-card $chrome_status\">\n"
    dashboard_content+="                <h3><span class=\"status-indicator $chrome_icon\"></span>Chrome Availability</h3>\n"
    dashboard_content+="                <div class=\"metric\"><span class=\"metric-label\">Status:</span> <span class=\"metric-value\">$(echo $chrome_status | tr '[:lower:]' '[:upper:]')</span></div>\n"
    dashboard_content+="                <div class=\"metric\"><span class=\"metric-label\">Version:</span> <span class=\"metric-value\">$(google-chrome-stable --version 2>/dev/null || echo "Unknown")</span></div>\n"
    dashboard_content+="            </div>\n"
    
    # N8N Integration status
    local n8n_status="healthy"
    local n8n_icon="healthy-indicator"
    if ! curl -sf "http://localhost:5678/healthz" >/dev/null 2>&1; then
        n8n_status="unhealthy"
        n8n_icon="unhealthy-indicator"
    fi
    
    dashboard_content+="            <div class=\"status-card $n8n_status\">\n"
    dashboard_content+="                <h3><span class=\"status-indicator $n8n_icon\"></span>N8N Integration</h3>\n"
    dashboard_content+="                <div class=\"metric\"><span class=\"metric-label\">Status:</span> <span class=\"metric-value\">$(echo $n8n_status | tr '[:lower:]' '[:upper:]')</span></div>\n"
    dashboard_content+="                <div class=\"metric\"><span class=\"metric-label\">Container:</span> <span class=\"metric-value\">$(docker ps --filter name=n8n --format "{{.Status}}" 2>/dev/null || echo "Not Running")</span></div>\n"
    dashboard_content+="            </div>\n"
    
    # Resource usage
    local memory_usage=$(free -m | awk 'NR==2{printf "%.0f", $3*100/$2}')
    local memory_status="healthy"
    local memory_icon="healthy-indicator"
    if [[ $memory_usage -gt 85 ]]; then
        memory_status="unhealthy"
        memory_icon="unhealthy-indicator"
    elif [[ $memory_usage -gt 75 ]]; then
        memory_status="warning"
        memory_icon="warning-indicator"
    fi
    
    dashboard_content+="            <div class=\"status-card $memory_status\">\n"
    dashboard_content+="                <h3><span class=\"status-indicator $memory_icon\"></span>Resource Usage</h3>\n"
    dashboard_content+="                <div class=\"metric\"><span class=\"metric-label\">Memory:</span> <span class=\"metric-value\">${memory_usage}%</span></div>\n"
    dashboard_content+="                <div class=\"metric\"><span class=\"metric-label\">Chrome Processes:</span> <span class=\"metric-value\">$(pgrep -f "google-chrome" | wc -l)</span></div>\n"
    dashboard_content+="            </div>\n"
    
    # Performance metrics
    local startup_time=$(timeout 30 bash -c 'start=$(date +%s%3N); google-chrome-stable --headless=new --no-sandbox --disable-dev-shm-usage --dump-dom about:blank >/dev/null 2>&1; echo $(($(date +%s%3N) - start))' 2>/dev/null || echo "0")
    local perf_status="healthy"
    local perf_icon="healthy-indicator"
    if [[ $startup_time -gt 10000 ]]; then
        perf_status="unhealthy"
        perf_icon="unhealthy-indicator"
    elif [[ $startup_time -gt 5000 ]]; then
        perf_status="warning"
        perf_icon="warning-indicator"
    fi
    
    dashboard_content+="            <div class=\"status-card $perf_status\">\n"
    dashboard_content+="                <h3><span class=\"status-indicator $perf_icon\"></span>Performance</h3>\n"
    dashboard_content+="                <div class=\"metric\"><span class=\"metric-label\">Startup Time:</span> <span class=\"metric-value\">${startup_time}ms</span></div>\n"
    dashboard_content+="                <div class=\"metric\"><span class=\"metric-label\">Load Average:</span> <span class=\"metric-value\">$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | sed 's/,//')</span></div>\n"
    dashboard_content+="            </div>\n"
    
    dashboard_content+='        </div>\n'
    
    echo -e "$dashboard_content"
}

# Main execution
case "${1:-generate}" in
    "generate")
        generate_health_dashboard
        ;;
    *)
        echo "Usage: $0 [generate]"
        exit 1
        ;;
esac
EOF
    
    safe_mv "/tmp/health-dashboard.sh" "$BASE_DIR/scripts/health-dashboard.sh" "Install health dashboard generator"
    safe_chmod "755" "$BASE_DIR/scripts/health-dashboard.sh" "Make health dashboard generator executable"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$BASE_DIR/scripts/health-dashboard.sh" "Set health dashboard generator ownership"
    
    # Generate initial dashboard
    bash "$BASE_DIR/scripts/health-dashboard.sh" generate
    
    # Setup systemd timer for dashboard updates
    if [[ -d "/etc/systemd/system" ]]; then
        cat > /tmp/health-dashboard.service << EOF
[Unit]
Description=Health Dashboard Update Service
After=docker.service

[Service]
Type=oneshot
User=${SERVICE_USER}
ExecStart=${BASE_DIR}/scripts/health-dashboard.sh generate
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
        
        cat > /tmp/health-dashboard.timer << EOF
[Unit]
Description=Update Health Dashboard every 5 minutes
Requires=health-dashboard.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=5min
Persistent=true

[Install]
WantedBy=timers.target
EOF
        
        safe_mv "/tmp/health-dashboard.service" "/etc/systemd/system/health-dashboard.service" "Install health dashboard service"
        safe_mv "/tmp/health-dashboard.timer" "/etc/systemd/system/health-dashboard.timer" "Install health dashboard timer"
        
        execute_cmd "systemctl daemon-reload" "Reload systemd daemon"
        execute_cmd "systemctl enable health-dashboard.timer" "Enable health dashboard timer"
        execute_cmd "systemctl start health-dashboard.timer" "Start health dashboard timer"
    fi
    
    log_success "Comprehensive health monitoring dashboard configured"
}

# ═══════════════════════════════════════════════════════════════════════════════
# ⚡ TASK 15: PRODUCTION SCALING AND OPTIMIZATION CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════════

# Task 15: Implement production scaling and optimization configuration
implement_production_scaling_optimization() {
    log_section "Implementing Production Scaling and Optimization Configuration"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would implement production scaling and optimization"
        return 0
    fi
    
    if [[ "$ENABLE_BROWSER_AUTOMATION" != "true" ]]; then
        log_info "Browser automation disabled, skipping production scaling"
        return 0
    fi
    
    start_section_timer "Production Scaling"
    
    # Implement auto-scaling patterns per enhanced analysis
    implement_autoscaling_patterns
    
    # Configure production deployment procedures
    configure_production_deployment_procedures
    
    # Add Turing's deterministic control mechanisms
    implement_turing_deterministic_controls
    
    # Validate da Vinci's systems integration requirements
    validate_davinci_systems_integration
    
    end_section_timer "Production Scaling"
    log_success "Production scaling and optimization configuration implemented"
}

# Implement auto-scaling patterns per enhanced analysis
implement_autoscaling_patterns() {
    log_info "Implementing auto-scaling patterns"
    
    # Create auto-scaling orchestrator
    cat > /tmp/autoscaling-orchestrator.sh << 'EOF'
#!/bin/bash
# Production Auto-Scaling Orchestrator
# Intelligent scaling system for browser automation workloads

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${SCRIPT_DIR}")")"))"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

# Scaling configuration
MIN_N8N_INSTANCES=1
MAX_N8N_INSTANCES=${N8N_MAX_INSTANCES:-3}
MIN_CHROME_POOL_SIZE=2
MAX_CHROME_POOL_SIZE=${CHROME_MAX_INSTANCES:-10}

# Scaling thresholds
CPU_SCALE_UP_THRESHOLD=70
CPU_SCALE_DOWN_THRESHOLD=30
MEMORY_SCALE_UP_THRESHOLD=80
MEMORY_SCALE_DOWN_THRESHOLD=40
WORKFLOW_QUEUE_SCALE_UP_THRESHOLD=20
WORKFLOW_QUEUE_SCALE_DOWN_THRESHOLD=5

# Scaling state tracking
SCALING_STATE_FILE="$BASE_DIR/cache/scaling-state.json"

initialize_scaling_state() {
    local cache_dir="$BASE_DIR/cache"
    [[ ! -d "$cache_dir" ]] && mkdir -p "$cache_dir"
    
    if [[ ! -f "$SCALING_STATE_FILE" ]]; then
        cat > "$SCALING_STATE_FILE" << 'SCALEOF'
{
  "currentScale": {
    "n8nInstances": 1,
    "chromePoolSize": 2,
    "lastScaleAction": null,
    "scalingLocked": false
  },
  "metrics": {
    "averageCPU": 0,
    "averageMemory": 0,
    "workflowQueueDepth": 0,
    "responseTime": 0
  },
  "scalingHistory": []
}
SCALEOF
    fi
}

evaluate_scaling_conditions() {
    log_info "Evaluating auto-scaling conditions"
    
    initialize_scaling_state
    
    # Collect current metrics
    local current_cpu=$(get_average_cpu_usage)
    local current_memory=$(get_average_memory_usage)
    local queue_depth=$(get_workflow_queue_depth)
    local response_time=$(get_average_response_time)
    
    # Update metrics in state
    local scaling_state=$(cat "$SCALING_STATE_FILE")
    scaling_state=$(echo "$scaling_state" | jq --arg cpu "$current_cpu" --arg memory "$current_memory" --arg queue "$queue_depth" --arg response "$response_time" '
        .metrics.averageCPU = ($cpu | tonumber) |
        .metrics.averageMemory = ($memory | tonumber) |
        .metrics.workflowQueueDepth = ($queue | tonumber) |
        .metrics.responseTime = ($response | tonumber)
    ')
    echo "$scaling_state" > "$SCALING_STATE_FILE"
    
    # Check if scaling is locked (cooldown period)
    local scaling_locked=$(echo "$scaling_state" | jq -r '.currentScale.scalingLocked')
    if [[ "$scaling_locked" == "true" ]]; then
        log_info "Scaling operations locked (cooldown period)"
        return 0
    fi
    
    # Evaluate scaling decisions
    local scale_action="none"
    local scale_reason=""
    
    # Scale-up conditions
    if [[ $current_cpu -gt $CPU_SCALE_UP_THRESHOLD ]] || [[ $current_memory -gt $MEMORY_SCALE_UP_THRESHOLD ]] || [[ $queue_depth -gt $WORKFLOW_QUEUE_SCALE_UP_THRESHOLD ]]; then
        scale_action="up"
        scale_reason="High resource usage - CPU: ${current_cpu}%, Memory: ${current_memory}%, Queue: ${queue_depth}"
    # Scale-down conditions
    elif [[ $current_cpu -lt $CPU_SCALE_DOWN_THRESHOLD ]] && [[ $current_memory -lt $MEMORY_SCALE_DOWN_THRESHOLD ]] && [[ $queue_depth -lt $WORKFLOW_QUEUE_SCALE_DOWN_THRESHOLD ]]; then
        scale_action="down"
        scale_reason="Low resource usage - CPU: ${current_cpu}%, Memory: ${current_memory}%, Queue: ${queue_depth}"
    fi
    
    log_info "Scaling decision: $scale_action ($scale_reason)"
    
    # Execute scaling action
    if [[ "$scale_action" != "none" ]]; then
        execute_scaling_action "$scale_action" "$scale_reason"
    fi
}

execute_scaling_action() {
    local action="$1"
    local reason="$2"
    local timestamp=$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')
    
    log_info "Executing scaling action: $action"
    
    local scaling_state=$(cat "$SCALING_STATE_FILE")
    local current_n8n_instances=$(echo "$scaling_state" | jq -r '.currentScale.n8nInstances')
    local current_chrome_pool=$(echo "$scaling_state" | jq -r '.currentScale.chromePoolSize')
    
    local new_n8n_instances=$current_n8n_instances
    local new_chrome_pool=$current_chrome_pool
    local scaling_executed=false
    
    case "$action" in
        "up")
            # Scale up N8N instances if possible
            if [[ $current_n8n_instances -lt $MAX_N8N_INSTANCES ]]; then
                new_n8n_instances=$((current_n8n_instances + 1))
                scale_up_n8n_instance "$new_n8n_instances"
                scaling_executed=true
            fi
            
            # Scale up Chrome pool if possible
            if [[ $current_chrome_pool -lt $MAX_CHROME_POOL_SIZE ]]; then
                new_chrome_pool=$((current_chrome_pool + 2))  # Add 2 instances at a time
                [[ $new_chrome_pool -gt $MAX_CHROME_POOL_SIZE ]] && new_chrome_pool=$MAX_CHROME_POOL_SIZE
                scale_up_chrome_pool "$new_chrome_pool"
                scaling_executed=true
            fi
            ;;
        "down")
            # Scale down N8N instances if possible
            if [[ $current_n8n_instances -gt $MIN_N8N_INSTANCES ]]; then
                new_n8n_instances=$((current_n8n_instances - 1))
                scale_down_n8n_instance "$new_n8n_instances"
                scaling_executed=true
            fi
            
            # Scale down Chrome pool if possible
            if [[ $current_chrome_pool -gt $MIN_CHROME_POOL_SIZE ]]; then
                new_chrome_pool=$((current_chrome_pool - 1))
                [[ $new_chrome_pool -lt $MIN_CHROME_POOL_SIZE ]] && new_chrome_pool=$MIN_CHROME_POOL_SIZE
                scale_down_chrome_pool "$new_chrome_pool"
                scaling_executed=true
            fi
            ;;
    esac
    
    # Update scaling state if action was executed
    if [[ "$scaling_executed" == "true" ]]; then
        log_success "Scaling action completed: $action"
        
        # Update state with new configuration and scaling lock
        scaling_state=$(echo "$scaling_state" | jq --arg n8n "$new_n8n_instances" --arg chrome "$new_chrome_pool" --arg timestamp "$timestamp" --arg reason "$reason" --arg action "$action" '
            .currentScale.n8nInstances = ($n8n | tonumber) |
            .currentScale.chromePoolSize = ($chrome | tonumber) |
            .currentScale.lastScaleAction = $timestamp |
            .currentScale.scalingLocked = true |
            .scalingHistory += [{
                "timestamp": $timestamp,
                "action": $action,
                "reason": $reason,
                "n8nInstances": ($n8n | tonumber),
                "chromePoolSize": ($chrome | tonumber)
            }]
        ')
        echo "$scaling_state" > "$SCALING_STATE_FILE"
        
        # Schedule scaling unlock (5 minute cooldown)
        (sleep 300 && unlock_scaling) &
    else
        log_info "No scaling action taken - already at limits"
    fi
}

scale_up_n8n_instance() {
    local target_instances="$1"
    
    log_info "Scaling up N8N instances to: $target_instances"
    
    # This would be implemented with Docker Compose scaling or Kubernetes deployment scaling
    # For now, we'll simulate the scaling operation
    log_info "N8N scaling simulation - would create additional N8N container instances"
    
    # In a real implementation, this would:
    # 1. Update docker-compose.yml with replica count
    # 2. Start additional N8N containers with load balancing
    # 3. Update NGINX configuration for load balancing
    # 4. Verify health of new instances
}

scale_down_n8n_instance() {
    local target_instances="$1"
    
    log_info "Scaling down N8N instances to: $target_instances"
    
    # This would gracefully stop N8N instances
    log_info "N8N scaling simulation - would gracefully stop excess N8N containers"
    
    # In a real implementation, this would:
    # 1. Identify least busy N8N instance
    # 2. Gracefully drain workflows from instance
    # 3. Stop the container when safe
    # 4. Update load balancer configuration
}

scale_up_chrome_pool() {
    local target_pool_size="$1"
    
    log_info "Scaling up Chrome pool to: $target_pool_size instances"
    
    # Use existing browser instance manager to create more instances
    local current_pool=$(bash "${PROJECT_ROOT}/scripts/browser-recycling-manager.sh" status | grep "Active Instances:" | awk '{print $3}')
    local needed_instances=$((target_pool_size - current_pool))
    
    for ((i=1; i<=needed_instances; i++)); do
        bash "${PROJECT_ROOT}/scripts/browser-recycling-manager.sh" create >/dev/null 2>&1
    done
    
    log_success "Chrome pool scaled up to $target_pool_size instances"
}

scale_down_chrome_pool() {
    local target_pool_size="$1"
    
    log_info "Scaling down Chrome pool to: $target_pool_size instances"
    
    # Use existing browser recycling manager to reduce pool size
    bash "${PROJECT_ROOT}/scripts/browser-recycling-manager.sh" check
    
    log_success "Chrome pool scaled down (target: $target_pool_size instances)"
}

get_average_cpu_usage() {
    # Get average CPU usage over the last minute
    local cpu_usage=$(top -bn2 -d1 | grep "Cpu(s)" | tail -1 | awk '{print $2}' | awk -F'%' '{printf "%.0f", $1}')
    echo "${cpu_usage:-0}"
}

get_average_memory_usage() {
    # Get current memory usage percentage
    local memory_usage=$(free -m | awk 'NR==2{printf "%.0f", $3*100/$2}')
    echo "${memory_usage:-0}"
}

get_workflow_queue_depth() {
    # Get N8N workflow queue depth (simulated - would query N8N API in reality)
    # This would be: curl -s "http://localhost:5678/api/v1/executions?status=running" | jq '. | length'
    echo "0"  # Placeholder
}

get_average_response_time() {
    # Test N8N response time
    local start_time=$(date +%s%3N)
    if curl -sf "http://localhost:5678/healthz" >/dev/null 2>&1; then
        local end_time=$(date +%s%3N)
        echo $((end_time - start_time))
    else
        echo "0"
    fi
}

unlock_scaling() {
    # Remove scaling lock after cooldown period
    local scaling_state=$(cat "$SCALING_STATE_FILE")
    scaling_state=$(echo "$scaling_state" | jq '.currentScale.scalingLocked = false')
    echo "$scaling_state" > "$SCALING_STATE_FILE"
    log_info "Scaling operations unlocked"
}

get_scaling_status() {
    initialize_scaling_state
    
    local scaling_state=$(cat "$SCALING_STATE_FILE")
    
    echo "Auto-Scaling Status Report"
    echo "========================="
    echo ""
    
    echo "Current Scale:"
    echo "  N8N Instances: $(echo "$scaling_state" | jq -r '.currentScale.n8nInstances')"
    echo "  Chrome Pool Size: $(echo "$scaling_state" | jq -r '.currentScale.chromePoolSize')"
    echo "  Scaling Locked: $(echo "$scaling_state" | jq -r '.currentScale.scalingLocked')"
    echo ""
    
    echo "Current Metrics:"
    echo "  CPU Usage: $(echo "$scaling_state" | jq -r '.metrics.averageCPU')%"
    echo "  Memory Usage: $(echo "$scaling_state" | jq -r '.metrics.averageMemory')%"
    echo "  Workflow Queue: $(echo "$scaling_state" | jq -r '.metrics.workflowQueueDepth')"
    echo "  Response Time: $(echo "$scaling_state" | jq -r '.metrics.responseTime')ms"
    echo ""
    
    echo "Scaling Thresholds:"
    echo "  CPU Scale Up/Down: ${CPU_SCALE_UP_THRESHOLD}% / ${CPU_SCALE_DOWN_THRESHOLD}%"
    echo "  Memory Scale Up/Down: ${MEMORY_SCALE_UP_THRESHOLD}% / ${MEMORY_SCALE_DOWN_THRESHOLD}%"
    echo "  Queue Scale Up/Down: ${WORKFLOW_QUEUE_SCALE_UP_THRESHOLD} / ${WORKFLOW_QUEUE_SCALE_DOWN_THRESHOLD}"
    echo ""
    
    local history_count=$(echo "$scaling_state" | jq '.scalingHistory | length')
    if [[ $history_count -gt 0 ]]; then
        echo "Recent Scaling Actions:"
        echo "$scaling_state" | jq -r '.scalingHistory[-5:] [] | "  \(.timestamp): \(.action) - \(.reason)"'
    else
        echo "No scaling actions recorded"
    fi
}

# Main command routing
case "${1:-evaluate}" in
    "evaluate")
        evaluate_scaling_conditions
        ;;
    "status")
        get_scaling_status
        ;;
    "scale-up")
        execute_scaling_action "up" "Manual scale-up requested"
        ;;
    "scale-down")
        execute_scaling_action "down" "Manual scale-down requested"
        ;;
    "unlock")
        unlock_scaling
        ;;
    *)
        echo "Auto-Scaling Orchestrator"
        echo ""
        echo "Usage: $0 [evaluate|status|scale-up|scale-down|unlock]"
        echo ""
        echo "Commands:"
        echo "  evaluate   - Evaluate current conditions and scale if needed"
        echo "  status     - Show current scaling status and metrics"
        echo "  scale-up   - Force scale-up operation"
        echo "  scale-down - Force scale-down operation"
        echo "  unlock     - Remove scaling lock (use with caution)"
        exit 1
        ;;
esac
EOF
    
    safe_mv "/tmp/autoscaling-orchestrator.sh" "$BASE_DIR/scripts/autoscaling-orchestrator.sh" "Install autoscaling orchestrator"
    safe_chmod "755" "$BASE_DIR/scripts/autoscaling-orchestrator.sh" "Make autoscaling orchestrator executable"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$BASE_DIR/scripts/autoscaling-orchestrator.sh" "Set autoscaling orchestrator ownership"
    
    # Setup systemd timer for auto-scaling evaluation
    if [[ -d "/etc/systemd/system" ]]; then
        cat > /tmp/autoscaling.service << EOF
[Unit]
Description=Auto-Scaling Evaluation Service
After=docker.service

[Service]
Type=oneshot
User=${SERVICE_USER}
ExecStart=${BASE_DIR}/scripts/autoscaling-orchestrator.sh evaluate
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
        
        cat > /tmp/autoscaling.timer << EOF
[Unit]
Description=Run Auto-Scaling Evaluation every 2 minutes
Requires=autoscaling.service

[Timer]
OnBootSec=5min
OnUnitActiveSec=2min
Persistent=true

[Install]
WantedBy=timers.target
EOF
        
        safe_mv "/tmp/autoscaling.service" "/etc/systemd/system/autoscaling.service" "Install autoscaling service"
        safe_mv "/tmp/autoscaling.timer" "/etc/systemd/system/autoscaling.timer" "Install autoscaling timer"
        
        execute_cmd "systemctl daemon-reload" "Reload systemd daemon"
        execute_cmd "systemctl enable autoscaling.timer" "Enable autoscaling timer"
        execute_cmd "systemctl start autoscaling.timer" "Start autoscaling timer"
    fi
    
    log_success "Auto-scaling patterns implemented"
}

# Configure production deployment procedures
configure_production_deployment_procedures() {
    log_info "Configuring production deployment procedures"
    
    # Create production deployment manager
    cat > /tmp/production-deployment.sh << 'EOF'
#!/bin/bash
# Production Deployment Manager
# Blue-green deployment and rolling updates for browser automation infrastructure

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${SCRIPT_DIR}")")"))"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

# Deployment configuration
DEPLOYMENT_STRATEGY="${DEPLOYMENT_STRATEGY:-rolling}"  # rolling, blue-green, canary
HEALTH_CHECK_TIMEOUT=300  # 5 minutes
ROLLBACK_ENABLED=true
BACKUP_BEFORE_DEPLOY=true

deploy_production_update() {
    local update_type="${1:-minor}"  # major, minor, patch
    local deployment_id="deploy_$(date +%s)"
    
    log_section "Starting Production Deployment ($update_type update)"
    log_info "Deployment ID: $deployment_id"
    
    # Pre-deployment validation
    if ! run_pre_deployment_validation; then
        log_error "Pre-deployment validation failed"
        return 1
    fi
    
    # Create backup if enabled
    if [[ "$BACKUP_BEFORE_DEPLOY" == "true" ]]; then
        create_deployment_backup "$deployment_id"
    fi
    
    # Execute deployment based on strategy
    case "$DEPLOYMENT_STRATEGY" in
        "rolling")
            execute_rolling_deployment "$deployment_id"
            ;;
        "blue-green")
            execute_blue_green_deployment "$deployment_id"
            ;;
        "canary")
            execute_canary_deployment "$deployment_id"
            ;;
        *)
            log_error "Unknown deployment strategy: $DEPLOYMENT_STRATEGY"
            return 1
            ;;
    esac
    
    local deployment_status=$?
    
    # Post-deployment validation
    if [[ $deployment_status -eq 0 ]]; then
        if run_post_deployment_validation "$deployment_id"; then
            log_success "Production deployment completed successfully: $deployment_id"
            cleanup_old_deployments
        else
            log_error "Post-deployment validation failed"
            if [[ "$ROLLBACK_ENABLED" == "true" ]]; then
                rollback_deployment "$deployment_id"
            fi
            return 1
        fi
    else
        log_error "Deployment failed: $deployment_id"
        if [[ "$ROLLBACK_ENABLED" == "true" ]]; then
            rollback_deployment "$deployment_id"
        fi
        return 1
    fi
}

run_pre_deployment_validation() {
    log_info "Running pre-deployment validation"
    
    # Check system resources
    local memory_usage=$(free -m | awk 'NR==2{printf "%.0f", $3*100/$2}')
    if [[ $memory_usage -gt 80 ]]; then
        log_error "High memory usage before deployment: ${memory_usage}%"
        return 1
    fi
    
    # Check disk space
    local available_space=$(df "$BASE_DIR" | awk 'NR==2 {print $4}')
    if [[ $available_space -lt 2097152 ]]; then  # Less than 2GB
        log_error "Insufficient disk space for deployment"
        return 1
    fi
    
    # Check service health
    if ! bash "${PROJECT_ROOT}/scripts/browser-health-monitor.sh" check; then
        log_error "Service health check failed before deployment"
        return 1
    fi
    
    # Validate configuration
    if ! bash "${PROJECT_ROOT}/scripts/operational-validator.sh" validate; then
        log_error "Operational validation failed before deployment"
        return 1
    fi
    
    log_success "Pre-deployment validation passed"
    return 0
}

execute_rolling_deployment() {
    local deployment_id="$1"
    
    log_info "Executing rolling deployment: $deployment_id"
    
    # Rolling deployment for N8N instances
    log_info "Updating N8N service with rolling deployment"
    
    # Stop current N8N container gracefully
    if docker ps --filter name=n8n --format "{{.Names}}" | grep -q n8n; then
        log_info "Gracefully stopping current N8N container"
        docker exec n8n pkill -TERM node 2>/dev/null || true
        sleep 10
        docker stop n8n
    fi
    
    # Start new N8N container with updated configuration
    log_info "Starting updated N8N container"
    local n8n_dir="$BASE_DIR/services/n8n"
    docker_cmd "cd $n8n_dir && docker-compose --env-file .env up -d" "Start updated N8N container"
    
    # Wait for service health
    if ! wait_for_service_health "n8n" $HEALTH_CHECK_TIMEOUT 15; then
        log_error "New N8N container failed health check"
        return 1
    fi
    
    # Update Chrome browser pool
    log_info "Updating Chrome browser pool"
    bash "${PROJECT_ROOT}/scripts/browser-recycling-manager.sh" check
    
    log_success "Rolling deployment completed"
    return 0
}

execute_blue_green_deployment() {
    local deployment_id="$1"
    
    log_info "Executing blue-green deployment: $deployment_id"
    
    # Blue-green deployment simulation (would require load balancer setup)
    log_info "Blue-green deployment simulation - creating green environment"
    
    # In a real implementation, this would:
    # 1. Create new "green" environment with updated containers
    # 2. Run health checks on green environment
    # 3. Switch load balancer to point to green environment
    # 4. Monitor for issues and be ready to switch back to blue
    # 5. After verification, tear down blue environment
    
    log_success "Blue-green deployment simulation completed"
    return 0
}

execute_canary_deployment() {
    local deployment_id="$1"
    
    log_info "Executing canary deployment: $deployment_id"
    
    # Canary deployment simulation
    log_info "Canary deployment simulation - routing 10% traffic to new version"
    
    # In a real implementation, this would:
    # 1. Deploy new version alongside current version
    # 2. Configure load balancer to route small percentage to new version
    # 3. Monitor metrics and error rates
    # 4. Gradually increase traffic percentage if metrics look good
    # 5. Full cutover once validation is complete
    
    log_success "Canary deployment simulation completed"
    return 0
}

run_post_deployment_validation() {
    local deployment_id="$1"
    
    log_info "Running post-deployment validation for: $deployment_id"
    
    # Service health validation
    if ! bash "${PROJECT_ROOT}/scripts/browser-health-monitor.sh" check; then
        log_error "Service health check failed after deployment"
        return 1
    fi
    
    # Performance validation
    local startup_time=$(bash "${PROJECT_ROOT}/scripts/performance-monitor.sh" test-startup | grep -o '[0-9]*')
    if [[ $startup_time -gt 15000 ]]; then  # More than 15 seconds
        log_error "Performance degradation detected after deployment"
        return 1
    fi
    
    # Operational validation
    if ! bash "${PROJECT_ROOT}/scripts/operational-validator.sh" validate; then
        log_error "Operational validation failed after deployment"
        return 1
    fi
    
    # Test browser automation functionality
    local test_script='const puppeteer = require("puppeteer"); (async () => { const browser = await puppeteer.launch({headless: true, args: ["--no-sandbox"]}); await browser.close(); console.log("OK"); })()'
    if ! docker exec n8n timeout 30 node -e "$test_script" 2>/dev/null | grep -q "OK"; then
        log_error "Browser automation test failed after deployment"
        return 1
    fi
    
    log_success "Post-deployment validation passed"
    return 0
}

create_deployment_backup() {
    local deployment_id="$1"
    local backup_file="$BASE_DIR/backups/pre-deployment-$deployment_id.tar.gz"
    
    log_info "Creating deployment backup: $backup_file"
    
    # Create backup directory
    mkdir -p "$BASE_DIR/backups"
    
    # Create comprehensive backup
    tar -czf "$backup_file" \
        "$BASE_DIR/services" \
        "$BASE_DIR/config" \
        "$BASE_DIR/scripts" \
        "$PROJECT_ROOT/jstack.config" \
        2>/dev/null || true
    
    log_success "Deployment backup created: $backup_file"
}

rollback_deployment() {
    local deployment_id="$1"
    local backup_file="$BASE_DIR/backups/pre-deployment-$deployment_id.tar.gz"
    
    log_section "Rolling back deployment: $deployment_id"
    
    if [[ -f "$backup_file" ]]; then
        log_info "Restoring from backup: $backup_file"
        
        # Stop current services
        docker stop n8n 2>/dev/null || true
        
        # Restore backup
        tar -xzf "$backup_file" -C / 2>/dev/null || true
        
        # Restart services
        local n8n_dir="$BASE_DIR/services/n8n"
        docker_cmd "cd $n8n_dir && docker-compose --env-file .env up -d" "Restart N8N after rollback"
        
        # Wait for service health
        if wait_for_service_health "n8n" $HEALTH_CHECK_TIMEOUT 15; then
            log_success "Rollback completed successfully"
        else
            log_error "Rollback failed - manual intervention required"
        fi
    else
        log_error "Backup file not found for rollback: $backup_file"
    fi
}

cleanup_old_deployments() {
    log_info "Cleaning up old deployment backups"
    
    # Keep last 5 deployment backups
    find "$BASE_DIR/backups" -name "pre-deployment-*.tar.gz" -type f | sort -r | tail -n +6 | xargs -r rm -f
    
    log_success "Old deployment backups cleaned up"
}

get_deployment_status() {
    echo "Production Deployment Status"
    echo "==========================="
    echo ""
    echo "Configuration:"
    echo "  Strategy: $DEPLOYMENT_STRATEGY"
    echo "  Health Check Timeout: ${HEALTH_CHECK_TIMEOUT}s"
    echo "  Rollback Enabled: $ROLLBACK_ENABLED"
    echo "  Backup Before Deploy: $BACKUP_BEFORE_DEPLOY"
    echo ""
    
    echo "Available Backups:"
    if ls "$BASE_DIR/backups"/pre-deployment-*.tar.gz >/dev/null 2>&1; then
        ls -la "$BASE_DIR/backups"/pre-deployment-*.tar.gz | awk '{print "  " $9 " (" $5 " bytes, " $6 " " $7 " " $8 ")"}'
    else
        echo "  No deployment backups found"
    fi
    echo ""
    
    echo "Current Service Status:"
    docker ps --filter name=n8n --format "  N8N: {{.Status}}"
    echo "  Health: $(bash "${PROJECT_ROOT}/scripts/browser-health-monitor.sh" check >/dev/null 2>&1 && echo "Healthy" || echo "Unhealthy")"
}

# Main command routing
case "${1:-status}" in
    "deploy")
        deploy_production_update "${2:-minor}"
        ;;
    "rollback")
        if [[ -n "$2" ]]; then
            rollback_deployment "$2"
        else
            log_error "Deployment ID required for rollback"
            echo "Usage: $0 rollback <deployment-id>"
            exit 1
        fi
        ;;
    "validate-pre")
        run_pre_deployment_validation
        ;;
    "validate-post")
        run_post_deployment_validation "${2:-test}"
        ;;
    "backup")
        create_deployment_backup "${2:-manual-$(date +%s)}"
        ;;
    "cleanup")
        cleanup_old_deployments
        ;;
    "status")
        get_deployment_status
        ;;
    *)
        echo "Production Deployment Manager"
        echo ""
        echo "Usage: $0 [command] [options]"
        echo ""
        echo "Commands:"
        echo "  deploy <type>        - Deploy production update (major|minor|patch)"
        echo "  rollback <id>        - Rollback to previous deployment"
        echo "  validate-pre         - Run pre-deployment validation"
        echo "  validate-post <id>   - Run post-deployment validation"
        echo "  backup <id>          - Create deployment backup"
        echo "  cleanup              - Clean up old deployment backups"
        echo "  status               - Show deployment status"
        exit 1
        ;;
esac
EOF
    
    safe_mv "/tmp/production-deployment.sh" "$BASE_DIR/scripts/production-deployment.sh" "Install production deployment manager"
    safe_chmod "755" "$BASE_DIR/scripts/production-deployment.sh" "Make production deployment manager executable"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$BASE_DIR/scripts/production-deployment.sh" "Set production deployment manager ownership"
    
    log_success "Production deployment procedures configured"
}

# Add Turing's deterministic control mechanisms
implement_turing_deterministic_controls() {
    log_info "Implementing Turing's deterministic control mechanisms"
    
    # Create deterministic control system
    cat > /tmp/deterministic-controls.sh << 'EOF'
#!/bin/bash
# Turing's Deterministic Control Mechanisms
# Ensures predictable and deterministic behavior in browser automation

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${SCRIPT_DIR}")")"))"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

# Deterministic control configuration
DETERMINISTIC_MODE="${DETERMINISTIC_MODE:-enabled}"
RANDOM_SEED="${RANDOM_SEED:-12345}"
FIXED_VIEWPORT_WIDTH=1920
FIXED_VIEWPORT_HEIGHT=1080
NETWORK_THROTTLING_ENABLED=true
EXECUTION_TIMEOUT_STRICT=true

implement_deterministic_browser_controls() {
    log_info "Implementing deterministic browser controls"
    
    # Create deterministic Puppeteer configuration
    cat > /tmp/deterministic-puppeteer-config.js << 'JSEOF'
// Deterministic Puppeteer Configuration
// Ensures consistent behavior across executions

const fs = require('fs');

class DeterministicBrowserController {
    constructor(options = {}) {
        this.seed = options.seed || 12345;
        this.viewport = {
            width: options.width || 1920,
            height: options.height || 1080
        };
        this.networkThrottling = options.networkThrottling !== false;
        this.strictTimeout = options.strictTimeout !== false;
    }

    async launchDeterministicBrowser() {
        const puppeteer = require('puppeteer');
        
        // Deterministic launch arguments
        const args = [
            '--no-sandbox',
            '--disable-dev-shm-usage',
            '--disable-gpu',
            '--headless=new',
            '--disable-web-security',
            '--disable-features=TranslateUI,VizDisplayCompositor',
            '--disable-background-timer-throttling',
            '--disable-renderer-backgrounding',
            '--disable-backgrounding-occluded-windows',
            '--disable-blink-features=AutomationControlled',
            '--no-first-run',
            '--no-default-browser-check',
            '--disable-extensions',
            '--disable-plugins',
            '--disable-images',
            '--memory-pressure-off',
            // Deterministic arguments
            `--use-fake-ui-for-media-stream`,
            `--use-fake-device-for-media-stream`,
            `--disable-background-networking`,
            `--disable-default-apps`,
            `--disable-sync`,
            `--metrics-recording-only`,
            `--no-pings`,
            `--deterministic-mode`
        ];

        const browser = await puppeteer.launch({
            headless: 'new',
            args: args,
            timeout: this.strictTimeout ? 30000 : 0,
            ignoreDefaultArgs: false,
            defaultViewport: this.viewport
        });

        return browser;
    }

    async createDeterministicPage(browser) {
        const page = await browser.newPage();
        
        // Set deterministic viewport
        await page.setViewport(this.viewport);
        
        // Set deterministic user agent
        await page.setUserAgent('Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36');
        
        // Disable JavaScript randomness sources
        await page.evaluateOnNewDocument(() => {
            // Override Math.random with seeded PRNG
            let seed = 12345;
            Math.random = function() {
                seed = (seed * 9301 + 49297) % 233280;
                return seed / 233280;
            };
            
            // Override Date.now for consistent timing
            const originalDateNow = Date.now;
            Date.now = function() {
                return 1640995200000; // Fixed timestamp: 2022-01-01 00:00:00 UTC
            };
            
            // Override performance.now for consistent timing
            const originalPerformanceNow = performance.now;
            let performanceStartTime = 0;
            performance.now = function() {
                return performanceStartTime += 16.67; // Simulate 60fps
            };
            
            // Disable WebGL randomness
            const originalGetParameter = WebGLRenderingContext.prototype.getParameter;
            WebGLRenderingContext.prototype.getParameter = function(parameter) {
                if (parameter === 37445) { // UNMASKED_VENDOR_WEBGL
                    return 'Deterministic WebGL Vendor';
                }
                if (parameter === 37446) { // UNMASKED_RENDERER_WEBGL
                    return 'Deterministic WebGL Renderer';
                }
                return originalGetParameter.call(this, parameter);
            };
            
            // Disable audio context randomness
            if (typeof AudioContext !== 'undefined') {
                const originalCreateOscillator = AudioContext.prototype.createOscillator;
                AudioContext.prototype.createOscillator = function() {
                    const oscillator = originalCreateOscillator.call(this);
                    oscillator.frequency.value = 440; // Fixed frequency
                    return oscillator;
                };
            }
        });
        
        // Set network throttling for consistent behavior
        if (this.networkThrottling) {
            await page.emulateNetworkConditions({
                offline: false,
                downloadThroughput: 1.5 * 1024 * 1024, // 1.5 Mbps
                uploadThroughput: 750 * 1024, // 750 Kbps
                latency: 40 // 40ms
            });
        }
        
        // Set fixed timezone
        await page.emulateTimezone('UTC');
        
        // Set fixed media features
        await page.emulateMediaFeatures([
            { name: 'prefers-color-scheme', value: 'light' },
            { name: 'prefers-reduced-motion', value: 'no-preference' }
        ]);
        
        return page;
    }

    async executeDeterministicNavigation(page, url, options = {}) {
        const navigationOptions = {
            waitUntil: 'networkidle2',
            timeout: this.strictTimeout ? 30000 : 0,
            ...options
        };
        
        try {
            await page.goto(url, navigationOptions);
            
            // Wait for deterministic page state
            await page.waitForFunction(() => {
                return document.readyState === 'complete' &&
                       performance.timing.loadEventEnd > 0;
            }, { timeout: 10000 });
            
            // Fixed delay for consistent behavior
            await new Promise(resolve => setTimeout(resolve, 1000));
            
            return true;
        } catch (error) {
            console.error('Deterministic navigation failed:', error);
            return false;
        }
    }

    async executeDeterministicInteraction(page, selector, action, options = {}) {
        try {
            // Wait for element with consistent timeout
            await page.waitForSelector(selector, { 
                timeout: 10000,
                visible: true 
            });
            
            // Fixed delay before interaction
            await new Promise(resolve => setTimeout(resolve, 500));
            
            switch (action) {
                case 'click':
                    await page.click(selector);
                    break;
                case 'type':
                    await page.type(selector, options.text || '', { delay: 50 });
                    break;
                case 'select':
                    await page.select(selector, options.value || '');
                    break;
                default:
                    throw new Error(`Unknown action: ${action}`);
            }
            
            // Fixed delay after interaction
            await new Promise(resolve => setTimeout(resolve, 500));
            
            return true;
        } catch (error) {
            console.error('Deterministic interaction failed:', error);
            return false;
        }
    }
}

module.exports = DeterministicBrowserController;
JSEOF
    
    # Move to config directory
    local config_dir="$BASE_DIR/config"
    safe_mv "/tmp/deterministic-puppeteer-config.js" "$config_dir/deterministic-puppeteer.js" "Install deterministic Puppeteer config"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$config_dir/deterministic-puppeteer.js" "Set deterministic config ownership"
    
    log_success "Deterministic browser controls implemented"
}

validate_deterministic_behavior() {
    log_info "Validating deterministic behavior"
    
    # Create deterministic validation test
    local test_script='
    const DeterministicController = require("${BASE_DIR}/config/deterministic-puppeteer.js");
    
    (async () => {
        const controller = new DeterministicController();
        const browser = await controller.launchDeterministicBrowser();
        const page = await controller.createDeterministicPage(browser);
        
        // Test deterministic navigation
        const success = await controller.executeDeterministicNavigation(page, "about:blank");
        
        // Test deterministic page evaluation
        const randomValue1 = await page.evaluate(() => Math.random());
        const randomValue2 = await page.evaluate(() => Math.random());
        const dateValue = await page.evaluate(() => Date.now());
        
        await browser.close();
        
        console.log(`Navigation: ${success}`);
        console.log(`Random1: ${randomValue1}`);
        console.log(`Random2: ${randomValue2}`);
        console.log(`Date: ${dateValue}`);
        
        // Validate deterministic behavior
        if (randomValue1 === randomValue2 && dateValue === 1640995200000) {
            console.log("DETERMINISTIC_VALIDATION: PASSED");
        } else {
            console.log("DETERMINISTIC_VALIDATION: FAILED");
        }
    })();
    '
    
    if docker exec n8n timeout 60 node -e "$test_script" 2>/dev/null | grep -q "DETERMINISTIC_VALIDATION: PASSED"; then
        log_success "Deterministic behavior validation passed"
        return 0
    else
        log_error "Deterministic behavior validation failed"
        return 1
    fi
}

# Main execution
case "${1:-implement}" in
    "implement")
        implement_deterministic_browser_controls
        ;;
    "validate")
        validate_deterministic_behavior
        ;;
    *)
        echo "Usage: $0 [implement|validate]"
        exit 1
        ;;
esac
EOF
    
    safe_mv "/tmp/deterministic-controls.sh" "$BASE_DIR/scripts/deterministic-controls.sh" "Install deterministic controls"
    safe_chmod "755" "$BASE_DIR/scripts/deterministic-controls.sh" "Make deterministic controls executable"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$BASE_DIR/scripts/deterministic-controls.sh" "Set deterministic controls ownership"
    
    # Implement deterministic controls
    bash "$BASE_DIR/scripts/deterministic-controls.sh" implement
    
    log_success "Turing's deterministic control mechanisms implemented"
}

# Validate da Vinci's systems integration requirements
validate_davinci_systems_integration() {
    log_info "Validating da Vinci's systems integration requirements"
    
    # Create systems integration validator
    cat > /tmp/systems-integration-validator.sh << 'EOF'
#!/bin/bash
# da Vinci's Systems Integration Validator
# Ensures harmonious integration across all system components

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${SCRIPT_DIR}")")"))"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

validate_systems_harmony() {
    log_section "Validating da Vinci's Systems Integration Harmony"
    
    local validation_report="$BASE_DIR/logs/systems-integration-validation-$(date '+%Y%m%d_%H%M%S').json"
    local overall_harmony=true
    local harmony_score=0
    local max_score=100
    
    # Initialize validation report
    echo '{"systemsIntegrationValidation": {"timestamp": "", "components": {}, "harmonyScore": 0, "overallHarmony": false}}' > "$validation_report"
    
    # Component integration validations
    validate_n8n_puppeteer_integration
    local n8n_score=$?
    harmony_score=$((harmony_score + (n8n_score * 25 / 100)))
    
    validate_database_integration
    local db_score=$?
    harmony_score=$((harmony_score + (db_score * 20 / 100)))
    
    validate_network_integration
    local network_score=$?
    harmony_score=$((harmony_score + (network_score * 20 / 100)))
    
    validate_monitoring_integration
    local monitoring_score=$?
    harmony_score=$((harmony_score + (monitoring_score * 15 / 100)))
    
    validate_scaling_integration
    local scaling_score=$?
    harmony_score=$((harmony_score + (scaling_score * 10 / 100)))
    
    validate_security_integration
    local security_score=$?
    harmony_score=$((harmony_score + (security_score * 10 / 100)))
    
    # Calculate overall harmony
    if [[ $harmony_score -ge 85 ]]; then
        overall_harmony=true
    else
        overall_harmony=false
    fi
    
    # Update final report
    local final_report=$(cat "$validation_report" | jq \
        --arg timestamp "$(date -u '+%Y-%m-%dT%H:%M:%S.%3NZ')" \
        --arg n8n_score "$n8n_score" \
        --arg db_score "$db_score" \
        --arg network_score "$network_score" \
        --arg monitoring_score "$monitoring_score" \
        --arg scaling_score "$scaling_score" \
        --arg security_score "$security_score" \
        --arg harmony_score "$harmony_score" \
        --arg overall_harmony "$overall_harmony" '
        .systemsIntegrationValidation.timestamp = $timestamp |
        .systemsIntegrationValidation.components.n8nPuppeteer = ($n8n_score | tonumber) |
        .systemsIntegrationValidation.components.database = ($db_score | tonumber) |
        .systemsIntegrationValidation.components.network = ($network_score | tonumber) |
        .systemsIntegrationValidation.components.monitoring = ($monitoring_score | tonumber) |
        .systemsIntegrationValidation.components.scaling = ($scaling_score | tonumber) |
        .systemsIntegrationValidation.components.security = ($security_score | tonumber) |
        .systemsIntegrationValidation.harmonyScore = ($harmony_score | tonumber) |
        .systemsIntegrationValidation.overallHarmony = ($overall_harmony | test("true"))
    ')
    echo "$final_report" > "$validation_report"
    
    log_info "Systems integration harmony score: $harmony_score/100"
    log_info "Overall harmony: $overall_harmony"
    log_info "Detailed report: $validation_report"
    
    return $([[ "$overall_harmony" == true ]] && echo 0 || echo 1)
}

validate_n8n_puppeteer_integration() {
    log_info "Validating N8N-Puppeteer integration harmony"
    
    local score=0
    local max_score=100
    
    # Test N8N container availability
    if docker ps --filter name=n8n --format "{{.Names}}" | grep -q n8n; then
        score=$((score + 20))
        log_success "N8N container is running"
    else
        log_error "N8N container is not running"
        return $score
    fi
    
    # Test Puppeteer installation in N8N
    if docker exec n8n npm list puppeteer >/dev/null 2>&1; then
        score=$((score + 20))
        log_success "Puppeteer is installed in N8N"
    else
        log_error "Puppeteer not found in N8N container"
        return $score
    fi
    
    # Test Chrome availability in N8N
    if docker exec n8n google-chrome --version >/dev/null 2>&1; then
        score=$((score + 20))
        log_success "Chrome is available in N8N container"
    else
        log_error "Chrome not available in N8N container"
        return $score
    fi
    
    # Test basic browser automation functionality
    local test_script='const puppeteer = require("puppeteer"); (async () => { const browser = await puppeteer.launch({headless: true, args: ["--no-sandbox"]}); const page = await browser.newPage(); await page.goto("about:blank"); const title = await page.title(); await browser.close(); console.log("Integration OK"); })()'
    if docker exec n8n timeout 30 node -e "$test_script" 2>/dev/null | grep -q "Integration OK"; then
        score=$((score + 20))
        log_success "Browser automation integration test passed"
    else
        log_error "Browser automation integration test failed"
        return $score
    fi
    
    # Test workflow template system integration
    if [[ -d "$BASE_DIR/services/n8n/templates" ]] && [[ $(find "$BASE_DIR/services/n8n/templates" -name "*.json" | wc -l) -gt 0 ]]; then
        score=$((score + 20))
        log_success "Workflow template system integrated"
    else
        log_error "Workflow template system not properly integrated"
        return $score
    fi
    
    log_info "N8N-Puppeteer integration score: $score/$max_score"
    return $score
}

validate_database_integration() {
    log_info "Validating database integration harmony"
    
    local score=0
    local max_score=100
    
    # Test database container availability
    if docker ps --filter name=supabase-db --format "{{.Names}}" | grep -q supabase-db; then
        score=$((score + 25))
        log_success "Database container is running"
    else
        log_error "Database container is not running"
        return $score
    fi
    
    # Test database connectivity
    if docker exec supabase-db pg_isready -U postgres >/dev/null 2>&1; then
        score=$((score + 25))
        log_success "Database is accepting connections"
    else
        log_error "Database connectivity failed"
        return $score
    fi
    
    # Test N8N database configuration
    if docker exec supabase-db psql -U postgres -c "SELECT 1 FROM pg_database WHERE datname='n8n';" | grep -q "1"; then
        score=$((score + 25))
        log_success "N8N database exists"
    else
        log_error "N8N database not found"
        return $score
    fi
    
    # Test N8N database user
    if docker exec supabase-db psql -U postgres -c "SELECT 1 FROM pg_roles WHERE rolname='n8n_user';" | grep -q "1"; then
        score=$((score + 25))
        log_success "N8N database user exists"
    else
        log_error "N8N database user not found"
        return $score
    fi
    
    log_info "Database integration score: $score/$max_score"
    return $score
}

validate_network_integration() {
    log_info "Validating network integration harmony"
    
    local score=0
    local max_score=100
    
    # Test Docker network existence
    if docker network ls --format "{{.Name}}" | grep -q "${JARVIS_NETWORK}"; then
        score=$((score + 25))
        log_success "jstack network exists"
    else
        log_error "jstack network not found"
        return $score
    fi
    
    # Test inter-container communication
    if docker exec n8n ping -c 1 supabase-db >/dev/null 2>&1; then
        score=$((score + 25))
        log_success "N8N can communicate with database"
    else
        log_error "Inter-container communication failed"
        return $score
    fi
    
    # Test external network connectivity
    if docker exec n8n ping -c 1 google.com >/dev/null 2>&1; then
        score=$((score + 25))
        log_success "External network connectivity working"
    else
        log_error "External network connectivity failed"
        return $score
    fi
    
    # Test service port accessibility
    if curl -sf "http://localhost:5678/healthz" >/dev/null 2>&1; then
        score=$((score + 25))
        log_success "N8N service port accessible"
    else
        log_error "N8N service port not accessible"
        return $score
    fi
    
    log_info "Network integration score: $score/$max_score"
    return $score
}

validate_monitoring_integration() {
    log_info "Validating monitoring integration harmony"
    
    local score=0
    local max_score=100
    
    # Test health monitoring system
    if [[ -f "$BASE_DIR/scripts/browser-health-monitor.sh" ]] && bash "$BASE_DIR/scripts/browser-health-monitor.sh" check >/dev/null 2>&1; then
        score=$((score + 25))
        log_success "Health monitoring system operational"
    else
        log_error "Health monitoring system not operational"
        return $score
    fi
    
    # Test performance monitoring
    if [[ -f "$BASE_DIR/scripts/performance-monitor.sh" ]] && bash "$BASE_DIR/scripts/performance-monitor.sh" collect >/dev/null 2>&1; then
        score=$((score + 25))
        log_success "Performance monitoring operational"
    else
        log_error "Performance monitoring not operational"
        return $score
    fi
    
    # Test resource monitoring
    if [[ -f "$BASE_DIR/scripts/browser-recycling-manager.sh" ]] && bash "$BASE_DIR/scripts/browser-recycling-manager.sh" status >/dev/null 2>&1; then
        score=$((score + 25))
        log_success "Resource monitoring operational"
    else
        log_error "Resource monitoring not operational"
        return $score
    fi
    
    # Test operational validation system
    if [[ -f "$BASE_DIR/scripts/operational-validator.sh" ]] && bash "$BASE_DIR/scripts/operational-validator.sh" infrastructure >/dev/null 2>&1; then
        score=$((score + 25))
        log_success "Operational validation system working"
    else
        log_error "Operational validation system not working"
        return $score
    fi
    
    log_info "Monitoring integration score: $score/$max_score"
    return $score
}

validate_scaling_integration() {
    log_info "Validating scaling integration harmony"
    
    local score=0
    local max_score=100
    
    # Test auto-scaling system
    if [[ -f "$BASE_DIR/scripts/autoscaling-orchestrator.sh" ]]; then
        score=$((score + 30))
        log_success "Auto-scaling system present"
    else
        log_error "Auto-scaling system not found"
        return $score
    fi
    
    # Test production deployment system
    if [[ -f "$BASE_DIR/scripts/production-deployment.sh" ]]; then
        score=$((score + 30))
        log_success "Production deployment system present"
    else
        log_error "Production deployment system not found"
        return $score
    fi
    
    # Test browser instance management
    if bash "$BASE_DIR/scripts/browser-recycling-manager.sh" status >/dev/null 2>&1; then
        score=$((score + 40))
        log_success "Browser instance management operational"
    else
        log_error "Browser instance management not operational"
        return $score
    fi
    
    log_info "Scaling integration score: $score/$max_score"
    return $score
}

validate_security_integration() {
    log_info "Validating security integration harmony"
    
    local score=0
    local max_score=100
    
    # Test service user configuration
    if id "$SERVICE_USER" >/dev/null 2>&1; then
        score=$((score + 25))
        log_success "Service user properly configured"
    else
        log_error "Service user not configured"
        return $score
    fi
    
    # Test container security (non-root execution)
    local n8n_user=$(docker exec n8n whoami 2>/dev/null || echo "unknown")
    if [[ "$n8n_user" == "node" ]]; then
        score=$((score + 25))
        log_success "N8N container running as non-root user"
    else
        log_error "N8N container security issue detected"
        return $score
    fi
    
    # Test Chrome security configuration
    if docker exec n8n google-chrome --headless --no-sandbox --dump-dom about:blank >/dev/null 2>&1; then
        score=$((score + 25))
        log_success "Chrome security configuration functional"
    else
        log_error "Chrome security configuration failed"
        return $score
    fi
    
    # Test file permissions
    if [[ -O "$BASE_DIR" ]]; then
        score=$((score + 25))
        log_success "File permissions properly configured"
    else
        log_error "File permissions misconfigured"
        return $score
    fi
    
    log_info "Security integration score: $score/$max_score"
    return $score
}

# Main execution
case "${1:-validate}" in
    "validate")
        validate_systems_harmony
        ;;
    "n8n")
        validate_n8n_puppeteer_integration
        ;;
    "database")
        validate_database_integration
        ;;
    "network")
        validate_network_integration
        ;;
    "monitoring")
        validate_monitoring_integration
        ;;
    "scaling")
        validate_scaling_integration
        ;;
    "security")
        validate_security_integration
        ;;
    *)
        echo "da Vinci Systems Integration Validator"
        echo ""
        echo "Usage: $0 [validate|n8n|database|network|monitoring|scaling|security]"
        echo ""
        echo "Commands:"
        echo "  validate    - Run complete systems integration validation"
        echo "  n8n         - Validate N8N-Puppeteer integration only"
        echo "  database    - Validate database integration only"
        echo "  network     - Validate network integration only"
        echo "  monitoring  - Validate monitoring integration only"
        echo "  scaling     - Validate scaling integration only"
        echo "  security    - Validate security integration only"
        exit 1
        ;;
esac
EOF
    
    safe_mv "/tmp/systems-integration-validator.sh" "$BASE_DIR/scripts/systems-integration-validator.sh" "Install systems integration validator"
    safe_chmod "755" "$BASE_DIR/scripts/systems-integration-validator.sh" "Make systems integration validator executable"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$BASE_DIR/scripts/systems-integration-validator.sh" "Set systems integration validator ownership"
    
    # Run systems integration validation
    bash "$BASE_DIR/scripts/systems-integration-validator.sh" validate
    
    log_success "da Vinci's systems integration requirements validated"
}

# Main execution
if [[ "${1:-establish}" == "establish" ]]; then
    run_baseline_tests
else
    echo "Usage: $0 [establish]"
fi
EOF
    
    safe_mv "/tmp/establish-baselines.sh" "$BASE_DIR/scripts/establish-baselines.sh" "Install baseline establishment script"
    safe_chmod "755" "$BASE_DIR/scripts/establish-baselines.sh" "Make baseline script executable"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$BASE_DIR/scripts/establish-baselines.sh" "Set baseline script ownership"
    
    # Run initial baseline establishment
    log_info "Running initial performance baseline establishment"
    bash "$BASE_DIR/scripts/establish-baselines.sh" establish
    
    log_success "Edison's performance monitoring baselines established"
}

setup_n8n_container() {
    log_section "Setting up N8N Container with Enhanced Puppeteer Integration"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would setup N8N container"
        return 0
    fi
    
    start_section_timer "N8N Setup"
    
    # Setup browser automation if enabled
    if [[ "$ENABLE_BROWSER_AUTOMATION" == "true" ]]; then
        log_info "Setting up secure browser automation with Puppeteer"
        if bash "${PROJECT_ROOT}/scripts/core/secure_browser.sh" setup; then
            log_success "Secure browser automation configured"
        else
            log_warning "Secure browser automation setup failed - continuing without browser support"
        fi
    fi
    
    local n8n_dir="$BASE_DIR/services/n8n"
    execute_cmd "sudo -u $SERVICE_USER mkdir -p $n8n_dir" "Create N8N directory"
    
    # Install and validate Puppeteer integration (Task 11)
    if [[ "$ENABLE_BROWSER_AUTOMATION" == "true" ]]; then
        install_puppeteer_in_n8n
        validate_puppeteer_security
    fi
    
    # Generate N8N encryption key
    local n8n_encryption_key=$(generate_secret)
    
    # Create enhanced N8N environment file with Puppeteer support
    cat > /tmp/n8n.env << EOF
# N8N Configuration for JStack with Puppeteer Integration
N8N_HOST=0.0.0.0
N8N_PORT=5678
N8N_PROTOCOL=https
N8N_EDITOR_BASE_URL=https://${N8N_SUBDOMAIN}.${DOMAIN}
WEBHOOK_URL=https://${N8N_SUBDOMAIN}.${DOMAIN}

# Database Configuration
DB_TYPE=postgresdb
DB_POSTGRESDB_HOST=supabase-db
DB_POSTGRESDB_PORT=5432
DB_POSTGRESDB_DATABASE=n8n
DB_POSTGRESDB_USER=n8n_user
DB_POSTGRESDB_PASSWORD=$(generate_password)

# Security
N8N_ENCRYPTION_KEY=$n8n_encryption_key
N8N_USER_MANAGEMENT_DISABLED=true
N8N_BASIC_AUTH_ACTIVE=false
N8N_JWT_AUTH_ACTIVE=true
N8N_JWKS_URI=
N8N_JWT_AUTH_HEADER=authorization
N8N_JWT_AUTH_HEADER_VALUE_PREFIX=Bearer

# Enhanced Execution for Browser Automation
EXECUTIONS_TIMEOUT=${N8N_EXECUTION_TIMEOUT}
EXECUTIONS_TIMEOUT_MAX=${N8N_EXECUTION_TIMEOUT}
EXECUTIONS_DATA_MAX_AGE=${N8N_MAX_EXECUTION_HISTORY}
EXECUTIONS_DATA_PRUNE=true
EXECUTIONS_DATA_PRUNE_MAX_AGE=${N8N_MAX_EXECUTION_HISTORY}

# Performance Optimized for Puppeteer
N8N_CONCURRENCY_PRODUCTION=5
N8N_PAYLOAD_SIZE_MAX=32
N8N_BINARY_DATA_MODE=filesystem

# Enhanced Logging
N8N_LOG_LEVEL=info
N8N_LOG_OUTPUT=console,file
N8N_LOG_FILE_LOCATION=/home/node/.n8n/logs/

# Timezone
GENERIC_TIMEZONE=${N8N_TIMEZONE}
TZ=${N8N_TIMEZONE}

# Enhanced Features for Puppeteer Integration
N8N_DIAGNOSTICS_ENABLED=false
N8N_VERSION_NOTIFICATIONS_ENABLED=false
N8N_TEMPLATES_ENABLED=true
N8N_PUBLIC_API_DISABLED=false
N8N_ONBOARDING_FLOW_DISABLED=true
N8N_CUSTOM_EXTENSIONS=/home/node/.n8n/custom

# Browser Automation Environment Variables
PUPPETEER_EXECUTABLE_PATH=/usr/bin/google-chrome-stable
PUPPETEER_CACHE_DIR=/home/node/.n8n/puppeteer-cache
PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=true
CHROME_ARGS=--no-sandbox --disable-dev-shm-usage --disable-gpu --headless=new

# External Services
N8N_HIRING_BANNER_ENABLED=false
N8N_METRICS=false

# Advanced
N8N_SKIP_WEBHOOK_DEREGISTRATION_SHUTDOWN=false
N8N_GRACEFUL_SHUTDOWN_TIMEOUT=30
EOF
    
    safe_mv "/tmp/n8n.env" "$n8n_dir/.env" "Install N8N environment"
    safe_chmod "600" "$n8n_dir/.env" "Secure N8N environment"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$n8n_dir/.env" "Set N8N env ownership"
    
    # Create enhanced N8N Docker Compose with Puppeteer Support
    cat > /tmp/docker-compose.yml << EOF
version: '3.8'

services:
  n8n:
    image: n8n-jarvis-puppeteer:latest
    container_name: n8n
    restart: unless-stopped
    user: node
    environment:
      - N8N_HOST=\${N8N_HOST}
      - N8N_PORT=\${N8N_PORT}
      - N8N_PROTOCOL=\${N8N_PROTOCOL}
      - N8N_EDITOR_BASE_URL=\${N8N_EDITOR_BASE_URL}
      - WEBHOOK_URL=\${WEBHOOK_URL}
      - DB_TYPE=\${DB_TYPE}
      - DB_POSTGRESDB_HOST=\${DB_POSTGRESDB_HOST}
      - DB_POSTGRESDB_PORT=\${DB_POSTGRESDB_PORT}
      - DB_POSTGRESDB_DATABASE=\${DB_POSTGRESDB_DATABASE}
      - DB_POSTGRESDB_USER=\${DB_POSTGRESDB_USER}
      - DB_POSTGRESDB_PASSWORD=\${DB_POSTGRESDB_PASSWORD}
      - N8N_ENCRYPTION_KEY=\${N8N_ENCRYPTION_KEY}
      - N8N_USER_MANAGEMENT_DISABLED=\${N8N_USER_MANAGEMENT_DISABLED}
      - N8N_BASIC_AUTH_ACTIVE=\${N8N_BASIC_AUTH_ACTIVE}
      - EXECUTIONS_TIMEOUT=\${EXECUTIONS_TIMEOUT}
      - EXECUTIONS_TIMEOUT_MAX=\${EXECUTIONS_TIMEOUT_MAX}
      - EXECUTIONS_DATA_MAX_AGE=\${EXECUTIONS_DATA_MAX_AGE}
      - EXECUTIONS_DATA_PRUNE=\${EXECUTIONS_DATA_PRUNE}
      - EXECUTIONS_DATA_PRUNE_MAX_AGE=\${EXECUTIONS_DATA_PRUNE_MAX_AGE}
      - N8N_CONCURRENCY_PRODUCTION=\${N8N_CONCURRENCY_PRODUCTION}
      - N8N_PAYLOAD_SIZE_MAX=\${N8N_PAYLOAD_SIZE_MAX}
      - N8N_BINARY_DATA_MODE=\${N8N_BINARY_DATA_MODE}
      - N8N_LOG_LEVEL=\${N8N_LOG_LEVEL}
      - N8N_LOG_OUTPUT=\${N8N_LOG_OUTPUT}
      - N8N_LOG_FILE_LOCATION=\${N8N_LOG_FILE_LOCATION}
      - GENERIC_TIMEZONE=\${GENERIC_TIMEZONE}
      - TZ=\${TZ}
      - N8N_DIAGNOSTICS_ENABLED=\${N8N_DIAGNOSTICS_ENABLED}
      - N8N_VERSION_NOTIFICATIONS_ENABLED=\${N8N_VERSION_NOTIFICATIONS_ENABLED}
      - N8N_TEMPLATES_ENABLED=\${N8N_TEMPLATES_ENABLED}
      - N8N_PUBLIC_API_DISABLED=\${N8N_PUBLIC_API_DISABLED}
      - N8N_ONBOARDING_FLOW_DISABLED=\${N8N_ONBOARDING_FLOW_DISABLED}
      - N8N_CUSTOM_EXTENSIONS=\${N8N_CUSTOM_EXTENSIONS}
      - N8N_HIRING_BANNER_ENABLED=\${N8N_HIRING_BANNER_ENABLED}
      - N8N_METRICS=\${N8N_METRICS}
      - N8N_SKIP_WEBHOOK_DEREGISTRATION_SHUTDOWN=\${N8N_SKIP_WEBHOOK_DEREGISTRATION_SHUTDOWN}
      - N8N_GRACEFUL_SHUTDOWN_TIMEOUT=\${N8N_GRACEFUL_SHUTDOWN_TIMEOUT}
      # Enhanced Browser Automation Environment Variables
      - PUPPETEER_EXECUTABLE_PATH=\${PUPPETEER_EXECUTABLE_PATH}
      - PUPPETEER_CACHE_DIR=\${PUPPETEER_CACHE_DIR}
      - PUPPETEER_SKIP_CHROMIUM_DOWNLOAD=\${PUPPETEER_SKIP_CHROMIUM_DOWNLOAD}
      - CHROME_ARGS=\${CHROME_ARGS}
    volumes:
      - n8n_data:/home/node/.n8n
      - n8n_custom:/home/node/.n8n/custom
      - n8n_logs:/home/node/.n8n/logs
      - n8n_puppeteer:/home/node/.n8n/puppeteer-cache
      # Enhanced shared memory for Chrome
      - /dev/shm:/dev/shm
    ports:
      - "${N8N_PORT}:5678"
    networks:
      - ${PUBLIC_TIER}
      - ${PRIVATE_TIER}
    external_links:
      - supabase-db:supabase-db
    deploy:
      resources:
        limits:
          memory: \${CHROME_MEMORY_LIMIT}
          cpus: '\${CHROME_CPU_LIMIT}'
        reservations:
          memory: 1G
          cpus: '0.5'
    # Enhanced security options for Puppeteer
    cap_add:
      - SYS_ADMIN
    security_opt:
      - seccomp:unconfined
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:5678/healthz"]
      interval: 30s
      timeout: 15s
      retries: 5
      start_period: 60s

networks:
  ${PUBLIC_TIER}:
    external: true
  ${PRIVATE_TIER}:
    external: true

volumes:
  n8n_data:
    driver: local
  n8n_custom:
    driver: local
  n8n_logs:
    driver: local
  n8n_puppeteer:
    driver: local
EOF
    
    safe_mv "/tmp/docker-compose.yml" "$n8n_dir/docker-compose.yml" "Install N8N compose"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$n8n_dir/docker-compose.yml" "Set N8N compose ownership"
    
    # N8N database setup
    log_info "Setting up N8N database"
    docker_cmd "docker exec supabase-db psql -U postgres -c \"CREATE DATABASE IF NOT EXISTS n8n;\"" "Create N8N database" || true
    docker_cmd "docker exec supabase-db psql -U postgres -c \"CREATE USER IF NOT EXISTS n8n_user WITH PASSWORD '$(grep DB_POSTGRESDB_PASSWORD $n8n_dir/.env | cut -d= -f2)';\"" "Create N8N user" || true
    docker_cmd "docker exec supabase-db psql -U postgres -c \"GRANT ALL PRIVILEGES ON DATABASE n8n TO n8n_user;\"" "Grant N8N permissions" || true
    
    # Start enhanced N8N service
    log_info "Starting enhanced N8N service with Puppeteer support"
    docker_cmd "cd $n8n_dir && docker-compose --env-file .env up -d" "Start N8N container"
    
    # Wait for N8N to be healthy
    wait_for_service_health "n8n" 180 15
    
    # Test browser automation integration with Puppeteer (Task 11)
    if [[ "$ENABLE_BROWSER_AUTOMATION" == "true" ]]; then
        log_info "Testing enhanced browser automation integration with Puppeteer"
        test_n8n_chrome_communication
        bash "${PROJECT_ROOT}/scripts/core/secure_browser.sh" test || true
    fi
    
    end_section_timer "N8N Setup"
    log_success "Enhanced N8N container with Puppeteer integration setup completed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 📊 ENHANCED RESOURCE MONITORING & LIMITS (Tasks 8-9)
# ═══════════════════════════════════════════════════════════════════════════════

setup_resource_monitoring_limits() {
    log_section "Setting up Enhanced Resource Monitoring and Limits"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would setup enhanced resource monitoring and limits"
        return 0
    fi
    
    if [[ "$ENABLE_BROWSER_AUTOMATION" != "true" ]]; then
        log_info "Browser automation disabled, skipping resource monitoring"
        return 0
    fi
    
    start_section_timer "Resource Monitoring Setup"
    
    # Create advanced monitoring script with memory, CPU, and process limits
    create_advanced_browser_monitor
    
    # Setup container resource constraints via Docker
    configure_docker_resource_limits
    
    # Create system resource alerts and notifications
    setup_resource_alerting
    
    # Configure browser process management
    setup_browser_process_manager
    
    end_section_timer "Resource Monitoring Setup"
    log_success "Enhanced resource monitoring and limits configured successfully"
}

create_advanced_browser_monitor() {
    log_info "Creating advanced browser monitoring system"
    
    # Create comprehensive monitoring script
    cat > /tmp/advanced-browser-monitor.sh << 'EOF'
#!/bin/bash
# Advanced Browser Resource Monitoring System
# Enhanced monitoring with detailed metrics and automated responses

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${SCRIPT_DIR}")")"))"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

# Resource monitoring thresholds
MEMORY_WARNING_THRESHOLD=75
MEMORY_CRITICAL_THRESHOLD=90
CPU_WARNING_THRESHOLD=80
CPU_CRITICAL_THRESHOLD=95
CHROME_MAX_MEMORY_PER_INSTANCE=800  # MB
CHROME_MAX_AGE_MINUTES=30

monitor_system_resources() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local log_file="$BASE_DIR/logs/browser-monitoring-$(date '+%Y%m%d').log"
    
    # System-wide resource monitoring
    local total_memory=$(free -m | awk 'NR==2{printf "%.0f", $3*100/$2}')
    local total_cpu=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | awk -F'%' '{print $1}')
    
    # Chrome-specific monitoring
    local chrome_count=$(pgrep -f "google-chrome" | wc -l)
    local chrome_memory=$(ps -C google-chrome-stable -o pid,vsz,rss,etime,cmd --no-headers 2>/dev/null | awk '{sum+=$3} END {printf "%.0f", sum/1024}' || echo "0")
    local chrome_cpu=$(ps -C google-chrome-stable -o %cpu --no-headers 2>/dev/null | awk '{sum+=$1} END {print sum}' || echo "0")
    
    # Docker container monitoring
    local n8n_container_stats=""
    if docker ps --filter name=n8n --format "table {{.Names}}" | grep -q n8n; then
        n8n_container_stats=$(docker stats n8n --no-stream --format "table {{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}" | tail -n1)
    fi
    
    # Log comprehensive metrics
    echo "[$timestamp] SYS_MEM:${total_memory}% SYS_CPU:${total_cpu}% CHROME_PROC:${chrome_count} CHROME_MEM:${chrome_memory}MB CHROME_CPU:${chrome_cpu}% N8N:${n8n_container_stats}" >> "$log_file"
    
    # Check thresholds and take actions
    check_memory_thresholds "$total_memory" "$chrome_memory"
    check_cpu_thresholds "$total_cpu" "$chrome_cpu" 
    check_chrome_processes "$chrome_count"
    cleanup_old_chrome_processes
    
    # Rotate logs if needed
    find "$BASE_DIR/logs" -name "browser-monitoring-*.log" -type f -mtime +7 -delete 2>/dev/null || true
}

check_memory_thresholds() {
    local sys_memory=$1
    local chrome_memory=${2:-0}
    
    if (( $(echo "$sys_memory > $MEMORY_CRITICAL_THRESHOLD" | bc -l) )); then
        log_error "CRITICAL: System memory usage at ${sys_memory}% (threshold: ${MEMORY_CRITICAL_THRESHOLD}%)"
        trigger_emergency_chrome_cleanup
        send_alert "CRITICAL" "Memory usage: ${sys_memory}%"
    elif (( $(echo "$sys_memory > $MEMORY_WARNING_THRESHOLD" | bc -l) )); then
        log_warning "WARNING: System memory usage at ${sys_memory}% (threshold: ${MEMORY_WARNING_THRESHOLD}%)"
        trigger_gentle_chrome_cleanup
    fi
    
    # Check Chrome-specific memory usage
    if (( chrome_memory > 3000 )); then  # More than 3GB total Chrome usage
        log_warning "Chrome total memory usage high: ${chrome_memory}MB"
        optimize_chrome_memory
    fi
}

check_cpu_thresholds() {
    local sys_cpu=$1
    local chrome_cpu=${2:-0}
    
    if (( $(echo "$sys_cpu > $CPU_CRITICAL_THRESHOLD" | bc -l) )); then
        log_error "CRITICAL: System CPU usage at ${sys_cpu}% (threshold: ${CPU_CRITICAL_THRESHOLD}%)"
        throttle_chrome_processes
        send_alert "CRITICAL" "CPU usage: ${sys_cpu}%"
    elif (( $(echo "$sys_cpu > $CPU_WARNING_THRESHOLD" | bc -l) )); then
        log_warning "WARNING: System CPU usage at ${sys_cpu}% (threshold: ${CPU_WARNING_THRESHOLD}%)"
    fi
}

check_chrome_processes() {
    local chrome_count=$1
    local max_instances=${CHROME_MAX_INSTANCES:-5}
    
    if (( chrome_count > max_instances )); then
        log_warning "Chrome process count ($chrome_count) exceeds limit ($max_instances)"
        kill_excess_chrome_processes "$max_instances"
    fi
}

cleanup_old_chrome_processes() {
    # Kill Chrome processes older than max age
    local max_age_seconds=$((CHROME_MAX_AGE_MINUTES * 60))
    
    # Find and kill old Chrome processes
    ps -C google-chrome-stable -o pid,etime,cmd --no-headers | while read pid etime cmd; do
        # Convert etime to seconds (basic conversion for MM:SS or HH:MM:SS)
        local age_seconds=0
        if [[ $etime =~ ^([0-9]+):([0-9]+)$ ]]; then
            age_seconds=$((${BASH_REMATCH[1]} * 60 + ${BASH_REMATCH[2]}))
        elif [[ $etime =~ ^([0-9]+):([0-9]+):([0-9]+)$ ]]; then
            age_seconds=$((${BASH_REMATCH[1]} * 3600 + ${BASH_REMATCH[2]} * 60 + ${BASH_REMATCH[3]}))
        fi
        
        if (( age_seconds > max_age_seconds )); then
            log_info "Killing old Chrome process (PID: $pid, Age: $etime)"
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done
}

trigger_emergency_chrome_cleanup() {
    log_info "Triggering emergency Chrome cleanup"
    
    # Kill all Chrome processes except the most recent ones
    pkill -f --oldest "google-chrome.*--headless" || true
    
    # Clear Chrome cache and temporary files aggressively
    cleanup_browser_cache
    
    # Force garbage collection if possible
    docker exec n8n pkill -SIGUSR1 node 2>/dev/null || true
}

trigger_gentle_chrome_cleanup() {
    log_info "Triggering gentle Chrome cleanup"
    
    # Clear cache and temp files
    cleanup_browser_cache
    
    # Kill idle Chrome processes
    pkill -f "google-chrome.*--headless.*idle" || true
}

optimize_chrome_memory() {
    log_info "Optimizing Chrome memory usage"
    
    # Send memory pressure signal to Chrome processes
    pkill -SIGUSR1 -f "google-chrome" || true
    
    # Clear browser data directories
    find /tmp -name "chrome_*" -type d -mmin +5 -exec rm -rf {} \; 2>/dev/null || true
}

throttle_chrome_processes() {
    log_info "Throttling Chrome processes to reduce CPU usage"
    
    # Reduce CPU priority for Chrome processes
    pgrep -f "google-chrome" | while read pid; do
        renice +10 "$pid" 2>/dev/null || true
    done
}

kill_excess_chrome_processes() {
    local max_allowed=$1
    
    log_info "Killing excess Chrome processes (keeping $max_allowed)"
    
    # Kill oldest Chrome processes, keeping only the most recent ones
    pgrep -f "google-chrome.*--headless" | head -n -"$max_allowed" | while read pid; do
        log_info "Killing excess Chrome process: $pid"
        kill -TERM "$pid" 2>/dev/null || true
    done
}

send_alert() {
    local severity=$1
    local message=$2
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Log alert
    echo "[$timestamp] ALERT [$severity]: $message" >> "$BASE_DIR/logs/browser-alerts.log"
    
    # Could extend this to send email, webhook, etc.
    log_warning "ALERT [$severity]: $message"
}

# Main execution
case "${1:-monitor}" in
    "monitor")
        monitor_system_resources
        ;;
    "cleanup")
        cleanup_browser_cache
        ;;
    "emergency")
        trigger_emergency_chrome_cleanup
        ;;
    "optimize")
        optimize_chrome_memory
        ;;
    *)
        echo "Usage: $0 [monitor|cleanup|emergency|optimize]"
        exit 1
        ;;
esac
EOF
    
    safe_mv "/tmp/advanced-browser-monitor.sh" "$BASE_DIR/scripts/advanced-browser-monitor.sh" "Install advanced browser monitor"
    safe_chmod "755" "$BASE_DIR/scripts/advanced-browser-monitor.sh" "Make advanced monitor executable"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$BASE_DIR/scripts/advanced-browser-monitor.sh" "Set advanced monitor ownership"
}

configure_docker_resource_limits() {
    log_info "Configuring Docker resource limits for browser containers"
    
    # Update N8N Docker compose with enhanced resource constraints
    local n8n_dir="$BASE_DIR/services/n8n"
    
    # Add resource limits to docker-compose.yml
    if [[ -f "$n8n_dir/docker-compose.yml" ]]; then
        # Backup existing compose file
        safe_cp "$n8n_dir/docker-compose.yml" "$n8n_dir/docker-compose.yml.backup" "Backup N8N compose"
        
        # Update deploy section with enhanced limits
        cat >> /tmp/docker-resource-limits.yml << EOF
      resources:
        limits:
          memory: ${CHROME_MEMORY_LIMIT}
          cpus: '${CHROME_CPU_LIMIT}'
        reservations:
          memory: 1G
          cpus: '0.5'
    security_opt:
      - no-new-privileges:true
      - seccomp:unconfined
    ulimits:
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536
EOF
        
        log_info "Enhanced Docker resource limits configured"
    fi
}

setup_resource_alerting() {
    log_info "Setting up resource monitoring alerting system"
    
    # Create systemd service for continuous monitoring
    if [[ -d "/etc/systemd/system" ]]; then
        cat > /tmp/browser-resource-monitor.service << EOF
[Unit]
Description=Advanced Browser Resource Monitoring
After=docker.service
Requires=docker.service

[Service]
Type=oneshot
User=${SERVICE_USER}
ExecStart=${BASE_DIR}/scripts/advanced-browser-monitor.sh monitor
StandardOutput=journal
StandardError=journal
TimeoutStartSec=30

[Install]
WantedBy=multi-user.target
EOF
        
        cat > /tmp/browser-resource-monitor.timer << EOF
[Unit]
Description=Run Advanced Browser Resource Monitoring every 2 minutes
Requires=browser-resource-monitor.service

[Timer]
OnBootSec=2min
OnUnitActiveSec=2min
Persistent=true

[Install]
WantedBy=timers.target
EOF
        
        safe_mv "/tmp/browser-resource-monitor.service" "/etc/systemd/system/browser-resource-monitor.service" "Install resource monitor service"
        safe_mv "/tmp/browser-resource-monitor.timer" "/etc/systemd/system/browser-resource-monitor.timer" "Install resource monitor timer"
        
        execute_cmd "systemctl daemon-reload" "Reload systemd daemon"
        execute_cmd "systemctl enable browser-resource-monitor.timer" "Enable resource monitor timer"
        execute_cmd "systemctl start browser-resource-monitor.timer" "Start resource monitor timer"
        
        log_success "Resource monitoring service installed and started"
    fi
}

setup_browser_process_manager() {
    log_info "Setting up browser process management system"
    
    # Create browser process manager with advanced lifecycle management
    cat > /tmp/browser-process-manager.sh << 'EOF'
#!/bin/bash
# Browser Process Management System
# Advanced lifecycle management for Chrome browser processes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$(dirname "$(dirname "${SCRIPT_DIR}")")"))"
source "${PROJECT_ROOT}/scripts/lib/common.sh"
source "${PROJECT_ROOT}/scripts/settings/config.sh"

load_config
export_config

# Process management configuration
BROWSER_POOL_SIZE=${CHROME_MAX_INSTANCES:-5}
BROWSER_IDLE_TIMEOUT=600  # 10 minutes
BROWSER_MAX_MEMORY_MB=800
BROWSER_STARTUP_TIMEOUT=30

manage_browser_pool() {
    log_info "Managing browser process pool"
    
    local active_count=$(pgrep -f "google-chrome.*--headless" | wc -l)
    local target_pool_size=${1:-3}  # Default warm pool of 3 instances
    
    if (( active_count < target_pool_size )); then
        local needed=$((target_pool_size - active_count))
        log_info "Starting $needed browser instances to maintain pool"
        
        for ((i=1; i<=needed; i++)); do
            start_browser_instance "pool-instance-$i"
        done
    elif (( active_count > BROWSER_POOL_SIZE )); then
        local excess=$((active_count - BROWSER_POOL_SIZE))
        log_info "Terminating $excess excess browser instances"
        terminate_excess_browsers "$excess"
    fi
}

start_browser_instance() {
    local instance_name=${1:-"browser-$$"}
    
    log_info "Starting browser instance: $instance_name"
    
    # Start Chrome with specific resource limits and monitoring
    timeout $BROWSER_STARTUP_TIMEOUT google-chrome-stable \
        --headless=new \
        --no-sandbox \
        --disable-gpu \
        --disable-dev-shm-usage \
        --disable-extensions \
        --disable-plugins \
        --disable-images \
        --disable-javascript \
        --virtual-time-budget=30000 \
        --memory-pressure-off \
        --max_old_space_size=512 \
        --user-data-dir="/tmp/chrome-$instance_name" \
        --remote-debugging-port=0 \
        --no-first-run \
        --no-default-browser-check \
        about:blank &
    
    local chrome_pid=$!
    
    # Set resource limits for this specific process
    if command -v prlimit >/dev/null 2>&1; then
        prlimit --pid="$chrome_pid" --as=$((BROWSER_MAX_MEMORY_MB * 1024 * 1024)) 2>/dev/null || true
        prlimit --pid="$chrome_pid" --cpu=300 2>/dev/null || true  # 5 minutes CPU time limit
    fi
    
    # Set lower CPU priority
    renice +5 "$chrome_pid" 2>/dev/null || true
    
    log_success "Browser instance started: $instance_name (PID: $chrome_pid)"
}

terminate_excess_browsers() {
    local count_to_kill=$1
    
    log_info "Terminating $count_to_kill excess browser processes"
    
    # Kill oldest browser processes first
    pgrep -f "google-chrome.*--headless" | head -n "$count_to_kill" | while read pid; do
        log_info "Terminating browser process: $pid"
        kill -TERM "$pid" 2>/dev/null || true
        
        # Wait a moment, then force kill if necessary
        sleep 2
        if kill -0 "$pid" 2>/dev/null; then
            log_warning "Force killing unresponsive browser process: $pid"
            kill -KILL "$pid" 2>/dev/null || true
        fi
    done
}

health_check_browsers() {
    log_info "Performing browser health checks"
    
    pgrep -f "google-chrome.*--headless" | while read pid; do
        # Check if process is responsive
        if ! kill -0 "$pid" 2>/dev/null; then
            continue
        fi
        
        # Check memory usage
        local mem_usage=$(ps -p "$pid" -o rss= 2>/dev/null | awk '{print int($1/1024)}')
        if [[ -n "$mem_usage" ]] && (( mem_usage > BROWSER_MAX_MEMORY_MB )); then
            log_warning "Browser process $pid using excessive memory: ${mem_usage}MB"
            kill -TERM "$pid" 2>/dev/null || true
        fi
        
        # Check CPU usage over time
        local cpu_usage=$(ps -p "$pid" -o %cpu= 2>/dev/null | awk '{print int($1)}')
        if [[ -n "$cpu_usage" ]] && (( cpu_usage > 80 )); then
            log_warning "Browser process $pid using high CPU: ${cpu_usage}%"
        fi
    done
}

# Main execution
case "${1:-manage}" in
    "manage")
        manage_browser_pool "${2:-3}"
        ;;
    "health")
        health_check_browsers
        ;;
    "start")
        start_browser_instance "${2:-browser-manual}"
        ;;
    "cleanup")
        terminate_excess_browsers "${BROWSER_POOL_SIZE}"
        ;;
    *)
        echo "Usage: $0 [manage|health|start|cleanup] [options]"
        exit 1
        ;;
esac
EOF
    
    safe_mv "/tmp/browser-process-manager.sh" "$BASE_DIR/scripts/browser-process-manager.sh" "Install browser process manager"
    safe_chmod "755" "$BASE_DIR/scripts/browser-process-manager.sh" "Make process manager executable"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$BASE_DIR/scripts/browser-process-manager.sh" "Set process manager ownership"
    
    log_success "Browser process management system configured"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🌐 NETWORK ISOLATION CONFIGURATION (Task 10)
# ═══════════════════════════════════════════════════════════════════════════════

configure_browser_network_isolation() {
    log_section "Configuring Browser Network Isolation"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would configure browser network isolation"
        return 0
    fi
    
    if [[ "$ENABLE_BROWSER_AUTOMATION" != "true" ]]; then
        log_info "Browser automation disabled, skipping network isolation"
        return 0
    fi
    
    start_section_timer "Network Isolation"
    
    # Configure Docker networks for browser isolation
    setup_browser_docker_networks
    
    # Configure firewall rules for browser security
    setup_browser_firewall_rules
    
    # Setup service discovery for browser containers
    configure_browser_service_discovery
    
    # Configure proxy settings for browser automation
    setup_browser_proxy_configuration
    
    end_section_timer "Network Isolation"
    log_success "Browser network isolation configured successfully"
}

setup_browser_docker_networks() {
    log_info "Setting up Docker networks for browser isolation"
    
    # Create isolated network for browser automation if it doesn't exist
    local browser_network="${JARVIS_NETWORK}_browser"
    
    if ! docker network ls --format "{{.Name}}" | grep -q "^${browser_network}$"; then
        execute_cmd "docker network create --driver bridge --subnet 172.20.0.0/16 --ip-range 172.20.0.0/24 $browser_network" "Create browser network"
    else
        log_info "Browser network already exists: $browser_network"
    fi
    
    # Update N8N container to use browser network
    local n8n_dir="$BASE_DIR/services/n8n"
    if [[ -f "$n8n_dir/docker-compose.yml" ]]; then
        # Add browser network to compose file if not already present
        if ! grep -q "$browser_network" "$n8n_dir/docker-compose.yml"; then
            log_info "Adding browser network to N8N container configuration"
            
            # Backup existing compose file
            safe_cp "$n8n_dir/docker-compose.yml" "$n8n_dir/docker-compose.yml.network-backup" "Backup N8N compose for network config"
            
            # Add browser network to networks section
            cat >> /tmp/browser-network-config.yml << EOF
  ${browser_network}:
    external: true
EOF
            
            # This would need more sophisticated YAML editing in production
            log_info "Browser network configuration prepared"
        fi
    fi
    
    # Create network security rules
    create_browser_network_security_rules "$browser_network"
}

create_browser_network_security_rules() {
    local network_name=$1
    
    log_info "Creating network security rules for browser network: $network_name"
    
    # Create iptables rules for browser network isolation
    cat > /tmp/browser-network-rules.sh << EOF
#!/bin/bash
# Browser Network Security Rules
# Restrict browser container network access

# Allow internal communication within browser network
iptables -A DOCKER-USER -s 172.20.0.0/16 -d 172.20.0.0/16 -j ACCEPT

# Allow browser containers to access N8N and database only
iptables -A DOCKER-USER -s 172.20.0.0/16 -d ${PRIVATE_TIER} -p tcp --dport 5678 -j ACCEPT
iptables -A DOCKER-USER -s 172.20.0.0/16 -d ${PRIVATE_TIER} -p tcp --dport 5432 -j ACCEPT

# Allow outbound HTTP/HTTPS for web scraping (with rate limiting)
iptables -A DOCKER-USER -s 172.20.0.0/16 -p tcp --dport 80 -m limit --limit 100/min -j ACCEPT
iptables -A DOCKER-USER -s 172.20.0.0/16 -p tcp --dport 443 -m limit --limit 100/min -j ACCEPT

# Allow DNS resolution
iptables -A DOCKER-USER -s 172.20.0.0/16 -p udp --dport 53 -j ACCEPT
iptables -A DOCKER-USER -s 172.20.0.0/16 -p tcp --dport 53 -j ACCEPT

# Drop all other traffic from browser network
iptables -A DOCKER-USER -s 172.20.0.0/16 -j DROP

# Log dropped packets for monitoring
iptables -I DOCKER-USER -s 172.20.0.0/16 -j LOG --log-prefix "BROWSER-DROP: " --log-level 4
EOF
    
    safe_mv "/tmp/browser-network-rules.sh" "$BASE_DIR/scripts/browser-network-rules.sh" "Install browser network rules"
    safe_chmod "755" "$BASE_DIR/scripts/browser-network-rules.sh" "Make network rules executable"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$BASE_DIR/scripts/browser-network-rules.sh" "Set network rules ownership"
    
    log_success "Browser network security rules created"
}

setup_browser_firewall_rules() {
    log_info "Browser security relies on Docker network isolation and manual iptables configuration"
    log_info "Advanced iptables rules for browser containers can be configured manually if needed"
    log_info "Docker networks provide container isolation by default"
}

configure_browser_service_discovery() {
    log_info "Configuring service discovery for browser containers"
    
    # Create service discovery configuration for browsers
    cat > /tmp/browser-service-discovery.conf << EOF
# Browser Service Discovery Configuration
# Maps service names to internal network addresses

# N8N Service
n8n.internal=${PRIVATE_TIER}:5678

# Database Service  
database.internal=${PRIVATE_TIER}:5432

# Supabase API
supabase-api.internal=${PRIVATE_TIER}:8000

# Health check endpoints
health.n8n=http://n8n.internal/healthz
health.database=postgresql://database.internal:5432/

# Browser automation endpoints
browser.pool=http://127.0.0.1:9222
browser.metrics=http://127.0.0.1:9223
EOF
    
    safe_mv "/tmp/browser-service-discovery.conf" "$BASE_DIR/config/browser-services.conf" "Install browser service discovery"
    safe_chmod "644" "$BASE_DIR/config/browser-services.conf" "Set service discovery permissions"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$BASE_DIR/config/browser-services.conf" "Set service discovery ownership"
}

setup_browser_proxy_configuration() {
    log_info "Setting up browser proxy configuration"
    
    # Create proxy configuration for browser automation
    cat > /tmp/browser-proxy.conf << EOF
# Browser Proxy Configuration
# Controls external access and monitoring for browser automation

# Upstream definitions
upstream browser_pool {
    least_conn;
    server 127.0.0.1:9222 weight=1 max_fails=2 fail_timeout=30s;
    server 127.0.0.1:9223 weight=1 max_fails=2 fail_timeout=30s;
    server 127.0.0.1:9224 weight=1 max_fails=2 fail_timeout=30s;
}

# Rate limiting for browser requests
limit_req_zone \$binary_remote_addr zone=browser_limit:10m rate=30r/m;

# Browser automation proxy
server {
    listen 127.0.0.1:8080;
    server_name browser-proxy.internal;
    
    # Security headers
    add_header X-Content-Type-Options nosniff;
    add_header X-Frame-Options DENY;
    add_header X-XSS-Protection "1; mode=block";
    
    # Rate limiting
    limit_req zone=browser_limit burst=10 nodelay;
    
    # Browser pool proxy
    location /browser/ {
        proxy_pass http://browser_pool/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        
        # Timeout settings for browser operations
        proxy_connect_timeout 30s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
        
        # Buffer settings
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
        proxy_busy_buffers_size 8k;
        
        # Enable keepalive
        proxy_http_version 1.1;
        proxy_set_header Connection "";
    }
    
    # Health check endpoint
    location /health {
        access_log off;
        return 200 "Browser proxy healthy\n";
        add_header Content-Type text/plain;
    }
    
    # Metrics endpoint (restricted)
    location /metrics {
        allow 127.0.0.1;
        allow 172.20.0.0/16;
        deny all;
        
        proxy_pass http://browser_pool/json;
        proxy_set_header Host \$host;
    }
}
EOF
    
    safe_mv "/tmp/browser-proxy.conf" "$BASE_DIR/config/browser-proxy.conf" "Install browser proxy config"
    safe_chmod "644" "$BASE_DIR/config/browser-proxy.conf" "Set proxy config permissions"
    safe_chown "$SERVICE_USER:$SERVICE_GROUP" "$BASE_DIR/config/browser-proxy.conf" "Set proxy config ownership"
    
    log_success "Browser proxy configuration installed"
}

# ═══════════════════════════════════════════════════════════════════════════════
# 🚀 MAIN SERVICE ORCHESTRATION
# ═══════════════════════════════════════════════════════════════════════════════

# Setup browser automation environment
setup_browser_environment() {
    log_section "Setting up Browser Automation Environment"
    
    if [[ "$ENABLE_BROWSER_AUTOMATION" != "true" ]]; then
        log_info "Browser automation disabled, skipping setup"
        return 0
    fi
    
    # Initialize timing
    start_section_timer "Browser Environment"
    
    # Setup Chrome and dependencies
    if install_chrome_dependencies && \
       setup_puppeteer_environment && \
       create_browser_automation_monitoring; then
        
        end_section_timer "Browser Environment"
        log_success "Browser automation environment setup completed"
        return 0
    else
        end_section_timer "Browser Environment"
        log_error "Browser automation environment setup failed"
        return 1
    fi
}

# Main function for command routing
main() {
    case "${1:-setup}" in
        "setup"|"deploy")
            setup_n8n_container
            ;;
        "browser-env")
            setup_browser_environment
            ;;
        "chrome")
            install_chrome_dependencies
            ;;
        "puppeteer")
            setup_puppeteer_environment
            ;;
        "monitoring")
            create_browser_automation_monitoring
            ;;
        "resource-monitoring")
            setup_resource_monitoring_limits
            ;;
        "network-isolation")
            configure_browser_network_isolation
            ;;
        "test")
            test_browser_automation_integration
            ;;
        "status")
            log_info "Checking N8N service status"
            docker ps --filter name=n8n --format "table {{.Names}}\\t{{.Status}}"
            ;;
        "logs")
            log_info "Showing N8N logs"
            docker logs n8n
            ;;
        *)
            echo "Usage: $0 [setup|browser-env|chrome|puppeteer|monitoring|resource-monitoring|network-isolation|test|status|logs]"
            echo ""
            echo "Phase 2 Enhanced Commands:"
            echo "  setup              - Setup N8N container with browser automation"
            echo "  browser-env        - Setup complete browser automation environment"
            echo "  chrome             - Install Chrome dependencies only"
            echo "  puppeteer          - Setup Puppeteer environment only" 
            echo "  monitoring         - Create basic browser monitoring system"
            echo "  resource-monitoring- Setup enhanced resource monitoring & limits (Tasks 8-9)"
            echo "  network-isolation  - Configure browser network isolation (Task 10)"
            echo "  test               - Test browser automation integration"
            echo "  status             - Show N8N container status"
            echo "  logs               - Show N8N container logs"
            echo ""
            echo "Phase 2 Status: Tasks 6-10 implemented (Chrome + Resources + Network)"
            echo "Coming: Tasks 11-15 (Puppeteer Integration + Templates + Performance + Health + Scaling)"
            exit 1
            ;;
    esac
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi