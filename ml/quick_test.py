#!/usr/bin/env python3

import cv2
import numpy as np
from pathlib import Path
import time
from advanced_ocr_processor import AdvancedWeighbridgeOCR

def create_test_image():
    """Create a simple test image with text"""
    # Create white background
    img = np.ones((400, 600, 3), dtype=np.uint8) * 255
    
    # Add some text
    font = cv2.FONT_HERSHEY_SIMPLEX
    cv2.putText(img, "WEIGHMENT SLIP: WB001R123456789", (50, 50), font, 0.5, (0, 0, 0), 1)
    cv2.putText(img, "VEHICLE NUMBER: TN914235", (50, 80), font, 0.5, (0, 0, 0), 1)
    cv2.putText(img, "GROSS WEIGHT: 25420 KG", (50, 110), font, 0.5, (0, 0, 0), 1)
    cv2.putText(img, "TARE WEIGHT: 8350 KG", (50, 140), font, 0.5, (0, 0, 0), 1)
    cv2.putText(img, "NET WEIGHT: 17070 KG", (50, 170), font, 0.5, (0, 0, 0), 1)
    cv2.putText(img, "MATERIAL: ORDINARY PORTLAND CEMENT", (50, 200), font, 0.5, (0, 0, 0), 1)
    
    # Save test image
    cv2.imwrite('test_image.png', img)
    return 'test_image.png'

def test_advanced_ocr():
    """Test the advanced OCR processor"""
    print("=== Quick Test for Advanced OCR ===\n")
    
    # Create test image
    test_image_path = create_test_image()
    print(f"Created test image: {test_image_path}")
    
    # Initialize processor
    processor = AdvancedWeighbridgeOCR()
    print("Initialized Advanced OCR processor")
    
    # Test basic preprocessing
    print("\nTesting image preprocessing...")
    image = cv2.imread(test_image_path)
    processed_images = processor.advanced_preprocess_image(image)
    print(f"Generated {len(processed_images)} processed variants")
    
    # Test OCR extraction
    print("\nTesting OCR extraction...")
    start_time = time.time()
    
    # Use only first 3 processed images for quick test
    quick_results = processor.extract_text_ensemble(processed_images[:3])
    
    processing_time = time.time() - start_time
    print(f"OCR extraction completed in {processing_time:.2f}s")
    print(f"Generated {len(quick_results)} OCR results")
    
    # Test result selection
    if quick_results:
        best_text = processor.select_best_ocr_result(quick_results)
        print(f"Best OCR result length: {len(best_text)} characters")
        print(f"Sample text: {best_text[:200]}...")
        
        # Test data parsing
        parsed_data = processor.parse_enhanced_weighbridge_data(best_text)
        print(f"\nParsed data:")
        for key, value in parsed_data.items():
            if value:
                print(f"  {key}: {value}")
        
        # Test validation
        validation_result = processor.validate_comprehensive_data(parsed_data)
        print(f"\nValidation result:")
        print(f"  Valid: {validation_result['is_valid']}")
        print(f"  Confidence: {validation_result['confidence_score']:.1f}%")
        if validation_result['errors']:
            print(f"  Errors: {validation_result['errors']}")
        if validation_result['warnings']:
            print(f"  Warnings: {validation_result['warnings']}")
    
    # Clean up
    import os
    if os.path.exists(test_image_path):
        os.remove(test_image_path)
    
    print("\n=== Quick Test Complete ===")

if __name__ == "__main__":
    test_advanced_ocr()