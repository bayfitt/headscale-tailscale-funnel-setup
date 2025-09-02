# Troubleshooting Guide

This guide covers common issues and solutions for the Headscale + Tailscale Funnel setup.

## Table of Contents

- [Prerequisites Issues](#prerequisites-issues)
- [Docker and Container Issues](#docker-and-container-issues)
- [Apache Configuration Issues](#apache-configuration-issues)
- [Headscale Configuration Issues](#headscale-configuration-issues)
- [iOS Client Issues](#ios-client-issues)
- [Tailscale Funnel Issues](#tailscale-funnel-issues)
- [Network and Connectivity Issues](#network-and-connectivity-issues)
- [Headplane Web UI Issues](#headplane-web-ui-issues)
- [Authentication Issues](#authentication-issues)
- [Logging and Debugging](#logging-and-debugging)

## Prerequisites Issues

### Docker Not Running
**Symptoms:** `Cannot connect to the Docker daemon`
**Solution:**
```bash
sudo systemctl start docker
sudo systemctl enable docker
# Add user to docker group
sudo usermod -aG docker $USER
# Logout and login again
```

### Apache Not Installed or Running
**Symptoms:** `apache2: command not found` or service not active
**Solution:**
```bash
sudo apt update
sudo apt install -y apache2
sudo systemctl start apache2
sudo systemctl enable apache2
```

### Tailscale Not Connected
**Symptoms:** `tailscale status` fails or shows not connected
**Solution:**
```bash
sudo tailscale up
# Follow authentication prompts
```

## Docker and Container Issues

### Headscale Container Won't Start
**Check logs:**
```bash
sudo -u headscale docker compose -f /opt/headscale/docker-compose.yml logs headscale
```

**Common causes:**
1. **Port conflict**: Another service using port 8080
   ```bash
   sudo ss -tulpn | grep :8080
   sudo systemctl stop <conflicting-service>
   ```

2. **Permission issues**: Wrong ownership of data directories
   ```bash
   sudo chown -R headscale:headscale /opt/headscale
   ```

3. **Configuration errors**: Invalid YAML syntax
   ```bash
   sudo -u headscale docker compose -f /opt/headscale/docker-compose.yml config
   ```

### Headplane Container Issues
**Symptoms:** Headplane not accessible on port 3000
**Solution:**
1. Check container status:
   ```bash
   sudo -u headscale docker compose -f /opt/headscale/docker-compose.yml ps headplane
   ```

2. Check logs:
   ```bash
   sudo -u headscale docker compose -f /opt/headscale/docker-compose.yml logs headplane
   ```

3. Verify Tailscale IP binding:
   ```bash
   tailscale ip
   # Should match the IP in docker-compose.yml
   ```

## Apache Configuration Issues

### 502 Bad Gateway
**Symptoms:** Apache returns 502 when accessing Headscale
**Causes and solutions:**

1. **Headscale not running:**
   ```bash
   curl -I http://127.0.0.1:8080
   # Should return HTTP response
   ```

2. **Proxy modules not enabled:**
   ```bash
   sudo a2enmod proxy proxy_http proxy_wstunnel
   sudo systemctl reload apache2
   ```

3. **Configuration syntax error:**
   ```bash
   sudo apache2ctl configtest
   ```

### Redirect Loops
**Symptoms:** "Stopped after 10 redirects"
**Solution:** Remove HTTP-to-HTTPS redirects in Apache config, Tailscale Funnel handles SSL

### Apache Won't Start
**Common issues:**
1. **Port 80 already in use:**
   ```bash
   sudo ss -tulpn | grep :80
   ```

2. **Configuration syntax error:**
   ```bash
   sudo apache2ctl configtest
   sudo systemctl status apache2
   ```

## Headscale Configuration Issues

### v0.26.0+ Configuration Format
**Symptoms:** Container fails to start with YAML parsing errors
**Solution:** Ensure configuration uses the new format:

```yaml
# New format (v0.26.0+)
prefixes:
  v4: 100.64.0.0/10
  v6: fd7a:115c:a1e0::/48

dns:
  magic_dns: true
  base_domain: ts.net

database:
  type: sqlite3
  sqlite:
    path: /var/lib/headscale/db.sqlite
```

### Database Permissions
**Symptoms:** Database connection errors
**Solution:**
```bash
sudo chown -R headscale:headscale /opt/headscale/headscale-data
sudo chmod 755 /opt/headscale/headscale-data
```

## iOS Client Issues

### "FetchControlKeyGit EOF" Error
**Cause:** iOS client not receiving capability version parameter
**Solution:** The Apache configuration includes an iOS fix that automatically adds `v=88` parameter

### "400 Bad Request" from iOS
**Symptoms:** iOS devices get HTTP 400 when connecting
**Verification:** Check if iOS fix is working:
```bash
# Test iOS user agent
curl -H "User-Agent: Tailscale iOS/1.50.0" \
  "http://your-server.ts.net/key?key=test"
```

**Solution:** Ensure Apache rewrite rules are active:
```bash
# Check if mod_rewrite is enabled
sudo apache2ctl -M | grep rewrite

# Check configuration
grep -A 3 "tailscale.*ios" /etc/apache2/sites-enabled/headscale.conf
```

### iOS Not Accepting Server
**Symptoms:** iOS client doesn't accept custom coordination server
**Solution:**
1. Use the exact server URL from Headscale config
2. Ensure HTTPS is working via Funnel
3. Try generating a new auth key

## Tailscale Funnel Issues

### Funnel Not Available
**Symptoms:** `tailscale funnel` commands fail
**Cause:** Funnel not available in your region or plan
**Solution:**
1. Check availability: https://tailscale.com/kb/1223/funnel
2. Ensure you're on a supported plan
3. Try connecting from a different region

### "Plain HTTP to SSL Port" Error
**Symptoms:** SSL protocol error when accessing via Funnel
**Cause:** Funnel configured to proxy to HTTPS instead of HTTP
**Solution:**
```bash
# Configure Funnel to proxy to HTTP port 80
sudo tailscale serve https / http://127.0.0.1:80
sudo tailscale funnel https on
```

### Funnel Configuration Lost
**Symptoms:** Funnel stops working after restart
**Solution:**
```bash
# Reconfigure Funnel
sudo tailscale serve https / http://127.0.0.1:80
sudo tailscale funnel https on

# Check status
sudo tailscale funnel status
```

## Network and Connectivity Issues

### DNS Resolution Problems
**Symptoms:** Cannot resolve .ts.net domains
**Solution:**
1. Check MagicDNS is enabled in Headscale config
2. Verify DNS configuration on clients
3. Test DNS resolution:
   ```bash
   nslookup your-hostname.ts.net
   ```

### Port Conflicts
**Common conflicts:**
- Port 80: Other web servers (nginx, etc.)
- Port 8080: Other applications
- Port 3000: Development servers

**Solution:**
```bash
# Find what's using a port
sudo ss -tulpn | grep :PORT
sudo systemctl stop <service>
```

## Headplane Web UI Issues

### Cannot Access Headplane
**Symptoms:** Connection refused to Headplane UI
**Debugging steps:**

1. **Check container status:**
   ```bash
   sudo -u headscale docker compose -f /opt/headscale/docker-compose.yml ps headplane
   ```

2. **Check port binding:**
   ```bash
   sudo ss -tulpn | grep :3000
   ```

3. **Check Tailscale IP:**
   ```bash
   tailscale ip
   # Try accessing http://[this-ip]:3000
   ```

4. **Check container logs:**
   ```bash
   sudo -u headscale docker compose -f /opt/headscale/docker-compose.yml logs headplane
   ```

### Cookie Secret Errors
**Symptoms:** Headplane shows authentication errors
**Solution:** Ensure cookie secret in docker-compose.yml is exactly 32 characters

## Authentication Issues

### Cannot Create Auth Keys
**Symptoms:** `headscale preauthkeys create` fails
**Solution:**
```bash
# Check if user exists
sudo -u headscale docker compose -f /opt/headscale/docker-compose.yml exec headscale headscale users list

# Create user if needed
sudo -u headscale docker compose -f /opt/headscale/docker-compose.yml exec headscale headscale users create USERNAME
```

### Auth Key Expired
**Symptoms:** Client connection fails with expired key
**Solution:** Generate new auth key with longer expiration:
```bash
./scripts/create-auth-key.sh --user USERNAME --expiration 24h
```

## Logging and Debugging

### Enable Debug Logging

**Headscale debug logs:**
Edit `/opt/headscale/headscale-config/config.yaml`:
```yaml
log:
  level: debug
```

Restart containers:
```bash
sudo -u headscale docker compose -f /opt/headscale/docker-compose.yml restart
```

**Apache debug logs:**
Add to `/etc/apache2/sites-enabled/headscale.conf`:
```apache
LogLevel rewrite:trace2
```

### Useful Log Commands

```bash
# Headscale logs
sudo -u headscale docker compose -f /opt/headscale/docker-compose.yml logs -f headscale

# Apache access logs
sudo tail -f /var/log/apache2/headscale_access.log

# Apache error logs
sudo tail -f /var/log/apache2/headscale_error.log

# System logs
sudo journalctl -u apache2 -f
sudo journalctl -u docker -f
```

### Test Commands

```bash
# Test local Headscale API
curl -I http://127.0.0.1:8080

# Test Apache proxy
curl -I http://127.0.0.1

# Test public access (if Funnel enabled)
curl -I https://your-hostname.ts.net

# Test iOS user agent handling
curl -H "User-Agent: Tailscale iOS/1.50.0" http://127.0.0.1/key?key=test

# Check WebSocket support
curl -I -H "Connection: Upgrade" -H "Upgrade: websocket" http://127.0.0.1/ts2021
```

### Run Comprehensive Tests
```bash
# Run all tests
./scripts/test-setup.sh

# Check prerequisites
./scripts/check-prerequisites.sh
```

## Getting Help

If you're still experiencing issues:

1. **Run the test script:** `./scripts/test-setup.sh`
2. **Check the logs** using the commands above
3. **Verify configuration** files match the templates
4. **Check Headscale documentation:** https://headscale.net/
5. **Check Tailscale status:** https://status.tailscale.com/

## Common Error Messages

### "capability version must be set"
**Issue:** iOS clients require capability version parameter
**Fixed by:** Apache rewrite rule that adds `v=88` for iOS clients

### "FetchControlKeyGit EOF"
**Issue:** Connection terminated during key fetch
**Solution:** Usually resolved by the iOS fix above

### "502 Bad Gateway"
**Issue:** Apache can't connect to Headscale backend
**Check:** Headscale container running on port 8080

### "Stopped after 10 redirects"
**Issue:** Redirect loop between HTTP and HTTPS
**Solution:** Remove HTTP-to-HTTPS redirects, let Funnel handle SSL

### "plain HTTP request to SSL port"
**Issue:** Trying to send HTTP to HTTPS port
**Solution:** Configure Funnel to proxy to HTTP port 80, not 443