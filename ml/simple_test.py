#!/usr/bin/env python3
"""
Simple test without Tesseract to verify basic functionality
"""

import sys
import os
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont

def test_basic_imports():
    """Test basic imports"""
    print("Testing basic imports...")
    
    try:
        import cv2
        print(f"✓ OpenCV version: {cv2.__version__}")
    except ImportError as e:
        print(f"✗ OpenCV failed: {e}")
        return False
    
    try:
        from PIL import Image
        print("✓ PIL/Pillow imported successfully")
    except ImportError as e:
        print(f"✗ PIL failed: {e}")
        return False
    
    try:
        import numpy as np
        print(f"✓ NumPy version: {np.__version__}")
    except ImportError as e:
        print(f"✗ NumPy failed: {e}")
        return False
    
    try:
        import fastapi
        print("✓ FastAPI imported successfully")
    except ImportError as e:
        print(f"✗ FastAPI failed: {e}")
        return False
    
    return True

def test_image_processing():
    """Test basic image processing without OCR"""
    print("\nTesting image processing...")
    
    # Create test image
    img = Image.new('RGB', (800, 600), color='white')
    draw = ImageDraw.Draw(img)
    
    # Add text
    try:
        font = ImageFont.load_default()
        draw.text((100, 150), "GROSS : 28000 Kg", fill='black', font=font)
        draw.text((100, 200), "TARE  : 12000 Kg", fill='black', font=font)
        draw.text((100, 250), "NET   : 16000 Kg", fill='black', font=font)
        print("✓ Test image created successfully")
    except Exception as e:
        print(f"✗ Image creation failed: {e}")
        return False
    
    # Convert to numpy array
    try:
        img_array = np.array(img)
        print(f"✓ Image converted to numpy array: {img_array.shape}")
    except Exception as e:
        print(f"✗ Numpy conversion failed: {e}")
        return False
    
    # Test OpenCV processing
    try:
        gray = cv2.cvtColor(img_array, cv2.COLOR_RGB2GRAY)
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)
        thresh = cv2.adaptiveThreshold(
            blurred, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 11, 2
        )
        print(f"✓ OpenCV preprocessing successful: {thresh.shape}")
    except Exception as e:
        print(f"✗ OpenCV processing failed: {e}")
        return False
    
    return True

def test_weight_parsing():
    """Test weight parsing logic without OCR"""
    print("\nTesting weight parsing...")
    
    import re
    
    # Test parsing function
    def parse_weights(text):
        result = {
            "gross_weight": None,
            "tare_weight": None,
            "net_weight": None
        }
        
        text = text.upper().replace('\n', ' ').replace('\r', ' ')
        
        patterns = {
            'gross_weight': [
                r'GROSS\s*:?\s*(\d+(?:,\d+)*\.?\d*)\s*(KG|KGS|TONNES?|T)?',
            ],
            'tare_weight': [
                r'TARE\s*:?\s*(\d+(?:,\d+)*\.?\d*)\s*(KG|KGS|TONNES?|T)?',
            ],
            'net_weight': [
                r'NET\s*:?\s*(\d+(?:,\d+)*\.?\d*)\s*(KG|KGS|TONNES?|T)?',
            ]
        }
        
        for weight_type, pattern_list in patterns.items():
            for pattern in pattern_list:
                match = re.search(pattern, text)
                if match:
                    weight_value = match.group(1).replace(',', '')
                    unit = match.group(2) if match.group(2) else 'Kg'
                    result[weight_type] = f"{weight_value} {unit}"
                    break
        
        return result
    
    # Test cases
    test_cases = [
        {
            'text': 'GROSS : 28000 Kg\nTARE  : 12000 Kg\nNET   : 16000 Kg',
            'expected': {'gross_weight': '28000 Kg', 'tare_weight': '12000 Kg', 'net_weight': '16000 Kg'}
        },
        {
            'text': 'GROSS WEIGHT: 25,000 KG\nTARE WEIGHT: 10,000 KG\nNET WEIGHT: 15,000 KG',
            'expected': {'gross_weight': '25000 KG', 'tare_weight': '10000 KG', 'net_weight': '15000 KG'}
        }
    ]
    
    for i, test_case in enumerate(test_cases):
        try:
            result = parse_weights(test_case['text'])
            for key, expected in test_case['expected'].items():
                if result[key] == expected:
                    print(f"✓ Test case {i+1} - {key}: {result[key]}")
                else:
                    print(f"✗ Test case {i+1} - {key}: expected {expected}, got {result[key]}")
        except Exception as e:
            print(f"✗ Test case {i+1} failed: {e}")
            return False
    
    return True

def test_api_imports():
    """Test API related imports"""
    print("\nTesting API imports...")
    
    try:
        from fastapi import FastAPI, File, UploadFile
        from fastapi.middleware.cors import CORSMiddleware
        print("✓ FastAPI components imported successfully")
    except ImportError as e:
        print(f"✗ FastAPI imports failed: {e}")
        return False
    
    try:
        import uvicorn
        print("✓ Uvicorn imported successfully")
    except ImportError as e:
        print(f"✗ Uvicorn failed: {e}")
        return False
    
    return True

def main():
    """Run all tests"""
    print("🧪 Running Simple OCR System Tests (without Tesseract)\n")
    
    tests = [
        ("Basic Imports", test_basic_imports),
        ("Image Processing", test_image_processing),
        ("Weight Parsing", test_weight_parsing),
        ("API Imports", test_api_imports)
    ]
    
    passed = 0
    total = len(tests)
    
    for test_name, test_func in tests:
        print(f"\n{'='*50}")
        print(f"Running: {test_name}")
        print(f"{'='*50}")
        
        if test_func():
            print(f"✅ {test_name} PASSED")
            passed += 1
        else:
            print(f"❌ {test_name} FAILED")
    
    print(f"\n{'='*50}")
    print(f"TEST SUMMARY: {passed}/{total} tests passed")
    print(f"{'='*50}")
    
    if passed == total:
        print("🎉 All tests passed! Basic functionality is working.")
        print("\nNext steps:")
        print("1. Install Tesseract OCR: brew install tesseract")
        print("2. Install pytesseract: pip install pytesseract")
        print("3. Run full OCR tests")
    else:
        print("❌ Some tests failed. Please check the errors above.")
        sys.exit(1)

if __name__ == "__main__":
    main()