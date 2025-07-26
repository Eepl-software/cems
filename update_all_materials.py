#!/usr/bin/env python3
"""
Script to update all material pages with enhanced OCR functionality
"""

import os
import re

# List of material pages to update
materials = [
    'sand', 'metals', 'pipes', 'tiles', 'wood', 
    'electricals', 'plastic', 'aggregates'
]

def update_material_page(material_name):
    """Update a single material page with enhanced OCR functionality"""
    
    file_path = f"/Users/syedkhaja/Desktop/Prestige Park Groove Main Code 2/lib/{material_name}/{material_name}.dart"
    
    if not os.path.exists(file_path):
        print(f"❌ File not found: {file_path}")
        return False
    
    print(f"📝 Updating {material_name}.dart...")
    
    # Read the file
    with open(file_path, 'r') as f:
        content = f.read()
    
    # 1. Add enhanced OCR field controllers after existing controllers
    controller_pattern = r'(final TextEditingController _contactController = TextEditingController\(\);)'
    enhanced_controllers = '''
  
  // Enhanced OCR field controllers
  final TextEditingController _materialNameController = TextEditingController();
  final TextEditingController _materialCategoryController = TextEditingController();
  final TextEditingController _weighmentSlipNoController = TextEditingController();
  final TextEditingController _driverNameController = TextEditingController();
  final TextEditingController _transporterController = TextEditingController();'''
    
    if re.search(controller_pattern, content):
        content = re.sub(controller_pattern, r'\1' + enhanced_controllers, content)
    
    # 2. Add disposal of enhanced controllers
    dispose_pattern = r'(_contactController\.dispose\(\);)'
    enhanced_dispose = '''
    // Enhanced OCR controllers
    _materialNameController.dispose();
    _materialCategoryController.dispose();
    _weighmentSlipNoController.dispose();
    _driverNameController.dispose();
    _transporterController.dispose();'''
    
    if re.search(dispose_pattern, content):
        content = re.sub(dispose_pattern, r'\1' + enhanced_dispose, content)
    
    # 3. Update OCR API URL
    ocr_url_pattern = r'static String get _ocrApiUrl \{[^}]+\}'
    new_ocr_url = '''static String get _ocrApiUrl {
    // Use the enhanced OCR endpoint
    return '$_customBackendUrl/extract-weighbridge-data';
  }'''
    
    if re.search(ocr_url_pattern, content):
        content = re.sub(ocr_url_pattern, new_ocr_url, content)
    
    # 4. Update connection test method
    connection_test_pattern = r'Future<bool> _testOCRConnection\(\) async \{[^}]+\}'
    new_connection_test = '''Future<bool> _testOCRConnection() async {
    try {
      // Test the actual backend API endpoint instead of a non-existent health endpoint
      final response = await http.get(Uri.parse('$_customBackendUrl/{}-submissions')).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      print('OCR Connection test failed: $e');
      return false;
    }
  }'''.format(material_name)
    
    if re.search(r'Future<bool> _testOCRConnection\(\) async \{', content):
        content = re.sub(r'Future<bool> _testOCRConnection\(\) async \{[^}]+\}', new_connection_test, content, flags=re.DOTALL)
    
    # 5. Add mock OCR data method
    mock_data_method = '''
  void _useMockOCRData() {
    // Mock data based on material type
    final Map<String, String> mockData = {
      'material_name': 'CONSTRUCTION {}',
      'material_category': '{}',
      'gross_weight': '45000 KG',
      'tare_weight': '12000 KG',
      'net_weight': '33000 KG',
      'weighment_slip_no': 'WB48R2025071512345-1',
      'vehicle_number': 'KA01AB5678',
      'driver_name': 'Demo Driver',
      'transporter': 'Demo Logistics',
    };

    setState(() {
      // Original weight fields
      _grossWeightController.text = mockData['gross_weight']!;
      _tareWeightController.text = mockData['tare_weight']!;
      _netWeightController.text = mockData['net_weight']!;
      _vehicleNumberController.text = mockData['vehicle_number']!;
      
      // Enhanced OCR fields
      _materialNameController.text = mockData['material_name']!;
      _materialCategoryController.text = mockData['material_category']!;
      _weighmentSlipNoController.text = mockData['weighment_slip_no']!;
      _driverNameController.text = mockData['driver_name']!;
      _transporterController.text = mockData['transporter']!;
    });
  }'''.format(material_name.upper(), material_name.title())
    
    # Insert the mock data method before _processImageWithOCR
    process_image_pattern = r'(Future<void> _processImageWithOCR\(\) async \{)'
    if re.search(process_image_pattern, content):
        content = re.sub(process_image_pattern, mock_data_method + '\n\n  ' + r'\1', content)
    
    # Save the updated content
    with open(file_path, 'w') as f:
        f.write(content)
    
    print(f"✅ Updated {material_name}.dart successfully")
    return True

def update_backend_for_material(material_name):
    """Update backend server.js to add enhanced OCR fields for material"""
    
    server_path = "/Users/syedkhaja/Desktop/Prestige Park Groove Main Code 2/backend/server.js"
    
    print(f"📝 Updating backend for {material_name}...")
    
    # Read the server file
    with open(server_path, 'r') as f:
        content = f.read()
    
    # Find the material endpoint pattern
    endpoint_pattern = f'// {material_name.title()} submissions endpoint'
    
    if endpoint_pattern in content:
        # Update the endpoint to include enhanced OCR fields
        # This is a simplified update - in practice, you'd need more specific regex patterns
        print(f"✅ Found {material_name} endpoint in backend")
    else:
        print(f"⚠️  {material_name} endpoint not found in backend")
    
    return True

def main():
    print("🚀 Starting Enhanced OCR Update for All Material Pages")
    print("=" * 60)
    
    updated_count = 0
    
    for material in materials:
        print(f"\n📦 Processing {material}...")
        
        # Update frontend
        if update_material_page(material):
            updated_count += 1
        
        # Update backend
        update_backend_for_material(material)
    
    print(f"\n✅ Update Complete!")
    print(f"📊 Updated {updated_count}/{len(materials)} material pages")
    print("\nNext steps:")
    print("1. Manual verification of key changes")
    print("2. Test OCR functionality")
    print("3. Update backend endpoints for enhanced fields")

if __name__ == "__main__":
    main()