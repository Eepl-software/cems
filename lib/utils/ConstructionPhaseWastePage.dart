import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';

const String baseUrl = 'http://54.146.215.18:3000';

class ConstructionPhaseWastePage extends StatefulWidget {
  const ConstructionPhaseWastePage({Key? key}) : super(key: key);

  @override
  _ConstructionPhaseWastePageState createState() => _ConstructionPhaseWastePageState();
}

class _ConstructionPhaseWastePageState extends State<ConstructionPhaseWastePage> 
    with SingleTickerProviderStateMixin {
  // Tab Controller
  late TabController _tabController;
  
  // State variables
  bool _isLoading = false;
  bool _isRefreshing = false;
  
  // Form state
  final _formKey = GlobalKey<FormState>();
  DateTime _selectedDate = DateTime.now();
  final _labourController = TextEditingController();
  final _dryWasteGeneratedController = TextEditingController();
  final _dryWasteDisposedController = TextEditingController();
  final _wetWasteGeneratedController = TextEditingController();
  final _wetWasteDisposedController = TextEditingController();
  final _notesController = TextEditingController();
  
  // Data storage
  List<ConstructionPhaseWasteRecord> _wasteRecords = [];
  Map<String, double> _wasteStats = {};
  
  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchInitialData();
  }
  
  @override
  void dispose() {
    _labourController.dispose();
    _dryWasteGeneratedController.dispose();
    _dryWasteDisposedController.dispose();
    _wetWasteGeneratedController.dispose();
    _wetWasteDisposedController.dispose();
    _notesController.dispose();
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
        Uri.http('54.146.215.18:3000', '/construction-phase-waste', {'limit': '50'}),
      );
      
      print('Fetch records status: ${response.statusCode}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('Records response: $data');
        
        setState(() {
          _wasteRecords = (data['data'] as List? ?? [])
              .map((json) => ConstructionPhaseWasteRecord.fromJson(json))
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
        Uri.http('54.146.215.18:3000', '/construction-phase-waste/stats'),
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
              'totalDryWaste': _safeParseDouble(summary['total_dry_waste']),
              'totalWetWaste': _safeParseDouble(summary['total_wet_waste']),
              'totalWasteGenerated': _safeParseDouble(summary['total_waste_generated']),
              'avgDailyWaste': _safeParseDouble(summary['avg_daily_waste']),
              'avgLabourCount': _safeParseDouble(summary['avg_labour_count']),
              'avgWastePerLabour': _safeParseDouble(summary['avg_waste_per_labour']),
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
      final wasteData = {
        'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
        'approx_no_of_labour': int.parse(_labourController.text),
        'dry_waste_generated': _safeParseDouble(_dryWasteGeneratedController.text),
        'dry_waste_disposed_through': _dryWasteDisposedController.text,
        'wet_waste_generated': _safeParseDouble(_wetWasteGeneratedController.text),
        'wet_waste_disposed_through': _wetWasteDisposedController.text,
        'notes': _notesController.text,
      };
      
      print('Submitting waste data: $wasteData');
      
      final response = await http.post(
        Uri.http('54.146.215.18:3000', '/construction-phase-waste'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(wasteData),
      );
      
      print('Submit response status: ${response.statusCode}');
      print('Submit response body: ${response.body}');
      
      if (response.statusCode == 201) {
        _showSuccess('Construction phase waste data saved successfully');
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
        Uri.http('54.146.215.18:3000', '/construction-phase-waste/$id'),
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
    _labourController.clear();
    _dryWasteGeneratedController.clear();
    _dryWasteDisposedController.clear();
    _wetWasteGeneratedController.clear();
    _wetWasteDisposedController.clear();
    _notesController.clear();
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
              Icon(Icons.construction, size: 24),
              SizedBox(width: 8),
              Flexible(
                child: Text(
                  'Construction Phase Waste',
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
            _buildWasteDetailsCard(),
            const SizedBox(height: 16),
            _buildNotesCard(),
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
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.info_outline, color: Color(0xFF00796B)),
                SizedBox(width: 8),
                Text(
                  'Basic Information',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF00796B)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _selectDate,
                    child: InputDecorator(
                      decoration: InputDecoration(
                        labelText: 'Date',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        prefixIcon: const Icon(Icons.calendar_today, color: Color(0xFF00796B)),
                      ),
                      child: Text(
                        DateFormat('yyyy-MM-dd').format(_selectedDate),
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _labourController,
                    decoration: InputDecoration(
                      labelText: 'Approx No. of Labour/Employees',
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
          ],
        ),
      ),
    );
  }
  
  Widget _buildWasteDetailsCard() {
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
                  'Waste Details',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF00796B)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Dry Waste Section
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.dry_cleaning, color: Colors.orange[700], size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Dry Waste',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.orange[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _dryWasteGeneratedController,
                          decoration: InputDecoration(
                            labelText: 'Generated (Kg)',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _dryWasteDisposedController,
                          decoration: InputDecoration(
                            labelText: 'Disposed Through',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 16),
            
            // Wet Waste Section
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.water_drop, color: Colors.blue[700], size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Wet Waste',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.blue[700],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _wetWasteGeneratedController,
                          decoration: InputDecoration(
                            labelText: 'Generated (Kg)',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: _wetWasteDisposedController,
                          decoration: InputDecoration(
                            labelText: 'Disposed Through',
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildNotesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.note_alt, color: Color(0xFF00796B)),
                SizedBox(width: 8),
                Text(
                  'Additional Notes',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF00796B)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesController,
              decoration: InputDecoration(
                labelText: 'Notes (Optional)',
                hintText: 'Enter any additional information about waste generation or disposal...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                alignLabelWithHint: true,
              ),
              maxLines: 3,
            ),
          ],
        ),
      ),
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
        return _buildHistoryCard(record);
      },
    );
  }
  
  Widget _buildHistoryCard(ConstructionPhaseWasteRecord record) {
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
                        '${record.approxNoOfLabour} Labour',
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
            _buildHistoryDetails(record),
          ],
        ),
      ),
    );
  }
  
  Widget _buildHistoryDetails(ConstructionPhaseWasteRecord record) {
    return Column(
      children: [
        // Summary row
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                  'Total Waste',
                  '${record.totalWasteGenerated.toStringAsFixed(2)} kg',
                  Icons.scale,
                  Colors.teal,
                ),
              ),
              Container(width: 1, height: 40, color: Colors.grey.shade300),
              Expanded(
                child: _buildSummaryItem(
                  'Per Labour',
                  '${(record.totalWasteGenerated / (record.approxNoOfLabour > 0 ? record.approxNoOfLabour : 1)).toStringAsFixed(2)} kg',
                  Icons.person,
                  Colors.orange,
                ),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 12),
        
        // Waste breakdown
        Row(
          children: [
            Expanded(
              child: _buildWasteTypeCard(
                'Dry Waste',
                record.dryWasteGenerated,
                record.dryWasteDisposedThrough,
                Icons.dry_cleaning,
                Colors.orange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildWasteTypeCard(
                'Wet Waste',
                record.wetWasteGenerated,
                record.wetWasteDisposedThrough,
                Icons.water_drop,
                Colors.blue,
              ),
            ),
          ],
        ),
        
        if (record.notes.isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: const [
                    Icon(Icons.note_alt, size: 16, color: Colors.grey),
                    SizedBox(width: 4),
                    Text('Notes:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ],
                ),
                const SizedBox(height: 4),
                Text(record.notes, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ],
      ],
    );
  }
  
  Widget _buildSummaryItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 10,
            color: Colors.grey,
          ),
        ),
      ],
    );
  }
  
  Widget _buildWasteTypeCard(String type, double amount, String disposedThrough, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  type,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${amount.toStringAsFixed(2)} kg',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          if (disposedThrough.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              'Via: $disposedThrough',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
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
          const SizedBox(height: 16),
          _buildEfficiencyCard(),
        ],
      ),
    );
  }
  
  Widget _buildStatsCards() {
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
                'Avg Labour',
                (_wasteStats['avgLabourCount'] ?? 0).toStringAsFixed(0),
                Icons.people,
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
                'Total Waste',
                '${(_wasteStats['totalWasteGenerated'] ?? 0).toStringAsFixed(1)} kg',
                Icons.scale,
                Colors.orange,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStatCard(
                'Avg Per Labour',
                '${(_wasteStats['avgWastePerLabour'] ?? 0).toStringAsFixed(2)} kg',
                Icons.person,
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
                'Dry Waste',
                '${(_wasteStats['totalDryWaste'] ?? 0).toStringAsFixed(1)} kg',
                Icons.dry_cleaning,
                Colors.amber,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildStatCard(
                'Wet Waste',
                '${(_wasteStats['totalWetWaste'] ?? 0).toStringAsFixed(1)} kg',
                Icons.water_drop,
                Colors.cyan,
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
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
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
                  'Waste Generation Trend',
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
  
  Widget _buildEfficiencyCard() {
    final totalDry = _wasteStats['totalDryWaste'] ?? 0;
    final totalWet = _wasteStats['totalWetWaste'] ?? 0;
    final totalWaste = _wasteStats['totalWasteGenerated'] ?? 0;
    
    final dryPercentage = totalWaste > 0 ? (totalDry / totalWaste * 100) : 0;
    final wetPercentage = totalWaste > 0 ? (totalWet / totalWaste * 100) : 0;
    
    return Card(
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
                  'Waste Composition',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF00796B)),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildCompositionItem(
                    'Dry Waste',
                    dryPercentage.toDouble(),
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildCompositionItem(
                    'Wet Waste',
                    wetPercentage.toDouble(),
                    Colors.blue,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCompositionItem(String label, double percentage, Color color) {
    return Column(
      children: [
        CircularProgressIndicator(
          value: percentage / 100,
          backgroundColor: Colors.grey.shade200,
          valueColor: AlwaysStoppedAnimation<Color>(color),
          strokeWidth: 8,
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        Text(
          '${percentage.toStringAsFixed(1)}%',
          style: TextStyle(color: color, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }
}

// Data Model
class ConstructionPhaseWasteRecord {
  final int id;
  final DateTime date;
  final int approxNoOfLabour;
  final double dryWasteGenerated;
  final String dryWasteDisposedThrough;
  final double wetWasteGenerated;
  final String wetWasteDisposedThrough;
  final double totalWasteGenerated;
  final String notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  ConstructionPhaseWasteRecord({
    required this.id,
    required this.date,
    required this.approxNoOfLabour,
    required this.dryWasteGenerated,
    required this.dryWasteDisposedThrough,
    required this.wetWasteGenerated,
    required this.wetWasteDisposedThrough,
    required this.totalWasteGenerated,
    required this.notes,
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

  factory ConstructionPhaseWasteRecord.fromJson(Map<String, dynamic> json) {
    return ConstructionPhaseWasteRecord(
      id: json['id'] ?? 0,
      date: DateTime.parse(json['date'] ?? DateTime.now().toIso8601String()),
      approxNoOfLabour: json['approx_no_of_labour'] ?? 0,
      dryWasteGenerated: _safeParseDouble(json['dry_waste_generated']),
      dryWasteDisposedThrough: json['dry_waste_disposed_through'] ?? '',
      wetWasteGenerated: _safeParseDouble(json['wet_waste_generated']),
      wetWasteDisposedThrough: json['wet_waste_disposed_through'] ?? '',
      totalWasteGenerated: _safeParseDouble(json['total_waste_generated']),
      notes: json['notes'] ?? '',
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
      updatedAt: DateTime.parse(json['updated_at'] ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'date': DateFormat('yyyy-MM-dd').format(date),
      'approx_no_of_labour': approxNoOfLabour,
      'dry_waste_generated': dryWasteGenerated,
      'dry_waste_disposed_through': dryWasteDisposedThrough,
      'wet_waste_generated': wetWasteGenerated,
      'wet_waste_disposed_through': wetWasteDisposedThrough,
      'total_waste_generated': totalWasteGenerated,
      'notes': notes,
    };
  }
}