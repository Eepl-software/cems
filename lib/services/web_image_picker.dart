import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

class WebImagePicker {
  static Future<Uint8List?> pickImage() async {
    if (!kIsWeb) return null;
    
    final html.FileUploadInputElement uploadInput = html.FileUploadInputElement();
    uploadInput.accept = 'image/*';
    uploadInput.click();
    
    await uploadInput.onChange.first;
    
    final files = uploadInput.files;
    if (files!.isEmpty) return null;
    
    final html.File file = files[0];
    final reader = html.FileReader();
    reader.readAsArrayBuffer(file);
    
    await reader.onLoad.first;
    
    return reader.result as Uint8List;
  }
  
  static Future<List<Uint8List>> pickMultipleImages() async {
    if (!kIsWeb) return [];
    
    final html.FileUploadInputElement uploadInput = html.FileUploadInputElement();
    uploadInput.accept = 'image/*';
    uploadInput.multiple = true;
    uploadInput.click();
    
    await uploadInput.onChange.first;
    
    final files = uploadInput.files;
    if (files!.isEmpty) return [];
    
    List<Uint8List> imagesList = [];
    
    for (final html.File file in files) {
      final reader = html.FileReader();
      reader.readAsArrayBuffer(file);
      await reader.onLoad.first;
      imagesList.add(reader.result as Uint8List);
    }
    
    return imagesList;
  }
  
  // Convert Uint8List to base64 for web display
  static String uint8ListToBase64(Uint8List data) {
    final String base64String = html.Url.createObjectUrlFromBlob(
      html.Blob([data])
    );
    return base64String;
  }
}