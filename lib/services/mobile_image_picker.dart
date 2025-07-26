import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';

// This is just a stub for conditional imports - mobile uses ImagePicker directly
class WebImagePicker {
  static final ImagePicker _picker = ImagePicker();
  
  static Future<Uint8List?> pickImage() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );
    return image != null ? await image.readAsBytes() : null;
  }
  
  static Future<List<Uint8List>> pickMultipleImages() async {
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
  
  static String? uint8ListToBase64(Uint8List data) {
    // Mobile doesn't need base64 conversion, uses Image.memory directly
    return null;
  }
}