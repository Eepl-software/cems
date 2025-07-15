import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';

const String baseUrl = 'http://54.146.215.18:3000';

class MunicipalSolidWasteDetailsPage extends StatefulWidget {
  const MunicipalSolidWasteDetailsPage({Key? key}) : super(key: key);

  @override
  _MunicipalSolidWasteDetailsPageState createState() => _MunicipalSolidWasteDetailsPageState();
}

class _MunicipalSolidWasteDetailsPageState extends State<MunicipalSolidWasteDetailsPage> 
    with SingleTickerProviderStateMixin {
  // Tab Controller
  late TabController _tabController;
  
  // State variables
  bool _isLoading = false;
  bool _isRefreshing = false;
  
  // Form state
  final _formKey = GlobalKey<FormState>();
  DateTime _selectedDate = DateTime.now();
  final _housesController = TextEditingController();
  final _employeesController = TextEditingController();
  
  // Data storage
  List<MunicipalWasteRecord> _wasteRecords = [];
  Map<String, double> _wasteStats = {};
  
  // Waste types definition
  final List<Map<String, dynamic>> _wasteTypes = [
    {
      'key': 'dry',
      'name': 'Dry Waste',
      'icon': Icons.dry_cleaning,
      'color': Colors.orange,
      'generatedController': TextEditingController(),
      'disposedToController': TextEditingController(),
      'quantityController': TextEditingController(),
    },
    {
      'key': 'wet',
      'name': 'Wet Waste',
      'icon': Icons.water_drop,
      'color': Colors.blue,
      'generatedController': TextEditingController(),
      'disposedToController': TextEditingController(),
      'quantityController': TextEditingController(),
    },
    {
      'key': 'sanitary_napkins',
      'name': 'Sanitary Napkins',
      'icon': Icons.health_and_safety,
      'color': Colors.pink,
      'generatedController': TextEditingController(),
      'disposedToController': TextEditingController(),
      'quantityController': TextEditingController(),
    },
    {
      'key': 'e_waste',
      'name': 'E-Waste',
      'icon': Icons.electrical_services,
      'color': Colors.green,
      'generatedController': TextEditingController(),
      'disposedToController': TextEditingController(),
      'quantityController': TextEditingController(),
    },
    {
      'key': 'bio_medical_waste',
      'name': 'Bio Medical Waste',
      'icon': Icons.medical_services,
      'color': Colors.red,
      'generatedController': TextEditingController(),
      'disposedToController': TextEditingController(),
      'quantityController': TextEditingController(),
    },
    {
      'key': 'battery_waste',
      'name': 'Battery Waste',
      'icon': Icons.battery_alert,
      'color': Colors.amber,
      'generatedController': TextEditingController(),
      'disposedToController': TextEditingController(),
      'quantityController': TextEditingController(),
    },
    {
      'key': 'others',
      'name': 'Others',
      'icon': Icons.category,
      'color': Colors.grey,
      'generatedController': TextEditingController(),
      'disposedToController': TextEditingController(),
      'quantityController': TextEditingController(),
    },
  ];
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchInitialData();
  }
  
  @override
  void dispose() {
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
      
      print('Fetch records status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Records response: $data');
        
        setState(() {
          _wasteRecords = (data['data'] as List? ?? [])
              .map((json) => MunicipalWasteRecord.fromJson(json))
              .toList();
        });
      } else {
        throw Exception('Failed to load waste records: ${response.statusCode} - ${response.reasonPhrase}');
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
      
      print('Fetch stats status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Stats response: $data');
        
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
        } else {
          print('Summary is null in stats response');
        }
      } else {
        print('Stats API error: ${response.statusCode} - ${response.body}');
      }
    } catch (e) {
      print('Error fetching stats: $e');
      // Don't rethrow as stats are not critical
    }
  }
  
  Future<void> _submitWasteData() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    try {
      final numEmployees = int.tryParse(_employeesController.text) ?? 0;
      final employeeGeneratedWaste = numEmployees * 0.1;
      final wasteData = {
        'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
        'no_of_houses_occupied': int.parse(_housesController.text),
        'num_employees': numEmployees,
        // employee_generated_waste is calculated and stored in backend, but can be sent for display
        'employee_generated_waste': employeeGeneratedWaste,
      };
      
      // Add waste type data
      for (var wasteType in _wasteTypes) {
        final key = wasteType['key'];
        wasteData['${key}_generated_quantity'] = _safeParseDouble(wasteType['generatedController'].text);
        wasteData['${key}_disposed_to'] = wasteType['disposedToController'].text ?? '';
        wasteData['${key}_quantity'] = _safeParseDouble(wasteType['quantityController'].text);
      }
      
      print('Submitting waste data: $wasteData');
      
      final response = await http.post(
        Uri.http('54.146.215.18:3000', '/municipal-solid-waste'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(wasteData),
      );
      
      print('Submit response status: ${response.statusCode}');
      print('Submit response body: ${response.body}');
      
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
              primary: const Color(0xFF00796B),
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
        title: const Text('Delete Record'),
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
          backgroundColor: Color(0xFF00796B),
          foregroundColor: Colors.white,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF00796B),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        cardTheme: CardTheme(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          clipBehavior: Clip.antiAlias,
        ),
        tabBarTheme: const TabBarTheme(
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicator: BoxDecoration(
            border: Border(bottom: BorderSide(color: Colors.white, width: 3)),
          ),
        ),
      ),
      child: Scaffold(
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.delete_outline, size: 24),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Municipal Solid Waste',
                  style: TextStyle(fontWeight: FontWeight.bold),
                  overflow: TextOverflow.ellipsis,
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
              Tab(icon: Icon(Icons.add), text: 'Add Record'),
              Tab(icon: Icon(Icons.history), text: 'History'),
              Tab(icon: Icon(Icons.analytics), text: 'Analytics'),
            ],
          ),
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : TabBarView(
                controller: _tabController,
                children: [
                  _buildAddRecordTab(),
                  _buildHistoryTab(),
                  _buildAnalyticsTab(),
                ],
              ),
      ),
    );
  }
  
  Widget _buildAddRecordTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildBasicInfoCard(),
            const SizedBox(height: 16),
            _buildWasteTableCard(),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _submitWasteData,
                icon: const Icon(Icons.save),
                label: const Text('Save Waste Data', style: TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildBasicInfoCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _housesController,
                    decoration: InputDecoration(
                      labelText: 'No. of Houses Occupied',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      prefixIcon: const Icon(Icons.home, color: Color(0xFF00796B)),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Required';
                      }
                      if (int.tryParse(value) == null) {
                        return 'Invalid number';
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _employeesController,
                    decoration: InputDecoration(
                      labelText: 'No. of Employees',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      prefixIcon: const Icon(Icons.people, color: Color(0xFF00796B)),
                    ),
                    keyboardType: TextInputType.number,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Required';
                      }
                      if (int.tryParse(value) == null) {
                        return 'Invalid number';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final numEmployees = int.tryParse(_employeesController.text) ?? 0;
                final employeeGeneratedWaste = numEmployees * 0.1;
                return Text(
                  'Employee Waste (100g/employee): ${employeeGeneratedWaste.toStringAsFixed(2)} kg',
                  style: const TextStyle(fontSize: 13, color: Colors.teal, fontWeight: FontWeight.w500),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildWasteTableCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.delete_outline, color: Color(0xFF00796B)),
                SizedBox(width: 8),
                Text(
                  'Waste Generated (in Kg)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF00796B)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Table Header
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFFE0F2F1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF00796B), width: 1),
              ),
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(2),
                  1: FlexColumnWidth(1.5),
                  2: FlexColumnWidth(2),
                  3: FlexColumnWidth(1.5),
                },
                children: [
                  TableRow(
                    children: [
                      _buildTableHeader('Waste Type'),
                      _buildTableHeader('Generated\nQty'),
                      _buildTableHeader('Disposed To'),
                      _buildTableHeader('Quantity'),
                    ],
                  ),
                ],
              ),
            ),
            
            // Table Body
            Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.shade300),
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
              ),
              child: Table(
                columnWidths: const {
                  0: FlexColumnWidth(2),
                  1: FlexColumnWidth(1.5),
                  2: FlexColumnWidth(2),
                  3: FlexColumnWidth(1.5),
                },
                children: _wasteTypes.map((wasteType) => _buildTableRow(wasteType)).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildTableHeader(String text) {
    return Container(
      padding: const EdgeInsets.all(12),
      child: Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
          color: Color(0xFF00796B),
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
  
  TableRow _buildTableRow(Map<String, dynamic> wasteType) {
    return TableRow(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade200),
        ),
      ),
      children: [
        // Waste Type Name with Icon
        Container(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: (wasteType['color'] as Color).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  wasteType['icon'] as IconData,
                  color: wasteType['color'] as Color,
                  size: 16,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  wasteType['name'] as String,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        
        // Generated Quantity
        Container(
          padding: const EdgeInsets.all(4),
          child: TextFormField(
            controller: wasteType['generatedController'],
            decoration: const InputDecoration(
              hintText: '0.0',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              isDense: true,
            ),
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 12),
          ),
        ),
        
        // Disposed To
        Container(
          padding: const EdgeInsets.all(4),
          child: TextFormField(
            controller: wasteType['disposedToController'],
            decoration: const InputDecoration(
              hintText: 'Location/Method',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              isDense: true,
            ),
            style: const TextStyle(fontSize: 12),
          ),
        ),
        
        // Quantity
        Container(
          padding: const EdgeInsets.all(4),
          child: TextFormField(
            controller: wasteType['quantityController'],
            decoration: const InputDecoration(
              hintText: '0.0',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              isDense: true,
            ),
            keyboardType: TextInputType.number,
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
  
  Widget _buildHistoryTab() {
    if (_wasteRecords.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, color: Colors.grey, size: 64),
            SizedBox(height: 16),
            Text(
              'No waste records found',
              style: TextStyle(fontSize: 18, color: Colors.grey, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              'Add your first record using the "Add Record" tab',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }
    
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _wasteRecords.length,
      itemBuilder: (context, index) {
        final record = _wasteRecords[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.calendar_today, size: 16, color: Colors.teal[700]),
                    const SizedBox(width: 8),
                    Text(DateFormat('yyyy-MM-dd').format(record.date), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                Text('No. of Houses: ${record.noOfHousesOccupied}'),
                Text('No. of Employees: ${record.numEmployees}'),
                Text('Employee Waste: ${record.employeeGeneratedWaste.toStringAsFixed(2)} kg'),
                // ... add more fields as needed ...
              ],
            ),
          ),
        );
      },
    );
  }
  
  Widget _buildHistoryCard(MunicipalWasteRecord record) {
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
                      DateFormat('MMMM d, yyyy').format(record.date),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                        '${record.noOfHousesOccupied} Houses',
                        style: const TextStyle(
                          color: Color(0xFF00796B),
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      onPressed: () => _showDeleteConfirmation(record.id),
                      tooltip: 'Delete record',
                    ),
                  ],
                ),
              ],
            ),
            const Divider(),
            _buildHistoryTable(record),
          ],
        ),
      ),
    );
  }
  
  Widget _buildHistoryTable(MunicipalWasteRecord record) {
    final wasteData = [
      {'name': 'Dry', 'generated': record.dryGeneratedQuantity, 'disposed': record.dryQuantity, 'disposedTo': record.dryDisposedTo},
      {'name': 'Wet', 'generated': record.wetGeneratedQuantity, 'disposed': record.wetQuantity, 'disposedTo': record.wetDisposedTo},
      {'name': 'Sanitary Napkins', 'generated': record.sanitaryNapkinsGeneratedQuantity, 'disposed': record.sanitaryNapkinsQuantity, 'disposedTo': record.sanitaryNapkinsDisposedTo},
      {'name': 'E-Waste', 'generated': record.eWasteGeneratedQuantity, 'disposed': record.eWasteQuantity, 'disposedTo': record.eWasteDisposedTo},
      {'name': 'Bio Medical', 'generated': record.bioMedicalWasteGeneratedQuantity, 'disposed': record.bioMedicalWasteQuantity, 'disposedTo': record.bioMedicalWasteDisposedTo},
      {'name': 'Battery', 'generated': record.batteryWasteGeneratedQuantity, 'disposed': record.batteryWasteQuantity, 'disposedTo': record.batteryWasteDisposedTo},
      {'name': 'Others', 'generated': record.othersGeneratedQuantity, 'disposed': record.othersQuantity, 'disposedTo': record.othersDisposedTo},
    ];
    
    // Filter out rows with no data
    final filteredData = wasteData.where((item) => 
      (item['generated'] as double) > 0 || (item['disposed'] as double) > 0
    ).toList();
    
    if (filteredData.isEmpty) {
      return const Text('No waste data recorded', style: TextStyle(color: Colors.grey));
    }
    
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2),
          1: FlexColumnWidth(1.5),
          2: FlexColumnWidth(2),
          3: FlexColumnWidth(1.5),
        },
        children: [
          // Header
          TableRow(
            decoration: BoxDecoration(color: Colors.grey.shade100),
            children: [
              _buildTableCell('Waste Type', isHeader: true),
              _buildTableCell('Generated', isHeader: true),
              _buildTableCell('Disposed To', isHeader: true),
              _buildTableCell('Quantity', isHeader: true),
            ],
          ),
          // Data rows
          ...filteredData.map((item) => TableRow(
            children: [
              _buildTableCell(item['name'] as String),
              _buildTableCell('${(item['generated'] as double).toStringAsFixed(2)} kg'),
              _buildTableCell(item['disposedTo'] as String),
              _buildTableCell('${(item['disposed'] as double).toStringAsFixed(2)} kg'),
            ],
          )).toList(),
        ],
      ),
    );
  }
  
  Widget _buildTableCell(String text, {bool isHeader = false}) {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
          color: isHeader ? const Color(0xFF00796B) : Colors.black87,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
  
  Widget _buildAnalyticsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStatsCards(),
          const SizedBox(height: 16),
          _buildWasteChart(),
        ],
      ),
    );
  }
  
  Widget _buildStatsCards() {
    double totalEmployeeWaste = 0;
    int totalEmployees = 0;
    if (_wasteRecords.isNotEmpty) {
      totalEmployeeWaste = _wasteRecords.fold(0.0, (sum, r) => sum + (r.employeeGeneratedWaste));
      totalEmployees = _wasteRecords.fold(0, (sum, r) => sum + (r.numEmployees));
    }
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Total Records',
                (_wasteStats['totalRecords'] ?? 0).toInt().toString(),
                Icons.format_list_numbered,
                Colors.blue,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStatCard(
                'Avg Houses',
                (_wasteStats['avgHousesOccupied'] ?? 0).toStringAsFixed(0),
                Icons.home,
                Colors.green,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Total Generated',
                '${(_wasteStats['totalWasteGenerated'] ?? 0).toStringAsFixed(2)} kg',
                Icons.trending_up,
                Colors.orange,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStatCard(
                'Total Disposed',
                '${(_wasteStats['totalWasteDisposed'] ?? 0).toStringAsFixed(2)} kg',
                Icons.trending_down,
                Colors.purple,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Total Employees',
                totalEmployees.toString(),
                Icons.people,
                Colors.teal,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStatCard(
                'Employee Waste',
                '${totalEmployeeWaste.toStringAsFixed(2)} kg',
                Icons.delete_sweep,
                Colors.brown,
              ),
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
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
              style: TextStyle(fontSize: 14, color: Colors.grey[700]),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildWasteChart() {
    if (_wasteRecords.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(
            child: Text(
              'No data available for chart',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ),
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
              children: const [
                Icon(Icons.bar_chart, color: Color(0xFF00796B)),
                SizedBox(width: 8),
                Text(
                  'Recent Waste Generation Trend',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF00796B)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const SizedBox(
              height: 200,
              child: Center(
                child: Text(
                  'Chart implementation can be added here',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// Data Model (same as before but with enhanced error handling)
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
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': DateFormat('yyyy-MM-dd').format(date),
      'no_of_houses_occupied': noOfHousesOccupied,
      'num_employees': numEmployees,
      'employee_generated_waste': employeeGeneratedWaste,
      'dry_generated_quantity': dryGeneratedQuantity,
      'dry_disposed_to': dryDisposedTo,
      'dry_quantity': dryQuantity,
      'wet_generated_quantity': wetGeneratedQuantity,
      'wet_disposed_to': wetDisposedTo,
      'wet_quantity': wetQuantity,
      'sanitary_napkins_generated_quantity': sanitaryNapkinsGeneratedQuantity,
      'sanitary_napkins_disposed_to': sanitaryNapkinsDisposedTo,
      'sanitary_napkins_quantity': sanitaryNapkinsQuantity,
      'e_waste_generated_quantity': eWasteGeneratedQuantity,
      'e_waste_disposed_to': eWasteDisposedTo,
      'e_waste_quantity': eWasteQuantity,
      'bio_medical_waste_generated_quantity': bioMedicalWasteGeneratedQuantity,
      'bio_medical_waste_disposed_to': bioMedicalWasteDisposedTo,
      'bio_medical_waste_quantity': bioMedicalWasteQuantity,
      'battery_waste_generated_quantity': batteryWasteGeneratedQuantity,
      'battery_waste_disposed_to': batteryWasteDisposedTo,
      'battery_waste_quantity': batteryWasteQuantity,
      'others_generated_quantity': othersGeneratedQuantity,
      'others_disposed_to': othersDisposedTo,
      'others_quantity': othersQuantity,
    };
  }
}