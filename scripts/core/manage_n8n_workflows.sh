#!/bin/bash
# n8n Workflow Management Script for JStack
# Provides CLI access to n8n workflows via SQLite database
# Read-only operations by default (view, list, export)

set -e

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
JSTACK_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
N8N_DB_PATH="$JSTACK_ROOT/data/n8n/database.sqlite"
CONTAINER_NAME="n8n"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
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

highlight() {
    echo -e "${CYAN}$1${NC}"
}

# Check if database exists
check_database() {
    if [ ! -f "$N8N_DB_PATH" ]; then
        error "n8n database not found at: $N8N_DB_PATH"
        info "Make sure n8n is installed and running"
        return 1
    fi
    return 0
}

# Execute SQLite query using Docker
query_db() {
    local query="$1"
    docker run --rm -v "$JSTACK_ROOT/data/n8n:/data" nouchka/sqlite3 /data/database.sqlite "$query" 2>/dev/null
}

# List all workflows
list_workflows() {
    if ! check_database; then
        return 1
    fi

    echo ""
    echo "n8n Workflows"
    echo "============================================"
    echo ""

    local query="SELECT id, name, active, triggerCount, updatedAt FROM workflow_entity WHERE isArchived = 0 ORDER BY updatedAt DESC;"
    local results=$(query_db "$query")

    if [ -z "$results" ]; then
        warn "No workflows found"
        echo ""
        info "Create workflows in the n8n web interface"
        return 0
    fi

    local count=0
    while IFS='|' read -r id name active trigger_count updated_at; do
        count=$((count + 1))

        # Format status
        if [ "$active" = "1" ]; then
            local status="${GREEN}●${NC} Active"
        else
            local status="${YELLOW}○${NC} Inactive"
        fi

        # Format date (remove milliseconds)
        local date_short=$(echo "$updated_at" | cut -d'.' -f1)

        echo -e "📋 ${CYAN}$name${NC}"
        echo "   ID: $id"
        echo -e "   Status: $status"
        echo "   Triggers: $trigger_count"
        echo "   Updated: $date_short"
        echo ""
    done <<< "$results"

    echo "Total workflows: $count"
    echo ""
    info "View details: ./jstack.sh --workflows view <id|name>"
    echo ""
}

# Find workflow by ID or name
find_workflow() {
    local identifier="$1"

    if [ -z "$identifier" ]; then
        error "No workflow identifier provided"
        return 1
    fi

    # Try exact ID match first
    local query="SELECT id FROM workflow_entity WHERE id = '$identifier' AND isArchived = 0 LIMIT 1;"
    local result=$(query_db "$query")

    if [ -n "$result" ]; then
        echo "$result"
        return 0
    fi

    # Try exact name match
    query="SELECT id FROM workflow_entity WHERE name = '$identifier' AND isArchived = 0 LIMIT 1;"
    result=$(query_db "$query")

    if [ -n "$result" ]; then
        echo "$result"
        return 0
    fi

    # Try partial name match (case insensitive)
    query="SELECT id FROM workflow_entity WHERE name LIKE '%$identifier%' AND isArchived = 0 LIMIT 1;"
    result=$(query_db "$query")

    if [ -n "$result" ]; then
        echo "$result"
        return 0
    fi

    error "Workflow not found: $identifier"
    info "Use './jstack.sh --workflows list' to see available workflows"
    return 1
}

