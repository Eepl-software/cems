import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

// Safe parsing helper function
double safeParseDouble(dynamic value) {
  if (value == null) return 0.0;
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) {
    final cleanValue = value.toString().trim();
    if (cleanValue.isEmpty) return 0.0;
    return double.tryParse(cleanValue) ?? 0.0;
  }
  if (value is num) return value.toDouble();
  return 0.0;
}

// API Service for Water Tanker Records
class WaterTankerApiService {
  static const String baseUrl = 'http://54.146.215.18:3000/api/water-tanker-records';
  
  // Create new water tanker record
  static Future<Map<String, dynamic>?> createRecord({
    required String tankerNumber,
    required int tankerCapacityLiters,
    String waterType = 'Treated Water',
    File? tankerPhoto,
    File? vendorLicense,
    File? vehicleRc,
    File? entryPhoto,
    File? exitPhoto,
    double? gpsLatitude,
    double? gpsLongitude,
    DateTime? gpsCapturedAt,
  }) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse(baseUrl));
      
      // Add form fields
      request.fields['tanker_number'] = tankerNumber;
      request.fields['tanker_capacity_liters'] = tankerCapacityLiters.toString();
      request.fields['water_type'] = waterType;
      
      if (gpsLatitude != null) {
        request.fields['gps_latitude'] = gpsLatitude.toString();
      }
      if (gpsLongitude != null) {
        request.fields['gps_longitude'] = gpsLongitude.toString();
      }
      if (gpsCapturedAt != null) {
        request.fields['gps_captured_at'] = gpsCapturedAt.toIso8601String();
      }
      
      // Add file attachments
      if (tankerPhoto != null) {
        request.files.add(await http.MultipartFile.fromPath('tanker_photo', tankerPhoto.path));
      }
      if (vendorLicense != null) {
        request.files.add(await http.MultipartFile.fromPath('vendor_license', vendorLicense.path));
      }
      if (vehicleRc != null) {
        request.files.add(await http.MultipartFile.fromPath('vehicle_rc', vehicleRc.path));
      }
      if (entryPhoto != null) {
        request.files.add(await http.MultipartFile.fromPath('entry_photo', entryPhoto.path));
      }
      if (exitPhoto != null) {
        request.files.add(await http.MultipartFile.fromPath('exit_photo', exitPhoto.path));
      }
      
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      if (response.statusCode == 201) {
        return json.decode(responseBody);
      } else {
        print('Error creating record: ${response.statusCode} - $responseBody');
        return null;
      }
    } catch (e) {
      print('Exception creating record: $e');
      return null;
    }
  }
  
  // Get all water tanker records
  static Future<List<Map<String, dynamic>>?> getAllRecords({
    int page = 1,
    int limit = 10,
    String sort = 'created_at',
    String order = 'DESC',
    DateTime? date,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    try {
      final Map<String, String> queryParams = {
        'page': page.toString(),
        'limit': limit.toString(),
        'sort': sort,
        'order': order,
      };
      
      // Add date filtering parameters
      if (date != null) {
        queryParams['date'] = DateFormat('yyyy-MM-dd').format(date);
      } else if (startDate != null && endDate != null) {
        queryParams['start_date'] = DateFormat('yyyy-MM-dd').format(startDate);
        queryParams['end_date'] = DateFormat('yyyy-MM-dd').format(endDate);
      } else if (startDate != null) {
        queryParams['start_date'] = DateFormat('yyyy-MM-dd').format(startDate);
      } else if (endDate != null) {
        queryParams['end_date'] = DateFormat('yyyy-MM-dd').format(endDate);
      }
      
      final uri = Uri.parse(baseUrl).replace(queryParameters: queryParams);
      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['data']);
      } else {
        print('Error fetching records: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Exception fetching records: $e');
      return null;
    }
  }
  
  // Delete water tanker record
  static Future<bool> deleteRecord(int id) async {
    try {
      final response = await http.delete(Uri.parse('$baseUrl/$id'));
      return response.statusCode == 200;
    } catch (e) {
      print('Exception deleting record: $e');
      return false;
    }
  }
}


// API Service for Daily Input
class DailyInputApiService {
  static const String baseUrl = 'http://54.146.215.18:3000/api/daily-input';
  
