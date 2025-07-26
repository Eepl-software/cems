#!/usr/bin/env python3
"""
Final Script to cleanly update all material submission endpoints in backend/server.js
to include enhanced OCR fields.
"""

import re
import sys
import os

def update_single_material_endpoint(content, material_name):
    """Update a single material endpoint with enhanced OCR fields using precise matching."""
    
    print(f"Processing {material_name} endpoint...")
    
    # 1. Find and update the request body destructuring
    destructure_pattern = rf"(app\.post\('/api/{material_name}-submissions'[^{{]+{{\s*try\s*{{\s*const\s*{{\s*)([^}}]+)(\s*}}\s*=\s*req\.body;)"
    
    def replace_destructure(match):
        prefix = match.group(1)
        suffix = match.group(3)
        
        # Build the new destructuring fields
        new_fields = """date,
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
        
        return f"{prefix}{new_fields}{suffix}"
    
    content = re.sub(destructure_pattern, replace_destructure, content, flags=re.DOTALL)
    
    # 2. Find and update the CREATE TABLE statement
    create_table_pattern = rf"(CREATE TABLE IF NOT EXISTS {material_name}_submissions\s*\(\s*)(.*?)(\s*\)\s*`)"
    
    def replace_create_table(match):
        prefix = match.group(1)
        suffix = match.group(3)
        
        # Build the new table definition
        new_table_def = """id SERIAL PRIMARY KEY,
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
        transporter VARCHAR(100)"""
        
        return f"{prefix}{new_table_def}{suffix}"
    
    content = re.sub(create_table_pattern, replace_create_table, content, flags=re.DOTALL)
    
    # 3. Find and update the INSERT statement
    insert_pattern = rf"(INSERT INTO {material_name}_submissions\s*\(\s*)(.*?)(\s*\)\s*VALUES\s*\([^)]+\)\s*RETURNING\s+id)"
    
    def replace_insert(match):
        prefix = match.group(1)
        suffix = match.group(3)
        
        # Build the new insert columns
        new_columns = """date, latitude, longitude, gross_weight, tare_weight, net_weight,
        vehicle_number, driver_number, contact_number, timestamp,
        material_name, material_category, weighment_slip_no, driver_name, transporter"""
        
        # Update the VALUES part to match the new column count
        new_values = "VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15) RETURNING id"
        
        return f"{prefix}{new_columns}\n      ) {new_values}"
    
    content = re.sub(insert_pattern, replace_insert, content, flags=re.DOTALL)
    
    # 4. Find and update the values array
    values_pattern = rf"(const values = \[\s*)(.*?)(\s*\];)"
    
    def replace_values(match):
        prefix = match.group(1)
        suffix = match.group(3)
        
        # Build the new values array
        new_values = """date,
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
      transporter || null"""
        
        return f"{prefix}{new_values}{suffix}"
    
    # Find the values array within the specific material endpoint
    material_endpoint_pattern = rf"(app\.post\('/api/{material_name}-submissions'.*?const values = \[\s*)(.*?)(\s*\];.*?^\}}\);)"
    
    def replace_material_values(match):
        prefix = match.group(1)
        current_values = match.group(2)
        suffix = match.group(3)
        
        # Only replace if enhanced OCR fields are not already present
        if "material_name" not in current_values:
            new_values = """date,
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
      transporter || null"""
            
            return f"{prefix}{new_values}{suffix}"
        else:
            return match.group(0)
    
    content = re.sub(material_endpoint_pattern, replace_material_values, content, flags=re.DOTALL | re.MULTILINE)
    
    print(f"  ✅ Updated {material_name} endpoint")
    return content

def main():
    """Main function to update all material endpoints."""
    
    server_js_path = "/Users/syedkhaja/Desktop/Prestige Park Groove Main Code 2/backend/server.js"
    
    print("🚀 Final Backend Material Endpoints Update")
    print("=" * 50)
    
    # Restore from backup first
    backup_path = f"{server_js_path}.backup"
    if os.path.exists(backup_path):
        print(f"📁 Restoring from backup: {backup_path}")
        with open(backup_path, 'r', encoding='utf-8') as f:
            content = f.read()
        with open(server_js_path, 'w', encoding='utf-8') as f:
            f.write(content)
    else:
        print(f"⚠️  No backup found at {backup_path}")
    
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
    
    # Create new backup
    backup_path_final = f"{server_js_path}.backup_final"
    try:
        with open(backup_path_final, 'w', encoding='utf-8') as f:
            f.write(content)
        print(f"💾 Backup created at: {backup_path_final}")
    except Exception as e:
        print(f"⚠️  Warning: Could not create backup: {e}")
    
    # Update each material endpoint
    updated_content = content
    
    for material in materials:
        updated_content = update_single_material_endpoint(updated_content, material)
    
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
    print(f"  - Backup created: {backup_path_final}")
    
    print(f"\n🎯 Updated endpoints:")
    for material in materials:
        print(f"  - /api/{material}-submissions")
    
    print(f"\n🔧 Enhanced OCR fields added:")
    print(f"  - material_name TEXT")
    print(f"  - material_category VARCHAR(100)")
    print(f"  - weighment_slip_no VARCHAR(100)")
    print(f"  - driver_name VARCHAR(100)")
    print(f"  - transporter VARCHAR(100)")

if __name__ == "__main__":
    main()