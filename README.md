# Headscale + Tailscale Funnel with iOS Authentication Fix

A complete self-hosted Tailscale control server setup using Headscale, exposed publicly via Tailscale Funnel with full iOS device support.

## ✅ What This Setup Provides

- **Self-hosted Headscale server** (v0.26.1) with Headplane web UI
- **Public HTTPS access** via Tailscale Funnel for mobile clients
- **iOS authentication fix** - automatic `v=88` parameter injection for iOS clients
- **WebSocket support** for ts2021 coordination protocol
- **Test environment** with Docker container for validation
- **Production-ready** Apache configuration with proper security headers

## 🚀 Quick Start

1. **Prerequisites Check**
   ```bash
   ./scripts/check-prerequisites.sh
   ```

2. **Deploy Headscale + Headplane**
   ```bash
   ./scripts/deploy-headscale.sh
   ```

3. **Configure Apache Proxy**
   ```bash
   ./scripts/setup-apache.sh
   ```

4. **Enable Tailscale Funnel**
   ```bash
   ./scripts/setup-funnel.sh
   ```

5. **Test Setup**
   ```bash
   ./scripts/test-setup.sh
   ```

## 📱 iOS Device Connection

1. **Open Tailscale iOS app**
2. **Add account** → **Use a custom coordination server**
3. **Server URL**: `https://your-tailscale-hostname.ts.net`
4. **Auth Key**: Generate using `./scripts/create-auth-key.sh username`

## 🛠️ Components

### Headscale Server
- **Port**: 8080 (internal)
- **Configuration**: `config/headscale-config.yaml`
- **Data**: Persistent SQLite database

### Headplane Web UI
- **Access**: `http://your-tailscale-ip:3000` (tailnet only)
- **Purpose**: Web-based management interface

### Apache Reverse Proxy
- **Configuration**: `config/apache-headscale.conf`
- **Features**: iOS fix, WebSocket support, security headers

### Tailscale Funnel
- **Purpose**: Public HTTPS exposure
- **URL**: `https://your-hostname.ts.net`

## 📁 Project Structure

```
headscale-tailscale-funnel-setup/
├── README.md                          # This file
├── SETUP-GUIDE.md                     # Detailed setup instructions
├── TROUBLESHOOTING.md                 # Common issues and solutions
├── config/                            # Configuration files
│   ├── docker-compose.yml            # Headscale + Headplane containers
│   ├── headscale-config.yaml         # Headscale server configuration
│   └── apache-headscale.conf          # Apache reverse proxy config
├── scripts/                           # Automation scripts
│   ├── check-prerequisites.sh        # System requirements check
│   ├── deploy-headscale.sh           # Deploy containers
│   ├── setup-apache.sh               # Configure Apache
│   ├── setup-funnel.sh               # Enable Tailscale Funnel
│   ├── create-auth-key.sh            # Generate auth keys
│   └── test-setup.sh                 # Test environment validation
├── test-client/                       # Docker test client
│   ├── Dockerfile                    # Test client container
│   ├── docker-compose.yml            # Test client deployment
│   ├── entrypoint.sh                 # Test client scripts
│   └── test-connection.sh            # Connection testing script
└── docs/                             # Additional documentation
    ├── ARCHITECTURE.md               # System architecture overview
    ├── IOS-FIX.md                    # iOS authentication fix details
    └── SECURITY.md                   # Security considerations
```

## 🔧 Configuration Details

### Headscale Features
- **Server URL**: Configured for public Funnel access
- **IP Ranges**: `100.64.0.0/10` (IPv4), `fd7a:115c:a1e0::/48` (IPv6)
- **Database**: SQLite with persistent storage
- **DNS**: Custom DNS configuration support

### iOS Authentication Fix
- **Issue**: iOS clients require `v=88` capability parameter
- **Solution**: Apache mod_rewrite automatically injects parameter
- **Detection**: Based on `Tailscale iOS` user agent

### Security Features
- **HTTPS**: Enforced via Tailscale Funnel
- **Headers**: HSTS, X-Frame-Options, X-Content-Type-Options
- **Access Control**: Headplane restricted to tailnet only

## 📊 Testing

### Test Client Container
```bash
cd test-client
docker-compose up -d
./test-connection.sh
```

### Manual Testing
```bash
# Test iOS authentication endpoint
curl -H "User-Agent: Tailscale iOS/1.50.0" \
  "https://your-hostname.ts.net/key?key=YOUR_AUTH_KEY"

# Test WebSocket upgrade
curl -i -H "Connection: Upgrade" -H "Upgrade: websocket" \
  "https://your-hostname.ts.net/ts2021"
```

## 🆘 Support

- **Setup Issues**: See `TROUBLESHOOTING.md`
- **iOS Problems**: See `docs/IOS-FIX.md`
- **Architecture**: See `docs/ARCHITECTURE.md`

## ⚠️ Important Notes

**Headplane UI Testing Required**: This setup has been tested with Headplane on commercial Tailscale networks. The Headplane UI accessibility on the self-hosted Headscale network still needs validation. In theory, you should only need commercial Tailscale for setting up the funnel on the control server itself.

## 📝 License

MIT License - See [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- [Headscale](https://headscale.net/) - Self-hosted Tailscale control server
- [Headplane](https://github.com/tale/headplane) - Web UI for Headscale
- [Tailscale](https://tailscale.com/) - Zero-config mesh VPN