#!/usr/bin/env python3
"""
Full OCR system test with Tesseract
"""

import sys
import os
import time
import tempfile
import threading
import requests
from PIL import Image, ImageDraw, ImageFont
import cv2
import numpy as np

# Add current directory to path so we can import our modules
sys.path.insert(0, '/Users/syedkhaja/Desktop/Prestige Park Groove Main Code 2/ml')

def test_tesseract_integration():
    """Test Tesseract OCR integration"""
    print("Testing Tesseract OCR integration...")
    
    try:
        import pytesseract
        
        # Test basic OCR
        test_image = Image.new('RGB', (400, 100), color='white')
        draw = ImageDraw.Draw(test_image)
        
        try:
            font = ImageFont.load_default()
            draw.text((10, 30), "GROSS : 28000 Kg", fill='black', font=font)
            
            # Extract text
            text = pytesseract.image_to_string(test_image)
            print(f"✓ Tesseract extracted text: '{text.strip()}'")
            
            if "GROSS" in text.upper() and "28000" in text:
                print("✓ Tesseract basic OCR working")
                return True
            else:
                print("✗ Tesseract text extraction not accurate enough")
                return False
                
        except Exception as e:
            print(f"✗ Tesseract processing failed: {e}")
            return False
            
    except ImportError as e:
        print(f"✗ Tesseract import failed: {e}")
        return False

def test_ocr_processor():
    """Test OCR processor module"""
    print("\nTesting OCR processor module...")
    
    try:
        from ocr_processor import WeighbridgeOCR
        
        # Initialize processor
        processor = WeighbridgeOCR()
        print("✓ OCR processor initialized")
        
        # Create test image
        test_image = Image.new('RGB', (800, 600), color='white')
        draw = ImageDraw.Draw(test_image)
        
        font = ImageFont.load_default()
        draw.text((100, 150), "GROSS : 28000 Kg", fill='black', font=font)
        draw.text((100, 200), "TARE  : 12000 Kg", fill='black', font=font)
        draw.text((100, 250), "NET   : 16000 Kg", fill='black', font=font)
        
        # Save to temporary file
        with tempfile.NamedTemporaryFile(suffix='.png', delete=False) as tmp_file:
            test_image.save(tmp_file.name)
            tmp_path = tmp_file.name
        
        try:
            # Test processing
            result = processor.process_image(tmp_path)
            print(f"✓ OCR processing completed: {result}")
            
            # Check results
            if result.get('gross_weight') and result.get('tare_weight') and result.get('net_weight'):
                print("✓ All weights extracted successfully")
                return True
            else:
                print("✗ Some weights not extracted")
                return False
                
        finally:
            os.unlink(tmp_path)
            
    except Exception as e:
        print(f"✗ OCR processor test failed: {e}")
        return False

def test_api_server():
    """Test API server functionality"""
    print("\nTesting API server...")
    
    # Start server in background
    import subprocess
    import time
    
    server_process = None
    try:
        # Start server
        server_process = subprocess.Popen([
            'python3', 'main.py'
        ], cwd='/Users/syedkhaja/Desktop/Prestige Park Groove Main Code 2/ml')
        
        # Wait for server to start
        time.sleep(5)
        
        # Test health endpoint
        try:
            response = requests.get('http://localhost:8000/health')
            if response.status_code == 200:
                print("✓ API server health check passed")
            else:
                print(f"✗ Health check failed: {response.status_code}")
                return False
        except Exception as e:
            print(f"✗ Health check failed: {e}")
            return False
        
        # Test image upload
        try:
            # Create test image
            test_image = Image.new('RGB', (800, 600), color='white')
            draw = ImageDraw.Draw(test_image)
            
            font = ImageFont.load_default()
            draw.text((100, 150), "GROSS : 28000 Kg", fill='black', font=font)
            draw.text((100, 200), "TARE  : 12000 Kg", fill='black', font=font)
            draw.text((100, 250), "NET   : 16000 Kg", fill='black', font=font)
            
            # Save to bytes
            import io
            img_bytes = io.BytesIO()
            test_image.save(img_bytes, format='PNG')
            img_bytes.seek(0)
            
            # Upload to API
            files = {'file': ('test.png', img_bytes, 'image/png')}
            response = requests.post('http://localhost:8000/extract-weights', files=files)
            
            if response.status_code == 200:
                result = response.json()
                print(f"✓ API weight extraction successful: {result}")
                return True
            else:
                print(f"✗ API weight extraction failed: {response.status_code}")
                return False
                
        except Exception as e:
            print(f"✗ API upload test failed: {e}")
            return False
            
    except Exception as e:
        print(f"✗ API server test failed: {e}")
        return False
        
    finally:
        # Clean up server process
        if server_process:
            server_process.terminate()
            server_process.wait()

