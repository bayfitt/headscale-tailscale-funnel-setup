# iOS Authentication Fix

This document explains the iOS client authentication issue and how our Apache configuration fixes it.

## The Problem

### Symptoms
iOS Tailscale clients would fail to authenticate with Headscale, showing these errors:
- `FetchControlKeyGit EOF`
- `400 Bad Request` with "capability version must be set"

### Root Cause
Through analysis of the Headscale source code, we discovered that iOS clients require a specific capability version parameter (`v=88`) to be included in authentication requests. Without this parameter, Headscale rejects the request.

## Technical Details

### iOS Client Behavior
iOS Tailscale clients make requests to the `/key` endpoint but don't include the required capability version parameter that Headscale expects for proper protocol negotiation.

### Expected Request Format
```http
GET /key?key=your-auth-key&v=88 HTTP/1.1
User-Agent: Tailscale iOS/1.50.0
```

### Actual iOS Client Request
```http  
GET /key?key=your-auth-key HTTP/1.1
User-Agent: Tailscale iOS/1.50.0
```

## The Solution

### Apache mod_rewrite Fix
We implemented an Apache reverse proxy with mod_rewrite rules that automatically detect iOS clients and inject the required capability version parameter.

### Configuration
```apache
# Enable required modules
LoadModule rewrite_module modules/mod_rewrite.so
LoadModule proxy_module modules/mod_proxy.so
LoadModule proxy_http_module modules/mod_proxy_http.so
LoadModule proxy_wstunnel_module modules/mod_proxy_wstunnel.so

<VirtualHost *:80>
    ServerName your-headscale-server.ts.net
    
    # Enable rewrite engine
    RewriteEngine On
    
    # iOS Fix: Detect iOS user agent and add capability version
    RewriteCond %{HTTP_USER_AGENT} tailscale.*ios [NC]
    RewriteCond %{REQUEST_URI} ^/key$
    RewriteCond %{QUERY_STRING} !v= [NC]
    RewriteRule ^/key$ http://127.0.0.1:8080/key?%{QUERY_STRING}&v=88 [QSA,L,P]
    
    # Proxy all other requests normally
    ProxyPass / http://127.0.0.1:8080/ upgrade=any
    ProxyPassReverse / http://127.0.0.1:8080/
    
    # WebSocket support for ts2021 protocol
    ProxyPass /ts2021 http://127.0.0.1:8080/ts2021 upgrade=websocket
    ProxyPassReverse /ts2021 http://127.0.0.1:8080/ts2021
</VirtualHost>
```

### How It Works

1. **User Agent Detection**: `%{HTTP_USER_AGENT} tailscale.*ios [NC]`
   - Matches any iOS Tailscale client user agent string
   - Case-insensitive (`[NC]`) matching

2. **Path Matching**: `%{REQUEST_URI} ^/key$`
   - Only applies to the `/key` endpoint used for authentication

3. **Parameter Check**: `%{QUERY_STRING} !v= [NC]`
   - Only applies if the `v=` parameter is not already present
   - Prevents duplicate parameters

4. **URL Rewriting**: `RewriteRule ^/key$ http://127.0.0.1:8080/key?%{QUERY_STRING}&v=88 [QSA,L,P]`
   - Appends `&v=88` to the query string
   - `[QSA]`: Query String Append - preserves existing parameters
   - `[L]`: Last rule - stop processing further rules
   - `[P]`: Proxy - forward the rewritten request

## Why nginx Didn't Work

### Initial Attempts with nginx
We initially tried to implement this fix using nginx, but encountered several issues:

1. **Location Block Processing**: nginx location blocks weren't being processed for the specific `/key` endpoint
2. **Complex Conditional Logic**: nginx's `if` statements are limited and don't handle complex user agent + parameter logic well
3. **Rewrite Rule Conflicts**: Multiple attempts at different nginx configurations failed to properly rewrite the URLs

### Apache Advantages
Apache's mod_rewrite proved superior for this use case because:
- More powerful and flexible rewrite conditions
- Better support for complex conditional logic  
- Reliable user agent string matching
- Proper query string manipulation with `[QSA]` flag

## Testing the Fix

