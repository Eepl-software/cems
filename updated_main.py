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

from production_ocr_processor import ProductionWeighbridgeOCR

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Initialize FastAPI app
app = FastAPI(
    title="Weighbridge OCR API",
    description="Production API for extracting comprehensive data from weighbridge slip images",
    version="2.0.0"
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
ocr_processor = ProductionWeighbridgeOCR()

@app.get("/")
async def root():
    """
    Root endpoint - API health check
    """
    return {
        "message": "Weighbridge OCR API",
        "version": "2.0.0",
        "processor": "Production",
        "status": "running"
    }

@app.get("/health")
async def health_check():
    """
    Health check endpoint
    """
    return {
        "status": "healthy",
        "service": "production-weighbridge-ocr-api"
    }

@app.post("/extract-weights")
async def extract_weights(file: UploadFile = File(...)):
    """
    Extract comprehensive data from weighbridge slip image
    
    Args:
        file: Uploaded image file
        
    Returns:
        JSON response with extracted data including weights, vehicle info, material details
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
        
        # Process image using production OCR
        result = ocr_processor.process_image_from_bytes(image_data)
        
        # Check if processing was successful
        if 'error' in result:
            raise HTTPException(
                status_code=500,
                detail=f"OCR processing failed: {result['error']}"
            )
        
        # Return comprehensive results
        return JSONResponse(
            status_code=200,
            content={
                "success": True,
                "data": {
                    # Weight information
                    "gross_weight": result.get("gross_weight"),
                    "tare_weight": result.get("tare_weight"),
                    "net_weight": result.get("net_weight"),
                    
                    # Vehicle information
                    "vehicle_number": result.get("vehicle_number"),
                    
                    # Material information
                    "material_name": result.get("material_name"),
                    "material_category": result.get("material_category"),
                    
                    # Document information
                    "weighment_slip_no": result.get("weighment_slip_no"),
                    
                    # Personnel information
                    "driver_name": result.get("driver_name"),
                    "transporter": result.get("transporter"),
                    
                    # Validation
                    "validation_passed": result.get("validation_passed", False)
                },
                "message": "Comprehensive data extracted successfully"
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

if __name__ == "__main__":
    uvicorn.run(
        "main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
        log_level="info"
    )
