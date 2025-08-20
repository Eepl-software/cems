
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'dart:io';

const String baseUrl = 'http://54.146.215.18:3000';

class CDWasteDetailsPage extends StatefulWidget {
  const CDWasteDetailsPage({Key? key}) : super(key: key);

  @override
  _CDWasteDetailsPageState createState() => _CDWasteDetailsPageState();
}

class _CDWasteDetailsPageState extends State<CDWasteDetailsPage> with SingleTickerProviderStateMixin {
  // Tab Controller
  late TabController _tabController;
  
  // State variables
  bool _isLoading = false;
  bool _isRefreshing = false;
  bool _isLoadingConfig = true;
  Map<String, dynamic> _dynamicConfig = {};
  
  // Waste calculation state
  final _formKey = GlobalKey<FormState>();
  final _projectAreaController = TextEditingController();
  final _projectNameController = TextEditingController();
  DateTime? _startDate;
  DateTime? _endDate;
  String _selectedConstructionType = 'Residential';
  
  // Waste data
  List<Map<String, dynamic>> _wasteHistory = [];
  double _totalWasteGenerated = 0;
  double _totalAreaMeasured = 0;
  Map<String, double> _wasteByMonth = {};
  
  // Daily waste state
  List<DailyWaste> _dailyWasteRecords = [];
  Map<String, double> _wasteByCategoryData = {};
  
  // Dynamic configuration
  List<String> _constructionTypes = [];
  Map<String, double> _wasteCoefficients = {};
  Map<String, dynamic> _wasteCategories = {};
  List<String> _storageMethods = [];
  List<String> _disposalMethods = [];
  List<String> _wasteTypes = [];
  Map<String, dynamic> _thresholds = {};
  