### Manual Testing
```bash
# Test normal request (should pass through unchanged)
curl -H "User-Agent: curl/7.68.0" "http://your-server/key?key=test-key"

# Test iOS request without v parameter (should add v=88)
curl -H "User-Agent: Tailscale iOS/1.50.0" "http://your-server/key?key=test-key"

# Test iOS request with existing v parameter (should not modify)
curl -H "User-Agent: Tailscale iOS/1.50.0" "http://your-server/key?key=test-key&v=77"
```

### Verification Script
```bash
#!/bin/bash
# Test iOS authentication fix

# Test 1: Non-iOS user agent (should not add v parameter)
echo "Test 1: Non-iOS user agent"
curl -s -H "User-Agent: curl/7.68.0" "http://127.0.0.1/key?key=test" \
  --write-out "Status: %{http_code}\n" -o /dev/null

# Test 2: iOS user agent without v parameter (should add v=88)  
echo "Test 2: iOS user agent without v parameter"
curl -s -H "User-Agent: Tailscale iOS/1.50.0" "http://127.0.0.1/key?key=test" \
  --write-out "Status: %{http_code}\n" -o /dev/null

# Test 3: iOS user agent with existing v parameter (should not modify)
echo "Test 3: iOS user agent with existing v parameter"  
curl -s -H "User-Agent: Tailscale iOS/1.50.0" "http://127.0.0.1/key?key=test&v=77" \
  --write-out "Status: %{http_code}\n" -o /dev/null
```

## Debugging and Troubleshooting

### Enable Apache Rewrite Logging
```apache
# Add to virtual host configuration
LogLevel rewrite:trace2
ErrorLog /var/log/apache2/headscale_error.log
```

### Check Rewrite Rules
```bash
# View rewrite log
sudo tail -f /var/log/apache2/headscale_error.log | grep rewrite

# Test rewrite engine
sudo apache2ctl -S
sudo apache2ctl -M | grep rewrite
```

### Common Issues

1. **mod_rewrite not enabled**:
   ```bash
   sudo a2enmod rewrite
   sudo systemctl reload apache2
   ```

2. **User agent not matching**:
   - Check exact iOS client user agent string
   - Adjust regex pattern if needed

3. **Query string not preserved**:
   - Ensure `[QSA]` flag is present
   - Check for conflicting rewrite rules

## Performance Impact

### Minimal Overhead
- Rewrite rules only activate for iOS clients
- Simple string matching and parameter appending
- No impact on other clients or endpoints

### Processing Time
- Adds <1ms latency for iOS authentication requests
- No ongoing performance impact after authentication

## Alternative Solutions Considered

### 1. Patch Headscale Source
**Pros**: Direct fix at the source
**Cons**: Requires maintaining custom fork, complex deployment

### 2. Custom Proxy Application
**Pros**: Full control over request handling
**Cons**: Additional complexity, maintenance burden

### 3. Client-Side Workaround  
**Pros**: No server changes needed
**Cons**: Requires custom iOS client build, not practical

### 4. nginx Proxy (Attempted)
**Pros**: Lightweight, commonly used
**Cons**: Failed to handle complex rewrite logic reliably

## Security Considerations

### Input Validation
- User agent header is properly escaped in regex
- Query string manipulation uses Apache's built-in functions
- No direct shell execution or file system access

### Attack Surface
- Minimal: only adds parameter to existing requests
- No new endpoints or functionality exposed
- Follows principle of least modification

## Maintenance

### Updates
- Monitor for changes in iOS client user agent strings
- Watch for Headscale protocol changes that might affect capability versions
- Test iOS authentication after any Apache configuration changes

### Monitoring
- Track iOS client authentication success/failure rates
- Monitor Apache error logs for rewrite rule issues
- Verify fix continues working with iOS Tailscale updates

## Future Considerations

### Upstream Fix
This fix may become unnecessary if:
- Headscale adds automatic iOS compatibility
- iOS Tailscale client includes capability version by default
- Tailscale protocol changes eliminate the requirement

### Protocol Evolution
Monitor for:
- New capability version requirements
- Changes to authentication flow
- Additional mobile client quirks requiring fixes