  // Save or update daily input for a specific date
  static Future<Map<String, dynamic>?> saveDailyInput({
    required DateTime date,
    required int numberOfLabourers,
    String? constructionActivity,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'date': DateFormat('yyyy-MM-dd').format(date),
          'number_of_labourers': numberOfLabourers,
          'construction_activity': constructionActivity,
        }),
      );
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        print('Error saving daily input: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Exception saving daily input: $e');
      return null;
    }
  }
  
  // Get daily input for a specific date
  static Future<Map<String, dynamic>?> getDailyInput(DateTime date) async {
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      final response = await http.get(Uri.parse('$baseUrl/$dateStr'));
      
      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 404) {
        // No data found for this date, return empty
        return {
          'success': true,
          'data': {
            'number_of_labourers': 0,
            'construction_activity': null,
          }
        };
      } else {
        print('Error fetching daily input: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Exception fetching daily input: $e');
      return null;
    }
  }
  
  // Get all daily inputs with optional date range
  static Future<List<Map<String, dynamic>>?> getAllDailyInputs({
    DateTime? startDate,
    DateTime? endDate,
    int limit = 30,
  }) async {
    try {
      final uri = Uri.parse(baseUrl).replace(queryParameters: {
        if (startDate != null) 'start_date': DateFormat('yyyy-MM-dd').format(startDate),
        if (endDate != null) 'end_date': DateFormat('yyyy-MM-dd').format(endDate),
        'limit': limit.toString(),
      });
      
      final response = await http.get(uri);
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['data']);
      } else {
        print('Error fetching daily inputs: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      print('Exception fetching daily inputs: $e');
      return null;
    }
  }
  
  // Delete daily input for a specific date
  static Future<bool> deleteDailyInput(DateTime date) async {
    try {
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      final response = await http.delete(Uri.parse('$baseUrl/$dateStr'));
      return response.statusCode == 200;
    } catch (e) {
      print('Exception deleting daily input: $e');
      return false;
    }
  }
}

class TreatedWaterDashboard extends StatefulWidget {
  const TreatedWaterDashboard({Key? key}) : super(key: key);

  @override
  TreatedWaterDashboardState createState() => TreatedWaterDashboardState();
}

class TreatedWaterDashboardState extends State<TreatedWaterDashboard> {
  late SharedPreferences _prefs;
  DateTime _selectedDate = DateTime.now();
  
  // Navigation state
  int _selectedTabIndex = 0;
  
  // Date filtering state
  DateTime? _filterDate;
  bool _showAllData = true;
  
  // Dashboard display values (auto-calculated)
  int _numberOfLabourers = 0;
  double _sewageGenerated = 0.0;
  double _totalTreatedWaterGenerated = 0.0;
  double _treatedWaterUsed = 0.0;
  double _balanceRemaining = 0.0;
  double _drinkingWaterRequired = 0.0;
  
  // Constants
  final double _waterPerPerson = 135.0; // litres
  final double _sewageGenerationFactor = 0.8; // 80% of fresh water becomes sewage
  final double _treatmentEfficiency = 0.9; // 90% treatment efficiency
  
  // Selected activity
  String? _selectedActivity;
  final List<String> _constructionActivities = [
    'Slab Casting',
    'Brick Work', 
    'Curing',
    'Plastering',
    'Foundation Work',
    'Column Casting',
    'Beam Casting',
    'Wall Construction',
    'Flooring',
    'External Works',
    'Other',
  ];
  
  // Tanker records
  List<WaterTankerRecord> _tankerRecords = [];
  
  // GPS tracking
  Position? _currentPosition;
  
  @override
  void initState() {
    super.initState();
    _initializeData();
  }
  
