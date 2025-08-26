# AT Protocol Quick Start Guide

This guide provides a quick overview for setting up AT Protocol services in production.

## What is AT Protocol?

AT Protocol (ATP) is a decentralized social media protocol developed by Bluesky Social. It consists of several interconnected services:

- **PDS (Personal Data Server)**: Core service for user data and authentication
- **BSky AppView**: Social media API endpoints
- **Ozone**: Content moderation service
- **BSync**: Data synchronization service

## Quick Setup Options

### Option 1: Docker-based Setup (Recommended for most users)

Use the provided deployment script for a fully automated Docker-based setup:

```bash
# Clone the repository
git clone https://github.com/bluesky-social/atproto.git
cd atproto

# Make the deployment script executable
chmod +x deploy.sh

# Run the automated setup
./deploy.sh
```

The script will:
- Install Docker and Docker Compose
- Generate cryptographic keys
- Set up databases and services in containers
- Configure Nginx and SSL
- Start all services automatically

### Option 2: Native Setup (Better Performance)

For better performance and more control, use the native setup without Docker:

```bash
# Clone the repository
git clone https://github.com/bluesky-social/atproto.git
cd atproto

# Make the native deployment script executable
chmod +x deploy-native.sh

# Run the native setup
./deploy-native.sh
```

The native script will:
- Install all dependencies directly on the system
- Generate cryptographic keys
- Set up PostgreSQL and Redis natively
- Configure services with PM2 or systemd
- Configure Nginx and SSL
- Start all services automatically

**Advantages of Native Setup:**
- Better performance (no container overhead)
- Lower resource usage
- Easier debugging and monitoring
- Direct system integration

### Option 3: Systemd Setup (Recommended for Production)

For the most reliable and Linux-native experience, use systemd for process management:

```bash
# Clone the repository
git clone https://github.com/bluesky-social/atproto.git
cd atproto

# Follow the systemd setup guide
# See SYSTEMD_SETUP.md for detailed instructions
```

**Advantages of Systemd Setup:**
- Native Linux service management
- Automatic restarts and recovery
- Built-in dependency management
- Native journal logging
- Resource control and monitoring
- Boot persistence
- Security features

### Option 4: Manual Setup

Follow the detailed guides:
- `PRODUCTION_SETUP.md` for Docker-based manual setup
- `NATIVE_SETUP.md` for native manual setup with PM2
- `SYSTEMD_SETUP.md` for systemd-based manual setup

## Prerequisites

Before running the setup, ensure you have:

- **Server**: Ubuntu 20.04+ with 4+ CPU cores, 8GB+ RAM, 100GB+ storage
- **Domain**: A registered domain name pointing to your server
- **Access**: SSH access to your server with sudo privileges

## What You'll Get

After successful setup, you'll have:

- **PDS API**: `https://your-domain.com/xrpc/`
- **BSky AppView**: `https://your-domain.com/xrpc/app.bsky.*`
- **Ozone Admin**: `https://your-domain.com/ozone/`
- **BSync API**: `https://your-domain.com/bsync/`

## Post-Setup Tasks

1. **Register with PLC Directory**: Register your PDS with the public ledger
2. **Configure Moderation**: Set up Ozone rules and policies
3. **Customize Branding**: Update OAuth provider settings
4. **Set Up Monitoring**: Configure alerts and monitoring
5. **User Onboarding**: Decide on invite system or open registration

## Troubleshooting

### Common Issues

- **Services won't start**: Check logs with `docker-compose logs -f`
- **SSL issues**: Verify domain DNS and certificate paths
- **Database errors**: Check PostgreSQL connection and credentials

### Useful Commands

```bash
# View service logs
docker-compose logs -f [service-name]

# Restart services
docker-compose restart

# Check service status
docker-compose ps

# Access service shell
docker-compose exec [service-name] sh

# Manual backup
/usr/local/bin/atproto-backup.sh
```

## Security Notes

- Keep your cryptographic keys secure
- Regularly update your system and services
- Monitor logs for suspicious activity
- Use strong passwords for admin accounts
- Enable firewall and only expose necessary ports

## Support

- **Documentation**: See `PRODUCTION_SETUP.md` for detailed instructions
- **Issues**: Check the [AT Protocol GitHub repository](https://github.com/bluesky-social/atproto)
- **Community**: Join the [Bluesky Discord](https://discord.gg/bluesky) for support

## Next Steps

Once your AT Protocol services are running:

1. **Test the APIs**: Use the provided endpoints to verify functionality
2. **Set up a client**: Connect a Bluesky client to your PDS
3. **Configure federation**: Connect with other AT Protocol servers
4. **Scale up**: Plan for horizontal scaling as your user base grows

Your AT Protocol server is now ready to serve users and participate in the decentralized social web!
