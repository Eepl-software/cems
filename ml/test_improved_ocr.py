#!/usr/bin/env python3
"""
Test script for Improved Weighbridge OCR
Optimized for L&T Construction weighbridge slips
"""

import os
import sys
import json
from improved_ocr_processor import ImprovedWeighbridgeOCR

def test_improved_ocr_with_real_images():
    """
    Test the improved OCR system with real L&T weighbridge slip images
    """
    print("🔍 Testing Improved L&T Weighbridge OCR System")
    print("=" * 60)
    
    # Initialize the improved OCR processor
    ocr_processor = ImprovedWeighbridgeOCR()
    
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
            
        except Exception as e:
            print(f"❌ Error processing image: {str(e)}")
    
    print("\n" + "=" * 60)
    print("🏁 Testing Complete!")

def compare_with_expected_improved():
    """
    Compare extracted data with expected values from the L&T weighbridge slips
    """
    print("\n🎯 Comparing with Expected Values (Improved)")
    print("-" * 40)
    
    # Expected values based on visual inspection of the L&T slips
    expected_data = {
        "PHOTO-2025-07-15-17-27-21.jpg": {
            "material_name": "STONE AGGREGATE",
            "material_category": "Aggregate", 
            "gross_weight": "44560",
            "tare_weight": "12350",
            "net_weight": "32210",
            "weighment_slip_no": "WB48R20250715153923-3",
            "vehicle_number": "KA034C313",
            "driver_name": "Sartmul",
            "transporter": "foyer mines"
        },
        "PHOTO-2025-07-15-17-27-21 2.jpg": {
            "material_name": "ORDINARY PORTLAND CEMENT",
            "material_category": "Grey Cement",
            "gross_weight": "65570", 
            "tare_weight": "14500",
            "net_weight": "51070",  # Corrected: 65570 - 14500 = 51070
            "weighment_slip_no": "WB48R20250715111655-3",
            "vehicle_number": "TN914235",
            "driver_name": "babrish",
            "transporter": "bam logistics"
        }
    }
    
    ocr_processor = ImprovedWeighbridgeOCR()
    
    total_fields = 0
    correct_fields = 0
    
    for filename, expected in expected_data.items():
        image_path = f"/Users/syedkhaja/Desktop/Prestige Park Groove Main Code 2/ml/{filename}"
        
        if os.path.exists(image_path):
            print(f"\n📸 Testing: {filename}")
            
            try:
                result = ocr_processor.process_image(image_path)
                
                print("🎯 ACCURACY CHECK:")
                for field, expected_value in expected.items():
                    extracted_value = result.get(field, "Not found")
                    total_fields += 1
                    
                    # Check if extracted value matches expected value (flexible matching)
                    if extracted_value and expected_value.upper() in str(extracted_value).upper():
                        status = "✅ MATCH"
                        correct_fields += 1
                    elif extracted_value and extracted_value != "Not found":
                        # Check partial matches for weights (just numbers)
                        if field.endswith('_weight') and expected_value in str(extracted_value):
                            status = "✅ MATCH"
                            correct_fields += 1
                        else:
                            status = "⚠️ PARTIAL"
                    else:
                        status = "❌ MISSING"
                    
                    print(f"  {field:20} {status:10} | Expected: {expected_value:15} | Got: {extracted_value}")
                
            except Exception as e:
                print(f"❌ Error: {str(e)}")
    
    # Calculate accuracy
    accuracy = (correct_fields / total_fields) * 100 if total_fields > 0 else 0
    print(f"\n📈 OVERALL ACCURACY: {correct_fields}/{total_fields} = {accuracy:.1f}%")

if __name__ == "__main__":
    print("🚀 Improved L&T Weighbridge OCR Test Suite")
    print("Testing material extraction from L&T weighbridge slips")
    print("=" * 60)
    
    # Run improved tests
    test_improved_ocr_with_real_images()
    compare_with_expected_improved()
    
    print("\n✨ All tests completed!")
    print("This improved OCR system is optimized for:")
    print("  • L&T Construction weighbridge slip format")
    print("  • Material name and category extraction")
    print("  • Weight table parsing (Gross, Tare, Net)")
    print("  • Weighment slip number detection")
    print("  • Vehicle number recognition") 
    print("  • Driver name extraction")
    print("  • Transporter information")