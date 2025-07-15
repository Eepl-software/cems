# 🚀 EC2 Production Deployment Guide
## Weighbridge OCR API - Production Ready Setup

### 📋 Overview
This deployment package creates a production-ready OCR service with:
- **Docker containerization** with multi-stage builds
- **Nginx reverse proxy** with SSL/TLS termination
- **API authentication** and rate limiting
- **Comprehensive monitoring** with Prometheus & Grafana
- **Automated backups** and log rotation
- **Security hardening** and fail2ban protection
- **Health checks** and alerting system

---

## 🏗️ Architecture

```
Internet → Nginx (SSL) → OCR Service (Docker) → PostgreSQL
                    ↓
            Prometheus ← Grafana
                    ↓
               Log Aggregation
```

### Components:
- **OCR Service**: FastAPI + Tesseract OCR in Docker
- **Nginx**: Reverse proxy with rate limiting
- **Prometheus**: Metrics collection
- **Grafana**: Monitoring dashboards
- **Systemd**: Service management
- **Certbot**: SSL certificate management

---

## 🚀 Quick Deployment

### Prerequisites
- **EC2 Instance**: t3.medium or larger (2 vCPU, 4GB RAM minimum)
- **Operating System**: Ubuntu 20.04+ or Amazon Linux 2
- **Domain Name**: (Optional) for SSL certificates
- **Security Group**: Ports 22, 80, 443 open

### 1. Clone and Deploy
```bash
# On your EC2 instance
git clone <your-repo-url>
cd Prestige\ Park\ Groove\ Main\ Code\ 2/ml/

# Make script executable
chmod +x deploy-ec2.sh

# Run deployment (replace with your domain)
./deploy-ec2.sh your-domain.com admin@your-domain.com
```

### 2. Verify Deployment
```bash
# Check service status
curl http://your-domain.com/health

# Check Docker containers
docker ps

# Check systemd service
sudo systemctl status weighbridge-ocr
```

---

## 🔧 Manual Setup (Step by Step)

### Step 1: System Preparation
```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install dependencies
sudo apt install -y docker.io docker-compose nginx certbot python3-certbot-nginx
```

### Step 2: Configure Environment
```bash
# Copy environment template
cp .env.example .env

# Edit configuration
nano .env
```

Required environment variables:
```env
API_KEY=your-secure-api-key-here
JWT_SECRET_KEY=your-jwt-secret-key-here
DOMAIN_NAME=your-domain.com
```

### Step 3: Build and Deploy
```bash
# Build Docker image
docker-compose build

# Start services
docker-compose up -d

# Verify health
curl http://localhost:8000/health
```

### Step 4: Configure SSL (Production)
```bash
# Generate SSL certificates
sudo certbot --nginx -d your-domain.com

# Copy certificates to project
sudo cp /etc/letsencrypt/live/your-domain.com/* ./ssl/
```

---

## 🔐 Security Configuration

### API Authentication
```bash
# Generate secure API key
openssl rand -hex 32

# Add to .env file
echo "API_KEY=<generated-key>" >> .env
```

### Rate Limiting
Current limits (configurable in `.env`):
- **General API**: 100 requests/hour per IP
- **Upload endpoints**: 5 requests/second per IP
- **Health checks**: 5 requests/second per IP

### Firewall Setup
```bash
# Configure UFW
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

---

## 📊 Monitoring & Observability

### Prometheus Metrics
Access: `http://your-domain.com:9090`

Key metrics:
- Request count and latency
- OCR processing success rate
- System resource usage
- Error rates and types

### Grafana Dashboards
Access: `http://your-domain.com:3001`
- **Default credentials**: admin/admin123
- **Change password** immediately after first login

### Log Management
```bash
# View application logs
docker-compose logs -f ocr-service

# View Nginx access logs
docker-compose logs -f nginx

# System logs location
tail -f /opt/weighbridge-ocr/logs/ocr-service.log
```

---

## 🛠️ Management Commands

### Service Control
```bash
# Start services
sudo systemctl start weighbridge-ocr

# Stop services
sudo systemctl stop weighbridge-ocr

# Restart services
sudo systemctl restart weighbridge-ocr

# Check status
sudo systemctl status weighbridge-ocr
```

### Docker Management
```bash
# View containers
docker ps

# Check container logs
docker-compose logs -f [service-name]

# Restart specific service
docker-compose restart ocr-service

# Update services
docker-compose pull && docker-compose up -d
```

### Backup & Recovery
```bash
# Manual backup
/opt/weighbridge-ocr/backup.sh

# View backup files
ls -la /opt/backups/weighbridge-ocr/

# Restore from backup (example)
tar -xzf /opt/backups/weighbridge-ocr/app_backup_20250715_120000.tar.gz -C /
```

---

## 🔧 Configuration Files

