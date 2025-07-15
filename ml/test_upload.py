#!/usr/bin/env python3

import requests
import sys
import os

def test_ocr_upload(image_path, base_url="http://localhost:8000"):
    """Test OCR service with an image upload"""
    
    if not os.path.exists(image_path):
        print(f"❌ Image file not found: {image_path}")
        return False
    
    # Test health endpoint first
    try:
        response = requests.get(f"{base_url}/health")
        if response.status_code == 200:
            print("✅ Health check passed")
        else:
            print(f"❌ Health check failed: {response.status_code}")
            return False
    except Exception as e:
        print(f"❌ Cannot connect to service: {e}")
        return False
    
    # Test file upload
    try:
        with open(image_path, 'rb') as f:
            files = {'file': (os.path.basename(image_path), f, 'image/png')}
            response = requests.post(f"{base_url}/extract-weights", files=files)
            
        print(f"📤 Upload Status: {response.status_code}")
        print(f"📋 Response: {response.text}")
        
        if response.status_code == 200:
            print("✅ Upload successful!")
            data = response.json()
            if data.get('success'):
                weights = data.get('data', {})
                print(f"🏋️ Gross Weight: {weights.get('gross_weight', 'Not found')}")
                print(f"🏋️ Tare Weight: {weights.get('tare_weight', 'Not found')}")
                print(f"🏋️ Net Weight: {weights.get('net_weight', 'Not found')}")
                print(f"✅ Validation: {weights.get('validation_passed', False)}")
            return True
        else:
            print(f"❌ Upload failed: {response.status_code}")
            return False
            
    except Exception as e:
        print(f"❌ Upload error: {e}")
        return False

if __name__ == "__main__":
    # Use test image if it exists
    test_image = "test_weighbridge_slip.png"
    if len(sys.argv) > 1:
        test_image = sys.argv[1]
    
    if not os.path.exists(test_image):
        print(f"❌ Test image not found: {test_image}")
        print("Please provide an image file path as argument")
        print("Usage: python test_upload.py <image_path>")
        sys.exit(1)
    
    print(f"🧪 Testing OCR service with image: {test_image}")
    success = test_ocr_upload(test_image)
    
    if success:
        print("🎉 Test completed successfully!")
    else:
        print("💥 Test failed!")
        sys.exit(1)