import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

class CementPage extends StatefulWidget {
  const CementPage({Key? key}) : super(key: key);

  @override
  State<CementPage> createState() => _CementPageState();
}

class _CementPageState extends State<CementPage> {
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  // Controllers for form fields
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();
  final TextEditingController _grossWeightController = TextEditingController();
  final TextEditingController _tareWeightController = TextEditingController();
  final TextEditingController _netWeightController = TextEditingController();
  final TextEditingController _vehicleNumberController = TextEditingController();
  final TextEditingController _driverNumberController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  
  // State variables
  File? _selectedImage;
  File? _selectedLicense;
  bool _isProcessing = false;
  bool _isUploadingLicense = false;
  bool _isLicenseUploaded = false;
  String? _errorMessage;
  Position? _currentLocation;
  
  // Platform-aware API URLs
  // For physical devices, replace 'localhost' with your computer's IP address
  // Example: 'http://192.168.1.100:8000/extract-weights'
  static const String? _customOcrUrl = null; // Set this for physical devices
  static const String? _customBackendUrl = 'http://54.146.215.18:3000/api'; // EC2 backend URL
  
  static String get _ocrApiUrl {
    if (_customOcrUrl != null) {
      return _customOcrUrl!;
    }
    
    if (Platform.isAndroid) {
      // For Android emulator, localhost maps to 10.0.2.2
      return 'http://10.0.2.2:8000/extract-weights';
    } else if (Platform.isIOS) {
      // For iOS simulator, localhost works
      return 'http://localhost:8000/extract-weights';
    } else {
      // For other platforms (web, desktop)
      return 'http://localhost:8000/extract-weights';
    }
  }
  
  static String get _backendApiUrl {
    if (_customBackendUrl != null) {
      return _customBackendUrl!;
    }
    
    if (Platform.isAndroid) {
      // For Android emulator, localhost maps to 10.0.2.2
      return 'http://10.0.2.2:3000/api';
    } else if (Platform.isIOS) {
      // For iOS simulator, localhost works
      return 'http://localhost:3000/api';
    } else {
      // For other platforms (web, desktop)
      return 'http://localhost:3000/api';
    }
  }
  
  @override
  void initState() {
    super.initState();
    _initializeData();
  }

  @override
  void dispose() {
    _dateController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _grossWeightController.dispose();
    _tareWeightController.dispose();
    _netWeightController.dispose();
    _vehicleNumberController.dispose();
    _driverNumberController.dispose();
    _contactController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    // Auto-fill current date
    _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
    
    // Auto-fill location
    await _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        _showErrorSnackBar('Location services are disabled');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          _showErrorSnackBar('Location permission denied');
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        _showErrorSnackBar('Location permissions are permanently denied');
        return;
      }