  Future<void> _initializeData() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadDailyData();
    await _getCurrentLocation();
    await _loadRecordsFromBackend(); // Load records from backend
  }
  
  Future<void> _loadDailyData() async {
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    
    // Try to load from backend first
    try {
      final backendData = await DailyInputApiService.getDailyInput(_selectedDate);
      if (backendData != null && backendData['success'] == true) {
        final data = backendData['data'];
        setState(() {
          _numberOfLabourers = data['number_of_labourers'] ?? 0;
          _selectedActivity = data['construction_activity'];
          _calculateMetrics();
        });
        
        // Save to local storage as backup
        await _saveDailyDataLocally();
        return;
      }
    } catch (e) {
      print('Error loading from backend, falling back to local storage: $e');
    }
    
    // Fallback to local storage if backend fails
    final savedData = _prefs.getString('water_dashboard_data_$dateKey');
    if (savedData != null) {
      final data = json.decode(savedData);
      setState(() {
        _numberOfLabourers = data['labourers'] ?? 0;
        _selectedActivity = data['activity'];
        
        // Load tanker records
        if (data['tankerRecords'] != null) {
          _tankerRecords = (data['tankerRecords'] as List)
              .map((record) => WaterTankerRecord.fromJson(record))
              .toList();
        }
        
        _calculateMetrics();
      });
    }
  }
  
  Future<void> _saveDailyDataLocally() async {
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final data = {
      'date': _selectedDate.toIso8601String(),
      'labourers': _numberOfLabourers,
      'activity': _selectedActivity,
      'tankerRecords': _tankerRecords.map((record) => record.toJson()).toList(),
    };
    
    await _prefs.setString('water_dashboard_data_$dateKey', json.encode(data));
  }
  
  Future<void> _saveDailyDataToBackend() async {
    try {
      await DailyInputApiService.saveDailyInput(
        date: _selectedDate,
        numberOfLabourers: _numberOfLabourers,
        constructionActivity: _selectedActivity,
      );
      // Also save locally as backup
      await _saveDailyDataLocally();
    } catch (e) {
      print('Error saving to backend: $e');
      // Still save locally as fallback
      await _saveDailyDataLocally();
    }
  }
  
  Future<void> _loadRecordsFromBackend() async {
    try {
      final records = await WaterTankerApiService.getAllRecords(
        limit: 50,
        date: _showAllData ? null : (_filterDate ?? _selectedDate),
      );
      if (records != null) {
        setState(() {
          _tankerRecords.clear(); // Clear local records
          _tankerRecords.addAll(
            records.map((record) => WaterTankerRecord.fromBackendResponse(record)).toList()
          );
          _calculateMetrics();
        });
      }
    } catch (e) {
      print('Error loading records from backend: $e');
      // Fall back to local data if API fails
    }
  }
  
  void _calculateMetrics() {
    setState(() {
      // Calculate sewage generated (80% of fresh water consumed)
      _sewageGenerated = _numberOfLabourers * _waterPerPerson * _sewageGenerationFactor;
      
      // Calculate treated water generated (90% treatment efficiency)
      _totalTreatedWaterGenerated = _sewageGenerated * _treatmentEfficiency;
      
      // Calculate water used from tanker trips
      _treatedWaterUsed = _tankerRecords
          .where((record) => record.waterType == 'Treated Water')
          .fold(0.0, (sum, record) => sum + safeParseDouble(record.tankerCapacityLiters));
      
      // Calculate balance
      _balanceRemaining = _totalTreatedWaterGenerated - _treatedWaterUsed;
      
      // Drinking water required
      _drinkingWaterRequired = _numberOfLabourers * _waterPerPerson;
    });
  }
  
  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return;
      
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      
      _currentPosition = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (e) {
      print('Error getting location: $e');
    }
  }
  
  Future<void> _showAddTankerDialog() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddTankerScreen(
          currentPosition: _currentPosition,
        ),
      ),
    );
    
    if (result != null && result is WaterTankerRecord) {
      // Reload records from backend to get latest data
      await _loadRecordsFromBackend();
      await _saveDailyDataLocally();
    }
  }
  
  Widget _buildDashboardCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  // Date Filter Controls Widget
  Widget _buildDateFilterControls() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.filter_list, color: Colors.blue),
                const SizedBox(width: 8),
                const Text(
                  'Filter Data',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Toggle between Show All and Filter by Date
            Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey[300]!),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _showAllData = true;
                                _filterDate = null;
                              });
                              _loadRecordsFromBackend();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: _showAllData ? Colors.blue[600] : Colors.transparent,
                                borderRadius: const BorderRadius.only(
                                  topLeft: Radius.circular(8),
                                  bottomLeft: Radius.circular(8),
                                ),
                              ),
                              child: Text(
                                'Show All Days',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: _showAllData ? Colors.white : Colors.grey[700],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _showAllData = false;
                                _filterDate = _filterDate ?? DateTime.now();
                              });
                              _loadRecordsFromBackend();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: !_showAllData ? Colors.blue[600] : Colors.transparent,
                                borderRadius: const BorderRadius.only(
                                  topRight: Radius.circular(8),
                                  bottomRight: Radius.circular(8),
                                ),
                              ),
                              child: Text(
                                'Filter by Date',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: !_showAllData ? Colors.white : Colors.grey[700],
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            
            // Date Picker (only shown when filtering is enabled)
            if (!_showAllData) ...[
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: _filterDate ?? DateTime.now(),
                    firstDate: DateTime(2020),
                    lastDate: DateTime.now().add(const Duration(days: 30)),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: const ColorScheme.light(
                            primary: Colors.blue,
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (picked != null && picked != _filterDate) {
                    if (mounted) {
                      setState(() {
                        _filterDate = picked;
                      });
                      _loadRecordsFromBackend();
                    }
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.blue[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today, color: Colors.blue[700]),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _filterDate != null
                              ? 'Selected Date: ${DateFormat('EEEE, MMMM dd, yyyy').format(_filterDate!)}'
                              : 'Tap to select date',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.blue[700],
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            
            // Status Display
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _showAllData ? Colors.green[50] : Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _showAllData ? Colors.green[200]! : Colors.orange[200]!,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _showAllData ? Icons.visibility : Icons.filter_alt,
                    color: _showAllData ? Colors.green[700] : Colors.orange[700],
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _showAllData
                        ? 'Showing data from all days'
                        : 'Showing data for ${_filterDate != null ? DateFormat('MMM dd, yyyy').format(_filterDate!) : 'selected date'}',
                    style: TextStyle(
                      color: _showAllData ? Colors.green[700] : Colors.orange[700],
                      fontWeight: FontWeight.w500,
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
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Treated Water (In House)',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.blue[800],
        elevation: 0,
      ),
      body: Column(
        children: [
          // Navigation Tabs
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue[700]!, Colors.blue[800]!],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
            ),
            child: Row(
              children: [
                _buildNavTab(0, Icons.add, 'Submit Data'),
                _buildNavTab(1, Icons.analytics, 'Analytics'),
                _buildNavTab(2, Icons.table_chart, 'Data Table'),
                _buildNavTab(3, Icons.bar_chart, 'Charts'),
              ],
            ),
          ),
          
          // Content based on selected tab
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.blue[50]!, Colors.white],
                ),
              ),
              child: _buildTabContent(),
            ),
          ),
        ],
      ),
    );
  }
  
  // Navigation Tab Builder
  Widget _buildNavTab(int index, IconData icon, String label) {
    final isSelected = _selectedTabIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _selectedTabIndex = index;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected ? Colors.white.withValues(alpha: 0.2) : Colors.transparent,
            border: Border(
              bottom: BorderSide(
                color: isSelected ? Colors.white : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  // Build content based on selected tab
  Widget _buildTabContent() {
    switch (_selectedTabIndex) {
      case 0:
        return _buildSubmitDataTab();
      case 1:
        return _buildAnalyticsTab();
      case 2:
        return _buildDataTableTab();
      case 3:
        return _buildChartsTab();
      default:
        return _buildSubmitDataTab();
    }
  }
  
  // Submit Data Tab
  Widget _buildSubmitDataTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date Display
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.calendar_today, color: Colors.blue),
                  const SizedBox(width: 12),
                  Text(
                    DateFormat('EEEE, MMMM dd, yyyy').format(_selectedDate),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          
          // Input Section
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Daily Input',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  
                  // Number of Labourers
                  TextFormField(
                    initialValue: _numberOfLabourers.toString(),
                    decoration: InputDecoration(
                      labelText: 'Number of Labourers',
                      prefixIcon: const Icon(Icons.people),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) {
                      setState(() {
                        _numberOfLabourers = int.tryParse(value) ?? 0;
                        _calculateMetrics();
                      });
                      _saveDailyDataToBackend();
                    },
                  ),
                  const SizedBox(height: 16),
                  
                  // Activity Selection
                  DropdownButtonFormField<String>(
                    value: _selectedActivity,
                    decoration: InputDecoration(
                      labelText: 'Construction Activity',
                      prefixIcon: const Icon(Icons.construction),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    items: _constructionActivities.map((activity) {
                      return DropdownMenuItem(
                        value: activity,
                        child: Text(activity),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedActivity = value;
                      });
                      _saveDailyDataToBackend();
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          
          // Metrics Display
          const Text(
            'Water Metrics',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.5,
            children: [
              _buildDashboardCard(
                'Sewage Generated',
                '${_sewageGenerated.toStringAsFixed(0)} L',
                Icons.water_damage,
                Colors.orange,
              ),
              _buildDashboardCard(
                'Treated Water Generated',
                '${_totalTreatedWaterGenerated.toStringAsFixed(0)} L',
                Icons.recycling,
                Colors.green,
              ),
              _buildDashboardCard(
                'Water Used',
                '${_treatedWaterUsed.toStringAsFixed(0)} L',
                Icons.construction,
                Colors.blue,
              ),
              _buildDashboardCard(
                'Balance Remaining',
                '${_balanceRemaining.toStringAsFixed(0)} L',
                Icons.balance,
                Colors.purple,
              ),
              _buildDashboardCard(
                'Drinking Water Required',
                '${_drinkingWaterRequired.toStringAsFixed(0)} L',
                Icons.local_drink,
                Colors.cyan,
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Add Tanker Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showAddTankerDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add New Tanker Record'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // Analytics Tab
  Widget _buildAnalyticsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Water Management Analytics',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              IconButton(
                onPressed: _loadRecordsFromBackend,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh Data',
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Date Filter Controls
          _buildDateFilterControls(),
          const SizedBox(height: 20),
          
          // Summary Cards
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.8,
            children: [
              _buildAnalyticsCard(
                'Total Tankers',
                _tankerRecords.length.toString(),
                Icons.local_shipping,
                Colors.blue,
              ),
              _buildAnalyticsCard(
                'Fresh Water',
                _tankerRecords.where((r) => r.waterType == 'Fresh Water').length.toString(),
                Icons.water_drop,
                Colors.cyan,
              ),
              _buildAnalyticsCard(
                'Treated Water',
                _tankerRecords.where((r) => r.waterType == 'Treated Water').length.toString(),
                Icons.recycling,
                Colors.green,
              ),
              _buildAnalyticsCard(
                'Total Capacity',
                '${_tankerRecords.fold(0.0, (sum, r) => sum + r.tankerCapacityLiters.toDouble()).toStringAsFixed(0)}L',
                Icons.local_gas_station,
                Colors.orange,
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          // Recent Activity
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Recent Activity',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...(_tankerRecords.take(5).map((record) => _buildActivityItem(record)).toList()),
                  if (_tankerRecords.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(20),
                        child: Text(
                          'No recent activity',
                          style: TextStyle(color: Colors.grey),
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
  
  // Data Table Tab with Enhanced Columns
  Widget _buildDataTableTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Tanker Records',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${_tankerRecords.length} records',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Date Filter Controls
          _buildDateFilterControls(),
          const SizedBox(height: 20),
          
          if (_tankerRecords.isEmpty)
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Container(
                padding: const EdgeInsets.all(40),
                alignment: Alignment.center,
                child: Column(
                  children: [
                    Icon(Icons.inbox, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    const Text(
                      'No tanker records yet',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Add your first tanker record to see data here',
                      style: TextStyle(color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          else
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columnSpacing: 20,
                  headingRowColor: WidgetStateColor.resolveWith(
                    (states) => Colors.blue[50]!,
                  ),
                  columns: const [
                    DataColumn(
                      label: Text(
                        'No',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'Date',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'Tanker Number',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'Water Type (Fresh/treated)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'Tanker Capacity',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'Tanker Photo',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'Loading Photo',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    DataColumn(
                      label: Text(
                        'Unloading Photo',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                  rows: _tankerRecords.asMap().entries.map((entry) {
                    final index = entry.key + 1;
                    final record = entry.value;
                    return DataRow(
                      cells: [
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue[100],
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              index.toString(),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 90,
                            child: Text(
                              DateFormat('MMM dd, yyyy').format(record.createdAt ?? record.gpsCapturedAt ?? DateTime.now()),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(
                          SizedBox(
                            width: 80,
                            child: Text(
                              record.tankerNumber,
                              style: const TextStyle(fontWeight: FontWeight.w500),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: record.waterType == 'Fresh Water' ? Colors.cyan[100] : Colors.green[100],
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              record.waterType,
                              style: TextStyle(
                                color: record.waterType == 'Fresh Water' ? Colors.cyan[800] : Colors.green[800],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                        DataCell(Text(
                          '${record.tankerCapacityLiters.toStringAsFixed(0)}L',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        )),
                        DataCell(
                          record.tankerPhotoPath != null
                              ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                              : const Icon(Icons.cancel, color: Colors.red, size: 20),
                        ),
                        DataCell(
                          record.entryPhotoPath != null
                              ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                              : const Icon(Icons.cancel, color: Colors.red, size: 20),
                        ),
                        DataCell(
                          record.exitPhotoPath != null
                              ? const Icon(Icons.check_circle, color: Colors.green, size: 20)
                              : const Icon(Icons.cancel, color: Colors.red, size: 20),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  // Charts Tab
  Widget _buildChartsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Water Usage Charts',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          // Date Filter Controls
          _buildDateFilterControls(),
          const SizedBox(height: 20),
          
          // Water Type Distribution
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Water Type Distribution',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildWaterTypeChart(),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          
          // Daily Capacity Chart
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Daily Water Capacity',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildCapacityChart(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  // Helper Methods
  Widget _buildAnalyticsCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildActivityItem(WaterTankerRecord record) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: record.waterType == 'Fresh Water' ? Colors.cyan[100] : Colors.green[100],
              shape: BoxShape.circle,
            ),
            child: Icon(
              record.waterType == 'Fresh Water' ? Icons.water_drop : Icons.recycling,
              color: record.waterType == 'Fresh Water' ? Colors.cyan[700] : Colors.green[700],
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  record.tankerNumber,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  '${record.waterType} Water - ${record.tankerCapacityLiters.toStringAsFixed(0)}L',
                  style: TextStyle(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            DateFormat('MMM dd').format(record.createdAt ?? record.gpsCapturedAt ?? DateTime.now()),
            style: TextStyle(
              color: Colors.grey[500],
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildWaterTypeChart() {
    if (_tankerRecords.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: Text(
            'No data available',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    
    final freshCount = _tankerRecords.where((r) => r.waterType == 'Fresh Water').length;
    final treatedCount = _tankerRecords.where((r) => r.waterType == 'Treated Water').length;
    final total = _tankerRecords.length;
    
    return SizedBox(
      height: 200,
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                // Fresh Water Bar
                Container(
                  width: double.infinity,
                  height: 40,
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.cyan[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Stack(
                    children: [
                      Container(
                        width: total > 0 ? (freshCount / total) * double.infinity : 0,
                        decoration: BoxDecoration(
                          color: Colors.cyan[600],
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      Center(
                        child: Text(
                          'Fresh Water: $freshCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Treated Water Bar
                Container(
                  width: double.infinity,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.green[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Stack(
                    children: [
                      Container(
                        width: total > 0 ? (treatedCount / total) * double.infinity : 0,
                        decoration: BoxDecoration(
                          color: Colors.green[600],
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      Center(
                        child: Text(
                          'Treated Water: $treatedCount',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCapacityChart() {
    if (_tankerRecords.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: Text(
            'No data available',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      );
    }
    
    // Group by date and sum capacity - show last 7 days of data
    final Map<String, double> dailyCapacity = {};
    final sortedRecords = _tankerRecords..sort((a, b) {
      final dateA = a.createdAt ?? a.gpsCapturedAt ?? DateTime.now();
      final dateB = b.createdAt ?? b.gpsCapturedAt ?? DateTime.now();
      return dateB.compareTo(dateA); // Most recent first
    });
    
    for (final record in sortedRecords.take(7)) {
      final recordDate = record.createdAt ?? record.gpsCapturedAt ?? DateTime.now();
      final dateKey = DateFormat('MMM dd').format(recordDate);
      dailyCapacity[dateKey] = (dailyCapacity[dateKey] ?? 0) + safeParseDouble(record.tankerCapacityLiters);
    }
    
    final maxCapacity = dailyCapacity.values.isEmpty ? 1.0 : dailyCapacity.values.reduce((a, b) => a > b ? a : b);
    
    return SizedBox(
      height: 200,
      child: dailyCapacity.isEmpty
          ? const Center(
              child: Text(
                'No capacity data available',
                style: TextStyle(color: Colors.grey),
              ),
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: dailyCapacity.entries.map((entry) {
                final height = (entry.value / maxCapacity) * 150;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${entry.value.toStringAsFixed(0)}L',
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          width: double.infinity,
                          height: height,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [Colors.blue[600]!, Colors.blue[400]!],
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(4),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          entry.key,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
    );
  }
}

// Data Models
class WaterTankerRecord {
  final int? id;
  final String tankerNumber;
  final int tankerCapacityLiters;
  final String waterType;
  final String? tankerPhotoUrl;
  final String? vendorLicenseUrl;
  final String? vehicleRcUrl;
  final String? entryPhotoUrl;
  final String? exitPhotoUrl;
  final double? gpsLatitude;
  final double? gpsLongitude;
  final DateTime? gpsCapturedAt;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  
  // Local file paths (for form usage before API call)
  final String? tankerPhotoPath;
  final String? vendorLicensePath;
  final String? vehicleRcPath;
  final String? entryPhotoPath;
  final String? exitPhotoPath;
  
  WaterTankerRecord({
    this.id,
    required this.tankerNumber,
    required this.tankerCapacityLiters,
    required this.waterType,
    this.tankerPhotoUrl,
    this.vendorLicenseUrl,
    this.vehicleRcUrl,
    this.entryPhotoUrl,
    this.exitPhotoUrl,
    this.gpsLatitude,
    this.gpsLongitude,
    this.gpsCapturedAt,
    this.createdAt,
    this.updatedAt,
    // Local paths for form
    this.tankerPhotoPath,
    this.vendorLicensePath,
    this.vehicleRcPath,
    this.entryPhotoPath,
    this.exitPhotoPath,
  });
  
  Map<String, dynamic> toJson() => {
    'id': id,
    'tankerNumber': tankerNumber,
    'tankerCapacityLiters': tankerCapacityLiters,
    'waterType': waterType,
    'tankerPhotoUrl': tankerPhotoUrl,
    'vendorLicenseUrl': vendorLicenseUrl,
    'vehicleRcUrl': vehicleRcUrl,
    'entryPhotoUrl': entryPhotoUrl,
    'exitPhotoUrl': exitPhotoUrl,
    'gpsLatitude': gpsLatitude,
    'gpsLongitude': gpsLongitude,
    'gpsCapturedAt': gpsCapturedAt?.toIso8601String(),
    'createdAt': createdAt?.toIso8601String(),
    'updatedAt': updatedAt?.toIso8601String(),
    // Local paths
    'tankerPhotoPath': tankerPhotoPath,
    'vendorLicensePath': vendorLicensePath,
    'vehicleRcPath': vehicleRcPath,
    'entryPhotoPath': entryPhotoPath,
    'exitPhotoPath': exitPhotoPath,
  };

  factory WaterTankerRecord.fromJson(Map<String, dynamic> json) => WaterTankerRecord(
    id: json['id'],
    tankerNumber: json['tanker_number'] ?? json['tankerNumber'] ?? '',
    tankerCapacityLiters: json['tanker_capacity_liters'] ?? json['tankerCapacityLiters'] ?? 0,
    waterType: json['water_type'] ?? json['waterType'] ?? 'Treated Water',
    tankerPhotoUrl: json['tanker_photo_url'] ?? json['tankerPhotoUrl'],
    vendorLicenseUrl: json['vendor_license_url'] ?? json['vendorLicenseUrl'],
    vehicleRcUrl: json['vehicle_rc_url'] ?? json['vehicleRcUrl'],
    entryPhotoUrl: json['entry_photo_url'] ?? json['entryPhotoUrl'],
    exitPhotoUrl: json['exit_photo_url'] ?? json['exitPhotoUrl'],
    gpsLatitude: safeParseDouble(json['gps_latitude'] ?? json['gpsLatitude']),
    gpsLongitude: safeParseDouble(json['gps_longitude'] ?? json['gpsLongitude']),
    gpsCapturedAt: json['gps_captured_at'] != null ? DateTime.parse(json['gps_captured_at']) : 
                   (json['gpsCapturedAt'] != null ? DateTime.parse(json['gpsCapturedAt']) : null),
    createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : 
               (json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null),
    updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : 
               (json['updatedAt'] != null ? DateTime.parse(json['updatedAt']) : null),
    // Local paths
    tankerPhotoPath: json['tankerPhotoPath'],
    vendorLicensePath: json['vendorLicensePath'],
    vehicleRcPath: json['vehicleRcPath'],
    entryPhotoPath: json['entryPhotoPath'],
    exitPhotoPath: json['exitPhotoPath'],
  );
  
  // Helper method to create from backend response
  factory WaterTankerRecord.fromBackendResponse(Map<String, dynamic> json) => WaterTankerRecord(
    id: json['id'],
    tankerNumber: json['tanker_number'] ?? '',
    tankerCapacityLiters: json['tanker_capacity_liters'] ?? 0,
    waterType: json['water_type'] ?? 'Treated Water',
    tankerPhotoUrl: json['tanker_photo_url'],
    vendorLicenseUrl: json['vendor_license_url'],
    vehicleRcUrl: json['vehicle_rc_url'],
    entryPhotoUrl: json['entry_photo_url'],
    exitPhotoUrl: json['exit_photo_url'],
    gpsLatitude: safeParseDouble(json['gps_latitude']),
    gpsLongitude: safeParseDouble(json['gps_longitude']),
    gpsCapturedAt: json['gps_captured_at'] != null ? DateTime.parse(json['gps_captured_at']) : null,
    createdAt: json['created_at'] != null ? DateTime.parse(json['created_at']) : null,
    updatedAt: json['updated_at'] != null ? DateTime.parse(json['updated_at']) : null,
  );
}

// Add Tanker Screen
class AddTankerScreen extends StatefulWidget {
  final Position? currentPosition;
  
  const AddTankerScreen({Key? key, this.currentPosition}) : super(key: key);
  
  @override
  AddTankerScreenState createState() => AddTankerScreenState();
}

class AddTankerScreenState extends State<AddTankerScreen> {
  final _formKey = GlobalKey<FormState>();
  final _tankerNumberController = TextEditingController();
  final _capacityController = TextEditingController();
  String _waterType = 'Treated';
  
  File? _tankerPhoto;
  File? _vendorLicence;
  File? _vehicleRC;
  File? _entryPhoto;
  File? _exitPhoto;
  
  final ImagePicker _picker = ImagePicker();
  
  Future<void> _pickImage(String type) async {
    // Show dialog to choose between camera and gallery
    final ImageSource? source = await showDialog<ImageSource>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('📷 Select Image Source'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('How would you like to add the image?'),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Gallery Option
                Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: IconButton(
                        onPressed: () => Navigator.pop(context, ImageSource.gallery),
                        icon: Icon(Icons.photo_library, size: 32, color: Colors.blue[700]),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('Gallery', style: TextStyle(fontSize: 12)),
                  ],
                ),
                // Camera Option
                Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.green[50],
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green[200]!),
                      ),
                      child: IconButton(
                        onPressed: () => Navigator.pop(context, ImageSource.camera),
                        icon: Icon(Icons.camera_alt, size: 32, color: Colors.green[700]),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('Camera', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
    
    if (source == null) return;
    
    final XFile? image = await _picker.pickImage(
      source: source,
      imageQuality: 85,
      maxWidth: 1920,
      maxHeight: 1080,
    );
    
    if (image != null) {
      setState(() {
        switch (type) {
          case 'tanker':
            _tankerPhoto = File(image.path);
          case 'vendor':
            _vendorLicence = File(image.path);
          case 'vehicle':
            _vehicleRC = File(image.path);
          case 'entry':
            _entryPhoto = File(image.path);
          case 'exit':
            _exitPhoto = File(image.path);
        }
      });
    }
  }
  
  // Build section card with consistent styling
  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: child,
          ),
        ],
      ),
    );
  }
  
  // Build consistent input decoration
  InputDecoration _buildInputDecoration({
    required String label,
    required String hint,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon, color: Colors.blue[700]),
      filled: true,
      fillColor: Colors.grey[50],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey[300]!),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.blue[700]!, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 1),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
    );
  }
  
  // Build photo upload card with consistent styling
  Widget _buildPhotoUploadCard(
    String title,
    File? image,
    String type,
    String hint,
  ) {
    return GestureDetector(
      onTap: () => _pickImage(type),
      child: Container(
        height: 160,
        decoration: BoxDecoration(
          color: image != null ? Colors.green[50] : Colors.blue[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: image != null ? Colors.green[300]! : Colors.blue[300]!,
            width: 1,
          ),
        ),
        child: image != null
            ? Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.file(
                      image,
                      width: double.infinity,
                      height: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.green[600],
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 16,
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 0,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: const BorderRadius.only(
                          bottomLeft: Radius.circular(12),
                          bottomRight: Radius.circular(12),
                        ),
                      ),
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              )
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue[100],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.add_a_photo,
                      size: 32,
                      color: Colors.blue[700],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue[700],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    hint,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  
  void _saveTanker() async {
    if (_formKey.currentState!.validate()) {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
      
      try {
        // Call API to create record
        final result = await WaterTankerApiService.createRecord(
          tankerNumber: _tankerNumberController.text,
          tankerCapacityLiters: int.parse(_capacityController.text),
          waterType: _waterType,
          tankerPhoto: _tankerPhoto,
          vendorLicense: _vendorLicence,
          vehicleRc: _vehicleRC,
          entryPhoto: _entryPhoto,
          exitPhoto: _exitPhoto,
          gpsLatitude: widget.currentPosition?.latitude,
          gpsLongitude: widget.currentPosition?.longitude,
          gpsCapturedAt: DateTime.now(),
        );
        
        // Hide loading indicator
        Navigator.pop(context);
        
        if (result != null && result['success'] == true) {
          // Create record from API response
          final record = WaterTankerRecord.fromBackendResponse(result['data']);
          
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tanker record saved successfully!'),
              backgroundColor: Colors.green,
            ),
          );
          
          Navigator.pop(context, record);
        } else {
          // Show error message
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to save tanker record. Please try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } catch (e) {
        // Hide loading indicator
        Navigator.pop(context);
        
        // Show error message
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        title: const Text(
          'Add Tanker Details',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        backgroundColor: const Color(0xFF4C6EF5),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF4C6EF5), Color(0xFF7C3AED)],
            ),
          ),
        ),
      ),
      body: Container(
        color: Colors.grey[50],
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Header Section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue[700]!, Colors.blue[900]!],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.local_shipping,
                        size: 48,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Water Tanker Registration',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Complete all details for proper tracking',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
              
              // Form Content
              Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                
                      // Tanker Photo Section
                      _buildSectionCard(
                        title: 'Tanker Photo',
                        icon: Icons.camera_alt,
                        color: Colors.blue,
                        child: Column(
                          children: [
                            _buildPhotoUploadCard(
                              'TANKER PHOTO',
                              _tankerPhoto,
                              'tanker',
                              'Tap to capture tanker image',
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
              
                      // Tanker Information Section
                      _buildSectionCard(
                        title: 'Tanker Information',
                        icon: Icons.local_shipping,
                        color: Colors.indigo,
                        child: Column(
                          children: [
              
                            TextFormField(
                              controller: _tankerNumberController,
                              decoration: _buildInputDecoration(
                                label: 'Tanker Number',
                                hint: 'Enter tanker number',
                                icon: Icons.confirmation_number,
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter tanker number';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
              
                            TextFormField(
                              controller: _capacityController,
                              keyboardType: TextInputType.number,
                              decoration: _buildInputDecoration(
                                label: 'Tanker Capacity (Litres)',
                                hint: 'Enter capacity in litres',
                                icon: Icons.local_gas_station,
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return 'Please enter capacity';
                                }
                                if (double.tryParse(value) == null) {
                                  return 'Please enter a valid number';
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: 16),
              
                            DropdownButtonFormField<String>(
                              value: _waterType,
                              decoration: _buildInputDecoration(
                                label: 'Water Type',
                                hint: 'Select water type',
                                icon: Icons.water_drop,
                              ),
                              items: const [
                                DropdownMenuItem(value: 'Fresh', child: Text('Fresh Water')),
                                DropdownMenuItem(value: 'Treated', child: Text('Treated Water')),
                              ],
                              onChanged: (value) {
                                setState(() {
                                  _waterType = value!;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
              
                      // Documents Section
                      _buildSectionCard(
                        title: 'Documents',
                        icon: Icons.description,
                        color: Colors.purple,
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildPhotoUploadCard(
                                'VENDOR LICENCE',
                                _vendorLicence,
                                'vendor',
                                'Upload vendor licence',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildPhotoUploadCard(
                                'VEHICLE RC',
                                _vehicleRC,
                                'vehicle',
                                'Upload vehicle RC',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
              
                      // Entry/Exit Photos Section
                      _buildSectionCard(
                        title: 'Entry/Exit Photos',
                        icon: Icons.camera_enhance,
                        color: Colors.teal,
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildPhotoUploadCard(
                                'ENTRY PHOTO',
                                _entryPhoto,
                                'entry',
                                'Capture entry photo',
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _buildPhotoUploadCard(
                                'EXIT PHOTO',
                                _exitPhoto,
                                'exit',
                                'Capture exit photo',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
              
                      // GPS Location
                      if (widget.currentPosition != null)
                        _buildSectionCard(
                          title: 'GPS Location Captured',
                          icon: Icons.location_on,
                          color: Colors.green,
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: Colors.green[50],
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.green[200]!,
                                width: 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.pin_drop,
                                  color: Colors.green[700],
                                  size: 24,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    'Lat: ${widget.currentPosition!.latitude.toStringAsFixed(6)}, '
                                    'Long: ${widget.currentPosition!.longitude.toStringAsFixed(6)}',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.green[800],
                                      fontWeight: FontWeight.w600,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
              
                      // Save Button
                      Container(
                        width: double.infinity,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Colors.blue[600]!, Colors.blue[800]!],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.blue.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ElevatedButton(
                          onPressed: _saveTanker,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.transparent,
                            shadowColor: Colors.transparent,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.save,
                                color: Colors.white,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Save Tanker Details',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _tankerNumberController.dispose();
    _capacityController.dispose();
    super.dispose();
  }
}