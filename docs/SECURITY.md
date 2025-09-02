# Security Guide

This document covers security considerations and best practices for the Headscale + Tailscale Funnel setup.

## Security Architecture Overview

### Network Security Layers

```
Internet
    │ (HTTPS via Tailscale Funnel)
    │
    ▼
Tailscale Funnel
    │ (Automatic TLS termination)
    │
    ▼  
Apache Reverse Proxy (Port 80)
    │ (HTTP - secure due to Funnel encryption)
    │
    ▼
Headscale Server (Port 8080)
    │ (Container isolation)
    │
    ▼
SQLite Database
    (File system permissions)

Tailnet (Private Network)
    │
    ▼
Headplane Admin UI (Port 3000)
    (Restricted to tailnet access only)
```

## Access Control

### Public Access (via Tailscale Funnel)
- **Endpoint**: HTTPS only via Tailscale Funnel
- **Purpose**: Client coordination and authentication only
- **Protocols**: HTTP API + WebSocket (ts2021)
- **Authentication**: Pre-shared auth keys

### Private Access (Tailnet Only)
- **Endpoint**: Headplane web UI on tailnet IP
- **Purpose**: Administrative functions
- **Access**: Requires tailnet membership
- **Functions**: User management, node monitoring, auth key creation

### Principle of Least Exposure
- Only coordination server exposed publicly
- Administrative interface restricted to private network
- No unnecessary services or ports exposed

## Authentication Security

### Auth Key Management
```bash
# Create time-limited, single-use keys
./scripts/create-auth-key.sh --user username --expiration 1h --reusable false

# Avoid long-lived or reusable keys in production
./scripts/create-auth-key.sh --user username --expiration 5m
```

### Best Practices
1. **Short Expiration**: Use the minimum necessary expiration time
2. **Single-Use**: Prefer non-reusable keys when possible
3. **User Separation**: Create separate users for different purposes
4. **Key Rotation**: Regularly regenerate and distribute new keys
5. **Secure Distribution**: Share keys via secure channels only

### User Management
```bash
# Create users for different purposes
headscale users create production-servers
headscale users create developer-laptops  
headscale users create mobile-devices

# Separate authentication domains
headscale users create company-employees
headscale users create contractors
```

## Network Security

### Firewall Configuration
```bash
# Only allow necessary ports
sudo ufw default deny incoming
sudo ufw default allow outgoing

# SSH access (change default port)
sudo ufw allow 2222/tcp

# HTTP for Tailscale Funnel (if not using host networking)
sudo ufw allow 80/tcp

# Tailscale traffic
sudo ufw allow in on tailscale0
```

### Port Exposure
- **Port 80**: Only accessible via Tailscale Funnel
- **Port 8080**: Bound to localhost only (container internal)
- **Port 3000**: Bound to tailnet IP only
- **Port 443**: Handled by Tailscale Funnel

### Network Isolation
```yaml
# Docker Compose network isolation
networks:
  headscale-network:
    internal: true  # No external access
  
services:
  headscale:
    networks:
      - headscale-network
    ports:
      - "127.0.0.1:8080:8080"  # Localhost only
```

## Container Security

### User Privileges
```bash
# Run containers as non-root user
useradd -r -s /bin/false headscale
chown -R headscale:headscale /opt/headscale
```

### Docker Security
```yaml
# Security-focused Docker Compose
services:
  headscale:
    user: "1000:1000"  # Non-root user
    read_only: true    # Read-only root filesystem
    cap_drop:
      - ALL            # Drop all capabilities
    cap_add:
      - NET_BIND_SERVICE  # Only if needed
    security_opt:
      - no-new-privileges:true
```

### Volume Mounts
```yaml
# Minimal required mounts
volumes:
  - headscale-data:/var/lib/headscale:rw
  - headscale-config:/etc/headscale:ro
  - /dev/null:/root/.ash_history  # Disable shell history
```

## File System Security

### Directory Permissions
```bash
# Secure directory permissions
chmod 750 /opt/headscale
chmod 640 /opt/headscale/headscale-config/config.yaml
chmod 600 /opt/headscale/headscale-data/db.sqlite

# Ownership
chown -R headscale:headscale /opt/headscale
chown root:root /opt/headscale  # Parent directory
```

