#!/usr/bin/env python3
"""
Fixed Script to update all material submission endpoints in backend/server.js
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
    
    # Find the endpoint start and end more precisely
    endpoint_start = f"app.post('/api/{material_name}-submissions', async (req, res) => {{"
    endpoint_end = "});"
    
    # Find the position of the endpoint
    start_pos = content.find(endpoint_start)
    if start_pos == -1:
        print(f"Warning: Could not find {material_name} endpoint")
        return content
    
    # Find the matching closing brace
    brace_count = 0
    end_pos = start_pos
    i = start_pos + len(endpoint_start)
    
    while i < len(content):
        if content[i] == '{':
            brace_count += 1
        elif content[i] == '}':
            brace_count -= 1
            if brace_count == 0:
                end_pos = i + 1
                if i + 1 < len(content) and content[i + 1] == ')':
                    end_pos = i + 2
                if end_pos + 1 < len(content) and content[end_pos] == ';':
                    end_pos += 1
                break
        i += 1
    
    if end_pos == start_pos:
        print(f"Warning: Could not find end of {material_name} endpoint")
        return content
    
    endpoint_content = content[start_pos:end_pos]
    original_endpoint = endpoint_content
    
    # 1. Update destructured req.body to include enhanced OCR fields
    destructure_pattern = r"const\s*\{([^}]+)\}\s*=\s*req\.body;"
    destructure_match = re.search(destructure_pattern, endpoint_content, re.DOTALL)
    
    if destructure_match:
        current_fields = destructure_match.group(1)
        
        # Check if enhanced OCR fields are already present
        if "material_name" not in current_fields:
            print(f"  Adding enhanced OCR fields to request body destructuring...")
            
            # Build new destructuring with enhanced fields
            new_destructure = f"""const {{
      date,
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
      transporter
    }} = req.body;"""
            
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
            
            # Build new table definition
            new_table = f"""CREATE TABLE IF NOT EXISTS {material_name}_submissions (
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
            
            endpoint_content = re.sub(create_table_pattern, new_table, endpoint_content, flags=re.DOTALL)
        else:
            print(f"  Enhanced OCR fields already present in CREATE TABLE")
    
    # 3. Update INSERT statement
    insert_pattern = rf"INSERT INTO {material_name}_submissions\s*\([^)]+\)\s*VALUES\s*\([^)]+\)\s*RETURNING\s+id"
    insert_match = re.search(insert_pattern, endpoint_content, re.DOTALL)
    
    if insert_match:
        current_insert = insert_match.group(0)
        
        # Check if enhanced OCR fields are already in insert
        if "material_name" not in current_insert:
            print(f"  Adding enhanced OCR fields to INSERT statement...")
            
            # Build new insert statement
            new_insert = f"""INSERT INTO {material_name}_submissions (
        date, latitude, longitude, gross_weight, tare_weight, net_weight,
        vehicle_number, driver_number, contact_number, timestamp,
        material_name, material_category, weighment_slip_no, driver_name, transporter
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15) RETURNING id"""
            
            endpoint_content = re.sub(insert_pattern, new_insert, endpoint_content, flags=re.DOTALL)
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
            
            # Build new values array
            new_values = """const values = [
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
            
            endpoint_content = re.sub(values_pattern, new_values, endpoint_content, flags=re.DOTALL)
        else:
            print(f"  Enhanced OCR fields already present in values array")
    
    # Replace the original endpoint with the updated one
    if endpoint_content != original_endpoint:
        updated_content = content[:start_pos] + endpoint_content + content[end_pos:]
        print(f"  ✅ Successfully updated {material_name} endpoint")
        return updated_content
    else:
        print(f"  ℹ️  No changes needed for {material_name} endpoint")
        return content

def main():
    """Main function to update all material endpoints."""
    
    server_js_path = "/Users/syedkhaja/Desktop/Prestige Park Groove Main Code 2/backend/server.js"
    
    print("🚀 Starting Backend Material Endpoints Update (Fixed Version)")
    print("=" * 70)
    
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
    backup_path = f"{server_js_path}.backup_fixed"
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
        # Restore backup if write fails
        try:
            with open(backup_path, 'r', encoding='utf-8') as f:
                backup_content = f.read()
            with open(server_js_path, 'w', encoding='utf-8') as f:
                f.write(backup_content)
            print(f"🔄 Restored backup due to write error")
        except:
            pass
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