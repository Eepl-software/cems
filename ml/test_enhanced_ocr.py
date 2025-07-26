#!/usr/bin/env python3
"""
Test script for Enhanced Weighbridge OCR
Tests the extraction of material name, category, weights, slip number, vehicle number, driver name, and transporter
"""

import os
import sys
import json
from enhanced_ocr_processor import EnhancedWeighbridgeOCR

def test_enhanced_ocr_with_real_images():
    """
    Test the enhanced OCR system with real weighbridge slip images
    """
    print("🔍 Testing Enhanced Weighbridge OCR System")
    print("=" * 60)
    
    # Initialize the enhanced OCR processor
    ocr_processor = EnhancedWeighbridgeOCR()
    
    # Test image paths
    test_images = [
        "/Users/syedkhaja/Desktop/Prestige Park Groove Main Code 2/ml/PHOTO-2025-07-15-17-27-21.jpg",
        "/Users/syedkhaja/Desktop/Prestige Park Groove Main Code 2/ml/PHOTO-2025-07-15-17-27-21 2.jpg"
    ]
    
    for i, image_path in enumerate(test_images, 1):
        print(f"\n📸 Testing Image {i}: {os.path.basename(image_path)}")
        print("-" * 40)
        
        if not os.path.exists(image_path):
            print(f"❌ Image not found: {image_path}")
            continue
        
        try:
            # Process the image
            result = ocr_processor.process_image(image_path)
            
            # Display results in a formatted way
            print("📊 EXTRACTION RESULTS:")
            print(f"  Material Name:        {result.get('material_name', 'Not found')}")
            print(f"  Material Category:    {result.get('material_category', 'Not found')}")
            print(f"  Gross Weight:         {result.get('gross_weight', 'Not found')}")
            print(f"  Tare Weight:          {result.get('tare_weight', 'Not found')}")
            print(f"  Net Weight:           {result.get('net_weight', 'Not found')}")
            print(f"  Weighment Slip No:    {result.get('weighment_slip_no', 'Not found')}")
            print(f"  Vehicle Number:       {result.get('vehicle_number', 'Not found')}")
            print(f"  Driver Name:          {result.get('driver_name', 'Not found')}")
            print(f"  Transporter:          {result.get('transporter', 'Not found')}")
            print(f"  Validation Passed:    {'✅ Yes' if result.get('validation_passed') else '❌ No'}")
            
            if result.get('error'):
                print(f"  Error:                {result.get('error')}")
            
            # Show extracted text for debugging (first 200 chars)
            if result.get('extracted_text'):
                print(f"\n📝 RAW OCR TEXT (first 200 chars):")
                print(f"  {result['extracted_text'][:200]}...")
            
        except Exception as e:
            print(f"❌ Error processing image: {str(e)}")
    
    print("\n" + "=" * 60)
    print("🏁 Testing Complete!")

def test_api_format():
    """
    Test the OCR processor in API format (processing from bytes)
    """
    print("\n🔌 Testing API Format (Bytes Processing)")
    print("-" * 40)
    
    ocr_processor = EnhancedWeighbridgeOCR()
    
    # Test with one of the images in bytes format
    image_path = "/Users/syedkhaja/Desktop/Prestige Park Groove Main Code 2/ml/PHOTO-2025-07-15-17-27-21.jpg"
    
    if os.path.exists(image_path):
        try:
            # Read image as bytes
            with open(image_path, 'rb') as f:
                image_bytes = f.read()
            
            print(f"📸 Processing image bytes ({len(image_bytes)} bytes)")
            
            # Process from bytes
            result = ocr_processor.process_image_from_bytes(image_bytes)
            
            print("📊 API FORMAT RESULTS:")
            print(json.dumps({
                "material_name": result.get('material_name'),
                "material_category": result.get('material_category'),
                "gross_weight": result.get('gross_weight'),
                "tare_weight": result.get('tare_weight'),
                "net_weight": result.get('net_weight'),
                "weighment_slip_no": result.get('weighment_slip_no'),
                "vehicle_number": result.get('vehicle_number'),
                "driver_name": result.get('driver_name'),
                "transporter": result.get('transporter'),
                "validation_passed": result.get('validation_passed')
            }, indent=2))
            
        except Exception as e:
            print(f"❌ Error processing bytes: {str(e)}")
    else:
        print(f"❌ Image not found: {image_path}")

def compare_with_expected():
    """
    Compare extracted data with expected values from the weighbridge slips
    """
    print("\n🎯 Comparing with Expected Values")
    print("-" * 40)
    
    # Expected values based on visual inspection of the images
    expected_data = {
        "PHOTO-2025-07-15-17-27-21.jpg": {
            "material_name": "STONE AGGREGATE",
            "material_category": "Aggregate", 
            "gross_weight": "44560",
            "tare_weight": "12350",
            "net_weight": "32210",
            "weighment_slip_no": "WB48R2025071515323-3",
            "vehicle_number": "KA034C313",
            "driver_name": "Sartmul",
            "transporter": "foyer mines"
        },
        "PHOTO-2025-07-15-17-27-21 2.jpg": {
            "material_name": "ORDINARY PORTLAND CEMENT",
            "material_category": "Grey Cement",
            "gross_weight": "65570", 
            "tare_weight": "14500",
            "net_weight": "41010",
            "weighment_slip_no": "WB48R2025071511655-3",
            "vehicle_number": "TN914235",
            "driver_name": "babrish",
            "transporter": "bam logistics"
        }
    }
    
    ocr_processor = EnhancedWeighbridgeOCR()
    
    for filename, expected in expected_data.items():
        image_path = f"/Users/syedkhaja/Desktop/Prestige Park Groove Main Code 2/ml/{filename}"
        
        if os.path.exists(image_path):
            print(f"\n📸 Testing: {filename}")
            
            try:
                result = ocr_processor.process_image(image_path)
                
                print("🎯 ACCURACY CHECK:")
                for field, expected_value in expected.items():
                    extracted_value = result.get(field, "Not found")
                    
                    # Check if extracted value contains expected value (flexible matching)
                    if extracted_value and expected_value.upper() in extracted_value.upper():
                        status = "✅ MATCH"
                    elif extracted_value and extracted_value != "Not found":
                        status = "⚠️ PARTIAL"
                    else:
                        status = "❌ MISSING"
                    
                    print(f"  {field:20} {status:10} | Expected: {expected_value:15} | Got: {extracted_value}")
                
            except Exception as e:
                print(f"❌ Error: {str(e)}")

if __name__ == "__main__":
    print("🚀 Enhanced Weighbridge OCR Test Suite")
    print("Testing material extraction from real weighbridge slips")
    print("=" * 60)
    
    # Run all tests
    test_enhanced_ocr_with_real_images()
    test_api_format()
    compare_with_expected()
    
    print("\n✨ All tests completed!")
    print("This enhanced OCR system extracts:")
    print("  • Material name and category")
    print("  • Gross, Tare, and Net weights")
    print("  • Weighment slip number")
    print("  • Vehicle number") 
    print("  • Driver name")
    print("  • Transporter information")