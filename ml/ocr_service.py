#!/usr/bin/env python3

import sys
import json
import base64
import io
from production_ocr_processor import ProductionWeighbridgeOCR

def process_image_from_base64(base64_data):
    """
    Process image from base64 data
    """
    try:
        # Remove data URL prefix if present
        if ',' in base64_data:
            base64_data = base64_data.split(',')[1]
        
        # Decode base64
        image_bytes = base64.b64decode(base64_data)
        
        # Process with OCR
        processor = ProductionWeighbridgeOCR()
        result = processor.process_image_from_bytes(image_bytes)
        
        return result
        
    except Exception as e:
        return {
            "material_name": None,
            "material_category": None,
            "gross_weight": None,
            "tare_weight": None,
            "net_weight": None,
            "weighment_slip_no": None,
            "vehicle_number": None,
            "driver_name": None,
            "transporter": None,
            "validation_passed": False,
            "confidence_score": 0,
            "error": str(e)
        }

def main():
    """
    Main function for command line usage
    """
    if len(sys.argv) < 2:
        print("Usage: python ocr_service.py <command> [args]")
        sys.exit(1)
    
    command = sys.argv[1]
    
    if command == "process_base64":
        if len(sys.argv) != 3:
            print("Usage: python ocr_service.py process_base64 <base64_data>")
            sys.exit(1)
        
        base64_data = sys.argv[2]
        result = process_image_from_base64(base64_data)
        print(json.dumps(result, indent=2))
        
    elif command == "process_file":
        if len(sys.argv) != 3:
            print("Usage: python ocr_service.py process_file <image_path>")
            sys.exit(1)
        
        image_path = sys.argv[2]
        processor = ProductionWeighbridgeOCR()
        result = processor.process_image(image_path)
        print(json.dumps(result, indent=2))
        
    else:
        print(f"Unknown command: {command}")
        sys.exit(1)

if __name__ == "__main__":
    main()