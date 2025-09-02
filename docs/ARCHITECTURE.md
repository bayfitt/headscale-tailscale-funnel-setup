# Architecture Overview

This document describes the architecture of the Headscale + Tailscale Funnel setup.

## System Components

```
Internet
    │
    ├─── Tailscale Funnel (HTTPS) ─────┐
    │                                  │
    └─── Direct Tailnet Access ────────┼──── Headplane Web UI :3000
                                       │
                                       ▼
                                 Apache Reverse Proxy :80
                                       │
                                       ├─── iOS Fix (mod_rewrite)
                                       │
                                       ▼
                              Headscale Server :8080
                                   (Docker)
                                       │
                                       ▼
                                SQLite Database
```

## Network Flow

### 1. Public Access via Tailscale Funnel

```
Internet User → Tailscale Funnel → Apache :80 → Headscale :8080
```

- **Tailscale Funnel** provides public HTTPS endpoint
- **Apache** handles reverse proxy and iOS authentication fixes  
- **Headscale** serves the coordination protocol

### 2. Private Access via Tailnet

```
Tailnet Client → Direct Access → Headplane :3000
```

- **Headplane** web UI only accessible on tailnet
- **Direct connection** to Tailscale IP address
- **Administrative interface** for managing users and keys

### 3. Mobile Client Connection

```
Mobile App → Public HTTPS → Apache (iOS Fix) → Headscale → ts2021 Protocol
```

- **iOS fix** automatically adds capability version parameter
- **WebSocket support** for ts2021 protocol  
- **Apache upgrade=any** handles non-standard WebSocket protocols

## Component Details

### Headscale (Port 8080)
- **Purpose**: Self-hosted Tailscale coordination server
- **Protocol**: HTTP API + WebSocket (ts2021)
- **Database**: SQLite for node and user data
- **Configuration**: `/opt/headscale/headscale-config/config.yaml`

### Apache Reverse Proxy (Port 80)
- **Purpose**: Handle public requests and iOS compatibility
- **Modules**: proxy, proxy_http, proxy_wstunnel, rewrite, headers
- **Key Features**:
  - iOS authentication fix (capability version injection)
  - WebSocket proxying for ts2021 protocol
  - Request logging and debugging

### Headplane (Port 3000, Tailnet only)
- **Purpose**: Web UI for Headscale administration
- **Access**: Restricted to tailnet IP address
- **Features**: User management, node monitoring, auth key creation

### Tailscale Funnel (Port 443)
- **Purpose**: Provide public HTTPS access
- **Protocol**: HTTPS with automatic certificate management
- **Routing**: Forwards to Apache on port 80

## Security Architecture

### Network Isolation
- **Public**: Only Headscale coordination server
- **Private**: Headplane admin interface on tailnet only
- **Segregation**: Different access paths for users vs. admins

### Authentication Flow
```
1. Client requests auth → Public HTTPS endpoint
2. Apache processes request → Adds iOS compatibility if needed  
3. Headscale validates → Returns auth response
4. Client establishes → Secure Tailscale connection
```

### Certificate Management
- **Tailscale Funnel**: Automatic HTTPS certificates
- **Internal**: HTTP only (encrypted by Funnel layer)
- **Client connections**: End-to-end encrypted via Tailscale

## Data Flow

### Configuration Data
```
Docker Compose → Headscale Container → SQLite Database
                      ↑
               Config Volume Mount
```

### User Management
```
Headplane UI → Docker API → Headscale CLI → SQLite Database
```

### Client Authentication  
```
Mobile App → Funnel → Apache → Headscale → Database Lookup → Auth Response
```

## File System Layout

```
/opt/headscale/
├── docker-compose.yml          # Container orchestration
├── headscale-config/
│   └── config.yaml             # Headscale configuration
├── headscale-data/             # SQLite database & logs
│   └── db.sqlite
└── headplane-data/             # Headplane data (if any)

/etc/apache2/
├── sites-available/
│   └── headscale.conf          # Apache virtual host
└── sites-enabled/
    └── headscale.conf          # Symlink to above

/tmp/headscale-tailscale-funnel-setup/
├── config/                     # Template configurations
├── scripts/                    # Automation scripts  
├── test-client/               # Docker test environment
└── docs/                      # Documentation
```

