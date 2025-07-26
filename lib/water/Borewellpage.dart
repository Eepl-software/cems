import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:ui' show TextDirection;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Import the water consumption widget
import '../water_consumption_widget.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class BorewellDataScreen extends StatefulWidget {
  const BorewellDataScreen({Key? key}) : super(key: key);

  @override
  _BorewellDataScreenState createState() => _BorewellDataScreenState();
}

class _BorewellDataScreenState extends State<BorewellDataScreen> with SingleTickerProviderStateMixin {
  List<Map<String, dynamic>> _data = [];
  List<Map<String, dynamic>> _cachedData = [];
  List<Map<String, dynamic>> _stats = [];
  bool _isLoading = false;
  bool _isLoadingStats = false;
  DateTime? _selectedDate;
  String? _searchQuery;
  String? _selectedBorewell;
  
  late TabController _tabController;
  
  // Statistics
  double _totalConsumed = 0;
  double _averageConsumption = 0;
  Map<String, double> _consumptionByLocation = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadCachedData();
    _fetchBorewellData();
    _fetchBorewellStats();
  }
  
  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedDataString = prefs.getString('borewell_data');
      if (cachedDataString != null) {
        final decoded = jsonDecode(cachedDataString);
        setState(() {
          _cachedData = List<Map<String, dynamic>>.from(decoded);
          if (_data.isEmpty) {
            _data = _cachedData;
            _calculateStatistics();
          }
        });
      }
    } catch (e) {
      print('Error loading cached data: $e');
    }
  }

  Future<void> _saveCachedData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('borewell_data', jsonEncode(_data));
    } catch (e) {
      print('Error saving cached data: $e');
    }
  }

  Future<void> _fetchBorewellData({bool showErrorDialog = true}) async {
    setState(() => _isLoading = true);
    try {
      String url = 'http://54.146.215.18:3000/borewell';
      
      // Apply filters
      List<String> queryParams = [];
      if (_selectedDate != null) {
        queryParams.add('date=${DateFormat('yyyy-MM-dd').format(_selectedDate!)}');
      }
      if (_searchQuery != null && _searchQuery!.isNotEmpty) {
        queryParams.add('search=$_searchQuery');
      }
      if (_selectedBorewell != null) {
        queryParams.add('borewell=$_selectedBorewell');
      }
      
      if (queryParams.isNotEmpty) {
        url += '?' + queryParams.join('&');
      }

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        
        // Normalize the data to ensure numeric values
        final normalizedData = List<Map<String, dynamic>>.from(data['data']).map((item) {
          return {
            ...item,
            'water_consumed': double.tryParse(item['water_consumed'].toString()) ?? 0.0,
            'in_kld': double.tryParse(item['in_kld'].toString()) ?? 0.0,
            'out_kld': double.tryParse(item['out_kld'].toString()) ?? 0.0,
          };
        }).toList();
        
        setState(() {
          _data = normalizedData;
          _cachedData = normalizedData;
          _calculateStatistics();
        });
        
        // Save to cache
        _saveCachedData();
      } else if (_cachedData.isNotEmpty) {
        // Use cached data if request fails but we have cached data
        setState(() {
          _data = _cachedData;
          _calculateStatistics();
        });
        _showError('Using cached data. Please check your connection.');
      } else {
        throw Exception('Failed to load data: ${response.reasonPhrase}');
      }
    } catch (e) {
      _showError('Error: ${e.toString()}');
      if (showErrorDialog && _cachedData.isEmpty) {
        _showRetryDialog();
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  Future<void> _fetchBorewellStats() async {
    setState(() => _isLoadingStats = true);
    try {
      final response = await http.get(Uri.parse('http://54.146.215.18:3000/borewell/stats'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _stats = List<Map<String, dynamic>>.from(data['data']);
        });
      }
    } catch (e) {
      print('Error fetching stats: $e');
    } finally {
      setState(() => _isLoadingStats = false);
    }
  }
  
  void _calculateStatistics() {
    if (_data.isEmpty) return;
    
    // Calculate total and average consumption
    _totalConsumed = _data.fold(0, (sum, item) => sum + ((item['water_consumed'] as num).toDouble()));
    _averageConsumption = _totalConsumed / _data.length;
    
    // Calculate consumption by location
    _consumptionByLocation = {};
    for (var item in _data) {
      final location = item['located_at'] ?? 'Unknown';
      final consumed = (item['water_consumed'] as num).toDouble();
      
      if (_consumptionByLocation.containsKey(location)) {
        _consumptionByLocation[location] = _consumptionByLocation[location]! + consumed;
      } else {
        _consumptionByLocation[location] = consumed;
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: Colors.white,
          onPressed: () {},
        ),
      ),
    );
  }
  
  void _showRetryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red),
            SizedBox(width: 8),
            Text('Connection Error'),
          ],
        ),
        content: Text('Failed to load borewell data. Would you like to retry?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _fetchBorewellData(showErrorDialog: false);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1FA7F0),
            ),
            child: Text('Retry'),
          ),
        ],
      ),
    );
  }
  
  void _resetFilters() {
    setState(() {
      _selectedDate = null;
      _searchQuery = null;
      _selectedBorewell = null;
    });
    _fetchBorewellData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Borewell Water Management',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF1FA7F0),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_alt),
            onPressed: _showFilterDialog,
            tooltip: 'Filter data',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _resetFilters,
            tooltip: 'Reset filters',
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: const [
            Tab(
              icon: Icon(Icons.bar_chart),
              text: 'Dashboard',
            ),
            Tab(
              icon: Icon(Icons.list),
              text: 'Data Table',
            ),
          ],
        ),
      ),
      body: _isLoading && _data.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading data...'),
                ],
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildDashboardTab(),
                _buildDataTableTab(),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddDataDialog,
        backgroundColor: const Color(0xFF1FA7F0),
        child: const Icon(Icons.add),
        tooltip: 'Add Borewell Data',
      ),
    );
  }
  
  Widget _buildDashboardTab() {
    return RefreshIndicator(
      onRefresh: () => _fetchBorewellData(showErrorDialog: false),
      color: const Color(0xFF1FA7F0),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Active filters
            if (_hasActiveFilters())
              _buildActiveFilters(),
              
            // Statistics cards
            _buildStatisticsCards(),
            
            const SizedBox(height: 16),
            
            // Water consumption chart
            _buildWaterConsumptionWidget(),
            
            const SizedBox(height: 16),
            
            // Location breakdown
            _buildLocationBreakdown(),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDataTableTab() {
    return RefreshIndicator(
      onRefresh: () => _fetchBorewellData(showErrorDialog: false),
      color: const Color(0xFF1FA7F0),
      child: Column(
        children: [
          // Active filters
          if (_hasActiveFilters())
            _buildActiveFilters(),
            
          // Data table
          Expanded(
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              scrollDirection: Axis.horizontal,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Card(
                  elevation: 4,
                  margin: const EdgeInsets.all(8.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8.0),
                  ),
                  child: DataTable(
                    headingRowColor: MaterialStateProperty.all(Colors.blue.shade50),
                    columnSpacing: 20.0,
                    headingTextStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1FA7F0),
                      fontSize: 16,
                    ),
                    dataRowColor: MaterialStateProperty.resolveWith(
                      (Set states) {
                        if (states.contains(MaterialState.selected)) {
                          return Colors.grey.shade100;
                        }
                        return null;
                      },
                    ),
                    border: TableBorder.all(
                      color: Colors.grey.shade300,
                      width: 1,
                    ),
                    columns: const [
                      DataColumn(
                        label: Text('Date', 
                          style: TextStyle(fontWeight: FontWeight.bold)
                        ),
                      ),
                      DataColumn(
                        label: Text('Borewell No', 
                          style: TextStyle(fontWeight: FontWeight.bold)
                        ),
                      ),
                      DataColumn(
                        label: Text('Located At', 
                          style: TextStyle(fontWeight: FontWeight.bold)
                        ),
                      ),
                      DataColumn(
                        label: Text('Initial (KLD)', 
                          style: TextStyle(fontWeight: FontWeight.bold)
                        ),
                      ),
                      DataColumn(
                        label: Text('Final (KLD)', 
                          style: TextStyle(fontWeight: FontWeight.bold)
                        ),
                      ),
                      DataColumn(
                        label: Text('Consumed (KLD)', 
                          style: TextStyle(fontWeight: FontWeight.bold)
                        ),
                      ),
                    ],
                    rows: _data.map((item) {
                      return DataRow(
                        cells: [
                          DataCell(
                            Text(
                              DateFormat('yyyy-MM-dd').format(
                                DateTime.parse(item['date']),
                              ),
                            ),
                          ),
                          DataCell(Text(item['borewell_no'])),
                          DataCell(Text(item['located_at'])),
                          DataCell(Text(item['in_kld'].toString())),
                          DataCell(Text(item['out_kld'].toString())),
                          DataCell(
                            Text(
                              item['water_consumed'].toString(),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: (item['water_consumed'] as num).toDouble() > 10 
                                    ? Colors.red 
                                    : Colors.green,
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _hasActiveFilters() {
    return _selectedDate != null || 
           (_searchQuery != null && _searchQuery!.isNotEmpty) || 
           _selectedBorewell != null;
  }
  
  Widget _buildActiveFilters() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.filter_list, size: 18, color: Color(0xFF1FA7F0)),
                  SizedBox(width: 8),
                  Text(
                    'Active Filters:',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8.0,
                runSpacing: 8.0,
                children: [
                  if (_selectedDate != null)
                    Chip(
                      label: Text(
                        'Date: ${DateFormat('yyyy-MM-dd').format(_selectedDate!)}',
                      ),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      onDeleted: () {
                        setState(() => _selectedDate = null);
                        _fetchBorewellData();
                      },
                      backgroundColor: Colors.blue.shade50,
                    ),
                  if (_searchQuery != null && _searchQuery!.isNotEmpty)
                    Chip(
                      label: Text('Search: $_searchQuery'),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      onDeleted: () {
                        setState(() => _searchQuery = null);
                        _fetchBorewellData();
                      },
                      backgroundColor: Colors.blue.shade50,
                    ),
                  if (_selectedBorewell != null)
                    Chip(
                      label: Text('Borewell: $_selectedBorewell'),
                      deleteIcon: const Icon(Icons.close, size: 18),
                      onDeleted: () {
                        setState(() => _selectedBorewell = null);
                        _fetchBorewellData();
                      },
                      backgroundColor: Colors.blue.shade50,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildStatisticsCards() {
    final formatter = NumberFormat('#,##0.00');
    
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            title: 'Total Consumption',
            value: '${formatter.format(_totalConsumed)} KLD',
            icon: Icons.water_drop,
            color: Colors.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            title: 'Average Consumption',
            value: '${formatter.format(_averageConsumption)} KLD',
            icon: Icons.bar_chart,
            color: Colors.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            title: 'Records',
            value: _data.length.toString(),
            icon: Icons.analytics,
            color: Colors.orange,
          ),
        ),
      ],
    );
  }
  
  Widget _buildStatCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
          child: Column(
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  Widget _buildWaterConsumptionWidget() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.water_drop, color: Colors.blue.shade700),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Water Consumption Trend',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1FA7F0),
                      ),
                    ),
                  ],
                ),
                
                // Period selector
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Last 7 days',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // Chart placeholder
            _isLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          height: 40,
                          width: 40,
                          child: CircularProgressIndicator(
                            strokeWidth: 3,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.blue.shade300),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text('Loading chart data...'),
                      ],
                    ),
                  )
                : _data.isEmpty 
                ? Container(
                    height: 180,
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.bar_chart, size: 48, color: Colors.grey),
                        SizedBox(height: 16),
                        Text('No consumption data available',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : Container(
                    height: 180,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.blue.shade100.withOpacity(0.2),
                          Colors.blue.withOpacity(0.05),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: CustomPaint(
                      size: const Size(double.infinity, 180),
                      painter: SimpleChartPainter(
                        data: _data.isNotEmpty 
                            ? _data.reversed.take(7).toList() 
                            : [],
                      ),
                    ),
                  ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildLocationBreakdown() {
    if (_consumptionByLocation.isEmpty) {
      return const SizedBox.shrink();
    }
    
    // Sort locations by consumption (highest first)
    final sortedLocations = _consumptionByLocation.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.location_on, color: Colors.green.shade700),
                ),
                const SizedBox(width: 12),
                const Text(
                  'Consumption by Location',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1FA7F0),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Location bars
            ...sortedLocations.take(5).map((entry) => _buildLocationBar(
              entry.key, 
              entry.value, 
              _totalConsumed,
            )),
          ],
        ),
      ),
    );
  }
  
  Widget _buildLocationBar(String location, double value, double total) {
    final percentage = total > 0 ? (value / total) * 100 : 0;
    final formatter = NumberFormat('#,##0.00');
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  location,
                  style: const TextStyle(fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${formatter.format(value)} KLD (${percentage.toStringAsFixed(1)}%)',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Stack(
            children: [
              // Background
              Container(
                height: 8,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              // Progress
              AnimatedContainer(
                duration: const Duration(milliseconds: 800),
                curve: Curves.easeInOut,
                height: 8,
                width: MediaQuery.of(context).size.width * (percentage / 100) - 64,
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width - 64,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade300, Colors.blue.shade600],
                  ),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  void _showFilterDialog() {
    // Get unique borewell numbers
    final borewellNumbers = _data
        .map((item) => item['borewell_no'].toString())
        .toSet()
        .toList();
    
    String? tempSelectedBorewell = _selectedBorewell;
    DateTime? tempSelectedDate = _selectedDate;
    String? tempSearchQuery = _searchQuery;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.filter_alt, color: Color(0xFF1FA7F0)),
            SizedBox(width: 8),
            Text('Filter Data'),
          ],
        ),
        content: StatefulBuilder(
          builder: (context, setState) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date filter
                  ListTile(
                    title: Text(
                      tempSelectedDate != null
                          ? 'Date: ${DateFormat('yyyy-MM-dd').format(tempSelectedDate!)}'
                          : 'Select Date',
                    ),
                    leading: const Icon(Icons.calendar_today),
                    onTap: () async {
                      final DateTime? picked = await showDatePicker(
                        context: context,
                        initialDate: tempSelectedDate ?? DateTime.now(),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2030),
                        builder: (context, child) {
                          return Theme(
                            data: Theme.of(context).copyWith(
                              colorScheme: ColorScheme.light(
                                primary: Color(0xFF1FA7F0),
                              ),
                            ),
                            child: child!,
                          );
                        },
                      );
                      if (picked != null) {
                        setState(() => tempSelectedDate = picked);
                      }
                    },
                  ),
                  
                  const Divider(),
                  
                  // Borewell filter
                  if (borewellNumbers.isNotEmpty) ...[
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Text(
                        'Borewell Number:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    
                    // Borewell list
                    Container(
                      height: 150,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ListView(
                        children: [
                          // All option
                          RadioListTile<String?>(
                            title: const Text('All Borewells'),
                            value: null,
                            groupValue: tempSelectedBorewell,
                            onChanged: (value) {
                              setState(() => tempSelectedBorewell = value);
                            },
                          ),
                          // Borewell options
                          ...borewellNumbers.map((borewell) => RadioListTile<String>(
                            title: Text(borewell),
                            value: borewell,
                            groupValue: tempSelectedBorewell,
                            onChanged: (value) {
                              setState(() => tempSelectedBorewell = value);
                            },
                          )),
                        ],
                      ),
                    ),
                  ],
                  
                  const SizedBox(height: 16),
                  
                  // Search field
                  TextField(
                    decoration: const InputDecoration(
                      labelText: 'Search',
                      hintText: 'Enter location or borewell number',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                    controller: TextEditingController(text: tempSearchQuery),
                    onChanged: (value) => setState(() => tempSearchQuery = value.isEmpty ? null : value),
                  ),
                ],
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              setState(() {
                _selectedBorewell = tempSelectedBorewell;
                _selectedDate = tempSelectedDate;
                _searchQuery = tempSearchQuery;
              });
              _fetchBorewellData();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1FA7F0),
            ),
            child: const Text('Apply Filters'),
          ),
        ],
      ),
    );
  }
  
  Future<void> _showAddDataDialog() async {
  final formKey = GlobalKey<FormState>();
  final borewellNoController = TextEditingController();
  final locatedAtController = TextEditingController();
  final inKldController = TextEditingController();
  final outKldController = TextEditingController();
  final notesController = TextEditingController();
  DateTime selectedDate = DateTime.now();
  double? calculatedConsumption;
  bool isSubmitting = false;
  bool isLoadingLocation = false;
  
  // Location variables
  double? latitude;
  double? longitude;
  
  // Function to calculate consumption preview
  void updateConsumptionPreview() {
    if (inKldController.text.isNotEmpty && 
        outKldController.text.isNotEmpty &&
        double.tryParse(inKldController.text) != null &&
        double.tryParse(outKldController.text) != null) {
      calculatedConsumption = double.parse(outKldController.text) - double.parse(inKldController.text);
    } else {
      calculatedConsumption = null;
    }
  }
  
  // Function to get current location
  Future<void> getCurrentLocation(StateSetter setStateDialog) async {
    setStateDialog(() => isLoadingLocation = true);
    
    try {
      // Check location permission
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permission denied');
        }
      }
      
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permission permanently denied');
      }
      
      // Get current position
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high
      );
      
      // Reverse geocoding to get address
      List<Placemark> placemarks = await placemarkFromCoordinates(
        position.latitude, 
        position.longitude
      );
      
      if (placemarks.isNotEmpty) {
        Placemark place = placemarks[0];
        String address = '';
        
        // Build address from components
        if (place.name != null && place.name!.isNotEmpty) {
          address += place.name! + ', ';
        }
        if (place.subLocality != null && place.subLocality!.isNotEmpty) {
          address += place.subLocality! + ', ';
        }
        if (place.locality != null && place.locality!.isNotEmpty) {
          address += place.locality! + ', ';
        }
        if (place.administrativeArea != null && place.administrativeArea!.isNotEmpty) {
          address += place.administrativeArea!;
        }
        
        // Update location info
        setStateDialog(() {
          locatedAtController.text = address;
          latitude = position.latitude;
          longitude = position.longitude;
        });
        
      } else {
        // Use coordinates as fallback
        setStateDialog(() {
          locatedAtController.text = 'Lat: ${position.latitude}, Long: ${position.longitude}';
          latitude = position.latitude;
          longitude = position.longitude;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error getting location: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setStateDialog(() => isLoadingLocation = false);
    }
  }

  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 8,
          child: Form(
            key: formKey,
            child: Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1FA7F0).withOpacity(0.2),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.water_drop, color: Color(0xFF1FA7F0)),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Add Borewell Data',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1FA7F0),
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  
                  // Scrollable content
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Date picker
                          InkWell(
                            onTap: () async {
                              // Calculate a safe date range that includes the current date
                              final now = DateTime.now();
                              final firstDate = DateTime(now.year - 5, now.month, now.day);
                              final lastDate = DateTime(now.year + 5, now.month, now.day);
                              
                              final DateTime? picked = await showDatePicker(
                                context: context,
                                initialDate: selectedDate,
                                firstDate: firstDate,
                                lastDate: lastDate,
                                builder: (context, child) {
                                  return Theme(
                                    data: Theme.of(context).copyWith(
                                      colorScheme: const ColorScheme.light(
                                        primary: Color(0xFF1FA7F0),
                                      ),
                                    ),
                                    child: child!,
                                  );
                                },
                              );
                              if (picked != null) {
                                setState(() => selectedDate = picked);
                              }
                            },
                            child: InputDecorator(
                              decoration: InputDecoration(
                                labelText: 'Date',
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                prefixIcon: const Icon(Icons.calendar_today),
                              ),
                              child: Text(
                                DateFormat('yyyy-MM-dd').format(selectedDate),
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Borewell Number
                          TextFormField(
                            controller: borewellNoController,
                            decoration: InputDecoration(
                              labelText: 'Borewell Number',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              prefixIcon: const Icon(Icons.pin_drop),
                              hintText: 'Enter borewell number/ID',
                            ),
                            validator: (value) =>
                                value!.isEmpty ? 'Please enter borewell number' : null,
                          ),
                          const SizedBox(height: 16),
                          
                          // Location with auto-detect button
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: locatedAtController,
                                  decoration: InputDecoration(
                                    labelText: 'Located At',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    prefixIcon: const Icon(Icons.location_on),
                                    hintText: 'Enter location or auto-detect',
                                    suffixIcon: latitude != null && longitude != null 
                                      ? Tooltip(
                                          message: 'Location detected\nLat: $latitude\nLng: $longitude',
                                          child: Icon(Icons.check_circle, color: Colors.green),
                                        )
                                      : null,
                                  ),
                                  validator: (value) =>
                                      value!.isEmpty ? 'Please enter location' : null,
                                  maxLines: 2,
                                  minLines: 1,
                                ),
                              ),
                              const SizedBox(width: 8),
                              // Auto-detect location button
                              Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  ElevatedButton(
                                    onPressed: isLoadingLocation 
                                      ? null 
                                      : () => getCurrentLocation(setState),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF1FA7F0),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                    ),
                                    child: isLoadingLocation
                                      ? const SizedBox(
                                          height: 20,
                                          width: 20,
                                          child: CircularProgressIndicator(
                                            color: Colors.white,
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.my_location),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          
                          // Show lat/long if detected
                          if (latitude != null && longitude != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0, left: 8.0),
                              child: Text(
                                'GPS: ${latitude!.toStringAsFixed(6)}, ${longitude!.toStringAsFixed(6)}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                ),
                              ),
                            ),
                            
                          const SizedBox(height: 16),
                          
                          // Water readings section header
                          Container(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: const [
                                Icon(Icons.water_drop, color: Color(0xFF1FA7F0), size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'Water Readings',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          
                          // Initial and Final readings
                          Row(
                            children: [
                              Expanded(
                                child: TextFormField(
                                  controller: inKldController,
                                  decoration: InputDecoration(
                                    labelText: 'Initial Reading (KLD)',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    prefixIcon: const Icon(Icons.water),
                                    hintText: 'e.g. 100.50',
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  validator: (value) => value!.isEmpty 
                                      ? 'Required' 
                                      : (double.tryParse(value) == null ? 'Invalid number' : null),
                                  onChanged: (_) {
                                    setState(() {
                                      updateConsumptionPreview();
                                    });
                                  },
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  controller: outKldController,
                                  decoration: InputDecoration(
                                    labelText: 'Final Reading (KLD)',
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    prefixIcon: const Icon(Icons.water_drop),
                                    hintText: 'e.g. 120.75',
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  validator: (value) => value!.isEmpty 
                                      ? 'Required' 
                                      : (double.tryParse(value) == null ? 'Invalid number' : null),
                                  onChanged: (_) {
                                    setState(() {
                                      updateConsumptionPreview();
                                    });
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          
                          // Consumption preview
                          if (calculatedConsumption != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: calculatedConsumption! < 0 
                                    ? Colors.red.shade50 
                                    : Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: calculatedConsumption! < 0 
                                      ? Colors.red.shade200 
                                      : Colors.blue.shade200,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    calculatedConsumption! < 0 
                                        ? Icons.error_outline 
                                        : Icons.info_outline,
                                    color: calculatedConsumption! < 0 
                                        ? Colors.red 
                                        : Colors.blue,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      calculatedConsumption! < 0
                                          ? 'Error: Final reading must be greater than initial reading'
                                          : 'Calculated Consumption: ${calculatedConsumption!.toStringAsFixed(2)} KLD',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        color: calculatedConsumption! < 0 
                                            ? Colors.red 
                                            : Colors.blue,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const SizedBox(height: 16),
                          
                          // Notes field (UI only - not sent to server)
                          TextFormField(
                            controller: notesController,
                            decoration: InputDecoration(
                              labelText: 'Notes (Local Only)',
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              prefixIcon: const Icon(Icons.note),
                              hintText: 'Enter local notes (not saved to server)',
                              helperText: 'These notes are for your reference only',
                            ),
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 20),
                  const Divider(height: 1),
                  const SizedBox(height: 20),
                  
                  // Action Buttons
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.pop(context),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          side: const BorderSide(color: Color(0xFF1FA7F0)),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(color: Color(0xFF1FA7F0)),
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: isSubmitting 
                            ? null 
                            : () async {
                                if (formKey.currentState!.validate()) {
                                  setState(() => isSubmitting = true);
                                  
                                  try {
                                    final inKld = double.parse(inKldController.text);
                                    final outKld = double.parse(outKldController.text);
                                    
                                    // Validate that final reading is greater than initial
                                    if (outKld < inKld) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Final reading must be greater than initial reading'),
                                          backgroundColor: Colors.red,
                                        ),
                                      );
                                      setState(() => isSubmitting = false);
                                      return;
                                    }
                                    
                                    // Create API request body - Note: while we store lat/lng locally,
                                    // we don't send them to the server since the borewell schema doesn't include them
                                    final Map<String, dynamic> requestBody = {
                                      'date': selectedDate.toIso8601String().split('T')[0],
                                      'borewell_no': borewellNoController.text,
                                      'located_at': locatedAtController.text,
                                      'in_kld': inKld,
                                      'out_kld': outKld,
                                      'water_consumed': outKld - inKld,
                                    };
                                    
                                    final response = await http.post(
                                      Uri.parse('http://54.146.215.18:3000/borewell'),
                                      headers: {'Content-Type': 'application/json'},
                                      body: jsonEncode(requestBody),
                                    );
                
                                    if (response.statusCode == 201) {
                                      // If we have location data, save it locally
                                      if (latitude != null && longitude != null) {
                                        // Here you could save the location data to a local database if desired
                                        // For now we just have it in memory
                                      }
                                      
                                      Navigator.pop(context);
                                      _fetchBorewellData();
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Row(
                                            children: [
                                              Icon(Icons.check_circle, color: Colors.white),
                                              SizedBox(width: 8),
                                              Text('Data added successfully!'),
                                            ],
                                          ),
                                          backgroundColor: Colors.green,
                                          behavior: SnackBarBehavior.floating,
                                          duration: Duration(seconds: 3),
                                        ),
                                      );
                                    } else if (response.statusCode == 409) {
                                      // Handle conflict - entry exists for this date/borewell
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('An entry already exists for this date and borewell number'),
                                          backgroundColor: Colors.orange,
                                          behavior: SnackBarBehavior.floating,
                                        ),
                                      );
                                      setState(() => isSubmitting = false);
                                    } else {
                                      final errorResponse = jsonDecode(response.body);
                                      throw Exception(errorResponse['error'] ?? 'Failed to add data');
                                    }
                                  } catch (e) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Error: ${e.toString()}'),
                                        backgroundColor: Colors.red,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                    setState(() => isSubmitting = false);
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1FA7F0),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: isSubmitting
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text(
                                'Submit',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );
}
}
class SimpleChartPainter extends CustomPainter {
  final List<Map<String, dynamic>> data;

  SimpleChartPainter({required this.data});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) {
      // Draw a message when no data is available
      final textPaint = Paint()
        ..color = Colors.grey
        ..style = PaintingStyle.fill;
      
      const textMessage = 'No data available';
      
      // Use drawRect and drawLine instead of TextPainter
      final messageRect = Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2),
        width: 150,
        height: 30,
      );
      
      // Draw a centered icon instead
      final iconPaint = Paint()
        ..color = Colors.grey.withOpacity(0.5)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      
      // Draw chart icon
      const iconSize = 40.0;
      final iconRect = Rect.fromCenter(
        center: Offset(size.width / 2, size.height / 2 - 15),
        width: iconSize,
        height: iconSize,
      );
      
      // Draw bar chart
      canvas.drawRect(iconRect, iconPaint);
      
      // Draw bars
      const barWidth = 8.0;
      const barGap = 4.0;
      final startX = size.width / 2 - (3 * barWidth + 2 * barGap) / 2;
      
      canvas.drawRect(
        Rect.fromLTWH(startX, size.height / 2 - 10, barWidth, 20),
        iconPaint,
      );
      
      canvas.drawRect(
        Rect.fromLTWH(startX + barWidth + barGap, size.height / 2 - 25, barWidth, 35),
        iconPaint,
      );
      
      canvas.drawRect(
        Rect.fromLTWH(startX + 2 * (barWidth + barGap), size.height / 2 - 15, barWidth, 25),
        iconPaint,
      );
      
      return;
    }

    // Define paint objects
    final linePaint = Paint()
      ..color = const Color(0xFF1FA7F0)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0xFF1FA7F0).withOpacity(0.5),
          const Color(0xFF1FA7F0).withOpacity(0.0),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    
    final pointPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..style = PaintingStyle.fill;
      
    final pointBorderPaint = Paint()
      ..color = const Color(0xFF1FA7F0)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    
    // Calculate max value for scaling
    double maxValue = 0;
    for (var item in data) {
      final value = (item['water_consumed'] as num).toDouble();
      if (value > maxValue) maxValue = value;
    }
    
    // Add 20% padding to max value
    maxValue = maxValue * 1.2;
    if (maxValue == 0) maxValue = 1.0; // Avoid division by zero
    
    // Create path for line
    final path = Path();
    final fillPath = Path();
    
    // Calculate x step
    final xStep = size.width / (data.length - 1 > 0 ? data.length - 1 : 1);
    
    // Draw line and points
    for (int i = 0; i < data.length; i++) {
      final value = (data[i]['water_consumed'] as num).toDouble();
      final x = i * xStep;
      final y = size.height - (value / maxValue * size.height) - 15; // Space for labels
      
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
      
      // Draw point
      canvas.drawCircle(Offset(x, y), 5, pointPaint);
      canvas.drawCircle(Offset(x, y), 5, pointBorderPaint);
      
      // Draw date label without TextPainter
      // Use small circle markers instead
      final dateLabelPaint = Paint()
        ..color = Colors.grey.shade400
        ..style = PaintingStyle.fill;
        
      canvas.drawCircle(Offset(x, size.height - 5), 2, dateLabelPaint);
    }
    
    // Complete fill path
    fillPath.lineTo(size.width, size.height - 15);
    fillPath.lineTo(0, size.height - 15);
    fillPath.close();
    
    // Draw fill and line
    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}