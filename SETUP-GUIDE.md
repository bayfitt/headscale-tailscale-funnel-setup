# Headscale + Tailscale Funnel Setup Guide

This guide provides step-by-step instructions for setting up a self-hosted Headscale server with Tailscale Funnel public access and iOS device support.

## Prerequisites

### System Requirements
- **OS**: Ubuntu/Debian Linux server
- **Memory**: Minimum 1GB RAM
- **Storage**: 10GB free space
- **Network**: Internet connectivity with ports 443/80 access

### Required Software
- Docker and Docker Compose
- Apache2 web server
- Tailscale installed and authenticated
- SSL certificates (handled by Tailscale Funnel)

### Tailscale Requirements
- Tailscale account with Funnel access enabled
- Device added to tailnet and authenticated
- Funnel feature available in your region

## Step-by-Step Installation

### Step 1: System Preparation

1. **Update system packages**
   ```bash
   sudo apt update && sudo apt upgrade -y
   ```

2. **Install Docker**
   ```bash
   curl -fsSL https://get.docker.com -o get-docker.sh
   sudo sh get-docker.sh
   sudo usermod -aG docker $USER
   # Log out and back in for group changes
   ```

3. **Install Apache2**
   ```bash
   sudo apt install -y apache2
   sudo a2enmod proxy proxy_http proxy_wstunnel rewrite headers
   ```

4. **Install Tailscale**
   ```bash
   curl -fsSL https://tailscale.com/install.sh | sh
   sudo tailscale up
   ```

### Step 2: Configure Directories

1. **Create project structure**
   ```bash
   sudo mkdir -p /opt/headscale/{headscale-config,headscale-data,headplane-data}
   sudo chown -R $USER:$USER /opt/headscale
   ```

2. **Set up headscale user for Docker**
   ```bash
   sudo useradd -r -s /bin/false headscale
   sudo chown -R headscale:headscale /opt/headscale/headscale-data
   ```

### Step 3: Deploy Headscale + Headplane

1. **Copy configuration files**
   ```bash
   cp config/docker-compose.yml /opt/headscale/
   cp config/headscale-config.yaml /opt/headscale/headscale-config/config.yaml
   ```

2. **Update configuration**
   - Edit `/opt/headscale/headscale-config/config.yaml`
   - Replace `your-headscale-server.ts.net` with your Tailscale hostname
   - Update `prefixes` if needed for your network

3. **Get your Tailscale IP**
   ```bash
   TAILSCALE_IP=$(tailscale ip)
   echo "Tailscale IP: $TAILSCALE_IP"
   ```

4. **Update Headplane binding in docker-compose.yml**
   ```yaml
   headplane:
     ports:
       - "${TAILSCALE_IP}:3000:3000"
   ```

5. **Start services**
   ```bash
   cd /opt/headscale
   sudo -u headscale docker compose up -d
   ```

6. **Verify deployment**
   ```bash
   sudo -u headscale docker compose ps
   sudo -u headscale docker compose logs
   ```

### Step 4: Configure Apache Reverse Proxy

1. **Copy Apache configuration**
   ```bash
   sudo cp config/apache-headscale.conf /etc/apache2/sites-available/headscale.conf
   ```

2. **Update hostname in configuration**
   ```bash
   sudo sed -i 's/your-headscale-server.ts.net/YOUR_TAILSCALE_HOSTNAME.ts.net/g' \
     /etc/apache2/sites-available/headscale.conf
   ```

3. **Enable site and disable default**
   ```bash
   sudo a2ensite headscale
   sudo a2dissite 000-default
   sudo systemctl reload apache2
   ```

4. **Test Apache configuration**
   ```bash
   curl -I http://localhost/
   # Should return 404 (expected)
   ```

### Step 5: Configure Tailscale Funnel

1. **Set up Tailscale Funnel**
   ```bash
   tailscale funnel --bg --https=443 --set-path=/ http://localhost:80
   ```

2. **Verify Funnel status**
   ```bash
   tailscale funnel status
   ```

3. **Test external access**
   ```bash
   curl -I https://YOUR_HOSTNAME.ts.net
   # Should return 404 (expected, but connection works)
   ```

