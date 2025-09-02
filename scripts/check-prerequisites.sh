#!/bin/bash
# Prerequisites Check Script for Headscale + Tailscale Funnel Setup
# Verifies system requirements and dependencies

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
    echo -e "${BLUE}[CHECK]${NC} $1"
}

# Check functions
check_os() {
    log_header "Checking operating system..."
    
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        log_info "OS: $PRETTY_NAME"
        
        if [[ "$ID" == "ubuntu" ]] || [[ "$ID" == "debian" ]]; then
            log_info "✓ Supported OS detected"
        else
            log_warn "⚠ Untested OS - Ubuntu/Debian recommended"
        fi
    else
        log_error "✗ Cannot determine OS"
        return 1
    fi
}

check_memory() {
    log_header "Checking memory..."
    
    local mem_gb
    mem_gb=$(free -g | awk '/^Mem:/ {print $2}')
    
    if [[ "$mem_gb" -ge 1 ]]; then
        log_info "✓ Memory: ${mem_gb}GB (sufficient)"
    else
        log_warn "⚠ Memory: ${mem_gb}GB (minimum 1GB recommended)"
    fi
}

check_disk_space() {
    log_header "Checking disk space..."
    
    local space_gb
    space_gb=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    
    if [[ "$space_gb" -ge 10 ]]; then
        log_info "✓ Free space: ${space_gb}GB (sufficient)"
    else
        log_warn "⚠ Free space: ${space_gb}GB (minimum 10GB recommended)"
    fi
}

check_docker() {
    log_header "Checking Docker..."
    
    if command -v docker >/dev/null 2>&1; then
        local docker_version
        docker_version=$(docker --version)
        log_info "✓ Docker installed: $docker_version"
        
        if docker ps >/dev/null 2>&1; then
            log_info "✓ Docker daemon running"
        else
            log_error "✗ Docker daemon not running or no permission"
            log_info "Try: sudo systemctl start docker"
            log_info "Or add user to docker group: sudo usermod -aG docker \$USER"
            return 1
        fi
    else
        log_error "✗ Docker not installed"
        log_info "Install with: curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh get-docker.sh"
        return 1
    fi
}

check_docker_compose() {
    log_header "Checking Docker Compose..."
    
    if docker compose version >/dev/null 2>&1; then
        local compose_version
        compose_version=$(docker compose version)
        log_info "✓ Docker Compose (plugin): $compose_version"
    elif command -v docker-compose >/dev/null 2>&1; then
        local compose_version
        compose_version=$(docker-compose --version)
        log_info "✓ Docker Compose (standalone): $compose_version"
    else
        log_error "✗ Docker Compose not available"
        log_info "Docker Compose should be included with modern Docker installations"
        return 1
    fi
}