### Configuration Protection
```bash
# Protect sensitive configuration
chmod 600 /opt/headscale/headscale-config/config.yaml
chmod 600 /opt/headscale/docker-compose.yml

# Apache configuration
chmod 644 /etc/apache2/sites-available/headscale.conf
chown root:root /etc/apache2/sites-available/headscale.conf
```

### Database Security
```bash
# SQLite database permissions
chmod 600 /opt/headscale/headscale-data/db.sqlite
chown headscale:headscale /opt/headscale/headscale-data/db.sqlite

# Backup security
umask 077  # Ensure backups are not world-readable
```

## Transport Security

### TLS Configuration
- **External**: Automatic TLS via Tailscale Funnel
- **Internal**: HTTP acceptable (encrypted by Funnel layer)
- **Client Connections**: End-to-end encrypted via Tailscale protocol

### Certificate Management
- **Automated**: Tailscale Funnel handles certificate lifecycle
- **No Manual Certs**: Reduces configuration errors
- **Domain Validation**: Automatic via Tailscale infrastructure

## Apache Security

### Security Modules
```apache
# Load security modules
LoadModule headers_module modules/mod_headers.so
LoadModule security2_module modules/mod_security2.so
```

### Security Headers
```apache
# Security headers
Header always set X-Content-Type-Options nosniff
Header always set X-Frame-Options DENY  
Header always set X-XSS-Protection "1; mode=block"
Header always set Referrer-Policy "strict-origin-when-cross-origin"
Header always set Content-Security-Policy "default-src 'self'"

# Hide server information
ServerTokens Prod
ServerSignature Off
```

### Request Filtering
```apache
# Block common attack patterns
<LocationMatch "(\.(php|asp|jsp|cgi)|\?|&)">
    Require all denied
</LocationMatch>

# Rate limiting (if mod_evasive available)
DOSHashTableSize    1024
DOSPageCount        2
DOSSiteCount        5
DOSPageInterval     1
DOSSiteInterval     1
DOSBlockingPeriod   600
```

## Logging and Monitoring

### Comprehensive Logging
```apache
# Detailed access logging
LogFormat "%h %l %u %t \"%r\" %>s %O \"%{Referer}i\" \"%{User-Agent}i\" %D" combined_with_time
CustomLog /var/log/apache2/headscale_access.log combined_with_time

# Security event logging  
LogFormat "%{%Y-%m-%d %H:%M:%S}t %h %{User-Agent}i \"%r\" %>s" security
CustomLog /var/log/apache2/headscale_security.log security
```

### System Monitoring
```bash
# Monitor authentication attempts
sudo tail -f /var/log/apache2/headscale_access.log | grep "/key"

# Monitor container logs
sudo -u headscale docker compose -f /opt/headscale/docker-compose.yml logs -f

# System resource monitoring
watch -n 5 'docker stats --no-stream'
```

### Log Rotation
```bash
# Configure logrotate
cat > /etc/logrotate.d/headscale << 'EOF'
/var/log/apache2/headscale_*.log {
    weekly
    rotate 52
    compress
    delaycompress
    missingok
    notifempty
    postrotate
        systemctl reload apache2
    endscript
}
EOF
```

## Secrets Management

### Environment Variables
```bash
# Use environment files for secrets
echo "HEADPLANE_COOKIE_SECRET=$(openssl rand -hex 16)" > /opt/headscale/.env
chmod 600 /opt/headscale/.env
chown headscale:headscale /opt/headscale/.env
```

### Docker Secrets
```yaml
# Use Docker secrets for sensitive data
secrets:
  cookie_secret:
    file: ./cookie_secret.txt
    
services:
  headplane:
    secrets:
      - cookie_secret
    environment:
      COOKIE_SECRET_FILE: /run/secrets/cookie_secret
```

### Auth Key Security
```bash
# Secure auth key generation
umask 077
./scripts/create-auth-key.sh --user production > /tmp/auth_key_$$
chmod 600 /tmp/auth_key_$$

# Secure distribution (example)
scp -P 2222 /tmp/auth_key_$$ user@remote:/tmp/
rm /tmp/auth_key_$$
```

## Update and Patch Management

### Container Updates
```bash
# Regular container updates
sudo -u headscale docker compose -f /opt/headscale/docker-compose.yml pull
sudo -u headscale docker compose -f /opt/headscale/docker-compose.yml up -d

# Security-only updates
sudo apt update && sudo apt upgrade -y
sudo systemctl restart docker
```

