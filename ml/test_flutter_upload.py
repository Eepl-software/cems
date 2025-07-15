#!/usr/bin/env python3
"""
Test script that simulates a Flutter multipart upload
to help debug the 400 error issue
"""

import requests
import os
import sys

def test_flutter_like_upload(image_path, base_url="http://localhost:8000"):
    """Test upload that mimics Flutter's multipart request"""
    
    if not os.path.exists(image_path):
        print(f"❌ Image file not found: {image_path}")
        return False
    
    print(f"🧪 Testing Flutter-like upload with: {image_path}")
    
    try:
        # Method 1: Explicit content-type (like Flutter should do)
        print("\n📤 Test 1: With explicit content-type")
        with open(image_path, 'rb') as f:
            files = {
                'file': (os.path.basename(image_path), f, 'image/png')
            }
            response = requests.post(f"{base_url}/extract-weights", files=files)
            
        print(f"Status: {response.status_code}")
        print(f"Response: {response.text[:200]}...")
        
        # Method 2: No content-type (let requests guess)
        print("\n📤 Test 2: Without explicit content-type")
        with open(image_path, 'rb') as f:
            files = {
                'file': (os.path.basename(image_path), f)
            }
            response = requests.post(f"{base_url}/extract-weights", files=files)
            
        print(f"Status: {response.status_code}")
        print(f"Response: {response.text[:200]}...")
        
        # Method 3: Raw multipart (closest to Flutter)
        print("\n📤 Test 3: Raw multipart form")
        import requests_toolbelt
        from requests_toolbelt.multipart.encoder import MultipartEncoder
        
        with open(image_path, 'rb') as f:
            multipart_data = MultipartEncoder(
                fields={
                    'file': (os.path.basename(image_path), f, 'image/png')
                }
            )
            response = requests.post(
                f"{base_url}/extract-weights",
                data=multipart_data,
                headers={'Content-Type': multipart_data.content_type}
            )
            
        print(f"Status: {response.status_code}")
        print(f"Response: {response.text[:200]}...")
        
    except ImportError:
        print("⚠️ requests-toolbelt not installed, skipping test 3")
        print("Install with: pip install requests-toolbelt")
    except Exception as e:
        print(f"❌ Error during testing: {e}")
        return False
    
    return True

def test_curl_equivalent(image_path, base_url="http://localhost:8000"):
    """Show the curl equivalent for debugging"""
    print(f"\n🛠️ Curl equivalent for debugging:")
    print(f"curl -X POST '{base_url}/extract-weights' \\")
    print(f"  -F 'file=@{image_path}' \\")
    print(f"  -H 'Content-Type: multipart/form-data'")
    print()

if __name__ == "__main__":
    test_image = "test_weighbridge_slip.png"
    if len(sys.argv) > 1:
        test_image = sys.argv[1]
    
    if not os.path.exists(test_image):
        print(f"❌ Test image not found: {test_image}")
        print("Usage: python test_flutter_upload.py <image_path>")
        sys.exit(1)
    
    test_flutter_like_upload(test_image)
    test_curl_equivalent(test_image)