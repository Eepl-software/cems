#!/usr/bin/env python3
"""
Create a test weighbridge slip image
"""

from PIL import Image, ImageDraw, ImageFont
import sys

def create_test_image():
    """Create a test weighbridge slip image"""
    
    # Create a white background
    img = Image.new('RGB', (800, 600), color='white')
    draw = ImageDraw.Draw(img)
    
    # Try to use a system font
    try:
        header_font = ImageFont.truetype('/System/Library/Fonts/Arial.ttf', 32)
        weight_font = ImageFont.truetype('/System/Library/Fonts/Arial.ttf', 28)
        info_font = ImageFont.truetype('/System/Library/Fonts/Arial.ttf', 20)
    except:
        header_font = ImageFont.load_default()
        weight_font = ImageFont.load_default()
        info_font = ImageFont.load_default()
    
    # Draw header
    draw.text((200, 50), "SHREE WEIGH BRIDGE", fill='black', font=header_font)
    
    # Draw weight information
    draw.text((100, 150), "GROSS : 28000 Kg", fill='black', font=weight_font)
    draw.text((100, 200), "TARE  : 12000 Kg", fill='black', font=weight_font)
    draw.text((100, 250), "NET   : 16000 Kg", fill='black', font=weight_font)
    
    # Add additional information
    draw.text((100, 350), "Date: 2025-07-14", fill='black', font=info_font)
    draw.text((100, 380), "Time: 10:30", fill='black', font=info_font)
    draw.text((100, 410), "Vehicle No: KA01AB1234", fill='black', font=info_font)
    
    # Add some border
    draw.rectangle([20, 20, 780, 580], outline='black', width=2)
    
    # Save the image
    img.save('/Users/syedkhaja/Desktop/Prestige Park Groove Main Code 2/ml/test_weighbridge_slip.png')
    print("✓ Test image created: test_weighbridge_slip.png")
    
    return img

if __name__ == "__main__":
    create_test_image()