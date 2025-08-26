#!/bin/bash

# AT Protocol Native Deployment Script (Without Docker)
# This script automates the setup of AT Protocol services natively

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   print_error "This script should not be run as root"
   exit 1
fi

# Configuration
DOMAIN=""
ADMIN_EMAIL=""
DB_PASSWORD=""
PDS_SIGNING_KEY=""
PDS_ROTATION_KEY=""
PDS_DPOP_SECRET=""
PDS_JWT_SECRET=""
PDS_ADMIN_PASSWORD=""
OZONE_ADMIN_PASSWORD=""
USE_SYSTEMD=false

# Function to get user input
get_input() {
    local prompt="$1"
    local var_name="$2"
    local default="$3"

    if [[ -n "$default" ]]; then
        read -p "$prompt [$default]: " input
        eval "$var_name=\${input:-$default}"
    else
        read -p "$prompt: " input
        eval "$var_name=\$input"
    fi
}

# Function to generate random hex string
generate_hex() {
    openssl rand -hex 32
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to install Node.js and pnpm
install_nodejs() {
    print_status "Installing Node.js and pnpm..."

    if command_exists node && command_exists pnpm; then
        print_success "Node.js and pnpm are already installed"
        return
    fi

    # Install Node.js 18
    curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
    sudo apt-get install -y nodejs

    # Install pnpm
    npm install -g pnpm

    print_success "Node.js and pnpm installed successfully"
}

# Function to install PostgreSQL
install_postgresql() {
    print_status "Installing PostgreSQL..."

    if command_exists psql; then
        print_success "PostgreSQL is already installed"
        return
    fi

    sudo apt install postgresql postgresql-contrib -y
    sudo systemctl start postgresql
    sudo systemctl enable postgresql

    # Set up database user and databases
    sudo -u postgres psql << EOF
CREATE USER atproto WITH PASSWORD '$DB_PASSWORD';
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

    print_success "PostgreSQL installed and configured"
}

# Function to install Redis
install_redis() {
    print_status "Installing Redis..."

    if command_exists redis-server; then
        print_success "Redis is already installed"
        return
    fi

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

    sudo systemctl restart redis-server
    sudo systemctl enable redis-server

    print_success "Redis installed and configured"
}

# Function to install PM2
install_pm2() {
    print_status "Installing PM2..."

    if command_exists pm2; then
        print_success "PM2 is already installed"
        return
    fi

    npm install -g pm2
    pm2 startup

    print_success "PM2 installed successfully"
}

# Function to install Nginx
install_nginx() {
    print_status "Installing Nginx..."

    if command_exists nginx; then
        print_success "Nginx is already installed"
        return
    fi

    sudo apt install nginx -y
    sudo systemctl start nginx
    sudo systemctl enable nginx

    print_success "Nginx installed successfully"
}

# Function to setup service directories
setup_directories() {
    print_status "Setting up service directories..."

    sudo mkdir -p /opt/atproto/{pds,bsky,ozone,bsync}
    sudo mkdir -p /opt/atproto/data/{pds,bsky,ozone,bsync}
    sudo mkdir -p /opt/atproto/logs
    sudo mkdir -p /opt/atproto/blobs
    sudo chown -R $USER:$USER /opt/atproto

    print_success "Service directories created"
}

# Function to generate environment files
generate_env_files() {
    print_status "Generating environment files..."

    # Create PDS configuration
    cat > /opt/atproto/pds/.env << EOF
# PDS Configuration
PDS_HOSTNAME="$DOMAIN"
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

          # Create BSky configuration
      cat > /opt/atproto/bsky/.env << EOF
# BSky AppView Configuration
BSKY_PORT=3000
NODE_ENV=production
BSKY_PUBLIC_URL="https://$DOMAIN"
BSKY_SERVER_DID="did:web:$DOMAIN"
BSKY_DID_PLC_URL="https://plc.directory"
BSKY_DATAPLANE_URLS="http://localhost:2583"
BSKY_BSYNC_URL="http://localhost:3002"
BSKY_SERVICE_SIGNING_KEY="did:key:zQ3shZc2QzApp2oymGvQbzP8eKheVshBHbU4ZYjeXqwSKEn6N"
BSKY_ADMIN_PASSWORDS="$PDS_ADMIN_PASSWORD"
MOD_SERVICE_DID="did:web:$DOMAIN"
BSKY_ETCD_HOSTS=""
BSKY_DATAPLANE_HTTP_VERSION="2"
BSKY_BSYNC_HTTP_VERSION="2"
LOG_ENABLED=1
LOG_LEVEL=info
EOF

          # Create Ozone configuration
      cat > /opt/atproto/ozone/.env << EOF
# Ozone Configuration
OZONE_PORT=3001
NODE_ENV=production
OZONE_PUBLIC_URL="https://$DOMAIN"
OZONE_SERVER_DID="did:web:$DOMAIN"
OZONE_DB_POSTGRES_URL="postgresql://atproto:$DB_PASSWORD@localhost:5432/ozone"
OZONE_DB_POSTGRES_SCHEMA="ozone"
OZONE_APPVIEW_URL="http://localhost:3000"
OZONE_APPVIEW_DID="did:web:$DOMAIN"
OZONE_PDS_URL="http://localhost:2583"
OZONE_PDS_DID="did:web:$DOMAIN"
OZONE_DID_PLC_URL="https://plc.directory"
OZONE_ADMIN_PASSWORD="$OZONE_ADMIN_PASSWORD"
OZONE_ADMIN_DIDS="did:web:$DOMAIN"
OZONE_MODERATOR_DIDS=""
OZONE_TRIAGE_DIDS=""
OZONE_SIGNING_KEY_HEX="$(openssl rand -hex 32)"
LOG_ENABLED=1
LOG_LEVEL=info
EOF

          # Create BSync configuration
      cat > /opt/atproto/bsync/.env << EOF
# BSync Configuration
BSYNC_PORT=3002
NODE_ENV=production
BSYNC_DB_POSTGRES_URL="postgresql://atproto:$DB_PASSWORD@localhost:5432/bsync"
BSYNC_DB_POSTGRES_SCHEMA="bsync"
BSYNC_DB_MIGRATE=true
LOG_ENABLED=1
LOG_LEVEL=info
EOF

    print_success "Environment files generated"
}

# Function to create PM2 configuration
create_pm2_config() {
    print_status "Creating PM2 configuration..."

    cat > /opt/atproto/ecosystem.config.js << EOF
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

    print_success "PM2 configuration created"
}

# Function to create systemd services
create_systemd_services() {
    print_status "Creating systemd services..."

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

    sudo systemctl daemon-reload
    sudo systemctl enable atproto-pds atproto-bsky atproto-ozone atproto-bsync

    print_success "Systemd services created"
}

# Function to setup Nginx
setup_nginx() {
    print_status "Setting up Nginx..."

    # Create Nginx configuration
    sudo tee /etc/nginx/sites-available/atproto > /dev/null << EOF
server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$server_name\$request_uri;
}

server {
    listen 443 ssl http2;
    server_name $DOMAIN;

    ssl_certificate /etc/letsencrypt/live/$DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$DOMAIN/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-RSA-AES256-GCM-SHA512:DHE-RSA-AES256-GCM-SHA512:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;

    add_header X-Frame-Options DENY;
    add_header X-Content-Type-Options nosniff;
    add_header X-XSS-Protection "1; mode=block";
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload";

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

    print_success "Nginx configured"
}

# Function to setup SSL certificate
setup_ssl() {
    print_status "Setting up SSL certificate..."

    # Install Certbot
    sudo apt install certbot python3-certbot-nginx -y

    # Temporarily disable HTTPS redirect
    sudo sed -i 's/return 301 https/# return 301 https/' /etc/nginx/sites-available/atproto
    sudo systemctl reload nginx

    # Generate certificate
    sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos --email $ADMIN_EMAIL

    # Re-enable HTTPS redirect
    sudo sed -i 's/# return 301 https/return 301 https/' /etc/nginx/sites-available/atproto
    sudo systemctl reload nginx

    # Setup auto-renewal
    (crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | crontab -

    print_success "SSL certificate configured"
}

# Function to setup firewall
setup_firewall() {
    print_status "Setting up firewall..."

    sudo ufw allow ssh
    sudo ufw allow 80/tcp
    sudo ufw allow 443/tcp
    sudo ufw --force enable

    print_success "Firewall configured"
}

# Function to build and start services
build_and_start_services() {
    print_status "Building and starting AT Protocol services..."

    # Copy AT Protocol files to production directory
    sudo cp -r . /opt/atproto/
    sudo chown -R $USER:$USER /opt/atproto

    # Navigate to production directory
    cd /opt/atproto

    # Install dependencies and build
    pnpm install
    pnpm build

    if [ "$USE_SYSTEMD" = true ]; then
        # Start services with systemd
        sudo systemctl start atproto-pds atproto-bsky atproto-ozone atproto-bsync
        print_success "Services started with systemd"
    else
        # Start services with PM2
        pm2 start ecosystem.config.js
        pm2 save
        pm2 startup
        print_success "Services started with PM2"
    fi
}

# Function to create backup script
create_backup_script() {
    print_status "Creating backup script..."

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

    print_success "Backup script created"
}

# Function to display final information
display_final_info() {
    print_success "AT Protocol native deployment completed!"
    echo
    echo "Your AT Protocol services are now running at:"
    echo "  - PDS API: https://$DOMAIN/xrpc/"
    echo "  - BSky AppView: https://$DOMAIN/xrpc/app.bsky.*"
    echo "  - Ozone Admin: https://$DOMAIN/ozone/"
    echo "  - BSync API: https://$DOMAIN/bsync/"
    echo
    echo "Admin credentials:"
    echo "  - PDS Admin Password: $PDS_ADMIN_PASSWORD"
    echo "  - Ozone Admin Password: $OZONE_ADMIN_PASSWORD"
    echo
    if [ "$USE_SYSTEMD" = true ]; then
        echo "Services are managed with systemd:"
        echo "  - View status: sudo systemctl status atproto-*"
        echo "  - Restart services: sudo systemctl restart atproto-*"
        echo "  - View logs: sudo journalctl -u atproto-pds -f"
    else
        echo "Services are managed with PM2:"
        echo "  - View status: pm2 list"
        echo "  - Restart services: pm2 restart all"
        echo "  - View logs: pm2 logs"
    fi
    echo
    echo "Useful commands:"
    echo "  - Manual backup: /usr/local/bin/atproto-backup.sh"
    echo "  - Monitor resources: htop"
    echo
    echo "Next steps:"
    echo "  1. Register your PDS with the PLC directory"
    echo "  2. Configure Ozone moderation rules"
    echo "  3. Set up monitoring and alerts"
    echo "  4. Customize branding and settings"
}

# Main deployment function
main() {
    echo "AT Protocol Native Deployment Script"
    echo "===================================="
    echo

    # Get user input
    get_input "Enter your domain name" DOMAIN
    get_input "Enter admin email for SSL certificate" ADMIN_EMAIL
    get_input "Enter database password" DB_PASSWORD

    # Ask about process manager preference
    read -p "Use systemd instead of PM2? (y/N): " use_systemd
    if [[ $use_systemd =~ ^[Yy]$ ]]; then
        USE_SYSTEMD=true
    fi

    # Generate cryptographic keys
    print_status "Generating cryptographic keys..."
    PDS_SIGNING_KEY=$(generate_hex)
    PDS_ROTATION_KEY=$(generate_hex)
    PDS_DPOP_SECRET=$(generate_hex)
    PDS_JWT_SECRET=$(generate_hex)
    PDS_ADMIN_PASSWORD=$(openssl rand -hex 16)
    OZONE_ADMIN_PASSWORD=$(openssl rand -hex 16)

    print_success "Keys generated"

    # Install dependencies
    install_nodejs
    install_postgresql
    install_redis

    if [ "$USE_SYSTEMD" = true ]; then
        print_status "Using systemd for process management"
    else
        install_pm2
    fi

    install_nginx

    # Setup services
    setup_directories
    generate_env_files

    if [ "$USE_SYSTEMD" = true ]; then
        create_systemd_services
    else
        create_pm2_config
    fi

    setup_nginx
    setup_ssl
    setup_firewall
    build_and_start_services
    create_backup_script

    # Display final information
    display_final_info
}

# Run main function
main "$@"
