import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

class WeighbridgeOCRService {
  static const String baseUrl = 'http://localhost:8000'; // Change for production
  
  /// Extract weights from weighbridge slip image
  static Future<WeighbridgeResult> extractWeights(File imageFile) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/extract-weights'),
      );
      
      request.files.add(
        await http.MultipartFile.fromPath('file', imageFile.path),
      );
      
      var response = await request.send();
      var responseBody = await response.stream.bytesToString();
      var data = json.decode(responseBody);
      
      if (data['success']) {
        return WeighbridgeResult.fromJson(data['data']);
      } else {
        throw Exception(data['message'] ?? 'Failed to extract weights');
      }
    } catch (e) {
      throw Exception('Network error: $e');
    }
  }
  
  /// Validate image before processing
  static Future<ImageValidationResult> validateImage(File imageFile) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/validate-image'),
      );
      
      request.files.add(
        await http.MultipartFile.fromPath('file', imageFile.path),
      );
      
      var response = await request.send();
      var responseBody = await response.stream.bytesToString();
      var data = json.decode(responseBody);
      
      if (data['success']) {
        return ImageValidationResult.fromJson(data['data']);
      } else {
        throw Exception(data['message'] ?? 'Image validation failed');
      }
    } catch (e) {
      throw Exception('Validation error: $e');
    }
  }
  
  /// Check API health
  static Future<bool> checkHealth() async {
    try {
      var response = await http.get(Uri.parse('$baseUrl/health'));
      var data = json.decode(response.body);
      return data['status'] == 'healthy';
    } catch (e) {
      return false;
    }
  }
}

class WeighbridgeResult {
  final String? grossWeight;
  final String? tareWeight;
  final String? netWeight;
  final bool validationPassed;
  
  WeighbridgeResult({
    this.grossWeight,
    this.tareWeight,
    this.netWeight,
    this.validationPassed = false,
  });
  
  factory WeighbridgeResult.fromJson(Map<String, dynamic> json) {
    return WeighbridgeResult(
      grossWeight: json['gross_weight'],
      tareWeight: json['tare_weight'],
      netWeight: json['net_weight'],
      validationPassed: json['validation_passed'] ?? false,
    );
  }
  
  bool get isComplete => grossWeight != null && tareWeight != null && netWeight != null;
}

class ImageValidationResult {
  final int width;
  final int height;
  final int fileSize;
  final String fileType;
  final bool isValid;
  final List<String> issues;
  
  ImageValidationResult({
    required this.width,
    required this.height,
    required this.fileSize,
    required this.fileType,
    required this.isValid,
    required this.issues,
  });
  
  factory ImageValidationResult.fromJson(Map<String, dynamic> json) {
    return ImageValidationResult(
      width: json['width'],
      height: json['height'],
      fileSize: json['file_size'],
      fileType: json['file_type'],
      isValid: json['is_valid'],
      issues: List<String>.from(json['issues']),
    );
  }
}

class WeighbridgeOCRPage extends StatefulWidget {
  @override
  WeighbridgeOCRPageState createState() => WeighbridgeOCRPageState();
}

class WeighbridgeOCRPageState extends State<WeighbridgeOCRPage> {
  File? _selectedImage;
  WeighbridgeResult? _result;
  bool _isProcessing = false;
  String? _errorMessage;
  final ImagePicker _picker = ImagePicker();
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Weighbridge OCR'),
        backgroundColor: Colors.blue,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Image Selection Section
            Card(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      'Select Weighbridge Slip Image',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    SizedBox(height: 16),
                    if (_selectedImage != null)
                      Container(
                        height: 200,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            _selectedImage!,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ),
                    SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _isProcessing ? null : () => _pickImage(ImageSource.camera),
                          icon: Icon(Icons.camera_alt),
                          label: Text('Camera'),
                        ),
                        ElevatedButton.icon(
                          onPressed: _isProcessing ? null : () => _pickImage(ImageSource.gallery),
                          icon: Icon(Icons.photo_library),
                          label: Text('Gallery'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            SizedBox(height: 16),
            
            // Process Button
            ElevatedButton(
              onPressed: _selectedImage != null && !_isProcessing ? _processImage : null,
              style: ElevatedButton.styleFrom(
                padding: EdgeInsets.symmetric(vertical: 16),
                backgroundColor: Colors.green,
              ),
              child: _isProcessing
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('Processing...'),
                      ],
                    )
                  : Text(
                      'Extract Weights',
                      style: TextStyle(fontSize: 16),
                    ),
            ),
            
            SizedBox(height: 16),
            
            // Error Message
            if (_errorMessage != null)
              Card(
                color: Colors.red[50],
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.error, color: Colors.red),
                          SizedBox(width: 8),
                          Text(
                            'Error',
                            style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red[700]),
                      ),
                    ],
                  ),
                ),
              ),
            
            // Results Section
            if (_result != null)
              Card(
                color: _result!.validationPassed ? Colors.green[50] : Colors.orange[50],
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _result!.validationPassed ? Icons.check_circle : Icons.warning,
                            color: _result!.validationPassed ? Colors.green : Colors.orange,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Extraction Results',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 16),
                      _buildResultRow('GROSS Weight', _result!.grossWeight),
                      _buildResultRow('TARE Weight', _result!.tareWeight),
                      _buildResultRow('NET Weight', _result!.netWeight),
                      SizedBox(height: 12),
                      Container(
                        padding: EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _result!.validationPassed ? Colors.green[100] : Colors.orange[100],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              _result!.validationPassed ? Icons.verified : Icons.info,
                              size: 16,
                              color: _result!.validationPassed ? Colors.green[700] : Colors.orange[700],
                            ),
                            SizedBox(width: 4),
                            Text(
                              _result!.validationPassed 
                                  ? 'Weights validated successfully' 
                                  : 'Weights validation failed',
                              style: TextStyle(
                                color: _result!.validationPassed ? Colors.green[700] : Colors.orange[700],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildResultRow(String label, String? value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(fontWeight: FontWeight.w500),
          ),
          Text(
            value ?? 'Not found',
            style: TextStyle(
              color: value != null ? Colors.black : Colors.grey,
              fontWeight: value != null ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
  
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _result = null;
          _errorMessage = null;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to pick image: $e';
      });
    }
  }
  
  Future<void> _processImage() async {
    if (_selectedImage == null) return;
    
    setState(() {
      _isProcessing = true;
      _errorMessage = null;
      _result = null;
    });
    
    try {
      // First validate the image
      final validation = await WeighbridgeOCRService.validateImage(_selectedImage!);
      
      if (!validation.isValid) {
        setState(() {
          _errorMessage = 'Image validation failed:\\n${validation.issues.join('\\n')}';
          _isProcessing = false;
        });
        return;
      }
      
      // Extract weights
      final result = await WeighbridgeOCRService.extractWeights(_selectedImage!);
      
      setState(() {
        _result = result;
        _isProcessing = false;
      });
      
      // Show success message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Weights extracted successfully!'),
            backgroundColor: Colors.green,
          ),
        );
      }
      
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isProcessing = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to extract weights'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// Usage in main.dart
void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Weighbridge OCR',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: WeighbridgeOCRPage(),
    );
  }
}