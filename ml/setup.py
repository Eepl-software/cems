#!/usr/bin/env python3
"""
Setup script for Weighbridge OCR system
"""
import subprocess
import sys
import os

def install_requirements():
    """Install Python requirements"""
    print("Installing Python requirements...")
    subprocess.check_call([sys.executable, "-m", "pip", "install", "-r", "requirements.txt"])

def install_tesseract():
    """Install Tesseract OCR"""
    print("Installing Tesseract OCR...")
    
    # Check if running on macOS
    if sys.platform == "darwin":
        try:
            subprocess.run(["brew", "--version"], check=True, capture_output=True)
            subprocess.check_call(["brew", "install", "tesseract"])
        except (subprocess.CalledProcessError, FileNotFoundError):
            print("Homebrew not found. Please install Tesseract manually:")
            print("Visit: https://github.com/tesseract-ocr/tesseract")
    
    # Check if running on Ubuntu/Debian
    elif sys.platform == "linux":
        try:
            subprocess.check_call(["sudo", "apt-get", "update"])
            subprocess.check_call(["sudo", "apt-get", "install", "-y", "tesseract-ocr"])
        except subprocess.CalledProcessError:
            print("Failed to install Tesseract. Please install manually:")
            print("sudo apt-get install tesseract-ocr")
    
    else:
        print("Please install Tesseract manually for your platform:")
        print("Visit: https://github.com/tesseract-ocr/tesseract")

def verify_installation():
    """Verify that all dependencies are installed correctly"""
    print("Verifying installation...")
    
    # Test Tesseract
    try:
        import pytesseract
        pytesseract.get_tesseract_version()
        print("✓ Tesseract OCR installed successfully")
    except Exception as e:
        print(f"✗ Tesseract OCR installation failed: {e}")
        return False
    
    # Test OpenCV
    try:
        import cv2
        print(f"✓ OpenCV installed successfully (version: {cv2.__version__})")
    except Exception as e:
        print(f"✗ OpenCV installation failed: {e}")
        return False
    
    # Test PIL
    try:
        from PIL import Image
        print("✓ PIL/Pillow installed successfully")
    except Exception as e:
        print(f"✗ PIL installation failed: {e}")
        return False
    
    # Test FastAPI
    try:
        import fastapi
        print("✓ FastAPI installed successfully")
    except Exception as e:
        print(f"✗ FastAPI installation failed: {e}")
        return False
    
    return True

def main():
    """Main setup function"""
    print("Setting up Weighbridge OCR system...")
    
    # Install Tesseract
    install_tesseract()
    
    # Install Python requirements
    install_requirements()
    
    # Verify installation
    if verify_installation():
        print("\n✓ Setup completed successfully!")
        print("\nTo start the API server, run:")
        print("python main.py")
        print("\nTo run tests, execute:")
        print("python test_ocr.py")
    else:
        print("\n✗ Setup failed. Please check the error messages above.")
        sys.exit(1)

if __name__ == "__main__":
    main()