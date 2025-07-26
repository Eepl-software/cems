#!/usr/bin/env python3

import os
import sys
import cv2
import numpy as np
from pathlib import Path
import json
import time
from advanced_ocr_processor import AdvancedWeighbridgeOCR
from enhanced_ocr_processor import EnhancedWeighbridgeOCR
from improved_ocr_processor import ImprovedWeighbridgeOCR

def test_ocr_processors():
    """
    Test all OCR processors with available sample images
    """
    print("=== OCR Processor Comparison Test ===\n")
    
    # Initialize processors
    processors = {
        'Advanced OCR': AdvancedWeighbridgeOCR(),
        'Enhanced OCR': EnhancedWeighbridgeOCR(),
        'Improved OCR': ImprovedWeighbridgeOCR()
    }
    
    # Find sample images
    sample_images = []
    image_extensions = ['.jpg', '.jpeg', '.png', '.bmp', '.tiff']
    
    # Look for sample images in ml directory
    ml_dir = Path(__file__).parent
    for ext in image_extensions:
        sample_images.extend(list(ml_dir.glob(f'*{ext}')))
    
    if not sample_images:
        print("No sample images found in ml directory.")
        print("Please add some weighbridge slip images to test the OCR processors.")
        return
    
    print(f"Found {len(sample_images)} sample images:")
    for img in sample_images:
        print(f"  - {img.name}")
    print()
    
    # Test each processor with each image
    results = {}
    
    for img_path in sample_images:
        print(f"Testing image: {img_path.name}")
        print("-" * 50)
        
        results[img_path.name] = {}
        
        for processor_name, processor in processors.items():
            print(f"\nTesting {processor_name}...")
            
            try:
                start_time = time.time()
                result = processor.process_image(str(img_path))
                processing_time = time.time() - start_time
                
                # Extract key metrics
                metrics = {
                    'processing_time': processing_time,
                    'validation_passed': result.get('validation_passed', False),
                    'confidence_score': result.get('confidence_score', 0),
                    'extracted_fields': {
                        'weighment_slip_no': result.get('weighment_slip_no'),
                        'vehicle_number': result.get('vehicle_number'),
                        'gross_weight': result.get('gross_weight'),
                        'tare_weight': result.get('tare_weight'),
                        'net_weight': result.get('net_weight'),
                        'material_name': result.get('material_name'),
                        'driver_name': result.get('driver_name'),
                        'transporter': result.get('transporter')
                    },
                    'errors': result.get('validation_errors', []),
                    'warnings': result.get('validation_warnings', [])
                }
                
                results[img_path.name][processor_name] = metrics
                
                # Print summary
                print(f"  ✓ Processed in {processing_time:.2f}s")
                print(f"  ✓ Validation: {'PASSED' if metrics['validation_passed'] else 'FAILED'}")
                print(f"  ✓ Confidence: {metrics['confidence_score']:.1f}%")
                
                # Show extracted fields
                extracted_count = sum(1 for v in metrics['extracted_fields'].values() if v)
                print(f"  ✓ Extracted fields: {extracted_count}/8")
                
                if metrics['errors']:
                    print(f"  ⚠ Errors: {len(metrics['errors'])}")
                if metrics['warnings']:
                    print(f"  ⚠ Warnings: {len(metrics['warnings'])}")
                
            except Exception as e:
                print(f"  ✗ Error: {str(e)}")
                results[img_path.name][processor_name] = {
                    'error': str(e),
                    'processing_time': 0,
                    'validation_passed': False,
                    'confidence_score': 0
                }
        
        print("\n" + "="*60 + "\n")
    
    # Generate comparison report
    generate_comparison_report(results)

