#!/usr/bin/env python3
"""
Script to update all material submission endpoints in backend/server.js
to include enhanced OCR fields.

Enhanced OCR fields to add:
- material_name TEXT
- material_category VARCHAR(100)
- weighment_slip_no VARCHAR(100)
- driver_name VARCHAR(100)
- transporter VARCHAR(100)
"""

import re
import sys
import os
from pathlib import Path

def update_material_endpoint(content, material_name):
    """Update a single material endpoint with enhanced OCR fields."""
    
    print(f"Updating {material_name} endpoint...")
    
    # Find the endpoint start and end
    endpoint_pattern = rf"app\.post\('/api/{material_name}-submissions'.*?^\}}\);"
    endpoint_match = re.search(endpoint_pattern, content, re.DOTALL | re.MULTILINE)
    
    if not endpoint_match:
        print(f"Warning: Could not find {material_name} endpoint")
        return content
    
    endpoint_content = endpoint_match.group(0)
    original_endpoint = endpoint_content
    
    # 1. Update destructured req.body to include enhanced OCR fields
    destructure_pattern = r"const\s*\{([^}]+)\}\s*=\s*req\.body;"
    destructure_match = re.search(destructure_pattern, endpoint_content, re.DOTALL)
    
    if destructure_match:
        current_fields = destructure_match.group(1)
        
        # Check if enhanced OCR fields are already present
        if "material_name" not in current_fields:
            print(f"  Adding enhanced OCR fields to request body destructuring...")
            # Add enhanced OCR fields
            enhanced_fields = f"""      date,
      latitude,
      longitude,
      gross_weight,
      tare_weight,
      net_weight,
      vehicle_number,
      driver_number,
      contact_number,
      timestamp,
      // Enhanced OCR fields
      material_name,
      material_category,
      weighment_slip_no,
      driver_name,
      transporter"""
            
            new_destructure = f"const {{\n{enhanced_fields}\n    }} = req.body;"
            endpoint_content = re.sub(destructure_pattern, new_destructure, endpoint_content, flags=re.DOTALL)
        else:
            print(f"  Enhanced OCR fields already present in request body")
    
    # 2. Update CREATE TABLE statement
    create_table_pattern = rf"CREATE TABLE IF NOT EXISTS {material_name}_submissions\s*\([^)]+\)"
    create_table_match = re.search(create_table_pattern, endpoint_content, re.DOTALL)
    
    if create_table_match:
        current_table = create_table_match.group(0)
        
        # Check if enhanced OCR fields are already in table
        if "material_name" not in current_table:
            print(f"  Adding enhanced OCR fields to CREATE TABLE statement...")
            # Add enhanced OCR fields to table
            enhanced_table = f"""CREATE TABLE IF NOT EXISTS {material_name}_submissions (
        id SERIAL PRIMARY KEY,
        date DATE NOT NULL,
        latitude DECIMAL(10, 8) NOT NULL,
        longitude DECIMAL(11, 8) NOT NULL,
        gross_weight VARCHAR(50) NOT NULL,
        tare_weight VARCHAR(50) NOT NULL,
        net_weight VARCHAR(50) NOT NULL,
        vehicle_number VARCHAR(20),
        driver_number VARCHAR(100) NOT NULL,
        contact_number VARCHAR(20) NOT NULL,
        timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
        material_name TEXT,
        material_category VARCHAR(100),
        weighment_slip_no VARCHAR(100),
        driver_name VARCHAR(100),
        transporter VARCHAR(100)
      )"""
            
            endpoint_content = re.sub(create_table_pattern, enhanced_table, endpoint_content, flags=re.DOTALL)
        else:
            print(f"  Enhanced OCR fields already present in CREATE TABLE")
    
    # 3. Update INSERT statement
    insert_pattern = rf"INSERT INTO {material_name}_submissions\s*\([^)]+\)\s*VALUES\s*\([^)]+\)"
    insert_match = re.search(insert_pattern, endpoint_content, re.DOTALL)
    
    if insert_match:
        current_insert = insert_match.group(0)
        
        # Check if enhanced OCR fields are already in insert
        if "material_name" not in current_insert:
            print(f"  Adding enhanced OCR fields to INSERT statement...")
            # Update INSERT statement
            enhanced_insert = f"""INSERT INTO {material_name}_submissions (
        date, latitude, longitude, gross_weight, tare_weight, net_weight,
        vehicle_number, driver_number, contact_number, timestamp,
        material_name, material_category, weighment_slip_no, driver_name, transporter
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15) RETURNING id"""
            
            endpoint_content = re.sub(insert_pattern, enhanced_insert, endpoint_content, flags=re.DOTALL)
        else:
            print(f"  Enhanced OCR fields already present in INSERT statement")
    
    # 4. Update values array
    values_pattern = r"const values = \[\s*([^]]+)\s*\];"
    values_match = re.search(values_pattern, endpoint_content, re.DOTALL)
    
    if values_match:
        current_values = values_match.group(1)
        
        # Check if enhanced OCR fields are already in values
        if "material_name" not in current_values:
            print(f"  Adding enhanced OCR fields to values array...")
            # Update values array
            enhanced_values = """const values = [
      date,
      parseFloat(latitude),
      parseFloat(longitude),
      gross_weight,
      tare_weight,
      net_weight,
      vehicle_number || null,
      driver_number,
      contact_number,
      timestamp || new Date().toISOString(),
      material_name || null,
      material_category || null,
      weighment_slip_no || null,
      driver_name || null,
      transporter || null
    ];"""
            
            endpoint_content = re.sub(values_pattern, enhanced_values, endpoint_content, flags=re.DOTALL)
        else:
            print(f"  Enhanced OCR fields already present in values array")
    
    # Replace the original endpoint with the updated one
    if endpoint_content != original_endpoint:
        updated_content = content.replace(endpoint_match.group(0), endpoint_content)
        print(f"  ✅ Successfully updated {material_name} endpoint")
        return updated_content
    else:
        print(f"  ℹ️  No changes needed for {material_name} endpoint")
        return content

