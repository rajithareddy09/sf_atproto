# AT Protocol Native Setup Guide (Without Docker)

This guide shows you how to set up AT Protocol services directly on your system without using Docker containers.

## Overview

Running AT Protocol services natively provides:
- **Better performance** - No container overhead
- **Easier debugging** - Direct access to logs and processes
- **More control** - Direct system integration
- **Resource efficiency** - Lower memory and CPU usage

## Prerequisites

- **Server Requirements:**
  - Linux server (Ubuntu 20.04+ recommended)
  - 4+ CPU cores
  - 8GB+ RAM
  - 100GB+ storage
  - Public IP address
  - Domain name

- **Software Requirements:**
  - Node.js 18+
  - pnpm package manager
  - PostgreSQL 14+
  - Redis 7+
  - Nginx (for reverse proxy)
  - PM2 (for process management)
  - SSL certificate (Let's Encrypt recommended)

## Step 1: System Preparation

### Update System

```bash
sudo apt update && sudo apt upgrade -y
```

### Install Node.js and pnpm

```bash
# Install Node.js 18
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt-get install -y nodejs

# Install pnpm
npm install -g pnpm

# Verify installation
node --version
pnpm --version
```

### Install PostgreSQL

```bash
# Install PostgreSQL
sudo apt install postgresql postgresql-contrib -y

# Start and enable PostgreSQL
sudo systemctl start postgresql
sudo systemctl enable postgresql

# Set up database user and databases
sudo -u postgres psql << EOF
CREATE USER atproto WITH PASSWORD 'your-secure-password';
CREATE DATABASE pds;
CREATE DATABASE bsky_appview;
CREATE DATABASE ozone;
CREATE DATABASE bsync;
GRANT ALL PRIVILEGES ON DATABASE pds TO atproto;
GRANT ALL PRIVILEGES ON DATABASE bsky_appview TO atproto;
GRANT ALL PRIVILEGES ON DATABASE ozone TO atproto;
GRANT ALL PRIVILEGES ON DATABASE bsync TO atproto;
\q
EOF
```

### Install Redis

```bash
# Install Redis
sudo apt install redis-server -y

# Configure Redis for production
sudo tee /etc/redis/redis.conf > /dev/null << EOF
# Redis configuration for production
bind 127.0.0.1
port 6379
timeout 300
tcp-keepalive 60
loglevel notice
logfile /var/log/redis/redis-server.log
databases 16
save 900 1
save 300 10
save 60 10000
stop-writes-on-bgsave-error yes
rdbcompression yes
rdbchecksum yes
dbfilename dump.rdb
dir /var/lib/redis
maxmemory 256mb
maxmemory-policy allkeys-lru
appendonly yes
appendfilename "appendonly.aof"
appendfsync everysec
no-appendfsync-on-rewrite no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 64mb
EOF

# Start and enable Redis
sudo systemctl restart redis-server
sudo systemctl enable redis-server
```

### Install PM2 (Process Manager)

```bash
# Install PM2 globally
npm install -g pm2

# Install PM2 startup script
pm2 startup
```

### Install Nginx

```bash
# Install Nginx
sudo apt install nginx -y

# Start and enable Nginx
sudo systemctl start nginx
sudo systemctl enable nginx
```

## Step 2: Clone and Build AT Protocol

```bash
# Clone the repository
git clone https://github.com/bluesky-social/atproto.git
cd atproto

# Install dependencies
pnpm install

# Build all packages
pnpm build
```

## Step 3: Generate Cryptographic Keys

```bash
# Generate cryptographic keys
PDS_SIGNING_KEY=$(openssl rand -hex 32)
PDS_ROTATION_KEY=$(openssl rand -hex 32)
PDS_DPOP_SECRET=$(openssl rand -hex 32)
PDS_JWT_SECRET=$(openssl rand -hex 32)
PDS_ADMIN_PASSWORD=$(openssl rand -hex 16)
OZONE_ADMIN_PASSWORD=$(openssl rand -hex 16)

# Save keys to a secure file
cat > .env << EOF
# AT Protocol Production Environment Variables
DOMAIN=your-domain.com
DB_PASSWORD=your-secure-password
PDS_REPO_SIGNING_KEY_K256_PRIVATE_KEY_HEX=$PDS_SIGNING_KEY
PDS_PLC_ROTATION_KEY_K256_PRIVATE_KEY_HEX=$PDS_ROTATION_KEY
PDS_DPOP_SECRET=$PDS_DPOP_SECRET
PDS_JWT_SECRET=$PDS_JWT_SECRET
PDS_ADMIN_PASSWORD=$PDS_ADMIN_PASSWORD
OZONE_ADMIN_PASSWORD=$OZONE_ADMIN_PASSWORD
EOF

# Secure the environment file
chmod 600 .env
```

## Step 4: Configure Services

### Create Service Directories

```bash
# Create directories for each service
mkdir -p /opt/atproto/{pds,bsky,ozone,bsync}
mkdir -p /opt/atproto/data/{pds,bsky,ozone,bsync}
mkdir -p /opt/atproto/logs
mkdir -p /opt/atproto/blobs

# Set permissions
sudo chown -R $USER:$USER /opt/atproto
```

### PDS Configuration

```bash
# Create PDS configuration
cat > /opt/atproto/pds/.env << EOF
# PDS Configuration
PDS_HOSTNAME="your-domain.com"
PDS_PORT="2583"
PDS_DATA_DIRECTORY="/opt/atproto/data/pds"
PDS_BLOBSTORE_DISK_LOCATION="/opt/atproto/blobs"
PDS_REPO_SIGNING_KEY_K256_PRIVATE_KEY_HEX="$PDS_SIGNING_KEY"
PDS_PLC_ROTATION_KEY_K256_PRIVATE_KEY_HEX="$PDS_ROTATION_KEY"
PDS_DPOP_SECRET="$PDS_DPOP_SECRET"
PDS_JWT_SECRET="$PDS_JWT_SECRET"
PDS_ADMIN_PASSWORD="$PDS_ADMIN_PASSWORD"
PDS_DID_PLC_URL="https://plc.directory"
PDS_BSKY_APP_VIEW_URL="https://api.bsky.app"
PDS_BSKY_APP_VIEW_DID="did:web:api.bsky.app"
PDS_CRAWLERS="https://bsky.network"
PDS_OAUTH_PROVIDER_NAME="AT Protocol Server"
PDS_OAUTH_PROVIDER_PRIMARY_COLOR="#7507e3"
NODE_TLS_REJECT_UNAUTHORIZED=1
LOG_ENABLED=1
LOG_LEVEL=info
PDS_INVITE_REQUIRED=0
PDS_DISABLE_SSRF_PROTECTION=0
EOF
```

### BSky AppView Configuration

```bash
# Create BSky configuration
cat > /opt/atproto/bsky/.env << EOF
# BSky AppView Configuration
PORT=3000
NODE_ENV=production
DATABASE_URL="postgresql://atproto:your-secure-password@localhost:5432/bsky_appview"
REDIS_URL="redis://localhost:6379"
PDS_URL="http://localhost:2583"
LOG_ENABLED=1
LOG_LEVEL=info
EOF
```

### Ozone Configuration

```bash
# Create Ozone configuration
cat > /opt/atproto/ozone/.env << EOF
# Ozone Configuration
PORT=3000
NODE_ENV=production
DATABASE_URL="postgresql://atproto:your-secure-password@localhost:5432/ozone"
PDS_URL="http://localhost:2583"
OZONE_ADMIN_PASSWORD="$OZONE_ADMIN_PASSWORD"
LOG_ENABLED=1
LOG_LEVEL=info
EOF
```

### BSync Configuration

```bash
# Create BSync configuration
cat > /opt/atproto/bsync/.env << EOF
# BSync Configuration
BSYNC_PORT=3000
NODE_ENV=production
PDS_URL="http://localhost:2583"
LOG_ENABLED=1
LOG_LEVEL=info
EOF
```

## Step 5: Create PM2 Configuration

```bash
# Create PM2 ecosystem file
cat > ecosystem.config.js << EOF
module.exports = {
  apps: [
    {
      name: 'pds',
      script: 'packages/pds/src/index.ts',
      cwd: '/opt/atproto',
      env_file: '/opt/atproto/pds/.env',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '1G',
      log_file: '/opt/atproto/logs/pds.log',
      out_file: '/opt/atproto/logs/pds-out.log',
      error_file: '/opt/atproto/logs/pds-error.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      env: {
        NODE_ENV: 'production'
      }
    },
    {
      name: 'bsky',
      script: 'packages/bsky/src/index.ts',
      cwd: '/opt/atproto',
      env_file: '/opt/atproto/bsky/.env',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '1G',
      log_file: '/opt/atproto/logs/bsky.log',
      out_file: '/opt/atproto/logs/bsky-out.log',
      error_file: '/opt/atproto/logs/bsky-error.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      env: {
        NODE_ENV: 'production'
      }
    },
    {
      name: 'ozone',
      script: 'packages/ozone/src/index.ts',
      cwd: '/opt/atproto',
      env_file: '/opt/atproto/ozone/.env',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '1G',
      log_file: '/opt/atproto/logs/ozone.log',
      out_file: '/opt/atproto/logs/ozone-out.log',
      error_file: '/opt/atproto/logs/ozone-error.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      env: {
        NODE_ENV: 'production'
      }
    },
    {
      name: 'bsync',
      script: 'packages/bsync/src/index.ts',
      cwd: '/opt/atproto',
      env_file: '/opt/atproto/bsync/.env',
      instances: 1,
      autorestart: true,
      watch: false,
      max_memory_restart: '1G',
      log_file: '/opt/atproto/logs/bsync.log',
      out_file: '/opt/atproto/logs/bsync-out.log',
      error_file: '/opt/atproto/logs/bsync-error.log',
      log_date_format: 'YYYY-MM-DD HH:mm:ss Z',
      env: {
        NODE_ENV: 'production'
      }
    }
  ]
};
EOF
```

## Step 6: Setup Nginx Configuration

```bash
# Create Nginx configuration
sudo tee /etc/nginx/sites-available/atproto > /dev/null << EOF
server {
    listen 80;
    server_name your-domain.com;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;

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
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # BSky AppView API
    location /xrpc/app.bsky. {
        proxy_pass http://localhost:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # Ozone Admin Interface
    location /ozone/ {
        proxy_pass http://localhost:3001/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }

    # BSync API
    location /bsync/ {
        proxy_pass http://localhost:3002/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
}
EOF

# Enable the site
sudo ln -sf /etc/nginx/sites-available/atproto /etc/nginx/sites-enabled/
sudo nginx -t
sudo systemctl restart nginx
```

## Step 7: Setup SSL Certificate

```bash
# Install Certbot
sudo apt install certbot python3-certbot-nginx -y

# Temporarily disable HTTPS redirect
sudo sed -i 's/return 301 https/# return 301 https/' /etc/nginx/sites-available/atproto
sudo systemctl reload nginx

# Generate certificate
sudo certbot --nginx -d your-domain.com --non-interactive --agree-tos --email your-email@example.com

# Re-enable HTTPS redirect
sudo sed -i 's/# return 301 https/return 301 https/' /etc/nginx/sites-available/atproto
sudo systemctl reload nginx

# Setup auto-renewal
(crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -
```

## Step 8: Setup Firewall

```bash
# Configure UFW firewall
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable
```

## Step 9: Start Services

```bash
# Copy AT Protocol files to production directory
sudo cp -r . /opt/atproto/
sudo chown -R $USER:$USER /opt/atproto

# Navigate to production directory
cd /opt/atproto

# Start all services with PM2
pm2 start ecosystem.config.js

# Save PM2 configuration
pm2 save

# Setup PM2 to start on boot
pm2 startup
```

## Step 10: Create Systemd Service Files (Alternative to PM2)

If you prefer systemd over PM2, create service files:

```bash
# Create PDS service
sudo tee /etc/systemd/system/atproto-pds.service > /dev/null << EOF
[Unit]
Description=AT Protocol PDS Service
After=network.target postgresql.service redis-server.service

[Service]
Type=simple
User=$USER
WorkingDirectory=/opt/atproto
Environment=NODE_ENV=production
ExecStart=/usr/bin/node packages/pds/src/index.ts
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=atproto-pds

[Install]
WantedBy=multi-user.target
EOF

# Create BSky service
sudo tee /etc/systemd/system/atproto-bsky.service > /dev/null << EOF
[Unit]
Description=AT Protocol BSky AppView Service
After=network.target postgresql.service redis-server.service atproto-pds.service

[Service]
Type=simple
User=$USER
WorkingDirectory=/opt/atproto
Environment=NODE_ENV=production
ExecStart=/usr/bin/node packages/bsky/src/index.ts
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=atproto-bsky

[Install]
WantedBy=multi-user.target
EOF

# Create Ozone service
sudo tee /etc/systemd/system/atproto-ozone.service > /dev/null << EOF
[Unit]
Description=AT Protocol Ozone Service
After=network.target postgresql.service atproto-pds.service

[Service]
Type=simple
User=$USER
WorkingDirectory=/opt/atproto
Environment=NODE_ENV=production
ExecStart=/usr/bin/node packages/ozone/src/index.ts
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=atproto-ozone

[Install]
WantedBy=multi-user.target
EOF

# Create BSync service
sudo tee /etc/systemd/system/atproto-bsync.service > /dev/null << EOF
[Unit]
Description=AT Protocol BSync Service
After=network.target atproto-pds.service

[Service]
Type=simple
User=$USER
WorkingDirectory=/opt/atproto
Environment=NODE_ENV=production
ExecStart=/usr/bin/node packages/bsync/src/index.ts
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal
SyslogIdentifier=atproto-bsync

[Install]
WantedBy=multi-user.target
EOF

# Enable and start services
sudo systemctl daemon-reload
sudo systemctl enable atproto-pds atproto-bsky atproto-ozone atproto-bsync
sudo systemctl start atproto-pds atproto-bsky atproto-ozone atproto-bsync
```

## Step 11: Create Backup Script

```bash
# Create backup script
sudo tee /usr/local/bin/atproto-backup.sh > /dev/null << 'EOF'
#!/bin/bash
BACKUP_DIR="/backup/atproto"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR

# Backup PostgreSQL databases
pg_dump -U atproto pds > $BACKUP_DIR/pds_$DATE.sql
pg_dump -U atproto bsky_appview > $BACKUP_DIR/bsky_appview_$DATE.sql
pg_dump -U atproto ozone > $BACKUP_DIR/ozone_$DATE.sql

# Backup PDS data
cp -r /opt/atproto/data/pds $BACKUP_DIR/pds_data_$DATE
cp -r /opt/atproto/blobs $BACKUP_DIR/pds_blobs_$DATE

# Compress backups
tar -czf $BACKUP_DIR/atproto_backup_$DATE.tar.gz $BACKUP_DIR/*_$DATE*

# Clean up old backups (keep last 7 days)
find $BACKUP_DIR -name "atproto_backup_*.tar.gz" -mtime +7 -delete

echo "Backup completed: atproto_backup_$DATE.tar.gz"
EOF

sudo chmod +x /usr/local/bin/atproto-backup.sh

# Setup daily backup
(crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/atproto-backup.sh") | crontab -
```

## Step 12: Monitoring and Logs

### View Service Status

```bash
# If using PM2
pm2 status
pm2 logs

# If using systemd
sudo systemctl status atproto-pds atproto-bsky atproto-ozone atproto-bsync
sudo journalctl -u atproto-pds -f
```

### Monitor Resources

```bash
# Install monitoring tools
sudo apt install htop iotop nethogs -y

# Monitor system resources
htop
iotop
nethogs
```

### Log Rotation

```bash
# Setup log rotation
sudo tee /etc/logrotate.d/atproto > /dev/null << EOF
/opt/atproto/logs/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 644 $USER $USER
}
EOF
```

## Useful Commands

### PM2 Commands
```bash
# View all processes
pm2 list

# Restart all services
pm2 restart all

# Restart specific service
pm2 restart pds

# View logs
pm2 logs

# View specific service logs
pm2 logs pds

# Monitor resources
pm2 monit
```

### Systemd Commands
```bash
# View service status
sudo systemctl status atproto-pds

# Restart service
sudo systemctl restart atproto-pds

# View logs
sudo journalctl -u atproto-pds -f

# Enable/disable services
sudo systemctl enable atproto-pds
sudo systemctl disable atproto-pds
```

### Database Commands
```bash
# Connect to PostgreSQL
psql -U atproto -d pds

# Backup database
pg_dump -U atproto pds > backup.sql

# Restore database
psql -U atproto -d pds < backup.sql
```

## Troubleshooting

### Common Issues

1. **Service won't start**: Check logs and environment variables
2. **Database connection issues**: Verify PostgreSQL is running and credentials are correct
3. **Port conflicts**: Ensure ports 2583, 3000, 3001, 3002 are available
4. **Permission issues**: Check file ownership and permissions

### Performance Tuning

1. **PostgreSQL tuning**: Adjust `postgresql.conf` for your workload
2. **Redis tuning**: Monitor memory usage and adjust `maxmemory` setting
3. **Node.js tuning**: Adjust PM2 memory limits and instance counts
4. **System tuning**: Optimize kernel parameters for high concurrency

## Advantages of Native Setup

- **Better Performance**: No container overhead
- **Easier Debugging**: Direct access to processes and logs
- **Resource Efficiency**: Lower memory and CPU usage
- **System Integration**: Direct access to system resources
- **Simpler Updates**: Direct file updates without rebuilding containers

## Disadvantages

- **More Complex Setup**: Manual configuration required
- **System Dependencies**: Direct dependency on system packages
- **Less Isolation**: Services share system resources
- **Manual Scaling**: More complex horizontal scaling

This native setup provides excellent performance and control while maintaining all the functionality of the Docker-based setup.
