#!/bin/bash
# Comprehensive Test Script for Headscale Setup
# Tests all components and functionality

set -e

# Configuration
HEADSCALE_DIR="/opt/headscale"
TEST_USER="test-user"
TEST_KEY_FILE=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
TEST_RESULTS=()

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
    echo -e "${BLUE}[TEST]${NC} $1"
}

# Test result functions
test_pass() {
    ((TESTS_PASSED++))
    TEST_RESULTS+=("✓ PASS: $1")
    log_info "✓ PASS: $1"
}

test_fail() {
    ((TESTS_FAILED++))
    TEST_RESULTS+=("✗ FAIL: $1")
    log_error "✗ FAIL: $1"
}

test_skip() {
    TEST_RESULTS+=("- SKIP: $1")
    log_warn "- SKIP: $1"
}

# Test Docker and containers
test_docker() {
    log_header "Testing Docker and containers..."
    
    # Test Docker daemon
    if docker ps >/dev/null 2>&1; then
        test_pass "Docker daemon is running"
    else
        test_fail "Docker daemon is not accessible"
        return 1
    fi
    
    # Test Docker Compose
    if docker compose version >/dev/null 2>&1; then
        test_pass "Docker Compose is available"
    else
        test_fail "Docker Compose is not available"
    fi
    
    # Test Headscale containers
    if sudo -u headscale docker compose -f "$HEADSCALE_DIR/docker-compose.yml" ps | grep -q "headscale.*Up"; then
        test_pass "Headscale container is running"
    else
        test_fail "Headscale container is not running"
    fi
    
    if sudo -u headscale docker compose -f "$HEADSCALE_DIR/docker-compose.yml" ps | grep -q "headplane.*Up"; then
        test_pass "Headplane container is running"
    else
        test_fail "Headplane container is not running"
    fi
}

# Test Headscale API
test_headscale_api() {
    log_header "Testing Headscale API..."
    
    # Test local HTTP connection
    if curl -s -I http://127.0.0.1:8080 | head -1 | grep -q "200\|404"; then
        test_pass "Headscale API is responding on port 8080"
    else
        test_fail "Headscale API is not responding on port 8080"
    fi
    
    # Test users endpoint
    local users_response
    users_response=$(sudo -u headscale docker compose -f "$HEADSCALE_DIR/docker-compose.yml" exec -T headscale headscale users list 2>/dev/null || echo "error")
    
    if [[ "$users_response" != "error" ]]; then
        test_pass "Headscale users command works"
    else
        test_fail "Headscale users command failed"
    fi
}

