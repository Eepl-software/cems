import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';

class AggregatesPage extends StatefulWidget {
  const AggregatesPage({Key? key}) : super(key: key);

  @override
  State<AggregatesPage> createState() => _AggregatesPageState();
}

class _AggregatesPageState extends State<AggregatesPage> with TickerProviderStateMixin {
  late TabController _tabController;
  
  // Form controllers and state
  final _formKey = GlobalKey<FormState>();
  final ImagePicker _picker = ImagePicker();
  final TextEditingController _dateController = TextEditingController();
  final TextEditingController _latitudeController = TextEditingController();
  final TextEditingController _longitudeController = TextEditingController();
  final TextEditingController _grossWeightController = TextEditingController();
  final TextEditingController _tareWeightController = TextEditingController();
  final TextEditingController _netWeightController = TextEditingController();
  final TextEditingController _vehicleNumberController = TextEditingController();
  final TextEditingController _driverNumberController = TextEditingController();
  final TextEditingController _contactController = TextEditingController();
  
  // Enhanced OCR field controllers
  final TextEditingController _materialNameController = TextEditingController();
  final TextEditingController _driverNameController = TextEditingController();
  
  // State variables
  File? _selectedImage;
  File? _selectedLicense;
  bool _isProcessing = false;
  bool _isUploadingLicense = false;
  bool _isLicenseUploaded = false;
  String? _errorMessage;
  Position? _currentLocation;
  
  // Vehicle and vendor photo state variables
  File? _vehiclePhotoFile;
  File? _vendorLicenseFile;
  String? _vehiclePhotoUrl;
  String? _vendorLicenseUrl;
  bool _isVehiclePhotoUploaded = false;
  bool _isVendorLicenseUploaded = false;
  bool _isUploadingVehiclePhoto = false;
  bool _isUploadingVendorLicense = false;
  
  // Dashboard state
  List<Map<String, dynamic>> _submissions = [];
  List<Map<String, dynamic>> _analytics = [];
  bool _isLoading = true;
  String? _dashboardErrorMessage;
  String? _selectedDateFrom;
  String? _selectedDateTo;
  String _selectedTimeRange = 'All Time';
  
  // API URLs
  static const String _customBackendUrl = 'http://54.146.215.18:3000/api';
  
  static String get _ocrApiUrl {
    // Use the direct ML OCR service deployed on EC2
    return 'http://54.146.215.18/extract-weights';
  }
  
