#!/bin/bash

# Enhanced EC2 Deployment Script for Weighbridge OCR API
# Author: Auto-generated deployment script
# Version: 2.0.0

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="weighbridge-ocr"
DOMAIN_NAME=${1:-"your-domain.com"}
EMAIL=${2:-"admin@your-domain.com"}
API_KEY=${3:-$(openssl rand -hex 32)}

# Logging function
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}"
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        error "This script should not be run as root. Please run as a regular user with sudo privileges."
    fi
}

# Update system packages
update_system() {
    log "Updating system packages..."
    sudo apt-get update -y
    sudo apt-get upgrade -y
    sudo apt-get install -y curl wget git unzip software-properties-common
}

# Install Docker and Docker Compose
install_docker() {
    log "Installing Docker and Docker Compose..."
    
    # Remove old Docker versions
    sudo apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true
    
    # Install Docker
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    
    # Add user to docker group
    sudo usermod -aG docker $USER
    
    # Install Docker Compose V2
    DOCKER_COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | grep 'tag_name' | cut -d\" -f4)
    sudo curl -L "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose
    
    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker
    
    # Verify installation
    docker --version || error "Docker installation failed"
    docker-compose --version || error "Docker Compose installation failed"
}

# Setup firewall
setup_firewall() {
    log "Configuring firewall..."
    
    # Install UFW if not present
    sudo apt-get install -y ufw
    
    # Reset UFW to defaults
    sudo ufw --force reset
    
    # Default policies
    sudo ufw default deny incoming
    sudo ufw default allow outgoing
    
    # Allow essential services
    sudo ufw allow ssh
    sudo ufw allow 80/tcp   # HTTP
    sudo ufw allow 443/tcp  # HTTPS
    sudo ufw allow 9090/tcp # Prometheus (restrict this in production)
    sudo ufw allow 3001/tcp # Grafana (restrict this in production)
    
    # Enable firewall
    sudo ufw --force enable
    
    sudo ufw status
}

# Create project structure
create_project_structure() {
    log "Creating project structure..."
    
    # Create project directory
    PROJECT_DIR="/opt/${PROJECT_NAME}"
    sudo mkdir -p ${PROJECT_DIR}
    sudo chown $USER:$USER ${PROJECT_DIR}
    
    # Create subdirectories
    mkdir -p ${PROJECT_DIR}/{logs,ssl,monitoring/grafana/provisioning,nginx}
    
    # Set permissions
    chmod 755 ${PROJECT_DIR}
    chmod 755 ${PROJECT_DIR}/logs
}

