#!/usr/bin/env python3
"""
Test the real OCR processor with the L&T weighbridge slip
"""

import sys
import os
sys.path.append('/Users/syedkhaja/Desktop/Prestige Park Groove Main Code 2/ml')

try:
    from real_ocr_processor import RealWeighbridgeOCR
    print("✅ RealWeighbridgeOCR imported successfully")
except ImportError as e:
    print(f"❌ Failed to import RealWeighbridgeOCR: {e}")
    print("Installing required dependencies...")
    import subprocess
    subprocess.run([sys.executable, '-m', 'pip', 'install', 'opencv-python', 'pytesseract', 'pillow'])
    
    try:
        from real_ocr_processor import RealWeighbridgeOCR
        print("✅ RealWeighbridgeOCR imported after installing dependencies")
    except ImportError as e2:
        print(f"❌ Still failed to import: {e2}")
        print("Note: You may need to install tesseract-ocr system package")
        sys.exit(1)

def test_real_ocr():
    """Test the real OCR processor"""
    
    # Test image path
    image_path = "/Users/syedkhaja/Desktop/Prestige Park Groove Main Code 2/ml/PHOTO-2025-07-15-17-27-21.jpg"
    
    if not os.path.exists(image_path):
        print(f"❌ Test image not found: {image_path}")
        return
    
    print(f"🔍 Testing real OCR with: {image_path}")
    
    try:
        # Initialize processor
        processor = RealWeighbridgeOCR()
        print("✅ OCR processor initialized")
        
        # Read image as bytes
        with open(image_path, 'rb') as f:
            image_bytes = f.read()
        
        print(f"📸 Loaded image: {len(image_bytes)} bytes")
        
        # Process image
        print("🔄 Processing image...")
        result = processor.process_image_from_bytes(image_bytes)
        
        print("\n📊 OCR Results:")
        print("=" * 50)
        
        # Display results
        for key, value in result.items():
            if key == 'extracted_text_preview':
                continue  # Skip text preview for readability
            
            status = "✅" if value and str(value) not in ['False', '0', 'None'] else "❌"
            print(f"  {status} {key}: {value}")
        
        # Summary
        extracted_fields = sum(1 for v in result.values() 
                             if v and str(v) not in ['True', 'False', '0'] and 'error' not in str(v).lower())
        
        print(f"\n📈 Summary:")
        print(f"  Fields extracted: {extracted_fields}/9")
        print(f"  Confidence: {result.get('confidence_score', 0):.1f}%")
        print(f"  Validation passed: {result.get('validation_passed', False)}")
        
        if result.get('validation_warnings'):
            print(f"  Warnings: {result['validation_warnings']}")
        
        if result.get('extracted_text_preview'):
            print(f"\n📝 Text Preview:")
            print(f"  {result['extracted_text_preview'][:100]}...")
        
        # Check specific expected values
        expected = {
            'vehicle_number': 'KA034C313',  # From the image
            'driver_name': 'Sartmul',
            'transporter': 'foyer mines',
            'material_category': 'Aggregate'
        }
        
        print(f"\n🎯 Expected vs Actual:")
        for field, expected_val in expected.items():
            actual_val = result.get(field)
            match = "✅" if actual_val and expected_val.lower() in str(actual_val).lower() else "❌"
            print(f"  {match} {field}: expected '{expected_val}' → got '{actual_val}'")
        
        return result
        
    except Exception as e:
        print(f"💥 Error testing OCR: {e}")
        import traceback
        traceback.print_exc()
        return None

if __name__ == "__main__":
    print("🚀 Testing Real OCR Processor")
    print("=" * 50)
    
    result = test_real_ocr()
    
    if result:
        print("\n🎉 OCR test completed!")
    else:
        print("\n❌ OCR test failed!")