### Security Monitoring
- Subscribe to Headscale security announcements
- Monitor CVE databases for Apache and Docker
- Enable automatic security updates for the base system

```bash
# Enable automatic security updates
sudo apt install unattended-upgrades
echo 'Unattended-Upgrade::Automatic-Reboot "false";' >> /etc/apt/apt.conf.d/50unattended-upgrades
```

## Incident Response

### Detection
```bash
# Monitor for suspicious activity
grep -i "error\|fail\|attack" /var/log/apache2/headscale_error.log
sudo ausearch -m avc  # SELinux violations
sudo journalctl --since="1 hour ago" --grep="headscale"
```

### Response Procedures

1. **Immediate Actions**:
   ```bash
   # Disable public access
   sudo tailscale funnel https off
   
   # Stop services if compromised
   sudo -u headscale docker compose -f /opt/headscale/docker-compose.yml stop
   ```

2. **Investigation**:
   ```bash
   # Collect logs
   sudo journalctl --since="24 hours ago" > /tmp/incident_logs.txt
   sudo tar -czf /tmp/apache_logs.tar.gz /var/log/apache2/
   
   # Check for unauthorized changes
   sudo find /opt/headscale -type f -mtime -1 -ls
   ```

3. **Recovery**:
   ```bash
   # Restore from backup
   sudo -u headscale docker compose -f /opt/headscale/docker-compose.yml exec headscale \
     sqlite3 /var/lib/headscale/db.sqlite ".restore /backup/latest.db"
   
   # Regenerate compromised auth keys
   ./scripts/create-auth-key.sh --user emergency --expiration 30m
   ```

## Backup Security

### Encrypted Backups
```bash
# Encrypt database backups
gpg --cipher-algo AES256 --compress-algo 1 --s2k-mode 3 \
    --s2k-digest-algo SHA512 --s2k-count 65536 --force-mdc \
    --encrypt --armor -r admin@example.com \
    headscale_backup.db > headscale_backup.db.gpg

# Secure backup storage
chmod 600 headscale_backup.db.gpg
```

### Backup Verification
```bash
# Verify backup integrity
sqlite3 backup.db "PRAGMA integrity_check;"

# Test restore procedure
cp /opt/headscale/headscale-data/db.sqlite /tmp/test_restore.db
sqlite3 /tmp/test_restore.db ".restore backup.db"
```

## Security Checklist

### Initial Setup
- [ ] Non-root user created for Headscale
- [ ] Proper file permissions set
- [ ] Firewall configured with minimal ports
- [ ] SSH hardened (key-based auth, non-standard port)
- [ ] Automatic security updates enabled

### Configuration
- [ ] Headplane restricted to tailnet access only
- [ ] Short-lived auth keys configured
- [ ] Apache security headers enabled
- [ ] Comprehensive logging configured
- [ ] Log rotation configured

### Ongoing Maintenance  
- [ ] Regular container updates
- [ ] Log monitoring and review
- [ ] Auth key rotation
- [ ] Backup verification
- [ ] Security patch application

### Monitoring
- [ ] Failed authentication attempts
- [ ] Unusual network traffic patterns
- [ ] Container resource usage
- [ ] File system changes
- [ ] Certificate expiration (handled by Funnel)

## Compliance Considerations

### Data Protection
- **Data Minimization**: Only store necessary client metadata
- **Retention**: Configure appropriate data retention periods
- **Access Logging**: Comprehensive audit trail

### Network Security Standards
- **Encryption in Transit**: HTTPS via Tailscale Funnel
- **Access Control**: Role-based via user separation
- **Network Segmentation**: Public/private service separation

## Security Testing

### Automated Testing
```bash
# Run security tests
./scripts/test-setup.sh

# Network vulnerability scanning  
nmap -sV -sC localhost

# Container security scanning
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
    aquasec/trivy:latest image headscale/headscale:0.26.1
```

### Manual Testing
```bash
# Test authentication bypass attempts
curl -H "User-Agent: malicious" "https://your-server.ts.net/key"

# Test directory traversal
curl "https://your-server.ts.net/../../../etc/passwd"

# Test injection attacks
curl "https://your-server.ts.net/key?key='; DROP TABLE--"
```