# View workflow details
view_workflow() {
    local identifier="$1"

    if ! check_database; then
        return 1
    fi

    local workflow_id=$(find_workflow "$identifier")
    if [ -z "$workflow_id" ]; then
        return 1
    fi

    # Get workflow metadata
    local query="SELECT id, name, active, triggerCount, createdAt, updatedAt, versionId FROM workflow_entity WHERE id = '$workflow_id';"
    local result=$(query_db "$query")

    if [ -z "$result" ]; then
        error "Failed to retrieve workflow data"
        return 1
    fi

    IFS='|' read -r id name active trigger_count created_at updated_at version_id <<< "$result"

    # Format status
    if [ "$active" = "1" ]; then
        local status="${GREEN}● Active${NC}"
    else
        local status="${YELLOW}○ Inactive${NC}"
    fi

    echo ""
    echo "Workflow Details"
    echo "============================================"
    echo ""
    echo -e "Name:       ${CYAN}$name${NC}"
    echo "ID:         $id"
    echo -e "Status:     $status"
    echo "Triggers:   $trigger_count"
    echo "Created:    $(echo "$created_at" | cut -d'.' -f1)"
    echo "Updated:    $(echo "$updated_at" | cut -d'.' -f1)"
    echo "Version:    ${version_id:-N/A}"
    echo ""

    # Get nodes information
    query="SELECT nodes FROM workflow_entity WHERE id = '$workflow_id';"
    local nodes_json=$(query_db "$query")

    if [ -n "$nodes_json" ]; then
        # Count nodes and extract types
        echo "Nodes:"
        echo "------"

        # Parse JSON to extract node information (basic parsing)
        local node_count=$(echo "$nodes_json" | grep -o '"type":' | wc -l)
        echo "Total nodes: $node_count"
        echo ""

        # Extract node types and names
        echo "Node List:"
        local node_info=$(echo "$nodes_json" | grep -oP '"name":"[^"]+"|"type":"[^"]+"' | paste -d ' ' - - | sed 's/"name":"\([^"]*\)".*"type":"\([^"]*\)"/  • \1 (\2)/g')
        echo "$node_info"
        echo ""

        # Check for sub-workflow dependencies
        if echo "$nodes_json" | grep -q "toolWorkflow"; then
            echo "Sub-workflow Dependencies:"
            echo "--------------------------"
            local sub_workflows=$(echo "$nodes_json" | grep -oP '"workflowId":\{"[^}]*"value":"[^"]+"|"name":"[^"]+"' | grep -A1 workflowId | grep -oP '"value":"[^"]+"' | cut -d'"' -f4)

            if [ -n "$sub_workflows" ]; then
                while read -r sub_id; do
                    if [ -n "$sub_id" ]; then
                        local sub_query="SELECT name FROM workflow_entity WHERE id = '$sub_id';"
                        local sub_name=$(query_db "$sub_query")
                        if [ -n "$sub_name" ]; then
                            echo "  → $sub_name ($sub_id)"
                        else
                            echo "  → Unknown workflow ($sub_id)"
                        fi
                    fi
                done <<< "$sub_workflows"
                echo ""
            fi
        fi
    fi

    # Get settings
    query="SELECT settings FROM workflow_entity WHERE id = '$workflow_id';"
    local settings=$(query_db "$query")

    if [ -n "$settings" ] && [ "$settings" != "{}" ]; then
        echo "Settings:"
        echo "---------"
        echo "$settings" | sed 's/,/\n/g' | sed 's/[{}"]//g' | sed 's/^/  /'
        echo ""
    fi

    info "Export: ./jstack.sh --workflows export $workflow_id"
    echo ""
}

# Export workflow to JSON
export_workflow() {
    local identifier="$1"
    local output_file="$2"

    if ! check_database; then
        return 1
    fi

    local workflow_id=$(find_workflow "$identifier")
    if [ -z "$workflow_id" ]; then
        return 1
    fi

    # Get complete workflow data
    local query="SELECT id, name, active, nodes, connections, settings, staticData, pinData FROM workflow_entity WHERE id = '$workflow_id';"
    local result=$(query_db "$query")

    if [ -z "$result" ]; then
        error "Failed to retrieve workflow data"
        return 1
    fi

    IFS='|' read -r id name active nodes connections settings static_data pin_data <<< "$result"

    # Determine output file
    if [ -z "$output_file" ]; then
        # Create filename from workflow name (sanitize)
        local safe_name=$(echo "$name" | tr ' ' '_' | tr -cd '[:alnum:]_-')
        output_file="${safe_name}_${id}.json"
    fi

    # Build JSON output
    cat > "$output_file" << EOF
{
  "id": "$id",
  "name": "$name",
  "active": $active,
  "nodes": $nodes,
  "connections": $connections,
  "settings": $settings,
  "staticData": $static_data,
  "pinData": $pin_data
}
EOF

    log "Workflow exported to: $output_file"

    # Show file size
    local file_size=$(du -h "$output_file" | cut -f1)
    info "File size: $file_size"
    echo ""
}