# Generate SSL certificates with Let's Encrypt
setup_ssl() {
    if [[ "$DOMAIN_NAME" != "your-domain.com" ]]; then
        log "Setting up SSL certificates with Let's Encrypt..."
        
        # Install Certbot
        sudo apt-get install -y certbot python3-certbot-nginx
        
        # Generate certificates
        sudo certbot certonly --standalone -d ${DOMAIN_NAME} --email ${EMAIL} --agree-tos --non-interactive
        
        # Copy certificates to project directory
        sudo cp /etc/letsencrypt/live/${DOMAIN_NAME}/fullchain.pem ${PROJECT_DIR}/ssl/
        sudo cp /etc/letsencrypt/live/${DOMAIN_NAME}/privkey.pem ${PROJECT_DIR}/ssl/
        sudo chown $USER:$USER ${PROJECT_DIR}/ssl/*
        
        # Setup certificate renewal
        (sudo crontab -l 2>/dev/null; echo "0 12 * * * /usr/bin/certbot renew --quiet") | sudo crontab -
    else
        warning "Domain name not provided. SSL setup skipped. Using HTTP only."
    fi
}

# Deploy application files
deploy_application() {
    log "Deploying application files..."
    
    PROJECT_DIR="/opt/${PROJECT_NAME}"
    
    # Copy all ML files to project directory
    # Note: In real deployment, you'd clone from git or copy from CI/CD
    if [[ -d "./ml" ]]; then
        cp -r ./ml/* ${PROJECT_DIR}/
    else
        error "ML directory not found. Please run this script from the project root."
    fi
    
    # Create environment file
    cat > ${PROJECT_DIR}/.env << EOF
# Production Environment Configuration
APP_NAME=${PROJECT_NAME}
APP_VERSION=2.0.0
DEBUG=false
LOG_LEVEL=INFO

# Server Configuration
HOST=0.0.0.0
PORT=8000
WORKERS=4

# API Security
API_KEY_ENABLED=true
API_KEY=${API_KEY}
JWT_SECRET_KEY=$(openssl rand -hex 64)
JWT_ALGORITHM=HS256
JWT_EXPIRE_MINUTES=60

# Rate Limiting
RATE_LIMIT_ENABLED=true
RATE_LIMIT_REQUESTS=100
RATE_LIMIT_WINDOW=3600

# OCR Configuration
TESSERACT_CONFIG=--oem 3 --psm 6
MAX_FILE_SIZE=10485760
MIN_RESOLUTION=200
SUPPORTED_FORMATS=png,jpg,jpeg,bmp,tiff

# Monitoring
PROMETHEUS_ENABLED=true
PROMETHEUS_PORT=8001

# Logging
LOG_FORMAT=json
LOG_FILE=/app/logs/ocr-service.log
LOG_ROTATION=midnight
LOG_RETENTION_DAYS=30
EOF
    
    # Set proper permissions
    chmod 600 ${PROJECT_DIR}/.env
    
    # Update main.py to use enhanced version
    if [[ -f "${PROJECT_DIR}/enhanced_main.py" ]]; then
        mv ${PROJECT_DIR}/main.py ${PROJECT_DIR}/main_original.py
        mv ${PROJECT_DIR}/enhanced_main.py ${PROJECT_DIR}/main.py
    fi
}

# Setup monitoring
setup_monitoring() {
    log "Setting up monitoring and logging..."
    
    PROJECT_DIR="/opt/${PROJECT_NAME}"
    
    # Create Grafana provisioning files
    mkdir -p ${PROJECT_DIR}/monitoring/grafana/provisioning/{dashboards,datasources}
    
    # Grafana datasource configuration
    cat > ${PROJECT_DIR}/monitoring/grafana/provisioning/datasources/prometheus.yml << EOF
apiVersion: 1

datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
EOF
    
    # Setup log rotation
    sudo cat > /etc/logrotate.d/${PROJECT_NAME} << EOF
${PROJECT_DIR}/logs/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 644 $USER $USER
    postrotate
        docker-compose -f ${PROJECT_DIR}/docker-compose.yml restart ocr-service
    endscript
}
EOF
}

# Create systemd service
create_systemd_service() {
    log "Creating systemd service..."
    
    PROJECT_DIR="/opt/${PROJECT_NAME}"
    
    sudo cat > /etc/systemd/system/${PROJECT_NAME}.service << EOF
[Unit]
Description=Weighbridge OCR API Service
Requires=docker.service
After=docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${PROJECT_DIR}
ExecStart=/usr/local/bin/docker-compose up -d
ExecStop=/usr/local/bin/docker-compose down
TimeoutStartSec=0
User=$USER
Group=$USER

[Install]
WantedBy=multi-user.target
EOF
    
    # Reload systemd and enable service
    sudo systemctl daemon-reload
    sudo systemctl enable ${PROJECT_NAME}.service
}

# Setup backup system
setup_backup() {
    log "Setting up backup system..."
    
    PROJECT_DIR="/opt/${PROJECT_NAME}"
    
    # Create backup script
    cat > ${PROJECT_DIR}/backup.sh << 'EOF'
#!/bin/bash
BACKUP_DIR="/opt/backups/weighbridge-ocr"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p ${BACKUP_DIR}

# Backup application data
tar -czf ${BACKUP_DIR}/app_backup_${DATE}.tar.gz \
    /opt/weighbridge-ocr \
    --exclude='/opt/weighbridge-ocr/logs' \
    --exclude='/opt/weighbridge-ocr/ssl'

# Backup Docker volumes
docker run --rm -v weighbridge-ocr_prometheus_data:/data -v ${BACKUP_DIR}:/backup alpine \
    tar -czf /backup/prometheus_data_${DATE}.tar.gz -C /data .

docker run --rm -v weighbridge-ocr_grafana_data:/data -v ${BACKUP_DIR}:/backup alpine \
    tar -czf /backup/grafana_data_${DATE}.tar.gz -C /data .

# Clean old backups (keep last 7 days)
find ${BACKUP_DIR} -name "*.tar.gz" -type f -mtime +7 -delete

echo "Backup completed: ${DATE}"
EOF
    
    chmod +x ${PROJECT_DIR}/backup.sh
    
    # Add to crontab for daily backups
    (crontab -l 2>/dev/null; echo "0 2 * * * ${PROJECT_DIR}/backup.sh >> ${PROJECT_DIR}/logs/backup.log 2>&1") | crontab -
}

# Deploy and start services
start_services() {
    log "Starting services..."
    
    PROJECT_DIR="/opt/${PROJECT_NAME}"
    cd ${PROJECT_DIR}
    
    # Pull latest images
    docker-compose pull
    
    # Build and start services
    docker-compose up -d --build
    
    # Wait for services to start
    sleep 30
    
    # Check service health
    if curl -f http://localhost/health; then
        log "✅ Services started successfully!"
    else
        error "❌ Service health check failed"
    fi
}

# Setup monitoring alerts
setup_alerts() {
    log "Setting up monitoring alerts..."
    
    # This would typically integrate with services like:
    # - PagerDuty
    # - Slack
    # - Email notifications
    # For now, we'll create a basic health check script
    
    PROJECT_DIR="/opt/${PROJECT_NAME}"
    
    cat > ${PROJECT_DIR}/health_check.sh << 'EOF'
#!/bin/bash
WEBHOOK_URL=${WEBHOOK_URL:-""}

check_service() {
    if ! curl -f -s http://localhost/health > /dev/null; then
        echo "❌ OCR Service is DOWN"
        if [[ -n "$WEBHOOK_URL" ]]; then
            curl -X POST -H 'Content-type: application/json' \
                --data '{"text":"🚨 OCR Service is DOWN"}' \
                "$WEBHOOK_URL"
        fi
        return 1
    else
        echo "✅ OCR Service is UP"
        return 0
    fi
}

check_service
EOF
    
    chmod +x ${PROJECT_DIR}/health_check.sh
    
    # Add health check to crontab (every 5 minutes)
    (crontab -l 2>/dev/null; echo "*/5 * * * * ${PROJECT_DIR}/health_check.sh >> ${PROJECT_DIR}/logs/health_check.log 2>&1") | crontab -
}