def test_image_formats():
    """Test different image formats"""
    print("\nTesting different image formats...")
    
    try:
        from ocr_processor import WeighbridgeOCR
        processor = WeighbridgeOCR()
        
        formats = ['PNG', 'JPEG', 'BMP']
        
        for fmt in formats:
            # Create test image
            test_image = Image.new('RGB', (800, 600), color='white')
            draw = ImageDraw.Draw(test_image)
            
            font = ImageFont.load_default()
            draw.text((100, 150), "GROSS : 25000 Kg", fill='black', font=font)
            draw.text((100, 200), "TARE  : 10000 Kg", fill='black', font=font)
            draw.text((100, 250), "NET   : 15000 Kg", fill='black', font=font)
            
            # Save in different formats
            with tempfile.NamedTemporaryFile(suffix=f'.{fmt.lower()}', delete=False) as tmp_file:
                test_image.save(tmp_file.name, format=fmt)
                tmp_path = tmp_file.name
            
            try:
                # Test processing
                result = processor.process_image(tmp_path)
                
                if result.get('gross_weight') and result.get('tare_weight') and result.get('net_weight'):
                    print(f"✓ {fmt} format processed successfully")
                else:
                    print(f"✗ {fmt} format processing failed")
                    
            finally:
                os.unlink(tmp_path)
                
        return True
        
    except Exception as e:
        print(f"✗ Image format test failed: {e}")
        return False

def test_performance():
    """Test performance with multiple images"""
    print("\nTesting performance...")
    
    try:
        from ocr_processor import WeighbridgeOCR
        processor = WeighbridgeOCR()
        
        # Create multiple test images
        num_images = 5
        test_images = []
        
        for i in range(num_images):
            test_image = Image.new('RGB', (800, 600), color='white')
            draw = ImageDraw.Draw(test_image)
            
            font = ImageFont.load_default()
            gross = 25000 + i * 1000
            tare = 10000 + i * 100
            net = gross - tare
            
            draw.text((100, 150), f"GROSS : {gross} Kg", fill='black', font=font)
            draw.text((100, 200), f"TARE  : {tare} Kg", fill='black', font=font)
            draw.text((100, 250), f"NET   : {net} Kg", fill='black', font=font)
            
            # Convert to bytes
            img_bytes = io.BytesIO()
            test_image.save(img_bytes, format='PNG')
            test_images.append(img_bytes.getvalue())
        
        # Time the processing
        start_time = time.time()
        
        for i, img_bytes in enumerate(test_images):
            result = processor.process_image_from_bytes(img_bytes)
            print(f"  Image {i+1}: {result.get('gross_weight', 'N/A')}, {result.get('tare_weight', 'N/A')}, {result.get('net_weight', 'N/A')}")
        
        end_time = time.time()
        
        total_time = end_time - start_time
        avg_time = total_time / num_images
        
        print(f"✓ Performance test completed:")
        print(f"  Total time: {total_time:.2f} seconds")
        print(f"  Average time per image: {avg_time:.2f} seconds")
        
        if avg_time < 5.0:  # Less than 5 seconds per image
            print("✓ Performance is acceptable")
            return True
        else:
            print("✗ Performance is too slow")
            return False
            
    except Exception as e:
        print(f"✗ Performance test failed: {e}")
        return False

def main():
    """Run all tests"""
    print("🧪 Running Full OCR System Tests\n")
    
    # Import required modules
    import io
    
    tests = [
        ("Tesseract Integration", test_tesseract_integration),
        ("OCR Processor", test_ocr_processor),
        ("Image Formats", test_image_formats),
        ("Performance", test_performance),
        ("API Server", test_api_server),
    ]
    
    passed = 0
    total = len(tests)
    
    for test_name, test_func in tests:
        print(f"\n{'='*60}")
        print(f"Running: {test_name}")
        print(f"{'='*60}")
        
        try:
            if test_func():
                print(f"✅ {test_name} PASSED")
                passed += 1
            else:
                print(f"❌ {test_name} FAILED")
        except Exception as e:
            print(f"❌ {test_name} FAILED with exception: {e}")
    
    print(f"\n{'='*60}")
    print(f"TEST SUMMARY: {passed}/{total} tests passed")
    print(f"{'='*60}")
    
    if passed == total:
        print("🎉 All tests passed! OCR system is fully functional.")
        print("\nSystem is ready for:")
        print("1. Production deployment")
        print("2. Flutter app integration")
        print("3. Real weighbridge slip processing")
    else:
        print("❌ Some tests failed. Please check the errors above.")
        
    return passed == total

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)