### Key Files Structure
```
/opt/weighbridge-ocr/
├── docker-compose.yml       # Service orchestration
├── Dockerfile              # OCR service container
├── .env                    # Environment variables
├── nginx/
│   ├── nginx.conf          # Main nginx config
│   └── default.conf        # Site configuration
├── monitoring/
│   └── prometheus.yml      # Metrics configuration
├── ssl/                    # SSL certificates
├── logs/                   # Application logs
└── backup.sh              # Backup script
```

### Environment Variables
| Variable | Description | Default |
|----------|-------------|---------|
| `API_KEY` | Authentication key | Generated |
| `DEBUG` | Debug mode | false |
| `WORKERS` | Gunicorn workers | 4 |
| `MAX_FILE_SIZE` | Max upload size | 10MB |
| `RATE_LIMIT_REQUESTS` | Requests per window | 100 |

---

## 🧪 Testing the Deployment

### Health Check
```bash
curl -X GET http://your-domain.com/health
```

### OCR Test
```bash
curl -X POST "http://your-domain.com/extract-weights" \
  -H "Authorization: Bearer YOUR_API_KEY" \
  -F "file=@test_image.png"
```

### Load Testing
```bash
# Install Apache Bench
sudo apt install apache2-utils

# Test 100 concurrent requests
ab -n 1000 -c 100 http://your-domain.com/health
```

---

## 🔍 Troubleshooting

### Common Issues

#### 1. Service Won't Start
```bash
# Check Docker daemon
sudo systemctl status docker

# Check container logs
docker-compose logs ocr-service

# Verify environment file
cat .env | grep -v "^#"
```

#### 2. OCR Processing Fails
```bash
# Check Tesseract installation
docker exec weighbridge-ocr tesseract --version

# Test OCR manually
docker exec -it weighbridge-ocr python -c "import pytesseract; print('OK')"
```

#### 3. SSL Certificate Issues
```bash
# Check certificate status
sudo certbot certificates

# Renew certificates manually
sudo certbot renew --dry-run
```

#### 4. High Memory Usage
```bash
# Check container resources
docker stats

# Adjust Docker limits in docker-compose.yml
# Reduce worker count in .env
```

### Performance Tuning

#### For High Traffic
```yaml
# In docker-compose.yml, increase resources:
deploy:
  resources:
    limits:
      memory: 2G
      cpus: '2.0'
```

#### For Memory Optimization
```env
# In .env file:
WORKERS=2
MAX_FILE_SIZE=5242880  # 5MB
```

---

## 📈 Scaling Considerations

### Horizontal Scaling
- Use Application Load Balancer
- Deploy multiple EC2 instances
- Shared Redis for rate limiting
- External PostgreSQL database

### Vertical Scaling
- Upgrade to larger EC2 instance types
- Increase Docker resource limits
- Add more Gunicorn workers

### Database Scaling
- Separate database server
- Read replicas for analytics
- Connection pooling

---

## 🔄 Updates & Maintenance

### Regular Maintenance Tasks

#### Weekly
- Review monitoring dashboards
- Check backup integrity
- Update security patches

#### Monthly
- Review and rotate API keys
- Check SSL certificate expiry
- Performance optimization review

#### Quarterly
- Security audit
- Dependency updates
- Disaster recovery testing

### Update Procedure
```bash
# 1. Backup current deployment
/opt/weighbridge-ocr/backup.sh

# 2. Pull latest code
git pull origin main

# 3. Update containers
docker-compose pull
docker-compose up -d --build

# 4. Verify deployment
curl http://your-domain.com/health
```

---

## 🆘 Support & Emergency Contacts

### Emergency Procedures

#### Service Down
1. Check systemd status
2. Restart Docker containers
3. Check resource usage
4. Review logs for errors
5. Contact system administrator

#### Security Incident
1. Immediately rotate API keys
2. Check access logs for anomalies
3. Block suspicious IPs
4. Contact security team

#### Data Loss
1. Stop all services
2. Restore from latest backup
3. Verify data integrity
4. Restart services

---

## ✅ Production Checklist

Before going live, ensure:

- [ ] SSL certificates configured and auto-renewal setup
- [ ] API keys are secure and documented
- [ ] Monitoring alerts configured
- [ ] Backup strategy tested
- [ ] Security hardening applied
- [ ] Performance testing completed
- [ ] Documentation updated
- [ ] Team trained on operations

---

## 🎯 Performance Benchmarks

### Expected Performance
- **Processing Time**: 2-3 seconds per image
- **Throughput**: 50-100 images/minute (with 4 workers)
- **Memory Usage**: 500MB-1GB per worker
- **Accuracy**: 95%+ on clear images

### Resource Requirements
- **Minimum**: 2 vCPU, 4GB RAM, 20GB storage
- **Recommended**: 4 vCPU, 8GB RAM, 50GB storage
- **High Load**: 8 vCPU, 16GB RAM, 100GB storage

---

*This deployment guide ensures a production-ready, secure, and scalable OCR service deployment on AWS EC2.*