check_apache() {
    log_header "Checking Apache2..."
    
    if command -v apache2 >/dev/null 2>&1; then
        local apache_version
        apache_version=$(apache2 -v | head -1)
        log_info "✓ Apache2 installed: $apache_version"
        
        if systemctl is-active --quiet apache2; then
            log_info "✓ Apache2 service running"
        else
            log_warn "⚠ Apache2 service not running"
            log_info "Start with: sudo systemctl start apache2"
        fi
        
        # Check required modules
        local modules_missing=()
        
        for module in proxy proxy_http proxy_wstunnel rewrite headers; do
            if apache2ctl -M 2>/dev/null | grep -q "${module}_module"; then
                log_info "✓ Apache module enabled: $module"
            else
                log_warn "⚠ Apache module not enabled: $module"
                modules_missing+=("$module")
            fi
        done
        
        if [[ ${#modules_missing[@]} -gt 0 ]]; then
            log_info "Enable missing modules with:"
            for module in "${modules_missing[@]}"; do
                log_info "  sudo a2enmod $module"
            done
            log_info "Then reload: sudo systemctl reload apache2"
        fi
        
    else
        log_error "✗ Apache2 not installed"
        log_info "Install with: sudo apt install -y apache2"
        return 1
    fi
}

check_tailscale() {
    log_header "Checking Tailscale..."
    
    if command -v tailscale >/dev/null 2>&1; then
        local tailscale_version
        tailscale_version=$(tailscale version)
        log_info "✓ Tailscale installed: $tailscale_version"
        
        if tailscale status >/dev/null 2>&1; then
            local tailscale_status
            tailscale_status=$(tailscale status --json | jq -r '.BackendState')
            
            if [[ "$tailscale_status" == "Running" ]]; then
                log_info "✓ Tailscale connected and running"
                
                local tailscale_ip
                tailscale_ip=$(tailscale ip)
                log_info "Tailscale IP: $tailscale_ip"
                
                # Check Funnel capability
                if tailscale funnel status >/dev/null 2>&1; then
                    log_info "✓ Tailscale Funnel available"
                else
                    log_warn "⚠ Tailscale Funnel may not be available in your region"
                    log_info "Funnel is required for public HTTPS access"
                fi
                
            else
                log_warn "⚠ Tailscale not connected (status: $tailscale_status)"
                log_info "Connect with: sudo tailscale up"
            fi
        else
            log_warn "⚠ Tailscale not authenticated"
            log_info "Connect with: sudo tailscale up"
        fi
    else
        log_error "✗ Tailscale not installed"
        log_info "Install with: curl -fsSL https://tailscale.com/install.sh | sh"
        return 1
    fi
}

check_ports() {
    log_header "Checking port availability..."
    
    local ports=(80 443 8080 3000 50443)
    
    for port in "${ports[@]}"; do
        if ss -tulpn | grep ":$port " >/dev/null 2>&1; then
            local service
            service=$(ss -tulpn | grep ":$port " | awk '{print $7}' | cut -d'"' -f2)
            log_warn "⚠ Port $port in use by: $service"
        else
            log_info "✓ Port $port available"
        fi
    done
}

check_network_connectivity() {
    log_header "Checking network connectivity..."
    
    if curl -s --connect-timeout 5 https://www.google.com >/dev/null; then
        log_info "✓ Internet connectivity working"
    else
        log_error "✗ No internet connectivity"
        return 1
    fi
    
    if curl -s --connect-timeout 5 https://registry-1.docker.io >/dev/null; then
        log_info "✓ Docker Hub accessible"
    else
        log_warn "⚠ Docker Hub may not be accessible"
    fi
}

check_permissions() {
    log_header "Checking permissions..."
    
    if [[ "$EUID" -eq 0 ]]; then
        log_warn "⚠ Running as root - consider using a regular user"
    fi
    
    if groups | grep -q docker; then
        log_info "✓ User in docker group"
    else
        log_warn "⚠ User not in docker group"
        log_info "Add with: sudo usermod -aG docker \$USER (requires logout/login)"
    fi
    
    if sudo -n true 2>/dev/null; then
        log_info "✓ Sudo access available"
    else
        log_warn "⚠ Sudo may require password"
    fi
}

# Main function
main() {
    echo "=========================================="
    echo "Headscale + Tailscale Funnel Prerequisites Check"
    echo "=========================================="
    echo ""
    
    local failed_checks=0
    
    # Run all checks
    check_os || ((failed_checks++))
    echo ""
    check_memory || ((failed_checks++))
    echo ""
    check_disk_space || ((failed_checks++))
    echo ""
    check_docker || ((failed_checks++))
    echo ""
    check_docker_compose || ((failed_checks++))
    echo ""
    check_apache || ((failed_checks++))
    echo ""
    check_tailscale || ((failed_checks++))
    echo ""
    check_ports || ((failed_checks++))
    echo ""
    check_network_connectivity || ((failed_checks++))
    echo ""
    check_permissions || ((failed_checks++))
    
    echo ""
    echo "=========================================="
    
    if [[ $failed_checks -eq 0 ]]; then
        log_info "✓ All prerequisite checks passed!"
        log_info "You can proceed with the Headscale setup."
    else
        log_error "✗ $failed_checks prerequisite check(s) failed"
        log_info "Please address the issues above before proceeding."
        exit 1
    fi
    
    echo "=========================================="
}

# Help text
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    echo "Headscale + Tailscale Funnel Prerequisites Checker"
    echo ""
    echo "This script checks system requirements for:"
    echo "  - Operating system compatibility"
    echo "  - Memory and disk space"
    echo "  - Docker and Docker Compose"
    echo "  - Apache2 web server"
    echo "  - Tailscale installation and authentication"
    echo "  - Network connectivity"
    echo "  - Required ports availability"
    echo "  - User permissions"
    echo ""
    echo "Usage: $0"
    echo ""
    exit 0
fi

# Run main function
main