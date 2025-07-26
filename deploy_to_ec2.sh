#!/bin/bash

# EC2 Deployment Script for ML/OCR Service
# Target IP: 54.146.215.18
# Usage: ./deploy_to_ec2.sh

set -e

# Configuration
EC2_IP="54.146.215.18"
EC2_USER="ubuntu"
KEY_PATH="/Users/syedkhaja/Downloads/thanush.pem"
PROJECT_NAME="weighbridge-ocr"
REMOTE_DIR="/opt/${PROJECT_NAME}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')] $1${NC}"
}

error() {
    echo -e "${RED}[ERROR] $1${NC}"
    exit 1
}

info() {
    echo -e "${BLUE}[INFO] $1${NC}"
}

# Check if key file exists
check_key() {
    if [[ ! -f "$KEY_PATH" ]]; then
        error "Key file not found at $KEY_PATH"
    fi
    chmod 400 "$KEY_PATH"
}

# Test SSH connection
test_connection() {
    log "Testing SSH connection to $EC2_IP..."
    ssh -i "$KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=no "$EC2_USER@$EC2_IP" "echo 'Connection successful'" || error "Cannot connect to EC2 instance"
}

# Prepare ML directory for deployment
prepare_ml_directory() {
    log "Preparing ML directory for deployment..."
    
    # Create temporary deployment directory
    TEMP_DIR="/tmp/ml_deploy_$(date +%s)"
    mkdir -p "$TEMP_DIR"
    
    # Copy ML files (excluding unnecessary files)
    cp -r ml/* "$TEMP_DIR/" 2>/dev/null || error "ML directory not found"
    
    # Remove unnecessary files
    rm -f "$TEMP_DIR"/*.jpg "$TEMP_DIR"/*.png "$TEMP_DIR"/test_*.py "$TEMP_DIR"/manual_*.py
    
    # Ensure we have the best OCR processor
    if [[ -f "$TEMP_DIR/advanced_ocr_processor.py" ]]; then
        cp "$TEMP_DIR/advanced_ocr_processor.py" "$TEMP_DIR/ocr_processor_main.py"
        info "Using advanced_ocr_processor.py as main OCR engine"
    elif [[ -f "$TEMP_DIR/production_ocr_processor.py" ]]; then
        cp "$TEMP_DIR/production_ocr_processor.py" "$TEMP_DIR/ocr_processor_main.py"
        info "Using production_ocr_processor.py as main OCR engine"
    fi
    
    # Create optimized requirements.txt
    cat > "$TEMP_DIR/requirements.txt" << EOF
fastapi==0.104.1
uvicorn[standard]==0.24.0
python-multipart==0.0.6
pillow==10.1.0
opencv-python-headless==4.8.1.78
pytesseract==0.3.10
numpy==1.24.3
python-jose[cryptography]==3.3.0
passlib[bcrypt]==1.7.4
aiofiles==23.2.1
scikit-image==0.21.0
requests==2.31.0
pydantic==2.5.0
python-dotenv==1.0.0
gunicorn==21.2.0
EOF
    
    # Create production main.py that uses the best OCR processor
    cat > "$TEMP_DIR/main.py" << 'EOF'
from fastapi import FastAPI, File, UploadFile, HTTPException, Depends, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
import logging
import os
from typing import Dict, Any
import time

# Import the best available OCR processor
try:
    from advanced_ocr_processor import AdvancedWeighbridgeOCR as OCRProcessor
    PROCESSOR_TYPE = "Advanced"
except ImportError:
    try:
        from production_ocr_processor import ProductionWeighbridgeOCR as OCRProcessor
        PROCESSOR_TYPE = "Production"
    except ImportError:
        from enhanced_ocr_processor import EnhancedWeighbridgeOCR as OCRProcessor
        PROCESSOR_TYPE = "Enhanced"

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="Weighbridge OCR API",
    description="Advanced OCR service for weighbridge slip processing",
    version="2.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Security
security = HTTPBearer()
API_KEY = os.getenv("API_KEY", "your-secure-api-key")

def verify_api_key(credentials: HTTPAuthorizationCredentials = Depends(security)):
    if credentials.credentials != API_KEY:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid API key"
        )
    return credentials.credentials

# Initialize OCR processor
ocr_processor = OCRProcessor()
logger.info(f"Initialized {PROCESSOR_TYPE} OCR Processor")

@app.get("/")
async def root():
    return {
        "message": "Weighbridge OCR API",
        "version": "2.0.0",
        "processor": PROCESSOR_TYPE,
        "status": "running"
    }

@app.get("/health")
async def health_check():
    return {
        "status": "healthy",
        "timestamp": time.time(),
        "processor": PROCESSOR_TYPE
    }

@app.post("/extract-weights")
async def extract_weights(
    file: UploadFile = File(...),
    api_key: str = Depends(verify_api_key)
) -> Dict[str, Any]:
    """
    Extract weighbridge data from uploaded image
    """
    try:
        # Validate file type
        if not file.content_type.startswith('image/'):
            raise HTTPException(
                status_code=400,
                detail="File must be an image"
            )
        
        # Read file contents
        contents = await file.read()
        
        if len(contents) > 10 * 1024 * 1024:  # 10MB limit
            raise HTTPException(
                status_code=400,
                detail="File too large. Maximum size is 10MB"
            )
        
        # Process image
        logger.info(f"Processing image: {file.filename}")
        start_time = time.time()
        
        result = ocr_processor.process_image_from_bytes(contents)
        
        processing_time = time.time() - start_time
        logger.info(f"Processing completed in {processing_time:.2f} seconds")
        
        # Add metadata
        result['processing_time'] = round(processing_time, 2)
        result['processor_type'] = PROCESSOR_TYPE
        result['filename'] = file.filename
        
        return result
        
    except Exception as e:
        logger.error(f"Error processing image {file.filename}: {str(e)}")
        raise HTTPException(
            status_code=500,
            detail=f"Error processing image: {str(e)}"
        )

@app.get("/metrics")
async def get_metrics():
    """
    Get basic service metrics
    """
    return {
        "processor_type": PROCESSOR_TYPE,
        "uptime": time.time(),
        "api_version": "2.0.0"
    }

if __name__ == "__main__":
    port = int(os.getenv("PORT", 8000))
    host = os.getenv("HOST", "0.0.0.0")
    
    logger.info(f"Starting server on {host}:{port}")
    uvicorn.run(
        "main:app",
        host=host,
        port=port,
        log_level="info",
        access_log=True
    )
EOF
    
    echo "$TEMP_DIR"
}

# Install dependencies on EC2
install_dependencies() {
    log "Installing dependencies on EC2..."
    
    ssh -i "$KEY_PATH" "$EC2_USER@$EC2_IP" << 'EOF'
        set -e
        
        # Update system
        sudo apt-get update -y
        
        # Install Python and pip
        sudo apt-get install -y python3 python3-pip python3-venv
        
        # Install Tesseract OCR
        sudo apt-get install -y tesseract-ocr tesseract-ocr-eng
        
        # Install system dependencies for OpenCV and image processing
        sudo apt-get install -y \
            libgl1-mesa-glx \
            libglib2.0-0 \
            libsm6 \
            libxext6 \
            libxrender-dev \
            libgomp1 \
            libglib2.0-0 \
            libgtk-3-0 \
            libavcodec-dev \
            libavformat-dev \
            libswscale-dev \
            libv4l-dev \
            libatlas-base-dev \
            gfortran \
            libjpeg-dev \
            libpng-dev \
            libtiff-dev \
            libdc1394-22-dev
        
        # Install nginx for reverse proxy
        sudo apt-get install -y nginx
        
        # Install supervisor for process management
        sudo apt-get install -y supervisor
        
        echo "Dependencies installed successfully"
EOF
}

# Deploy application files
deploy_files() {
    local temp_dir=$1
    log "Deploying application files to EC2..."
    
    # Create remote directory
    ssh -i "$KEY_PATH" "$EC2_USER@$EC2_IP" "sudo mkdir -p $REMOTE_DIR && sudo chown ubuntu:ubuntu $REMOTE_DIR"
    
    # Copy files to EC2
    scp -i "$KEY_PATH" -r "$temp_dir"/* "$EC2_USER@$EC2_IP:$REMOTE_DIR/"
    
    # Set up Python virtual environment and install dependencies
    ssh -i "$KEY_PATH" "$EC2_USER@$EC2_IP" << EOF
        cd $REMOTE_DIR
        
        # Create virtual environment
        python3 -m venv venv
        source venv/bin/activate
        
        # Upgrade pip
        pip install --upgrade pip
        
        # Install dependencies
        pip install -r requirements.txt
        
        # Create logs directory
        mkdir -p logs
        
        # Create environment file
        cat > .env << 'ENVEOF'
API_KEY=ocr-api-key-$(openssl rand -hex 16)
HOST=0.0.0.0
PORT=8000
ENVEOF
        
        echo "Application deployed successfully"
EOF
}

# Configure nginx reverse proxy
configure_nginx() {
    log "Configuring nginx reverse proxy..."
    
    ssh -i "$KEY_PATH" "$EC2_USER@$EC2_IP" << 'EOF'
        # Create nginx configuration
        sudo tee /etc/nginx/sites-available/weighbridge-ocr > /dev/null << 'NGINXEOF'
server {
    listen 80;
    server_name _;
    
    # Increase upload size limit
    client_max_body_size 10M;
    
    location / {
        proxy_pass http://127.0.0.1:8000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeout settings for large file uploads
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
    }
    
    # Health check endpoint
    location /health {
        proxy_pass http://127.0.0.1:8000/health;
        access_log off;
    }
}
NGINXEOF
        
        # Enable the site
        sudo ln -sf /etc/nginx/sites-available/weighbridge-ocr /etc/nginx/sites-enabled/
        sudo rm -f /etc/nginx/sites-enabled/default
        
        # Test nginx configuration
        sudo nginx -t
        
        # Restart nginx
        sudo systemctl restart nginx
        sudo systemctl enable nginx
        
        echo "Nginx configured successfully"
EOF
}

# Configure supervisor for process management
configure_supervisor() {
    log "Configuring supervisor for process management..."
    
    ssh -i "$KEY_PATH" "$EC2_USER@$EC2_IP" << EOF
        # Create supervisor configuration
        sudo tee /etc/supervisor/conf.d/weighbridge-ocr.conf > /dev/null << 'SUPEOF'
[program:weighbridge-ocr]
command=$REMOTE_DIR/venv/bin/python $REMOTE_DIR/main.py
directory=$REMOTE_DIR
user=ubuntu
autostart=true
autorestart=true
stdout_logfile=$REMOTE_DIR/logs/app.log
stderr_logfile=$REMOTE_DIR/logs/app_error.log
environment=PATH="$REMOTE_DIR/venv/bin"

[program:weighbridge-ocr-gunicorn]
command=$REMOTE_DIR/venv/bin/gunicorn main:app -w 4 -k uvicorn.workers.UvicornWorker --bind 127.0.0.1:8000
directory=$REMOTE_DIR
user=ubuntu
autostart=true
autorestart=true
stdout_logfile=$REMOTE_DIR/logs/gunicorn.log
stderr_logfile=$REMOTE_DIR/logs/gunicorn_error.log
environment=PATH="$REMOTE_DIR/venv/bin"
SUPEOF
        
        # Reload supervisor
        sudo supervisorctl reread
        sudo supervisorctl update
        
        # Start the service
        sudo supervisorctl start weighbridge-ocr-gunicorn
        
        echo "Supervisor configured successfully"
EOF
}

# Setup firewall
configure_firewall() {
    log "Configuring firewall..."
    
    ssh -i "$KEY_PATH" "$EC2_USER@$EC2_IP" << 'EOF'
        # Install and configure UFW
        sudo apt-get install -y ufw
        
        # Reset UFW
        sudo ufw --force reset
        
        # Default policies
        sudo ufw default deny incoming
        sudo ufw default allow outgoing
        
        # Allow SSH, HTTP, and HTTPS
        sudo ufw allow ssh
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        
        # Enable firewall
        sudo ufw --force enable
        
        echo "Firewall configured successfully"
EOF
}

# Test deployment
test_deployment() {
    log "Testing deployment..."
    
    sleep 10  # Wait for services to start
    
    # Test health endpoint
    if curl -f "http://$EC2_IP/health" > /dev/null 2>&1; then
        log "✅ Health check passed"
    else
        error "❌ Health check failed"
    fi
    
    # Test main endpoint
    if curl -f "http://$EC2_IP/" > /dev/null 2>&1; then
        log "✅ Main endpoint accessible"
    else
        error "❌ Main endpoint not accessible"
    fi
}

# Print deployment summary
print_summary() {
    log "🎉 Deployment completed successfully!"
    
    cat << EOF

${GREEN}========================================
📊 DEPLOYMENT SUMMARY
========================================${NC}

🌐 Service URL: http://$EC2_IP
🔧 Health Check: http://$EC2_IP/health
📊 Metrics: http://$EC2_IP/metrics

🛠️ Management Commands (on EC2):
  • Check status: sudo supervisorctl status
  • View logs: sudo supervisorctl tail -f weighbridge-ocr-gunicorn
  • Restart service: sudo supervisorctl restart weighbridge-ocr-gunicorn
  • Nginx status: sudo systemctl status nginx

📋 API Usage:
  • POST /extract-weights (with image file and API key)
  • GET /health (health check)
  • GET /metrics (service metrics)

${YELLOW}⚠️  IMPORTANT NOTES:
  • The API key is stored in $REMOTE_DIR/.env
  • Logs are stored in $REMOTE_DIR/logs/
  • Service runs on port 8000 behind nginx proxy${NC}

EOF
}

# Main execution
main() {
    log "🚀 Starting deployment to EC2 at $EC2_IP..."
    
    check_key
    test_connection
    
    TEMP_DIR=$(prepare_ml_directory)
    
    install_dependencies
    deploy_files "$TEMP_DIR"
    configure_nginx
    configure_supervisor
    configure_firewall
    test_deployment
    
    # Cleanup
    rm -rf "$TEMP_DIR"
    
    print_summary
    
    log "✅ Deployment completed successfully!"
}

# Run main function
main "$@"