# Direct Recommendations to Solidify jstack Installation Script

## Context
The jstack repository needs its installation script to handle all edge cases automatically, including the duplicate mount points issue. These recommendations will make `./jstack.sh --install` work reliably without manual intervention.

## Critical Issues to Fix in the Script

### 1. Duplicate Mount Points Prevention
The script is creating two volumes mounting to the same path. This needs to be fixed in the source.

**Location to Check:**
- `scripts/core/docker-compose-generator.sh` (if exists)
- `docker-compose.yml` template
- Any function in `jstack.sh` that modifies docker-compose

**Recommended Fix:**
```bash
# In the script where docker-compose.yml is generated/modified
# Add a deduplication check:

deduplicate_nginx_volumes() {
    local compose_file="${1:-docker-compose.yml}"
    
    # Extract nginx volumes section and remove duplicates
    # Keep only sites/default/html mount, remove site-templates mount
    sed -i.tmp '
    /nginx:/,/^[^ ]/ {
        /site-templates:\/usr\/share\/nginx\/html/d
    }
    ' "$compose_file"
    
    # Clean up temp file
    rm -f "${compose_file}.tmp"
}

# Call this function after docker-compose.yml generation
deduplicate_nginx_volumes
```

### 2. Pre-Installation Validation Function
Add this to the beginning of the install process:

```bash
pre_install_validation() {
    local errors=0
    
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Running pre-installation validation..."
    
    # Check Docker and Docker Compose
    if ! command -v docker &> /dev/null; then
        echo "❌ Docker is not installed"
        ((errors++))
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        echo "❌ Docker Compose is not installed"
        ((errors++))
    fi
    
    # Validate docker-compose.yml before using it
    if [ -f docker-compose.yml ]; then
        # Check for duplicate mounts
        local nginx_mounts=$(grep -A 20 "nginx:" docker-compose.yml | grep -c "/usr/share/nginx/html")
        if [ "$nginx_mounts" -gt 1 ]; then
            echo "⚠️  Detected duplicate nginx mounts, auto-fixing..."
            deduplicate_nginx_volumes
        fi
        
        # Validate syntax
        if ! docker-compose config > /dev/null 2>&1; then
            echo "❌ docker-compose.yml has syntax errors"
            ((errors++))
        fi
    fi
    
    # Check required directories
    local required_dirs=(
        "sites/default/html"
        "nginx/conf.d"
        "certbot/conf"
        "certbot/www"
        "data"
    )
    
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            echo "📁 Creating missing directory: $dir"
            mkdir -p "$dir"
        fi
    done
    
    # Check port availability
    for port in 80 443; do
        if lsof -Pi :$port -sTCP:LISTEN -t >/dev/null 2>&1; then
            echo "❌ Port $port is already in use"
            ((errors++))
        fi
    done
    
    if [ $errors -gt 0 ]; then
        echo "❌ Pre-installation validation failed with $errors errors"
        return 1
    fi
    
    echo "✅ Pre-installation validation passed"
    return 0
}
```

### 3. Docker Compose Generation Fix
If the script generates docker-compose.yml dynamically, fix the generation logic:

```bash
generate_nginx_service() {
    cat >> docker-compose.yml << EOF
  nginx:
    image: nginx:latest
    container_name: jstack_nginx_1
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
    volumes:
      # Only one mount to /usr/share/nginx/html
      - ./sites/default/html:/usr/share/nginx/html:ro
      - ./nginx/conf.d:/etc/nginx/conf.d:ro
      - ./nginx/nginx.conf:/etc/nginx/nginx.conf:ro
      - ./certbot/conf:/etc/letsencrypt:ro
      - ./certbot/www:/var/www/certbot:ro
    depends_on:
      - n8n
      - supabase-kong
    networks:
      - jstack-network
EOF
}
```

### 4. Intelligent Directory Setup
Replace any simple mkdir commands with intelligent directory creation:

