from fastapi import FastAPI, File, UploadFile, HTTPException, Depends, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
import uvicorn
from typing import Dict, Optional
import logging
import io
from PIL import Image
import numpy as np
import cv2
import os
import time
from datetime import datetime, timedelta
import jwt
from functools import wraps
import asyncio
from collections import defaultdict
import json

from ocr_processor import WeighbridgeOCR

# Environment configuration
DEBUG = os.getenv('DEBUG', 'false').lower() == 'true'
LOG_LEVEL = os.getenv('LOG_LEVEL', 'INFO').upper()
API_KEY_ENABLED = os.getenv('API_KEY_ENABLED', 'true').lower() == 'true'
API_KEY = os.getenv('API_KEY', 'your-secure-api-key-here')
JWT_SECRET_KEY = os.getenv('JWT_SECRET_KEY', 'your-jwt-secret-key-here')
RATE_LIMIT_ENABLED = os.getenv('RATE_LIMIT_ENABLED', 'true').lower() == 'true'
RATE_LIMIT_REQUESTS = int(os.getenv('RATE_LIMIT_REQUESTS', '100'))
RATE_LIMIT_WINDOW = int(os.getenv('RATE_LIMIT_WINDOW', '3600'))
MAX_FILE_SIZE = int(os.getenv('MAX_FILE_SIZE', '10485760'))  # 10MB

# Set up enhanced logging
def setup_logging():
    log_format = os.getenv('LOG_FORMAT', 'json')
    
    if log_format == 'json':
        formatter = logging.Formatter(
            '{"timestamp": "%(asctime)s", "level": "%(levelname)s", "module": "%(name)s", "message": "%(message)s"}'
        )
    else:
        formatter = logging.Formatter(
            '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
        )
    
    # Create logs directory if it doesn't exist
    os.makedirs('/app/logs', exist_ok=True)
    
    # File handler
    file_handler = logging.FileHandler('/app/logs/ocr-service.log')
    file_handler.setFormatter(formatter)
    
    # Console handler
    console_handler = logging.StreamHandler()
    console_handler.setFormatter(formatter)
    
    # Configure root logger
    logging.basicConfig(
        level=getattr(logging, LOG_LEVEL),
        handlers=[file_handler, console_handler]
    )

setup_logging()
logger = logging.getLogger(__name__)

# Rate limiting storage
rate_limit_storage = defaultdict(list)

# Security schemes
security = HTTPBearer(auto_error=False)

class RateLimiter:
    def __init__(self, max_requests: int, window: int):
        self.max_requests = max_requests
        self.window = window
        
    async def __call__(self, request: Request):
        if not RATE_LIMIT_ENABLED:
            return True
            
        client_ip = request.client.host
        current_time = time.time()
        
        # Clean old requests
        rate_limit_storage[client_ip] = [
            req_time for req_time in rate_limit_storage[client_ip]
            if current_time - req_time < self.window
        ]
        
        # Check rate limit
        if len(rate_limit_storage[client_ip]) >= self.max_requests:
            raise HTTPException(
                status_code=429,
                detail="Rate limit exceeded. Please try again later."
            )
        
        # Add current request
        rate_limit_storage[client_ip].append(current_time)
        return True

# Authentication dependency
async def verify_api_key(credentials: HTTPAuthorizationCredentials = Depends(security)):
    if not API_KEY_ENABLED:
        return True
        
    if not credentials:
        raise HTTPException(
            status_code=401,
            detail="API key required"
        )
    
    if credentials.credentials != API_KEY:
        raise HTTPException(
            status_code=401,
            detail="Invalid API key"
        )
    
    return credentials.credentials

