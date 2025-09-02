# Tailscale Test Client for Headscale
FROM debian:bookworm-slim

# Install required packages
RUN apt-get update && apt-get install -y \
    curl \
    ca-certificates \
    iptables \
    net-tools \
    iputils-ping \
    dnsutils \
    && rm -rf /var/lib/apt/lists/*

# Install Tailscale
RUN curl -fsSL https://tailscale.com/install.sh | sh

# Create entrypoint script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# Set capabilities for tailscaled
# Note: Will need to run with --privileged or specific caps

ENTRYPOINT ["/entrypoint.sh"]
CMD ["bash"]