# Security hardening
security_hardening() {
    log "Applying security hardening..."
    
    # Disable root login
    sudo sed -i 's/PermitRootLogin yes/PermitRootLogin no/' /etc/ssh/sshd_config
    
    # Configure automatic security updates
    sudo apt-get install -y unattended-upgrades
    sudo dpkg-reconfigure -plow unattended-upgrades
    
    # Set up fail2ban for SSH protection
    sudo apt-get install -y fail2ban
    
    sudo cat > /etc/fail2ban/jail.local << EOF
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 3

[sshd]
enabled = true
port = ssh
filter = sshd
logpath = /var/log/auth.log
maxretry = 3
EOF
    
    sudo systemctl restart fail2ban
    sudo systemctl enable fail2ban
    
    # Restart SSH to apply changes
    sudo systemctl restart ssh
}

# Print deployment summary
print_summary() {
    log "🎉 Deployment completed successfully!"
    
    cat << EOF

${GREEN}========================================
📊 DEPLOYMENT SUMMARY
========================================${NC}

🌐 Service URL: http://${DOMAIN_NAME}
🔑 API Key: ${API_KEY}
📁 Project Directory: /opt/${PROJECT_NAME}

🔧 Available Endpoints:
  • Health Check: http://${DOMAIN_NAME}/health
  • OCR Extraction: http://${DOMAIN_NAME}/extract-weights
  • Metrics: http://${DOMAIN_NAME}/metrics

📊 Monitoring:
  • Prometheus: http://${DOMAIN_NAME}:9090
  • Grafana: http://${DOMAIN_NAME}:3001 (admin/admin123)

🛠️ Management Commands:
  • Start: sudo systemctl start ${PROJECT_NAME}
  • Stop: sudo systemctl stop ${PROJECT_NAME}
  • Status: sudo systemctl status ${PROJECT_NAME}
  • Logs: docker-compose -f /opt/${PROJECT_NAME}/docker-compose.yml logs -f

📋 Next Steps:
  1. Update DNS to point ${DOMAIN_NAME} to this server
  2. Change default Grafana password
  3. Configure monitoring alerts
  4. Set up automated backups offsite
  5. Review and restrict monitoring port access

${YELLOW}⚠️  IMPORTANT SECURITY NOTES:
  • Save the API key securely: ${API_KEY}
  • Change default passwords
  • Restrict monitoring ports (9090, 3001) in production
  • Set up proper DNS and SSL certificates${NC}

EOF
}

# Main execution
main() {
    log "🚀 Starting EC2 deployment for Weighbridge OCR API..."
    
    check_root
    update_system
    install_docker
    setup_firewall
    create_project_structure
    setup_ssl
    deploy_application
    setup_monitoring
    create_systemd_service
    setup_backup
    start_services
    setup_alerts
    security_hardening
    print_summary
    
    log "✅ Deployment completed! Please reboot the system to ensure all changes take effect."
}

# Run main function
main "$@"