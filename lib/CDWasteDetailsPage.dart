
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  
  // Construction types
  final List<String> _constructionTypes = [
    'Residential',
    'Commercial',
    'Industrial',
    'Infrastructure',
    'Renovation',
    'Demolition'
  ];
  
  // Waste coefficients by construction type (kg/m²)
  final Map<String, double> _wasteCoefficients = {
    'Residential': 21.0,
    'Commercial': 18.5,
    'Industrial': 25.0,
    'Infrastructure': 15.0,
    'Renovation': 12.5,
    'Demolition': 30.0,
  };
  
  // Analytics data
  double _averageWastePerDay = 0;
  Map<String, double> _disposalMethodsData = {};
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_handleTabSelection);
    _loadSavedFormData();
    _fetchInitialData();
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
    _wasteByCategoryData = {
      'Concrete': 0.0,
      'Wood': 0.0, 
      'Metal': 0.0,
      'Glass': 0.0,
      'Plastic': 0.0,
      'Others': 0.0,
    };
    
    _disposalMethodsData = {};
    
    // Calculate total waste by category (using a simple distribution model)
    double totalWaste = _dailyWasteRecords.fold(0.0, 
      (sum, record) => sum + record.quantity);
    
    if (totalWaste > 0) {
      _wasteByCategoryData['Concrete'] = totalWaste * 0.40; // 40% concrete
      _wasteByCategoryData['Wood'] = totalWaste * 0.20;     // 20% wood
      _wasteByCategoryData['Metal'] = totalWaste * 0.15;    // 15% metal
      _wasteByCategoryData['Glass'] = totalWaste * 0.10;    // 10% glass
      _wasteByCategoryData['Plastic'] = totalWaste * 0.05;  // 5% plastic
      _wasteByCategoryData['Others'] = totalWaste * 0.10;   // 10% others
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
      // Use correct formula: 50kg per sq ft
      final wasteAmount = projectArea * 50;

      final response = await http.post(
        Uri.http('54.146.215.18:3000', '/waste-calculations'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'project_area': projectArea,
          'start_date': _startDate?.toIso8601String(),
          'end_date': _endDate?.toIso8601String(),
          'waste_amount': wasteAmount,
          'calculation_date': DateTime.now().toIso8601String(),
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
        onSubmit: _addDailyWaste,
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
    final wasteComponents = [
      {'icon': Icons.business, 'name': 'Concrete Waste', 'percentage': '40%'},
      {'icon': Icons.forest, 'name': 'Wood Waste', 'percentage': '20%'},
      {'icon': Icons.iron, 'name': 'Metal Scrap', 'percentage': '15%'},
      {'icon': Icons.grid_4x4, 'name': 'Glass & Ceramic', 'percentage': '10%'},
      {'icon': Icons.inventory_2, 'name': 'Plastics & Packaging', 'percentage': '5%'},
      {'icon': Icons.question_mark, 'name': 'Other Materials', 'percentage': '10%'},
    ];
    
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
              headingRowColor: MaterialStateProperty.all(const Color(0xFFE0F2F1)),
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
                    children: [
                      _buildCategoryIndicator('Concrete', const Color(0xFF1E88E5)),
                      _buildCategoryIndicator('Wood', const Color(0xFF43A047)),
                      _buildCategoryIndicator('Metal', const Color(0xFFFFB300)),
                      _buildCategoryIndicator('Glass', const Color(0xFFE53935)),
                      _buildCategoryIndicator('Plastic', const Color(0xFF8E24AA)),
                      _buildCategoryIndicator('Others', const Color(0xFF757575)),
                    ],
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
    final colors = [
      const Color(0xFF1E88E5), // Concrete - Blue
      const Color(0xFF43A047), // Wood - Green
      const Color(0xFFFFB300), // Metal - Amber
      const Color(0xFFE53935), // Glass - Red
      const Color(0xFF8E24AA), // Plastic - Purple
      const Color(0xFF757575), // Others - Grey
    ];
    
    final categories = _wasteByCategoryData.keys.toList();
    final total = _wasteByCategoryData.values.fold(0.0, (sum, amount) => sum + amount);
    
    final sections = <PieChartSectionData>[];
    for (var i = 0; i < categories.length; i++) {
      final category = categories[i];
      final amount = _wasteByCategoryData[category]!;
      final percentage = total > 0 ? (amount / total) * 100 : 0;
      
      sections.add(
        PieChartSectionData(
          color: colors[i % colors.length],
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
}

class AddWasteDialog extends StatefulWidget {
  final Function(DailyWaste) onSubmit;

  const AddWasteDialog({
    Key? key,
    required this.onSubmit,
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
  String _selectedWasteType = 'Mixed C&D Waste';
  
  final List<String> _wasteTypes = [
    'Mixed C&D Waste',
    'Concrete Debris',
    'Wood Waste',
    'Metal Scrap',
    'Glass/Ceramic',
    'Plastic Waste',
    'Packaging Materials',
    'Other',
  ];
  
  final List<String> _storageMethods = [
    'On-site Container',
    'Segregated Bins',
    'Temporary Storage Area',
    'Skip/Dumpster',
    'Collection Point',
    'Other',
  ];
  
  final List<String> _disposalMethods = [
    'Recycling Facility',
    'Landfill',
    'Reuse on Site',
    'Transfer Station',
    'Specialist Contractor',
    'Waste-to-Energy',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _storageController.text = _storageMethods.first;
    _disposalController.text = _disposalMethods.first;
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _storageController.dispose();
    _disposalController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _submit() {
  if (_formKey.currentState!.validate()) {
    final waste = DailyWaste(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      date: _selectedDate,
      quantity: double.parse(_quantityController.text),  // Parse as double
      modeOfStorage: _storageController.text,
      modeOfDisposal: _disposalController.text,
      wasteType: _selectedWasteType,
      notes: _notesController.text,
    );
    widget.onSubmit(waste);
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
                items: _wasteTypes.map((type) {
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
                value: _storageController.text.isEmpty ? _storageMethods.first : _storageController.text,
                decoration: InputDecoration(
                  labelText: 'Mode of Storage',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.inventory_2, color: Color(0xFF00796B)),
                ),
                items: _storageMethods.map((method) {
                  return DropdownMenuItem<String>(
                    value: method,
                    child: Text(method),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _storageController.text = value;
                    });
                  }
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: _disposalController.text.isEmpty ? _disposalMethods.first : _disposalController.text,
                decoration: InputDecoration(
                  labelText: 'Mode of Disposal',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  prefixIcon: const Icon(Icons.delete_outline, color: Color(0xFF00796B)),
                ),
                items: _disposalMethods.map((method) {
                  return DropdownMenuItem<String>(
                    value: method,
                    child: Text(method),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
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

  DailyWaste({
    required this.date,
    required this.quantity,
    required this.modeOfStorage,
    required this.modeOfDisposal,
    this.id = '',
    this.wasteType = 'Mixed C&D Waste',
    this.notes = '',
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