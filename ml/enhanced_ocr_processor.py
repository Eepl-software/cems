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

class EnhancedWeighbridgeOCR:
    """
    Enhanced OCR processor for extracting comprehensive weighbridge slip data
    Extracts: Material name, Material category, Gross/Tare/Net weights, 
    Weighment slip no, Vehicle no, Driver name, Transporter fields
    """
    
    def __init__(self):
        # Configure Tesseract for better OCR results
        self.tesseract_config = r'--oem 3 --psm 6'
        
    def preprocess_image(self, image: np.ndarray) -> np.ndarray:
        """
        Enhanced image preprocessing for better OCR results
        
        Args:
            image: Input image as numpy array
            
        Returns:
            Preprocessed image
        """
        # Convert to grayscale
        if len(image.shape) == 3:
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        else:
            gray = image
            
        # Apply Gaussian blur to reduce noise
        blurred = cv2.GaussianBlur(gray, (3, 3), 0)
        
        # Apply adaptive thresholding
        thresh = cv2.adaptiveThreshold(
            blurred, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 11, 2
        )
        
        # Morphological operations to clean up the image
        kernel = np.ones((1, 1), np.uint8)
        cleaned = cv2.morphologyEx(thresh, cv2.MORPH_CLOSE, kernel)
        
        # Resize image for better OCR accuracy
        height, width = cleaned.shape
        if height < 800 or width < 800:
            scale_factor = max(800 / height, 800 / width)
            new_width = int(width * scale_factor)
            new_height = int(height * scale_factor)
            cleaned = cv2.resize(cleaned, (new_width, new_height), interpolation=cv2.INTER_CUBIC)
        
        return cleaned
    
    def extract_text_from_image(self, image: np.ndarray) -> str:
        """
        Extract text from preprocessed image using Tesseract
        
        Args:
            image: Preprocessed image
            
        Returns:
            Extracted text
        """
        try:
            # Convert numpy array to PIL Image
            pil_image = Image.fromarray(image)
            
            # Extract text using Tesseract with enhanced config
            text = pytesseract.image_to_string(pil_image, config=self.tesseract_config)
            
            return text
        except Exception as e:
            logger.error(f"Error extracting text: {str(e)}")
            return ""
    
    def parse_enhanced_weighbridge_data(self, text: str) -> Dict[str, Optional[str]]:
        """
        Enhanced parsing to extract all weighbridge slip fields
        
        Args:
            text: Extracted text from OCR
            
        Returns:
            Dictionary containing all extracted fields
        """
        # Initialize result dictionary with all required fields
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
        
        # Extract Material Name patterns
        material_patterns = [
            r'MATERIAL\s+NAME\s*:?\s*([A-Z\s,\.]+?)(?:MATERIAL\s+CATEGORY|$)',
            r'ORDINARY\s+PORTLAND\s+CEMENT[^A-Z]*([A-Z\s,\.]*)',
            r'STONE\s+AGGREGATE[^A-Z]*([A-Z\s,\.]*)',
            r'GRADE\s*[-:]\s*([^,\n]+)',
            r'([A-Z\s]+CEMENT[A-Z\s]*)',
            r'([A-Z\s]+AGGREGATE[A-Z\s]*)',
            r'FORM\s*[-:]\s*([^,\n]+)'
        ]
        
        for pattern in material_patterns:
            match = re.search(pattern, text_upper)
            if match:
                material = match.group(1).strip()
                if len(material) > 3 and material not in ['MATERIAL CATEGORY', 'WEIGHT']:
                    result['material_name'] = material
                    break
        
        # Extract Material Category patterns
        category_patterns = [
            r'MATERIAL\s+CATEGORY\s*:?\s*([A-Z\s]+?)(?:WEIGHT|$)',
            r'CATEGORY\s*:?\s*([A-Z\s]+?)(?:WEIGHT|$)',
            r'GREY\s+CEMENT',
            r'AGGREGATE',
            r'CEMENT',
            r'STONE'
        ]
        
        for pattern in category_patterns:
            match = re.search(pattern, text_upper)
            if match:
                if pattern in ['GREY\s+CEMENT', 'AGGREGATE', 'CEMENT', 'STONE']:
                    result['material_category'] = match.group(0)
                else:
                    category = match.group(1).strip()
                    if len(category) > 2:
                        result['material_category'] = category
                break
        
        # Extract Weight information (enhanced patterns)
        weight_patterns = {
            'gross_weight': [
                r'GROSS\s*:?\s*(\d+(?:,\d+)*\.?\d*)\s*(?:KG|KGS)?',
                r'GROSS\s+WEIGHT.*?(\d+(?:,\d+)*)',
                r'(?:^|\s)(\d{4,6})\s*(?:KG)?\s*(?:\d{2}-\d{2}-\d{4})'  # Pattern from slip
            ],
            'tare_weight': [
                r'TARE\s*:?\s*(\d+(?:,\d+)*\.?\d*)\s*(?:KG|KGS)?',
                r'TARE\s+WEIGHT.*?(\d+(?:,\d+)*)',
                r'(?:TARE.*?)(\d{4,5})\s*(?:KG)?'
            ],
            'net_weight': [
                r'NET\s*:?\s*(\d+(?:,\d+)*\.?\d*)\s*(?:KG|KGS)?',
                r'NET\s+WEIGHT.*?(\d+(?:,\d+)*)',
                r'(?:NET.*?)(\d{4,5})\s*(?:KG)?',
                r'NETT?\s*:?\s*(\d+(?:,\d+)*)'
            ]
        }
        
        # Extract weights
        for weight_type, patterns in weight_patterns.items():
            for pattern in patterns:
                match = re.search(pattern, text_upper)
                if match:
                    weight_value = match.group(1).replace(',', '')
                    if weight_value.isdigit() and int(weight_value) > 100:  # Reasonable weight check
                        result[weight_type] = f"{weight_value} KG"
                        break
        
        # Extract Weighment Slip Number
        slip_patterns = [
            r'WEIGHMENT\s+SLIP\s*:?\s*([A-Z0-9\-]+)',
            r'SLIP\s*:?\s*([A-Z0-9\-]+)',
            r'WB\d+R\d+',
            r'(WB[A-Z0-9\-]+)',
            r'SLIP\s+NO\s*:?\s*([A-Z0-9\-]+)'
        ]
        
        for pattern in slip_patterns:
            match = re.search(pattern, text_upper)
            if match:
                slip_no = match.group(1) if match.lastindex else match.group(0)
                if len(slip_no) > 5:  # Reasonable length check
                    result['weighment_slip_no'] = slip_no
                    break
        
        # Enhanced Vehicle number patterns
        vehicle_patterns = [
            r'VEHICLE\s*(?:NO|NUMBER|NUM)?\s*:?\s*([A-Z]{2}\s*\d{1,2}\s*[A-Z]{1,3}\s*\d{3,4})',
            r'VEH\s*(?:NO|NUMBER)?\s*:?\s*([A-Z]{2}\s*\d{1,2}\s*[A-Z]{1,3}\s*\d{3,4})',
            r'TRUCK\s*(?:NO|NUMBER)?\s*:?\s*([A-Z]{2}\s*\d{1,2}\s*[A-Z]{1,3}\s*\d{3,4})',
            r'\b([A-Z]{2}\d{1,2}[A-Z]{1,3}\d{3,4})\b',  # TN914235, KA034C313
            r'\b([A-Z]{2}\s*\d{1,2}\s*[A-Z]{1,3}\s*\d{3,4})\b',
            r'([A-Z]{2}\d{2}[A-Z]{1,2}\d{3,4})',  # Common Indian format
        ]
        
        for pattern in vehicle_patterns:
            match = re.search(pattern, text_upper)
            if match:
                vehicle_num = match.group(1).replace(' ', '')
                # Clean up common OCR errors
                vehicle_num = vehicle_num.replace('O', '0').replace('I', '1')
                if len(vehicle_num) >= 8:  # Valid vehicle number length
                    result['vehicle_number'] = vehicle_num
                    break
        
        # Extract Driver Name
        driver_patterns = [
            r'DRIVER\s+NAME\s*:?\s*([A-Za-z\s]+?)(?:TRANSPORTER|VEHICLE|$)',
            r'DRIVER\s*:?\s*([A-Za-z\s]+?)(?:TRANSPORTER|VEHICLE|$)',
            r'NAME\s*:?\s*([A-Za-z\s]+?)(?:TRANSPORTER|VEHICLE|$)'
        ]
        
        # Also try to find names in lowercase since OCR might preserve case
        text_mixed = text  # Keep original case for names
        
        for pattern in driver_patterns:
            match = re.search(pattern, text_mixed, re.IGNORECASE)
            if match:
                name = match.group(1).strip()
                # Clean up the name (remove extra spaces, numbers)
                name = re.sub(r'\s+', ' ', name)
                name = re.sub(r'[0-9]+', '', name).strip()
                if len(name) > 2 and name.upper() not in ['TRANSPORTER', 'VEHICLE', 'NUMBER']:
                    result['driver_name'] = name
                    break
        
        # Extract Transporter
        transporter_patterns = [
            r'TRANSPORTER\s*:?\s*([A-Za-z\s]+?)(?:CONSIGNOR|DOCUMENT|$)',
            r'TRANSPORTER\s*:?\s*([A-Za-z\s]+)',
            r'LOGISTICS\s*([A-Za-z\s]*)',
            r'MINES\s*([A-Za-z\s]*)'
        ]
        
        for pattern in transporter_patterns:
            match = re.search(pattern, text_mixed, re.IGNORECASE)
            if match:
                transporter = match.group(1).strip() if match.lastindex else match.group(0)
                # Clean up the transporter name
                transporter = re.sub(r'\s+', ' ', transporter)
                transporter = re.sub(r'[0-9]+', '', transporter).strip()
                if len(transporter) > 2:
                    result['transporter'] = transporter
                    break
        
        return result
    
    def validate_enhanced_data(self, data: Dict[str, Optional[str]]) -> bool:
        """
        Validate extracted weighbridge data for logical consistency
        
        Args:
            data: Dictionary of extracted data
            
        Returns:
            Boolean indicating if data is valid
        """
        try:
            # Check if we have minimum required fields
            required_fields = ['gross_weight', 'tare_weight', 'net_weight', 'vehicle_number']
            missing_fields = [field for field in required_fields if not data.get(field)]
            
            if missing_fields:
                logger.warning(f"Missing required fields: {missing_fields}")
                return False
            
            # Validate weight relationship if all weights are present
            if data['gross_weight'] and data['tare_weight'] and data['net_weight']:
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
        Main processing function to extract all weighbridge slip data
        
        Args:
            image_path: Path to the image file
            
        Returns:
            Dictionary containing all extracted fields
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
            logger.info(f"Extracted text: {extracted_text[:500]}...")  # Log first 500 chars
            
            # Parse all weighbridge data
            data = self.parse_enhanced_weighbridge_data(extracted_text)
            
            # Validate data
            is_valid = self.validate_enhanced_data(data)
            data['validation_passed'] = is_valid
            data['extracted_text'] = extracted_text  # Include for debugging
            
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
        
        Args:
            image_bytes: Image data as bytes
            
        Returns:
            Dictionary containing all extracted fields
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
            logger.info(f"Extracted text: {extracted_text[:500]}...")  # Log first 500 chars
            
            # Parse all weighbridge data
            data = self.parse_enhanced_weighbridge_data(extracted_text)
            
            # Validate data
            is_valid = self.validate_enhanced_data(data)
            data['validation_passed'] = is_valid
            data['extracted_text'] = extracted_text  # Include for debugging
            
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