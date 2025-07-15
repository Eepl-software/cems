#!/usr/bin/env python3
"""
Debug OCR script to analyze what text is being extracted
"""

import sys
import os
from ocr_processor import WeighbridgeOCR
import cv2

def debug_ocr_extraction(image_path):
    """Debug OCR extraction to see raw text and patterns"""
    
    if not os.path.exists(image_path):
        print(f"❌ Image file not found: {image_path}")
        return
    
    print(f"🔍 Debugging OCR extraction for: {image_path}")
    
    # Initialize OCR processor
    ocr = WeighbridgeOCR()
    
    # Load and preprocess image
    image = cv2.imread(image_path)
    if image is None:
        print("❌ Could not load image")
        return
    
    print(f"📏 Image dimensions: {image.shape}")
    
    # Preprocess image
    preprocessed = ocr.preprocess_image(image)
    print(f"📏 Preprocessed dimensions: {preprocessed.shape}")
    
    # Extract raw text
    raw_text = ocr.extract_text_from_image(preprocessed)
    print(f"\n📝 Raw extracted text:")
    print("=" * 50)
    print(raw_text)
    print("=" * 50)
    
    # Parse weights and vehicle number
    result = ocr.parse_weights(raw_text)
    
    print(f"\n🎯 Parsed results:")
    for key, value in result.items():
        status = "✅" if value else "❌"
        print(f"{status} {key}: {value}")
    
    # Test individual vehicle patterns
    print(f"\n🔍 Testing vehicle number patterns:")
    import re
    
    vehicle_patterns = [
        r'VEHICLE\s*(?:NO|NUMBER|NUM)?\s*:?\s*([A-Z]{2}\s*\d{1,2}\s*[A-Z]{1,2}\s*\d{1,4})',
        r'VEH\s*(?:NO|NUMBER|NUM)?\s*:?\s*([A-Z]{2}\s*\d{1,2}\s*[A-Z]{1,2}\s*\d{1,4})',
        r'TRUCK\s*(?:NO|NUMBER|NUM)?\s*:?\s*([A-Z]{2}\s*\d{1,2}\s*[A-Z]{1,2}\s*\d{1,4})',
        r'REG\s*(?:NO|NUMBER|NUM)?\s*:?\s*([A-Z]{2}\s*\d{1,2}\s*[A-Z]{1,2}\s*\d{1,4})',
        r'REGISTRATION\s*(?:NO|NUMBER|NUM)?\s*:?\s*([A-Z]{2}\s*\d{1,2}\s*[A-Z]{1,2}\s*\d{1,4})',
        r'\b([A-Z]{2}\s*\d{1,2}\s*[A-Z]{1,2}\s*\d{3,4})\b',
        r'\b([A-Z]{2}\d{1,2}[A-Z]{1,2}\d{3,4})\b',
        r'([A-Z]{2}\s*\d{1,2}\s*[A-Z]{1,3}\s*\d{1,4})',
        r'([A-Z0-9]{2}\s*\d{1,2}\s*[A-Z0-9]{1,2}\s*\d{3,4})',
    ]
    
    text = raw_text.upper().replace('\n', ' ').replace('\r', ' ')
    
    for i, pattern in enumerate(vehicle_patterns):
        matches = re.findall(pattern, text)
        if matches:
            print(f"✅ Pattern {i}: {pattern[:50]}... found: {matches}")
        else:
            print(f"❌ Pattern {i}: No match")
    
    # Look for potential vehicle-like strings
    print(f"\n🔍 Looking for potential vehicle numbers:")
    potential_vehicles = re.findall(r'\b[A-Z0-9]{6,10}\b', text)
    for vehicle in potential_vehicles:
        print(f"🚗 Potential: {vehicle}")

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("Usage: python debug_ocr.py <image_path>")
        sys.exit(1)
    
    debug_ocr_extraction(sys.argv[1])