      _currentLocation = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      
      if (_currentLocation != null) {
        setState(() {
          _latitudeController.text = _currentLocation!.latitude.toStringAsFixed(6);
          _longitudeController.text = _currentLocation!.longitude.toStringAsFixed(6);
        });
      }
    } catch (e) {
      _showErrorSnackBar('Error getting location: $e');
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _errorMessage = null;
        });
        
        // Process the image with OCR
        await _processImageWithOCR();
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick image: $e');
    }
  }

  Future<bool> _testOCRConnection() async {
    try {
      print('🔍 DEBUG: Testing OCR service connection...');
      final response = await http.get(Uri.parse(_ocrApiUrl.replaceAll('/extract-weights', '/health')));
      print('🔍 DEBUG: Health check status: ${response.statusCode}');
      print('🔍 DEBUG: Health check response: ${response.body}');
      return response.statusCode == 200;
    } catch (e) {
      print('🔍 DEBUG: Health check failed: $e');
      return false;
    }
  }

  Future<void> _processImageWithOCR() async {
    if (_selectedImage == null) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    // Test connection first
    bool isConnected = await _testOCRConnection();
    if (!isConnected) {
      _showErrorSnackBar('Cannot connect to OCR service. Please check if the service is running.');
      setState(() {
        _isProcessing = false;
      });
      return;
    }

    try {
      // Debug information
      print('🔍 DEBUG: Platform: ${Platform.operatingSystem}');
      print('🔍 DEBUG: OCR URL: $_ocrApiUrl');
      print('🔍 DEBUG: Image path: ${_selectedImage!.path}');
      print('🔍 DEBUG: File exists: ${await File(_selectedImage!.path).exists()}');
      
      // Check if file exists
      if (!await File(_selectedImage!.path).exists()) {
        _showErrorSnackBar('Selected image file not found');
        return;
      }
      
      var request = http.MultipartRequest('POST', Uri.parse(_ocrApiUrl));
      
      // Add file to request
      request.files.add(await http.MultipartFile.fromPath(
        'file', 
        _selectedImage!.path,
      ));

      var response = await request.send();
      var responseBody = await response.stream.bytesToString();

      print('OCR Response Status: ${response.statusCode}');
      print('OCR Response Body: $responseBody');

      if (response.statusCode == 200) {
        var data = json.decode(responseBody);
        
        if (data['success']) {
          var weights = data['data'];
          
          setState(() {
            _grossWeightController.text = weights['gross_weight'] ?? '';
            _tareWeightController.text = weights['tare_weight'] ?? '';
            _netWeightController.text = weights['net_weight'] ?? '';
            _vehicleNumberController.text = weights['vehicle_number'] ?? '';
          });
          
          // Log what was extracted
          print('🔍 DEBUG: Extracted weights: $weights');
          if (weights['vehicle_number'] == null) {
            print('⚠️ No vehicle number found in slip - user can enter manually');
          }
          
          _showSuccessSnackBar('Weights extracted successfully!');
        } else {
          _showErrorSnackBar('OCR processing failed: ${data['message']}');
        }
      } else {
        _showErrorSnackBar('Server error: ${response.statusCode} - $responseBody');
      }
    } catch (e) {
      _showErrorSnackBar('Network error: $e');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _pickLicenseImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image != null) {
        setState(() {
          _selectedLicense = File(image.path);
          _errorMessage = null;
        });
        
        // Upload license to backend
        await _uploadLicenseToBackend();
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick license image: $e');
    }
  }

  Future<void> _pickLicenseFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'bmp', 'tiff', 'webp'],
        allowMultiple: false,
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedLicense = File(result.files.single.path!);
          _errorMessage = null;
        });
        
        // Upload license to backend
        await _uploadLicenseToBackend();
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick license file: $e');
    }
  }

  Future<void> _uploadLicenseToBackend() async {
    if (_selectedLicense == null) return;

    // Validate driver information is filled before upload
    if (_driverNumberController.text.isEmpty || _contactController.text.isEmpty) {
      _showErrorSnackBar('Please fill driver number and contact number before uploading license.');
      return;
    }

    setState(() {
      _isUploadingLicense = true;
    });

    try {
      // Test connection first
      bool isConnected = await _testBackendConnection();
      if (!isConnected) {
        _showErrorSnackBar('Cannot connect to backend service.');
        return;
      }

      print('🔍 DEBUG: Uploading license to backend...');
      print('🔍 DEBUG: License path: ${_selectedLicense!.path}');

      var request = http.MultipartRequest('POST', Uri.parse('${_backendApiUrl}/upload-license'));
      
      // Add driver info
      request.fields['driver_number'] = _driverNumberController.text;
      request.fields['contact_number'] = _contactController.text;
      
      // Add file to request
      request.files.add(await http.MultipartFile.fromPath(
        'license',
        _selectedLicense!.path,
      ));

      var response = await request.send();
      var responseBody = await response.stream.bytesToString();

      print('🔍 DEBUG: License upload status: ${response.statusCode}');
      print('🔍 DEBUG: License upload response: $responseBody');

      if (response.statusCode == 200 || response.statusCode == 201) {
        var data = json.decode(responseBody);
        setState(() {
          _isLicenseUploaded = true;
        });
        _showSuccessSnackBar('Driver license uploaded successfully!');
      } else {
        _showErrorSnackBar('License upload failed: ${response.statusCode} - $responseBody');
      }
    } catch (e) {
      print('🔍 DEBUG: License upload error: $e');
      _showErrorSnackBar('License upload error: $e');
    } finally {
      setState(() {
        _isUploadingLicense = false;
      });
    }
  }

  Future<bool> _testBackendConnection() async {
    try {
      print('🔍 DEBUG: Testing backend connection...');
      // Use the base URL without /api for health check
      String baseUrl = _backendApiUrl.replaceAll('/api', '');
      final response = await http.get(Uri.parse('$baseUrl/health'));
      print('🔍 DEBUG: Backend health check status: ${response.statusCode}');
      return response.statusCode == 200;
    } catch (e) {
      print('🔍 DEBUG: Backend health check failed: $e');
      return false;
    }
  }

  void _showImageSourceDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Select Image Source'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showLicenseSourceDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Upload Driver License'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera (Photo)'),
                subtitle: const Text('Take photo of license'),
                onTap: () {
                  Navigator.pop(context);
                  _pickLicenseImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Photo Gallery'),
                subtitle: const Text('Select image from gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickLicenseImage(ImageSource.gallery);
                },
              ),
              ListTile(
                leading: const Icon(Icons.file_present),
                title: const Text('Choose File'),
                subtitle: const Text('PDF, JPG, PNG, BMP, TIFF, WEBP'),
                onTap: () {
                  Navigator.pop(context);
                  _pickLicenseFile();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  bool _isImageFile(String filePath) {
    final extension = filePath.toLowerCase().split('.').last;
    return ['jpg', 'jpeg', 'png', 'bmp', 'tiff', 'webp'].contains(extension);
  }

  IconData _getFileIcon(String filePath) {
    final extension = filePath.toLowerCase().split('.').last;
    switch (extension) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'bmp':
      case 'tiff':
      case 'webp':
        return Icons.image;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _getFileName(String filePath) {
    return filePath.split('/').last;
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  Future<void> _submitForm() async {
    // Check if license is uploaded first (Temporarily disabled for testing)
    if (!_isLicenseUploaded) {
      _showErrorSnackBar('Driver license upload failed. Proceeding with form submission for testing.');
      // Temporarily allow submission without license for testing
      // return;
    }
    
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isProcessing = true;
      });
      
      try {
        await _submitDataToBackend();
        _showSuccessSnackBar('Cement data submitted successfully!');
        
        // Clear form after successful submission
        _clearForm();
      } catch (e) {
        _showErrorSnackBar('Failed to submit data: $e');
      } finally {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _submitDataToBackend() async {
    final data = {
      'date': _dateController.text,
      'latitude': _latitudeController.text,
      'longitude': _longitudeController.text,
      'gross_weight': _grossWeightController.text,
      'tare_weight': _tareWeightController.text,
      'net_weight': _netWeightController.text,
      'vehicle_number': _vehicleNumberController.text,
      'driver_number': _driverNumberController.text,
      'contact_number': _contactController.text,
      'timestamp': DateTime.now().toIso8601String(),
    };

    final response = await http.post(
      Uri.parse('$_backendApiUrl/cement-submissions'),
      headers: {
        'Content-Type': 'application/json',
      },
      body: json.encode(data),
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception('Server returned ${response.statusCode}: ${response.body}');
    }
  }

  void _clearForm() {
    _grossWeightController.clear();
    _tareWeightController.clear();
    _netWeightController.clear();
    _vehicleNumberController.clear();
    _driverNumberController.clear();
    _contactController.clear();
    setState(() {
      _selectedImage = null;
      _selectedLicense = null;
      _isLicenseUploaded = false;
    });
    
    // Refresh date and location
    _initializeData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cement Management'),
        backgroundColor: const Color(0xFF2E3B55),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image Upload Section
              _buildImageUploadSection(),
              const SizedBox(height: 24),
              
              // Auto-filled Information Section
              _buildAutoFilledSection(),
              const SizedBox(height: 24),
              
              // Weight Information Section
              _buildWeightSection(),
              const SizedBox(height: 24),
              
              // Vehicle Information Section
              _buildVehicleSection(),
              const SizedBox(height: 24),
              
              // Driver Information Section
              _buildDriverSection(),
              const SizedBox(height: 32),
              
              // Submit Button
              _buildSubmitButton(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImageUploadSection() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Upload Weighbridge Slip',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
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
            
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _showImageSourceDialog,
                    icon: _isProcessing
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.camera_alt),
                    label: Text(_isProcessing ? 'Processing...' : 'Upload Image'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E3B55),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              ],
            ),
            
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAutoFilledSection() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Auto-filled Information',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _dateController,
              decoration: const InputDecoration(
                labelText: 'Date',
                prefixIcon: Icon(Icons.calendar_today),
                border: OutlineInputBorder(),
              ),
              readOnly: true,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please select a date';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _latitudeController,
                    decoration: const InputDecoration(
                      labelText: 'Latitude',
                      prefixIcon: Icon(Icons.location_on),
                      border: OutlineInputBorder(),
                    ),
                    readOnly: false,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Location required';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _longitudeController,
                    decoration: const InputDecoration(
                      labelText: 'Longitude',
                      prefixIcon: Icon(Icons.location_on),
                      border: OutlineInputBorder(),
                    ),
                    readOnly: false,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Location required';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 8),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _getCurrentLocation,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh Location'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeightSection() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Weight Information (Auto-extracted)',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _grossWeightController,
              decoration: const InputDecoration(
                labelText: 'Gross Weight',
                prefixIcon: Icon(Icons.scale),
                border: OutlineInputBorder(),
                suffixText: 'KG',
              ),
              keyboardType: TextInputType.text,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Gross weight is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _tareWeightController,
              decoration: const InputDecoration(
                labelText: 'Tare Weight',
                prefixIcon: Icon(Icons.scale),
                border: OutlineInputBorder(),
                suffixText: 'KG',
              ),
              keyboardType: TextInputType.text,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Tare weight is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _netWeightController,
              decoration: const InputDecoration(
                labelText: 'Net Weight',
                prefixIcon: Icon(Icons.scale),
                border: OutlineInputBorder(),
                suffixText: 'KG',
              ),
              keyboardType: TextInputType.text,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Net weight is required';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleSection() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Vehicle Information',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                if (_vehicleNumberController.text.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Auto-extracted',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.orange,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      'Manual entry',
                      style: TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _vehicleNumberController,
              decoration: const InputDecoration(
                labelText: 'Vehicle Number',
                prefixIcon: Icon(Icons.local_shipping),
                border: OutlineInputBorder(),
                hintText: 'e.g., KA01AB1234',
              ),
              textCapitalization: TextCapitalization.characters,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Vehicle number is required';
                }
                return null;
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDriverSection() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Driver Information',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _driverNumberController,
              decoration: const InputDecoration(
                labelText: 'Driver Number',
                prefixIcon: Icon(Icons.badge),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.text,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Driver number is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            TextFormField(
              controller: _contactController,
              decoration: const InputDecoration(
                labelText: 'Contact Number',
                prefixIcon: Icon(Icons.phone),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.phone,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Contact number is required';
                }
                if (value.length < 10) {
                  return 'Please enter a valid contact number';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            
            // Driver License Upload Section (MANDATORY)
            Row(
              children: [
                const Text(
                  'Driver License',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'MANDATORY',
                    style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                  ),
                ),
                if (_isLicenseUploaded)
                  const SizedBox(width: 8),
                if (_isLicenseUploaded)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Text(
                      '✓ UPLOADED',
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            
            if (_selectedLicense != null)
              Container(
                height: 120,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _isImageFile(_selectedLicense!.path)
                      ? Image.file(
                          _selectedLicense!,
                          fit: BoxFit.cover,
                        )
                      : Container(
                          color: Colors.grey[100],
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  _getFileIcon(_selectedLicense!.path),
                                  size: 40,
                                  color: Colors.grey[600],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _getFileName(_selectedLicense!.path),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                    fontWeight: FontWeight.w500,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ),
                ),
              ),
            
            const SizedBox(height: 8),
            
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isUploadingLicense ? null : _showLicenseSourceDialog,
                    icon: _isUploadingLicense
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file),
                    label: Text(_isUploadingLicense 
                        ? 'Uploading...' 
                        : _isLicenseUploaded 
                          ? '✓ License Uploaded' 
                          : (_selectedLicense != null ? 'Change License' : 'Upload License')),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isLicenseUploaded ? Colors.green : (_selectedLicense != null ? Colors.orange : const Color(0xFF2E3B55)),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isProcessing ? null : _submitForm,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isLicenseUploaded ? const Color(0xFF2E3B55) : Colors.grey,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: _isProcessing
            ? const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  SizedBox(width: 12),
                  Text(
                    'Submitting...',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              )
            : Text(
                _isLicenseUploaded ? 'Submit Cement Data' : 'Upload License First',
                style: TextStyle(
                  fontSize: 18, 
                  fontWeight: FontWeight.bold,
                  color: _isLicenseUploaded ? Colors.white : Colors.white70
                ),
              ),
      ),
    );
  }
}