# Initialize FastAPI app
app = FastAPI(
    title="Enhanced Weighbridge OCR API",
    description="Production-ready API for extracting GROSS, TARE, and NET weights from weighbridge slip images",
    version="2.0.0",
    debug=DEBUG
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"] if DEBUG else ["https://yourdomain.com"],
    allow_credentials=True,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

# Initialize rate limiter and OCR processor
rate_limiter = RateLimiter(RATE_LIMIT_REQUESTS, RATE_LIMIT_WINDOW)
ocr_processor = WeighbridgeOCR()

# Metrics storage
metrics = {
    "total_requests": 0,
    "successful_extractions": 0,
    "failed_extractions": 0,
    "average_processing_time": 0.0,
    "uptime_start": datetime.now().isoformat()
}

@app.middleware("http")
async def log_requests(request: Request, call_next):
    start_time = time.time()
    
    # Log request
    logger.info(f"Incoming request: {request.method} {request.url}")
    
    response = await call_next(request)
    
    # Calculate processing time
    process_time = time.time() - start_time
    
    # Update metrics
    metrics["total_requests"] += 1
    metrics["average_processing_time"] = (
        (metrics["average_processing_time"] * (metrics["total_requests"] - 1) + process_time) 
        / metrics["total_requests"]
    )
    
    # Log response
    logger.info(f"Request completed: {response.status_code} in {process_time:.3f}s")
    
    return response

@app.get("/")
async def root():
    """
    Root endpoint - API health check
    """
    return {
        "message": "Enhanced Weighbridge OCR API",
        "version": "2.0.0",
        "status": "operational",
        "features": [
            "Authentication",
            "Rate Limiting", 
            "Enhanced Logging",
            "Metrics Collection",
            "Production Ready"
        ]
    }

@app.get("/health")
async def health_check():
    """
    Comprehensive health check endpoint
    """
    return {
        "status": "healthy",
        "service": "weighbridge-ocr-api",
        "version": "2.0.0",
        "timestamp": datetime.now().isoformat(),
        "uptime_start": metrics["uptime_start"],
        "tesseract_available": True  # Could add actual Tesseract check
    }

@app.get("/metrics")
async def get_metrics():
    """
    Get service metrics
    """
    uptime = datetime.now() - datetime.fromisoformat(metrics["uptime_start"])
    
    return {
        "metrics": {
            **metrics,
            "uptime_seconds": uptime.total_seconds(),
            "success_rate": (
                metrics["successful_extractions"] / max(metrics["total_requests"], 1) * 100
            ),
            "error_rate": (
                metrics["failed_extractions"] / max(metrics["total_requests"], 1) * 100
            )
        },
        "timestamp": datetime.now().isoformat()
    }

@app.post("/extract-weights")
async def extract_weights(
    file: UploadFile = File(...),
    _: bool = Depends(rate_limiter),
    api_key: str = Depends(verify_api_key)
):
    """
    Extract GROSS, TARE, and NET weights from weighbridge slip image
    """
    start_time = time.time()
    
    try:
        # Validate file
        if not file.content_type or not file.content_type.startswith('image/'):
            raise HTTPException(
                status_code=400,
                detail="Invalid file type. Please upload an image file."
            )
        
        # Check file size
        file_size = 0
        image_data = bytearray()
        
        while chunk := await file.read(8192):
            file_size += len(chunk)
            if file_size > MAX_FILE_SIZE:
                raise HTTPException(
                    status_code=413,
                    detail=f"File too large. Maximum size: {MAX_FILE_SIZE / (1024*1024):.1f}MB"
                )
            image_data.extend(chunk)
        
        # Process image using OCR
        result = ocr_processor.process_image_from_bytes(bytes(image_data))
        
        processing_time = time.time() - start_time
        
        # Check if processing was successful
        if 'error' in result:
            metrics["failed_extractions"] += 1
            logger.error(f"OCR processing failed: {result['error']}")
            raise HTTPException(
                status_code=500,
                detail=f"OCR processing failed: {result['error']}"
            )
        
        # Update metrics
        metrics["successful_extractions"] += 1
        
        # Log successful processing
        logger.info(f"Successfully processed image in {processing_time:.3f}s")
        
        # Return results
        return JSONResponse(
            status_code=200,
            content={
                "success": True,
                "data": {
                    "gross_weight": result.get("gross_weight"),
                    "tare_weight": result.get("tare_weight"),
                    "net_weight": result.get("net_weight"),
                    "validation_passed": result.get("validation_passed", False)
                },
                "processing_time": round(processing_time, 3),
                "message": "Weights extracted successfully"
            }
        )
        
    except HTTPException:
        metrics["failed_extractions"] += 1
        raise
    except Exception as e:
        metrics["failed_extractions"] += 1
        logger.error(f"Unexpected error in extract_weights: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Internal server error: {str(e)}"
        )

@app.post("/extract-weights-detailed")
async def extract_weights_detailed(
    file: UploadFile = File(...),
    _: bool = Depends(rate_limiter),
    api_key: str = Depends(verify_api_key)
):
    """
    Extract weights with detailed information and debugging data
    """
    start_time = time.time()
    
    try:
        # Validate file type
        if not file.content_type.startswith('image/'):
            raise HTTPException(
                status_code=400,
                detail="Invalid file type. Please upload an image file."
            )
        
        # Read image data with size check
        file_size = 0
        image_data = bytearray()
        
        while chunk := await file.read(8192):
            file_size += len(chunk)
            if file_size > MAX_FILE_SIZE:
                raise HTTPException(
                    status_code=413,
                    detail=f"File too large. Maximum size: {MAX_FILE_SIZE / (1024*1024):.1f}MB"
                )
            image_data.extend(chunk)
        
        # Process image using OCR
        result = ocr_processor.process_image_from_bytes(bytes(image_data))
        
        processing_time = time.time() - start_time
        
        # Check if processing was successful
        if 'error' in result:
            metrics["failed_extractions"] += 1
            raise HTTPException(
                status_code=500,
                detail=f"OCR processing failed: {result['error']}"
            )
        
        metrics["successful_extractions"] += 1
        
        # Return detailed results
        return JSONResponse(
            status_code=200,
            content={
                "success": True,
                "data": {
                    **result,
                    "processing_time": round(processing_time, 3),
                    "file_size": file_size,
                    "file_type": file.content_type
                },
                "message": "Detailed weight extraction completed"
            }
        )
        
    except HTTPException:
        metrics["failed_extractions"] += 1
        raise
    except Exception as e:
        metrics["failed_extractions"] += 1
        logger.error(f"Unexpected error in extract_weights_detailed: {str(e)}", exc_info=True)
        raise HTTPException(
            status_code=500,
            detail=f"Internal server error: {str(e)}"
        )

@app.post("/validate-image")
async def validate_image(
    file: UploadFile = File(...),
    _: bool = Depends(rate_limiter),
    api_key: str = Depends(verify_api_key)
):
    """
    Validate if uploaded image is suitable for OCR processing
    """
    try:
        # Validate file type
        if not file.content_type.startswith('image/'):
            return JSONResponse(
                status_code=400,
                content={
                    "success": False,
                    "message": "Invalid file type. Please upload an image file."
                }
            )
        
        # Read image data with size check
        file_size = 0
        image_data = bytearray()
        
        while chunk := await file.read(8192):
            file_size += len(chunk)
            if file_size > MAX_FILE_SIZE:
                return JSONResponse(
                    status_code=413,
                    content={
                        "success": False,
                        "message": f"File too large. Maximum size: {MAX_FILE_SIZE / (1024*1024):.1f}MB"
                    }
                )
            image_data.extend(chunk)
        
        # Convert to numpy array for validation
        nparr = np.frombuffer(bytes(image_data), np.uint8)
        image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
        
        if image is None:
            return JSONResponse(
                status_code=400,
                content={
                    "success": False,
                    "message": "Could not decode image. Please check the file format."
                }
            )
        
        # Get image properties
        height, width = image.shape[:2]
        min_resolution = int(os.getenv('MIN_RESOLUTION', '200'))
        
        validation_results = {
            "width": width,
            "height": height,
            "file_size": file_size,
            "file_type": file.content_type,
            "is_valid": True,
            "issues": []
        }
        
        # Check resolution
        if width < min_resolution or height < min_resolution:
            validation_results["is_valid"] = False
            validation_results["issues"].append(
                f"Image resolution too low. Minimum: {min_resolution}x{min_resolution}"
            )
        
        # Check file size
        if file_size > MAX_FILE_SIZE:
            validation_results["is_valid"] = False
            validation_results["issues"].append(
                f"File size too large. Maximum: {MAX_FILE_SIZE / (1024*1024):.1f}MB"
            )
        
        return JSONResponse(
            status_code=200,
            content={
                "success": True,
                "data": validation_results,
                "message": "Image validation completed"
            }
        )
        
    except Exception as e:
        logger.error(f"Error in validate_image: {str(e)}", exc_info=True)
        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "message": f"Validation error: {str(e)}"
            }
        )

if __name__ == "__main__":
    host = os.getenv('HOST', '0.0.0.0')
    port = int(os.getenv('PORT', 8000))
    workers = int(os.getenv('WORKERS', 1))
    
    uvicorn.run(
        "enhanced_main:app",
        host=host,
        port=port,
        workers=workers if not DEBUG else 1,
        reload=DEBUG,
        log_level=LOG_LEVEL.lower(),
        access_log=True
    )