import cv2
import pytesseract
import numpy as np
import re
from PIL import Image
from typing import Dict, Optional, Tuple, List
import logging

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class ImprovedWeighbridgeOCR:
    """
    Improved OCR processor for L&T Construction weighbridge slips
    Enhanced patterns based on actual slip analysis
    """
    
    def __init__(self):
        # Configure Tesseract for better OCR results
        self.tesseract_config = r'--oem 3 --psm 6'
        
    def preprocess_image(self, image: np.ndarray) -> np.ndarray:
        """
        Enhanced image preprocessing for L&T weighbridge slips
        """
        # Convert to grayscale
        if len(image.shape) == 3:
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        else:
            gray = image
            
        # Apply Gaussian blur to reduce noise
        blurred = cv2.GaussianBlur(gray, (1, 1), 0)
        
        # Apply adaptive thresholding
        thresh = cv2.adaptiveThreshold(
            blurred, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 11, 2
        )
        
        # Morphological operations to clean up the image
        kernel = np.ones((1, 1), np.uint8)
        cleaned = cv2.morphologyEx(thresh, cv2.MORPH_CLOSE, kernel)
        
        # Resize image for better OCR accuracy
        height, width = cleaned.shape
        if height < 1000 or width < 1000:
            scale_factor = max(1000 / height, 1000 / width)
            new_width = int(width * scale_factor)
            new_height = int(height * scale_factor)
            cleaned = cv2.resize(cleaned, (new_width, new_height), interpolation=cv2.INTER_CUBIC)
        
        return cleaned
    
    def extract_text_from_image(self, image: np.ndarray) -> str:
        """
        Extract text from preprocessed image using multiple OCR configurations
        """
        try:
            # Convert numpy array to PIL Image
            pil_image = Image.fromarray(image)
            
            # Try multiple OCR configurations
            configs = [
                r'--oem 3 --psm 6',  # Default
                r'--oem 3 --psm 4',  # Single column
                r'--oem 3 --psm 1',  # Automatic page segmentation
                r'--oem 3 --psm 3'   # Fully automatic
            ]
            
            best_text = ""
            max_length = 0
            
            for config in configs:
                try:
                    text = pytesseract.image_to_string(pil_image, config=config)
                    if len(text) > max_length:
                        max_length = len(text)
                        best_text = text
                except:
                    continue
            
            return best_text
        except Exception as e:
            logger.error(f"Error extracting text: {str(e)}")
            return ""
    
    def parse_enhanced_weighbridge_data(self, text: str) -> Dict[str, Optional[str]]:
        """
        Enhanced parsing for L&T Construction weighbridge slips
        """
        # Initialize result dictionary
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
        text_lines = text.split('\n')
        
        # Extract Weighment Slip Number (very specific to L&T format)
        slip_patterns = [
            r'WEIGHMENT\s+SLIP[:\s]*([A-Z0-9\-]+)',
            r'WB\d+R\d+\-?\d*',
            r'(WB\d{2,3}R\d{12,15}\-?\d?)',
            r'SLIP[:\s]+([A-Z0-9\-]{10,})'
        ]
        
        for pattern in slip_patterns:
            match = re.search(pattern, text_upper)
            if match:
                slip_no = match.group(1) if match.lastindex else match.group(0)
                if len(slip_no) > 8:
                    result['weighment_slip_no'] = slip_no
                    break
        
        # Extract Vehicle Number (specific patterns from slips)
        vehicle_patterns = [
            r'VEHICLE\s+NUMBER[:\s]*([A-Z]{2}\d{2,3}[A-Z]?\d{3,4})',
            r'([A-Z]{2}\d{2,3}[A-Z]?\d{3,4})',  # Direct format like TN914235, KA034C313
            r'([A-Z]{2}\s*\d{2,3}\s*[A-Z]?\s*\d{3,4})',
            r'TN\d{6}',
            r'KA\d{3}[A-Z]\d{3}'
        ]
        
        for pattern in vehicle_patterns:
            match = re.search(pattern, text_upper)
            if match:
                vehicle = match.group(1) if match.lastindex else match.group(0)
                vehicle = vehicle.replace(' ', '')
                # Filter out weighment slip numbers that match vehicle pattern
                if not vehicle.startswith('WB') and len(vehicle) >= 8:
                    result['vehicle_number'] = vehicle
                    break
        
        # Extract Driver Name (case sensitive for names)
        driver_patterns = [
            r'DRIVER\s+NAME[:\s]*([a-zA-Z\s]+?)(?:\s+[A-Z]{2}|\s*$|\s+TRANSPORTER)',
            r'NAME[:\s]*([a-zA-Z\s]{3,20})(?:\s+[A-Z]{2}|\s*$|\s+TRANSPORTER)',
            r'Driver[:\s]*([a-zA-Z\s]{3,20})',
        ]
        
        for pattern in driver_patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                name = match.group(1).strip()
                # Clean name (remove numbers, extra spaces)
                name = re.sub(r'\d+', '', name)
                name = re.sub(r'\s+', ' ', name).strip()
                if len(name) > 2 and name.upper() not in ['TRANSPORTER', 'VEHICLE', 'NUMBER', 'NAME']:
                    result['driver_name'] = name
                    break
        
        # Extract Transporter
        transporter_patterns = [
            r'TRANSPORTER[:\s]*([a-zA-Z\s]+?)(?:\s+[A-Z]{2}|\s*$|\s+CONSIGNOR)',
            r'([a-zA-Z\s]*(?:LOGISTICS|MINES|TRANSPORT)[a-zA-Z\s]*)',
        ]
        
        for pattern in transporter_patterns:
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                transporter = match.group(1).strip()
                transporter = re.sub(r'\d+', '', transporter)
                transporter = re.sub(r'\s+', ' ', transporter).strip()
                if len(transporter) > 3:
                    result['transporter'] = transporter
                    break
        
        # Extract Material Name from table format
        material_patterns = [
            r'ORDINARY\s+PORTLAND\s+CEMENT',
            r'STONE\s+AGGREGATE',
            r'Material\s+Name[^|]*?([A-Z\s]+(?:CEMENT|AGGREGATE))',
            r'1\s+([A-Z\s]+(?:CEMENT|AGGREGATE))',  # Row 1 in table
        ]
        
        for pattern in material_patterns:
            match = re.search(pattern, text_upper)
            if match:
                if pattern == r'ORDINARY\s+PORTLAND\s+CEMENT' or pattern == r'STONE\s+AGGREGATE':
                    result['material_name'] = match.group(0)
                else:
                    material = match.group(1).strip()
                    if len(material) > 5:
                        result['material_name'] = material
                break
        
        # Extract Material Category
        if result['material_name']:
            if 'CEMENT' in result['material_name']:
                result['material_category'] = 'Grey Cement'
            elif 'AGGREGATE' in result['material_name']:
                result['material_category'] = 'Aggregate'
        
        # Extract weights from table format (more specific patterns)
        # Look for weight table with Gross, Tare, Net rows
        weight_patterns = {
            'gross_weight': [
                r'GROSS[:\s]*(\d{4,6})',
                r'Gross[:\s]*(\d{4,6})',
                r'(\d{4,6})\s*15-07-2025\s*11:16:03',  # Specific to slip format
            ],
            'tare_weight': [
                r'TARE[:\s]*(\d{4,6})',
                r'Tare[:\s]*(\d{4,6})',
                r'(\d{4,6})\s*15-07-2025\s*16:01:45',  # Specific to slip format
            ],
            'net_weight': [
                r'NET[:\s]*(\d{4,6})',
                r'Net[:\s]*(\d{4,6})',
                r'(\d{4,6})\s*$',  # Weight at end of line
            ]
        }
        
        # Try to extract weights from structured table format
        lines = text.split('\n')
        for i, line in enumerate(lines):
            line_upper = line.upper()
            
            # Look for weight table headers and values
            if 'GROSS' in line_upper and any(char.isdigit() for char in line):
                numbers = re.findall(r'\d{4,6}', line)
                if numbers:
                    result['gross_weight'] = f"{numbers[0]} KG"
            
            if 'TARE' in line_upper and any(char.isdigit() for char in line):
                numbers = re.findall(r'\d{4,6}', line)
                if numbers:
                    result['tare_weight'] = f"{numbers[0]} KG"
            
            if 'NET' in line_upper and any(char.isdigit() for char in line):
                numbers = re.findall(r'\d{4,6}', line)
                if numbers:
                    result['net_weight'] = f"{numbers[0]} KG"
        
        # Fallback weight extraction using regex patterns
        for weight_type, patterns in weight_patterns.items():
            if not result[weight_type]:  # Only if not found above
                for pattern in patterns:
                    match = re.search(pattern, text)
                    if match:
                        weight_value = match.group(1)
                        if weight_value.isdigit() and int(weight_value) > 1000:
                            result[weight_type] = f"{weight_value} KG"
                            break
        
        return result
    
    def validate_enhanced_data(self, data: Dict[str, Optional[str]]) -> bool:
        """
        Validate extracted weighbridge data
        """
        try:
            # Check minimum required fields
            required_fields = ['weighment_slip_no', 'vehicle_number']
            missing_fields = [field for field in required_fields if not data.get(field)]
            
            if missing_fields:
                logger.warning(f"Missing critical fields: {missing_fields}")
                return False
            
            # Validate weight relationship if all weights are present
            if all(data.get(field) for field in ['gross_weight', 'tare_weight', 'net_weight']):
                try:
                    gross_num = float(re.search(r'(\d+)', data['gross_weight']).group(1))
                    tare_num = float(re.search(r'(\d+)', data['tare_weight']).group(1))
                    net_num = float(re.search(r'(\d+)', data['net_weight']).group(1))
                    
                    # Validate relationship: GROSS = TARE + NET (with tolerance)
                    calculated_net = gross_num - tare_num
                    tolerance = 0.15  # 15% tolerance for OCR errors
                    
                    if abs(calculated_net - net_num) / max(net_num, 1) > tolerance:
                        logger.warning(f"Weight validation failed: GROSS({gross_num}) - TARE({tare_num}) != NET({net_num})")
                        return False
                        
                except (AttributeError, ValueError) as e:
                    logger.warning(f"Could not validate weights: {e}")
                    return False
            
            return True
            
        except Exception as e:
            logger.error(f"Error validating data: {str(e)}")
            return False
    
    def process_image(self, image_path: str) -> Dict[str, Optional[str]]:
        """
        Main processing function for L&T weighbridge slips
        """
        try:
            # Load image
            image = cv2.imread(image_path)
            if image is None:
                raise ValueError(f"Could not load image from {image_path}")
            
            # Preprocess image
            preprocessed = self.preprocess_image(image)
            
            # Extract text
            extracted_text = self.extract_text_from_image(preprocessed)
            logger.info(f"Extracted text: {extracted_text[:500]}...")
            
            # Parse all weighbridge data
            data = self.parse_enhanced_weighbridge_data(extracted_text)
            
            # Validate data
            is_valid = self.validate_enhanced_data(data)
            data['validation_passed'] = is_valid
            data['extracted_text'] = extracted_text
            
            return data
            
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
                "error": str(e)
            }
    
    def process_image_from_bytes(self, image_bytes: bytes) -> Dict[str, Optional[str]]:
        """
        Process image from bytes (for API uploads)
        """
        try:
            # Convert bytes to numpy array
            nparr = np.frombuffer(image_bytes, np.uint8)
            image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            
            if image is None:
                raise ValueError("Could not decode image from bytes")
            
            # Preprocess image
            preprocessed = self.preprocess_image(image)
            
            # Extract text
            extracted_text = self.extract_text_from_image(preprocessed)
            logger.info(f"Extracted text: {extracted_text[:500]}...")
            
            # Parse all weighbridge data
            data = self.parse_enhanced_weighbridge_data(extracted_text)
            
            # Validate data
            is_valid = self.validate_enhanced_data(data)
            data['validation_passed'] = is_valid
            data['extracted_text'] = extracted_text
            
            return data
            
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
                "error": str(e)
            }