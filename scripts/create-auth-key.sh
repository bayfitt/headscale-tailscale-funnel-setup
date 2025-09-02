#!/bin/bash
# Create Authentication Key Script for Headscale
# Generates pre-authentication keys for users

set -e

# Configuration
HEADSCALE_DIR="/opt/headscale"
DEFAULT_EXPIRATION="1h"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_header() {
    echo -e "${BLUE}[AUTH]${NC} $1"
}

# Check if user exists
check_user_exists() {
    local username="$1"
    local user_list
    user_list=$(sudo -u headscale docker compose -f "$HEADSCALE_DIR/docker-compose.yml" exec -T headscale headscale users list)
    
    if echo "$user_list" | grep -q "$username"; then
        return 0
    else
        return 1
    fi
}

# Get user ID by username
get_user_id() {
    local username="$1"
    local user_id
    user_id=$(sudo -u headscale docker compose -f "$HEADSCALE_DIR/docker-compose.yml" exec -T headscale headscale users list | grep "$username" | awk '{print $1}')
    echo "$user_id"
}

# Create new user
create_user() {
    local username="$1"
    
    log_header "Creating user: $username"
    
    if check_user_exists "$username"; then
        log_info "User '$username' already exists"
        return 0
    fi
    
    if sudo -u headscale docker compose -f "$HEADSCALE_DIR/docker-compose.yml" exec -T headscale headscale users create "$username"; then
        log_info "✓ User '$username' created successfully"
    else
        log_error "✗ Failed to create user '$username'"
        return 1
    fi
}

# Create auth key
create_auth_key() {
    local username="$1"
    local expiration="$2"
    local reusable="$3"
    
    # Get user ID
    local user_id
    user_id=$(get_user_id "$username")
    
    if [[ -z "$user_id" ]]; then
        log_error "Could not find user ID for '$username'"
        return 1
    fi
    
    log_header "Creating auth key for user: $username (ID: $user_id)"
    
    # Build command
    local cmd="headscale preauthkeys create --user $user_id --expiration $expiration"
    if [[ "$reusable" == "true" ]]; then
        cmd="$cmd --reusable"
    fi
    
    # Execute command
    local auth_key
    auth_key=$(sudo -u headscale docker compose -f "$HEADSCALE_DIR/docker-compose.yml" exec -T headscale $cmd | head -1)
    
    if [[ -n "$auth_key" ]]; then
        log_info "✓ Auth key created successfully"
        echo ""
        echo "=========================================="
        echo "AUTH KEY FOR USER: $username"
        echo "=========================================="
        echo "$auth_key"
        echo "=========================================="
        echo "Expiration: $expiration"
        echo "Reusable: $reusable"
        echo "=========================================="
        echo ""
        
        # Save to file for reference
        local key_file="/tmp/headscale-key-$username-$(date +%Y%m%d-%H%M%S).txt"
        cat > "$key_file" << EOF
Headscale Authentication Key
Generated: $(date)
User: $username
User ID: $user_id
Expiration: $expiration
Reusable: $reusable

Auth Key:
$auth_key

Server URL:
$(get_server_url)

Instructions for iOS:
1. Open Tailscale app
2. Add account -> Use custom coordination server
3. Enter server URL above
4. Enter auth key above
EOF
        
        log_info "Key details saved to: $key_file"
        
    else
        log_error "✗ Failed to create auth key"
        return 1
    fi
}

# Get server URL from configuration
get_server_url() {
    if [[ -f "$HEADSCALE_DIR/headscale-config/config.yaml" ]]; then
        grep "server_url:" "$HEADSCALE_DIR/headscale-config/config.yaml" | sed 's/.*server_url: *//'
    else
        echo "https://your-tailscale-hostname.ts.net"
    fi
}

# List users
list_users() {
    log_header "Current users:"
    sudo -u headscale docker compose -f "$HEADSCALE_DIR/docker-compose.yml" exec -T headscale headscale users list
}

# List auth keys
list_auth_keys() {
    local username="$1"
    
    if [[ -n "$username" ]]; then
        local user_id
        user_id=$(get_user_id "$username")
        
        if [[ -n "$user_id" ]]; then
            log_header "Auth keys for user: $username"
            sudo -u headscale docker compose -f "$HEADSCALE_DIR/docker-compose.yml" exec -T headscale headscale preauthkeys list --user "$user_id"
        else
            log_error "User '$username' not found"
        fi
    else
        log_header "All auth keys:"
        sudo -u headscale docker compose -f "$HEADSCALE_DIR/docker-compose.yml" exec -T headscale headscale preauthkeys list
    fi
}

# Check if Headscale is running
check_headscale_running() {
    if ! sudo -u headscale docker compose -f "$HEADSCALE_DIR/docker-compose.yml" ps | grep -q "headscale.*Up"; then
        log_error "Headscale container is not running"
        log_info "Start with: sudo -u headscale docker compose -f $HEADSCALE_DIR/docker-compose.yml up -d"
        return 1
    fi
}

# Main function
main() {
    local username=""
    local expiration="$DEFAULT_EXPIRATION"
    local reusable="false"
    local action="create"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --user|-u)
                username="$2"
                shift 2
                ;;
            --expiration|-e)
                expiration="$2"
                shift 2
                ;;
            --reusable|-r)
                reusable="true"
                shift
                ;;
            --list-users)
                action="list_users"
                shift
                ;;
            --list-keys)
                action="list_keys"
                if [[ -n "$2" ]] && [[ "$2" != --* ]]; then
                    username="$2"
                    shift
                fi
                shift
                ;;
            --help|-h)
                action="help"
                shift
                ;;
            *)
                if [[ -z "$username" ]]; then
                    username="$1"
                fi
                shift
                ;;
        esac
    done
    
    # Handle different actions
    case $action in
        help)
            echo "Headscale Authentication Key Generator"
            echo ""
            echo "Usage: $0 [OPTIONS] USERNAME"
            echo ""
            echo "Options:"
            echo "  -u, --user USERNAME     Username for the auth key"
            echo "  -e, --expiration TIME   Expiration time (default: $DEFAULT_EXPIRATION)"
            echo "                          Examples: 1h, 24h, 7d, 30d"
            echo "  -r, --reusable          Make the key reusable (default: single-use)"
            echo "      --list-users        List all users"
            echo "      --list-keys [USER]  List auth keys (all or for specific user)"
            echo "  -h, --help              Show this help"
            echo ""
            echo "Examples:"
            echo "  $0 john                          # Create 1h key for john"
            echo "  $0 --user john --expiration 24h  # Create 24h key for john"
            echo "  $0 -u john -e 7d -r             # Create reusable 7d key for john"
            echo "  $0 --list-users                  # List all users"
            echo "  $0 --list-keys john              # List keys for john"
            echo ""
            exit 0
            ;;
        list_users)
            check_headscale_running
            list_users
            exit 0
            ;;
        list_keys)
            check_headscale_running
            list_auth_keys "$username"
            exit 0
            ;;
        create)
            if [[ -z "$username" ]]; then
                log_error "Username is required"
                echo "Usage: $0 [OPTIONS] USERNAME"
                echo "Use --help for more information"
                exit 1
            fi
            
            check_headscale_running
            create_user "$username"
            create_auth_key "$username" "$expiration" "$reusable"
            ;;
    esac
}

# Run main function
main "$@"