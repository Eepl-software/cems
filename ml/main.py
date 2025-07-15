from fastapi import FastAPI, File, UploadFile, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import uvicorn
from typing import Dict, Optional
import logging
import io
from PIL import Image
import numpy as np
import cv2

from ocr_processor import WeighbridgeOCR

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="Weighbridge OCR API",
    description="API for extracting GROSS, TARE, and NET weights from weighbridge slip images",
    version="1.0.0"
)

# Add CORS middleware
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Configure this properly for production
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Initialize OCR processor
ocr_processor = WeighbridgeOCR()

@app.get("/")
async def root():
    """
    Root endpoint - API health check
    """
    return {
        "message": "Weighbridge OCR API",
        "version": "1.0.0",
        "status": "operational"
    }

@app.get("/health")
async def health_check():
    """
    Health check endpoint
    """
    return {
        "status": "healthy",
        "service": "weighbridge-ocr-api"
    }

@app.post("/extract-weights")
async def extract_weights(file: UploadFile = File(...)):
    """
    Extract GROSS, TARE, and NET weights from weighbridge slip image
    
    Args:
        file: Uploaded image file
        
    Returns:
        JSON response with extracted weights
    """
    try:
        # Debug logging
        logger.info(f"Received file: {file.filename}, content_type: {file.content_type}")
        
        # Validate file type (be more lenient and also check file extension)
        valid_content_types = ['image/png', 'image/jpeg', 'image/jpg', 'image/bmp', 'image/tiff']
        valid_extensions = ['.png', '.jpg', '.jpeg', '.bmp', '.tiff']
        
        is_valid_content_type = file.content_type and file.content_type.startswith('image/')
        is_valid_extension = file.filename and any(file.filename.lower().endswith(ext) for ext in valid_extensions)
        
        if not (is_valid_content_type or is_valid_extension):
            logger.error(f"Invalid file: content_type='{file.content_type}', filename='{file.filename}'")
            raise HTTPException(
                status_code=400,
                detail=f"Invalid file type. Content-Type: '{file.content_type}', Filename: '{file.filename}'. Please upload an image file (PNG, JPEG, BMP, TIFF)."
            )
        
        # Read image data
        image_data = await file.read()
        
        # Process image using OCR
        result = ocr_processor.process_image_from_bytes(image_data)
        
        # Check if processing was successful
        if 'error' in result:
            raise HTTPException(
                status_code=500,
                detail=f"OCR processing failed: {result['error']}"
            )
        
        # Return results
        return JSONResponse(
            status_code=200,
            content={
                "success": True,
                "data": {
                    "gross_weight": result.get("gross_weight"),
                    "tare_weight": result.get("tare_weight"),
                    "net_weight": result.get("net_weight"),
                    "vehicle_number": result.get("vehicle_number"),
                    "validation_passed": result.get("validation_passed", False)
                },
                "message": "Weights extracted successfully"
            }
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Unexpected error in extract_weights: {str(e)}")
        raise HTTPException(
            status_code=500,
            detail=f"Internal server error: {str(e)}"
        )

@app.post("/extract-weights-detailed")
async def extract_weights_detailed(file: UploadFile = File(...)):
    """
    Extract weights with detailed information and debugging data
    
    Args:
        file: Uploaded image file
        
    Returns:
        JSON response with detailed extraction results
    """
    try:
        # Validate file type
        if not file.content_type or not file.content_type.startswith('image/'):
            raise HTTPException(
                status_code=400,
                detail="Invalid file type. Please upload an image file."
            )
        
        # Read image data
        image_data = await file.read()
        
        # Process image using OCR
        result = ocr_processor.process_image_from_bytes(image_data)
        
        # Check if processing was successful
        if 'error' in result:
            raise HTTPException(
                status_code=500,
                detail=f"OCR processing failed: {result['error']}"
            )
        
        # Return detailed results
        return JSONResponse(
            status_code=200,
            content={
                "success": True,
                "data": result,
                "message": "Detailed weight extraction completed"
            }
        )
        
    except HTTPException:
        raise
    except Exception as e:
        logger.error(f"Unexpected error in extract_weights_detailed: {str(e)}")
        raise HTTPException(
            status_code=500,
            detail=f"Internal server error: {str(e)}"
        )

@app.post("/validate-image")
async def validate_image(file: UploadFile = File(...)):
    """
    Validate if uploaded image is suitable for OCR processing
    
    Args:
        file: Uploaded image file
        
    Returns:
        JSON response with validation results
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
        
        # Read image data
        image_data = await file.read()
        
        # Convert to numpy array for validation
        nparr = np.frombuffer(image_data, np.uint8)
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
        file_size = len(image_data)
        
        # Basic validation criteria
        min_resolution = 200  # Minimum width/height
        max_file_size = 10 * 1024 * 1024  # 10MB
        
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
        if file_size > max_file_size:
            validation_results["is_valid"] = False
            validation_results["issues"].append(
                f"File size too large. Maximum: {max_file_size / (1024*1024):.1f}MB"
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
        logger.error(f"Error in validate_image: {str(e)}")
        return JSONResponse(
            status_code=500,
            content={
                "success": False,
                "message": f"Validation error: {str(e)}"
            }
        )

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info"
    )