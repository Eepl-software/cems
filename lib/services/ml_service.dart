import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

class MLService {
  static final MLService _instance = MLService._internal();
  factory MLService() => _instance;
  MLService._internal();

  final _imageLabeler = ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.5));

  Future<Map<String, dynamic>> classifyImage(File imageFile) async {
    try {
      if (!await imageFile.exists()) {
        return {
          'isTanker': false,
          'confidence': 0.0,
          'error': 'File does not exist',
        };
      }

      final inputImage = InputImage.fromFile(imageFile);
      final labels = await _imageLabeler.processImage(inputImage);

      // Vehicle-related keywords
      final vehicleKeywords = {
        'truck': 1.0,
        'vehicle': 0.9,
        'tanker': 1.0,
        'transport': 0.8,
        'commercial': 0.7,
        'cargo': 0.8,
        'delivery': 0.7,
        'heavy': 0.7,
        'motor': 0.6,
        'wheel': 0.6,
      };

      bool isTanker = false;
      double maxConfidence = 0.0;
      Map<String, double> scores = {};
      
      for (ImageLabel label in labels) {
        final String text = label.label.toLowerCase();
        final double confidence = label.confidence;
        scores[text] = confidence;

        // Check each keyword and apply weight
        for (var entry in vehicleKeywords.entries) {
          if (text.contains(entry.key)) {
            double weightedConfidence = confidence * entry.value;
            if (weightedConfidence > maxConfidence) {
              maxConfidence = weightedConfidence;
              isTanker = true;
            }
          }
        }
      }

      debugPrint('Image classification result: isTanker=$isTanker, confidence=$maxConfidence');
      debugPrint('Detected labels: ${scores.toString()}');

      return {
        'isTanker': isTanker,
        'confidence': maxConfidence,
        'scores': scores,
      };
    } catch (e) {
      debugPrint('Error in classifyImage: $e');
      return {
        'isTanker': false,
        'confidence': 0.0,
        'error': e.toString(),
        'errorDetails': e is Exception ? e.toString() : 'Unknown error',
      };
    }
  }

  void dispose() {
    _imageLabeler.close();
  }
} 