# Search workflows by name
search_workflows() {
    local search_term="$1"

    if [ -z "$search_term" ]; then
        error "No search term provided"
        echo "Usage: ./jstack.sh --workflows search <term>"
        return 1
    fi

    if ! check_database; then
        return 1
    fi

    echo ""
    echo "Search Results for: '$search_term'"
    echo "============================================"
    echo ""

    local query="SELECT id, name, active FROM workflow_entity WHERE name LIKE '%$search_term%' AND isArchived = 0 ORDER BY name;"
    local results=$(query_db "$query")

    if [ -z "$results" ]; then
        warn "No workflows found matching: $search_term"
        echo ""
        return 0
    fi

    local count=0
    while IFS='|' read -r id name active; do
        count=$((count + 1))

        if [ "$active" = "1" ]; then
            local status="${GREEN}●${NC}"
        else
            local status="${YELLOW}○${NC}"
        fi

        echo -e "$status ${CYAN}$name${NC}"
        echo "   ID: $id"
        echo ""
    done <<< "$results"

    echo "Found: $count workflow(s)"
    echo ""
}

# Show workflow statistics
show_stats() {
    local identifier="$1"

    if ! check_database; then
        return 1
    fi

    local workflow_id=$(find_workflow "$identifier")
    if [ -z "$workflow_id" ]; then
        return 1
    fi

    # Get workflow data
    local query="SELECT name, nodes, connections FROM workflow_entity WHERE id = '$workflow_id';"
    local result=$(query_db "$query")

    if [ -z "$result" ]; then
        error "Failed to retrieve workflow data"
        return 1
    fi

    IFS='|' read -r name nodes connections <<< "$result"

    echo ""
    echo "Workflow Statistics: $name"
    echo "============================================"
    echo ""

    # Count nodes
    local node_count=$(echo "$nodes" | grep -o '"type":' | wc -l)
    echo "Total Nodes: $node_count"

    # Count node types
    local trigger_count=$(echo "$nodes" | grep -o '"type":"[^"]*Trigger"' | wc -l)
    local tool_count=$(echo "$nodes" | grep -o '"type":"@n8n/n8n-nodes-langchain.toolWorkflow"' | wc -l)
    local agent_count=$(echo "$nodes" | grep -o '"type":"@n8n/n8n-nodes-langchain.agent"' | wc -l)

    echo "  Triggers: $trigger_count"
    echo "  AI Agents: $agent_count"
    echo "  Tool Workflows: $tool_count"
    echo "  Other: $((node_count - trigger_count - tool_count - agent_count))"
    echo ""

    # Count connections
    local connection_count=$(echo "$connections" | grep -o '"main":' | wc -l)
    echo "Connections: $connection_count"
    echo ""

    # Calculate JSON sizes
    local nodes_size=$(echo "$nodes" | wc -c)
    local connections_size=$(echo "$connections" | wc -c)

    echo "Data Size:"
    echo "  Nodes: $(numfmt --to=iec-i --suffix=B $nodes_size)"
    echo "  Connections: $(numfmt --to=iec-i --suffix=B $connections_size)"
    echo ""
}

