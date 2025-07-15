import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'ml_service.dart';

class ImageClassifier {
  static final ImageClassifier _instance = ImageClassifier._internal();
  factory ImageClassifier() => _instance;
  ImageClassifier._internal();

  final MLService _mlService = MLService();

  // Constants for image validation with more lenient thresholds
  static const int _minWidth = 640;  // Reduced minimum width
  static const int _minHeight = 480;  // Reduced minimum height
  static const double _minAspectRatio = 1.2;  // More lenient aspect ratio
  static const double _maxAspectRatio = 2.2;
  static const int _minFileSize = 20 * 1024;  // Reduced to 20KB
  static const int _maxFileSize = 15 * 1024 * 1024;  // Increased to 15MB
  static const double _minBrightness = 0.2;  // More lenient brightness
  static const double _minSharpness = 0.3;   // More lenient sharpness
  static const double _minConfidence = 0.6;  // Reduced confidence threshold

  Future<Map<String, dynamic>> validateAndClassifyImage(File imageFile) async {
    try {
      debugPrint('Starting image validation for: ${imageFile.path}');

      // Basic file validation
      final validationResult = await _validateImageFile(imageFile);
      if (!validationResult['isValid']) {
        debugPrint('File validation failed: ${validationResult['message']}');
        return validationResult;
      }

      // Read and analyze image
      final bytes = await imageFile.readAsBytes();
      final image = img.decodeImage(bytes);
      
      if (image == null) {
        debugPrint('Failed to decode image');
        return {
          'isValid': false,
          'message': 'Failed to decode image',
          'details': {'error': 'Image format not supported'}
        };
      }

      // Skip detailed image analysis if the image is clearly good quality
      bool skipDetailedAnalysis = image.width >= 1024 && image.height >= 768;
      Map<String, dynamic> analysisResult;
      
      if (!skipDetailedAnalysis) {
        analysisResult = await _analyzeImage(image);
        if (!analysisResult['isValid']) {
          debugPrint('Image analysis failed: ${analysisResult['message']}');
          return analysisResult;
        }
      } else {
        analysisResult = {
          'isValid': true,
          'message': 'Skipped detailed analysis for high-quality image',
          'details': {
            'brightness': '1.0',
            'sharpness': '1.0'
          }
        };
      }

      // Perform ML-based classification
      final classificationResult = await _mlService.classifyImage(imageFile);
      debugPrint('Classification result: $classificationResult');
      
      if (!classificationResult['isTanker']) {
        return {
          'isValid': false,
          'message': 'Image does not appear to be a tanker',
          'details': {
            'confidence': classificationResult['confidence'],
            'threshold': _minConfidence,
            'scores': classificationResult['scores']
          }
        };
      }

      // If all checks pass, return success with details
      return {
        'isValid': true,
        'message': 'Image validation successful',
        'details': {
          'dimensions': '${image.width}x${image.height}',
          'aspectRatio': (image.width / image.height).toStringAsFixed(2),
          'brightness': analysisResult['details']['brightness'],
          'sharpness': analysisResult['details']['sharpness'],
          'confidence': classificationResult['confidence'],
          'classificationScores': classificationResult['scores']
        }
      };
    } catch (e, stackTrace) {
      debugPrint('Error in validateAndClassifyImage: $e');
      debugPrint('Stack trace: $stackTrace');
      return {
        'isValid': false,
        'message': 'Error processing image',
        'details': {
          'error': e.toString(),
          'stackTrace': stackTrace.toString()
        }
      };
    }
  }

  Future<Map<String, dynamic>> _validateImageFile(File imageFile) async {
    try {
      // Check if file exists
      if (!await imageFile.exists()) {
        return {
          'isValid': false,
          'message': 'File does not exist',
          'details': {'path': imageFile.path}
        };
      }

      // Check file extension
      final extension = imageFile.path.split('.').last.toLowerCase();
      if (!['jpg', 'jpeg', 'png'].contains(extension)) {
        return {
          'isValid': false,
          'message': 'Unsupported file format',
          'details': {'format': extension}
        };
      }

      // Check file size
      final size = await imageFile.length();
      if (size < _minFileSize) {
        return {
          'isValid': false,
          'message': 'Image file too small',
          'details': {'size': size, 'minSize': _minFileSize}
        };
      }
      if (size > _maxFileSize) {
        return {
          'isValid': false,
          'message': 'Image file too large',
          'details': {'size': size, 'maxSize': _maxFileSize}
        };
      }

      return {'isValid': true, 'message': 'File validation passed'};
    } catch (e) {
      debugPrint('Error in _validateImageFile: $e');
      return {
        'isValid': false,
        'message': 'Error validating file',
        'details': {'error': e.toString()}
      };
    }
  }