def generate_comparison_report(results):
    """
    Generate a detailed comparison report
    """
    print("=== COMPARISON REPORT ===\n")
    
    # Overall statistics
    processor_stats = {
        'Advanced OCR': {'total_time': 0, 'success_count': 0, 'avg_confidence': 0, 'total_fields': 0},
        'Enhanced OCR': {'total_time': 0, 'success_count': 0, 'avg_confidence': 0, 'total_fields': 0},
        'Improved OCR': {'total_time': 0, 'success_count': 0, 'avg_confidence': 0, 'total_fields': 0}
    }
    
    total_images = len(results)
    
    # Calculate statistics
    for img_name, img_results in results.items():
        for processor_name, metrics in img_results.items():
            if 'error' not in metrics:
                stats = processor_stats[processor_name]
                stats['total_time'] += metrics['processing_time']
                stats['success_count'] += 1 if metrics['validation_passed'] else 0
                stats['avg_confidence'] += metrics['confidence_score']
                stats['total_fields'] += sum(1 for v in metrics['extracted_fields'].values() if v)
    
    # Print statistics
    print("Performance Summary:")
    print("-" * 50)
    
    for processor_name, stats in processor_stats.items():
        avg_time = stats['total_time'] / total_images if total_images > 0 else 0
        success_rate = (stats['success_count'] / total_images) * 100 if total_images > 0 else 0
        avg_confidence = stats['avg_confidence'] / total_images if total_images > 0 else 0
        avg_fields = stats['total_fields'] / total_images if total_images > 0 else 0
        
        print(f"\n{processor_name}:")
        print(f"  Average Processing Time: {avg_time:.2f}s")
        print(f"  Success Rate: {success_rate:.1f}%")
        print(f"  Average Confidence: {avg_confidence:.1f}%")
        print(f"  Average Fields Extracted: {avg_fields:.1f}/8")
    
    # Field extraction comparison
    print("\n\nField Extraction Comparison:")
    print("-" * 50)
    
    field_names = ['weighment_slip_no', 'vehicle_number', 'gross_weight', 'tare_weight', 
                   'net_weight', 'material_name', 'driver_name', 'transporter']
    
    for field in field_names:
        print(f"\n{field.replace('_', ' ').title()}:")
        
        for processor_name in processor_stats.keys():
            success_count = 0
            total_count = 0
            
            for img_results in results.values():
                if processor_name in img_results and 'error' not in img_results[processor_name]:
                    total_count += 1
                    if img_results[processor_name]['extracted_fields'][field]:
                        success_count += 1
            
            success_rate = (success_count / total_count) * 100 if total_count > 0 else 0
            print(f"  {processor_name}: {success_rate:.1f}% ({success_count}/{total_count})")
    
    # Save detailed results to file
    output_file = Path(__file__).parent / 'ocr_comparison_results.json'
    with open(output_file, 'w') as f:
        json.dump(results, f, indent=2)
    
    print(f"\nDetailed results saved to: {output_file}")

def create_synthetic_low_quality_test():
    """
    Create synthetic low-quality images for testing
    """
    print("=== Creating Synthetic Low-Quality Test Images ===\n")
    
    # Sample weighbridge slip text
    sample_text = """
    WEIGHMENT SLIP: WB001R202507151234567-1
    
    VEHICLE NUMBER: TN914235
    DRIVER NAME: RAJA KUMAR
    TRANSPORTER: LOGISTICS SOLUTIONS
    
    MATERIAL NAME: ORDINARY PORTLAND CEMENT
    MATERIAL CATEGORY: Grey Cement
    
    GROSS WEIGHT: 25420 KG
    TARE WEIGHT: 8350 KG
    NET WEIGHT: 17070 KG
    
    DATE: 15-07-2025
    TIME: 11:16:03
    """
    
    # Create base image
    img = np.ones((800, 600, 3), dtype=np.uint8) * 255
    
    # Add text to image
    font = cv2.FONT_HERSHEY_SIMPLEX
    font_scale = 0.6
    color = (0, 0, 0)
    thickness = 1
    
    y_offset = 50
    for line in sample_text.strip().split('\n'):
        if line.strip():
            cv2.putText(img, line.strip(), (50, y_offset), font, font_scale, color, thickness)
            y_offset += 30
    
    # Create different quality versions
    quality_versions = {
        'original': img.copy(),
        'blurred': cv2.GaussianBlur(img, (5, 5), 0),
        'noisy': img.copy(),
        'low_contrast': img.copy(),
        'rotated': img.copy(),
        'compressed': img.copy()
    }
    
    # Add noise
    noise = np.random.normal(0, 25, img.shape).astype(np.uint8)
    quality_versions['noisy'] = cv2.add(img, noise)
    
    # Reduce contrast
    quality_versions['low_contrast'] = cv2.convertScaleAbs(img, alpha=0.5, beta=50)
    
    # Rotate slightly
    rows, cols = img.shape[:2]
    rotation_matrix = cv2.getRotationMatrix2D((cols/2, rows/2), 2, 1)
    quality_versions['rotated'] = cv2.warpAffine(img, rotation_matrix, (cols, rows))
    
    # Save test images
    output_dir = Path(__file__).parent / 'synthetic_test_images'
    output_dir.mkdir(exist_ok=True)
    
    for quality_type, test_img in quality_versions.items():
        output_path = output_dir / f'synthetic_{quality_type}.png'
        cv2.imwrite(str(output_path), test_img)
        print(f"Created: {output_path}")
    
    print(f"\nSynthetic test images created in: {output_dir}")
    return output_dir

def main():
    """
    Main test function
    """
    print("Advanced OCR Processor Testing Suite")
    print("=" * 50)
    
    # Check if we have sample images
    ml_dir = Path(__file__).parent
    sample_images = list(ml_dir.glob('*.jpg')) + list(ml_dir.glob('*.png'))
    
    if not sample_images:
        print("No sample images found. Creating synthetic test images...")
        create_synthetic_low_quality_test()
        print("\nNow testing with synthetic images...")
    
    # Run OCR processor tests
    test_ocr_processors()
    
    print("\n=== Test Complete ===")
    print("Check the generated comparison report for detailed results.")

if __name__ == "__main__":
    main()