# Show workflow dependency tree
show_tree() {
    local identifier="$1"
    local depth="${2:-0}"
    local prefix="${3:-}"

    if ! check_database; then
        return 1
    fi

    local workflow_id=$(find_workflow "$identifier")
    if [ -z "$workflow_id" ]; then
        return 1
    fi

    # Get workflow info
    local query="SELECT name, nodes FROM workflow_entity WHERE id = '$workflow_id';"
    local result=$(query_db "$query")

    if [ -z "$result" ]; then
        return 1
    fi

    IFS='|' read -r name nodes <<< "$result"

    # Show current workflow
    if [ $depth -eq 0 ]; then
        echo ""
        echo "Workflow Dependency Tree"
        echo "============================================"
        echo ""
        echo -e "${CYAN}$name${NC} ($workflow_id)"
    else
        echo -e "${prefix}└─ ${CYAN}$name${NC} ($workflow_id)"
    fi

    # Find sub-workflows (max depth 3 to prevent infinite loops)
    if [ $depth -lt 3 ]; then
        local sub_workflows=$(echo "$nodes" | grep -oP '"workflowId":\{"[^}]*"value":"[^"]+"' | grep -oP '"value":"[^"]+"' | cut -d'"' -f4 | sort -u)

        if [ -n "$sub_workflows" ]; then
            while read -r sub_id; do
                if [ -n "$sub_id" ]; then
                    show_tree "$sub_id" $((depth + 1)) "$prefix  "
                fi
            done <<< "$sub_workflows"
        fi
    fi

    if [ $depth -eq 0 ]; then
        echo ""
    fi
}

# Show overall statistics
show_overall_stats() {
    if ! check_database; then
        return 1
    fi

    echo ""
    echo "n8n Workflow Statistics"
    echo "============================================"
    echo ""

    # Total workflows
    local total=$(query_db "SELECT COUNT(*) FROM workflow_entity WHERE isArchived = 0;")
    echo "Total Workflows: $total"

    # Active workflows
    local active=$(query_db "SELECT COUNT(*) FROM workflow_entity WHERE active = 1 AND isArchived = 0;")
    echo "  Active: $active"
    echo "  Inactive: $((total - active))"
    echo ""

    # Most triggered workflows
    echo "Most Triggered Workflows:"
    echo "-------------------------"
    local top_triggered=$(query_db "SELECT name, triggerCount FROM workflow_entity WHERE isArchived = 0 ORDER BY triggerCount DESC LIMIT 5;")

    if [ -n "$top_triggered" ]; then
        while IFS='|' read -r name count; do
            echo "  $count - $name"
        done <<< "$top_triggered"
    fi
    echo ""

    # Recently updated
    echo "Recently Updated:"
    echo "-----------------"
    local recent=$(query_db "SELECT name, updatedAt FROM workflow_entity WHERE isArchived = 0 ORDER BY updatedAt DESC LIMIT 5;")

    if [ -n "$recent" ]; then
        while IFS='|' read -r name updated; do
            local date_short=$(echo "$updated" | cut -d'.' -f1)
            echo "  $date_short - $name"
        done <<< "$recent"
    fi
    echo ""
}

# Show help
show_help() {
    cat << EOF

n8n Workflow Management (JStack)

Usage: ./jstack.sh --workflows <command> [arguments]

Commands:
  list                    List all workflows with status
  view <id|name>          View complete workflow details
  export <id|name> [file] Export workflow to JSON file
  search <term>           Search workflows by name
  stats [id|name]         Show workflow statistics (or overall if no ID)
  tree <id|name>          Show workflow dependency tree

Examples:
  # List all workflows
  ./jstack.sh --workflows list

  # View workflow details by name
  ./jstack.sh --workflows view "Telegram input"

  # Export workflow to JSON
  ./jstack.sh --workflows export EWrrgFUh91xoodbB

  # Search for workflows
  ./jstack.sh --workflows search telegram

  # Show statistics
  ./jstack.sh --workflows stats

  # Show dependency tree
  ./jstack.sh --workflows tree "Telegram input"

Database location: $N8N_DB_PATH

Note: These are read-only operations. To modify workflows, use the n8n web interface.

EOF
}

# Main command router
main() {
    local command="$1"
    shift

    case "$command" in
        list|ls)
            list_workflows
            ;;
        view|show|get)
            view_workflow "$@"
            ;;
        export|dump)
            export_workflow "$@"
            ;;
        search|find)
            search_workflows "$@"
            ;;
        stats|statistics)
            if [ -z "$1" ]; then
                show_overall_stats
            else
                show_stats "$@"
            fi
            ;;
        tree|deps|dependencies)
            show_tree "$@"
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
