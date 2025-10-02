#!/bin/bash
# Edge Functions Management Script for JStack
# Wraps Supabase CLI commands and manages Docker deployment
# Uses native Supabase CLI for function operations

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSTACK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FUNCTIONS_DIR="$JSTACK_ROOT/supabase/functions"
CONTAINER_NAME="supabase-functions"

# Check if Supabase CLI is installed
check_supabase_cli() {
    if ! command -v supabase &> /dev/null; then
        error "Supabase CLI not found"
        echo ""
        info "Install with: npm install -g supabase"
        info "Or see: https://supabase.com/docs/guides/cli"
        return 1
    fi
    return 0
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${GREEN}✓${NC} $1"
}

warn() {
    echo -e "${YELLOW}⚠${NC} $1"
}

error() {
    echo -e "${RED}✗${NC} $1"
}

info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

# Check if functions directory exists
ensure_functions_dir() {
    if [ ! -d "$FUNCTIONS_DIR" ]; then
        mkdir -p "$FUNCTIONS_DIR"
        log "Created functions directory: $FUNCTIONS_DIR"
    fi
}

# List all edge functions
list_functions() {
    ensure_functions_dir

    echo ""
    echo "Edge Functions in $FUNCTIONS_DIR"
    echo "================================"
    echo ""

    if [ -z "$(ls -A "$FUNCTIONS_DIR" 2>/dev/null)" ]; then
        warn "No functions found"
        echo ""
        info "Create a new function with: ./jstack.sh --functions new <name>"
        return 0
    fi

    local count=0
    for func_dir in "$FUNCTIONS_DIR"/*; do
        if [ -d "$func_dir" ]; then
            local func_name=$(basename "$func_dir")
            local has_index=false
            local has_deno=false
            local file_count=0
            local total_size=0

            # Check for index.ts
            if [ -f "$func_dir/index.ts" ]; then
                has_index=true
            fi

            # Check for deno.json
            if [ -f "$func_dir/deno.json" ]; then
                has_deno=true
            fi

            # Count files and calculate size
            file_count=$(find "$func_dir" -type f | wc -l)
            total_size=$(du -sh "$func_dir" 2>/dev/null | cut -f1)

            # Display function info
            echo "📦 $func_name"
            if [ "$has_index" = true ]; then
                echo "   ✓ index.ts"
            else
                echo "   ✗ Missing index.ts"
            fi
            if [ "$has_deno" = true ]; then
                echo "   ✓ deno.json (has dependencies)"
            fi
            echo "   Files: $file_count | Size: $total_size"
            echo ""

            count=$((count + 1))
        fi
    done

    echo "Total functions: $count"
    echo ""
}

# Validate function structure
validate_function() {
    local func_path="$1"
    local func_name=$(basename "$func_path")

    if [ ! -d "$func_path" ]; then
        error "Function directory does not exist: $func_path"
        return 1
    fi

    if [ ! -f "$func_path/index.ts" ]; then
        error "Function $func_name is missing index.ts"
        return 1
    fi

    # Check if index.ts has content
    if [ ! -s "$func_path/index.ts" ]; then
        error "Function $func_name has empty index.ts"
        return 1
    fi

    # Optional: Check for basic Deno.serve structure
    if ! grep -q "Deno.serve" "$func_path/index.ts"; then
        warn "Function $func_name may be missing Deno.serve() call"
    fi

    return 0
}

# Import function from external directory
import_function() {
    local source_path="$1"

    if [ -z "$source_path" ]; then
        error "No source path provided"
        echo "Usage: ./jstack.sh --functions import <path>"
        return 1
    fi

    if [ ! -d "$source_path" ]; then
        error "Source path does not exist: $source_path"
        return 1
    fi

    local func_name=$(basename "$source_path")
    local target_path="$FUNCTIONS_DIR/$func_name"

    echo ""
    info "Importing function: $func_name"
    echo ""

    # Validate source function
    info "Validating source..."
    if ! validate_function "$source_path"; then
        error "Source function validation failed"
        return 1
    fi
    log "Source validation passed"

    # Check if target already exists
    if [ -d "$target_path" ]; then
        warn "Function $func_name already exists at target"
        read -p "Overwrite? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            info "Import cancelled"
            return 0
        fi
        rm -rf "$target_path"
    fi

    # Copy function
    info "Copying files..."
    ensure_functions_dir
    cp -r "$source_path" "$target_path"
    log "Files copied to $target_path"

    # Validate target
    if ! validate_function "$target_path"; then
        error "Target function validation failed"
        return 1
    fi

    # Restart container
    info "Restarting container..."
    if restart_container; then
        log "Container restarted"
    else
        error "Container restart failed"
        return 1
    fi

    echo ""
    log "Function '$func_name' imported successfully!"
    echo ""
    info "Test at: http://localhost:9000/$func_name"
    echo ""

    return 0
}

# Create new function from template using Supabase CLI
create_function() {
    local func_name="$1"

    if [ -z "$func_name" ]; then
        error "No function name provided"
        echo "Usage: ./jstack.sh --functions new <name>"
        return 1
    fi

    # Check Supabase CLI
    if ! check_supabase_cli; then
        return 1
    fi

    # Validate function name (alphanumeric, hyphens, underscores)
    if [[ ! "$func_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        error "Invalid function name. Use only letters, numbers, hyphens, and underscores"
        return 1
    fi

    local target_path="$FUNCTIONS_DIR/$func_name"

    echo ""
    info "Creating new function: $func_name"
    echo ""

    # Check if already exists
    if [ -d "$target_path" ]; then
        error "Function $func_name already exists"
        info "Use './jstack.sh --functions edit $func_name' to edit it"
        return 1
    fi

    # Use Supabase CLI to create function
    cd "$JSTACK_ROOT"
    if supabase functions new "$func_name"; then
        log "Function '$func_name' created successfully!"
        echo ""
        info "Location: $target_path/index.ts"
        info "Edit with: ./jstack.sh --functions edit $func_name"
        info "Serve locally: supabase functions serve"
        echo ""

        # Register function in _main router
        info "Remember to register this function in supabase/functions/_main/index.ts"
        echo ""

        # Ask if user wants to edit now
        read -p "Edit now? [Y/n]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
            edit_function "$func_name"
        fi

        return 0
    else
        error "Failed to create function"
        return 1
    fi
}

# Old template code removed - now using Supabase CLI
# The following is kept for reference if Supabase CLI is not available
create_function_fallback() {
    local func_name="$1"
    local target_path="$FUNCTIONS_DIR/$func_name"

    # Create directory
    ensure_functions_dir
    mkdir -p "$target_path"

    # Create index.ts with template
    cat > "$target_path/index.ts" << 'EOF'
// Edge Function: Replace with your function name
// For more examples, see: https://supabase.com/docs/guides/functions

Deno.serve(async (req) => {
  try {
    // Get request data
    const { method, url } = req;

    // Example: Parse JSON body for POST requests
    let body = null;
    if (method === 'POST') {
      body = await req.json();
    }

    // Your function logic here
    const data = {
      message: "Hello from Edge Function!",
      method: method,
      timestamp: new Date().toISOString(),
      body: body
    };

    // Return JSON response
    return new Response(
      JSON.stringify(data),
      {
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*"
        },
        status: 200
      }
    );

  } catch (error) {
    // Error handling
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: {
          "Content-Type": "application/json",
          "Access-Control-Allow-Origin": "*"
        },
        status: 500
      }
    );
  }
});
EOF

    log "Created $target_path/index.ts"

    # Optionally create deno.json for dependencies
    # Uncomment if needed by default
    # cat > "$target_path/deno.json" << 'EOF'
# {
#   "imports": {
#   }
# }
# EOF

    echo ""
    log "Function '$func_name' created successfully!"
    echo ""
    info "Location: $target_path/index.ts"
    info "Edit with: ./jstack.sh --functions edit $func_name"
    echo ""

    # Ask if user wants to edit now
    read -p "Edit now? [Y/n]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        edit_function "$func_name"
    fi

    return 0
}

# Edit existing function
edit_function() {
    local func_name="$1"

    if [ -z "$func_name" ]; then
        error "No function name provided"
        echo "Usage: ./jstack.sh --functions edit <name>"
        return 1
    fi

    local func_path="$FUNCTIONS_DIR/$func_name"
    local index_path="$func_path/index.ts"

    if [ ! -d "$func_path" ]; then
        error "Function $func_name does not exist"
        info "Available functions:"
        list_functions
        return 1
    fi

    if [ ! -f "$index_path" ]; then
        error "Function $func_name is missing index.ts"
        return 1
    fi

    echo ""
    info "Opening $func_name in editor..."
    echo ""

    # Determine editor (prefer nano, fallback to vim, then vi)
    local editor="${EDITOR:-nano}"
    if ! command -v "$editor" &> /dev/null; then
        if command -v nano &> /dev/null; then
            editor="nano"
        elif command -v vim &> /dev/null; then
            editor="vim"
        elif command -v vi &> /dev/null; then
            editor="vi"
        else
            error "No text editor found (tried: $EDITOR, nano, vim, vi)"
            return 1
        fi
    fi

    # Get modification time before editing
    local mtime_before=$(stat -c %Y "$index_path" 2>/dev/null || stat -f %m "$index_path" 2>/dev/null)

    # Open editor
    "$editor" "$index_path"

    # Get modification time after editing
    local mtime_after=$(stat -c %Y "$index_path" 2>/dev/null || stat -f %m "$index_path" 2>/dev/null)

    # Check if file was modified
    if [ "$mtime_before" != "$mtime_after" ]; then
        echo ""
        log "File saved with changes"

        # Validate the function
        if validate_function "$func_path"; then
            log "Function validated successfully"

            # Ask to restart container
            read -p "Restart container to apply changes? [Y/n]: " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
                if restart_container; then
                    log "Container restarted - changes are live!"
                    info "Test at: http://localhost:9000/$func_name"
                fi
            else
                info "Remember to restart later: ./jstack.sh --functions restart"
            fi
        else
            warn "Function validation failed - there may be errors"
        fi
    else
        info "No changes made"
    fi

    echo ""
    return 0
}

# Delete function
delete_function() {
    local func_name="$1"

    if [ -z "$func_name" ]; then
        error "No function name provided"
        echo "Usage: ./jstack.sh --functions delete <name>"
        return 1
    fi

    local func_path="$FUNCTIONS_DIR/$func_name"

    if [ ! -d "$func_path" ]; then
        error "Function $func_name does not exist"
        return 1
    fi

    echo ""
    warn "This will permanently delete function: $func_name"
    echo "Location: $func_path"
    echo ""
    read -p "Are you sure? Type 'yes' to confirm: " -r
    echo

    if [ "$REPLY" != "yes" ]; then
        info "Deletion cancelled"
        return 0
    fi

    # Delete the function
    rm -rf "$func_path"
    log "Function $func_name deleted"

    # Restart container
    info "Restarting container..."
    if restart_container; then
        log "Container restarted"
    fi

    echo ""
    log "Function $func_name removed successfully"
    echo ""

    return 0
}

# Restart the supabase-functions container
restart_container() {
    cd "$JSTACK_ROOT"

    if ! command -v docker-compose &> /dev/null && ! command -v docker &> /dev/null; then
        error "Docker not found"
        return 1
    fi

    # Find the actual container name (docker-compose adds prefix and suffix)
    local actual_container=$(docker ps -a --format '{{.Names}}' | grep "${CONTAINER_NAME}" | head -1)

    if [ -z "$actual_container" ]; then
        error "Container matching $CONTAINER_NAME not found"
        info "Start JStack services first: ./jstack.sh up"
        return 1
    fi

    info "Restarting container: $actual_container"

    # Restart the container using docker-compose service name
    if command -v docker-compose &> /dev/null; then
        docker-compose restart "$CONTAINER_NAME" >/dev/null 2>&1
    else
        docker restart "$actual_container" >/dev/null 2>&1
    fi

    # Wait for container to be healthy
    local max_wait=10
    local count=0
    while [ $count -lt $max_wait ]; do
        if docker ps --filter "name=$actual_container" --filter "status=running" | grep -q "$actual_container"; then
            return 0
        fi
        sleep 1
        ((count++))
    done

    error "Container did not start within ${max_wait} seconds"
    return 1
}

# Show logs for a function or container
show_logs() {
    local func_name="$1"

    cd "$JSTACK_ROOT"

    # Find the actual container name
    local actual_container=$(docker ps -a --format '{{.Names}}' | grep "${CONTAINER_NAME}" | head -1)

    if [ -z "$actual_container" ]; then
        error "Container matching $CONTAINER_NAME not found"
        return 1
    fi

    if [ -n "$func_name" ]; then
        info "Showing logs for function: $func_name"
        echo ""
        docker logs "$actual_container" 2>&1 | grep -i "$func_name" | tail -n 50
    else
        info "Showing container logs (last 50 lines):"
        echo ""
        docker logs --tail 50 "$actual_container"
    fi

    echo ""
}

# Serve functions locally using Supabase CLI
serve_functions() {
    if ! check_supabase_cli; then
        return 1
    fi

    cd "$JSTACK_ROOT"

    echo ""
    info "Starting Supabase functions server..."
    info "This will serve all functions in $FUNCTIONS_DIR"
    echo ""
    info "Press Ctrl+C to stop"
    echo ""

    # Run supabase functions serve
    supabase functions serve
}

# Register a function in the _main router
register_function() {
    local func_name="$1"

    if [ -z "$func_name" ]; then
        error "No function name provided"
        echo "Usage: ./jstack.sh --functions register <name>"
        return 1
    fi

    local main_router="$FUNCTIONS_DIR/_main/index.ts"

    if [ ! -f "$main_router" ]; then
        error "_main router not found at $main_router"
        info "Create it first or use the Docker deployment"
        return 1
    fi

    echo ""
    info "To register '$func_name' in the Docker router:"
    echo ""
    echo "1. Edit $main_router"
    echo "2. Add routing logic for '/$func_name'"
    echo "3. Restart container: ./jstack.sh --functions restart"
    echo ""
    info "Or use 'supabase functions serve' for local development (auto-discovery)"
    echo ""
}

# Show help
show_help() {
    cat << EOF

Edge Functions Management (JStack + Supabase CLI)

Usage: ./jstack.sh --functions <command> [arguments]

Commands:
  list                    List all edge functions
  new <name>              Create new function (uses Supabase CLI)
  serve                   Serve all functions locally (uses Supabase CLI)
  edit <name>             Edit existing function
  delete <name>           Delete function
  register <name>         Show how to register function in Docker router
  restart                 Restart Docker functions container
  logs [name]             Show container logs
  import <path>           Import function from directory

Examples:
  # Create new function (uses Supabase CLI)
  ./jstack.sh --functions new my-function

  # Serve locally for development
  ./jstack.sh --functions serve

  # Edit function
  ./jstack.sh --functions edit my-function

  # List all functions
  ./jstack.sh --functions list

  # Restart Docker container (production)
  ./jstack.sh --functions restart

Native Supabase CLI commands (can also be used directly):
  supabase functions new <name>       # Create function
  supabase functions serve            # Serve all functions
  supabase functions deploy <name>    # Deploy to cloud

Functions are stored in: $FUNCTIONS_DIR

For more information, see: docs/EDGE_FUNCTIONS.md

EOF
}

# Main command router
main() {
    local command="$1"
    shift

    case "$command" in
        list)
            list_functions
            ;;
        new|create)
            create_function "$@"
            ;;
        serve)
            serve_functions
            ;;
        edit)
            edit_function "$@"
            ;;
        register)
            register_function "$@"
            ;;
        import)
            import_function "$@"
            ;;
        delete|remove|rm)
            delete_function "$@"
            ;;
        restart)
            info "Restarting container..."
            if restart_container; then
                log "Container restarted successfully"
            else
                error "Container restart failed"
                return 1
            fi
            ;;
        logs)
            show_logs "$@"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            error "Unknown command: $command"
            show_help
            return 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