def main():
    """Main function to update all material endpoints."""
    
    server_js_path = "/Users/syedkhaja/Desktop/Prestige Park Groove Main Code 2/backend/server.js"
    
    print("🚀 Starting Backend Material Endpoints Update")
    print("=" * 60)
    
    # Check if file exists
    if not os.path.exists(server_js_path):
        print(f"❌ Error: File {server_js_path} does not exist")
        sys.exit(1)
    
    # Read the file
    try:
        with open(server_js_path, 'r', encoding='utf-8') as f:
            content = f.read()
        print(f"📖 Successfully read server.js ({len(content)} characters)")
    except Exception as e:
        print(f"❌ Error reading file: {e}")
        sys.exit(1)
    
    # List of materials to update
    materials = [
        'cement', 'sand', 'metals', 'pipes', 'tiles', 
        'wood', 'electricals', 'plastic', 'aggregates'
    ]
    
    # Create backup
    backup_path = f"{server_js_path}.backup"
    try:
        with open(backup_path, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"💾 Backup created at: {backup_path}")
    except Exception as e:
        print(f"⚠️  Warning: Could not create backup: {e}")
    
    # Update each material endpoint
    updated_content = content
    updated_count = 0
    
    for material in materials:
        print(f"\n📦 Processing {material}...")
        original_content = updated_content
        updated_content = update_material_endpoint(updated_content, material)
        
        if updated_content != original_content:
            updated_count += 1
    
    # Write the updated content
    try:
        with open(server_js_path, 'w', encoding='utf-8') as f:
            f.write(updated_content)
        print(f"\n✅ Successfully updated server.js!")
    except Exception as e:
        print(f"❌ Error writing file: {e}")
        sys.exit(1)
    
    print(f"\n📊 Summary:")
    print(f"  - Total endpoints processed: {len(materials)}")
    print(f"  - Endpoints updated: {updated_count}")
    print(f"  - Backup created: {backup_path}")
    
    print(f"\n🎯 Updated endpoints:")
    for material in materials:
        print(f"  - /api/{material}-submissions")
    
    print(f"\n🔧 Enhanced OCR fields added:")
    print(f"  - material_name TEXT")
    print(f"  - material_category VARCHAR(100)")
    print(f"  - weighment_slip_no VARCHAR(100)")
    print(f"  - driver_name VARCHAR(100)")
    print(f"  - transporter VARCHAR(100)")
    
    print(f"\n📋 Next steps:")
    print(f"  1. Test the updated endpoints")
    print(f"  2. Verify database table creation")
    print(f"  3. Update frontend to send enhanced OCR fields")
    print(f"  4. Test end-to-end OCR functionality")

if __name__ == "__main__":
    main()