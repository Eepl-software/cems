import unittest
import requests
import json
import cv2
import numpy as np
from PIL import Image, ImageDraw, ImageFont
import io
import os
from ocr_processor import WeighbridgeOCR

class TestWeighbridgeOCR(unittest.TestCase):
    """
    Test suite for Weighbridge OCR functionality
    """
    
    def setUp(self):
        """Set up test fixtures"""
        self.ocr_processor = WeighbridgeOCR()
        self.api_base_url = "http://localhost:8000"
        
    def create_test_image(self, gross_weight="28000", tare_weight="12000", net_weight="16000"):
        """
        Create a synthetic test image with weighbridge slip format
        
        Args:
            gross_weight: GROSS weight value
            tare_weight: TARE weight value
            net_weight: NET weight value
            
        Returns:
            PIL Image object
        """
        # Create a white background
        img = Image.new('RGB', (800, 600), color='white')
        draw = ImageDraw.Draw(img)
        
        # Try to use a default font, fallback to basic font
        try:
            font = ImageFont.truetype("arial.ttf", 24)
            header_font = ImageFont.truetype("arial.ttf", 32)
        except:
            font = ImageFont.load_default()
            header_font = ImageFont.load_default()
        
        # Draw header
        draw.text((200, 50), "WEIGHBRIDGE SLIP", fill='black', font=header_font)
        
        # Draw weight information
        draw.text((100, 150), f"GROSS : {gross_weight} Kg", fill='black', font=font)
        draw.text((100, 200), f"TARE  : {tare_weight} Kg", fill='black', font=font)
        draw.text((100, 250), f"NET   : {net_weight} Kg", fill='black', font=font)
        
        # Add some additional typical weighbridge slip content
        draw.text((100, 350), "Date: 2025-07-14", fill='black', font=font)
        draw.text((100, 400), "Time: 10:30", fill='black', font=font)
        draw.text((100, 450), "Vehicle No: KA01AB1234", fill='black', font=font)
        
        return img
    
    def test_ocr_processor_initialization(self):
        """Test OCR processor initialization"""
        self.assertIsNotNone(self.ocr_processor)
        self.assertIsNotNone(self.ocr_processor.tesseract_config)
    
    def test_image_preprocessing(self):
        """Test image preprocessing functionality"""
        # Create test image
        test_img = self.create_test_image()
        
        # Convert to numpy array
        img_array = np.array(test_img)
        
        # Test preprocessing
        preprocessed = self.ocr_processor.preprocess_image(img_array)
        
        # Check that preprocessing returns a valid image
        self.assertIsNotNone(preprocessed)
        self.assertEqual(len(preprocessed.shape), 2)  # Should be grayscale
        self.assertGreater(preprocessed.shape[0], 0)
        self.assertGreater(preprocessed.shape[1], 0)
    
    def test_text_extraction(self):
        """Test text extraction from image"""
        # Create test image
        test_img = self.create_test_image()
        img_array = np.array(test_img)
        
        # Preprocess and extract text
        preprocessed = self.ocr_processor.preprocess_image(img_array)
        text = self.ocr_processor.extract_text_from_image(preprocessed)
        
        # Check that text was extracted
        self.assertIsNotNone(text)
        self.assertIsInstance(text, str)
        self.assertGreater(len(text), 0)
    
    def test_weight_parsing(self):
        """Test weight parsing from extracted text"""
        # Test with standard format
        test_text = """
        WEIGHBRIDGE SLIP
        GROSS : 28000 Kg
        TARE  : 12000 Kg
        NET   : 16000 Kg
        """
        
        weights = self.ocr_processor.parse_weights(test_text)
        
        self.assertEqual(weights['gross_weight'], '28000 Kg')
        self.assertEqual(weights['tare_weight'], '12000 Kg')
        self.assertEqual(weights['net_weight'], '16000 Kg')
    
    def test_weight_parsing_variations(self):
        """Test weight parsing with different formats"""
        test_cases = [
            {
                'text': 'GROSS WEIGHT: 25,000 KG\nTARE WEIGHT: 10,000 KG\nNET WEIGHT: 15,000 KG',
                'expected': {'gross_weight': '25000 KG', 'tare_weight': '10000 KG', 'net_weight': '15000 KG'}
            },
            {
                'text': 'Gross: 30000\nTare: 15000\nNet: 15000',
                'expected': {'gross_weight': '30000 Kg', 'tare_weight': '15000 Kg', 'net_weight': '15000 Kg'}
            }
        ]
        
        for test_case in test_cases:
            weights = self.ocr_processor.parse_weights(test_case['text'])
            for key, expected_value in test_case['expected'].items():
                self.assertEqual(weights[key], expected_value)
    
    def test_weight_validation(self):
        """Test weight validation logic"""
        # Valid weights (GROSS = TARE + NET)
        valid_weights = {
            'gross_weight': '28000 Kg',
            'tare_weight': '12000 Kg',
            'net_weight': '16000 Kg'
        }
        
        self.assertTrue(self.ocr_processor.validate_weights(valid_weights))
        
        # Invalid weights
        invalid_weights = {
            'gross_weight': '28000 Kg',
            'tare_weight': '12000 Kg',
            'net_weight': '20000 Kg'  # This doesn't match GROSS - TARE
        }
        
        self.assertFalse(self.ocr_processor.validate_weights(invalid_weights))
    
    def test_full_processing_pipeline(self):
        """Test complete image processing pipeline"""
        # Create test image
        test_img = self.create_test_image("30000", "15000", "15000")
        
        # Save to temporary file
        temp_path = "/tmp/test_weighbridge.png"
        test_img.save(temp_path)
        
        # Process image
        result = self.ocr_processor.process_image(temp_path)
        
        # Check results
        self.assertIsNotNone(result)
        self.assertIn('gross_weight', result)
        self.assertIn('tare_weight', result)
        self.assertIn('net_weight', result)
        self.assertIn('validation_passed', result)
        
        # Clean up
        if os.path.exists(temp_path):
            os.remove(temp_path)
    
    def test_process_image_from_bytes(self):
        """Test processing image from bytes"""
        # Create test image
        test_img = self.create_test_image()
        
        # Convert to bytes
        img_bytes = io.BytesIO()
        test_img.save(img_bytes, format='PNG')
        img_bytes = img_bytes.getvalue()
        
        # Process from bytes
        result = self.ocr_processor.process_image_from_bytes(img_bytes)
        
        # Check results
        self.assertIsNotNone(result)
        self.assertIn('gross_weight', result)
        self.assertIn('tare_weight', result)
        self.assertIn('net_weight', result)

