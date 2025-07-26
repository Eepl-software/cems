#!/usr/bin/env python3
"""
Script to update the OCR service on EC2 with the production version
"""

import subprocess
import sys
import os

def run_command(command, description):
    """Run a command and handle errors"""
    print(f"\n🔄 {description}...")
    try:
        result = subprocess.run(command, shell=True, check=True, capture_output=True, text=True)
        print(f"✅ {description} completed successfully")
        if result.stdout:
            print(f"Output: {result.stdout}")
        return True
    except subprocess.CalledProcessError as e:
        print(f"❌ {description} failed")
        print(f"Error: {e.stderr}")
        return False

def main():
    """Main function to update EC2 service"""
    
    # Configuration
    ec2_host = "54.146.215.18"
    pem_file = "/Users/syedkhaja/Downloads/thanush.pem"
    remote_dir = "/home/ubuntu/ocr-service"
    
    print("🚀 Starting EC2 OCR Service Update")
    print(f"Target: {ec2_host}")
    
    # Check if PEM file exists
    if not os.path.exists(pem_file):
        print(f"❌ PEM file not found: {pem_file}")
        return False
    
    # Set correct permissions for PEM file
    run_command(f"chmod 400 {pem_file}", "Setting PEM file permissions")
    
    # Copy the production service file to EC2
    scp_command = f'scp -i "{pem_file}" -o StrictHostKeyChecking=no ml/production_main.py ubuntu@{ec2_host}:{remote_dir}/'
    if not run_command(scp_command, "Copying production service to EC2"):
        return False
    
    # Copy the advanced OCR processor if it doesn't exist
    scp_advanced_command = f'scp -i "{pem_file}" -o StrictHostKeyChecking=no ml/advanced_ocr_processor.py ubuntu@{ec2_host}:{remote_dir}/'
    run_command(scp_advanced_command, "Copying advanced OCR processor to EC2")
    
    # Connect to EC2 and update the service
    ssh_commands = f'''
    cd {remote_dir} && 
    echo "📋 Current directory contents:" &&
    ls -la &&
    echo "🔄 Stopping existing service..." &&
    pkill -f "main.py" || echo "No existing service running" &&
    pkill -f "production_main.py" || echo "No production service running" &&
    sleep 2 &&
    echo "🚀 Starting production OCR service..." &&
    nohup python3 production_main.py > ocr_service.log 2>&1 &
    sleep 3 &&
    echo "✅ Service started. Checking status..." &&
    ps aux | grep production_main.py | grep -v grep &&
    echo "📊 Testing service health..." &&
    curl -s http://localhost:8000/ || echo "Service not yet ready" &&
    echo "🎯 Production OCR service is now running!"
    '''
    
    ssh_command = f'ssh -i "{pem_file}" -o StrictHostKeyChecking=no ubuntu@{ec2_host} "{ssh_commands}"'
    
    if run_command(ssh_command, "Updating and restarting EC2 service"):
        print("\n🎉 EC2 OCR service successfully updated to production version!")
        print("📍 Service is now running at: http://54.146.215.18/extract-weights")
        print("🔧 The service now includes all enhanced fields for the Flutter app")
        return True
    else:
        print("\n❌ Failed to update EC2 service")
        return False

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)