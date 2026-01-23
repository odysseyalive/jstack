#!/bin/bash

# Setup MCP Server for JStack
# Installs dependencies, builds TypeScript, and configures for Claude Desktop

set -e

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
MCP_DIR="$PROJECT_ROOT/mcp-server"

log "Setting up JStack MCP Server..."

# Check if Node.js is installed
if ! command -v node >/dev/null 2>&1; then
  log "Node.js not found. Installing Node.js..."

  # Install Node.js (using NodeSource for Debian)
  curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
  sudo apt-get install -y nodejs

  log "✓ Node.js installed: $(node --version)"
else
  log "✓ Node.js found: $(node --version)"
fi

# Check if npm is available
if ! command -v npm >/dev/null 2>&1; then
  log "ERROR: npm not found"
  exit 1
fi

log "✓ npm found: $(npm --version)"

# Navigate to MCP directory
cd "$MCP_DIR"

# Install dependencies
log "Installing npm dependencies..."
npm install

log "✓ Dependencies installed"

# Build TypeScript
log "Building TypeScript..."
npm run build

log "✓ TypeScript compiled to build/"

# Make executable
chmod +x build/index.js

log "✓ Made build/index.js executable"

# Create Claude Desktop config directory if it doesn't exist
CLAUDE_CONFIG_DIR="$HOME/.config/claude"
mkdir -p "$CLAUDE_CONFIG_DIR"

# Generate Claude Desktop config
CLAUDE_CONFIG_FILE="$CLAUDE_CONFIG_DIR/claude_desktop_config.json"

log "Checking Claude Desktop configuration..."

if [ -f "$CLAUDE_CONFIG_FILE" ]; then
  log "⚠ Claude Desktop config already exists at $CLAUDE_CONFIG_FILE"
  log "  Please manually add the following to your mcpServers section:"
  echo ""
  echo "  \"jstack\": {"
  echo "    \"command\": \"node\","
  echo "    \"args\": [\"$MCP_DIR/build/index.js\"],"
  echo "    \"env\": {"
  echo "      \"EDGE_FUNCTIONS_URL\": \"http://localhost:9000\","
  echo "      \"MCP_USER_ID\": \"mcp-user-francis\""
  echo "    }"
  echo "  }"
  echo ""
else
  log "Creating Claude Desktop config..."
  cat > "$CLAUDE_CONFIG_FILE" << EOF
{
  "mcpServers": {
    "jstack": {
      "command": "node",
      "args": ["$MCP_DIR/build/index.js"],
      "env": {
        "EDGE_FUNCTIONS_URL": "http://localhost:9000",
        "MCP_USER_ID": "mcp-user-francis"
      }
    }
  }
}
EOF
  log "✓ Created Claude Desktop config at $CLAUDE_CONFIG_FILE"
fi

log ""
log "=========================================="
log "MCP Server Setup Complete!"
log "=========================================="
log ""
log "Next steps:"
log "1. Restart Claude Desktop to load the MCP server"
log "2. Open Claude Desktop and check for the 🔌 icon (MCP connected)"
log "3. Try asking Claude to search your memory or create a note"
log ""
log "Available tools:"
log "  - search_memory: Search messages, notes, contacts, images"
log "  - create_note, update_note, delete_note, get_note: Note management"
log "  - store_contact, search_contacts: Contact management"
log "  - query_image, process_image: Image tools"
log "  - store_message: Message storage"
log "  - manage_tags: Tag management"
log ""
log "Configuration:"
log "  Config file: $CLAUDE_CONFIG_FILE"
log "  MCP directory: $MCP_DIR"
log "  Edge functions: http://localhost:9000"
log ""
