import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cross_file/cross_file.dart';
import 'web_image_picker.dart' if (dart.library.io) 'mobile_image_picker.dart' as platform_picker;

class UnifiedImageService {
  static final ImagePicker _picker = ImagePicker();
  
  static Future<Uint8List?> pickImage() async {
    try {
      if (kIsWeb) {
        return await platform_picker.WebImagePicker.pickImage();
      } else {
        final XFile? image = await _picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1920,
          maxHeight: 1080,
          imageQuality: 85,
        );
        if (image != null) {
          return await image.readAsBytes();
        }
        return null;
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      return null;
    }
  }
  
  static Future<Uint8List?> pickImageFromGallery() async {
    try {
      if (kIsWeb) {
        return await platform_picker.WebImagePicker.pickImage();
      } else {
        final XFile? image = await _picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1920,
          maxHeight: 1080,
          imageQuality: 85,
        );
        if (image != null) {
          return await image.readAsBytes();
        }
        return null;
      }
    } catch (e) {
      debugPrint('Error picking image from gallery: $e');
      return null;
    }
  }
  
  static Future<List<Uint8List>> pickMultipleImages() async {
    try {
      if (kIsWeb) {
        return await platform_picker.WebImagePicker.pickMultipleImages();
      } else {
        final List<XFile> images = await _picker.pickMultiImage(
          maxWidth: 1920,
          maxHeight: 1080,
          imageQuality: 85,
        );
        List<Uint8List> imagesList = [];
        
        for (final XFile image in images) {
          final Uint8List bytes = await image.readAsBytes();
          imagesList.add(bytes);
        }
        
        return imagesList;
      }
    } catch (e) {
      debugPrint('Error picking multiple images: $e');
      return [];
    }
  }
  
  // Safe image display helper that works on both platforms
  static String? getImageDisplayPath(Uint8List? imageData) {
    if (imageData == null) return null;
    
    if (kIsWeb) {
      return platform_picker.WebImagePicker.uint8ListToBase64(imageData);
    } else {
      // For mobile, return null to indicate use Image.memory(imageData) directly
      return null;
    }
  }
  
  // Create XFile from Uint8List for cross-platform compatibility
  static XFile? createXFileFromBytes(Uint8List bytes, String name) {
    try {
      return XFile.fromData(bytes, name: name);
    } catch (e) {
      debugPrint('Error creating XFile: $e');
      return null;
    }
  }
}