  // Analytics data
  double _averageWastePerDay = 0;
  Map<String, double> _disposalMethodsData = {};
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabSelection);
    _loadSavedFormData();
    _fetchDynamicConfig();
  }
  
  void _handleTabSelection() {
  if (_tabController.indexIsChanging) {
    _saveFormData(); // Save form data when switching tabs
  }
  setState(() {
    // This will force the build method to be called again
    // when tab changes, which will update the FloatingActionButton visibility
  });
}
  
  @override
  void dispose() {
    _projectAreaController.dispose();
    _projectNameController.dispose();
    _tabController.removeListener(_handleTabSelection);
    _tabController.dispose();
    _saveFormData(); // Save form data when disposing
    super.dispose();
  }
  
  // Persistence methods
  Future<void> _saveFormData() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('projectArea', _projectAreaController.text);
    prefs.setString('projectName', _projectNameController.text);
    prefs.setString('constructionType', _selectedConstructionType);
    prefs.setString('startDate', _startDate?.toIso8601String() ?? '');
    prefs.setString('endDate', _endDate?.toIso8601String() ?? '');
  }
  
  Future<void> _loadSavedFormData() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _projectAreaController.text = prefs.getString('projectArea') ?? '';
      _projectNameController.text = prefs.getString('projectName') ?? '';
      _selectedConstructionType = prefs.getString('constructionType') ?? 'Residential';
      
      final startDateStr = prefs.getString('startDate');
      if (startDateStr != null && startDateStr.isNotEmpty) {
        _startDate = DateTime.parse(startDateStr);
      }
      
      final endDateStr = prefs.getString('endDate');
      if (endDateStr != null && endDateStr.isNotEmpty) {
        _endDate = DateTime.parse(endDateStr);
      }
    });
  }
  
  // API Calls
  Future<void> _fetchDynamicConfig() async {
    try {
      final response = await http.get(Uri.http('54.146.215.18:3000', '/cd-waste/config'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _dynamicConfig = data['config'];
          _constructionTypes = List<String>.from(_dynamicConfig['constructionTypes'] ?? []);
          _wasteCoefficients = Map<String, double>.from(
            (_dynamicConfig['wasteCoefficients'] ?? {}).map((k, v) => MapEntry(k, v.toDouble()))
          );
          _wasteCategories = Map<String, dynamic>.from(_dynamicConfig['wasteCategories'] ?? {});
          _storageMethods = List<String>.from(_dynamicConfig['storageMethods'] ?? []);
          _disposalMethods = List<String>.from(_dynamicConfig['disposalMethods'] ?? []);
          _wasteTypes = List<String>.from(_dynamicConfig['wasteTypes'] ?? []);
          _thresholds = Map<String, dynamic>.from(_dynamicConfig['thresholds'] ?? {});
          _isLoadingConfig = false;
        });
        _fetchInitialData();
      } else {
        // Fallback to default values
        _setDefaultConfig();
        _fetchInitialData();
      }
    } catch (e) {
      print('Error fetching dynamic config: $e');
      _setDefaultConfig();
      _fetchInitialData();
    }
  }

  void _setDefaultConfig() {
    setState(() {
      _constructionTypes = ['Residential', 'Commercial', 'Industrial', 'Infrastructure', 'Renovation', 'Demolition'];
      _wasteCoefficients = {
        'Residential': 21.0,
        'Commercial': 18.5,
        'Industrial': 25.0,
        'Infrastructure': 15.0,
        'Renovation': 12.5,
        'Demolition': 30.0,
      };
      _storageMethods = ['On-site Container', 'Segregated Bins', 'Temporary Storage Area'];
      _disposalMethods = ['Recycling Facility', 'Landfill', 'Reuse on Site'];
      _wasteTypes = ['Mixed C&D Waste', 'Concrete Debris', 'Wood Waste'];
      _isLoadingConfig = false;
    });
  }
  
  Future<void> _fetchInitialData() async {
    setState(() => _isLoading = true);
    try {
      await Future.wait([
        _fetchWasteHistory(),
        _fetchDailyWasteRecords(),
      ]);
      _processAnalyticsData();
    } catch (e) {
      _showError('Error loading data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _refreshData() async {
    setState(() => _isRefreshing = true);
    try {
      await Future.wait([
        _fetchWasteHistory(),
        _fetchDailyWasteRecords(),
      ]);
      _processAnalyticsData();
    } catch (e) {
      _showError('Error refreshing data: $e');
    } finally {
      setState(() => _isRefreshing = false);
    }
  }
  
  Future<void> _fetchWasteHistory() async {
    try {
      final response = await http.get(Uri.http('54.146.215.18:3000', '/cd-waste'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _wasteHistory = List<Map<String, dynamic>>.from(data['data'] ?? []);
          _calculateTotals();
          _calculateWasteByMonth();
        });
      } else {
        throw Exception('Failed to load waste history: ${response.reasonPhrase}');
      }
    } catch (e) {
      rethrow;
    }
  }
  
  Future<void> _fetchDailyWasteRecords() async {
  try {
    final response = await http.get(Uri.http('54.146.215.18:3000', '/daily-waste'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        _dailyWasteRecords = (data['data'] as List? ?? [])
            .map((json) => DailyWaste.fromJson(json))
            .toList();
        _calculateWasteByCategory();
      });
    } else {
      throw Exception('Failed to load daily waste records: ${response.reasonPhrase}');
    }
  } catch (e) {
    rethrow;
  }
}
  
  void _calculateTotals() {
    _totalWasteGenerated = _wasteHistory.fold(0.0, 
      (sum, item) => sum + (double.tryParse(item['waste_amount']?.toString() ?? '0') ?? 0));
    _totalAreaMeasured = _wasteHistory.fold(0.0, 
      (sum, item) => sum + (double.tryParse(item['project_area']?.toString() ?? '0') ?? 0));
  }
  
  void _calculateWasteByMonth() {
    _wasteByMonth = {};
    
    for (var waste in _wasteHistory) {
      final date = DateTime.parse(waste['date']);
      final monthYear = DateFormat('MMM yyyy').format(date);
      final amount = double.tryParse(waste['waste_amount']?.toString() ?? '0') ?? 0;
      
      _wasteByMonth[monthYear] = (_wasteByMonth[monthYear] ?? 0) + amount;
    }
  }
  
  void _calculateWasteByCategory() {
    // Reset data
    _wasteByCategoryData = {};
    
    _disposalMethodsData = {};
    
    // Calculate total waste by category using dynamic percentages
    double totalWaste = _dailyWasteRecords.fold(0.0, 
      (sum, record) => sum + record.quantity);
    
    if (totalWaste > 0 && _wasteCategories.isNotEmpty) {
      // Use dynamic waste categories from config
      _wasteCategories.forEach((category, details) {
        final percentage = (details['percentage'] ?? 0) / 100.0;
        _wasteByCategoryData[category] = totalWaste * percentage;
      });
    } else if (totalWaste > 0) {
      // Fallback to default distribution
      _wasteByCategoryData = {
        'Concrete': totalWaste * 0.40,
        'Wood': totalWaste * 0.20,
        'Metal': totalWaste * 0.15,
        'Glass': totalWaste * 0.10,
        'Plastic': totalWaste * 0.05,
        'Others': totalWaste * 0.10,
      };
    }
    
    // Calculate disposal methods data
    for (var record in _dailyWasteRecords) {
      final method = record.modeOfDisposal;
      _disposalMethodsData[method] = (_disposalMethodsData[method] ?? 0) + record.quantity;
    }
    
    // Calculate average waste per day
    if (_dailyWasteRecords.isNotEmpty) {
      _averageWastePerDay = totalWaste / _dailyWasteRecords.length;
    }
  }
  
  void _processAnalyticsData() {
    _calculateWasteByMonth();
    _calculateWasteByCategory();
  }
  
  // --- Update: C&D Waste Calculation Formula ---
  Future<void> _calculateAndStoreWaste() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) {
      _showError('Please select both start and end dates');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final projectArea = double.tryParse(_projectAreaController.text) ?? 0.0;
      // Use dynamic formula from config or default
      final factor = _dynamicConfig['calculationFormula']?['factor'] ?? 50;
      final wasteAmount = projectArea * factor;

      final response = await http.post(
        Uri.http('54.146.215.18:3000', '/cd-waste'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'project_area': projectArea,
          'project_name': _projectNameController.text,
          'construction_type': _selectedConstructionType,
          'date': DateTime.now().toIso8601String().split('T')[0], // Send as date only
          'waste_type': 'Mixed C&D Waste', // Default value
          'disposal_method': 'To be determined', // Default value
          'reuse_recycling_details': '',
          'location': '',
          'contractor_name': '',
        }),
      );

      if (response.statusCode == 201) {
        _showSuccess('Waste calculation stored successfully');
        await _fetchWasteHistory();
        _resetForm();
      } else {
        throw Exception('Failed to calculate waste:  {response.reasonPhrase}');
      }
    } catch (e) {
      _showError('Error:  {e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _addDailyWasteWithPhotos(DailyWaste waste, {File? loadingPhoto, File? unloadingPhoto, File? vendorLicensePhoto}) async {
    setState(() => _isLoading = true);
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.http('54.146.215.18:3000', '/daily-waste'),
      );

      // Add form fields
      request.fields['date'] = DateFormat('yyyy-MM-dd').format(waste.date);
      request.fields['quantity_kg'] = waste.quantity.toString();
      request.fields['mode_of_storage'] = waste.modeOfStorage;
      request.fields['mode_of_disposal'] = waste.modeOfDisposal;
      request.fields['waste_type'] = waste.wasteType;
      request.fields['notes'] = waste.notes;
      request.fields['location'] = waste.location;
      request.fields['latitude'] = waste.latitude?.toString() ?? '';
      request.fields['longitude'] = waste.longitude?.toString() ?? '';

      // Add photo files if they exist
      if (loadingPhoto != null) {
        request.files.add(await http.MultipartFile.fromPath(
          'loading_photo',
          loadingPhoto.path,
        ));
      }
      
      if (unloadingPhoto != null) {
        request.files.add(await http.MultipartFile.fromPath(
          'unloading_photo',
          unloadingPhoto.path,
        ));
      }
      
      if (vendorLicensePhoto != null) {
        request.files.add(await http.MultipartFile.fromPath(
          'vendor_license_photo',
          vendorLicensePhoto.path,
        ));
      }

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201) {
        _showSuccess('Daily waste record added successfully');
        await _fetchDailyWasteRecords();
        _processAnalyticsData();
      } else {
        throw Exception('Failed to add waste record: ${response.reasonPhrase}');
      }
    } catch (e) {
      _showError('Error: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addDailyWaste(DailyWaste waste) async {
    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.http('54.146.215.18:3000', '/daily-waste'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(waste.toJson()),
      );

      if (response.statusCode == 201) {
        _showSuccess('Daily waste record added successfully');
        await _fetchDailyWasteRecords();
        _processAnalyticsData();
      } else {
        throw Exception('Failed to add waste record: ${response.reasonPhrase}');
      }
    } catch (e) {
      _showError('Error: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _deleteWasteRecord(String id, bool isDailyRecord) async {
    setState(() => _isLoading = true);
    try {
      final endpoint = isDailyRecord ? 'daily-waste' : 'cd-waste';
      final response = await http.delete(
        Uri.http('54.146.215.18:3000', '/$endpoint/$id'),
      );

      if (response.statusCode == 200) {
        _showSuccess('Record deleted successfully');
        if (isDailyRecord) {
          await _fetchDailyWasteRecords();
        } else {
          await _fetchWasteHistory();
        }
        _processAnalyticsData();
      } else {
        throw Exception('Failed to delete record: ${response.reasonPhrase}');
      }
    } catch (e) {
      _showError('Error: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  // UI Helper Methods
  void _resetForm() {
    _projectAreaController.clear();
    _projectNameController.clear();
    setState(() {
      _startDate = null;
      _endDate = null;
      _selectedConstructionType = 'Residential';
    });
  }
  
  void _showSuccess(String message) {
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.all(8),
        duration: const Duration(seconds: 3),
      ),
    );
  }
  
  void _showError(String message) {
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        margin: const EdgeInsets.all(8),
        duration: const Duration(seconds: 4),
      ),
    );
  }
  
  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate 
          ? (_startDate ?? DateTime.now()) 
          : (_endDate ?? (_startDate != null ? _startDate!.add(const Duration(days: 7)) : DateTime.now())),
      firstDate: isStartDate ? DateTime(2000) : (_startDate ?? DateTime(2000)),
      lastDate: isStartDate ? DateTime.now() : DateTime.now().add(const Duration(days: 365)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Theme.of(context).primaryColor,
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
        if (isStartDate) {
          _startDate = picked;
          // If end date is before start date, reset it
          if (_endDate != null && _endDate!.isBefore(_startDate!)) {
            _endDate = null;
          }
        } else {
          _endDate = picked;
        }
      });
    }
  }
  
  void _showAddDailyWasteDialog() {
    showDialog(
      context: context,
      builder: (context) => AddWasteDialog(
        onSubmit: _addDailyWasteWithPhotos,
        storageMethods: _storageMethods,
        disposalMethods: _disposalMethods,
        wasteTypes: _wasteTypes,
      ),
    );
  }
  
  void _showDeleteConfirmation(String id, bool isDailyRecord) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm Deletion'),
        content: Text(
          'Are you sure you want to delete this ${isDailyRecord ? 'daily waste record' : 'waste calculation record'}? This action cannot be undone.'
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteWasteRecord(id, isDailyRecord);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('DELETE'),
          ),
        ],
      ),
    );
  }
  
  // Widget Building Methods
  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        primarySwatch: Colors.teal,
        appBarTheme: const AppBarTheme(
          elevation: 0,
          backgroundColor: Color(0xFF00796B),
          foregroundColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00796B),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          clipBehavior: Clip.antiAlias,
        ),
        tabBarTheme: const TabBarTheme(
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicator: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.white, width: 3),
            ),
          ),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          
          title: Row(
            mainAxisSize: MainAxisSize.min, 
            children: const [
      Icon(Icons.eco, size: 24),
      SizedBox(width: 8),
      Flexible( // Wrap the text in Flexible
        child: Text(
          'C&D Waste Management',
          style: TextStyle(fontWeight: FontWeight.bold),
          overflow: TextOverflow.ellipsis, // Allow text to use ellipsis if needed
        ),
      ),
    ],
          ),
          actions: [
            _isRefreshing
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
                    icon: const Icon(Icons.refresh),
                    onPressed: _refreshData,
                    tooltip: 'Refresh Data',
                  ),
          ],
          bottom: TabBar(
            controller: _tabController,
            tabs: const [
              Tab(
                icon: Icon(Icons.calculate_outlined),
                text: 'Calculate',
              ),
              Tab(
                icon: Icon(Icons.history),
                text: 'History & Analysis',
              ),
              Tab(
                icon: Icon(Icons.add_chart),
                text: 'Daily Tracking',
              ),
            ],
          ),
        ),
        body: _isLoading
            ? _buildLoadingView()
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildCalculationTab(),
                  _buildHistoryTab(),
                  _buildDailyWasteTab(),
                ],
              ),
        floatingActionButton: _tabController.index == 2 
    ? FloatingActionButton.extended(
        onPressed: _showAddDailyWasteDialog,
        label: const Text('Add Record'),
        icon: const Icon(Icons.add),
        backgroundColor: const Color(0xFF00796B),
      )
    : null,
      ),
    );
  }
  
  Widget _buildLoadingView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(
            color: Color(0xFF00796B),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading data...',
            style: TextStyle(
              color: Colors.grey[700],
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildCalculationTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildComponentsCard(),
            const SizedBox(height: 16),
            _buildWasteFactsCard(),
            const SizedBox(height: 16),
            _buildEstimationCard(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildComponentsCard() {
    final iconMap = {
      'Concrete': Icons.business,
      'Wood': Icons.forest,
      'Metal': Icons.iron,
      'Glass': Icons.grid_4x4,
      'Plastic': Icons.inventory_2,
      'Others': Icons.question_mark,
    };

    final wasteComponents = _wasteCategories.entries.map((entry) {
      final category = entry.key;
      final details = entry.value as Map<String, dynamic>;
      return {
        'icon': iconMap[category] ?? Icons.circle,
        'name': '$category Waste',
        'percentage': '${details['percentage'] ?? 0}%',
        'recyclable': details['recyclable'] ?? 0,
      };
    }).toList();
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.pie_chart, color: Color(0xFF00796B)),
                const SizedBox(width: 8),
                const Text(
                  'Components of C&D Waste',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00796B),
                  ),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            ...wasteComponents.map((component) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2F1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      component['icon'] as IconData,
                      color: const Color(0xFF00796B),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      component['name'] as String,
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2F1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      component['percentage'] as String,
                      style: const TextStyle(
                        color: Color(0xFF00796B),
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            )).toList(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildWasteFactsCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.lightbulb, color: Color(0xFF00796B)),
                const SizedBox(width: 8),
                const Text(
                  'Waste Generation Factors',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00796B),
                  ),
                ),
              ],
            ),
            const Divider(),
            const SizedBox(height: 8),
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _constructionTypes.length,
              itemBuilder: (context, index) {
                final type = _constructionTypes[index];
                final coefficient = _wasteCoefficients[type]!;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2F1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Color(0xFF00796B),
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                  title: Text(type),
                  trailing: Text(
                    '$coefficient kg/m²',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            const Text(
              'Note: These are estimated values that vary based on construction practices, materials, and regional regulations.',
              style: TextStyle(
                color: Colors.grey,
                fontStyle: FontStyle.italic,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildEstimationCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.calculate, color: Color(0xFF00796B)),
                const SizedBox(width: 8),
                const Text(
                  'Waste Generation Estimation',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00796B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _projectNameController,
              decoration: InputDecoration(
                labelText: 'Project Name',
                hintText: 'Enter project name or identifier',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                prefixIcon: const Icon(Icons.business, color: Color(0xFF00796B)),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter project name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _projectAreaController,
              decoration: InputDecoration(
                labelText: 'Project Area (m²)',
                hintText: 'Enter project area in square meters',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                prefixIcon: const Icon(Icons.area_chart, color: Color(0xFF00796B)),
              ),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter project area';
                }
                if (double.tryParse(value) == null) {
                  return 'Please enter a valid number';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedConstructionType,
              decoration: InputDecoration(
                labelText: 'Construction Type',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                prefixIcon: const Icon(Icons.category, color: Color(0xFF00796B)),
              ),
              items: _constructionTypes.map((type) {
                return DropdownMenuItem<String>(
                  value: type,
                  child: Text(type),
                );
              }).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() {
                    _selectedConstructionType = value;
                  });
                }
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _selectDate(context, true),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Start Date',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        prefixIcon: const Icon(Icons.calendar_today, color: Color(0xFF00796B)),
                      ),
                      child: Text(
                        _startDate != null
                            ? DateFormat('yyyy-MM-dd').format(_startDate!)
                            : 'Select Date',
                        style: TextStyle(
                          color: _startDate != null ? Colors.black : Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: InkWell(
                    onTap: () => _selectDate(context, false),
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'End Date',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),),
                        prefixIcon: const Icon(Icons.calendar_today, color: Color(0xFF00796B)),
                      ),
                      child: Text(
                        _endDate != null
                            ? DateFormat('yyyy-MM-dd').format(_endDate!)
                            : 'Select Date',
                        style: TextStyle(
                          color: _endDate != null ? Colors.black : Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_startDate != null && _endDate != null && _projectAreaController.text.isNotEmpty)
              Card(
                color: const Color(0xFFE0F2F1),
                elevation: 0,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Estimated Waste Preview:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00796B),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Project Duration:'),
                          Text(
                            '${_endDate!.difference(_startDate!).inDays + 1} days',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Waste Coefficient:'),
                          Text(
                            '${_wasteCoefficients[_selectedConstructionType]} kg/m²',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Estimated Waste:'),
                          Text(
                            '${((double.tryParse(_projectAreaController.text) ?? 0) * _wasteCoefficients[_selectedConstructionType]! * ((_endDate!.difference(_startDate!).inDays + 1) / 30)).toStringAsFixed(2)} kg',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF00796B),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _calculateAndStoreWaste,
                icon: const Icon(Icons.save),
                label: const Text('Calculate & Save', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Note: C&D waste generation is estimated based on project area, duration, and construction type. Actual amounts may vary based on specific project conditions and waste management practices.',
              style: TextStyle(
                color: Colors.grey,
                fontStyle: FontStyle.italic,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildHistoryTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryCards(),
          const SizedBox(height: 16),
          _buildWasteChart(),
          const SizedBox(height: 16),
          _buildWasteHistoryTable(),
        ],
      ),
    );
  }
  
  Widget _buildSummaryCards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'Total Waste',
                '${_totalWasteGenerated.toStringAsFixed(2)} kg',
                Icons.delete_outline,
                Colors.orange,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSummaryCard(
                'Total Area',
                '${_totalAreaMeasured.toStringAsFixed(2)} m²',
                Icons.area_chart,
                Colors.blue,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'Projects',
                '${_wasteHistory.length}',
                Icons.business,
                Colors.green,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSummaryCard(
                'Avg. Waste/Area',
                _totalAreaMeasured > 0 
                    ? '${(_totalWasteGenerated / _totalAreaMeasured).toStringAsFixed(2)} kg/m²' 
                    : '0 kg/m²',
                Icons.analytics,
                Colors.purple,
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 3,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildWasteChart() {
    if (_wasteByMonth.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text(
              'No data available for chart',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey,
              ),
            ),
          ),
        ),
      );
    }
    
    final barGroups = <BarChartGroupData>[];
    final months = _wasteByMonth.keys.toList();
    
    // Sort months chronologically
    months.sort((a, b) {
      final aDate = DateFormat('MMM yyyy').parse(a);
      final bDate = DateFormat('MMM yyyy').parse(b);
      return aDate.compareTo(bDate);
    });
    
    // Take the last 6 months or all if less than 6
    final recentMonths = months.length <= 6 ? months : months.sublist(months.length - 6);
    
    for (var i = 0; i < recentMonths.length; i++) {
      final month = recentMonths[i];
      final amount = _wasteByMonth[month]!;
      
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: amount,
              color: const Color(0xFF00796B),
              width: 22,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(6),
                topRight: Radius.circular(6),
              ),
            ),
          ],
        ),
      );
    }
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.bar_chart, color: Color(0xFF00796B)),
                const SizedBox(width: 8),
                const Text(
                  'Waste Generation Trend',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00796B),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 250,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: _wasteByMonth.values.reduce((a, b) => a > b ? a : b) * 1.2,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      tooltipBgColor: Colors.blueGrey.shade800,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          '${recentMonths[group.x.toInt()]}\n${rod.toY.toStringAsFixed(2)} kg',
                          const TextStyle(color: Colors.white),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            recentMonths[value.toInt()].split(' ')[0], // First 3 chars of month
                            style: const TextStyle(
                              color: Colors.black,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          );
                        },
                        reservedSize: 16,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toString(),
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 10,
                            ),
                          );
                        },
                        reservedSize: 40,
                      ),
                    ),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true,
                    checkToShowHorizontalLine: (value) => value % (_wasteByMonth.values.reduce((a, b) => a > b ? a : b) / 5) == 0,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: Colors.grey.shade300,
                        strokeWidth: 1,
                      );
                    },
                  ),
                  borderData: FlBorderData(
                    show: false,
                  ),
                  barGroups: barGroups,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildWasteHistoryTable() {
    if (_wasteHistory.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Icon(
                Icons.info_outline,
                color: Colors.grey,
                size: 48,
              ),
              const SizedBox(height: 16),
              const Text(
                'No waste history data available',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Add your first waste calculation using the "Calculate" tab',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: const [
                Icon(Icons.history, color: Color(0xFF00796B)),
                SizedBox(width: 8),
                Text(
                  'Waste Calculation History',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF00796B),
                  ),
                ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFE0F2F1)),
              columns: const [
                DataColumn(label: Text('Date', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(label: Text('Project', style: TextStyle(fontWeight: FontWeight.bold))),
                DataColumn(
                  label: Text('Project Area (m²)', style: TextStyle(fontWeight: FontWeight.bold)),
                  numeric: true,
                ),
                DataColumn(
                  label: Text('Waste Amount (kg)', style: TextStyle(fontWeight: FontWeight.bold)),
                  numeric: true,
                ),
                DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
              ],
              rows: _wasteHistory.map((waste) {
                return DataRow(
                  cells: [
                    DataCell(Text(
                      DateFormat('yyyy-MM-dd').format(DateTime.parse(waste['date'])),
                    )),
                    DataCell(Text(
                      waste['project_name'] ?? 'Unknown',
                      overflow: TextOverflow.ellipsis,
                    )),
                    DataCell(Text(
                      (waste['project_area'] ?? 0).toString(),
                    )),
                    DataCell(Text(
                      (waste['waste_amount'] ?? 0).toString(),
                    )),
                    DataCell(
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.red),
                        onPressed: () => _showDeleteConfirmation(waste['id'], false),
                        tooltip: 'Delete record',
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildDailyWasteTab() {
  return Column(
    children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: _buildAnalyticsCards(),
      ),
      Expanded(
        child: _dailyWasteRecords.isEmpty
            ? Center(
                child: SingleChildScrollView( // Add this to allow scrolling if needed
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min, // Add this to minimize space
                    children: [
                      const Icon(
                        Icons.bar_chart_outlined,
                        color: Colors.grey,
                        size: 64,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No daily waste records available',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center, // Center the text
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Tap the + button to add your first record',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center, // Center the text
                      ),
                    ],
                  ),
                ),
              )
            : _buildDailyWasteList(),
        ),
    ],
  );
}
  
  Widget _buildAnalyticsCards() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildSummaryCard(
                'Daily Records',
                '${_dailyWasteRecords.length}',
                Icons.calendar_today,
                Colors.indigo,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildSummaryCard(
                'Avg. Daily Waste',
                '${_averageWastePerDay.toStringAsFixed(2)} kg',
                Icons.show_chart,
                Colors.orange,
              ),
            ),
          ],
        ),
        if (_wasteByCategoryData.isNotEmpty) ...[
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.pie_chart, color: Color(0xFF00796B)),
                      SizedBox(width: 8),
                      Text(
                        'Waste by Category',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF00796B),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 160,
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 40,
                        sections: _getWastePieChartSections(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: _wasteByCategoryData.keys.map((category) {
                      Color color;
                      if (_wasteCategories.containsKey(category)) {
                        final colorString = _wasteCategories[category]['color'] ?? '#757575';
                        color = Color(int.parse(colorString.replaceFirst('#', '0xFF')));
                      } else {
                        // Default color
                        color = const Color(0xFF757575);
                      }
                      return _buildCategoryIndicator(category, color);
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
  
  Widget _buildCategoryIndicator(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 12),
        ),
      ],
    );
  }
  
  List<PieChartSectionData> _getWastePieChartSections() {
    final categories = _wasteByCategoryData.keys.toList();
    final total = _wasteByCategoryData.values.fold(0.0, (sum, amount) => sum + amount);
    
    final sections = <PieChartSectionData>[];
    for (var i = 0; i < categories.length; i++) {
      final category = categories[i];
      final amount = _wasteByCategoryData[category]!;
      final percentage = total > 0 ? (amount / total) * 100 : 0;
      
      // Get color from dynamic config or use default
      Color color;
      if (_wasteCategories.containsKey(category)) {
        final colorString = _wasteCategories[category]['color'] ?? '#757575';
        color = Color(int.parse(colorString.replaceFirst('#', '0xFF')));
      } else {
        // Default colors
        final defaultColors = [
          const Color(0xFF1E88E5),
          const Color(0xFF43A047),
          const Color(0xFFFFB300),
          const Color(0xFFE53935),
          const Color(0xFF8E24AA),
          const Color(0xFF757575),
        ];
        color = defaultColors[i % defaultColors.length];
      }
      
      sections.add(
        PieChartSectionData(
          color: color,
          value: amount,
          title: '${percentage.toStringAsFixed(1)}%',
          radius: 60,
          titleStyle: const TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }
    
    return sections;
  }
  
  Widget _buildDailyWasteList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _dailyWasteRecords.length,
      itemBuilder: (context, index) {
        final waste = _dailyWasteRecords[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.calendar_today, size: 16, color: Color(0xFF00796B)),
                        const SizedBox(width: 8),
                        Text(
                          DateFormat('MMMM d, yyyy').format(waste.date),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE0F2F1),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Text(
                            '${waste.quantity.toStringAsFixed(2)} kg',
                            style: const TextStyle(
                              color: Color(0xFF00796B),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _showDeleteConfirmation(waste.id, true),
                          tooltip: 'Delete record',
                        ),
                      ],
                    ),
                  ],
                ),
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: _buildWasteInfoItem(
                        'Storage Mode',
                        waste.modeOfStorage,
                        Icons.inventory_2,
                      ),
                    ),
                    Expanded(
                      child: _buildWasteInfoItem(
                        'Disposal Mode',
                        waste.modeOfDisposal,
                        Icons.delete,
                      ),
                    ),
                  ],
                ),
                // Location section
                if (waste.location.isNotEmpty || (waste.latitude != null && waste.longitude != null)) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.location_on, size: 16, color: Color(0xFF00796B)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (waste.location.isNotEmpty)
                              Text(
                                waste.location,
                                style: const TextStyle(fontSize: 12),
                              ),
                            if (waste.latitude != null && waste.longitude != null)
                              Text(
                                'GPS: ${waste.latitude!.toStringAsFixed(6)}, ${waste.longitude!.toStringAsFixed(6)}',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey[600],
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                // Photo gallery section
                if (waste.loadingPhotoUrl != null || waste.unloadingPhotoUrl != null || waste.vendorLicensePhotoUrl != null) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Photos:',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF00796B),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        if (waste.loadingPhotoUrl != null)
                          _buildPhotoThumbnail('Loading', waste.loadingPhotoUrl!),
                        if (waste.unloadingPhotoUrl != null)
                          _buildPhotoThumbnail('Unloading', waste.unloadingPhotoUrl!),
                        if (waste.vendorLicensePhotoUrl != null)
                          _buildPhotoThumbnail('License', waste.vendorLicensePhotoUrl!),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildWasteInfoItem(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Icon(icon, size: 16, color: Colors.grey[600]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value,
                  style: const TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoThumbnail(String label, String photoUrl) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              // Show full screen image
              showDialog(
                context: context,
                builder: (context) => Dialog(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppBar(
                        title: Text(label),
                        leading: IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ),
                      Expanded(
                        child: CachedNetworkImage(
                          imageUrl: photoUrl,
                          fit: BoxFit.contain,
                          placeholder: (context, url) => const Center(
                            child: CircularProgressIndicator(),
                          ),
                          errorWidget: (context, url, error) => const Center(
                            child: Icon(Icons.error),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: CachedNetworkImage(
                  imageUrl: photoUrl,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                  errorWidget: (context, url, error) => const Icon(Icons.error),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class AddWasteDialog extends StatefulWidget {
  final Function(DailyWaste, {File? loadingPhoto, File? unloadingPhoto, File? vendorLicensePhoto}) onSubmit;
  final List<String> storageMethods;
  final List<String> disposalMethods;
  final List<String> wasteTypes;

  const AddWasteDialog({
    Key? key,
    required this.onSubmit,
    this.storageMethods = const [
      'On-site Container',
      'Segregated Bins',
      'Temporary Storage Area',
      'Skip/Dumpster',
      'Collection Point',
      'Other',
    ],
    this.disposalMethods = const [
      'Recycling Facility',
      'Landfill',
      'Reuse on Site',
      'Transfer Station',
      'Specialist Contractor',
      'Waste-to-Energy',
      'Other',
    ],
    this.wasteTypes = const [
      'Mixed C&D Waste',
      'Concrete Debris',
      'Wood Waste',
      'Metal Scrap',
      'Glass/Ceramic',
      'Plastic Waste',
      'Packaging Materials',
      'Hazardous Waste',
      'Excavation Soil',
      'Other',
    ],
  }) : super(key: key);

  @override
  _AddWasteDialogState createState() => _AddWasteDialogState();
}

class _AddWasteDialogState extends State<AddWasteDialog> {
  final _formKey = GlobalKey<FormState>();
  DateTime _selectedDate = DateTime.now();
  final _quantityController = TextEditingController();
  final _storageController = TextEditingController();
  final _disposalController = TextEditingController();
  final _notesController = TextEditingController();
  final _locationController = TextEditingController();
  String _selectedWasteType = 'Mixed C&D Waste';
  
  String _selectedStorageMethod = '';
  String _selectedDisposalMethod = '';
  
  // Photo upload variables
  File? _loadingPhoto;
  File? _unloadingPhoto;
  File? _vendorLicensePhoto;
  final ImagePicker _picker = ImagePicker();
  
  // Location variables
  double? _latitude;
  double? _longitude;
  String _locationStatus = 'Tap to get location';
  bool _isLoadingLocation = false;

  @override
  void initState() {
    super.initState();
    _selectedStorageMethod = widget.storageMethods.isNotEmpty ? widget.storageMethods[0] : 'On-site Container';
    _selectedDisposalMethod = widget.disposalMethods.isNotEmpty ? widget.disposalMethods[0] : 'Recycling Facility';
    _selectedWasteType = widget.wasteTypes.isNotEmpty ? widget.wasteTypes[0] : 'Mixed C&D Waste';
    
    _storageController.text = _selectedStorageMethod;
    _disposalController.text = _selectedDisposalMethod;
    
    // Automatically get location when dialog opens
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _getCurrentLocation();
    });
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _storageController.dispose();
    _disposalController.dispose();
    _notesController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  // Photo picking functions
  Future<void> _pickPhoto(String photoType) async {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Select ${photoType.replaceAll('_', ' ').toUpperCase()}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _getImage(ImageSource.camera, photoType);
                  },
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Camera'),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _getImage(ImageSource.gallery, photoType);
                  },
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Gallery'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _getImage(ImageSource source, String photoType) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 1024,
        maxHeight: 1024,
      );
      
      if (image != null) {
        setState(() {
          switch (photoType) {
            case 'loading_photo':
              _loadingPhoto = File(image.path);
            case 'unloading_photo':
              _unloadingPhoto = File(image.path);
            case 'vendor_license_photo':
              _vendorLicensePhoto = File(image.path);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error picking image: $e')),
        );
      }
    }
  }

  // Location functions
  Future<void> _getCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
      _locationStatus = 'Getting location...';
    });

    try {
      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _locationStatus = 'Location services are disabled';
          _isLoadingLocation = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enable location services')),
          );
        }
        return;
      }

      // Check location permissions
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          setState(() {
            _locationStatus = 'Location permission denied';
            _isLoadingLocation = false;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Location permission is required')),
            );
          }
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _locationStatus = 'Location permission permanently denied';
          _isLoadingLocation = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please enable location permission in app settings')),
          );
        }
        return;
      }

      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      // Get address from coordinates
      try {
        List<Placemark> placemarks = await placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        
        String address = 'Unknown location';
        if (placemarks.isNotEmpty) {
          Placemark placemark = placemarks[0];
          address = '${placemark.street ?? ''}, ${placemark.locality ?? ''}, ${placemark.administrativeArea ?? ''}';
        }

        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          _locationStatus = 'Location captured';
          _locationController.text = address;
          _isLoadingLocation = false;
        });
      } catch (e) {
        // If geocoding fails, still save coordinates
        setState(() {
          _latitude = position.latitude;
          _longitude = position.longitude;
          _locationStatus = 'Location captured';
          _locationController.text = '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
          _isLoadingLocation = false;
        });
      }
    } catch (e) {
      setState(() {
        _locationStatus = 'Failed to get location: $e';
        _isLoadingLocation = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting location: $e')),
        );
      }
    }
  }

  Widget _buildPhotoSelector(String label, File? photo, VoidCallback onTap, IconData icon) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF00796B)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  if (photo != null)
                    Text(
                      'Photo selected',
                      style: TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    )
                  else
                    Text(
                      'Tap to add photo',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            if (photo != null) 
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  image: DecorationImage(
                    image: FileImage(photo),
                    fit: BoxFit.cover,
                  ),
                ),
              )
            else
              const Icon(Icons.add_a_photo, color: Colors.grey),
          ],
        ),
      ),
    );
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      // Validate location is captured
      if (_latitude == null || _longitude == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location is required. Please tap to get your current location.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      final waste = DailyWaste(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        date: _selectedDate,
        quantity: double.parse(_quantityController.text),  // Parse as double
        modeOfStorage: _storageController.text,
        modeOfDisposal: _disposalController.text,
        wasteType: _selectedWasteType,
        notes: _notesController.text,
        location: _locationController.text,
        latitude: _latitude,
        longitude: _longitude,
      );
      widget.onSubmit(
        waste, 
        loadingPhoto: _loadingPhoto,
        unloadingPhoto: _unloadingPhoto,
        vendorLicensePhoto: _vendorLicensePhoto,
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: const [
          Icon(Icons.add_chart, color: Color(0xFF00796B)),
          SizedBox(width: 8),
          Text('Add Daily Waste Record'),
        ],
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  'Date: ${DateFormat('MMMM d, yyyy').format(_selectedDate)}',
                ),
                trailing: const Icon(Icons.calendar_today),
                onTap: () async {
                  final DateTime? picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2000),
                    lastDate: DateTime.now(),
                    builder: (context, child) {
                      return Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: ColorScheme.light(
                            primary: Theme.of(context).primaryColor,
                            onPrimary: Colors.white,
                            surface: Colors.white,
                          ),
                        ),
                        child: child!,
                      );
                    },
                  );
                  if (picked != null && picked != _selectedDate) {
                    setState(() {
                      _selectedDate = picked;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedWasteType,
                decoration: InputDecoration(
                  labelText: 'Waste Type',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.category, color: Color(0xFF00796B)),
                ),
                items: widget.wasteTypes.map((type) {
                  return DropdownMenuItem<String>(
                    value: type,
                    child: Text(type),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedWasteType = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _quantityController,
                decoration: InputDecoration(
                  labelText: 'Quantity (kg)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.scale, color: Color(0xFF00796B)),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Please enter quantity';
                  }
                  if (double.tryParse(value) == null) {
                    return 'Please enter a valid number';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedStorageMethod,
                decoration: InputDecoration(
                  labelText: 'Mode of Storage',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.inventory_2, color: Color(0xFF00796B)),
                ),
                items: widget.storageMethods.map((method) {
                  return DropdownMenuItem<String>(
                    value: method,
                    child: Text(method),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedStorageMethod = value;
                      _storageController.text = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _selectedDisposalMethod,
                decoration: InputDecoration(
                  labelText: 'Mode of Disposal',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.delete_outline, color: Color(0xFF00796B)),
                ),
                items: widget.disposalMethods.map((method) {
                  return DropdownMenuItem<String>(
                    value: method,
                    child: Text(method),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedDisposalMethod = value;
                      _disposalController.text = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _notesController,
                decoration: InputDecoration(
                  labelText: 'Notes (Optional)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.note, color: Color(0xFF00796B)),
                ),
                maxLines: 3,
              ),
              const SizedBox(height: 16),
              InkWell(
                onTap: _getCurrentLocation,
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _latitude != null && _longitude != null 
                          ? Icons.location_on 
                          : Icons.location_searching,
                        color: const Color(0xFF00796B),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Location *',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _latitude != null && _longitude != null
                                  ? _locationController.text.isNotEmpty 
                                    ? _locationController.text
                                    : '${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}'
                                  : _locationStatus,
                              style: TextStyle(
                                fontSize: 16,
                                color: _latitude != null && _longitude != null 
                                  ? Colors.black 
                                  : Colors.grey[600],
                              ),
                            ),
                            if (_latitude != null && _longitude != null)
                              Text(
                                'Lat: ${_latitude!.toStringAsFixed(6)}, Lng: ${_longitude!.toStringAsFixed(6)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[500],
                                ),
                              ),
                          ],
                        ),
                      ),
                      if (_isLoadingLocation)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else if (_latitude != null && _longitude != null)
                        const Icon(Icons.check_circle, color: Colors.green)
                      else
                        const Icon(Icons.gps_fixed, color: Colors.grey),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Photo upload section
              const Text(
                'Photo Documentation',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF00796B),
                ),
              ),
              const SizedBox(height: 12),
              // Loading Photo
              _buildPhotoSelector(
                'Loading Photo',
                _loadingPhoto,
                () => _pickPhoto('loading_photo'),
                Icons.upload,
              ),
              const SizedBox(height: 12),
              // Unloading Photo
              _buildPhotoSelector(
                'Unloading Photo',
                _unloadingPhoto,
                () => _pickPhoto('unloading_photo'),
                Icons.download,
              ),
              const SizedBox(height: 12),
              // Vendor License Photo
              _buildPhotoSelector(
                'Vendor License Photo',
                _vendorLicensePhoto,
                () => _pickPhoto('vendor_license_photo'),
                Icons.badge,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00796B),
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class DailyWaste {
  final String id;
  final DateTime date;
  final double quantity;
  final String modeOfStorage;
  final String modeOfDisposal;
  final String wasteType;
  final String notes;
  final String location;
  final double? latitude;
  final double? longitude;
  final String? loadingPhotoUrl;
  final String? unloadingPhotoUrl;
  final String? vendorLicensePhotoUrl;

  DailyWaste({
    required this.date,
    required this.quantity,
    required this.modeOfStorage,
    required this.modeOfDisposal,
    this.id = '',
    this.wasteType = 'Mixed C&D Waste',
    this.notes = '',
    this.location = '',
    this.latitude,
    this.longitude,
    this.loadingPhotoUrl,
    this.unloadingPhotoUrl,
    this.vendorLicensePhotoUrl,
  });

  factory DailyWaste.fromJson(Map<String, dynamic> json) {
    return DailyWaste(
      id: json['id']?.toString() ?? '',
      date: DateTime.parse(json['date']),
      quantity: double.parse(json['quantity_kg'].toString()),
      modeOfStorage: json['mode_of_storage'] ?? '',
      modeOfDisposal: json['mode_of_disposal'] ?? '',
      wasteType: json['waste_type'] ?? 'Mixed C&D Waste',
      notes: json['notes'] ?? '',
      location: json['location'] ?? '',
      latitude: json['latitude'] != null ? double.parse(json['latitude'].toString()) : null,
      longitude: json['longitude'] != null ? double.parse(json['longitude'].toString()) : null,
      loadingPhotoUrl: json['loading_photo_url'],
      unloadingPhotoUrl: json['unloading_photo_url'],
      vendorLicensePhotoUrl: json['vendor_license_photo_url'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': DateFormat('yyyy-MM-dd').format(date),
      'quantity_kg': quantity,  // Send as number
      'mode_of_storage': modeOfStorage,
      'mode_of_disposal': modeOfDisposal,
      'waste_type': wasteType,
      'notes': notes,
      'location': location,
      'latitude': latitude,
      'longitude': longitude,
      'loading_photo_url': loadingPhotoUrl,
      'unloading_photo_url': unloadingPhotoUrl,
      'vendor_license_photo_url': vendorLicensePhotoUrl,
    };
  }
}

// Create a custom Shimmer loading widget for better UX
class ShimmerLoading extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius? borderRadius;

  const ShimmerLoading({
    Key? key,
    required this.width,
    required this.height,
    this.borderRadius,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: borderRadius ?? BorderRadius.circular(8),
        ),
      ),
    );
  }
}

// For exporting waste data to PDF/CSV (can be implemented in a future version)
class WasteExporter {
  static Future<String> exportHistoryToCsv(List<Map<String, dynamic>> wasteHistory) async {
    // Implementation for exporting waste history to CSV
    // This would generate CSV data and return it as a string
    final buffer = StringBuffer();
    
    // Add CSV header
    buffer.writeln('Date,Project Name,Project Area (m²),Waste Amount (kg),Construction Type');
    
    // Add rows
    for (var waste in wasteHistory) {
      final date = DateTime.parse(waste['date']);
      final formattedDate = DateFormat('yyyy-MM-dd').format(date);
      final projectName = waste['project_name'] ?? 'Unknown';
      final projectArea = waste['project_area'] ?? 0;
      final wasteAmount = waste['waste_amount'] ?? 0;
      final constructionType = waste['construction_type'] ?? 'Unknown';
      
      buffer.writeln('$formattedDate,"$projectName",$projectArea,$wasteAmount,"$constructionType"');
    }
    
    return buffer.toString();
  }
}

// A helper class to manage waste coefficients and calculations
class WasteCalculator {
  // Waste coefficients by construction type (kg/m²)
  static final Map<String, double> wasteCoefficients = {
    'Residential': 21.0,
    'Commercial': 18.5,
    'Industrial': 25.0,
    'Infrastructure': 15.0,
    'Renovation': 12.5,
    'Demolition': 30.0,
  };
  
  // Calculate waste amount based on project area, construction type, and duration
  static double calculateWasteAmount({
    required double projectArea,
    required String constructionType,
    required int durationDays,
  }) {
    final coefficient = wasteCoefficients[constructionType] ?? 20.0; // Default to 20 if type not found
    final baseWasteAmount = projectArea * coefficient;
    
    // Adjust for project duration (normalized to monthly basis)
    return baseWasteAmount * (durationDays / 30);
  }
  
  // Calculate environmental impact (CO2 equivalent) based on waste amount
  static double calculateCO2Impact(double wasteAmount) {
    // Simplified calculation: 1 ton of C&D waste = ~0.2 tons CO2 equivalent
    return wasteAmount * 0.0002; // Convert kg to tons and multiply by 0.2
  }
  
  // Calculate recycling potential as a percentage of total waste
  static Map<String, double> calculateRecyclingPotential(double wasteAmount) {
    return {
      'Concrete': wasteAmount * 0.40 * 0.9, // 90% of concrete is recyclable
      'Wood': wasteAmount * 0.20 * 0.7,     // 70% of wood is recyclable
      'Metal': wasteAmount * 0.15 * 0.95,   // 95% of metal is recyclable
      'Glass': wasteAmount * 0.10 * 0.80,   // 80% of glass is recyclable
      'Plastic': wasteAmount * 0.05 * 0.60, // 60% of plastic is recyclable
      'Others': wasteAmount * 0.10 * 0.30,  // 30% of others is recyclable
    };
  }
}