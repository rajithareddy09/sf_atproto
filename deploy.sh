#!/bin/bash

# AT Protocol Production Deployment Script
# This script automates the setup of AT Protocol services

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

# Function to install Docker
install_docker() {
    print_status "Installing Docker..."

    if command_exists docker; then
        print_success "Docker is already installed"
        return
    fi

    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    rm get-docker.sh

    print_success "Docker installed successfully"
    print_warning "Please logout and login again for Docker group changes to take effect"
}

# Function to install Docker Compose
install_docker_compose() {
    print_status "Installing Docker Compose..."

    if command_exists docker-compose; then
        print_success "Docker Compose is already installed"
        return
    fi

    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose

    print_success "Docker Compose installed successfully"
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

# Function to install system dependencies
install_system_deps() {
    print_status "Installing system dependencies..."

    sudo apt update
    sudo apt install -y postgresql postgresql-contrib redis-server nginx certbot python3-certbot-nginx htop iotop nethogs

    # Start and enable services
    sudo systemctl start postgresql
    sudo systemctl enable postgresql
    sudo systemctl start redis-server
    sudo systemctl enable redis-server

    print_success "System dependencies installed successfully"
}

# Function to setup database
setup_database() {
    print_status "Setting up PostgreSQL databases..."

    # Create databases and user
    sudo -u postgres psql << EOF
CREATE DATABASE pds;
CREATE DATABASE bsky_appview;
CREATE DATABASE ozone;
CREATE DATABASE bsync;
CREATE USER atproto_user WITH PASSWORD '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON DATABASE pds TO atproto_user;
GRANT ALL PRIVILEGES ON DATABASE bsky_appview TO atproto_user;
GRANT ALL PRIVILEGES ON DATABASE ozone TO atproto_user;
GRANT ALL PRIVILEGES ON DATABASE bsync TO atproto_user;
\q
EOF

    print_success "Databases setup completed"
}

# Function to generate environment files
generate_env_files() {
    print_status "Generating environment files..."

    # Create .env file for docker-compose
    cat > .env << EOF
# AT Protocol Production Environment Variables
DOMAIN=$DOMAIN
DB_PASSWORD=$DB_PASSWORD
PDS_REPO_SIGNING_KEY_K256_PRIVATE_KEY_HEX=$PDS_SIGNING_KEY
PDS_PLC_ROTATION_KEY_K256_PRIVATE_KEY_HEX=$PDS_ROTATION_KEY
PDS_DPOP_SECRET=$PDS_DPOP_SECRET
PDS_JWT_SECRET=$PDS_JWT_SECRET
PDS_ADMIN_PASSWORD=$PDS_ADMIN_PASSWORD
OZONE_ADMIN_PASSWORD=$OZONE_ADMIN_PASSWORD
EOF

    # Create PDS environment file
    mkdir -p services/pds
    cat > services/pds/.env << EOF
# PDS Configuration
PDS_HOSTNAME="$DOMAIN"
PDS_PORT="2583"
PDS_DATA_DIRECTORY="data"
PDS_BLOBSTORE_DISK_LOCATION="blobs"
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

    # Create BSky environment file
    mkdir -p services/bsky
    cat > services/bsky/.env << EOF
# BSky AppView Configuration
PORT=3000
NODE_ENV=production
DATABASE_URL="postgresql://atproto_user:$DB_PASSWORD@localhost:5432/bsky_appview"
REDIS_URL="redis://localhost:6379"
PDS_URL="http://localhost:2583"
LOG_ENABLED=1
LOG_LEVEL=info
EOF

    # Create Ozone environment file
    mkdir -p services/ozone
    cat > services/ozone/.env << EOF
# Ozone Configuration
PORT=3000
NODE_ENV=production
DATABASE_URL="postgresql://atproto_user:$DB_PASSWORD@localhost:5432/ozone"
PDS_URL="http://localhost:2583"
OZONE_ADMIN_PASSWORD="$OZONE_ADMIN_PASSWORD"
LOG_ENABLED=1
LOG_LEVEL=info
EOF

    # Create BSync environment file
    mkdir -p services/bsync
    cat > services/bsync/.env << EOF
# BSync Configuration
BSYNC_PORT=3000
NODE_ENV=production
PDS_URL="http://localhost:2583"
LOG_ENABLED=1
LOG_LEVEL=info
EOF

    print_success "Environment files generated"
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
    }

    location /xrpc/app.bsky. {
        proxy_pass http://localhost:3000;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /ozone/ {
        proxy_pass http://localhost:3001/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    location /bsync/ {
        proxy_pass http://localhost:3002/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF

    # Enable site
    sudo ln -sf /etc/nginx/sites-available/atproto /etc/nginx/sites-enabled/
    sudo nginx -t
    sudo systemctl restart nginx

    print_success "Nginx configured"
}

# Function to setup SSL certificate
setup_ssl() {
    print_status "Setting up SSL certificate..."

    # Temporarily disable HTTPS redirect for certificate generation
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

    # Install dependencies and build
    pnpm install
    pnpm build

    # Start services
    docker-compose up -d

    print_success "Services started successfully"
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
EOF

    sudo chmod +x /usr/local/bin/atproto-backup.sh

    # Setup daily backup
    (crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/atproto-backup.sh") | crontab -

    print_success "Backup script created"
}

# Function to display final information
display_final_info() {
    print_success "AT Protocol deployment completed!"
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
    echo "Useful commands:"
    echo "  - View logs: docker-compose logs -f"
    echo "  - Restart services: docker-compose restart"
    echo "  - Stop services: docker-compose down"
    echo "  - Manual backup: /usr/local/bin/atproto-backup.sh"
    echo
    echo "Next steps:"
    echo "  1. Register your PDS with the PLC directory"
    echo "  2. Configure Ozone moderation rules"
    echo "  3. Set up monitoring and alerts"
    echo "  4. Customize branding and settings"
}

# Main deployment function
main() {
    echo "AT Protocol Production Deployment Script"
    echo "========================================"
    echo

    # Get user input
    get_input "Enter your domain name" DOMAIN
    get_input "Enter admin email for SSL certificate" ADMIN_EMAIL
    get_input "Enter database password" DB_PASSWORD

    # Generate cryptographic keys if not provided
    print_status "Generating cryptographic keys..."
    PDS_SIGNING_KEY=$(generate_hex)
    PDS_ROTATION_KEY=$(generate_hex)
    PDS_DPOP_SECRET=$(generate_hex)
    PDS_JWT_SECRET=$(generate_hex)
    PDS_ADMIN_PASSWORD=$(openssl rand -hex 16)
    OZONE_ADMIN_PASSWORD=$(openssl rand -hex 16)

    print_success "Keys generated"

    # Install dependencies
    install_docker
    install_docker_compose
    install_nodejs
    install_system_deps

    # Setup services
    setup_database
    generate_env_files
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