### Step 6: Create Users and Auth Keys

1. **Access Headplane web UI**
   - Navigate to `http://YOUR_TAILSCALE_IP:3000`
   - Or use CLI commands below

2. **Create a user via CLI**
   ```bash
   cd /opt/headscale
   sudo -u headscale docker compose exec headscale headscale users create USERNAME
   ```

3. **List users**
   ```bash
   sudo -u headscale docker compose exec headscale headscale users list
   ```

4. **Create auth key**
   ```bash
   sudo -u headscale docker compose exec headscale headscale preauthkeys create --user USER_ID --expiration 1h
   ```

### Step 7: Test iOS Connection

1. **Test authentication endpoint**
   ```bash
   curl -H "User-Agent: Tailscale iOS/1.50.0" \
     "https://YOUR_HOSTNAME.ts.net/key?key=YOUR_AUTH_KEY"
   # Should return JSON with public keys
   ```

2. **Connect iOS device**
   - Open Tailscale iOS app
   - Add account → Use custom coordination server
   - Server: `https://YOUR_HOSTNAME.ts.net`
   - Auth key: Generated key from step 6

### Step 8: Deploy Test Client (Optional)

1. **Build test client**
   ```bash
   cd test-client
   docker-compose build
   docker-compose up -d
   ```

2. **Test connection**
   ```bash
   ./test-connection.sh
   ```

3. **View test client status**
   ```bash
   docker exec headscale-test-client tailscale status
   ```

## Configuration Details

### Headscale Configuration
The main configuration is in `/opt/headscale/headscale-config/config.yaml`:

```yaml
server_url: https://YOUR_HOSTNAME.ts.net
prefixes:
  v4: 100.64.0.0/10
  v6: fd7a:115c:a1e0::/48
database:
  type: sqlite3
  sqlite:
    path: /var/lib/headscale/db.sqlite
```

### Apache iOS Fix
The iOS authentication fix automatically adds the `v=88` parameter:

```apache
RewriteCond %{HTTP_USER_AGENT} tailscale.*ios [NC]
RewriteCond %{REQUEST_URI} ^/key$
RewriteCond %{QUERY_STRING} !v= [NC]
RewriteRule ^/key$ http://127.0.0.1:8080/key?%{QUERY_STRING}&v=88 [QSA,L,P]
```

### WebSocket Support
The `upgrade=any` parameter enables Tailscale's custom WebSocket protocol:

```apache
ProxyPass / http://127.0.0.1:8080/ upgrade=any
```

## Security Considerations

### Network Security
- Headplane web UI only accessible via tailnet (private)
- Headscale API only accessible via Tailscale Funnel (public HTTPS)
- All HTTP traffic automatically handled by Tailscale Funnel

### Access Control
- Auth keys have configurable expiration
- Users can be created/deleted as needed
- Individual device management via Headplane

### SSL/TLS
- Tailscale Funnel handles all SSL termination
- Certificates managed automatically by Tailscale
- HSTS and security headers enforced

## Monitoring and Maintenance

### Log Files
- **Headscale**: `sudo -u headscale docker compose logs headscale`
- **Headplane**: `sudo -u headscale docker compose logs headplane`
- **Apache**: `/var/log/apache2/headscale_*.log`

### Service Management
```bash
# Restart services
sudo -u headscale docker compose restart

# Update containers
sudo -u headscale docker compose pull
sudo -u headscale docker compose up -d

# Check Funnel status
tailscale funnel status
```

### Backup
```bash
# Backup database
cp /opt/headscale/headscale-data/db.sqlite ~/headscale-backup-$(date +%Y%m%d).sqlite

# Backup configuration
tar -czf ~/headscale-config-$(date +%Y%m%d).tar.gz /opt/headscale/headscale-config
```

## Next Steps

1. **Add more users**: Create additional users and auth keys as needed
2. **Configure DNS**: Set up custom DNS resolution in Headscale
3. **Add routes**: Configure subnet routing for on-premise networks
4. **Monitor usage**: Set up monitoring and alerting for the service

## Troubleshooting

See `TROUBLESHOOTING.md` for common issues and solutions.