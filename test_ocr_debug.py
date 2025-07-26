#!/usr/bin/env python3
"""
Debug script to test OCR extraction with the actual weighbridge image
"""

import requests
import json

def test_ocr_extraction():
    """Test the OCR service with the weighbridge image from the screenshot"""
    
    # Use the weighbridge slip image from the screenshot
    image_path = "/Users/syedkhaja/Desktop/PHOTO-2025-07-17-12-31-02.jpg"
    ocr_url = "http://54.146.215.18/extract-weights"
    
    print("🔍 Testing OCR extraction...")
    print(f"Image: {image_path}")
    print(f"OCR Service: {ocr_url}")
    
    try:
        # Prepare the request
        with open(image_path, 'rb') as image_file:
            files = {'file': image_file}
            
            print("\n📤 Sending request to OCR service...")
            response = requests.post(ocr_url, files=files, timeout=60)
            
            print(f"Status Code: {response.status_code}")
            print(f"Response Headers: {dict(response.headers)}")
            
            if response.status_code == 200:
                result = response.json()
                print("\n✅ OCR Response:")
                print(json.dumps(result, indent=2))
                
                # Check extracted data
                if result.get('success'):
                    data = result.get('data', {})
                    print("\n📊 Extracted Fields:")
                    for key, value in data.items():
                        status = "✅" if value else "❌"
                        print(f"  {status} {key}: {value}")
                        
                    # Check weight fields specifically
                    weight_fields = ['gross_weight', 'tare_weight', 'net_weight']
                    weights_extracted = any(data.get(field) for field in weight_fields)
                    
                    if weights_extracted:
                        print("\n✅ Weight information was extracted!")
                    else:
                        print("\n❌ No weight information extracted - this is the issue!")
                        
                else:
                    print(f"\n❌ OCR processing failed: {result.get('message', 'Unknown error')}")
            else:
                print(f"\n❌ HTTP Error: {response.status_code}")
                print(f"Response: {response.text}")
                
    except requests.exceptions.Timeout:
        print("\n⏰ Request timed out - OCR processing took too long")
    except requests.exceptions.ConnectionError:
        print("\n🔌 Connection error - OCR service may be down")
    except FileNotFoundError:
        print(f"\n📁 Image file not found: {image_path}")
    except Exception as e:
        print(f"\n💥 Unexpected error: {e}")

if __name__ == "__main__":
    test_ocr_extraction()