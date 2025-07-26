import cv2
import pytesseract
import numpy as np
import re
from PIL import Image
from typing import Dict, Optional, List, Tuple
import logging

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class RealWeighbridgeOCR:
    """
    Real OCR processor for extracting weighbridge slip data from L&T Construction slips
    """
    
    def __init__(self):
        # Configure Tesseract for better OCR results
        self.tesseract_configs = [
            r'--oem 3 --psm 6',  # Standard config
            r'--oem 3 --psm 4',  # Single column of text
            r'--oem 3 --psm 3',  # Fully automatic page segmentation
            r'--oem 1 --psm 6',  # Legacy engine
        ]
        
    def preprocess_image(self, image: np.ndarray) -> List[np.ndarray]:
        """
        Preprocess image with multiple approaches for better OCR
        """
        processed_images = []
        
        # Convert to grayscale if needed
        if len(image.shape) == 3:
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        else:
            gray = image
            
        # Resize for better OCR if image is too small
        height, width = gray.shape
        if height < 1000 or width < 800:
            scale_factor = max(1000/height, 800/width)
            new_width = int(width * scale_factor)
            new_height = int(height * scale_factor)
            gray = cv2.resize(gray, (new_width, new_height), interpolation=cv2.INTER_CUBIC)
        
        # Original image
        processed_images.append(gray)
        
        # Enhanced contrast
        clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8,8))
        enhanced = clahe.apply(gray)
        processed_images.append(enhanced)
        
        # Threshold variations
        _, thresh1 = cv2.threshold(gray, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        processed_images.append(thresh1)
        
        # Adaptive threshold
        adaptive = cv2.adaptiveThreshold(gray, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 11, 2)
        processed_images.append(adaptive)
        
        return processed_images
    
    def extract_text_from_image(self, image: np.ndarray) -> str:
        """
        Extract text using multiple Tesseract configurations
        """
        best_text = ""
        best_confidence = 0
        
        for config in self.tesseract_configs:
            try:
                pil_image = Image.fromarray(image)
                
                # Get text with confidence
                data = pytesseract.image_to_data(pil_image, config=config, output_type=pytesseract.Output.DICT)
                confidences = [int(conf) for conf in data['conf'] if int(conf) > 0]
                avg_confidence = sum(confidences) / len(confidences) if confidences else 0
                
                # Extract text
                text = pytesseract.image_to_string(pil_image, config=config)
                
                if avg_confidence > best_confidence and text.strip():
                    best_confidence = avg_confidence
                    best_text = text
                    
            except Exception as e:
                logger.warning(f"OCR config failed: {e}")
                continue
        
        logger.info(f"Best OCR confidence: {best_confidence:.1f}%")
        return best_text
    
    def parse_weighbridge_data(self, text: str) -> Dict[str, Optional[str]]:
        """
        Parse L&T Construction weighbridge slip data from OCR text
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
        text = re.sub(r'\s+', ' ', text)  # Normalize whitespace
        text_upper = text.upper()
        
        logger.info(f"Parsing text snippet: {text[:200]}...")
        
        # Enhanced patterns for L&T Construction format
        patterns = {
            'weighment_slip_no': [
                r'WEIGHMENT\s+SLIP\s+([A-Z0-9\-]+)',
                r'WB\d+R\d+',
                r'([A-Z]{2}\d+[A-Z]\d+\-\d+)',
                r'SLIP\s*:?\s*([A-Z0-9\-]{10,})',
            ],
            'vehicle_number': [
                r'VEHICLE\s+NUMBER\s*:?\s*([A-Z]{2}\d{2,3}[A-Z]?\d{3,4})',
                r'VEHICLE\s*:?\s*([A-Z]{2}\d{2,3}[A-Z]?\d{3,4})',
                r'([A-Z]{2}\d{2,3}[A-Z]\d{3,4})',  # KA034K313 format
                r'\b([A-Z]{2}\d{2,3}[A-Z]?\d{3,4})\b',
            ],
            'driver_name': [
                r'DRIVER\s+NAME\s*:?\s*([A-Za-z\s]{3,25})',
                r'DRIVER\s*:?\s*([A-Za-z\s]{3,25})',
                r'NAME\s*:?\s*([A-Za-z\s]{3,25})',
            ],
            'transporter': [
                r'TRANSPORTER\s*:?\s*([A-Za-z\s]{3,30})',
                r'([A-Za-z\s]*(?:MINES|LOGISTICS|TRANSPORT)[A-Za-z\s]*)',
                r'FOYER\s+MINES',
            ],
            'material_name': [
                r'MATERIAL\s+NAME\s*:?\s*([A-Z\s,\-\.:]+(?:AGGREGATE|CEMENT|STONE))',
                r'STONE\s+AGGREGATE[A-Z\s,\-\.:]*',
                r'(STONE\s+AGGREGATE[^0-9]*)',
                r'([A-Z\s,\-\.:]*(AGGREGATE|CEMENT|STONE)[A-Z\s,\-\.:|]*)',
            ],
            'gross_weight': [
                r'GROSS\s*:?\s*(\d{4,6})\s*(?:KG|KGS)?',
                r'GROSS\s+(\d{4,6})',
                r'(\d{4,6})\s*(?:KG|KGS)?\s*\d{2}-\d{2}-\d{4}\s*\d{2}:\d{2}:\d{2}',
            ],
            'tare_weight': [
                r'TARE\s*:?\s*(\d{4,6})\s*(?:KG|KGS)?',
                r'TARE\s+(\d{4,6})',
                r'TARE\s*\d*\s*(\d{4,6})',
            ],
            'net_weight': [
                r'NET\s*:?\s*(\d{4,6})\s*(?:KG|KGS)?',
                r'NET\s+(\d{4,6})',
                r'NETT?\s*(\d{4,6})',
            ]
        }
        
        # Extract fields using patterns
        for field, pattern_list in patterns.items():
            for pattern in pattern_list:
                # Use case-insensitive search for names
                flags = re.IGNORECASE if field in ['driver_name', 'transporter', 'material_name'] else 0
                search_text = text if flags else text_upper
                
                match = re.search(pattern, search_text, flags)
                if match:
                    value = match.group(1) if match.lastindex else match.group(0)
                    
                    # Clean the extracted value
                    if field in ['driver_name', 'transporter']:
                        value = self._clean_name(value)
                    elif field in ['gross_weight', 'tare_weight', 'net_weight']:
                        value = f"{value} KG"
                    elif field == 'material_name':
                        value = value.strip().replace(':', '').strip()
                    elif field == 'vehicle_number':
                        value = value.replace(' ', '').upper()
                    
                    # Validate the value
                    if self._validate_field(field, value):
                        result[field] = value
                        logger.info(f"✅ Extracted {field}: {value}")
                        break
                    else:
                        logger.debug(f"❌ Invalid {field}: {value}")
        
        # Set material category based on material name
        if result['material_name']:
            if 'CEMENT' in result['material_name'].upper():
                result['material_category'] = 'Grey Cement'
            elif 'AGGREGATE' in result['material_name'].upper() or 'STONE' in result['material_name'].upper():
                result['material_category'] = 'Aggregate'
            elif 'SAND' in result['material_name'].upper():
                result['material_category'] = 'Sand'
            else:
                result['material_category'] = 'Other'
        
        return result
    
    def _clean_name(self, name: str) -> str:
        """Clean and format person/company names"""
        name = name.strip().title()
        # Remove common OCR artifacts
        name = re.sub(r'[^A-Za-z\s]', '', name)
        return ' '.join(name.split())  # Normalize whitespace
    
    def _validate_field(self, field: str, value: str) -> bool:
        """Validate extracted field values"""
        if not value or not value.strip():
            return False
        
        if field == 'vehicle_number':
            # Indian vehicle number format
            return bool(re.match(r'^[A-Z]{2}\d{2,3}[A-Z]?\d{3,4}$', value.replace(' ', '')))
        elif field in ['gross_weight', 'tare_weight', 'net_weight']:
            return bool(re.search(r'\d{4,6}', value))
        elif field == 'weighment_slip_no':
            return len(value) >= 8
        elif field in ['driver_name', 'transporter']:
            return len(value) >= 3 and not any(word in value.upper() for word in ['VEHICLE', 'NUMBER', 'WEIGHT', 'KG'])
        elif field == 'material_name':
            return len(value) >= 5
        
        return True
    
    def validate_weights(self, data: Dict[str, Optional[str]]) -> Dict[str, any]:
        """Validate weight relationships and calculate confidence"""
        validation_result = {
            'is_valid': True,
            'confidence_score': 0,
            'errors': [],
            'warnings': []
        }
        
        # Check weight relationship: GROSS = TARE + NET
        if all(data.get(f) for f in ['gross_weight', 'tare_weight', 'net_weight']):
            try:
                gross = float(re.search(r'(\d+)', data['gross_weight']).group(1))
                tare = float(re.search(r'(\d+)', data['tare_weight']).group(1))
                net = float(re.search(r'(\d+)', data['net_weight']).group(1))
                
                calculated_net = gross - tare
                tolerance = 0.10  # 10% tolerance
                
                if abs(calculated_net - net) / max(net, 1) > tolerance:
                    validation_result['warnings'].append(
                        f"Weight inconsistency: GROSS({gross}) - TARE({tare}) = {calculated_net} ≠ NET({net})"
                    )
                else:
                    validation_result['is_valid'] = True
                    
            except Exception as e:
                validation_result['warnings'].append("Could not validate weight relationships")
        
        # Calculate confidence score based on extracted fields
        total_fields = len(data)
        extracted_fields = sum(1 for v in data.values() if v)
        validation_result['confidence_score'] = (extracted_fields / total_fields) * 100
        
        return validation_result
    
    def process_image_from_bytes(self, image_bytes: bytes) -> Dict[str, any]:
        """
        Process image from bytes - main function called by FastAPI
        """
        try:
            # Convert bytes to numpy array
            nparr = np.frombuffer(image_bytes, np.uint8)
            image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            
            if image is None:
                raise ValueError("Could not decode image from bytes")
            
            logger.info(f"Processing image of size: {image.shape}")
            
            # Preprocess image with multiple approaches
            processed_images = self.preprocess_image(image)
            
            best_result = None
            best_confidence = 0
            
            # Try OCR on each preprocessed image
            for i, processed_img in enumerate(processed_images):
                logger.info(f"Trying OCR approach {i+1}/{len(processed_images)}")
                
                # Extract text
                extracted_text = self.extract_text_from_image(processed_img)
                
                if not extracted_text.strip():
                    continue
                
                # Parse data
                parsed_data = self.parse_weighbridge_data(extracted_text)
                
                # Validate
                validation_result = self.validate_weights(parsed_data)
                confidence = validation_result['confidence_score']
                
                logger.info(f"Approach {i+1} confidence: {confidence:.1f}%")
                
                if confidence > best_confidence:
                    best_confidence = confidence
                    best_result = {
                        **parsed_data,
                        'validation_passed': validation_result['is_valid'],
                        'confidence_score': confidence,
                        'validation_errors': validation_result['errors'],
                        'validation_warnings': validation_result['warnings'],
                        'extracted_text_preview': extracted_text[:200] + "..." if len(extracted_text) > 200 else extracted_text
                    }
            
            if best_result:
                logger.info(f"✅ Processing completed with confidence: {best_confidence:.1f}%")
                logger.info(f"Extracted fields: {sum(1 for v in best_result.values() if v and str(v) not in ['True', 'False'])}")
                return best_result
            else:
                # Return empty result if no data extracted
                return self._empty_result("No text could be extracted from the image")
                
        except Exception as e:
            logger.error(f"Error processing image: {str(e)}")
            return self._empty_result(str(e))
    
    def _empty_result(self, error_msg: str = None) -> Dict[str, any]:
        """Return empty result structure"""
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
            "error": error_msg
        }