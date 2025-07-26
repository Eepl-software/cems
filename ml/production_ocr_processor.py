import cv2
import pytesseract
import numpy as np
import re
from PIL import Image
from typing import Dict, Optional
import logging
import json
import sys
import os

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class ProductionWeighbridgeOCR:
    """
    Production-ready OCR processor optimized for performance and accuracy
    """
    
    def __init__(self):
        # Multiple Tesseract configurations for different scenarios
        self.tesseract_configs = [
            r'--oem 3 --psm 6',  # Default - uniform block of text
            r'--oem 3 --psm 4',  # Single column of text
            r'--oem 3 --psm 8',  # Single word
            r'--oem 3 --psm 11', # Sparse text
        ]
        
    def preprocess_image(self, image: np.ndarray) -> np.ndarray:
        """
        Optimized preprocessing for weighbridge slips
        """
        # Convert to grayscale
        if len(image.shape) == 3:
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        else:
            gray = image
            
        # Noise reduction
        denoised = cv2.fastNlMeansDenoising(gray, None, 10, 7, 21)
        
        # Contrast enhancement using CLAHE
        clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
        enhanced = clahe.apply(denoised)
        
        # Adaptive thresholding
        thresh = cv2.adaptiveThreshold(
            enhanced, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 11, 2
        )
        
        # Morphological operations to clean up
        kernel = np.ones((2, 2), np.uint8)
        cleaned = cv2.morphologyEx(thresh, cv2.MORPH_CLOSE, kernel)
        
        # Ensure minimum size for better OCR
        height, width = cleaned.shape
        if height < 1000 or width < 1000:
            scale_factor = max(1000 / height, 1000 / width)
            new_width = int(width * scale_factor)
            new_height = int(height * scale_factor)
            cleaned = cv2.resize(cleaned, (new_width, new_height), interpolation=cv2.INTER_CUBIC)
        
        return cleaned
    
    def extract_text(self, image: np.ndarray) -> str:
        """
        Extract text using the best OCR configuration
        """
        pil_image = Image.fromarray(image)
        
        best_text = ""
        best_confidence = 0
        
        # Try different OCR configurations
        for config in self.tesseract_configs:
            try:
                # Get confidence data
                data = pytesseract.image_to_data(pil_image, config=config, output_type=pytesseract.Output.DICT)
                confidences = [int(conf) for conf in data['conf'] if int(conf) > 0]
                avg_confidence = sum(confidences) / len(confidences) if confidences else 0
                
                if avg_confidence > best_confidence:
                    text = pytesseract.image_to_string(pil_image, config=config)
                    if text.strip():
                        best_text = text
                        best_confidence = avg_confidence
                        
            except Exception as e:
                logger.warning(f"OCR config failed: {e}")
                continue
        
        return best_text
    
    def parse_weighbridge_data(self, text: str) -> Dict[str, Optional[str]]:
        """
        Parse weighbridge slip data from OCR text
        """
        result = {
            "material_name": None,
            "material_category": None,
            "gross_weight": None,
            "tare_weight": None,
            "net_weight": None,
            "weighment_slip_no": None,
            "vehicle_number": None,
            "driver_name": None,
            "transporter": None
        }
        
        # Clean and normalize text
        text = text.replace('\n', ' ').replace('\r', ' ')
        text_upper = text.upper()
        
        # Enhanced patterns for key fields
        patterns = {
            'weighment_slip_no': [
                r'WEIGHMENT\s+SLIP[:\s]*([A-Z0-9\-]{8,})',
                r'WB\d{2,3}R\d{12,15}\-?\d*',
                r'SLIP[:\s]*([A-Z0-9\-]{8,})',
            ],
            'vehicle_number': [
                r'VEHICLE\s+(?:NO|NUMBER)[:\s]*([A-Z]{2}\d{2,3}[A-Z]?\d{3,4})',
                r'([A-Z]{2}\d{2,3}[A-Z]?\d{3,4})(?!\d)',
                r'VEH[:\s]*([A-Z]{2}\d{2,3}[A-Z]?\d{3,4})',
            ],
            'gross_weight': [
                r'GROSS[:\s]*(\d{4,6})\s*(?:KG|KGS)?',
                r'GROSS\s+WEIGHT[:\s]*(\d{4,6})',
            ],
            'tare_weight': [
                r'TARE[:\s]*(\d{4,6})\s*(?:KG|KGS)?',
                r'TARE\s+WEIGHT[:\s]*(\d{4,6})',
            ],
            'net_weight': [
                r'NET[:\s]*(\d{4,6})\s*(?:KG|KGS)?',
                r'NET\s+WEIGHT[:\s]*(\d{4,6})',
                r'NETT?[:\s]*(\d{4,6})',
            ],
            'material_name': [
                r'ORDINARY\s+PORTLAND\s+CEMENT',
                r'STONE\s+AGGREGATE',
                r'MATERIAL\s+NAME[:\s]*([A-Z\s]+(?:CEMENT|AGGREGATE))',
            ],
            'driver_name': [
                r'DRIVER\s+NAME[:\s]*([A-Za-z\s]{3,25})',
                r'DRIVER[:\s]*([A-Za-z\s]{3,25})',
            ],
            'transporter': [
                r'TRANSPORTER[:\s]*([A-Za-z\s]{3,30})',
                r'([A-Za-z\s]*(?:LOGISTICS|TRANSPORT|MINES)[A-Za-z\s]*)',
            ]
        }
        
        # Extract fields
        for field, pattern_list in patterns.items():
            for pattern in pattern_list:
                flags = re.IGNORECASE if field in ['driver_name', 'transporter'] else 0
                match = re.search(pattern, text_upper if not flags else text, flags)
                
                if match:
                    value = match.group(1) if match.lastindex else match.group(0)
                    
                    # Clean and format value
                    if field in ['gross_weight', 'tare_weight', 'net_weight']:
                        if value.isdigit() and int(value) > 1000:
                            result[field] = f"{value} KG"
                            break
                    elif field == 'vehicle_number':
                        value = value.replace(' ', '')
                        if len(value) >= 8:
                            result[field] = value
                            break
                    elif field in ['driver_name', 'transporter']:
                        value = re.sub(r'\d+', '', value)
                        value = re.sub(r'\s+', ' ', value).strip()
                        if len(value) >= 3:
                            result[field] = value
                            break
                    elif field == 'weighment_slip_no':
                        if len(value) >= 8:
                            result[field] = value
                            break
                    elif field == 'material_name':
                        result[field] = value.strip()
                        break
        
        # Set material category based on material name
        if result['material_name']:
            if 'CEMENT' in result['material_name']:
                result['material_category'] = 'Grey Cement'
            elif 'AGGREGATE' in result['material_name'] or 'STONE' in result['material_name']:
                result['material_category'] = 'Aggregate'
        
        return result
    
    def validate_data(self, data: Dict[str, Optional[str]]) -> Dict[str, any]:
        """
        Validate extracted data
        """
        validation_result = {
            'is_valid': True,
            'confidence_score': 0,
            'errors': [],
            'warnings': []
        }
        
        # Check required fields
        required_fields = ['weighment_slip_no', 'vehicle_number']
        for field in required_fields:
            if not data.get(field):
                validation_result['errors'].append(f"Missing required field: {field}")
                validation_result['is_valid'] = False
        
        # Validate weight relationships
        if all(data.get(f) for f in ['gross_weight', 'tare_weight', 'net_weight']):
            try:
                gross = float(re.search(r'(\d+)', data['gross_weight']).group(1))
                tare = float(re.search(r'(\d+)', data['tare_weight']).group(1))
                net = float(re.search(r'(\d+)', data['net_weight']).group(1))
                
                calculated_net = gross - tare
                tolerance = 0.15
                
                if abs(calculated_net - net) / max(net, 1) > tolerance:
                    validation_result['warnings'].append(
                        f"Weight inconsistency: GROSS({gross}) - TARE({tare}) ≠ NET({net})"
                    )
            except:
                validation_result['warnings'].append("Could not validate weight relationships")
        
        # Calculate confidence score
        field_count = sum(1 for v in data.values() if v)
        validation_result['confidence_score'] = (field_count / len(data)) * 100
        
        return validation_result
    
    def process_image(self, image_path: str) -> Dict[str, any]:
        """
        Main processing function
        """
        try:
            # Load image
            image = cv2.imread(image_path)
            if image is None:
                raise ValueError(f"Could not load image from {image_path}")
            
            # Preprocess
            processed_image = self.preprocess_image(image)
            
            # Extract text
            extracted_text = self.extract_text(processed_image)
            
            # Parse data
            parsed_data = self.parse_weighbridge_data(extracted_text)
            
            # Validate
            validation_result = self.validate_data(parsed_data)
            
            # Compile result
            result = {
                **parsed_data,
                'validation_passed': validation_result['is_valid'],
                'confidence_score': validation_result['confidence_score'],
                'validation_errors': validation_result['errors'],
                'validation_warnings': validation_result['warnings']
            }
            
            return result
            
        except Exception as e:
            logger.error(f"Error processing image: {str(e)}")
            return {
                "material_name": None,
                "material_category": None,
                "gross_weight": None,
                "tare_weight": None,
                "net_weight": None,
                "weighment_slip_no": None,
                "vehicle_number": None,
                "driver_name": None,
                "transporter": None,
                "validation_passed": False,
                "confidence_score": 0,
                "error": str(e)
            }
    
    def process_image_from_bytes(self, image_bytes: bytes) -> Dict[str, any]:
        """
        Process image from bytes
        """
        try:
            # Convert bytes to numpy array
            nparr = np.frombuffer(image_bytes, np.uint8)
            image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            
            if image is None:
                raise ValueError("Could not decode image from bytes")
            
            # Preprocess
            processed_image = self.preprocess_image(image)
            
            # Extract text
            extracted_text = self.extract_text(processed_image)
            
            # Parse data
            parsed_data = self.parse_weighbridge_data(extracted_text)
            
            # Validate
            validation_result = self.validate_data(parsed_data)
            
            # Compile result
            result = {
                **parsed_data,
                'validation_passed': validation_result['is_valid'],
                'confidence_score': validation_result['confidence_score'],
                'validation_errors': validation_result['errors'],
                'validation_warnings': validation_result['warnings']
            }
            
            return result
            
        except Exception as e:
            logger.error(f"Error processing image from bytes: {str(e)}")
            return {
                "material_name": None,
                "material_category": None,
                "gross_weight": None,
                "tare_weight": None,
                "net_weight": None,
                "weighment_slip_no": None,
                "vehicle_number": None,
                "driver_name": None,
                "transporter": None,
                "validation_passed": False,
                "confidence_score": 0,
                "error": str(e)
            }

def main():
    """
    Command line interface for testing
    """
    if len(sys.argv) != 2:
        print("Usage: python production_ocr_processor.py <image_path>")
        sys.exit(1)
    
    image_path = sys.argv[1]
    
    if not os.path.exists(image_path):
        print(f"Error: Image file not found: {image_path}")
        sys.exit(1)
    
    # Process image
    processor = ProductionWeighbridgeOCR()
    result = processor.process_image(image_path)
    
    # Output JSON result
    print(json.dumps(result, indent=2))

if __name__ == "__main__":
    main()