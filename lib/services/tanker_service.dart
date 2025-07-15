import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:excel/excel.dart';
import '../models/tanker.dart';
import 'plate_recognition_service.dart';
import 'image_classifier.dart';

class TankerService {
  static final TankerService _instance = TankerService._internal();
  factory TankerService() => _instance;
  TankerService._internal();

  final String _baseUrl = 'http://54.146.215.18:3000'; // Base URL without endpoints
  final PlateRecognitionService _plateRecognitionService = PlateRecognitionService();
  final ImageClassifier _imageClassifier = ImageClassifier();

  // Cache for tanker data
  final Map<String, Tanker> _tankerCache = {};

  Future<Map<String, dynamic>> processTankerImage(File imageFile) async {
    try {
      debugPrint('Starting tanker image processing');
      
      // Step 1: Validate if it's a tanker image
      final validationResult = await _imageClassifier.validateAndClassifyImage(imageFile);
      debugPrint('Validation result: $validationResult');
      
      if (!validationResult['isValid']) {
        return {
          'success': false,
          'message': validationResult['message'] ?? 'The image does not appear to be a tanker',
          'details': validationResult['details'],
        };
      }

      // Step 2: Recognize the plate number
      final plateNumber = await _plateRecognitionService.recognizePlateNumber(imageFile);
      debugPrint('Recognized plate number: $plateNumber');
      
      if (plateNumber == null || plateNumber.isEmpty) {
        return {
          'success': false,
          'message': 'Could not recognize the number plate',
        };
      }

      // Step 3: Upload the image first
      final uploadResult = await _uploadTankerImage(imageFile, plateNumber);
      debugPrint('Image upload result: $uploadResult');
      
      if (!uploadResult['success']) {
        return uploadResult;
      }

      // Step 4: Get tanker details from cache or backend
      final tanker = await _getTankerDetails(plateNumber);
      debugPrint('Tanker details: $tanker');
      
      if (tanker == null) {
        return {
          'success': false,
          'message': 'No matching tanker found for plate number: $plateNumber',
        };
      }

      // Step 5: Update backend with latest data
      final updateResult = await _updateTankerStatus(tanker);
      debugPrint('Update result: $updateResult');

      if (!updateResult) {
        return {
          'success': false,
          'message': 'Failed to update tanker status',
        };
      }

      return {
        'success': true,
        'message': 'Tanker processed successfully',
        'data': tanker.toJson(),
      };
    } catch (e, stackTrace) {
      debugPrint('Error processing tanker image: $e');
      debugPrint('Stack trace: $stackTrace');
      return {
        'success': false,
        'message': 'Error processing tanker image',
        'error': e.toString(),
      };
    }
  }

  Future<Map<String, dynamic>> _uploadTankerImage(File imageFile, String plateNumber) async {
    try {
      final uri = Uri.http('54.146.215.18:3000', '/upload-tanker-image');
      var request = http.MultipartRequest('POST', uri);
      
      // Add the image file
      var stream = http.ByteStream(imageFile.openRead());
      var length = await imageFile.length();
      var multipartFile = http.MultipartFile(
        'image',
        stream,
        length,
        filename: 'tanker_$plateNumber.jpg',
      );
      request.files.add(multipartFile);
      
      // Add plate number to form data
      request.fields['plateNumber'] = plateNumber;

      var response = await request.send();
      var responseData = await response.stream.bytesToString();
      var jsonResponse = json.decode(responseData);

      if (response.statusCode == 200) {
        return {
          'success': true,
          'imageUrl': jsonResponse['imageUrl'],
        };
      } else {
        return {
          'success': false,
          'message': jsonResponse['message'] ?? 'Failed to upload image',
        };
      }
    } catch (e) {
      debugPrint('Error uploading tanker image: $e');
      return {
        'success': false,
        'message': 'Error uploading image: $e',
      };
    }
  }

  Future<Tanker?> _getTankerDetails(String plateNumber) async {
    try {
      // Check cache first
      if (_tankerCache.containsKey(plateNumber)) {
        return _tankerCache[plateNumber];
      }

      // If not in cache, fetch from backend
      final response = await http.get(
        Uri.http('54.146.215.18:3000', '/tanker', {'plateNumber': plateNumber}),
        headers: {
          'Content-Type': 'application/json',
        },
      );

      if (response.statusCode == 200) {
        final List<dynamic> tankers = json.decode(response.body);
        if (tankers.isNotEmpty) {
          // Find the tanker with matching plate number
          final tankerData = tankers.firstWhere(
            (t) => t['plateNumber'] == plateNumber,
            orElse: () => null
          );
          if (tankerData != null) {
            final tanker = Tanker.fromJson(tankerData);
            _tankerCache[plateNumber] = tanker; // Update cache
            return tanker;
          }
        }
        return null;
      } else {
        debugPrint('Error response: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('Error getting tanker details: $e');
      return null;
    }
  }

  Future<bool> _updateTankerStatus(Tanker tanker) async {
    try {
      final response = await http.post(
        Uri.http('54.146.215.18:3000', '/tanker'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          ...tanker.toJson(),
          'lastUpdated': DateTime.now().toIso8601String(),
        }),
      );

      if (response.statusCode == 200) {
        _tankerCache[tanker.plateNumber] = tanker; // Update cache
        return true;
      } else {
        debugPrint('Error updating tanker: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('Error updating tanker status: $e');
      return false;
    }
  }

  // Method to load predefined tankers from Excel file
  Future<void> loadTankersFromExcel(String filePath) async {
    try {
      final file = File(filePath);
      final bytes = await file.readAsBytes();
      final excel = Excel.decodeBytes(bytes);
      
      for (var table in excel.tables.keys) {
        final sheet = excel.tables[table];
        if (sheet == null) continue;

        // Assuming first row is headers
        for (var row in sheet.rows.skip(1)) {
          if (row.length < 6) continue; // Skip invalid rows

          final tanker = Tanker(
            plateNumber: row[0]?.value?.toString() ?? '',
            capacity: double.tryParse(row[1]?.value?.toString() ?? '0') ?? 0,
            driverName: row[2]?.value?.toString() ?? '',
            driverContact: row[3]?.value?.toString() ?? '',
            vendor: row[4]?.value?.toString() ?? '',
            lastUpdated: DateTime.now(),
          );

          _tankerCache[tanker.plateNumber] = tanker;
        }
      }
    } catch (e) {
      debugPrint('Error loading tankers from Excel: $e');
    }
  }
} 