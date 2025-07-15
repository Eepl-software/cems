import cv2
import pytesseract
import numpy as np
import re
from PIL import Image
from typing import Dict, Optional, Tuple
import logging

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class WeighbridgeOCR:
    """
    OCR processor for extracting weighbridge slip data
    """
    
    def __init__(self):
        # Configure Tesseract for better OCR results
        self.tesseract_config = r'--oem 3 --psm 6'
        
    def preprocess_image(self, image: np.ndarray) -> np.ndarray:
        """
        Preprocess image for better OCR results
        
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
        blurred = cv2.GaussianBlur(gray, (5, 5), 0)
        
        # Apply adaptive thresholding
        thresh = cv2.adaptiveThreshold(
            blurred, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 11, 2
        )
        
        # Morphological operations to clean up the image
        kernel = np.ones((2, 2), np.uint8)
        cleaned = cv2.morphologyEx(thresh, cv2.MORPH_CLOSE, kernel)
        
        # Resize image if too small (improves OCR accuracy)
        height, width = cleaned.shape
        if height < 600 or width < 600:
            scale_factor = max(600 / height, 600 / width)
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
            
            # Extract text using Tesseract
            text = pytesseract.image_to_string(pil_image, config=self.tesseract_config)
            
            return text
        except Exception as e:
            logger.error(f"Error extracting text: {str(e)}")
            return ""
    
    def parse_weights(self, text: str) -> Dict[str, Optional[str]]:
        """
        Parse extracted text to find GROSS, TARE, NET weights and vehicle number
        
        Args:
            text: Extracted text from OCR
            
        Returns:
            Dictionary containing extracted weights and vehicle information
        """
        # Initialize result dictionary
        result = {
            "gross_weight": None,
            "tare_weight": None,
            "net_weight": None,
            "vehicle_number": None
        }
        
        # Clean and normalize text
        text = text.upper().replace('\n', ' ').replace('\r', ' ')
        
        # Define patterns for different weight formats and vehicle numbers
        patterns = {
            'gross_weight': [
                r'GROSS\s*:?\s*(\d+(?:,\d+)*\.?\d*)\s*(KG|KGS|TONNES?|T)?',
                r'GROSS\s+WEIGHT\s*:?\s*(\d+(?:,\d+)*\.?\d*)\s*(KG|KGS|TONNES?|T)?'
            ],
            'tare_weight': [
                r'TARE\s*:?\s*(\d+(?:,\d+)*\.?\d*)\s*(KG|KGS|TONNES?|T)?',
                r'TARE\s+WEIGHT\s*:?\s*(\d+(?:,\d+)*\.?\d*)\s*(KG|KGS|TONNES?|T)?'
            ],
            'net_weight': [
                r'NET\s*:?\s*(\d+(?:,\d+)*\.?\d*)\s*(KG|KGS|TONNES?|T)?',
                r'NET\s+WEIGHT\s*:?\s*(\d+(?:,\d+)*\.?\d*)\s*(KG|KGS|TONNES?|T)?',
                r'NETT\s*:?\s*(\d+(?:,\d+)*\.?\d*)\s*(KG|KGS|TONNES?|T)?'
            ]
        }
        
        # Vehicle number patterns (Indian format and variations)
        vehicle_patterns = [
            # With labels
            r'VEHICLE\s*(?:NO|NUMBER|NUM)?\s*:?\s*([A-Z]{2}\s*\d{1,2}\s*[A-Z]{1,2}\s*\d{1,4})',
            r'VEH\s*(?:NO|NUMBER|NUM)?\s*:?\s*([A-Z]{2}\s*\d{1,2}\s*[A-Z]{1,2}\s*\d{1,4})',
            r'TRUCK\s*(?:NO|NUMBER|NUM)?\s*:?\s*([A-Z]{2}\s*\d{1,2}\s*[A-Z]{1,2}\s*\d{1,4})',
            r'REG\s*(?:NO|NUMBER|NUM)?\s*:?\s*([A-Z]{2}\s*\d{1,2}\s*[A-Z]{1,2}\s*\d{1,4})',
            r'REGISTRATION\s*(?:NO|NUMBER|NUM)?\s*:?\s*([A-Z]{2}\s*\d{1,2}\s*[A-Z]{1,2}\s*\d{1,4})',
            # Direct patterns (most common)
            r'\b([A-Z]{2}\s*\d{1,2}\s*[A-Z]{1,2}\s*\d{3,4})\b',  # With spaces
            r'\b([A-Z]{2}\d{1,2}[A-Z]{1,2}\d{3,4})\b',  # Without spaces
            # More flexible patterns
            r'([A-Z]{2}\s*\d{1,2}\s*[A-Z]{1,3}\s*\d{1,4})',  # Flexible letter count
            # Fallback patterns for poorly scanned text
            r'([A-Z0-9]{2}\s*\d{1,2}\s*[A-Z0-9]{1,2}\s*\d{3,4})',  # With potential OCR errors
        ]
        
        # Extract weights using regex patterns
        for weight_type, pattern_list in patterns.items():
            for pattern in pattern_list:
                match = re.search(pattern, text)
                if match:
                    weight_value = match.group(1).replace(',', '')
                    unit = match.group(2) if match.group(2) else 'Kg'
                    result[weight_type] = f"{weight_value} {unit}"
                    break
        
        # Extract vehicle number
        logger.info(f"Searching for vehicle number in text: {text[:200]}...")  # Log first 200 chars
        
        for i, pattern in enumerate(vehicle_patterns):
            match = re.search(pattern, text)
            if match:
                vehicle_num = match.group(1).replace(' ', '')  # Remove spaces
                # Clean up common OCR errors
                vehicle_num = vehicle_num.replace('O', '0').replace('I', '1')
                result['vehicle_number'] = vehicle_num
                logger.info(f"Vehicle number extracted with pattern {i}: {vehicle_num}")
                break
        
        if not result['vehicle_number']:
            logger.warning("No vehicle number found in OCR text")
        
        return result
    
    def validate_weights(self, weights: Dict[str, Optional[str]]) -> bool:
        """
        Validate extracted weights for logical consistency
        
        Args:
            weights: Dictionary of extracted weights
            
        Returns:
            Boolean indicating if weights are valid
        """
        try:
            # Extract numeric values
            gross_num = None
            tare_num = None
            net_num = None
            
            if weights['gross_weight']:
                gross_num = float(re.search(r'(\d+(?:\.\d+)?)', weights['gross_weight']).group(1))
            if weights['tare_weight']:
                tare_num = float(re.search(r'(\d+(?:\.\d+)?)', weights['tare_weight']).group(1))
            if weights['net_weight']:
                net_num = float(re.search(r'(\d+(?:\.\d+)?)', weights['net_weight']).group(1))
            
            # Validate relationship: GROSS = TARE + NET (with some tolerance)
            if all([gross_num, tare_num, net_num]):
                calculated_net = gross_num - tare_num
                tolerance = 0.1  # 10% tolerance
                if abs(calculated_net - net_num) / net_num > tolerance:
                    logger.warning(f"Weight validation failed: GROSS({gross_num}) - TARE({tare_num}) != NET({net_num})")
                    return False
            
            return True
            
        except Exception as e:
            logger.error(f"Error validating weights: {str(e)}")
            return False
    
    def process_image(self, image_path: str) -> Dict[str, Optional[str]]:
        """
        Main processing function to extract weights from weighbridge slip image
        
        Args:
            image_path: Path to the image file
            
        Returns:
            Dictionary containing extracted weights
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
            logger.info(f"Extracted text: {extracted_text}")
            
            # Parse weights
            weights = self.parse_weights(extracted_text)
            
            # Validate weights
            is_valid = self.validate_weights(weights)
            weights['validation_passed'] = is_valid
            
            return weights
            
        except Exception as e:
            logger.error(f"Error processing image: {str(e)}")
            return {
                "gross_weight": None,
                "tare_weight": None,
                "net_weight": None,
                "vehicle_number": None,
                "validation_passed": False,
                "error": str(e)
            }
    
    def process_image_from_bytes(self, image_bytes: bytes) -> Dict[str, Optional[str]]:
        """
        Process image from bytes (for API uploads)
        
        Args:
            image_bytes: Image data as bytes
            
        Returns:
            Dictionary containing extracted weights
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
            logger.info(f"Extracted text: {extracted_text}")
            
            # Parse weights
            weights = self.parse_weights(extracted_text)
            
            # Validate weights
            is_valid = self.validate_weights(weights)
            weights['validation_passed'] = is_valid
            
            return weights
            
        except Exception as e:
            logger.error(f"Error processing image from bytes: {str(e)}")
            return {
                "gross_weight": None,
                "tare_weight": None,
                "net_weight": None,
                "vehicle_number": None,
                "validation_passed": False,
                "error": str(e)
            }