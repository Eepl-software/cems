#!/usr/bin/env python3

import requests
import json
import os
from pathlib import Path

def test_backend_ocr_integration():
    """Test the backend OCR integration"""
    
    # Backend endpoint
    backend_url = "http://localhost:3000/api/extract-weighbridge-data"
    
    # Test images
    test_images = [
        "PHOTO-2025-07-15-17-27-21 2.jpg",
        "PHOTO-2025-07-15-17-27-21.jpg"
    ]
    
    print("=== Testing Backend OCR Integration ===\n")
    
    for i, image_name in enumerate(test_images, 1):
        image_path = Path(image_name)
        
        if not image_path.exists():
            print(f"❌ Image {i} not found: {image_name}")
            continue
            
        print(f"Testing Image {i}: {image_name}")
        print("-" * 50)
        
        try:
            # Prepare the file for upload
            with open(image_path, 'rb') as f:
                files = {'weighbridge_slip': (image_name, f, 'image/jpeg')}
                
                # Make the request
                response = requests.post(backend_url, files=files, timeout=60)
                
                if response.status_code == 200:
                    result = response.json()
                    
                    print(f"✅ Request successful")
                    print(f"📊 Success: {result.get('success', False)}")
                    print(f"📊 Confidence: {result.get('confidence', 0):.1f}%")
                    print(f"📊 Processing Time: {result.get('processing_time', 0):.2f}s")
                    
                    # Check if fallback was used
                    if result.get('fallback'):
                        print(f"⚠️  Fallback mode used")
                    
                    # Display extracted data
                    data = result.get('data', {})
                    print(f"\n📋 Extracted Data:")
                    
                    fields = [
                        'material_name', 'material_category', 'gross_weight', 
                        'tare_weight', 'net_weight', 'weighment_slip_no', 
                        'vehicle_number', 'driver_name', 'transporter'
                    ]
                    
                    for field in fields:
                        value = data.get(field, 'Not found')
                        status = "✅" if value and value != 'Not found' else "❌"
                        print(f"  {status} {field.replace('_', ' ').title()}: {value}")
                    
                    print(f"\n📈 Validation: {'PASSED' if data.get('validation_passed') else 'FAILED'}")
                    
                else:
                    print(f"❌ Request failed with status {response.status_code}")
                    print(f"Response: {response.text}")
                    
        except requests.exceptions.RequestException as e:
            print(f"❌ Request error: {e}")
        except Exception as e:
            print(f"❌ Unexpected error: {e}")
        
        print("\n" + "="*70 + "\n")

def test_direct_ocr():
    """Test direct OCR without backend"""
    
    print("=== Testing Direct OCR (No Backend) ===\n")
    
    from production_ocr_processor import ProductionWeighbridgeOCR
    
    processor = ProductionWeighbridgeOCR()
    
    test_images = [
        "PHOTO-2025-07-15-17-27-21 2.jpg",
        "PHOTO-2025-07-15-17-27-21.jpg"
    ]
    
    for i, image_name in enumerate(test_images, 1):
        image_path = Path(image_name)
        
        if not image_path.exists():
            print(f"❌ Image {i} not found: {image_name}")
            continue
            
        print(f"Direct OCR Test - Image {i}: {image_name}")
        print("-" * 50)
        
        try:
            result = processor.process_image(str(image_path))
            
            print(f"✅ Processing completed")
            print(f"📊 Confidence: {result.get('confidence_score', 0):.1f}%")
            print(f"📊 Validation: {'PASSED' if result.get('validation_passed') else 'FAILED'}")
            
            # Show extracted fields
            fields = [
                'material_name', 'material_category', 'gross_weight', 
                'tare_weight', 'net_weight', 'weighment_slip_no', 
                'vehicle_number', 'driver_name', 'transporter'
            ]
            
            print(f"\n📋 Extracted Fields:")
            for field in fields:
                value = result.get(field)
                status = "✅" if value else "❌"
                print(f"  {status} {field.replace('_', ' ').title()}: {value or 'Not found'}")
            
            # Show validation details
            errors = result.get('validation_errors', [])
            warnings = result.get('validation_warnings', [])
            
            if errors:
                print(f"\n❌ Validation Errors:")
                for error in errors:
                    print(f"  - {error}")
            
            if warnings:
                print(f"\n⚠️  Validation Warnings:")
                for warning in warnings:
                    print(f"  - {warning}")
                    
        except Exception as e:
            print(f"❌ Processing error: {e}")
        
        print("\n" + "="*70 + "\n")

if __name__ == "__main__":
    import sys
    
    if len(sys.argv) > 1 and sys.argv[1] == "backend":
        test_backend_ocr_integration()
    else:
        test_direct_ocr()
        
        # Also test backend if requested
        if len(sys.argv) > 1 and sys.argv[1] == "both":
            test_backend_ocr_integration()