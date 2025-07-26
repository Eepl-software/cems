#!/usr/bin/env python3
"""
Manual extraction test based on visual inspection of L&T weighbridge slips
This demonstrates the expected output format for integration
"""

def get_manual_extraction_results():
    """
    Manual extraction results based on visual inspection of the weighbridge slips
    This serves as the target format for the OCR system
    """
    
    # Results from PHOTO-2025-07-15-17-27-21.jpg (Stone Aggregate slip)
    slip1_data = {
        "material_name": "STONE AGGREGATE",
        "material_category": "Aggregate",
        "gross_weight": "44560 KG",
        "tare_weight": "12350 KG", 
        "net_weight": "32210 KG",
        "weighment_slip_no": "WB48R20250715153923-3",
        "vehicle_number": "KA034C313",
        "driver_name": "Sartmul",
        "transporter": "foyer mines",
        "validation_passed": True
    }
    
    # Results from PHOTO-2025-07-15-17-27-21 2.jpg (Cement slip)
    slip2_data = {
        "material_name": "ORDINARY PORTLAND CEMENT, GRADE : 53, FORM : Grey Cement",
        "material_category": "Grey Cement", 
        "gross_weight": "65570 KG",
        "tare_weight": "14500 KG",
        "net_weight": "51070 KG",  # 65570 - 14500 = 51070
        "weighment_slip_no": "WB48R20250715111655-3",
        "vehicle_number": "TN914235",
        "driver_name": "babrish",
        "transporter": "bam logistics",
        "validation_passed": True
    }
    
    return {
        "PHOTO-2025-07-15-17-27-21.jpg": slip1_data,
        "PHOTO-2025-07-15-17-27-21 2.jpg": slip2_data
    }

def validate_weight_calculation(data):
    """
    Validate that NET = GROSS - TARE
    """
    try:
        gross = int(data['gross_weight'].replace(' KG', ''))
        tare = int(data['tare_weight'].replace(' KG', ''))
        net = int(data['net_weight'].replace(' KG', ''))
        
        calculated_net = gross - tare
        
        print(f"  Weight validation: {gross} - {tare} = {calculated_net}")
        print(f"  Recorded NET: {net}")
        print(f"  Difference: {abs(calculated_net - net)}")
        
        return abs(calculated_net - net) <= 10  # Allow small tolerance
        
    except Exception as e:
        print(f"  Validation error: {e}")
        return False

def demonstrate_expected_output():
    """
    Demonstrate the expected output format for the enhanced OCR system
    """
    print("🎯 Manual Extraction Results (Target Format)")
    print("=" * 60)
    
    manual_results = get_manual_extraction_results()
    
    for filename, data in manual_results.items():
        print(f"\n📸 {filename}")
        print("-" * 50)
        
        print("📊 EXTRACTED DATA:")
        print(f"  Material Name:        {data['material_name']}")
        print(f"  Material Category:    {data['material_category']}")
        print(f"  Gross Weight:         {data['gross_weight']}")
        print(f"  Tare Weight:          {data['tare_weight']}")
        print(f"  Net Weight:           {data['net_weight']}")
        print(f"  Weighment Slip No:    {data['weighment_slip_no']}")
        print(f"  Vehicle Number:       {data['vehicle_number']}")
        print(f"  Driver Name:          {data['driver_name']}")
        print(f"  Transporter:          {data['transporter']}")
        print(f"  Validation Passed:    {'✅ Yes' if data['validation_passed'] else '❌ No'}")
        
        print("\n🧮 WEIGHT VALIDATION:")
        is_valid = validate_weight_calculation(data)
        print(f"  Calculation Valid:    {'✅ Yes' if is_valid else '❌ No'}")

def create_api_response_format():
    """
    Create the expected API response format for frontend integration
    """
    print("\n\n🔌 API Response Format for Frontend Integration")
    print("=" * 60)
    
    manual_results = get_manual_extraction_results()
    
    # API response for successful extraction
    api_response = {
        "success": True,
        "message": "Weighbridge slip data extracted successfully",
        "data": manual_results["PHOTO-2025-07-15-17-27-21 2.jpg"],  # Use cement slip as example
        "confidence": 95.5,
        "processing_time": 2.3
    }
    
    import json
    print("📤 Successful API Response:")
    print(json.dumps(api_response, indent=2))
    
    # API response for failed extraction
    api_error_response = {
        "success": False,
        "message": "Could not extract all required fields from weighbridge slip",
        "data": {
            "material_name": None,
            "material_category": None,
            "gross_weight": None,
            "tare_weight": None,
            "net_weight": None,
            "weighment_slip_no": None,
            "vehicle_number": None,
            "driver_name": None,
            "transporter": None,
            "validation_passed": False
        },
        "error": "OCR extraction failed",
        "confidence": 0.0,
        "processing_time": 1.8
    }
    
    print("\n📤 Error API Response:")
    print(json.dumps(api_error_response, indent=2))

if __name__ == "__main__":
    print("🚀 Manual Extraction Test - Target Format")
    print("Based on visual inspection of L&T weighbridge slips")
    print("=" * 60)
    
    demonstrate_expected_output()
    create_api_response_format()
    
    print("\n✨ This demonstrates the target output format!")
    print("The OCR system should extract all these fields:")
    print("  • Material name (with grade and form details)")
    print("  • Material category classification")
    print("  • Complete weight information (Gross, Tare, Net)")
    print("  • Weighment slip identification number")
    print("  • Vehicle registration number")
    print("  • Driver name information")
    print("  • Transporter/logistics company name")
    print("  • Data validation and integrity checks")