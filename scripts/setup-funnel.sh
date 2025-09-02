#!/bin/bash
# Setup Tailscale Funnel for Public HTTPS Access
# Configures Tailscale Funnel to expose Headscale publicly

set -e

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
    echo -e "${BLUE}[FUNNEL]${NC} $1"
}

# Check if Tailscale is connected
check_tailscale_status() {
    log_header "Checking Tailscale status..."
    
    if ! command -v tailscale >/dev/null 2>&1; then
        log_error "Tailscale is not installed"
        log_info "Install with: curl -fsSL https://tailscale.com/install.sh | sh"
        exit 1
    fi
    
    if ! tailscale status >/dev/null 2>&1; then
        log_error "Tailscale is not connected"
        log_info "Connect with: sudo tailscale up"
        exit 1
    fi
    
    local status
    status=$(tailscale status --json | jq -r '.BackendState')
    
    if [[ "$status" != "Running" ]]; then
        log_error "Tailscale is not running (status: $status)"
        log_info "Connect with: sudo tailscale up"
        exit 1
    fi
    
    log_info "✓ Tailscale is connected and running"
    
    # Show current IP and hostname
    local tailscale_ip
    local tailscale_hostname
    tailscale_ip=$(tailscale ip)
    tailscale_hostname=$(tailscale status --json | jq -r '.Self.DNSName' | sed 's/\\.$//')
    
    log_info "Tailscale IP: $tailscale_ip"
    log_info "Tailscale hostname: $tailscale_hostname"
}

# Check if Funnel is available
check_funnel_availability() {
    log_header "Checking Funnel availability..."
    
    if tailscale funnel status >/dev/null 2>&1; then
        log_info "✓ Tailscale Funnel is available"
        
        # Show current Funnel status
        log_info "Current Funnel status:"
        tailscale funnel status
    else
        log_warn "Tailscale Funnel may not be available in your region"
        log_info "Funnel is required for public HTTPS access"
        log_info "Check https://tailscale.com/kb/1223/funnel for availability"
        
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Check if Apache is running and configured
check_apache_status() {
    log_header "Checking Apache status..."
    
    if ! systemctl is-active --quiet apache2; then
        log_error "Apache2 is not running"
        log_info "Start with: sudo systemctl start apache2"
        exit 1
    fi
    
    log_info "✓ Apache2 is running"
    
    # Check if port 80 is available
    if ss -tulpn | grep ":80 " | grep -q apache2; then
        log_info "✓ Apache2 is listening on port 80"
    else
        log_warn "Apache2 may not be listening on port 80"
    fi
    
    # Test local connection
    if curl -s -I http://127.0.0.1 | head -1 | grep -q "HTTP"; then
        log_info "✓ Apache is responding locally"
    else
        log_error "Apache is not responding on localhost"
        exit 1
    fi
}

# Configure Tailscale Serve
configure_serve() {
    log_header "Configuring Tailscale Serve..."
    
    # Configure serve to forward HTTPS traffic to Apache on port 80
    if sudo tailscale serve https / http://127.0.0.1:80; then
        log_info "✓ Configured Tailscale Serve to forward HTTPS to Apache"
    else
        log_error "Failed to configure Tailscale Serve"
        exit 1
    fi
    
    # Show serve status
    log_info "Current Serve configuration:"
    sudo tailscale serve status
}

# Enable Funnel
enable_funnel() {
    log_header "Enabling Tailscale Funnel..."
    
    if sudo tailscale funnel https on; then
        log_info "✓ Enabled Tailscale Funnel for HTTPS"
    else
        log_error "Failed to enable Tailscale Funnel"
        exit 1
    fi
    
    # Show funnel status
    log_info "Current Funnel configuration:"
    sudo tailscale funnel status
}

# Test public access
test_public_access() {
    log_header "Testing public access..."
    
    local tailscale_hostname
    tailscale_hostname=$(tailscale status --json | jq -r '.Self.DNSName' | sed 's/\\.$//')
    local public_url="https://$tailscale_hostname"
    
    log_info "Testing public URL: $public_url"
    
    # Wait a moment for funnel to propagate
    sleep 5
    
    if curl -s -I "$public_url" | head -1 | grep -q "HTTP"; then
        log_info "✓ Public URL is accessible"
        echo ""
        echo "=========================================="
        echo "SUCCESS: Headscale is publicly accessible!"
        echo "=========================================="
        echo "Public URL: $public_url"
        echo "=========================================="
    else
        log_warn "Public URL may not be immediately accessible"
        log_info "This can take a few minutes to propagate"
        log_info "Try accessing: $public_url"
    fi
}

# Show configuration summary
show_summary() {
    local tailscale_hostname
    tailscale_hostname=$(tailscale status --json | jq -r '.Self.DNSName' | sed 's/\\.$//')
    local tailscale_ip
    tailscale_ip=$(tailscale ip)
    
    echo ""
    echo "=========================================="
    echo "TAILSCALE FUNNEL CONFIGURATION SUMMARY"
    echo "=========================================="
    echo ""
    echo "Tailscale Node:"
    echo "  IP: $tailscale_ip"
    echo "  Hostname: $tailscale_hostname"
    echo ""
    echo "Public Access:"
    echo "  URL: https://$tailscale_hostname"
    echo "  Status: $(tailscale funnel status --json 2>/dev/null | jq -r '.Funnel."443".SrcAddr // "Enabled"' 2>/dev/null || echo 'Unknown')"
    echo ""
    echo "Private Access (Tailnet only):"
    echo "  Headplane UI: http://$tailscale_ip:3000"
    echo ""
    echo "Commands to manage Funnel:"
    echo "  View status: sudo tailscale funnel status"
    echo "  Disable: sudo tailscale funnel https off"
    echo "  Re-enable: sudo tailscale funnel https on"
    echo ""
    echo "=========================================="
}

# Disable funnel (for --disable flag)
disable_funnel() {
    log_header "Disabling Tailscale Funnel..."
    
    if sudo tailscale funnel https off; then
        log_info "✓ Disabled Tailscale Funnel"
    else
        log_warn "Failed to disable Funnel or already disabled"
    fi
    
    if sudo tailscale serve reset; then
        log_info "✓ Reset Tailscale Serve configuration"
    else
        log_warn "Failed to reset Serve configuration"
    fi
    
    log_info "Headscale is now only accessible on the tailnet"
}

# Main function
main() {
    local action="enable"
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --disable)
                action="disable"
                shift
                ;;
            --help|-h)
                action="help"
                shift
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    case $action in
        help)
            echo "Tailscale Funnel Setup Script"
            echo ""
            echo "Configures Tailscale Funnel to expose Headscale publicly via HTTPS."
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --disable    Disable Funnel (make Headscale private)"
            echo "  --help, -h   Show this help"
            echo ""
            echo "Examples:"
            echo "  $0              # Enable public access"
            echo "  $0 --disable    # Disable public access"
            echo ""
            echo "Prerequisites:"
            echo "  - Tailscale must be connected"
            echo "  - Apache must be running on port 80"
            echo "  - Funnel must be available in your region"
            echo ""
            exit 0
            ;;
        disable)
            echo "=========================================="
            echo "Disabling Tailscale Funnel"
            echo "=========================================="
            disable_funnel
            exit 0
            ;;
        enable)
            echo "=========================================="
            echo "Setting up Tailscale Funnel"
            echo "=========================================="
            
            check_tailscale_status
            check_funnel_availability
            check_apache_status
            configure_serve
            enable_funnel
            test_public_access
            show_summary
            ;;
    esac
}

# Run main function
main "$@"