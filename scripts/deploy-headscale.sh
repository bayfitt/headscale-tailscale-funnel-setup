#!/bin/bash
# Deploy Headscale with Docker Compose
# Main deployment script that handles installation and configuration

set -e

# Configuration
HEADSCALE_DIR="/opt/headscale"
APACHE_SITES="/etc/apache2/sites-available"
APACHE_SITES_ENABLED="/etc/apache2/sites-enabled"

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
    echo -e "${BLUE}[DEPLOY]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        log_error "This script must be run as root"
        log_info "Run with: sudo $0"
        exit 1
    fi
}

# Create headscale user and directories
setup_user_and_directories() {
    log_header "Setting up user and directories..."
    
    # Create headscale user if it doesn't exist
    if ! id "headscale" &>/dev/null; then
        useradd -r -s /bin/false -d /var/lib/headscale headscale
        log_info "✓ Created headscale user"
    else
        log_info "✓ Headscale user already exists"
    fi
    
    # Create directories
    mkdir -p "$HEADSCALE_DIR"
    mkdir -p "$HEADSCALE_DIR/headscale-config"
    mkdir -p "$HEADSCALE_DIR/headscale-data"
    mkdir -p "$HEADSCALE_DIR/headplane-data"
    
    # Set ownership
    chown -R headscale:headscale "$HEADSCALE_DIR"
    chmod 755 "$HEADSCALE_DIR"
    
    log_info "✓ Created and configured directories"
}

# Copy configuration files
copy_configurations() {
    log_header "Copying configuration files..."
    
    # Copy Docker Compose configuration
    if [[ -f "config/docker-compose.yml" ]]; then
        cp config/docker-compose.yml "$HEADSCALE_DIR/"
        chown headscale:headscale "$HEADSCALE_DIR/docker-compose.yml"
        log_info "✓ Copied Docker Compose configuration"
    else
        log_error "config/docker-compose.yml not found"
        exit 1
    fi
    
    # Copy Headscale configuration
    if [[ -f "config/headscale-config.yaml" ]]; then
        cp config/headscale-config.yaml "$HEADSCALE_DIR/headscale-config/config.yaml"
        chown headscale:headscale "$HEADSCALE_DIR/headscale-config/config.yaml"
        log_info "✓ Copied Headscale configuration"
    else
        log_error "config/headscale-config.yaml not found"
        exit 1
    fi
    
    # Copy Apache configuration
    if [[ -f "config/apache-headscale.conf" ]]; then
        cp config/apache-headscale.conf "$APACHE_SITES/headscale.conf"
        log_info "✓ Copied Apache configuration"
    else
        log_error "config/apache-headscale.conf not found"
        exit 1
    fi
}

# Enable and configure Apache
configure_apache() {
    log_header "Configuring Apache..."
    
    # Enable required Apache modules
    local modules=("proxy" "proxy_http" "proxy_wstunnel" "rewrite" "headers")
    
    for module in "${modules[@]}"; do
        if a2enmod "$module" >/dev/null 2>&1; then
            log_info "✓ Enabled Apache module: $module"
        else
            log_warn "Module $module may already be enabled"
        fi
    done
    
    # Disable default site
    if a2dissite 000-default >/dev/null 2>&1; then
        log_info "✓ Disabled default Apache site"
    fi
    
    # Enable Headscale site
    if a2ensite headscale >/dev/null 2>&1; then
        log_info "✓ Enabled Headscale Apache site"
    else
        log_error "Failed to enable Headscale site"
        exit 1
    fi
    
    # Test Apache configuration
    if apache2ctl configtest >/dev/null 2>&1; then
        log_info "✓ Apache configuration test passed"
    else
        log_error "Apache configuration test failed"
        apache2ctl configtest
        exit 1
    fi
    
    # Reload Apache
    systemctl reload apache2
    log_info "✓ Reloaded Apache configuration"
}

# Start Headscale services
start_services() {
    log_header "Starting Headscale services..."
    
    # Change to Headscale directory
    cd "$HEADSCALE_DIR"
    
    # Pull latest images
    sudo -u headscale docker compose pull
    log_info "✓ Pulled latest Docker images"
    
    # Start services
    if sudo -u headscale docker compose up -d; then
        log_info "✓ Started Headscale services"
    else
        log_error "Failed to start Headscale services"
        exit 1
    fi
    
    # Wait for services to start
    log_info "Waiting for services to start..."
    sleep 10
    
    # Check service status
    sudo -u headscale docker compose ps
}

# Verify deployment
verify_deployment() {
    log_header "Verifying deployment..."
    
    # Check if containers are running
    if sudo -u headscale docker compose -f "$HEADSCALE_DIR/docker-compose.yml" ps | grep -q "Up"; then
        log_info "✓ Headscale containers are running"
    else
        log_error "Headscale containers are not running"
        return 1
    fi
    
    # Check if Headscale is responding
    if curl -s -I http://127.0.0.1:8080 | head -1 | grep -q "HTTP"; then
        log_info "✓ Headscale is responding on port 8080"
    else
        log_warn "Headscale may not be responding on port 8080"
    fi
    
    # Check if Apache is responding
    if curl -s -I http://127.0.0.1 | head -1 | grep -q "HTTP"; then
        log_info "✓ Apache is responding on port 80"
    else
        log_warn "Apache may not be responding on port 80"
    fi
}

# Show next steps
show_next_steps() {
    log_header "Deployment completed successfully!"
    echo ""
    echo "=========================================="
    echo "NEXT STEPS:"
    echo "=========================================="
    echo ""
    echo "1. Configure Tailscale Funnel:"
    echo "   sudo tailscale serve 80"
    echo "   sudo tailscale funnel 80 on"
    echo ""
    echo "2. Create your first user and auth key:"
    echo "   ./scripts/create-auth-key.sh --user yourname --expiration 1h"
    echo ""
    echo "3. Access Headplane web UI:"
    echo "   http://$(tailscale ip):3000"
    echo ""
    echo "4. Test your setup:"
    echo "   ./scripts/test-setup.sh"
    echo ""
    echo "=========================================="
    echo "Server URL: https://$(hostname).$(tailscale status --json | jq -r '.MagicDNSSuffix')"
    echo "=========================================="
}

# Main function
main() {
    echo "=========================================="
    echo "Headscale + Tailscale Funnel Deployment"
    echo "=========================================="
    echo ""
    
    check_root
    setup_user_and_directories
    copy_configurations
    configure_apache
    start_services
    verify_deployment
    show_next_steps
}

# Help text
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    echo "Headscale Deployment Script"
    echo ""
    echo "This script deploys Headscale with Docker Compose and configures Apache"
    echo "as a reverse proxy with iOS authentication fixes."
    echo ""
    echo "Prerequisites:"
    echo "  - Docker and Docker Compose installed"
    echo "  - Apache2 installed"
    echo "  - Tailscale installed and authenticated"
    echo "  - Run ./scripts/check-prerequisites.sh first"
    echo ""
    echo "Usage: sudo $0"
    echo ""
    exit 0
fi

# Run main function
main "$@"