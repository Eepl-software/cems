import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'dart:io';
import 'package:prestige_park_groove/services/image_classifier.dart';
import 'package:prestige_park_groove/services/image_service.dart';

void main() {
  late ImageClassifier imageClassifier;
  late ImageService imageService;
  late Directory tempDir;

  setUp(() async {
    imageClassifier = ImageClassifier();
    imageService = ImageService();
    tempDir = await Directory.systemTemp.createTemp();
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group('ImageClassifier Tests', () {
    test('validates image dimensions correctly', () async {
      // Create a test image with valid dimensions
      final validImage = img.Image(width: 1000, height: 800);
      final validImageFile = await _saveImageToFile(validImage, 'valid.jpg');
      
      final result = await imageClassifier.validateAndClassifyImage(validImageFile);
      expect(result['isValid'], true);
      
      // Create a test image with invalid dimensions
      final invalidImage = img.Image(width: 400, height: 300);
      final invalidImageFile = await _saveImageToFile(invalidImage, 'invalid.jpg');
      
      final invalidResult = await imageClassifier.validateAndClassifyImage(invalidImageFile);
      expect(invalidResult['isValid'], false);
      expect(invalidResult['message'], contains('dimensions too small'));
    });

    test('validates aspect ratio correctly', () async {
      // Create a test image with valid aspect ratio
      final validImage = img.Image(width: 1600, height: 900); // 16:9 ratio
      final validImageFile = await _saveImageToFile(validImage, 'valid_ratio.jpg');
      
      final result = await imageClassifier.validateAndClassifyImage(validImageFile);
      expect(result['isValid'], true);
      
      // Create a test image with invalid aspect ratio
      final invalidImage = img.Image(width: 1000, height: 3000); // 1:3 ratio
      final invalidImageFile = await _saveImageToFile(invalidImage, 'invalid_ratio.jpg');
      
      final invalidResult = await imageClassifier.validateAndClassifyImage(invalidImageFile);
      expect(invalidResult['isValid'], false);
      expect(invalidResult['message'], contains('aspect ratio'));
    });

    test('validates brightness correctly', () async {
      // Create a bright test image
      final brightImage = _createTestImage(width: 1000, height: 800, brightness: 200);
      final brightImageFile = await _saveImageToFile(brightImage, 'bright.jpg');
      
      final result = await imageClassifier.validateAndClassifyImage(brightImageFile);
      expect(result['isValid'], true);
      
      // Create a dark test image
      final darkImage = _createTestImage(width: 1000, height: 800, brightness: 50);
      final darkImageFile = await _saveImageToFile(darkImage, 'dark.jpg');
      
      final darkResult = await imageClassifier.validateAndClassifyImage(darkImageFile);
      expect(darkResult['isValid'], false);
      expect(darkResult['message'], contains('too dark'));
    });

    test('validates tanker-specific criteria', () async {
      // Create a test image with tanker-like properties
      final tankerImage = _createTankerTestImage();
      final tankerImageFile = await _saveImageToFile(tankerImage, 'tanker.jpg');
      
      final result = await imageClassifier.validateAndClassifyImage(tankerImageFile);
      expect(result['isValid'], true);
      
      // Create a non-tanker test image
      final nonTankerImage = _createNonTankerTestImage();
      final nonTankerImageFile = await _saveImageToFile(nonTankerImage, 'non_tanker.jpg');
      
      final nonTankerResult = await imageClassifier.validateAndClassifyImage(nonTankerImageFile);
      expect(nonTankerResult['isValid'], false);
    });
  });

  group('ImageService Tests', () {
    test('caches and retrieves results correctly', () async {
      final testImage = _createTestImage(width: 1000, height: 800, brightness: 200);
      final testImageFile = await _saveImageToFile(testImage, 'cache_test.jpg');
      
      // First call should process the image
      final firstResult = await imageService.validateAndClassifyImage(testImageFile);
      expect(firstResult['isValid'], true);
      
      // Second call should retrieve from cache
      final secondResult = await imageService.validateAndClassifyImage(testImageFile);
      expect(secondResult, equals(firstResult));
    });

    test('cache expires correctly', () async {
      final testImage = _createTestImage(width: 1000, height: 800, brightness: 200);
      final testImageFile = await _saveImageToFile(testImage, 'expire_test.jpg');
      
      // First call should process the image
      final firstResult = await imageService.validateAndClassifyImage(testImageFile);
      
      // Manually clear cache
      await imageService.clearCache();
      
      // Next call should process the image again
      final secondResult = await imageService.validateAndClassifyImage(testImageFile);
      expect(secondResult, equals(firstResult)); // Results should be equal but not cached
    });
  });
}

Future<File> _saveImageToFile(img.Image image, String filename) async {
  final bytes = img.encodeJpg(image);
  final file = File('${Directory.systemTemp.path}/$filename');
  await file.writeAsBytes(bytes);
  return file;
}

img.Image _createTestImage({required int width, required int height, int brightness = 128}) {
  final image = img.Image(width: width, height: height);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      image.setPixel(x, y, img.ColorRgb8(brightness, brightness, brightness));
    }
  }
  return image;
}

img.Image _createTankerTestImage() {
  final image = img.Image(width: 1000, height: 800);
  
  // Add metallic color (grey)
  for (var y = 0; y < 800; y++) {
    for (var x = 0; x < 1000; x++) {
      image.setPixel(x, y, img.ColorRgb8(150, 150, 150));
    }
  }
  
  // Add horizontal lines
  for (var y = 200; y < 600; y += 100) {
    for (var x = 0; x < 1000; x++) {
      image.setPixel(x, y, img.ColorRgb8(200, 200, 200));
    }
  }
  
  return image;
}

img.Image _createNonTankerTestImage() {
  final image = img.Image(width: 1000, height: 800);
  
  // Add random colors
  for (var y = 0; y < 800; y++) {
    for (var x = 0; x < 1000; x++) {
      image.setPixel(x, y, img.ColorRgb8(
        (x * y) % 255,
        (x + y) % 255,
        (x - y).abs() % 255
      ));
    }
  }
  
  return image;
} 