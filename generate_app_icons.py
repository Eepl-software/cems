#!/usr/bin/env python3

import os
from PIL import Image, ImageDraw, ImageFilter
from pathlib import Path

def create_kalpar_app_icon(size, output_path):
    """
    Create a high-quality app icon inspired by the Kalpar logo
    focusing on the 'X' symbol with modern styling
    """
    # Create a new image with the specified size
    img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    
    # Colors from the Kalpar logo
    blue_color = (68, 138, 255)  # #448AFF - bright blue
    gray_color = (158, 158, 158)  # #9E9E9E - light gray
    bg_color = (55, 71, 79)      # #37474F - dark blue-gray
    
    # Calculate dimensions
    margin = size * 0.1
    icon_size = size - (margin * 2)
    center = size // 2
    
    # Create background with subtle gradient effect
    for y in range(size):
        for x in range(size):
            # Create circular mask for app icon
            dx = x - center
            dy = y - center
            distance = (dx**2 + dy**2)**0.5
            
            if distance <= center:
                # Gradient from center to edge
                gradient_factor = 1 - (distance / center) * 0.3
                r = int(bg_color[0] * gradient_factor)
                g = int(bg_color[1] * gradient_factor)
                b = int(bg_color[2] * gradient_factor)
                img.putpixel((x, y), (r, g, b, 255))
    
    # Draw the 'X' symbol
    stroke_width = max(size // 25, 2)
    
    # Calculate X coordinates
    x_margin = size * 0.25
    x_size = size * 0.5
    x_left = x_margin
    x_right = x_left + x_size
    x_top = x_margin
    x_bottom = x_top + x_size
    
    # Create the X shape using polygons for smoother edges
    # First stroke (top-left to bottom-right) - Blue
    points1 = [
        (x_left, x_top),
        (x_left + stroke_width, x_top),
        (x_right, x_bottom - stroke_width),
        (x_right, x_bottom),
        (x_right - stroke_width, x_bottom),
        (x_left, x_top + stroke_width)
    ]
    
    # Second stroke (top-right to bottom-left) - Gray
    points2 = [
        (x_right, x_top),
        (x_right, x_top + stroke_width),
        (x_left + stroke_width, x_bottom),
        (x_left, x_bottom),
        (x_left, x_bottom - stroke_width),
        (x_right - stroke_width, x_top)
    ]
    
    # Draw the X with anti-aliasing
    # Create a larger image for better anti-aliasing
    scale = 4
    large_img = Image.new('RGBA', (size * scale, size * scale), (0, 0, 0, 0))
    large_draw = ImageDraw.Draw(large_img)
    
    # Draw background on large image
    for y in range(size * scale):
        for x in range(size * scale):
            dx = x - (center * scale)
            dy = y - (center * scale)
            distance = (dx**2 + dy**2)**0.5
            
            if distance <= center * scale:
                gradient_factor = 1 - (distance / (center * scale)) * 0.3
                r = int(bg_color[0] * gradient_factor)
                g = int(bg_color[1] * gradient_factor)
                b = int(bg_color[2] * gradient_factor)
                large_img.putpixel((x, y), (r, g, b, 255))
    
    # Scale up the points
    large_points1 = [(x * scale, y * scale) for x, y in points1]
    large_points2 = [(x * scale, y * scale) for x, y in points2]
    
    # Draw X on large image
    large_draw.polygon(large_points1, fill=blue_color)
    large_draw.polygon(large_points2, fill=gray_color)
    
    # Add subtle shadow effect
    shadow_offset = scale * 2
    shadow_points1 = [(x + shadow_offset, y + shadow_offset) for x, y in large_points1]
    shadow_points2 = [(x + shadow_offset, y + shadow_offset) for x, y in large_points2]
    
    shadow_color = (0, 0, 0, 50)  # Semi-transparent black
    large_draw.polygon(shadow_points1, fill=shadow_color)
    large_draw.polygon(shadow_points2, fill=shadow_color)
    
    # Resize back to original size with high-quality resampling
    img = large_img.resize((size, size), Image.Resampling.LANCZOS)
    
    # Apply subtle blur to edges for iOS-style smoothness
    if size >= 512:  # Only for large icons
        img = img.filter(ImageFilter.GaussianBlur(radius=0.5))
    
    # Save the image
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    img.save(output_path, 'PNG', quality=100, optimize=True)
    print(f"Created icon: {output_path} ({size}x{size})")

def main():
    base_path = Path("/Users/syedkhaja/Desktop/Prestige Park Groove Main Code 2")
    
    # Create a master app icon
    master_icon_path = base_path / "assets" / "app_icon.png"
    create_kalpar_app_icon(1024, str(master_icon_path))
    
    # Android icon sizes
    android_sizes = {
        'mipmap-mdpi': 48,
        'mipmap-hdpi': 72,
        'mipmap-xhdpi': 96,
        'mipmap-xxhdpi': 144,
        'mipmap-xxxhdpi': 192
    }
    
    for folder, size in android_sizes.items():
        output_path = base_path / "android" / "app" / "src" / "main" / "res" / folder / "ic_launcher.png"
        create_kalpar_app_icon(size, str(output_path))
    
    # iOS icon sizes
    ios_sizes = {
        'Icon-App-20x20@1x.png': 20,
        'Icon-App-20x20@2x.png': 40,
        'Icon-App-20x20@3x.png': 60,
        'Icon-App-29x29@1x.png': 29,
        'Icon-App-29x29@2x.png': 58,
        'Icon-App-29x29@3x.png': 87,
        'Icon-App-40x40@1x.png': 40,
        'Icon-App-40x40@2x.png': 80,
        'Icon-App-40x40@3x.png': 120,
        'Icon-App-60x60@2x.png': 120,
        'Icon-App-60x60@3x.png': 180,
        'Icon-App-76x76@1x.png': 76,
        'Icon-App-76x76@2x.png': 152,
        'Icon-App-83.5x83.5@2x.png': 167,
        'Icon-App-1024x1024@1x.png': 1024
    }
    
    ios_base_path = base_path / "ios" / "Runner" / "Assets.xcassets" / "AppIcon.appiconset"
    for filename, size in ios_sizes.items():
        output_path = ios_base_path / filename
        create_kalpar_app_icon(size, str(output_path))
    
    print("\n✅ All app icons generated successfully!")
    print(f"Master icon saved to: {master_icon_path}")
    print("Ready to update pubspec.yaml configuration.")

if __name__ == "__main__":
    main()