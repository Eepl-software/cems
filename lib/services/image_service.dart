import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:image/image.dart' as img;
import 'package:exif/exif.dart';
import 'package:flutter/foundation.dart';
import 'image_classifier.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:path/path.dart';
import 'package:http_parser/http_parser.dart';

class ImageService {
  static final ImageService _instance = ImageService._internal();
  factory ImageService() => _instance;
  ImageService._internal();

  final ImageClassifier _classifier = ImageClassifier();
  final Map<String, Map<String, dynamic>> _memoryCache = {};
  static const int _maxMemoryCacheSize = 50; // Maximum number of cached results
  static const Duration _cacheDuration = Duration(hours: 24); // Cache validity duration
  static const String baseUrl = 'http://54.146.215.18:3000';

  Future<String> _getCachePath() async {
    final appDir = await getApplicationDocumentsDirectory();
    final cacheDir = Directory('${appDir.path}/image_cache');
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }
    return cacheDir.path;
  }

  Future<String> _generateCacheKey(File imageFile) async {
    final bytes = await imageFile.readAsBytes();
    final hash = sha256.convert(bytes);
    return hash.toString();
  }

  Future<Map<String, dynamic>?> _getFromCache(String cacheKey) async {
    // Check memory cache first
    if (_memoryCache.containsKey(cacheKey)) {
      final cached = _memoryCache[cacheKey]!;
      final timestamp = cached['timestamp'] as DateTime;
      if (DateTime.now().difference(timestamp) < _cacheDuration) {
        return cached['data'] as Map<String, dynamic>;
      } else {
        _memoryCache.remove(cacheKey);
      }
    }

    // Check disk cache
    try {
      final cachePath = await _getCachePath();
      final cacheFile = File('$cachePath/$cacheKey.json');
      if (await cacheFile.exists()) {
        final jsonStr = await cacheFile.readAsString();
        final cached = json.decode(jsonStr);
        final timestamp = DateTime.parse(cached['timestamp']);
        
        if (DateTime.now().difference(timestamp) < _cacheDuration) {
          // Update memory cache
          _updateMemoryCache(cacheKey, cached['data']);
          return cached['data'];
        } else {
          await cacheFile.delete();
        }
      }
    } catch (e) {
      debugPrint('Error reading from cache: $e');
    }
    return null;
  }

  Future<void> _saveToCache(String cacheKey, Map<String, dynamic> data) async {
    // Save to memory cache
    _updateMemoryCache(cacheKey, data);

    // Save to disk cache
    try {
      final cachePath = await _getCachePath();
      final cacheFile = File('$cachePath/$cacheKey.json');
      final cacheData = {
        'timestamp': DateTime.now().toIso8601String(),
        'data': data,
      };
      await cacheFile.writeAsString(json.encode(cacheData));
    } catch (e) {
      debugPrint('Error saving to cache: $e');
    }
  }

  void _updateMemoryCache(String cacheKey, Map<String, dynamic> data) {
    // Remove oldest entry if cache is full
    if (_memoryCache.length >= _maxMemoryCacheSize) {
      final oldestKey = _memoryCache.entries
          .reduce((a, b) => 
              (a.value['timestamp'] as DateTime).isBefore(b.value['timestamp'] as DateTime) 
              ? a : b)
          .key;
      _memoryCache.remove(oldestKey);
    }

    _memoryCache[cacheKey] = {
      'timestamp': DateTime.now(),
      'data': data,
    };
  }

  Future<Map<String, dynamic>> processAndValidateImage(File imageFile) async {
    try {
      // Process the image first
      final processedFile = await processImage(imageFile);
      
      // Validate and analyze the processed image
      final validationResult = await _classifier.validateAndClassifyImage(processedFile);
      
      // Add metadata to the result
      final metadata = await getImageMetadata(processedFile);
      validationResult['metadata'] = metadata;
      
      return validationResult;
    } catch (e) {
      debugPrint('Error in processAndValidateImage: $e');
      return {
        'isValid': false,
        'message': 'Failed to process and validate image',
        'details': {'error': e.toString()}
      };
    }
  }

  static Future<File> processImage(File imageFile) async {
    try {
      // Read EXIF data
      final bytes = await imageFile.readAsBytes();
      final exifData = await readExifFromBytes(bytes);

      // Load the image
      final image = img.decodeImage(bytes);
      if (image == null) {
        throw Exception('Failed to decode image');
      }

      // Resize if too large
      img.Image processedImage = image;
      if (image.width > 1920 || image.height > 1920) {
        processedImage = img.copyResize(
          image,
          width: image.width > image.height ? 1920 : null,
          height: image.width <= image.height ? 1920 : null,
        );
      }

      // Enhance image quality
      processedImage = img.adjustColor(
        processedImage,
        contrast: 1.1,
        saturation: 1.1,
        brightness: 1.0,
      );

      // Save processed image
      final tempDir = await getTemporaryDirectory();
      final tempPath = '${tempDir.path}/processed_${DateTime.now().millisecondsSinceEpoch}.jpg';
      final processedFile = File(tempPath);
      await processedFile.writeAsBytes(img.encodeJpg(processedImage, quality: 85));

      return processedFile;
    } catch (e) {
      debugPrint('Error in processImage: $e');
      // If processing fails, return original file
      return imageFile;
    }
  }

  static Future<Map<String, String>> getImageMetadata(File imageFile) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final exifData = await readExifFromBytes(bytes);
      
      final image = img.decodeImage(bytes);
      final dimensions = image != null ? '${image.width}x${image.height}' : 'Unknown';
      
      return {
        'dimensions': dimensions,
        'datetime': exifData['Image DateTime']?.toString() ?? DateTime.now().toString(),
        'make': exifData['Image Make']?.toString() ?? 'Unknown',
        'model': exifData['Image Model']?.toString() ?? 'Unknown',
        'fileSize': '${(await imageFile.length() / 1024).toStringAsFixed(1)} KB',
      };
    } catch (e) {
      debugPrint('Error getting image metadata: $e');
      return {
        'error': 'Failed to read metadata: ${e.toString()}',
        'datetime': DateTime.now().toString(),
      };
    }
  }

  Future<bool> isValidImage(File imageFile) async {
    try {
      final result = await _classifier.validateAndClassifyImage(imageFile);
      return result['isValid'] == true;
    } catch (e) {
      debugPrint('Error in isValidImage: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> validateAndClassifyImage(File imageFile) async {
    try {
      final cacheKey = await _generateCacheKey(imageFile);
      
      // Try to get from cache
      final cachedResult = await _getFromCache(cacheKey);
      if (cachedResult != null) {
        debugPrint('Retrieved result from cache');
        return cachedResult;
      }

      // Perform validation and classification
      final result = await _classifier.validateAndClassifyImage(imageFile);
      
      // Save result to cache
      await _saveToCache(cacheKey, result);
      
      return result;
    } catch (e) {
      debugPrint('Error in validateAndClassifyImage: $e');
      return {
        'isValid': false,
        'message': 'Error processing image',
        'details': {'error': e.toString()}
      };
    }
  }

  Future<void> clearCache() async {
    try {
      // Clear memory cache
      _memoryCache.clear();

      // Clear disk cache
      final cachePath = await _getCachePath();
      final cacheDir = Directory(cachePath);
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('Error clearing cache: $e');
    }
  }

  Future<Map<String, dynamic>> uploadTankerImage(File imageFile) async {
    try {
      // Create multipart request
      final uri = Uri.http('54.146.215.18:3000', '/upload-tanker-image');
      final request = http.MultipartRequest('POST', uri);

      // Add the image file
      final stream = http.ByteStream(imageFile.openRead());
      final length = await imageFile.length();
      final multipartFile = http.MultipartFile(
        'image',
        stream,
        length,
        filename: basename(imageFile.path),
        contentType: MediaType('image', 'jpeg'),
      );
      request.files.add(multipartFile);

      // Send the request
      final response = await request.send();
      final responseData = await response.stream.bytesToString();
      
      if (response.statusCode == 200 && responseData.isNotEmpty) {
        return {
          'success': true,
          'data': json.decode(responseData),
        };
      } else {
        return {
          'success': false,
          'error': responseData.isNotEmpty ? 
            json.decode(responseData)['error'] : 
            'Failed to upload image',
        };
      }
    } catch (e) {
      debugPrint('Error uploading image: $e');
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }
}
