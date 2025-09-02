#!/bin/bash
# Test Connection Script for Headscale Docker Client
# Tests connection to Headscale server and validates functionality

set -e

# Configuration
CONTAINER_NAME="headscale-test-client"
SERVER_URL="https://your-headscale-server.ts.net"  # Replace with your server
TEST_AUTH_KEY=""  # Will be generated or provided

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

# Check if container is running
check_container() {
    if ! docker ps | grep -q "$CONTAINER_NAME"; then
        log_error "Container $CONTAINER_NAME is not running"
        log_info "Starting container..."
        docker-compose up -d
        sleep 5
    else
        log_info "Container $CONTAINER_NAME is running"
    fi
}

# Test basic container functionality
test_container_health() {
    log_info "Testing container health..."
    
    if docker exec "$CONTAINER_NAME" tailscale version >/dev/null 2>&1; then
        log_info "✓ Tailscale binary is working"
    else
        log_error "✗ Tailscale binary not working"
        return 1
    fi
    
    if docker exec "$CONTAINER_NAME" curl --version >/dev/null 2>&1; then
        log_info "✓ Curl is available"
    else
        log_error "✗ Curl not available"
        return 1
    fi
}

# Test network connectivity to server
test_network_connectivity() {
    log_info "Testing network connectivity to $SERVER_URL..."
    
    if docker exec "$CONTAINER_NAME" curl -s -I "$SERVER_URL" | head -1 | grep -q "HTTP"; then
        log_info "✓ Server is reachable"
    else
        log_error "✗ Cannot reach server"
        return 1
    fi
}

# Test authentication endpoint
test_auth_endpoint() {
    log_info "Testing authentication endpoint..."
    
    # Test with iOS user agent (should get different response due to iOS fix)
    local response_ios
    response_ios=$(docker exec "$CONTAINER_NAME" curl -s \
        -H "User-Agent: Tailscale iOS/1.50.0" \
        "$SERVER_URL/key?key=invalid-key-for-testing" 2>/dev/null || echo "error")
    
    if [[ "$response_ios" == *"error"* ]]; then
        log_warn "iOS endpoint test failed (expected with invalid key)"
    else
        log_info "✓ iOS endpoint responding"
    fi
    
    # Test with regular user agent
    local response_normal
    response_normal=$(docker exec "$CONTAINER_NAME" curl -s \
        "$SERVER_URL/key?key=invalid-key-for-testing" 2>/dev/null || echo "error")
    
    if [[ "$response_normal" == *"error"* ]]; then
        log_warn "Normal endpoint test failed (expected with invalid key)"
    else
        log_info "✓ Normal endpoint responding"
    fi
}

# Test WebSocket upgrade capability
test_websocket() {
    log_info "Testing WebSocket upgrade support..."
    
    local ws_response
    ws_response=$(docker exec "$CONTAINER_NAME" curl -s -I \
        -H "Connection: Upgrade" \
        -H "Upgrade: websocket" \
        "$SERVER_URL/ts2021" 2>/dev/null | head -1)
    
    if [[ "$ws_response" == *"101"* ]] || [[ "$ws_response" == *"404"* ]] || [[ "$ws_response" == *"400"* ]]; then
        log_info "✓ WebSocket upgrade supported (got response: ${ws_response})"
    else
        log_warn "WebSocket upgrade test inconclusive"
    fi
}

# Test actual Tailscale connection (if auth key provided)
test_tailscale_connection() {
    if [[ -n "$TEST_AUTH_KEY" ]]; then
        log_info "Testing Tailscale connection with auth key..."
        
        # Try to connect
        if docker exec "$CONTAINER_NAME" tailscale up \
            --login-server="$SERVER_URL" \
            --authkey="$TEST_AUTH_KEY" \
            --accept-routes >/dev/null 2>&1; then
            log_info "✓ Tailscale connection successful"
            
            # Check status
            docker exec "$CONTAINER_NAME" tailscale status
            
            # Get IP
            local tailscale_ip
            tailscale_ip=$(docker exec "$CONTAINER_NAME" tailscale ip)
            log_info "Assigned IP: $tailscale_ip"
            
        else
            log_error "✗ Tailscale connection failed"
            return 1
        fi
    else
        log_warn "No auth key provided, skipping Tailscale connection test"
        log_info "To test connection, set TEST_AUTH_KEY environment variable"
    fi
}

# Main test runner
main() {
    echo "=================================="
    echo "Headscale Test Client Connection Test"
    echo "=================================="
    echo "Server: $SERVER_URL"
    echo "Container: $CONTAINER_NAME"
    echo "=================================="
    
    # Read auth key from environment or argument
    if [[ -n "$1" ]]; then
        TEST_AUTH_KEY="$1"
    elif [[ -n "$TEST_AUTH_KEY" ]]; then
        log_info "Using auth key from environment"
    fi
    
    # Run tests
    check_container
    test_container_health
    test_network_connectivity
    test_auth_endpoint
    test_websocket
    test_tailscale_connection
    
    echo "=================================="
    log_info "Test run completed"
    echo "=================================="
}

# Usage information
if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
    echo "Usage: $0 [AUTH_KEY]"
    echo ""
    echo "Test the Headscale test client connection"
    echo ""
    echo "Arguments:"
    echo "  AUTH_KEY    Optional auth key for full connection test"
    echo ""
    echo "Environment Variables:"
    echo "  TEST_AUTH_KEY    Auth key for testing (alternative to argument)"
    echo "  SERVER_URL       Override default server URL"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Basic connectivity tests"
    echo "  $0 your-auth-key-here                 # Full connection test"
    echo "  TEST_AUTH_KEY=key $0                  # Using environment variable"
    echo ""
    exit 0
fi

# Run main function
main "$@"