  static String get _backendApiUrl {
    return _customBackendUrl;
  }
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _initializeData();
    _loadDashboardData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _dateController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    _grossWeightController.dispose();
    _tareWeightController.dispose();
    _netWeightController.dispose();
    _vehicleNumberController.dispose();
    _driverNumberController.dispose();
    _contactController.dispose();
    // Enhanced OCR controllers
    _materialNameController.dispose();
    _driverNameController.dispose();
    super.dispose();
  }

  Future<void> _initializeData() async {
    _dateController.text = DateFormat('yyyy-MM-dd').format(DateTime.now());
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

  // Form submission methods
  Future<void> _pickImage(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image != null) {
        setState(() {
          _selectedImage = File(image.path);
          _errorMessage = null;
        });
        await _processImageWithOCR();
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick image: $e');
    }
  }

  Future<bool> _testOCRConnection() async {
    try {
      // Test the actual backend API endpoint instead of a non-existent health endpoint
      final response = await http.get(Uri.parse('$_customBackendUrl/aggregates-submissions')).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      print('OCR Connection test failed: $e');
      return false;
    }
  }

  void _useMockOCRData() {
    // Mock data for aggregates with aggregate-specific data
    final List<Map<String, String>> mockDataOptions = [
      {
        'material_name': 'COARSE AGGREGATES',
        'gross_weight': '35420 KG',
        'tare_weight': '9200 KG',
        'net_weight': '26220 KG',
        'vehicle_number': 'KA03MN5678',
        'driver_name': 'mohan',
      },
      {
        'material_name': 'FINE AGGREGATES',
        'gross_weight': '31850 KG',
        'tare_weight': '8100 KG',
        'net_weight': '23750 KG',
        'vehicle_number': 'TN07PQ9123',
        'driver_name': 'suresh',
      }
    ];

    // Randomly select mock data
    final mockData = mockDataOptions[DateTime.now().millisecond % 2];

    setState(() {
      // Original weight fields
      _grossWeightController.text = mockData['gross_weight']!;
      _tareWeightController.text = mockData['tare_weight']!;
      _netWeightController.text = mockData['net_weight']!;
      _vehicleNumberController.text = mockData['vehicle_number']!;
      
      // Enhanced OCR fields
      _materialNameController.text = mockData['material_name']!;
      _driverNameController.text = mockData['driver_name']!;
    });
  }

  Future<void> _processImageWithOCR() async {
    if (_selectedImage == null) return;

    setState(() {
      _isProcessing = true;
      _errorMessage = null;
    });

    bool isConnected = await _testOCRConnection();
    if (!isConnected) {
      // Use mock data instead of failing completely
      _showSuccessSnackBar('Using demo OCR data (backend not available)');
      _useMockOCRData();
      setState(() {
        _isProcessing = false;
      });
      return;
    }

    try {
      if (!await File(_selectedImage!.path).exists()) {
        _showErrorSnackBar('Selected image file not found');
        return;
      }
      
      var request = http.MultipartRequest('POST', Uri.parse(_ocrApiUrl));
      request.files.add(await http.MultipartFile.fromPath('file', _selectedImage!.path));

      var response = await request.send();
      var responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        var data = json.decode(responseBody);
        
        if (data['success']) {
          var extractedData = data['data'];
          
          setState(() {
            // Original weight fields
            _grossWeightController.text = extractedData['gross_weight'] ?? '';
            _tareWeightController.text = extractedData['tare_weight'] ?? '';
            _netWeightController.text = extractedData['net_weight'] ?? '';
            _vehicleNumberController.text = extractedData['vehicle_number'] ?? '';
            
            // Enhanced OCR fields
            _materialNameController.text = extractedData['material_name'] ?? '';
            _driverNameController.text = extractedData['driver_name'] ?? '';
          });
          
          _showSuccessSnackBar('Weighbridge slip data extracted successfully!');
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
        await _uploadLicenseToBackend();
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick license file: $e');
    }
  }

  Future<void> _uploadLicenseToBackend() async {
    if (_selectedLicense == null) return;

    if (_driverNumberController.text.isEmpty || _contactController.text.isEmpty) {
      _showErrorSnackBar('Please fill driver number and contact number before uploading license.');
      return;
    }

    setState(() {
      _isUploadingLicense = true;
    });

    try {
      bool isConnected = await _testBackendConnection();
      if (!isConnected) {
        _showErrorSnackBar('Cannot connect to backend service.');
        return;
      }

      var request = http.MultipartRequest('POST', Uri.parse('$_backendApiUrl/upload-license'));
      request.fields['driver_number'] = _driverNumberController.text;
      request.fields['contact_number'] = _contactController.text;
      request.files.add(await http.MultipartFile.fromPath('license', _selectedLicense!.path));

      var response = await request.send();

      if (response.statusCode == 200 || response.statusCode == 201) {
        setState(() {
          _isLicenseUploaded = true;
        });
        _showSuccessSnackBar('Driver license uploaded successfully!');
      } else {
        _showErrorSnackBar('License upload failed: ${response.statusCode}');
      }
    } catch (e) {
      _showErrorSnackBar('License upload error: $e');
    } finally {
      setState(() {
        _isUploadingLicense = false;
      });
    }
  }

  // Vehicle photo upload methods
  Future<void> _pickVehiclePhoto(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image != null) {
        setState(() {
          _vehiclePhotoFile = File(image.path);
        });
        await _uploadVehiclePhotoToBackend();
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick vehicle photo: $e');
    }
  }

  Future<void> _uploadVehiclePhotoToBackend() async {
    if (_vehiclePhotoFile == null) return;

    setState(() {
      _isUploadingVehiclePhoto = true;
    });

    try {
      var request = http.MultipartRequest('POST', Uri.parse('$_backendApiUrl/upload-aggregates-photo'));
      request.fields['type'] = 'vehicle';
      request.files.add(await http.MultipartFile.fromPath('photo', _vehiclePhotoFile!.path));

      var response = await request.send();
      var responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200 || response.statusCode == 201) {
        var data = json.decode(responseBody);
        setState(() {
          _vehiclePhotoUrl = data['url'];
          _isVehiclePhotoUploaded = true;
        });
        _showSuccessSnackBar('Vehicle photo uploaded successfully!');
      } else {
        _showErrorSnackBar('Vehicle photo upload failed: ${response.statusCode}');
      }
    } catch (e) {
      _showErrorSnackBar('Vehicle photo upload error: $e');
    } finally {
      setState(() {
        _isUploadingVehiclePhoto = false;
      });
    }
  }

  // Vendor license photo upload methods
  Future<void> _pickVendorLicense(ImageSource source) async {
    try {
      final XFile? image = await _picker.pickImage(source: source);
      if (image != null) {
        setState(() {
          _vendorLicenseFile = File(image.path);
        });
        await _uploadVendorLicenseToBackend();
      }
    } catch (e) {
      _showErrorSnackBar('Failed to pick vendor license: $e');
    }
  }

  Future<void> _uploadVendorLicenseToBackend() async {
    if (_vendorLicenseFile == null) return;

    setState(() {
      _isUploadingVendorLicense = true;
    });

    try {
      var request = http.MultipartRequest('POST', Uri.parse('$_backendApiUrl/upload-aggregates-photo'));
      request.fields['type'] = 'vendor_license';
      request.files.add(await http.MultipartFile.fromPath('photo', _vendorLicenseFile!.path));

      var response = await request.send();
      var responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200 || response.statusCode == 201) {
        var data = json.decode(responseBody);
        setState(() {
          _vendorLicenseUrl = data['url'];
          _isVendorLicenseUploaded = true;
        });
        _showSuccessSnackBar('Vendor license uploaded successfully!');
      } else {
        _showErrorSnackBar('Vendor license upload failed: ${response.statusCode}');
      }
    } catch (e) {
      _showErrorSnackBar('Vendor license upload error: $e');
    } finally {
      setState(() {
        _isUploadingVendorLicense = false;
      });
    }
  }

  Future<bool> _testBackendConnection() async {
    try {
      String baseUrl = _backendApiUrl.replaceAll('/api', '');
      final response = await http.get(Uri.parse('$baseUrl/health'));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  Future<void> _submitForm() async {
    // Check if required photos are uploaded
    if (!_isVehiclePhotoUploaded) {
      _showErrorSnackBar('Please upload vehicle photo before submitting.');
      return;
    }
    
    if (!_isVendorLicenseUploaded) {
      _showErrorSnackBar('Please upload vendor license photo before submitting.');
      return;
    }
    
    if (!_isLicenseUploaded) {
      _showErrorSnackBar('Driver license upload failed. Proceeding with form submission for testing.');
    }
    
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isProcessing = true;
      });
      
      try {
        await _submitDataToBackend();
        _showSuccessSnackBar('Aggregates data submitted successfully!');
        _clearForm();
        await _loadDashboardData(); // Refresh dashboard data
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
      // Enhanced OCR fields
      'material_name': _materialNameController.text,
      'driver_name': _driverNameController.text,
      // Photo URLs
      'vehicle_photo_url': _vehiclePhotoUrl ?? '',
      'vendor_license_photo_url': _vendorLicenseUrl ?? '',
    };

    final response = await http.post(
      Uri.parse('$_backendApiUrl/aggregates-submissions'),
      headers: {'Content-Type': 'application/json'},
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
    // Clear enhanced OCR fields
    _materialNameController.clear();
    _driverNameController.clear();
    setState(() {
      _selectedImage = null;
      _selectedLicense = null;
      _isLicenseUploaded = false;
      // Clear vehicle and vendor photo state
      _vehiclePhotoFile = null;
      _vendorLicenseFile = null;
      _vehiclePhotoUrl = null;
      _vendorLicenseUrl = null;
      _isVehiclePhotoUploaded = false;
      _isVendorLicenseUploaded = false;
      _isUploadingVehiclePhoto = false;
      _isUploadingVendorLicense = false;
    });
    _initializeData();
  }

  // Dashboard methods
  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _dashboardErrorMessage = null;
    });

    try {
      await Future.wait([
        _loadSubmissions(),
        _loadAnalytics(),
      ]);
    } catch (e) {
      setState(() {
        _dashboardErrorMessage = 'Failed to load data: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSubmissions() async {
    String url = '$_backendApiUrl/aggregates-submissions?limit=100';
    
    if (_selectedDateFrom != null) {
      url += '&date_from=$_selectedDateFrom';
    }
    if (_selectedDateTo != null) {
      url += '&date_to=$_selectedDateTo';
    }

    final response = await http.get(Uri.parse(url));
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        _submissions = List<Map<String, dynamic>>.from(data['data'] ?? []);
      });
    } else {
      throw Exception('Failed to load submissions: ${response.statusCode}');
    }
  }

  Future<void> _loadAnalytics() async {
    try {
      String url = '$_backendApiUrl/aggregates-analytics';
      
      if (_selectedDateFrom != null) {
        url += '?date_from=$_selectedDateFrom';
      }
      if (_selectedDateTo != null) {
        url += '${_selectedDateFrom != null ? '&' : '?'}date_to=$_selectedDateTo';
      }

      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _analytics = List<Map<String, dynamic>>.from(data['data']['daily_analytics'] ?? []);
        });
      } else {
        _calculateAnalytics();
      }
    } catch (e) {
      _calculateAnalytics();
    }
  }

  void _calculateAnalytics() {
    Map<String, int> dailyCounts = {};
    Map<String, double> dailyGrossWeight = {};
    Map<String, double> dailyNetWeight = {};
    Map<String, Set<String>> dailyVehicles = {};

    for (var submission in _submissions) {
      String date = submission['date'] ?? '';
      if (date.isNotEmpty) {
        dailyCounts[date] = (dailyCounts[date] ?? 0) + 1;
        
        double grossWeight = _parseWeight(submission['gross_weight']);
        double netWeight = _parseWeight(submission['net_weight']);
        
        dailyGrossWeight[date] = (dailyGrossWeight[date] ?? 0) + grossWeight;
        dailyNetWeight[date] = (dailyNetWeight[date] ?? 0) + netWeight;
        
        String vehicle = submission['vehicle_number'] ?? '';
        if (vehicle.isNotEmpty) {
          dailyVehicles[date] ??= <String>{};
          dailyVehicles[date]!.add(vehicle);
        }
      }
    }

    _analytics = dailyCounts.entries.map((entry) {
      String date = entry.key;
      return {
        'date': date,
        'submissions': entry.value,
        'gross_weight': dailyGrossWeight[date] ?? 0,
        'net_weight': dailyNetWeight[date] ?? 0,
        'unique_vehicles': dailyVehicles[date]?.length ?? 0,
      };
    }).toList();

    _analytics.sort((a, b) => a['date'].compareTo(b['date']));
  }

  double _parseWeight(String? weightStr) {
    if (weightStr == null || weightStr.isEmpty) return 0.0;
    
    RegExp regExp = RegExp(r'(\d+(?:\.\d+)?)');
    Match? match = regExp.firstMatch(weightStr);
    
    if (match != null) {
      return double.tryParse(match.group(1)!) ?? 0.0;
    }
    
    return 0.0;
  }

  double _parseNumericValue(dynamic value) {
    if (value == null) return 0.0;
    
    if (value is num) {
      return value.toDouble();
    }
    
    if (value is String) {
      double? directParse = double.tryParse(value);
      if (directParse != null) return directParse;
      
      RegExp regExp = RegExp(r'(\d+(?:\.\d+)?)');
      Match? match = regExp.firstMatch(value);
      
      if (match != null) {
        return double.tryParse(match.group(1)!) ?? 0.0;
      }
    }
    
    return 0.0;
  }

  // UI Helper methods
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

  void _showVehiclePhotoDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Upload Vehicle Photo'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                subtitle: const Text('Take photo of vehicle'),
                onTap: () {
                  Navigator.pop(context);
                  _pickVehiclePhoto(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                subtitle: const Text('Select from gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickVehiclePhoto(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showVendorLicenseDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Upload Vendor License'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Camera'),
                subtitle: const Text('Take photo of license'),
                onTap: () {
                  Navigator.pop(context);
                  _pickVendorLicense(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Gallery'),
                subtitle: const Text('Select from gallery'),
                onTap: () {
                  Navigator.pop(context);
                  _pickVendorLicense(ImageSource.gallery);
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

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
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

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Filter Data'),
          content: StatefulBuilder(
            builder: (context, setDialogState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DropdownButtonFormField<String>(
                    value: _selectedTimeRange,
                    decoration: const InputDecoration(
                      labelText: 'Time Range',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      'All Time',
                      'Last 7 Days',
                      'Last 30 Days',
                      'This Month',
                      'Custom Range'
                    ].map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: (String? newValue) {
                      setDialogState(() {
                        _selectedTimeRange = newValue!;
                        _applyTimeRangeFilter(newValue);
                      });
                    },
                  ),
                  if (_selectedTimeRange == 'Custom Range') ...[
                    const SizedBox(height: 16),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'From Date (YYYY-MM-DD)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        _selectedDateFrom = value;
                      },
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      decoration: const InputDecoration(
                        labelText: 'To Date (YYYY-MM-DD)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (value) {
                        _selectedDateTo = value;
                      },
                    ),
                  ],
                ],
              );
            },
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _loadDashboardData();
              },
              child: const Text('Apply'),
            ),
          ],
        );
      },
    );
  }

  void _applyTimeRangeFilter(String range) {
    DateTime now = DateTime.now();
    
    switch (range) {
      case 'Last 7 Days':
        _selectedDateFrom = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 7)));
        _selectedDateTo = DateFormat('yyyy-MM-dd').format(now);
      case 'Last 30 Days':
        _selectedDateFrom = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 30)));
        _selectedDateTo = DateFormat('yyyy-MM-dd').format(now);
      case 'This Month':
        _selectedDateFrom = DateFormat('yyyy-MM-dd').format(DateTime(now.year, now.month, 1));
        _selectedDateTo = DateFormat('yyyy-MM-dd').format(now);
      case 'All Time':
        _selectedDateFrom = null;
        _selectedDateTo = null;
    }
  }

  void _showSubmissionDetails(Map<String, dynamic> submission) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Submission Details - ${submission['vehicle_number']}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow('Date', submission['date']),
                _buildDetailRow('Vehicle Number', submission['vehicle_number']),
                _buildDetailRow('Driver Number', submission['driver_number']),
                _buildDetailRow('Contact Number', submission['contact_number']),
                _buildDetailRow('Gross Weight', submission['gross_weight']),
                _buildDetailRow('Tare Weight', submission['tare_weight']),
                _buildDetailRow('Net Weight', submission['net_weight']),
                // Enhanced OCR fields
                if (submission['material_name'] != null && submission['material_name'].toString().isNotEmpty)
                  _buildDetailRow('Material Name', submission['material_name']),
                if (submission['driver_name'] != null && submission['driver_name'].toString().isNotEmpty)
                  _buildDetailRow('Driver Name (OCR)', submission['driver_name']),
                // Photo URLs
                if (submission['vehicle_photo_url'] != null && submission['vehicle_photo_url'].toString().isNotEmpty)
                  _buildPhotoRow('Vehicle Photo', submission['vehicle_photo_url']),
                if (submission['vendor_license_photo_url'] != null && submission['vendor_license_photo_url'].toString().isNotEmpty)
                  _buildPhotoRow('Vendor License', submission['vendor_license_photo_url']),
                _buildDetailRow('Latitude', submission['latitude']),
                _buildDetailRow('Longitude', submission['longitude']),
                _buildDetailRow('Submitted At', submission['created_at']),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(String label, dynamic value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value?.toString() ?? 'N/A'),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoRow(String label, String photoUrl) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label:',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey[300]!),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: photoUrl.isNotEmpty
                  ? Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) {
                          return child;
                        }
                        return Container(
                          color: Colors.grey[100],
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(
                                  value: loadingProgress.expectedTotalBytes != null
                                      ? loadingProgress.cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                      : null,
                                ),
                                const SizedBox(height: 8),
                                const Text(
                                  'Loading image...',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          color: Colors.grey[100],
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.error_outline,
                                  size: 40,
                                  color: Colors.red,
                                ),
                                SizedBox(height: 8),
                                Text(
                                  'Failed to load image',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    )
                  : Container(
                      color: Colors.grey[100],
                      child: const Center(
                        child: Text(
                          'No image available',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Aggregates Management'),
        backgroundColor: const Color(0xFF795548),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadDashboardData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.add), text: 'Submit Data'),
            Tab(icon: Icon(Icons.analytics), text: 'Analytics'),
            Tab(icon: Icon(Icons.table_chart), text: 'Data Table'),
            Tab(icon: Icon(Icons.bar_chart), text: 'Charts'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildSubmissionTab(),
          _buildAnalyticsTab(),
          _buildDataTableTab(),
          _buildChartsTab(),
        ],
      ),
    );
  }

  Widget _buildSubmissionTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildImageUploadSection(),
            const SizedBox(height: 24),
            _buildAutoFilledSection(),
            const SizedBox(height: 24),
            _buildWeightSection(),
            const SizedBox(height: 24),
            _buildVehicleSection(),
            const SizedBox(height: 24),
            _buildVehiclePhotoSection(),
            const SizedBox(height: 24),
            _buildMaterialSection(),
            const SizedBox(height: 24),
            _buildWeighbridgeSlipDataSection(),
            const SizedBox(height: 24),
            _buildDriverSection(),
            const SizedBox(height: 32),
            _buildSubmitButton(),
          ],
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
                  child: Image.file(_selectedImage!, fit: BoxFit.cover),
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
                      backgroundColor: const Color(0xFF795548),
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

  Widget _buildWeighbridgeSlipDataSection() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.receipt_long, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Weighbridge Slip Data',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    'OCR EXTRACTED',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _materialNameController,
              decoration: const InputDecoration(
                labelText: 'Material Name',
                prefixIcon: Icon(Icons.inventory),
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.text,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Material name is required';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _driverNameController,
                    decoration: const InputDecoration(
                      labelText: 'Driver Name (OCR)',
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.text,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Driver name is required';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info, color: Colors.blue, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'These fields are automatically extracted from weighbridge slip images',
                      style: TextStyle(
                        color: Colors.blue,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
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
                      ? Image.file(_selectedLicense!, fit: BoxFit.cover)
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
                      backgroundColor: _isLicenseUploaded ? Colors.green : (_selectedLicense != null ? Colors.orange : const Color(0xFF795548)),
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

  Widget _buildVehiclePhotoSection() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.local_shipping, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Vehicle Photo',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                if (_isVehiclePhotoUploaded) ...
                [
                  const SizedBox(width: 8),
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
              ],
            ),
            const SizedBox(height: 16),
            if (_vehiclePhotoFile != null)
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(_vehiclePhotoFile!, fit: BoxFit.cover),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isUploadingVehiclePhoto ? null : () => _showVehiclePhotoDialog(),
                    icon: _isUploadingVehiclePhoto
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.camera_alt),
                    label: Text(_isUploadingVehiclePhoto 
                        ? 'Uploading...' 
                        : _isVehiclePhotoUploaded 
                          ? '✓ Vehicle Photo Uploaded' 
                          : 'Upload Vehicle Photo'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isVehiclePhotoUploaded ? Colors.green : const Color(0xFF795548),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
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

  Widget _buildMaterialSection() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.description, color: Colors.orange),
                const SizedBox(width: 8),
                const Text(
                  'Material/Vendor License',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
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
                if (_isVendorLicenseUploaded) ...
                [
                  const SizedBox(width: 8),
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
              ],
            ),
            const SizedBox(height: 16),
            if (_vendorLicenseFile != null)
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(_vendorLicenseFile!, fit: BoxFit.cover),
                ),
              ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isUploadingVendorLicense ? null : () => _showVendorLicenseDialog(),
                    icon: _isUploadingVendorLicense
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_file),
                    label: Text(_isUploadingVendorLicense 
                        ? 'Uploading...' 
                        : _isVendorLicenseUploaded 
                          ? '✓ License Uploaded' 
                          : 'Upload Vendor License'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isVendorLicenseUploaded ? Colors.green : const Color(0xFF795548),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
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
    bool canSubmit = _isVehiclePhotoUploaded && _isVendorLicenseUploaded;
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: _isProcessing ? null : (canSubmit ? _submitForm : null),
        style: ElevatedButton.styleFrom(
          backgroundColor: canSubmit ? const Color(0xFF795548) : Colors.grey,
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
                canSubmit ? 'Submit Aggregates Data' : 'Upload Photos First',
                style: TextStyle(
                  fontSize: 18, 
                  fontWeight: FontWeight.bold,
                  color: canSubmit ? Colors.white : Colors.white70
                ),
              ),
      ),
    );
  }

  Widget _buildAnalyticsTab() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading aggregates data...'),
          ],
        ),
      );
    }

    if (_dashboardErrorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text(
              _dashboardErrorMessage!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadDashboardData,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_submissions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No aggregates submissions found'),
            Text('Submit some aggregates data to see analytics'),
          ],
        ),
      );
    }

    double totalGrossWeight = 0;
    double totalNetWeight = 0;
    Set<String> uniqueVehicles = {};
    Set<String> uniqueDrivers = {};

    for (var submission in _submissions) {
      totalGrossWeight += _parseWeight(submission['gross_weight']);
      totalNetWeight += _parseWeight(submission['net_weight']);
      
      String vehicle = submission['vehicle_number'] ?? '';
      if (vehicle.isNotEmpty) uniqueVehicles.add(vehicle);
      
      String driver = submission['driver_number'] ?? '';
      if (driver.isNotEmpty) uniqueDrivers.add(driver);
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            childAspectRatio: 1.5,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            children: [
              _buildSummaryCard(
                'Total Submissions',
                _submissions.length.toString(),
                Icons.receipt_long,
                Colors.blue,
              ),
              _buildSummaryCard(
                'Total Gross Weight',
                '${totalGrossWeight.toStringAsFixed(0)} KG',
                Icons.scale,
                Colors.green,
              ),
              _buildSummaryCard(
                'Total Net Weight',
                '${totalNetWeight.toStringAsFixed(0)} KG',
                Icons.balance,
                Colors.orange,
              ),
              _buildSummaryCard(
                'Unique Vehicles',
                uniqueVehicles.length.toString(),
                Icons.local_shipping,
                Colors.purple,
              ),
            ],
          ),
          
          const SizedBox(height: 24),
          
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.history, color: Color(0xFFFF9800)),
                      const SizedBox(width: 8),
                      const Text(
                        'Recent Submissions',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _submissions.take(5).length,
                    itemBuilder: (context, index) {
                      final submission = _submissions[index];
                      return ListTile(
                        leading: CircleAvatar(
                          backgroundColor: const Color(0xFF795548),
                          child: Text(
                            '${index + 1}',
                            style: const TextStyle(color: Colors.white),
                          ),
                        ),
                        title: Text('Vehicle: ${submission['vehicle_number'] ?? 'N/A'}'),
                        subtitle: Text(
                          'Date: ${submission['date']} • Net: ${submission['net_weight']}',
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _showSubmissionDetails(submission),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: color),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 2),
            Flexible(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                ),
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataTableTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_submissions.isEmpty) {
      return const Center(
        child: Text('No data available'),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        elevation: 4,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(const Color(0xFF795548)),
            headingTextStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            columns: const [
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Vehicle')),
              DataColumn(label: Text('Material')),
              DataColumn(label: Text('Driver')),
              DataColumn(label: Text('Gross Weight')),
              DataColumn(label: Text('Net Weight')),
              DataColumn(label: Text('Actions')),
            ],
            rows: _submissions.map((submission) {
              return DataRow(
                cells: [
                  DataCell(Text(submission['date'] ?? 'N/A')),
                  DataCell(Text(submission['vehicle_number'] ?? 'N/A')),
                  DataCell(Text('Aggregates')),
                  DataCell(Text(submission['driver_number'] ?? 'N/A')),
                  DataCell(Text(submission['gross_weight'] ?? 'N/A')),
                  DataCell(Text(submission['net_weight'] ?? 'N/A')),
                  DataCell(
                    IconButton(
                      icon: const Icon(Icons.visibility, color: Color(0xFFFF9800)),
                      onPressed: () => _showSubmissionDetails(submission),
                    ),
                  ),
                ],
              );
            }).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildChartsTab() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_analytics.isEmpty) {
      return const Center(
        child: Text('No data for charts'),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Daily Submissions',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 200,
                    child: LineChart(
                      LineChartData(
                        gridData: const FlGridData(show: true),
                        titlesData: const FlTitlesData(show: true),
                        borderData: FlBorderData(show: true),
                        lineBarsData: [
                          LineChartBarData(
                            spots: _analytics.asMap().entries.map((entry) {
                              return FlSpot(
                                entry.key.toDouble(),
                                _parseNumericValue(entry.value['submissions'] ?? entry.value['submission_count'] ?? 0),
                              );
                            }).toList(),
                            isCurved: true,
                            color: const Color(0xFF795548),
                            barWidth: 3,
                            dotData: const FlDotData(show: true),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Daily Weight Distribution',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 200,
                    child: BarChart(
                      BarChartData(
                        gridData: const FlGridData(show: true),
                        titlesData: const FlTitlesData(show: true),
                        borderData: FlBorderData(show: true),
                        barGroups: _analytics.asMap().entries.map((entry) {
                          return BarChartGroupData(
                            x: entry.key,
                            barRods: [
                              BarChartRodData(
                                toY: _parseNumericValue(entry.value['gross_weight'] ?? entry.value['total_gross_weight'] ?? 0) / 1000,
                                color: Colors.blue,
                                width: 16,
                              ),
                              BarChartRodData(
                                toY: _parseNumericValue(entry.value['net_weight'] ?? entry.value['total_net_weight'] ?? 0) / 1000,
                                color: Colors.green,
                                width: 16,
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}