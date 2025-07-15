import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

class PlateRecognitionService {
  static final PlateRecognitionService _instance = PlateRecognitionService._internal();
  factory PlateRecognitionService() => _instance;
  PlateRecognitionService._internal();

  final _textRecognizer = TextRecognizer();

  Future<String?> recognizePlateNumber(File imageFile) async {
    try {
      // Convert the image file to ML Kit InputImage
      final inputImage = InputImage.fromFile(imageFile);
      
      // Process the image
      final RecognizedText recognizedText = await _textRecognizer.processImage(inputImage);

      // Extract text blocks
      String? plateNumber = await _extractPlateNumber(recognizedText);
      
      if (plateNumber != null) {
        debugPrint('Found plate number: $plateNumber');
        return plateNumber;
      } else {
        debugPrint('No valid plate number found');
        return null;
      }
    } catch (e) {
      debugPrint('Error in plate recognition: $e');
      return null;
    }
  }

  Future<String?> _extractPlateNumber(RecognizedText recognizedText) async {
    // Indian license plate format regex
    final plateRegex = RegExp(r'[A-Z]{2}[0-9]{2}[A-Z]{1,2}[0-9]{4}');
    
    for (TextBlock block in recognizedText.blocks) {
      for (TextLine line in block.lines) {
        // Remove spaces and special characters
        String cleanText = line.text.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();
        
        // Check if the text matches a license plate format
        if (plateRegex.hasMatch(cleanText)) {
          return plateRegex.firstMatch(cleanText)?.group(0);
        }
      }
    }
    return null;
  }

  void dispose() {
    _textRecognizer.close();
  }
} 