```bash
setup_directory_structure() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Setting up directory structure..."
    
    # Define all required directories
    local dirs=(
        "sites/default/html"
        "nginx/conf.d"
        "nginx/certs"
        "certbot/conf"
        "certbot/www"
        "data/n8n"
        "data/supabase"
        "logs"
    )
    
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            mkdir -p "$dir"
            echo "✅ Created: $dir"
        fi
    done
    
    # Create default index.html if missing
    if [ ! -f "sites/default/html/index.html" ]; then
        create_default_index
    fi
    
    # Set proper permissions
    chmod -R 755 sites/
    chmod -R 755 nginx/
}

create_default_index() {
    cat > sites/default/html/index.html << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>jstack - AI Second Brain Infrastructure</title>
    <meta charset="utf-8">
    <style>
        body { 
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0a0a0a; 
            color: #e0e0e0; 
            display: flex; 
            justify-content: center; 
            align-items: center; 
            height: 100vh; 
            margin: 0;
        }
        .container { text-align: center; }
        h1 { color: #4a9eff; }
        .status { color: #4ade80; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🧠 jstack</h1>
        <p class="status">✅ System is running</p>
        <p>Your AI automation platform is ready.</p>
    </div>
</body>
</html>
EOF
}
```

### 5. Main Install Function Enhancement
Wrap the install process with proper error handling:

```bash
install() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Starting jstack installation..."
    
    # Run pre-installation validation
    if ! pre_install_validation; then
        echo "❌ Installation aborted due to validation errors"
        exit 1
    fi
    
    # Setup directory structure
    setup_directory_structure
    
    # Load or create configuration
    if [ ! -f "jstack.config" ]; then
        create_configuration
    else
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Using existing configuration file: ./jstack.config"
    fi
    
    # Prompt for credentials (existing code)
    prompt_for_credentials
    
    # Generate docker-compose.yml if needed
    if [ ! -f "docker-compose.yml" ] || [ "$REGENERATE_COMPOSE" = "true" ]; then
        generate_docker_compose
    fi
    
    # Final validation before deployment
    if ! docker-compose config > /dev/null 2>&1; then
        echo "❌ Docker Compose configuration is invalid"
        echo "Running auto-fix..."
        deduplicate_nginx_volumes
        
        # Try again
        if ! docker-compose config > /dev/null 2>&1; then
            echo "❌ Unable to fix configuration automatically"
            exit 1
        fi
    fi
    
    # Deploy services
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Deploying services via Docker Compose..."
    if docker-compose up -d; then
        echo "✅ jstack installation completed successfully!"
        show_post_install_info
    else
        echo "❌ Docker Compose deployment failed"
        echo "Check logs with: docker-compose logs"
        exit 1
    fi
}
```

### 6. Add Self-Healing Capabilities
Include functions that automatically fix common issues:

```bash
auto_fix_common_issues() {
    local fixed=0
    
    # Fix duplicate mounts
    if grep -q "site-templates:/usr/share/nginx/html" docker-compose.yml 2>/dev/null; then
        echo "🔧 Fixing duplicate nginx mounts..."
        deduplicate_nginx_volumes
        ((fixed++))
    fi
    
    # Fix missing directories
    local dirs=("sites/default/html" "nginx/conf.d" "certbot/conf" "certbot/www")
    for dir in "${dirs[@]}"; do
        if [ ! -d "$dir" ]; then
            echo "🔧 Creating missing directory: $dir"
            mkdir -p "$dir"
            ((fixed++))
        fi
    done
    
    # Fix permissions
    if [ -d "sites" ] && [ ! -w "sites/default/html" ]; then
        echo "🔧 Fixing directory permissions..."
        chmod -R 755 sites/
        ((fixed++))
    fi
    
    echo "✅ Auto-fixed $fixed issues"
}
```

### 7. Recommended Script Structure
The main script should follow this flow:

```bash
#!/bin/bash
set -euo pipefail  # Exit on error, undefined vars, pipe failures

# Constants and configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Include all the functions defined above

# Main execution
case "${1:-}" in
    --install)
        install
        ;;
    --fix)
        auto_fix_common_issues
        ;;
    --validate)
        pre_install_validation
        ;;
    *)
        show_usage
        ;;
esac
```

## Summary of Changes Needed

1. **Remove site-templates mount** from docker-compose generation
2. **Add pre-validation** before any Docker commands
3. **Auto-create all required directories** with proper structure
4. **Implement auto-fix functions** for common issues
5. **Add proper error handling** throughout
6. **Validate docker-compose.yml** before using it
7. **Make the script idempotent** (safe to run multiple times)

These changes will ensure `./jstack.sh --install` works reliably without manual intervention.