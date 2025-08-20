import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:async';

const String baseUrl = 'http://54.146.215.18:3000';

class MunicipalSolidWasteDetailsPage extends StatefulWidget {
  const MunicipalSolidWasteDetailsPage({Key? key}) : super(key: key);

  @override
  _MunicipalSolidWasteDetailsPageState createState() => _MunicipalSolidWasteDetailsPageState();
}

class _MunicipalSolidWasteDetailsPageState extends State<MunicipalSolidWasteDetailsPage> 
    with TickerProviderStateMixin {
  // Animation Controllers
  late AnimationController _animationController;
  late AnimationController _pulseAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseAnimation;
  
  // Tab Controller
  late TabController _tabController;
  
  // State variables
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _isUploading = false;
  
  // Form state
  final _formKey = GlobalKey<FormState>();
  DateTime _selectedDate = DateTime.now();
  final _housesController = TextEditingController();
  final _employeesController = TextEditingController();
  
  // File upload state
  File? _vendorLicenseFile;
  File? _disposalPhotoFile;
  final ImagePicker _imagePicker = ImagePicker();
  
  // Data storage
  List<MunicipalWasteRecord> _wasteRecords = [];
  Map<String, double> _wasteStats = {};
  
  // Real-time update timer
  Timer? _refreshTimer;
  
  // Waste types definition with enhanced styling
  final List<Map<String, dynamic>> _wasteTypes = [
    {
      'key': 'dry',
      'name': 'Dry Waste',
      'icon': Icons.dry_cleaning_outlined,
      'color': Colors.orange,
      'gradient': [Colors.orange.shade400, Colors.orange.shade600],
      'generatedController': TextEditingController(),
      'disposedToController': TextEditingController(),
      'quantityController': TextEditingController(),
    },
    {
      'key': 'wet',
      'name': 'Wet Waste',
      'icon': Icons.water_drop_outlined,
      'color': Colors.blue,
      'gradient': [Colors.blue.shade400, Colors.blue.shade600],
      'generatedController': TextEditingController(),
      'disposedToController': TextEditingController(),
      'quantityController': TextEditingController(),
    },
    {
      'key': 'sanitary_napkins',
      'name': 'Sanitary Napkins',
      'icon': Icons.health_and_safety_outlined,
      'color': Colors.pink,
      'gradient': [Colors.pink.shade400, Colors.pink.shade600],
      'generatedController': TextEditingController(),
      'disposedToController': TextEditingController(),
      'quantityController': TextEditingController(),
    },
    {
      'key': 'e_waste',
      'name': 'E-Waste',
      'icon': Icons.electrical_services_outlined,
      'color': Colors.green,
      'gradient': [Colors.green.shade400, Colors.green.shade600],
      'generatedController': TextEditingController(),
      'disposedToController': TextEditingController(),
      'quantityController': TextEditingController(),
    },
    {
      'key': 'bio_medical_waste',
      'name': 'Bio Medical Waste',
      'icon': Icons.medical_services_outlined,
      'color': Colors.red,
      'gradient': [Colors.red.shade400, Colors.red.shade600],
      'generatedController': TextEditingController(),
      'disposedToController': TextEditingController(),
      'quantityController': TextEditingController(),
    },
    {
      'key': 'battery_waste',
      'name': 'Battery Waste',
      'icon': Icons.battery_alert_outlined,
      'color': Colors.amber,
      'gradient': [Colors.amber.shade400, Colors.amber.shade600],
      'generatedController': TextEditingController(),
      'disposedToController': TextEditingController(),
      'quantityController': TextEditingController(),
    },
    {
      'key': 'others',
      'name': 'Others',
      'icon': Icons.category_outlined,
      'color': Colors.grey,
      'gradient': [Colors.grey.shade400, Colors.grey.shade600],
      'generatedController': TextEditingController(),
      'disposedToController': TextEditingController(),
      'quantityController': TextEditingController(),
    },
  ];
  
  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _tabController = TabController(length: 4, vsync: this);
    _fetchInitialData();
    _startRealTimeUpdates();
  }
  
  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _pulseAnimationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _pulseAnimationController,
      curve: Curves.easeInOut,
    ));
    
    _animationController.forward();
  }
  
  void _startRealTimeUpdates() {
    _refreshTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      if (mounted && !_isLoading && !_isRefreshing) {
        _refreshData();
      }
    });
  }
  
  @override
  void dispose() {
    _animationController.dispose();
    _pulseAnimationController.dispose();
    _refreshTimer?.cancel();
    _housesController.dispose();
    _employeesController.dispose();
    for (var wasteType in _wasteTypes) {
      wasteType['generatedController'].dispose();
      wasteType['disposedToController'].dispose();
      wasteType['quantityController'].dispose();
    }
    _tabController.dispose();
    super.dispose();
  }
  
  // Safe parsing helper functions
  double _safeParseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) {
      final result = value.toDouble();
      return result.isNaN || result.isInfinite ? 0.0 : result;
    }
    if (value is String) {
      if (value.isEmpty || value.toLowerCase() == 'null') return 0.0;
      final parsed = double.tryParse(value);
      return parsed != null && !parsed.isNaN && !parsed.isInfinite ? parsed : 0.0;
    }
    return 0.0;
  }
  
  // File Upload Methods
  Future<void> _pickVendorLicense() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      
      if (pickedFile != null) {
        setState(() {
          _vendorLicenseFile = File(pickedFile.path);
        });
        _showSuccess('Vendor license selected successfully');
      }
    } catch (e) {
      _showError('Error selecting vendor license: $e');
    }
  }

  Future<void> _pickDisposalPhoto() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      
      if (pickedFile != null) {
        setState(() {
          _disposalPhotoFile = File(pickedFile.path);
        });
        _showSuccess('Disposal photo captured successfully');
      }
    } catch (e) {
      _showError('Error capturing disposal photo: $e');
    }
  }

  Future<String?> _uploadFileToS3(File file, String fileName) async {
    try {
      setState(() => _isUploading = true);
      
      var request = http.MultipartRequest(
        'POST',
        Uri.http('54.146.215.18:3000', '/upload-municipal-waste-document'),
      );
      
      request.files.add(
        await http.MultipartFile.fromPath('document', file.path, filename: fileName),
      );
      
      request.fields['document_type'] = fileName.contains('license') ? 'vendor_license' : 'disposal_photo';
      request.fields['upload_date'] = DateFormat('yyyy-MM-dd').format(DateTime.now());
      
      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      
      if (response.statusCode == 200) {
        final responseData = json.decode(response.body);
        return responseData['data']['s3_url'];
      } else {
        throw Exception('Upload failed: ${response.body}');
      }
    } catch (e) {
      _showError('File upload error: $e');
      return null;
    } finally {
      setState(() => _isUploading = false);
    }
  }
  
  // API Methods
  Future<void> _fetchInitialData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        _fetchWasteRecords(),
        _fetchWasteStats(),
      ]);
    } catch (e) {
      print('Error in _fetchInitialData: $e');
      _showError('Error loading data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _refreshData() async {
    setState(() => _isRefreshing = true);
    try {
      await Future.wait([
        _fetchWasteRecords(),
        _fetchWasteStats(),
      ]);
    } catch (e) {
      print('Error in _refreshData: $e');
      _showError('Error refreshing data: $e');
    } finally {
      setState(() => _isRefreshing = false);
    }
  }
  
  Future<void> _fetchWasteRecords() async {
    try {
      final response = await http.get(
        Uri.http('54.146.215.18:3000', '/municipal-solid-waste', {'limit': '50'}),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _wasteRecords = (data['data'] as List? ?? [])
              .map((json) => MunicipalWasteRecord.fromJson(json))
              .toList();
        });
      } else {
        throw Exception('Failed to load waste records: ${response.statusCode}');
      }
    } catch (e) {
      print('Error fetching waste records: $e');
      rethrow;
    }
  }
  
  Future<void> _fetchWasteStats() async {
    try {
      final response = await http.get(
        Uri.http('54.146.215.18:3000', '/municipal-solid-waste/stats'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final summary = data['summary'];
        if (summary != null) {
          setState(() {
            _wasteStats = {
              'totalRecords': _safeParseDouble(summary['total_records']),
              'totalWasteGenerated': _safeParseDouble(summary['total_waste_generated']),
              'totalWasteDisposed': _safeParseDouble(summary['total_waste_disposed']),
              'avgDailyWaste': _safeParseDouble(summary['avg_daily_waste']),
              'avgHousesOccupied': _safeParseDouble(summary['avg_houses_occupied']),
            };
          });
        }
      }
    } catch (e) {
      print('Error fetching stats: $e');
    }
  }
  
  Future<void> _submitWasteData() async {
    if (!_formKey.currentState!.validate()) return;
    
    // MANDATORY: Check if vendor license is uploaded
    if (_vendorLicenseFile == null) {
      _showError('Vendor license upload is mandatory for every waste disposal entry');
      return;
    }
    
    setState(() => _isLoading = true);
    try {
      // Upload files first if selected
      String? vendorLicenseUrl;
      String? disposalPhotoUrl;
      
      if (_vendorLicenseFile != null) {
        vendorLicenseUrl = await _uploadFileToS3(
          _vendorLicenseFile!,
          'vendor_license_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.jpg',
        );
      }
      
      if (_disposalPhotoFile != null) {
        disposalPhotoUrl = await _uploadFileToS3(
          _disposalPhotoFile!,
          'disposal_photo_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.jpg',
        );
      }
      
      final numEmployees = int.tryParse(_employeesController.text) ?? 0;
      final employeeGeneratedWaste = numEmployees * 0.1;
      final wasteData = {
        'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
        'no_of_houses_occupied': int.parse(_housesController.text),
        'num_employees': numEmployees,
        'employee_generated_waste': employeeGeneratedWaste,
      };
      
      // Add waste type data
      for (var wasteType in _wasteTypes) {
        final key = wasteType['key'];
        wasteData['${key}_generated_quantity'] = _safeParseDouble(wasteType['generatedController'].text);
        wasteData['${key}_disposed_to'] = wasteType['disposedToController'].text ?? '';
        wasteData['${key}_quantity'] = _safeParseDouble(wasteType['quantityController'].text);
      }
      
      // Add file URLs if uploaded
      if (vendorLicenseUrl != null) {
        wasteData['vendor_license_url'] = vendorLicenseUrl;
      }
      if (disposalPhotoUrl != null) {
        wasteData['disposal_photo_url'] = disposalPhotoUrl;
      }
      
      final response = await http.post(
        Uri.http('54.146.215.18:3000', '/municipal-solid-waste'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(wasteData),
      );
      
      if (response.statusCode == 201) {
        _showSuccess('Municipal solid waste data saved successfully');
        await _fetchWasteRecords();
        await _fetchWasteStats();
        _resetForm();
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['error'] ?? 'Failed to save data');
      }
    } catch (e) {
      print('Error submitting waste data: $e');
      _showError('Error: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _deleteRecord(int id) async {
    setState(() => _isLoading = true);
    try {
      final response = await http.delete(
        Uri.http('54.146.215.18:3000', '/municipal-solid-waste/$id'),
      );
      
      if (response.statusCode == 200) {
        _showSuccess('Record deleted successfully');
        await _fetchWasteRecords();
        await _fetchWasteStats();
      } else {
        throw Exception('Failed to delete record');
      }
    } catch (e) {
      _showError('Error: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  // UI Helper Methods
  void _resetForm() {
    _housesController.clear();
    _employeesController.clear();
    for (var wasteType in _wasteTypes) {
      wasteType['generatedController'].clear();
      wasteType['disposedToController'].clear();
      wasteType['quantityController'].clear();
    }
    setState(() {
      _selectedDate = DateTime.now();
      _vendorLicenseFile = null;
      _disposalPhotoFile = null;
    });
  }
  
  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
  
  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }
  
  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: const Color(0xFF2D5A5A),
              onPrimary: Colors.white,
              surface: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }
  
  void _showDeleteConfirmation(int id) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete Record'),
          ],
        ),
        content: const Text('Are you sure you want to delete this waste record? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteRecord(id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        primarySwatch: Colors.teal,
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: Color(0xFF2D5A5A),
          foregroundColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF2D5A5A),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            elevation: 2,
          ),
        ),
        cardTheme: CardTheme(
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
        ),
        tabBarTheme: const TabBarTheme(
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicator: UnderlineTabIndicator(
            borderSide: BorderSide(color: Colors.white, width: 3),
            insets: EdgeInsets.symmetric(horizontal: 16),
          ),
        ),
      ),
      child: Scaffold(
        appBar: _buildAppBar(),
        body: _isLoading
            ? _buildLoadingIndicator()
            : FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildAddRecordTab(),
                      _buildHistoryTab(),
                      _buildAnalyticsTab(),
                      _buildDocumentsTab(),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
  
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: const [
          Icon(Icons.delete_outline_rounded, size: 28),
          SizedBox(width: 12),
          Flexible(
            child: Text(
              'Municipal Solid Waste',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        ScaleTransition(
          scale: _pulseAnimation,
          child: Container(
            margin: const EdgeInsets.only(right: 8),
            child: _isRefreshing
                ? const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: _refreshData,
                    tooltip: 'Refresh Data',
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white.withOpacity(0.1),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
          ),
        ),
      ],
      bottom: TabBar(
        controller: _tabController,
        tabs: const [
          Tab(icon: Icon(Icons.add_circle_outline), text: 'Add Record'),
          Tab(icon: Icon(Icons.history_rounded), text: 'History'),
          Tab(icon: Icon(Icons.analytics_outlined), text: 'Analytics'),
          Tab(icon: Icon(Icons.folder_outlined), text: 'Documents'),
        ],
      ),
    );
  }
  
  Widget _buildLoadingIndicator() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFF2D5A5A).withOpacity(0.1),
            Colors.white,
          ],
        ),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2D5A5A)),
            ),
            SizedBox(height: 16),
            Text(
              'Loading waste management data...',
              style: TextStyle(
                fontSize: 16,
                color: Color(0xFF2D5A5A),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildAddRecordTab() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFF0F8FF),
            Colors.white,
          ],
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDateSelector(),
              const SizedBox(height: 20),
              _buildBasicInfoCard(),
              const SizedBox(height: 20),
              _buildWasteTableCard(),
              const SizedBox(height: 20),
              _buildFileUploadSection(),
              const SizedBox(height: 30),
              _buildSubmitButton(),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildDateSelector() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [Colors.blue.shade50, Colors.white],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D5A5A).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.calendar_today_rounded,
                  color: Color(0xFF2D5A5A),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Select Date',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2D5A5A),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      DateFormat('EEEE, MMMM d, yyyy').format(_selectedDate),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              ElevatedButton.icon(
                onPressed: _selectDate,
                icon: const Icon(Icons.edit_calendar),
                label: const Text('Change'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildBasicInfoCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [Colors.green.shade50, Colors.white],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D5A5A).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFF2D5A5A),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Basic Information',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D5A5A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _buildEnhancedTextField(
                      controller: _housesController,
                      label: 'Number of Houses Occupied',
                      icon: Icons.home_rounded,
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Required';
                        if (int.tryParse(value) == null) return 'Invalid number';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildEnhancedTextField(
                      controller: _employeesController,
                      label: 'Number of Employees',
                      icon: Icons.people_rounded,
                      keyboardType: TextInputType.number,
                      validator: (value) {
                        if (value == null || value.isEmpty) return 'Required';
                        if (int.tryParse(value) == null) return 'Invalid number';
                        return null;
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF2D5A5A).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2D5A5A).withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.info_outline,
                      color: Color(0xFF2D5A5A),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Builder(
                        builder: (context) {
                          final numEmployees = int.tryParse(_employeesController.text) ?? 0;
                          final employeeGeneratedWaste = numEmployees * 0.1;
                          return Text(
                            'Employee Generated Waste (100g/employee): ${employeeGeneratedWaste.toStringAsFixed(2)} kg',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Color(0xFF2D5A5A),
                              fontWeight: FontWeight.w600,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildEnhancedTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF2D5A5A)),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF2D5A5A), width: 2),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      ),
      onChanged: (value) => setState(() {}), // Trigger rebuild for employee waste calculation
    );
  }
  
  Widget _buildWasteTableCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [Colors.orange.shade50, Colors.white],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D5A5A).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.delete_outline_rounded,
                      color: Color(0xFF2D5A5A),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Waste Generated (in Kg)',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D5A5A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _buildEnhancedWasteTable(),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildEnhancedWasteTable() {
    return Column(
      children: _wasteTypes.map((wasteType) => _buildWasteTypeRow(wasteType)).toList(),
    );
  }
  
  Widget _buildWasteTypeRow(Map<String, dynamic> wasteType) {
    final gradient = wasteType['gradient'] as List<Color>;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [gradient[0].withOpacity(0.1), Colors.white],
        ),
        border: Border.all(color: gradient[0].withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: gradient),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    wasteType['icon'] as IconData,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  wasteType['name'] as String,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2D5A5A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildCompactTextField(
                    controller: wasteType['generatedController'],
                    label: 'Generated Qty',
                    hint: '0.0',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: _buildCompactTextField(
                    controller: wasteType['disposedToController'],
                    label: 'Disposed To',
                    hint: 'Location/Method',
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildCompactTextField(
                    controller: wasteType['quantityController'],
                    label: 'Quantity',
                    hint: '0.0',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCompactTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF2D5A5A), width: 2),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        isDense: true,
      ),
      style: const TextStyle(fontSize: 14),
    );
  }
  
  Widget _buildFileUploadSection() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [Colors.purple.shade50, Colors.white],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D5A5A).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.cloud_upload_outlined,
                      color: Color(0xFF2D5A5A),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Upload Documents',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D5A5A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _buildFileUploadCard(
                      title: 'Vendor License *',
                      subtitle: 'REQUIRED: Upload vendor license',
                      icon: Icons.assignment_outlined,
                      file: _vendorLicenseFile,
                      onTap: _pickVendorLicense,
                      color: Colors.red,
                      isRequired: true,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildFileUploadCard(
                      title: 'Disposal Photo',
                      subtitle: 'Capture disposal evidence',
                      icon: Icons.camera_alt_outlined,
                      file: _disposalPhotoFile,
                      onTap: _pickDisposalPhoto,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
              if (_isUploading) ...[
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                const Text(
                  'Uploading files to S3...',
                  style: TextStyle(color: Color(0xFF2D5A5A)),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildFileUploadCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required File? file,
    required VoidCallback onTap,
    required Color color,
    bool isRequired = false,
  }) {
    final hasFile = file != null;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: hasFile 
              ? color.withOpacity(0.1) 
              : (isRequired && !hasFile)
                  ? Colors.red.shade50
                  : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasFile 
                ? color 
                : (isRequired && !hasFile)
                    ? Colors.red.shade400
                    : Colors.grey.shade300,
            width: (hasFile || (isRequired && !hasFile)) ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: hasFile 
                    ? color 
                    : (isRequired && !hasFile)
                        ? Colors.red.shade400
                        : Colors.grey.shade400,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                hasFile 
                    ? Icons.check_circle_outline 
                    : (isRequired && !hasFile)
                        ? Icons.warning_outlined
                        : icon,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: hasFile 
                    ? color 
                    : (isRequired && !hasFile)
                        ? Colors.red.shade600
                        : Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              hasFile ? 'File selected' : subtitle,
              style: TextStyle(
                fontSize: 12,
                color: hasFile 
                    ? color 
                    : (isRequired && !hasFile)
                        ? Colors.red.shade500
                        : Colors.grey.shade500,
                fontWeight: (isRequired && !hasFile) ? FontWeight.w600 : FontWeight.normal,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isLoading || _isUploading ? null : _submitWasteData,
        icon: _isLoading || _isUploading 
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.save_rounded, size: 24),
        label: Text(
          _isLoading || _isUploading ? 'Saving...' : 'Save Waste Data',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 3,
        ),
      ),
    );
  }
  
  Widget _buildHistoryTab() {
    if (_wasteRecords.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFF0F8FF),
              Colors.white,
            ],
          ),
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.history_rounded, color: Colors.grey, size: 80),
              SizedBox(height: 24),
              Text(
                'No Waste Records Found',
                style: TextStyle(
                  fontSize: 24,
                  color: Colors.grey,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 12),
              Text(
                'Add your first record using the "Add Record" tab',
                style: TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFF0F8FF),
            Colors.white,
          ],
        ),
      ),
      child: ListView.builder(
        padding: const EdgeInsets.all(20),
        itemCount: _wasteRecords.length,
        itemBuilder: (context, index) {
          final record = _wasteRecords[index];
          return _buildEnhancedHistoryCard(record);
        },
      ),
    );
  }
  
  Widget _buildEnhancedHistoryCard(MunicipalWasteRecord record) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [Colors.white, Colors.blue.shade50],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2D5A5A).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.calendar_today_rounded,
                          color: Color(0xFF2D5A5A),
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            DateFormat('MMMM d, yyyy').format(record.date),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                              color: Color(0xFF2D5A5A),
                            ),
                          ),
                          Text(
                            DateFormat('EEEE').format(record.date),
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2D5A5A).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${record.noOfHousesOccupied} Houses',
                          style: const TextStyle(
                            color: Color(0xFF2D5A5A),
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _showDeleteConfirmation(record.id),
                        tooltip: 'Delete record',
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.red.withOpacity(0.1),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.people_rounded, color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      'Employees: ${record.numEmployees}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    const Spacer(),
                    Text(
                      'Generated: ${record.employeeGeneratedWaste.toStringAsFixed(2)} kg',
                      style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.green),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 16),
              _buildHistoryTable(record),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildHistoryTable(MunicipalWasteRecord record) {
    final wasteData = [
      {'name': 'Dry', 'generated': record.dryGeneratedQuantity, 'disposed': record.dryQuantity, 'disposedTo': record.dryDisposedTo, 'color': Colors.orange},
      {'name': 'Wet', 'generated': record.wetGeneratedQuantity, 'disposed': record.wetQuantity, 'disposedTo': record.wetDisposedTo, 'color': Colors.blue},
      {'name': 'Sanitary Napkins', 'generated': record.sanitaryNapkinsGeneratedQuantity, 'disposed': record.sanitaryNapkinsQuantity, 'disposedTo': record.sanitaryNapkinsDisposedTo, 'color': Colors.pink},
      {'name': 'E-Waste', 'generated': record.eWasteGeneratedQuantity, 'disposed': record.eWasteQuantity, 'disposedTo': record.eWasteDisposedTo, 'color': Colors.green},
      {'name': 'Bio Medical', 'generated': record.bioMedicalWasteGeneratedQuantity, 'disposed': record.bioMedicalWasteQuantity, 'disposedTo': record.bioMedicalWasteDisposedTo, 'color': Colors.red},
      {'name': 'Battery', 'generated': record.batteryWasteGeneratedQuantity, 'disposed': record.batteryWasteQuantity, 'disposedTo': record.batteryWasteDisposedTo, 'color': Colors.amber},
      {'name': 'Others', 'generated': record.othersGeneratedQuantity, 'disposed': record.othersQuantity, 'disposedTo': record.othersDisposedTo, 'color': Colors.grey},
    ];
    
    final filteredData = wasteData.where((item) => 
      (item['generated'] as double) > 0 || (item['disposed'] as double) > 0
    ).toList();
    
    if (filteredData.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: Text(
            'No waste data recorded',
            style: TextStyle(color: Colors.grey, fontSize: 16),
          ),
        ),
      );
    }
    
    return Column(
      children: filteredData.map((item) => _buildWasteDataRow(item)).toList(),
    );
  }
  
  Widget _buildWasteDataRow(Map<String, dynamic> item) {
    final color = item['color'] as Color;
    final generated = item['generated'] as double;
    final disposed = item['disposed'] as double;
    final disposedTo = item['disposedTo'] as String;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: Text(
              item['name'] as String,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
          Expanded(
            child: Text(
              '${generated.toStringAsFixed(2)} kg',
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              disposedTo.isEmpty ? 'Not specified' : disposedTo,
              style: const TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: Text(
              '${disposed.toStringAsFixed(2)} kg',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildAnalyticsTab() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFF0F8FF),
            Colors.white,
          ],
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatsCards(),
            const SizedBox(height: 24),
            _buildWasteChart(),
            const SizedBox(height: 24),
            _buildTrendAnalysis(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildStatsCards() {
    double totalEmployeeWaste = 0;
    int totalEmployees = 0;
    if (_wasteRecords.isNotEmpty) {
      totalEmployeeWaste = _wasteRecords.fold(0.0, (sum, r) => sum + r.employeeGeneratedWaste);
      totalEmployees = _wasteRecords.fold(0, (sum, r) => sum + r.numEmployees);
    }
    
    final stats = [
      {
        'title': 'Total Records',
        'value': (_wasteStats['totalRecords'] ?? 0).toInt().toString(),
        'icon': Icons.format_list_numbered_rounded,
        'color': Colors.blue,
        'gradient': [Colors.blue.shade400, Colors.blue.shade600],
      },
      {
        'title': 'Avg Houses',
        'value': (_wasteStats['avgHousesOccupied'] ?? 0).toStringAsFixed(0),
        'icon': Icons.home_rounded,
        'color': Colors.green,
        'gradient': [Colors.green.shade400, Colors.green.shade600],
      },
      {
        'title': 'Total Generated',
        'value': '${(_wasteStats['totalWasteGenerated'] ?? 0).toStringAsFixed(1)} kg',
        'icon': Icons.trending_up_rounded,
        'color': Colors.orange,
        'gradient': [Colors.orange.shade400, Colors.orange.shade600],
      },
      {
        'title': 'Total Disposed',
        'value': '${(_wasteStats['totalWasteDisposed'] ?? 0).toStringAsFixed(1)} kg',
        'icon': Icons.trending_down_rounded,
        'color': Colors.purple,
        'gradient': [Colors.purple.shade400, Colors.purple.shade600],
      },
      {
        'title': 'Total Employees',
        'value': totalEmployees.toString(),
        'icon': Icons.people_rounded,
        'color': Colors.teal,
        'gradient': [Colors.teal.shade400, Colors.teal.shade600],
      },
      {
        'title': 'Employee Waste',
        'value': '${totalEmployeeWaste.toStringAsFixed(1)} kg',
        'icon': Icons.delete_sweep_rounded,
        'color': Colors.brown,
        'gradient': [Colors.brown.shade400, Colors.brown.shade600],
      },
    ];
    
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.1,
      ),
      itemCount: stats.length,
      itemBuilder: (context, index) {
        final stat = stats[index];
        return _buildEnhancedStatCard(stat);
      },
    );
  }
  
  Widget _buildEnhancedStatCard(Map<String, dynamic> stat) {
    final gradient = stat['gradient'] as List<Color>;
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.white, gradient[0].withOpacity(0.1)],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: gradient),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  stat['icon'] as IconData,
                  size: 28,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                stat['value'] as String,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D5A5A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Flexible(
                child: Text(
                  stat['title'] as String,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade600,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildWasteChart() {
    if (_wasteRecords.isEmpty) {
      return Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          height: 250,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [Colors.white, Colors.grey.shade50],
            ),
          ),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.bar_chart_rounded, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No Data Available',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Add waste records to see analytics',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [Colors.white, Colors.blue.shade50],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2D5A5A).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.bar_chart_rounded,
                      color: Color(0xFF2D5A5A),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Waste Generation Trend',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D5A5A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                height: 200,
                child: _buildLineChart(),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildLineChart() {
    if (_wasteRecords.length < 2) {
      return const Center(
        child: Text(
          'Need at least 2 records to show trend',
          style: TextStyle(color: Colors.grey, fontSize: 16),
        ),
      );
    }
    
    final sortedRecords = List<MunicipalWasteRecord>.from(_wasteRecords)
      ..sort((a, b) => a.date.compareTo(b.date));
    
    final spots = sortedRecords.asMap().entries.map((entry) {
      final index = entry.key;
      final record = entry.value;
      final totalWaste = record.dryGeneratedQuantity + 
                        record.wetGeneratedQuantity + 
                        record.sanitaryNapkinsGeneratedQuantity +
                        record.eWasteGeneratedQuantity +
                        record.bioMedicalWasteGeneratedQuantity +
                        record.batteryWasteGeneratedQuantity +
                        record.othersGeneratedQuantity;
      return FlSpot(index.toDouble(), totalWaste);
    }).toList();
    
    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 50,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.grey.shade300,
              strokeWidth: 1,
            );
          },
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              getTitlesWidget: (value, meta) {
                return Text(
                  '${value.toInt()}kg',
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                );
              },
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index >= 0 && index < sortedRecords.length) {
                  return Text(
                    DateFormat('MM/dd').format(sortedRecords[index].date),
                    style: const TextStyle(color: Colors.grey, fontSize: 12),
                  );
                }
                return const Text('');
              },
            ),
          ),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            gradient: LinearGradient(
              colors: [const Color(0xFF2D5A5A), const Color(0xFF4A7C7D)],
            ),
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                return FlDotCirclePainter(
                  radius: 4,
                  color: Colors.white,
                  strokeWidth: 2,
                  strokeColor: const Color(0xFF2D5A5A),
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF2D5A5A).withOpacity(0.3),
                  const Color(0xFF2D5A5A).withOpacity(0.0),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildTrendAnalysis() {
    if (_wasteRecords.length < 2) return Container();
    
    final sortedRecords = List<MunicipalWasteRecord>.from(_wasteRecords)
      ..sort((a, b) => a.date.compareTo(b.date));
    
    final firstRecord = sortedRecords.first;
    final lastRecord = sortedRecords.last;
    
    final firstTotal = firstRecord.dryGeneratedQuantity + firstRecord.wetGeneratedQuantity + 
                      firstRecord.sanitaryNapkinsGeneratedQuantity + firstRecord.eWasteGeneratedQuantity +
                      firstRecord.bioMedicalWasteGeneratedQuantity + firstRecord.batteryWasteGeneratedQuantity +
                      firstRecord.othersGeneratedQuantity;
    
    final lastTotal = lastRecord.dryGeneratedQuantity + lastRecord.wetGeneratedQuantity + 
                     lastRecord.sanitaryNapkinsGeneratedQuantity + lastRecord.eWasteGeneratedQuantity +
                     lastRecord.bioMedicalWasteGeneratedQuantity + lastRecord.batteryWasteGeneratedQuantity +
                     lastRecord.othersGeneratedQuantity;
    
    final percentageChange = firstTotal > 0 ? ((lastTotal - firstTotal) / firstTotal * 100) : 0.0;
    final isIncrease = percentageChange > 0;
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [Colors.white, (isIncrease ? Colors.red : Colors.green).shade50],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: (isIncrease ? Colors.red : Colors.green).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      isIncrease ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                      color: isIncrease ? Colors.red : Colors.green,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Trend Analysis',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF2D5A5A),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Waste Generation Trend',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(
                              isIncrease ? Icons.arrow_upward : Icons.arrow_downward,
                              color: isIncrease ? Colors.red : Colors.green,
                              size: 20,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '${percentageChange.abs().toStringAsFixed(1)}%',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: isIncrease ? Colors.red : Colors.green,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isIncrease ? 'Increase' : 'Decrease',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: isIncrease ? Colors.red : Colors.green,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                'Compared to the first record (${DateFormat('MMM d').format(firstRecord.date)}) and latest record (${DateFormat('MMM d').format(lastRecord.date)})',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildDocumentsTab() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            const Color(0xFFF0F8FF),
            Colors.white,
          ],
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Document Management',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF2D5A5A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Manage vendor licenses and disposal photos',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 24),
            _buildDocumentsSummary(),
            const SizedBox(height: 24),
            _buildRecentDocuments(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDocumentsSummary() {
    return Row(
      children: [
        Expanded(
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [Colors.blue.shade50, Colors.white],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.blue.shade400, Colors.blue.shade600],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.assignment_outlined,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Vendor Licenses',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D5A5A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_wasteRecords.length} Records',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [Colors.green.shade50, Colors.white],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.green.shade400, Colors.green.shade600],
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.camera_alt_outlined,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Disposal Photos',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2D5A5A),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_wasteRecords.length} Records',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildRecentDocuments() {
    if (_wasteRecords.isEmpty) {
      return Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          height: 200,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [Colors.white, Colors.grey.shade50],
            ),
          ),
          child: const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.folder_open_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 16),
                Text(
                  'No Documents Found',
                  style: TextStyle(
                    fontSize: 18,
                    color: Colors.grey,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Upload documents when adding waste records',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [Colors.white, Colors.purple.shade50],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Recent Documents',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2D5A5A),
                ),
              ),
              const SizedBox(height: 16),
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _wasteRecords.take(5).length,
                itemBuilder: (context, index) {
                  final record = _wasteRecords[index];
                  return _buildDocumentItem(record);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildDocumentItem(MunicipalWasteRecord record) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF2D5A5A).withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.description_outlined,
              color: Color(0xFF2D5A5A),
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Record ${record.id}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('MMMM d, yyyy').format(record.date),
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'License',
                  style: TextStyle(
                    color: Colors.blue,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  'Photo',
                  style: TextStyle(
                    color: Colors.green,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Data Model (enhanced with file upload support)
class MunicipalWasteRecord {
  final int id;
  final DateTime date;
  final int noOfHousesOccupied;
  final int numEmployees;
  final double employeeGeneratedWaste;
  final double dryGeneratedQuantity;
  final String dryDisposedTo;
  final double dryQuantity;
  final double wetGeneratedQuantity;
  final String wetDisposedTo;
  final double wetQuantity;
  final double sanitaryNapkinsGeneratedQuantity;
  final String sanitaryNapkinsDisposedTo;
  final double sanitaryNapkinsQuantity;
  final double eWasteGeneratedQuantity;
  final String eWasteDisposedTo;
  final double eWasteQuantity;
  final double bioMedicalWasteGeneratedQuantity;
  final String bioMedicalWasteDisposedTo;
  final double bioMedicalWasteQuantity;
  final double batteryWasteGeneratedQuantity;
  final String batteryWasteDisposedTo;
  final double batteryWasteQuantity;
  final double othersGeneratedQuantity;
  final String othersDisposedTo;
  final double othersQuantity;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? vendorLicenseUrl;
  final String? disposalPhotoUrl;

  MunicipalWasteRecord({
    required this.id,
    required this.date,
    required this.noOfHousesOccupied,
    required this.numEmployees,
    required this.employeeGeneratedWaste,
    required this.dryGeneratedQuantity,
    required this.dryDisposedTo,
    required this.dryQuantity,
    required this.wetGeneratedQuantity,
    required this.wetDisposedTo,
    required this.wetQuantity,
    required this.sanitaryNapkinsGeneratedQuantity,
    required this.sanitaryNapkinsDisposedTo,
    required this.sanitaryNapkinsQuantity,
    required this.eWasteGeneratedQuantity,
    required this.eWasteDisposedTo,
    required this.eWasteQuantity,
    required this.bioMedicalWasteGeneratedQuantity,
    required this.bioMedicalWasteDisposedTo,
    required this.bioMedicalWasteQuantity,
    required this.batteryWasteGeneratedQuantity,
    required this.batteryWasteDisposedTo,
    required this.batteryWasteQuantity,
    required this.othersGeneratedQuantity,
    required this.othersDisposedTo,
    required this.othersQuantity,
    required this.createdAt,
    required this.updatedAt,
    this.vendorLicenseUrl,
    this.disposalPhotoUrl,
  });

  static double _safeParseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) {
      final result = value.toDouble();
      return result.isNaN || result.isInfinite ? 0.0 : result;
    }
    if (value is String) {
      if (value.isEmpty || value.toLowerCase() == 'null') return 0.0;
      final parsed = double.tryParse(value);
      return parsed != null && !parsed.isNaN && !parsed.isInfinite ? parsed : 0.0;
    }
    return 0.0;
  }

  factory MunicipalWasteRecord.fromJson(Map<String, dynamic> json) {
    return MunicipalWasteRecord(
      id: json['id'] ?? 0,
      date: DateTime.parse(json['date'] ?? DateTime.now().toIso8601String()),
      noOfHousesOccupied: json['no_of_houses_occupied'] ?? 0,
      numEmployees: json['num_employees'] ?? 0,
      employeeGeneratedWaste: _safeParseDouble(json['employee_generated_waste']),
      dryGeneratedQuantity: _safeParseDouble(json['dry_generated_quantity']),
      dryDisposedTo: json['dry_disposed_to'] ?? '',
      dryQuantity: _safeParseDouble(json['dry_quantity']),
      wetGeneratedQuantity: _safeParseDouble(json['wet_generated_quantity']),
      wetDisposedTo: json['wet_disposed_to'] ?? '',
      wetQuantity: _safeParseDouble(json['wet_quantity']),
      sanitaryNapkinsGeneratedQuantity: _safeParseDouble(json['sanitary_napkins_generated_quantity']),
      sanitaryNapkinsDisposedTo: json['sanitary_napkins_disposed_to'] ?? '',
      sanitaryNapkinsQuantity: _safeParseDouble(json['sanitary_napkins_quantity']),
      eWasteGeneratedQuantity: _safeParseDouble(json['e_waste_generated_quantity']),
      eWasteDisposedTo: json['e_waste_disposed_to'] ?? '',
      eWasteQuantity: _safeParseDouble(json['e_waste_quantity']),
      bioMedicalWasteGeneratedQuantity: _safeParseDouble(json['bio_medical_waste_generated_quantity']),
      bioMedicalWasteDisposedTo: json['bio_medical_waste_disposed_to'] ?? '',
      bioMedicalWasteQuantity: _safeParseDouble(json['bio_medical_waste_quantity']),
      batteryWasteGeneratedQuantity: _safeParseDouble(json['battery_waste_generated_quantity']),
      batteryWasteDisposedTo: json['battery_waste_disposed_to'] ?? '',
      batteryWasteQuantity: _safeParseDouble(json['battery_waste_quantity']),
      othersGeneratedQuantity: _safeParseDouble(json['others_generated_quantity']),
      othersDisposedTo: json['others_disposed_to'] ?? '',
      othersQuantity: _safeParseDouble(json['others_quantity']),
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(json['updated_at'] ?? DateTime.now().toIso8601String()),
      vendorLicenseUrl: json['vendor_license_url'],
      disposalPhotoUrl: json['disposal_photo_url'],
    );
  }
}