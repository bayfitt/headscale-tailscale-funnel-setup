#!/bin/bash
# Tailscale Test Client Entrypoint

echo "=== Tailscale Test Client for Headscale ==="
echo "Starting tailscaled daemon..."

# Start tailscaled in the background
tailscaled --tun=userspace-networking --socks5-server=localhost:1055 &
TAILSCALED_PID=$!

# Wait a moment for tailscaled to start
sleep 2

echo "Tailscaled started (PID: $TAILSCALED_PID)"
echo "Ready to connect to Headscale server"
echo
echo "Available commands:"
echo "  connect <auth_key>  - Connect to Headscale with auth key"
echo "  status              - Show Tailscale status"
echo "  ping <ip>           - Ping another node"
echo "  disconnect          - Disconnect from tailnet"
echo "  help                - Show this help"
echo

# Function to connect
connect() {
    if [ -z "$1" ]; then
        echo "Usage: connect <auth_key>"
        return 1
    fi
    
    echo "Connecting to Headscale with key: $1"
    tailscale up --login-server=https://your-headscale-server.ts.net --authkey="$1" --accept-routes
}

# Function to show status
status() {
    echo "=== Tailscale Status ==="
    tailscale status
    echo
    echo "=== IP Information ==="
    tailscale ip
}

# Function to disconnect
disconnect() {
    echo "Disconnecting from tailnet..."
    tailscale down
}

# Function to show help
help() {
    echo "Available commands:"
    echo "  connect <auth_key>  - Connect to Headscale with auth key"
    echo "  status              - Show Tailscale status"
    echo "  ping <ip>           - Ping another node"
    echo "  disconnect          - Disconnect from tailnet"
    echo "  help                - Show this help"
}

# Export functions
export -f connect status disconnect help

# Keep container running and provide interactive shell
exec "$@"