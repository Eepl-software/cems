#!/usr/bin/env python3

import time
from advanced_ocr_processor import AdvancedWeighbridgeOCR
import json
from pathlib import Path

def test_real_images():
    """Test the advanced OCR processor with real weighbridge slip images"""
    print("=== Testing Real Weighbridge Slip Images ===\n")
    
    # Test images
    test_images = [
        "/Users/syedkhaja/Desktop/Prestige Park Groove Main Code 2/ml/PHOTO-2025-07-15-17-27-21 2.jpg",
        "/Users/syedkhaja/Desktop/Prestige Park Groove Main Code 2/ml/PHOTO-2025-07-15-17-27-21.jpg"
    ]
    
    # Initialize processor
    processor = AdvancedWeighbridgeOCR()
    print("Initialized Advanced OCR processor\n")
    
    # Test each image
    for i, image_path in enumerate(test_images, 1):
        print(f"Testing Image {i}: {Path(image_path).name}")
        print("-" * 60)
        
        # Check if file exists
        if not Path(image_path).exists():
            print(f"❌ Image not found: {image_path}")
            continue
        
        try:
            # Process the image
            start_time = time.time()
            result = processor.process_image(image_path)
            processing_time = time.time() - start_time
            
            print(f"✅ Processing completed in {processing_time:.2f}s")
            
            # Display results
            print(f"📊 Validation: {'PASSED' if result.get('validation_passed', False) else 'FAILED'}")
            print(f"📊 Confidence Score: {result.get('confidence_score', 0):.1f}%")
            
            # Show extracted fields
            print("\n📋 Extracted Fields:")
            fields = [
                'weighment_slip_no', 'vehicle_number', 'gross_weight', 'tare_weight', 
                'net_weight', 'material_name', 'material_category', 'driver_name', 'transporter'
            ]
            
            extracted_count = 0
            for field in fields:
                value = result.get(field)
                if value:
                    print(f"  ✓ {field.replace('_', ' ').title()}: {value}")
                    extracted_count += 1
                else:
                    print(f"  ❌ {field.replace('_', ' ').title()}: Not found")
            
            print(f"\n📈 Fields Extracted: {extracted_count}/{len(fields)}")
            
            # Show processing metadata
            metadata = result.get('processing_metadata', {})
            if metadata:
                print(f"\n🔧 Processing Details:")
                print(f"  - Processed variants: {metadata.get('processed_variants', 0)}")
                print(f"  - OCR results: {metadata.get('ocr_results_count', 0)}")
                print(f"  - Best method: {metadata.get('best_ocr_method', 'unknown')}")
            
            # Show validation details
            errors = result.get('validation_errors', [])
            warnings = result.get('validation_warnings', [])
            
            if errors:
                print(f"\n❌ Validation Errors:")
                for error in errors:
                    print(f"  - {error}")
            
            if warnings:
                print(f"\n⚠️ Validation Warnings:")
                for warning in warnings:
                    print(f"  - {warning}")
            
            # Show sample extracted text
            extracted_text = result.get('extracted_text', '')
            if extracted_text:
                print(f"\n📝 Sample Extracted Text ({len(extracted_text)} chars):")
                print(f"  {extracted_text[:300]}...")
            
            # Save detailed result
            output_file = f"test_result_image_{i}.json"
            with open(output_file, 'w') as f:
                json.dump(result, f, indent=2)
            print(f"\n💾 Detailed results saved to: {output_file}")
            
        except Exception as e:
            print(f"❌ Error processing image: {str(e)}")
        
        print("\n" + "="*80 + "\n")
    
    print("=== Real Image Testing Complete ===")

if __name__ == "__main__":
    test_real_images()