  Future<Map<String, dynamic>> _analyzeImage(img.Image image) async {
    try {
      // Check dimensions
      if (image.width < _minWidth || image.height < _minHeight) {
        return {
          'isValid': false,
          'message': 'Image dimensions too small',
          'details': {
            'width': image.width,
            'height': image.height,
            'minWidth': _minWidth,
            'minHeight': _minHeight
          }
        };
      }

      // Check aspect ratio
      final aspectRatio = image.width / image.height;
      if (aspectRatio < _minAspectRatio || aspectRatio > _maxAspectRatio) {
        return {
          'isValid': false,
          'message': 'Invalid aspect ratio',
          'details': {
            'aspectRatio': aspectRatio.toStringAsFixed(2),
            'minRatio': _minAspectRatio,
            'maxRatio': _maxAspectRatio
          }
        };
      }

      // Calculate brightness
      final brightness = await compute(_calculateBrightness, image);
      if (brightness < _minBrightness) {
        return {
          'isValid': false,
          'message': 'Image too dark',
          'details': {
            'brightness': brightness.toStringAsFixed(2),
            'minBrightness': _minBrightness
          }
        };
      }

      // Calculate sharpness
      final sharpness = await compute(_calculateSharpness, image);
      if (sharpness < _minSharpness) {
        return {
          'isValid': false,
          'message': 'Image not sharp enough',
          'details': {
            'sharpness': sharpness.toStringAsFixed(2),
            'minSharpness': _minSharpness
          }
        };
      }

      return {
        'isValid': true,
        'message': 'Image analysis passed',
        'details': {
          'brightness': brightness.toStringAsFixed(2),
          'sharpness': sharpness.toStringAsFixed(2)
        }
      };
    } catch (e) {
      debugPrint('Error in _analyzeImage: $e');
      return {
        'isValid': false,
        'message': 'Error analyzing image',
        'details': {'error': e.toString()}
      };
    }
  }

  // Isolate functions for better performance
  static double _calculateBrightness(img.Image image) {
    var totalBrightness = 0.0;
    final pixels = image.length;
    
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final pixel = image.getPixel(x, y);
        // Convert RGB to relative luminance
        final luminance = (0.299 * pixel.r + 0.587 * pixel.g + 0.114 * pixel.b) / 255;
        totalBrightness += luminance;
      }
    }
    
    return totalBrightness / pixels;
  }

  static double _calculateSharpness(img.Image image) {
    var totalVariation = 0.0;
    final pixels = (image.width - 1) * (image.height - 1);
    
    for (var y = 0; y < image.height - 1; y++) {
      for (var x = 0; x < image.width - 1; x++) {
        final pixel = image.getPixel(x, y);
        final rightPixel = image.getPixel(x + 1, y);
        final bottomPixel = image.getPixel(x, y + 1);
        
        // Calculate horizontal and vertical gradients
        final horizontalDiff = _pixelDifference(pixel, rightPixel);
        final verticalDiff = _pixelDifference(pixel, bottomPixel);
        
        totalVariation += (horizontalDiff + verticalDiff) / 2;
      }
    }
    
    return totalVariation / pixels;
  }

  static double _pixelDifference(img.Pixel p1, img.Pixel p2) {
    final rDiff = (p1.r - p2.r).abs() / 255.0;
    final gDiff = (p1.g - p2.g).abs() / 255.0;
    final bDiff = (p1.b - p2.b).abs() / 255.0;
    return (rDiff + gDiff + bDiff) / 3;
  }

  void dispose() {
    _mlService.dispose();
  }
}