class TestAPIEndpoints(unittest.TestCase):
    """
    Test suite for API endpoints
    """
    
    def setUp(self):
        """Set up test fixtures"""
        self.api_base_url = "http://localhost:8000"
        
    def create_test_image_bytes(self):
        """Create test image as bytes"""
        img = Image.new('RGB', (800, 600), color='white')
        draw = ImageDraw.Draw(img)
        
        try:
            font = ImageFont.truetype("arial.ttf", 24)
        except:
            font = ImageFont.load_default()
        
        draw.text((100, 150), "GROSS : 28000 Kg", fill='black', font=font)
        draw.text((100, 200), "TARE  : 12000 Kg", fill='black', font=font)
        draw.text((100, 250), "NET   : 16000 Kg", fill='black', font=font)
        
        img_bytes = io.BytesIO()
        img.save(img_bytes, format='PNG')
        return img_bytes.getvalue()
    
    def test_health_endpoint(self):
        """Test health check endpoint"""
        try:
            response = requests.get(f"{self.api_base_url}/health")
            self.assertEqual(response.status_code, 200)
            
            data = response.json()
            self.assertEqual(data['status'], 'healthy')
            self.assertEqual(data['service'], 'weighbridge-ocr-api')
        except requests.exceptions.ConnectionError:
            self.skipTest("API server not running")
    
    def test_extract_weights_endpoint(self):
        """Test weight extraction endpoint"""
        try:
            img_bytes = self.create_test_image_bytes()
            
            files = {'file': ('test.png', img_bytes, 'image/png')}
            response = requests.post(f"{self.api_base_url}/extract-weights", files=files)
            
            self.assertEqual(response.status_code, 200)
            
            data = response.json()
            self.assertTrue(data['success'])
            self.assertIn('data', data)
            self.assertIn('gross_weight', data['data'])
            self.assertIn('tare_weight', data['data'])
            self.assertIn('net_weight', data['data'])
            
        except requests.exceptions.ConnectionError:
            self.skipTest("API server not running")

def run_performance_test():
    """
    Run performance tests on the OCR system
    """
    print("Running performance tests...")
    
    ocr_processor = WeighbridgeOCR()
    
    # Create test images
    test_images = []
    for i in range(10):
        img = Image.new('RGB', (800, 600), color='white')
        draw = ImageDraw.Draw(img)
        
        try:
            font = ImageFont.truetype("arial.ttf", 24)
        except:
            font = ImageFont.load_default()
        
        gross = 25000 + i * 1000
        tare = 12000 + i * 100
        net = gross - tare
        
        draw.text((100, 150), f"GROSS : {gross} Kg", fill='black', font=font)
        draw.text((100, 200), f"TARE  : {tare} Kg", fill='black', font=font)
        draw.text((100, 250), f"NET   : {net} Kg", fill='black', font=font)
        
        img_bytes = io.BytesIO()
        img.save(img_bytes, format='PNG')
        test_images.append(img_bytes.getvalue())
    
    # Time the processing
    import time
    start_time = time.time()
    
    for img_bytes in test_images:
        result = ocr_processor.process_image_from_bytes(img_bytes)
    
    end_time = time.time()
    
    avg_time = (end_time - start_time) / len(test_images)
    print(f"Average processing time per image: {avg_time:.2f} seconds")
    print(f"Total processing time for {len(test_images)} images: {end_time - start_time:.2f} seconds")

if __name__ == '__main__':
    # Run unit tests
    print("Running unit tests...")
    unittest.main(verbosity=2, exit=False)
    
    # Run performance tests
    run_performance_test()