# Test Apache reverse proxy
test_apache() {
    log_header "Testing Apache reverse proxy..."
    
    # Test Apache service
    if systemctl is-active --quiet apache2; then
        test_pass "Apache2 service is running"
    else
        test_fail "Apache2 service is not running"
        return 1
    fi
    
    # Test Apache configuration
    if apache2ctl configtest >/dev/null 2>&1; then
        test_pass "Apache configuration is valid"
    else
        test_fail "Apache configuration is invalid"
    fi
    
    # Test HTTP response
    if curl -s -I http://127.0.0.1 | head -1 | grep -q "200\|404"; then
        test_pass "Apache is responding on port 80"
    else
        test_fail "Apache is not responding on port 80"
    fi
    
    # Test Headscale site configuration
    if [[ -f "/etc/apache2/sites-enabled/headscale.conf" ]]; then
        test_pass "Headscale Apache site is enabled"
    else
        test_fail "Headscale Apache site is not enabled"
    fi
    
    # Test required Apache modules
    local required_modules=("proxy" "proxy_http" "proxy_wstunnel" "rewrite" "headers")
    local missing_modules=()
    
    for module in "${required_modules[@]}"; do
        if apache2ctl -M 2>/dev/null | grep -q "${module}_module"; then
            test_pass "Apache module enabled: $module"
        else
            test_fail "Apache module not enabled: $module"
            missing_modules+=("$module")
        fi
    done
    
    if [[ ${#missing_modules[@]} -gt 0 ]]; then
        log_info "Enable missing modules with:"
        for module in "${missing_modules[@]}"; do
            log_info "  sudo a2enmod $module"
        done
        log_info "Then reload: sudo systemctl reload apache2"
    fi
}

# Test Tailscale connection
test_tailscale() {
    log_header "Testing Tailscale..."
    
    # Test Tailscale installation
    if command -v tailscale >/dev/null 2>&1; then
        test_pass "Tailscale is installed"
    else
        test_fail "Tailscale is not installed"
        return 1
    fi
    
    # Test Tailscale connection
    if tailscale status >/dev/null 2>&1; then
        local status
        status=$(tailscale status --json | jq -r '.BackendState')
        
        if [[ "$status" == "Running" ]]; then
            test_pass "Tailscale is connected and running"
            
            local tailscale_ip
            tailscale_ip=$(tailscale ip)
            log_info "Tailscale IP: $tailscale_ip"
            
        else
            test_fail "Tailscale is not running (status: $status)"
        fi
    else
        test_fail "Tailscale is not authenticated"
        log_info "Connect with: sudo tailscale up"
    fi
}

# Test Tailscale Funnel
test_funnel() {
    log_header "Testing Tailscale Funnel..."
    
    # Check if Funnel is configured
    if tailscale funnel status >/dev/null 2>&1; then
        local funnel_output
        funnel_output=$(tailscale funnel status)
        
        if echo "$funnel_output" | grep -q "https://"; then
            test_pass "Tailscale Funnel is enabled"
            
            # Extract public URL
            local public_url
            public_url=$(echo "$funnel_output" | grep "https://" | head -1 | awk '{print $1}')
            log_info "Public URL: $public_url"
            
            # Test public access
            if curl -s -I "$public_url" --max-time 10 | head -1 | grep -q "200\|404"; then
                test_pass "Public URL is accessible"
            else
                test_fail "Public URL is not accessible"
            fi
            
        else
            test_skip "Tailscale Funnel is not configured"
        fi
    else
        test_skip "Tailscale Funnel is not available or configured"
    fi
}

# Test Headplane web UI
test_headplane() {
    log_header "Testing Headplane web UI..."
    
    # Get Tailscale IP for private access
    if command -v tailscale >/dev/null 2>&1 && tailscale status >/dev/null 2>&1; then
        local tailscale_ip
        tailscale_ip=$(tailscale ip 2>/dev/null || echo "")
        
        if [[ -n "$tailscale_ip" ]]; then
            # Test Headplane on Tailscale IP
            if curl -s -I "http://$tailscale_ip:3000" --max-time 5 | head -1 | grep -q "200"; then
                test_pass "Headplane UI is accessible on tailnet"
                log_info "Headplane URL: http://$tailscale_ip:3000"
            else
                test_fail "Headplane UI is not accessible on tailnet"
            fi
        else
            test_skip "Cannot determine Tailscale IP"
        fi
    else
        test_skip "Tailscale not available for Headplane test"
    fi
    
    # Test if Headplane container is healthy
    local container_status
    container_status=$(sudo -u headscale docker compose -f "$HEADSCALE_DIR/docker-compose.yml" ps headplane 2>/dev/null | tail -1 | awk '{print $4}' || echo "error")
    
    if [[ "$container_status" == "Up" ]]; then
        test_pass "Headplane container is healthy"
    else
        test_fail "Headplane container is not healthy (status: $container_status)"
    fi
}

# Test iOS authentication fix
test_ios_fix() {
    log_header "Testing iOS authentication fix..."
    
    # Test iOS user agent handling
    local ios_response
    ios_response=$(curl -s -w "%{http_code}" -o /dev/null \
        -H "User-Agent: Tailscale iOS/1.50.0" \
        "http://127.0.0.1/key?key=test-key-for-ios-check" 2>/dev/null || echo "error")
    
    if [[ "$ios_response" =~ ^[0-9]{3}$ ]] && [[ "$ios_response" != "error" ]]; then
        test_pass "iOS user agent handling works (HTTP $ios_response)"
    else
        test_fail "iOS user agent handling failed"
    fi
    
    # Check Apache rewrite configuration
    if grep -q "tailscale.*ios" /etc/apache2/sites-enabled/headscale.conf 2>/dev/null; then
        test_pass "iOS rewrite rule is configured"
    else
        test_fail "iOS rewrite rule is not found in configuration"
    fi
    
    # Check if mod_rewrite is enabled
    if apache2ctl -M 2>/dev/null | grep -q "rewrite_module"; then
        test_pass "Apache mod_rewrite is enabled"
    else
        test_fail "Apache mod_rewrite is not enabled"
    fi
}

# Test WebSocket support
test_websocket() {
    log_header "Testing WebSocket support..."
    
    # Test WebSocket upgrade capability
    local ws_response
    ws_response=$(curl -s -I \
        -H "Connection: Upgrade" \
        -H "Upgrade: websocket" \
        "http://127.0.0.1/ts2021" 2>/dev/null | head -1 || echo "error")
    
    if [[ "$ws_response" =~ HTTP ]] && [[ "$ws_response" != "error" ]]; then
        test_pass "WebSocket upgrade endpoint responds"
    else
        test_fail "WebSocket upgrade endpoint not responding"
    fi
    
    # Check if mod_proxy_wstunnel is enabled
    if apache2ctl -M 2>/dev/null | grep -q "proxy_wstunnel_module"; then
        test_pass "Apache mod_proxy_wstunnel is enabled"
    else
        test_fail "Apache mod_proxy_wstunnel is not enabled"
    fi
}

# Test network connectivity
test_network() {
    log_header "Testing network connectivity..."
    
    # Test internet connectivity
    if curl -s --connect-timeout 5 https://www.google.com >/dev/null; then
        test_pass "Internet connectivity works"
    else
        test_fail "No internet connectivity"
    fi
    
    # Test Docker Hub connectivity
    if curl -s --connect-timeout 5 https://registry-1.docker.io >/dev/null; then
        test_pass "Docker Hub is accessible"
    else
        test_warn "Docker Hub may not be accessible"
    fi
    
    # Test port availability
    local ports=(80 443 8080 3000 50443)
    
    for port in "${ports[@]}"; do
        if ss -tulpn | grep ":$port " >/dev/null 2>&1; then
            local service
            service=$(ss -tulpn | grep ":$port " | awk '{print $7}' | cut -d'"' -f2 | head -1)
            test_pass "Port $port is in use (by: $service)"
        else
            test_skip "Port $port is available"
        fi
    done
}

# Create test user and auth key
create_test_auth_key() {
    log_header "Creating test authentication key..."
    
    if [[ -f "./scripts/create-auth-key.sh" ]]; then
        # Create test user and get auth key
        local auth_key_output
        auth_key_output=$(./scripts/create-auth-key.sh --user "$TEST_USER" --expiration 5m 2>/dev/null || echo "error")
        
        if [[ "$auth_key_output" != "error" ]] && echo "$auth_key_output" | grep -q "Auth key created"; then
            # Extract auth key from output
            local auth_key
            auth_key=$(echo "$auth_key_output" | grep -A 5 "AUTH KEY FOR USER" | tail -1 | head -1)
            
            if [[ -n "$auth_key" ]] && [[ "$auth_key" != "==========================================" ]]; then
                TEST_KEY_FILE="/tmp/test-auth-key-$$"
                echo "$auth_key" > "$TEST_KEY_FILE"
                test_pass "Created test auth key for user: $TEST_USER"
                log_info "Auth key saved to: $TEST_KEY_FILE"
            else
                test_fail "Could not extract auth key from output"
            fi
        else
            test_fail "Could not create test auth key"
        fi
    else
        test_skip "create-auth-key.sh script not found"
    fi
}

# Test Docker test client
test_docker_client() {
    log_header "Testing Docker test client..."
    
    if [[ -d "./test-client" ]]; then
        cd test-client
        
        # Build test client
        if docker build -t headscale-test-client . >/dev/null 2>&1; then
            test_pass "Test client Docker image built successfully"
        else
            test_fail "Failed to build test client Docker image"
            cd ..
            return 1
        fi
        
        # Test basic functionality (without connecting to avoid conflicts)
        if docker run --rm headscale-test-client tailscale version >/dev/null 2>&1; then
            test_pass "Test client Tailscale binary works"
        else
            test_fail "Test client Tailscale binary not working"
        fi
        
        cd ..
    else
        test_skip "Test client directory not found"
    fi
}

# Show test results summary
show_results() {
    echo ""
    echo "=========================================="
    echo "TEST RESULTS SUMMARY"
    echo "=========================================="
    echo ""
    
    for result in "${TEST_RESULTS[@]}"; do
        echo "$result"
    done
    
    echo ""
    echo "=========================================="
    echo "TOTAL: $((TESTS_PASSED + TESTS_FAILED)) tests"
    echo "PASSED: $TESTS_PASSED"
    echo "FAILED: $TESTS_FAILED"
    echo "=========================================="
    
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_info "🎉 All tests passed! Your Headscale setup is working correctly."
    else
        log_error "❌ $TESTS_FAILED test(s) failed. Please review the failures above."
        
        if [[ $TESTS_PASSED -gt 0 ]]; then
            log_info "✅ $TESTS_PASSED test(s) passed successfully."
        fi
    fi
    
    # Cleanup
    if [[ -n "$TEST_KEY_FILE" ]] && [[ -f "$TEST_KEY_FILE" ]]; then
        rm -f "$TEST_KEY_FILE"
    fi
}

# Show system information
show_system_info() {
    log_header "System Information"
    echo ""
    echo "OS: $(lsb_release -d 2>/dev/null | cut -f2 || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo "Kernel: $(uname -r)"
    echo "Docker: $(docker --version 2>/dev/null || echo 'Not installed')"
    echo "Docker Compose: $(docker compose version 2>/dev/null || echo 'Not available')"
    echo "Apache: $(apache2 -v 2>/dev/null | head -1 || echo 'Not installed')"
    echo "Tailscale: $(tailscale version 2>/dev/null || echo 'Not installed')"
    
    if command -v tailscale >/dev/null 2>&1 && tailscale status >/dev/null 2>&1; then
        echo "Tailscale IP: $(tailscale ip 2>/dev/null || echo 'Not connected')"
        echo "Tailscale Hostname: $(tailscale status --json 2>/dev/null | jq -r '.Self.DNSName' | sed 's/\.$//' || echo 'Not available')"
    fi
    echo ""
}

# Main function
main() {
    local run_all=true
    local specific_tests=()
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --system-info)
                show_system_info
                exit 0
                ;;
            --help|-h)
                echo "Headscale Setup Test Script"
                echo ""
                echo "Tests all components of the Headscale + Tailscale Funnel setup."
                echo ""
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  --system-info    Show system information only"
                echo "  --help, -h       Show this help"
                echo ""
                echo "Test Categories:"
                echo "  - Docker containers and services"
                echo "  - Headscale API functionality"
                echo "  - Apache reverse proxy"
                echo "  - Tailscale connection"
                echo "  - Tailscale Funnel public access"
                echo "  - Headplane web UI"
                echo "  - iOS authentication fix"
                echo "  - WebSocket support"
                echo "  - Network connectivity"
                echo "  - Docker test client"
                echo ""
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                exit 1
                ;;
        esac
    done
    
    echo "=========================================="
    echo "Headscale Setup Comprehensive Test"
    echo "=========================================="
    
    show_system_info
    
    # Run all tests
    test_docker
    echo ""
    test_headscale_api
    echo ""
    test_apache
    echo ""
    test_tailscale
    echo ""
    test_funnel
    echo ""
    test_headplane
    echo ""
    test_ios_fix
    echo ""
    test_websocket
    echo ""
    test_network
    echo ""
    create_test_auth_key
    echo ""
    test_docker_client
    
    show_results
    
    # Exit with appropriate code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        exit 0
    else
        exit 1
    fi
}

# Run main function
main "$@"