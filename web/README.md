# Web Server Setup for lobby.route19.com/install

This directory contains configuration files to set up `curl -sSL lobby.route19.com/install | bash` as a short URL for the installer.

## Setup Instructions

### 1. DNS Configuration
Create a DNS A record pointing `lobby.route19.com` to your web server's IP address.

### 2. Web Server Setup

#### Option A: Nginx (Recommended)
1. Copy the install script to your web root:
   ```bash
   sudo mkdir -p /var/www/lobby.route19.com
   sudo cp install /var/www/lobby.route19.com/install
   sudo chmod 644 /var/www/lobby.route19.com/install
   ```

2. Add the nginx configuration:
   ```bash
   sudo cp nginx-config.conf /etc/nginx/sites-available/lobby.route19.com
   sudo ln -s /etc/nginx/sites-available/lobby.route19.com /etc/nginx/sites-enabled/
   sudo nginx -t
   sudo systemctl reload nginx
   ```

#### Option B: Apache
Add to your Apache virtual host:
```apache
<VirtualHost *:443>
    ServerName lobby.route19.com
    DocumentRoot /var/www/lobby.route19.com
    
    # SSL configuration (adjust paths)
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/route19.com.pem
    SSLCertificateKeyFile /etc/ssl/private/route19.com.key
    
    # Handle /install endpoint
    Alias /install /var/www/lobby.route19.com/install
    
    <Location "/install">
        ForceType text/plain
    </Location>
</VirtualHost>
```

### 3. SSL Certificate
Ensure you have a valid SSL certificate for `lobby.route19.com`. You can use:
- Let's Encrypt: `certbot --nginx -d lobby.route19.com`
- Your existing Route 19 wildcard certificate

### 4. Test
Test the endpoint:
```bash
curl -sSL lobby.route19.com/install
```

Should return the installer script content.

## Final Command
Once configured, users can install with:
```bash
curl -sSL lobby.route19.com/install | bash
```

## Updates
The install script automatically pulls the latest version from GitHub, so no manual updates needed.