# AT Protocol Production Setup Guide

This guide will help you set up a production-ready AT Protocol service stack. The AT Protocol consists of several interconnected services that work together to provide a complete social media platform.

## Overview of AT Protocol Services

The AT Protocol consists of these main services:

1. **PDS (Personal Data Server)** - Core service that hosts user data and handles authentication
2. **BSky AppView** - Provides the Bluesky-specific API endpoints for social features
3. **Ozone** - Moderation service for content filtering and user management
4. **BSync** - Synchronization service for data replication between servers
5. **PLC (Public Ledger of Changes)** - DID resolution and key management (external service)

## Prerequisites

- **Server Requirements:**
  - Linux server (Ubuntu 20.04+ recommended)
  - 4+ CPU cores
  - 8GB+ RAM
  - 100GB+ storage
  - Public IP address
  - Domain name

- **Software Requirements:**
  - Docker and Docker Compose
  - Node.js 18+ and pnpm
  - PostgreSQL 14+
  - Redis 7+
  - Nginx (for reverse proxy)
  - SSL certificate (Let's Encrypt recommended)

## Step 1: Server Preparation

### Install Docker and Docker Compose

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Docker
curl -fsSL https://get.docker.com -o get-docker.sh
sudo sh get-docker.sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Logout and login again for group changes to take effect
```

### Install Node.js and pnpm

```bash
# Install Node.js 18
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install pnpm
npm install -g pnpm
```

### Install PostgreSQL and Redis

```bash
# Install PostgreSQL
sudo apt install postgresql postgresql-contrib -y

# Install Redis
sudo apt install redis-server -y

# Start and enable services
sudo systemctl start postgresql
sudo systemctl enable postgresql
sudo systemctl start redis-server
sudo systemctl enable redis-server
```

## Step 2: Clone and Build AT Protocol

```bash
# Clone the repository
git clone https://github.com/bluesky-social/atproto.git
cd atproto

# Install dependencies and build
pnpm install
pnpm build
```

## Step 3: Generate Cryptographic Keys

You'll need to generate several cryptographic keys for your services:

```bash
# Generate PDS signing key (256-bit hex string)
openssl rand -hex 32

# Generate PLC rotation key (256-bit hex string)
openssl rand -hex 32

# Generate DPOP secret (32 random bytes hex-encoded)
openssl rand -hex 32

# Generate JWT secret (high-entropy string)
openssl rand -hex 32

# Generate admin password (high-entropy string)
openssl rand -hex 16
```

## Step 4: Configure Environment Variables

Create environment files for each service:

### PDS Configuration (`services/pds/.env`)

```bash
# Hostname - your public domain
PDS_HOSTNAME="your-domain.com"
PDS_PORT="2583"

# Database config
PDS_DATA_DIRECTORY="data"

# Blobstore location
PDS_BLOBSTORE_DISK_LOCATION="blobs"

# Private keys (replace with your generated keys)
PDS_REPO_SIGNING_KEY_K256_PRIVATE_KEY_HEX="your-generated-signing-key"
PDS_PLC_ROTATION_KEY_K256_PRIVATE_KEY_HEX="your-generated-rotation-key"

# Secrets (replace with your generated secrets)
PDS_DPOP_SECRET="your-generated-dpop-secret"
PDS_JWT_SECRET="your-generated-jwt-secret"
PDS_ADMIN_PASSWORD="your-generated-admin-password"

# Environment - for production network
PDS_DID_PLC_URL="https://plc.directory"
PDS_BSKY_APP_VIEW_URL="https://api.bsky.app"
PDS_BSKY_APP_VIEW_DID="did:web:api.bsky.app"
PDS_CRAWLERS="https://bsky.network"

# OAuth Provider Configuration
PDS_OAUTH_PROVIDER_NAME="Your AT Protocol Server"
PDS_OAUTH_PROVIDER_LOGO=""
PDS_OAUTH_PROVIDER_PRIMARY_COLOR="#7507e3"
PDS_OAUTH_PROVIDER_ERROR_COLOR=""
PDS_OAUTH_PROVIDER_HOME_LINK=""
PDS_OAUTH_PROVIDER_TOS_LINK=""
PDS_OAUTH_PROVIDER_POLICY_LINK=""
PDS_OAUTH_PROVIDER_SUPPORT_LINK=""

# Production settings
NODE_TLS_REJECT_UNAUTHORIZED=1
LOG_ENABLED=1
LOG_LEVEL=info
PDS_INVITE_REQUIRED=0
PDS_DISABLE_SSRF_PROTECTION=0
```

### BSky AppView Configuration (`services/bsky/.env`)

```bash
# AppView Configuration
PORT=3000
NODE_ENV=production

# Database (if using external PostgreSQL)
DATABASE_URL="postgresql://username:password@localhost:5432/bsky_appview"

# Redis (if using external Redis)
REDIS_URL="redis://localhost:6379"

# PDS URL
PDS_URL="http://localhost:2583"

# Logging
LOG_ENABLED=1
LOG_LEVEL=info
```

### Ozone Configuration (`services/ozone/.env`)

```bash
# Ozone Configuration
PORT=3000
NODE_ENV=production

# Database
DATABASE_URL="postgresql://username:password@localhost:5432/ozone"

# PDS URL
PDS_URL="http://localhost:2583"

# Admin credentials
OZONE_ADMIN_PASSWORD="your-ozone-admin-password"

# Logging
LOG_ENABLED=1
LOG_LEVEL=info
```

### BSync Configuration (`services/bsync/.env`)

```bash
# BSync Configuration
BSYNC_PORT=3000
NODE_ENV=production

# PDS URL
PDS_URL="http://localhost:2583"

# Logging
LOG_ENABLED=1
LOG_LEVEL=info
```

## Step 5: Database Setup

### Create PostgreSQL Databases

```bash
# Connect to PostgreSQL as postgres user
sudo -u postgres psql

# Create databases and users
CREATE DATABASE pds;
CREATE DATABASE bsky_appview;
CREATE DATABASE ozone;
CREATE DATABASE bsync;

# Create user (replace with your desired username/password)
CREATE USER atproto WITH PASSWORD 'atproto';
GRANT ALL PRIVILEGES ON DATABASE pds TO atproto;
GRANT ALL PRIVILEGES ON DATABASE bsky_appview TO atproto;
GRANT ALL PRIVILEGES ON DATABASE ozone TO atproto;
GRANT ALL PRIVILEGES ON DATABASE bsync TO atproto;

# Exit PostgreSQL
\q
```

## Step 6: Docker Compose Setup

Create a `docker-compose.yml` file in the root directory:

```yaml
version: '3.8'

services:
  # PostgreSQL Database
  postgres:
    image: postgres:14-alpine
    environment:
      POSTGRES_USER: atproto_user
      POSTGRES_PASSWORD: your-secure-password
      POSTGRES_DB: pds
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"
    restart: unless-stopped

  # Redis Cache
  redis:
    image: redis:7-alpine
    command: redis-server --save 60 1 --loglevel warning
    volumes:
      - redis_data:/data
    ports:
      - "6379:6379"
    restart: unless-stopped

  # PDS Service
  pds:
    build:
      context: .
      dockerfile: services/pds/Dockerfile
    environment:
      - PDS_HOSTNAME=your-domain.com
      - PDS_PORT=2583
      - PDS_DATA_DIRECTORY=/app/data
      - PDS_BLOBSTORE_DISK_LOCATION=/app/blobs
      - PDS_REPO_SIGNING_KEY_K256_PRIVATE_KEY_HEX=${PDS_REPO_SIGNING_KEY_K256_PRIVATE_KEY_HEX}
      - PDS_PLC_ROTATION_KEY_K256_PRIVATE_KEY_HEX=${PDS_PLC_ROTATION_KEY_K256_PRIVATE_KEY_HEX}
      - PDS_DPOP_SECRET=${PDS_DPOP_SECRET}
      - PDS_JWT_SECRET=${PDS_JWT_SECRET}
      - PDS_ADMIN_PASSWORD=${PDS_ADMIN_PASSWORD}
      - PDS_DID_PLC_URL=https://plc.directory
      - PDS_BSKY_APP_VIEW_URL=https://api.bsky.app
      - PDS_BSKY_APP_VIEW_DID=did:web:api.bsky.app
      - PDS_CRAWLERS=https://bsky.network
      - NODE_ENV=production
    volumes:
      - pds_data:/app/data
      - pds_blobs:/app/blobs
    ports:
      - "2583:2583"
    depends_on:
      - postgres
      - redis
    restart: unless-stopped

  # BSky AppView Service
  bsky:
    build:
      context: .
      dockerfile: services/bsky/Dockerfile
    environment:
      - PORT=3000
      - NODE_ENV=production
      - DATABASE_URL=postgresql://atproto_user:your-secure-password@postgres:5432/bsky_appview
      - REDIS_URL=redis://redis:6379
      - PDS_URL=http://pds:2583
    ports:
      - "3000:3000"
    depends_on:
      - postgres
      - redis
      - pds
    restart: unless-stopped

  # Ozone Service
  ozone:
    build:
      context: .
      dockerfile: services/ozone/Dockerfile
    environment:
      - PORT=3000
      - NODE_ENV=production
      - DATABASE_URL=postgresql://atproto_user:your-secure-password@postgres:5432/ozone
      - PDS_URL=http://pds:2583
      - OZONE_ADMIN_PASSWORD=${OZONE_ADMIN_PASSWORD}
    ports:
      - "3001:3000"
    depends_on:
      - postgres
      - pds
    restart: unless-stopped

  # BSync Service
  bsync:
    build:
      context: .
      dockerfile: services/bsync/Dockerfile
    environment:
      - BSYNC_PORT=3000
      - NODE_ENV=production
      - PDS_URL=http://pds:2583
    ports:
      - "3002:3000"
    depends_on:
      - pds
    restart: unless-stopped

volumes:
  postgres_data:
  redis_data:
  pds_data:
  pds_blobs:
```

## Step 7: Nginx Reverse Proxy Setup

Create an Nginx configuration file `/etc/nginx/sites-available/atproto`:

```nginx
server {
    listen 80;
    server_name your-domain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;

    # SSL Configuration (replace with your certificate paths)
    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    # Security headers
    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";

    # PDS API
    location /xrpc/ {
        proxy_pass http://localhost:2583;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # BSky AppView API
    location /xrpc/app.bsky. {
        proxy_pass http://localhost:3000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # Ozone Admin Interface
    location /ozone/ {
        proxy_pass http://localhost:3001/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }

    # BSync API
    location /bsync/ {
        proxy_pass http://localhost:3002/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

Enable the site and restart Nginx:

```bash
sudo ln -s /etc/nginx/sites-available/atproto /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

## Step 8: SSL Certificate Setup

Install Certbot and obtain SSL certificates:

```bash
# Install Certbot
sudo apt install certbot python3-certbot-nginx -y

# Obtain SSL certificate
sudo certbot --nginx -d your-domain.com

# Set up auto-renewal
sudo crontab -e
# Add this line: 0 12 * * * /usr/bin/certbot renew --quiet
```

## Step 9: Firewall Configuration

```bash
# Configure UFW firewall
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

## Step 10: Start Services

```bash
# Start all services
docker-compose up -d

# Check service status
docker-compose ps

# View logs
docker-compose logs -f
```

## Step 11: Initial Setup and Verification

### Register your PDS with the PLC

```bash
# Create a DID document for your PDS
curl -X POST https://plc.directory \
  -H "Content-Type: application/json" \
  -d '{
    "type": "com.atproto.sync.subscribeRepos",
    "did": "did:plc:your-did-here",
    "handle": "your-handle.bsky.social"
  }'
```

### Test your services

```bash
# Test PDS health
curl https://your-domain.com/xrpc/com.atproto.server.describeServer

# Test BSky AppView
curl https://your-domain.com/xrpc/app.bsky.feed.getTimeline

# Test Ozone admin interface
curl https://your-domain.com/ozone/
```

## Step 12: Monitoring and Maintenance

### Set up monitoring

```bash
# Install monitoring tools
sudo apt install htop iotop nethogs -y

# Set up log rotation
sudo nano /etc/logrotate.d/atproto
```

Add this content:

```
/var/log/atproto/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 root root
}
```

### Backup strategy

```bash
# Create backup script
sudo nano /usr/local/bin/atproto-backup.sh
```

```bash
#!/bin/bash
BACKUP_DIR="/backup/atproto"
DATE=$(date +%Y%m%d_%H%M%S)

# Create backup directory
mkdir -p $BACKUP_DIR

# Backup PostgreSQL databases
docker exec atproto_postgres_1 pg_dump -U atproto_user pds > $BACKUP_DIR/pds_$DATE.sql
docker exec atproto_postgres_1 pg_dump -U atproto_user bsky_appview > $BACKUP_DIR/bsky_appview_$DATE.sql
docker exec atproto_postgres_1 pg_dump -U atproto_user ozone > $BACKUP_DIR/ozone_$DATE.sql

# Backup PDS data
docker cp atproto_pds_1:/app/data $BACKUP_DIR/pds_data_$DATE
docker cp atproto_pds_1:/app/blobs $BACKUP_DIR/pds_blobs_$DATE

# Compress backups
tar -czf $BACKUP_DIR/atproto_backup_$DATE.tar.gz $BACKUP_DIR/*_$DATE*

# Clean up old backups (keep last 7 days)
find $BACKUP_DIR -name "atproto_backup_*.tar.gz" -mtime +7 -delete

echo "Backup completed: atproto_backup_$DATE.tar.gz"
```

Make it executable and set up cron:

```bash
sudo chmod +x /usr/local/bin/atproto-backup.sh
sudo crontab -e
# Add this line: 0 2 * * * /usr/local/bin/atproto-backup.sh
```

## Troubleshooting

### Common Issues

1. **Service won't start**: Check logs with `docker-compose logs [service-name]`
2. **Database connection issues**: Verify PostgreSQL is running and credentials are correct
3. **SSL certificate issues**: Check certificate paths and permissions
4. **Memory issues**: Monitor resource usage and consider upgrading server specs

### Useful Commands

```bash
# View all logs
docker-compose logs -f

# Restart a specific service
docker-compose restart [service-name]

# Update services
git pull
docker-compose build
docker-compose up -d

# Check resource usage
docker stats

# Access service shell
docker-compose exec [service-name] sh
```

## Security Considerations

1. **Keep private keys secure**: Store them in environment variables, not in code
2. **Regular updates**: Keep all software updated
3. **Firewall**: Only expose necessary ports
4. **Backups**: Regular automated backups
5. **Monitoring**: Set up alerts for service failures
6. **Access control**: Limit admin access to Ozone interface

## Performance Optimization

1. **Database tuning**: Optimize PostgreSQL configuration for your workload
2. **Redis caching**: Ensure Redis is properly configured
3. **CDN**: Consider using a CDN for static assets
4. **Load balancing**: For high traffic, consider multiple server instances
5. **Monitoring**: Use tools like Prometheus and Grafana for detailed metrics

## Next Steps

1. **Custom branding**: Update OAuth provider settings
2. **User onboarding**: Set up invite system or open registration
3. **Content moderation**: Configure Ozone rules and policies
4. **Analytics**: Set up monitoring and analytics
5. **Scaling**: Plan for horizontal scaling as your user base grows

This setup provides a production-ready AT Protocol service stack. Remember to regularly monitor your services, keep backups, and stay updated with the latest releases.