## Container Architecture

### Headscale Container
```dockerfile
FROM headscale/headscale:0.26.1
EXPOSE 8080
VOLUME /var/lib/headscale       # Database persistence
VOLUME /etc/headscale           # Configuration
```

### Headplane Container  
```dockerfile  
FROM ghcr.io/gurucomputing/headplane:0.3.0
EXPOSE 3000
ENVIRONMENT HEADSCALE_URL       # Connect to Headscale
ENVIRONMENT COOKIE_SECRET       # Session management
```

### Test Client Container
```dockerfile
FROM debian:bookworm-slim
RUN install tailscale           # For testing connections
EXPOSE 8080 3000               # For debugging
```

## Protocol Details

### ts2021 Protocol
- **Transport**: WebSocket over HTTPS
- **Purpose**: Tailscale coordination protocol
- **Requirements**: 
  - WebSocket upgrade support
  - Capability version for iOS (v=88)
  - Low-latency bidirectional communication

### iOS Compatibility Fix
```apache
# Detect iOS user agent
RewriteCond %{HTTP_USER_AGENT} tailscale.*ios [NC]
RewriteCond %{REQUEST_URI} ^/key$
RewriteCond %{QUERY_STRING} !v= [NC]

# Add capability version parameter  
RewriteRule ^/key$ http://127.0.0.1:8080/key?%{QUERY_STRING}&v=88 [QSA,L,P]
```

## Monitoring and Logging

### Log Locations
- **Headscale**: Docker container logs
- **Apache**: `/var/log/apache2/headscale_*.log`
- **System**: `journalctl -u apache2`, `journalctl -u docker`

### Health Check Endpoints
- **Headscale API**: `http://127.0.0.1:8080/`
- **Apache Proxy**: `http://127.0.0.1/`  
- **Public Access**: `https://hostname.ts.net/`
- **Headplane**: `http://tailscale-ip:3000/`

## Scaling Considerations

### Single Node Setup
- **Current**: All components on single server
- **Database**: SQLite (suitable for small-medium deployments)
- **Limitations**: Single point of failure

### Potential Scaling
- **Database**: Migrate to PostgreSQL for larger deployments
- **Load Balancing**: Multiple Headscale instances
- **High Availability**: Replicated setup with shared database

## Backup and Recovery

### Critical Data
- **SQLite Database**: `/opt/headscale/headscale-data/db.sqlite`
- **Configuration**: `/opt/headscale/headscale-config/config.yaml`  
- **Apache Config**: `/etc/apache2/sites-available/headscale.conf`

### Backup Strategy
```bash
# Automated backup
docker compose -f /opt/headscale/docker-compose.yml exec headscale \
  sqlite3 /var/lib/headscale/db.sqlite ".backup /backup/headscale-$(date +%Y%m%d).db"
```

## Performance Characteristics

### Expected Load
- **Coordination**: Low CPU, network I/O bound
- **Database**: Light SQLite usage for node state
- **Apache**: Minimal processing, mainly proxy
- **Memory**: ~100MB total for all components

### Bottlenecks
- **Network**: Internet bandwidth for Funnel
- **Database**: SQLite locks under high concurrency
- **CPU**: Minimal unless many concurrent connections

## Security Hardening

### Network Security
- **Firewall**: Only expose port 80 to Tailscale Funnel
- **TLS**: Terminated at Funnel, internal HTTP acceptable
- **Access Control**: Headplane restricted to tailnet

### Container Security
- **User**: Run as non-root headscale user
- **Volumes**: Minimal required mounts
- **Network**: Host networking for Tailscale integration

### Operational Security
- **Logging**: Comprehensive request/error logging
- **Updates**: Regular container image updates
- **Auth Keys**: Time-limited, single-use preferred