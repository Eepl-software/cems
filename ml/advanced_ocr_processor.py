import cv2
import pytesseract
import numpy as np
import re
from PIL import Image, ImageEnhance, ImageFilter
from typing import Dict, Optional, Tuple, List
import logging
from skimage import restoration, filters, morphology, segmentation
import json
import concurrent.futures
from dataclasses import dataclass

# Set up logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

@dataclass
class OCRResult:
    """Data class for OCR results with confidence scores"""
    text: str
    confidence: float
    method: str
    bbox: Optional[Tuple[int, int, int, int]] = None

class AdvancedWeighbridgeOCR:
    """
    Advanced OCR processor with sophisticated techniques for low-quality images
    Features:
    - Multi-scale processing
    - Advanced image preprocessing
    - Ensemble OCR approach
    - Confidence scoring
    - Noise reduction techniques
    """
    
    def __init__(self):
        # EasyOCR not available in this version
        self.use_easyocr = False
        
        # Tesseract configurations for different scenarios
        self.tesseract_configs = {
            'default': r'--oem 3 --psm 6',
            'single_column': r'--oem 3 --psm 4',
            'single_block': r'--oem 3 --psm 8',
            'single_word': r'--oem 3 --psm 7',
            'single_char': r'--oem 3 --psm 10',
            'sparse': r'--oem 3 --psm 11',
            'raw_line': r'--oem 3 --psm 13'
        }
        
    def advanced_preprocess_image(self, image: np.ndarray) -> List[np.ndarray]:
        """
        Advanced preprocessing with multiple enhancement techniques
        Returns multiple processed versions for ensemble processing
        """
        processed_images = []
        
        # Convert to grayscale if needed
        if len(image.shape) == 3:
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        else:
            gray = image.copy()
        
        # 1. Basic enhancement
        processed_images.append(self._basic_enhancement(gray))
        
        # 2. Noise reduction enhancement
        processed_images.append(self._noise_reduction_enhancement(gray))
        
        # 3. Contrast enhancement
        processed_images.append(self._contrast_enhancement(gray))
        
        # 4. Morphological enhancement
        processed_images.append(self._morphological_enhancement(gray))
        
        # 5. Frequency domain enhancement
        processed_images.append(self._frequency_domain_enhancement(gray))
        
        # 6. Multi-scale enhancement
        processed_images.extend(self._multi_scale_enhancement(gray))
        
        return processed_images
    
    def _basic_enhancement(self, image: np.ndarray) -> np.ndarray:
        """Basic preprocessing with standard techniques"""
        # Gaussian blur for noise reduction
        blurred = cv2.GaussianBlur(image, (3, 3), 0)
        
        # Adaptive thresholding
        thresh = cv2.adaptiveThreshold(
            blurred, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 11, 2
        )
        
        # Morphological operations
        kernel = np.ones((2, 2), np.uint8)
        cleaned = cv2.morphologyEx(thresh, cv2.MORPH_CLOSE, kernel)
        
        # Resize if too small
        return self._resize_if_needed(cleaned, min_size=800)
    
    def _noise_reduction_enhancement(self, image: np.ndarray) -> np.ndarray:
        """Advanced noise reduction techniques"""
        # Non-local means denoising
        denoised = cv2.fastNlMeansDenoising(image, None, 10, 7, 21)
        
        # Bilateral filter for edge preservation
        bilateral = cv2.bilateralFilter(denoised, 9, 75, 75)
        
        # Median filter for salt-and-pepper noise
        median_filtered = cv2.medianBlur(bilateral, 5)
        
        # Adaptive thresholding
        thresh = cv2.adaptiveThreshold(
            median_filtered, 255, cv2.ADAPTIVE_THRESH_MEAN_C, cv2.THRESH_BINARY, 15, 8
        )
        
        return self._resize_if_needed(thresh, min_size=1000)
    
    def _contrast_enhancement(self, image: np.ndarray) -> np.ndarray:
        """Contrast and brightness enhancement"""
        # CLAHE (Contrast Limited Adaptive Histogram Equalization)
        clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
        enhanced = clahe.apply(image)
        
        # Gamma correction
        gamma = 1.2
        gamma_corrected = np.power(enhanced / 255.0, gamma) * 255.0
        gamma_corrected = gamma_corrected.astype(np.uint8)
        
        # Otsu's thresholding
        _, thresh = cv2.threshold(gamma_corrected, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        
        return self._resize_if_needed(thresh, min_size=900)
    
    def _morphological_enhancement(self, image: np.ndarray) -> np.ndarray:
        """Morphological operations for text enhancement"""
        # Gaussian blur
        blurred = cv2.GaussianBlur(image, (3, 3), 0)
        
        # Adaptive threshold
        thresh = cv2.adaptiveThreshold(
            blurred, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 11, 2
        )
        
        # Morphological operations to connect broken text
        kernel_horizontal = cv2.getStructuringElement(cv2.MORPH_RECT, (2, 1))
        kernel_vertical = cv2.getStructuringElement(cv2.MORPH_RECT, (1, 2))
        
        # Closing to connect broken characters
        closed_h = cv2.morphologyEx(thresh, cv2.MORPH_CLOSE, kernel_horizontal)
        closed_v = cv2.morphologyEx(closed_h, cv2.MORPH_CLOSE, kernel_vertical)
        
        # Opening to remove small noise
        kernel_noise = np.ones((2, 2), np.uint8)
        opened = cv2.morphologyEx(closed_v, cv2.MORPH_OPEN, kernel_noise)
        
        return self._resize_if_needed(opened, min_size=1200)
    
    def _frequency_domain_enhancement(self, image: np.ndarray) -> np.ndarray:
        """Frequency domain filtering for enhancement"""
        # Apply FFT
        f_transform = np.fft.fft2(image)
        f_shift = np.fft.fftshift(f_transform)
        
        # Create high-pass filter
        rows, cols = image.shape
        crow, ccol = rows // 2, cols // 2
        
        # Create mask for high-pass filter
        mask = np.ones((rows, cols), np.uint8)
        r = 30
        center = [crow, ccol]
        x, y = np.ogrid[:rows, :cols]
        mask_area = (x - center[0]) ** 2 + (y - center[1]) ** 2 <= r * r
        mask[mask_area] = 0
        
        # Apply mask
        f_shift_filtered = f_shift * mask
        
        # Inverse FFT
        f_ishift = np.fft.ifftshift(f_shift_filtered)
        img_filtered = np.fft.ifft2(f_ishift)
        img_filtered = np.real(img_filtered)
        
        # Normalize
        img_filtered = np.uint8(np.clip(img_filtered, 0, 255))
        
        # Threshold
        _, thresh = cv2.threshold(img_filtered, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
        
        return self._resize_if_needed(thresh, min_size=1100)
    
    def _multi_scale_enhancement(self, image: np.ndarray) -> List[np.ndarray]:
        """Multi-scale processing for different text sizes"""
        scales = [0.8, 1.0, 1.2, 1.5, 2.0]
        processed_images = []
        
        for scale in scales:
            # Resize image
            height, width = image.shape
            new_height, new_width = int(height * scale), int(width * scale)
            resized = cv2.resize(image, (new_width, new_height), interpolation=cv2.INTER_CUBIC)
            
            # Apply basic preprocessing
            blurred = cv2.GaussianBlur(resized, (3, 3), 0)
            thresh = cv2.adaptiveThreshold(
                blurred, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 11, 2
            )
            
            # Ensure minimum size
            processed = self._resize_if_needed(thresh, min_size=800)
            processed_images.append(processed)
        
        return processed_images
    
    def _resize_if_needed(self, image: np.ndarray, min_size: int = 800) -> np.ndarray:
        """Resize image if too small for OCR"""
        height, width = image.shape
        if height < min_size or width < min_size:
            scale_factor = max(min_size / height, min_size / width)
            new_width = int(width * scale_factor)
            new_height = int(height * scale_factor)
            return cv2.resize(image, (new_width, new_height), interpolation=cv2.INTER_CUBIC)
        return image
    
    def extract_text_ensemble(self, processed_images: List[np.ndarray]) -> List[OCRResult]:
        """
        Extract text using ensemble of OCR engines and configurations
        """
        results = []
        
        # Use ThreadPoolExecutor for parallel processing
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
            futures = []
            
            # Submit Tesseract tasks
            for i, image in enumerate(processed_images):
                for config_name, config in self.tesseract_configs.items():
                    future = executor.submit(self._tesseract_ocr, image, config, f"tesseract_{config_name}_{i}")
                    futures.append(future)
            
            # EasyOCR not available in this version
            # if self.use_easyocr:
            #     for i, image in enumerate(processed_images[:3]):  # Limit EasyOCR to first 3 images
            #         future = executor.submit(self._easyocr_ocr, image, f"easyocr_{i}")
            #         futures.append(future)
            
            # Collect results
            for future in concurrent.futures.as_completed(futures):
                try:
                    result = future.result()
                    if result and result.text.strip():
                        results.append(result)
                except Exception as e:
                    logger.warning(f"OCR task failed: {e}")
        
        return results
    
    def _tesseract_ocr(self, image: np.ndarray, config: str, method: str) -> OCRResult:
        """Tesseract OCR with confidence scoring"""
        try:
            pil_image = Image.fromarray(image)
            
            # Get text and confidence data
            data = pytesseract.image_to_data(pil_image, config=config, output_type=pytesseract.Output.DICT)
            
            # Calculate average confidence
            confidences = [int(conf) for conf in data['conf'] if int(conf) > 0]
            avg_confidence = sum(confidences) / len(confidences) if confidences else 0
            
            # Extract text
            text = pytesseract.image_to_string(pil_image, config=config)
            
            return OCRResult(
                text=text,
                confidence=avg_confidence,
                method=method
            )
        except Exception as e:
            logger.warning(f"Tesseract OCR failed: {e}")
            return OCRResult(text="", confidence=0, method=method)
    
    def _easyocr_ocr(self, image: np.ndarray, method: str) -> OCRResult:
        """EasyOCR with confidence scoring"""
        try:
            results = self.easyocr_reader.readtext(image)
            
            # Combine results
            text_parts = []
            confidences = []
            
            for (bbox, text, conf) in results:
                text_parts.append(text)
                confidences.append(conf)
            
            combined_text = ' '.join(text_parts)
            avg_confidence = sum(confidences) / len(confidences) if confidences else 0
            
            return OCRResult(
                text=combined_text,
                confidence=avg_confidence * 100,  # Convert to percentage
                method=method
            )
        except Exception as e:
            logger.warning(f"EasyOCR failed: {e}")
            return OCRResult(text="", confidence=0, method=method)
    
    def select_best_ocr_result(self, results: List[OCRResult]) -> str:
        """
        Select the best OCR result based on confidence and content quality
        """
        if not results:
            return ""
        
        # Filter results with reasonable confidence
        filtered_results = [r for r in results if r.confidence > 30]
        
        if not filtered_results:
            # If no high-confidence results, use the one with highest confidence
            filtered_results = [max(results, key=lambda x: x.confidence)]
        
        # Score results based on multiple factors
        scored_results = []
        for result in filtered_results:
            score = self._calculate_result_score(result)
            scored_results.append((result, score))
        
        # Sort by score and return best result
        scored_results.sort(key=lambda x: x[1], reverse=True)
        best_result = scored_results[0][0]
        
        logger.info(f"Selected OCR result from {best_result.method} with confidence {best_result.confidence:.2f}")
        return best_result.text
    
    def _calculate_result_score(self, result: OCRResult) -> float:
        """Calculate quality score for OCR result"""
        text = result.text
        confidence = result.confidence
        
        # Base score from confidence
        score = confidence
        
        # Bonus for containing expected keywords
        keywords = ['GROSS', 'TARE', 'NET', 'VEHICLE', 'WEIGHMENT', 'SLIP', 'MATERIAL']
        keyword_count = sum(1 for keyword in keywords if keyword in text.upper())
        score += keyword_count * 10
        
        # Bonus for containing numbers (weights, dates, etc.)
        number_count = len(re.findall(r'\d{3,}', text))
        score += number_count * 5
        
        # Penalty for too short text
        if len(text.strip()) < 50:
            score -= 20
        
        # Bonus for proper structure (lines, formatting)
        line_count = len(text.split('\n'))
        if line_count > 5:
            score += 10
        
        return score
    
    def parse_enhanced_weighbridge_data(self, text: str) -> Dict[str, Optional[str]]:
        """
        Enhanced parsing with multiple pattern matching strategies
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
        
        # Clean text
        text = text.replace('\n', ' ').replace('\r', ' ')
        text_upper = text.upper()
        
        # Enhanced regex patterns with fuzzy matching
        patterns = {
            'weighment_slip_no': [
                r'WEIGHMENT\s+SLIP[:\s]*([A-Z0-9\-]{8,})',
                r'WB\d{2,3}R\d{12,15}\-?\d*',
                r'SLIP[:\s]*([A-Z0-9\-]{8,})',
                r'([A-Z0-9]{2,3}\d{2,3}[A-Z0-9]\d{8,15})',
            ],
            'vehicle_number': [
                r'VEHICLE\s+(?:NO|NUMBER)[:\s]*([A-Z]{2}\d{2,3}[A-Z]?\d{3,4})',
                r'([A-Z]{2}\d{2,3}[A-Z]?\d{3,4})(?!\d)',
                r'([A-Z]{2}\s*\d{2,3}\s*[A-Z]?\s*\d{3,4})',
                r'VEH[:\s]*([A-Z]{2}\d{2,3}[A-Z]?\d{3,4})',
            ],
            'gross_weight': [
                r'GROSS[:\s]*(\d{4,6})\s*(?:KG|KGS)?',
                r'GROSS\s+WEIGHT[:\s]*(\d{4,6})',
                r'(\d{4,6})\s*(?:KG)?\s*\d{2}-\d{2}-\d{4}\s*\d{2}:\d{2}:\d{2}',
            ],
            'tare_weight': [
                r'TARE[:\s]*(\d{4,6})\s*(?:KG|KGS)?',
                r'TARE\s+WEIGHT[:\s]*(\d{4,6})',
                r'(\d{4,6})\s*(?:KG)?\s*\d{2}-\d{2}-\d{4}\s*\d{2}:\d{2}:\d{2}',
            ],
            'net_weight': [
                r'NET[:\s]*(\d{4,6})\s*(?:KG|KGS)?',
                r'NET\s+WEIGHT[:\s]*(\d{4,6})',
                r'NETT?[:\s]*(\d{4,6})',
            ],
            'material_name': [
                r'MATERIAL\s+NAME[:\s]*([A-Z\s]+(?:CEMENT|AGGREGATE|STONE))',
                r'ORDINARY\s+PORTLAND\s+CEMENT',
                r'STONE\s+AGGREGATE',
                r'([A-Z\s]+(?:CEMENT|AGGREGATE))',
            ],
            'driver_name': [
                r'DRIVER\s+NAME[:\s]*([A-Za-z\s]{3,25})',
                r'DRIVER[:\s]*([A-Za-z\s]{3,25})',
                r'NAME[:\s]*([A-Za-z\s]{3,25})',
            ],
            'transporter': [
                r'TRANSPORTER[:\s]*([A-Za-z\s]{3,30})',
                r'([A-Za-z\s]*(?:LOGISTICS|TRANSPORT|MINES)[A-Za-z\s]*)',
            ]
        }
        
        # Extract fields using enhanced patterns
        for field, pattern_list in patterns.items():
            for pattern in pattern_list:
                flags = re.IGNORECASE if field in ['driver_name', 'transporter'] else 0
                match = re.search(pattern, text_upper if not flags else text, flags)
                
                if match:
                    value = match.group(1) if match.lastindex else match.group(0)
                    
                    # Clean and validate the value
                    if field in ['driver_name', 'transporter']:
                        value = self._clean_name(value)
                    elif field in ['gross_weight', 'tare_weight', 'net_weight']:
                        value = f"{value} KG"
                    elif field == 'material_name':
                        value = value.strip()
                    
                    if self._validate_field(field, value):
                        result[field] = value
                        logger.info(f"Extracted {field}: {value}")
                        break
        
        # Set material category based on material name
        if result['material_name']:
            if 'CEMENT' in result['material_name']:
                result['material_category'] = 'Grey Cement'
            elif 'AGGREGATE' in result['material_name'] or 'STONE' in result['material_name']:
                result['material_category'] = 'Aggregate'
        
        return result
    
    def _clean_name(self, name: str) -> str:
        """Clean extracted names"""
        name = re.sub(r'\d+', '', name)
        name = re.sub(r'\s+', ' ', name).strip()
        return name
    
    def _validate_field(self, field: str, value: str) -> bool:
        """Validate extracted field values"""
        if not value or not value.strip():
            return False
        
        if field == 'vehicle_number':
            return len(value.replace(' ', '')) >= 8
        elif field in ['gross_weight', 'tare_weight', 'net_weight']:
            return bool(re.search(r'\d{4,6}', value))
        elif field == 'weighment_slip_no':
            return len(value) >= 8
        elif field in ['driver_name', 'transporter']:
            return len(value) >= 3 and value.upper() not in ['VEHICLE', 'NUMBER', 'WEIGHT']
        elif field == 'material_name':
            return len(value) >= 5
        
        return True
    
    def validate_comprehensive_data(self, data: Dict[str, Optional[str]]) -> Dict[str, any]:
        """
        Comprehensive validation with detailed feedback
        """
        validation_result = {
            'is_valid': True,
            'errors': [],
            'warnings': [],
            'confidence_score': 0
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
        field_count = sum(1 for v in data.values() if v and v != 'None')
        validation_result['confidence_score'] = (field_count / len(data)) * 100
        
        return validation_result
    
    def process_image(self, image_path: str) -> Dict[str, any]:
        """
        Main processing function with advanced techniques
        """
        try:
            # Load image
            image = cv2.imread(image_path)
            if image is None:
                raise ValueError(f"Could not load image from {image_path}")
            
            logger.info(f"Processing image: {image_path}")
            
            # Advanced preprocessing
            processed_images = self.advanced_preprocess_image(image)
            logger.info(f"Generated {len(processed_images)} processed variants")
            
            # Ensemble OCR
            ocr_results = self.extract_text_ensemble(processed_images)
            logger.info(f"Generated {len(ocr_results)} OCR results")
            
            # Select best result
            best_text = self.select_best_ocr_result(ocr_results)
            
            # Parse data
            extracted_data = self.parse_enhanced_weighbridge_data(best_text)
            
            # Comprehensive validation
            validation_result = self.validate_comprehensive_data(extracted_data)
            
            # Compile final result
            result = {
                **extracted_data,
                'validation_passed': validation_result['is_valid'],
                'confidence_score': validation_result['confidence_score'],
                'validation_errors': validation_result['errors'],
                'validation_warnings': validation_result['warnings'],
                'extracted_text': best_text[:1000],  # Truncate for storage
                'processing_metadata': {
                    'processed_variants': len(processed_images),
                    'ocr_results_count': len(ocr_results),
                    'best_ocr_method': next((r.method for r in ocr_results if r.text == best_text), 'unknown')
                }
            }
            
            logger.info(f"Processing completed with confidence: {validation_result['confidence_score']:.1f}%")
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
        Process image from bytes with advanced techniques
        """
        try:
            # Convert bytes to numpy array
            nparr = np.frombuffer(image_bytes, np.uint8)
            image = cv2.imdecode(nparr, cv2.IMREAD_COLOR)
            
            if image is None:
                raise ValueError("Could not decode image from bytes")
            
            logger.info("Processing image from bytes")
            
            # Advanced preprocessing
            processed_images = self.advanced_preprocess_image(image)
            logger.info(f"Generated {len(processed_images)} processed variants")
            
            # Ensemble OCR
            ocr_results = self.extract_text_ensemble(processed_images)
            logger.info(f"Generated {len(ocr_results)} OCR results")
            
            # Select best result
            best_text = self.select_best_ocr_result(ocr_results)
            
            # Parse data
            extracted_data = self.parse_enhanced_weighbridge_data(best_text)
            
            # Comprehensive validation
            validation_result = self.validate_comprehensive_data(extracted_data)
            
            # Compile final result
            result = {
                **extracted_data,
                'validation_passed': validation_result['is_valid'],
                'confidence_score': validation_result['confidence_score'],
                'validation_errors': validation_result['errors'],
                'validation_warnings': validation_result['warnings'],
                'extracted_text': best_text[:1000],  # Truncate for storage
                'processing_metadata': {
                    'processed_variants': len(processed_images),
                    'ocr_results_count': len(ocr_results),
                    'best_ocr_method': next((r.method for r in ocr_results if r.text == best_text), 'unknown')
                }
            }
            
            logger.info(f"Processing completed with confidence: {validation_result['confidence_score']:.1f}%")
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