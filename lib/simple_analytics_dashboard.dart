
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:prestige_park_groove/treated_water_dashboard_old.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'dart:io';
import 'package:image_picker/image_picker.dart';

class SimpleAnalyticsDashboard extends StatefulWidget {
  const SimpleAnalyticsDashboard({Key? key}) : super(key: key);

  @override
  SimpleAnalyticsDashboardState createState() => SimpleAnalyticsDashboardState();
}

class SimpleAnalyticsDashboardState extends State<SimpleAnalyticsDashboard> {
  late SharedPreferences _prefs;
  List<DailyWaterData> _historicalData = [];
  DateTimeRange? _selectedDateRange;
  String _selectedSortBy = 'date';
  bool _isAscending = false;
  String _selectedMetric = 'treatedWater';
  
  // OCR Components
  final ImagePicker _picker = ImagePicker();
  
  @override
  void initState() {
    super.initState();
    _initializeData();
  }
  
  Future<void> _initializeData() async {
    _prefs = await SharedPreferences.getInstance();
    await _loadHistoricalData();
  }
  
  Future<void> _loadHistoricalData() async {
    final keys = _prefs.getKeys()
        .where((key) => key.startsWith('treated_water_data_'))
        .toList();
    
    List<DailyWaterData> data = [];
    
    for (String key in keys) {
      final jsonString = _prefs.getString(key);
      if (jsonString != null) {
        try {
          final Map<String, dynamic> jsonData = json.decode(jsonString);
          data.add(DailyWaterData.fromJson(jsonData));
        } catch (e) {
          print('Error parsing data for key $key: $e');
        }
      }
    }
    
    setState(() {
      _historicalData = data;
      _sortData();
    });
  }
  
  void _sortData() {
    _historicalData.sort((a, b) {
      int comparison = 0;
      
      switch (_selectedSortBy) {
        case 'date':
          comparison = a.date.compareTo(b.date);
        case 'labourers':
          comparison = a.labourers.compareTo(b.labourers);
        case 'treatedWater':
          comparison = a.treatedWaterAvailable.compareTo(b.treatedWaterAvailable);
        case 'freshWater':
          comparison = a.totalFreshWaterRequired.compareTo(b.totalFreshWaterRequired);
      }
      
      return _isAscending ? comparison : -comparison;
    });
  }
  
  List<DailyWaterData> get _filteredData {
    if (_selectedDateRange == null) return _historicalData;
    
    return _historicalData.where((data) {
      return data.date.isAfter(_selectedDateRange!.start.subtract(const Duration(days: 1))) &&
             data.date.isBefore(_selectedDateRange!.end.add(const Duration(days: 1)));
    }).toList();
  }
  
  Future<void> _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _selectedDateRange,
    );
    
    if (picked != null) {
      setState(() {
        _selectedDateRange = picked;
      });
    }
  }
  
  // Simplified OCR demo
  Future<void> _showOCRDemo() async {
    final XFile? image = await _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 80,
    );
    
    if (image != null) {
      // Simulate OCR processing
      await Future.delayed(const Duration(seconds: 2));
      
      // Mock vehicle number detection
      final List<String> mockNumbers = [
        'KA01T8743',
        'KA01F1234',
        'HR74B2818',
        'KA02T9876'
      ];
      
      final detectedNumber = mockNumbers[DateTime.now().millisecond % mockNumbers.length];
      
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('🔍 OCR Results (Demo)'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.file(
                  File(image.path),
                  height: 200,
                  fit: BoxFit.cover,
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'Detected Vehicle Number:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        detectedNumber,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '(Demo Mode - Real OCR available with ML Kit)',
                        style: TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Vehicle number detected: $detectedNumber'),
                        backgroundColor: Colors.green,
                      ),
                    );
                  }
                },
                child: const Text('Use Number'),
              ),
            ],
          ),
        );
      }
    }
  }
  
  // Simplified Report Generation
  Future<void> _generateReport() async {
    final data = _filteredData;
    
    // Create a simple text report
    final StringBuffer report = StringBuffer();
    report.writeln('WATER MANAGEMENT ANALYTICS REPORT');
    report.writeln('Generated: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(DateTime.now())}');
    report.writeln('=' * 50);
    report.writeln();
    
    report.writeln('SUMMARY STATISTICS');
    report.writeln('Total Records: ${data.length}');
    if (_selectedDateRange != null) {
      report.writeln('Date Range: ${DateFormat('yyyy-MM-dd').format(_selectedDateRange!.start)} to ${DateFormat('yyyy-MM-dd').format(_selectedDateRange!.end)}');
    } else {
      report.writeln('Date Range: All Time');
    }
    report.writeln('Total Labour Days: ${data.fold(0, (sum, item) => sum + item.labourers)}');
    if (data.isNotEmpty) {
      report.writeln('Average Daily Labourers: ${(data.fold(0, (sum, item) => sum + item.labourers) / data.length).toStringAsFixed(1)}');
    }
    report.writeln();
    
    report.writeln('DETAILED DATA');
    report.writeln('Date\t\tLabourers\tFresh Water(L)\tTreated Water(L)');
    report.writeln('-' * 60);
    
    for (final item in data) {
      report.writeln('${DateFormat('yyyy-MM-dd').format(item.date)}\t${item.labourers}\t\t${item.totalFreshWaterRequired.toStringAsFixed(0)}\t\t${item.treatedWaterAvailable.toStringAsFixed(0)}');
    }
    
    // Show report in dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('📊 Analytics Report'),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(
            child: Text(
              report.toString(),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Report generated successfully!'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }
  
  Widget _buildSimpleChart() {
    final data = _filteredData;
    if (data.isEmpty) {
      return const SizedBox(
        height: 200,
        child: Center(
          child: Text('No data available for chart'),
        ),
      );
    }
    
    // Simple bar chart using containers
    double maxValue = 0;
    for (final item in data) {
      double value = 0;
      switch (_selectedMetric) {
        case 'treatedWater':
          value = item.treatedWaterAvailable;
        case 'freshWater':
          value = item.totalFreshWaterRequired;
        case 'labourers':
          value = item.labourers.toDouble() * 1000; // Scale for visibility
      }
      if (value > maxValue) maxValue = value;
    }
    
    return Container(
      height: 300,
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            'Water Usage Trends - ${_selectedMetric.replaceAllMapped(RegExp(r'([A-Z])'), (match) => ' ${match.group(1)}')}',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: data.take(10).map((item) {
                double value = 0;
                switch (_selectedMetric) {
                  case 'treatedWater':
                    value = item.treatedWaterAvailable;
                  case 'freshWater':
                    value = item.totalFreshWaterRequired;
                  case 'labourers':
                    value = item.labourers.toDouble() * 1000;
                }
                
                final height = maxValue > 0 ? (value / maxValue) * 200 : 0.0;
                final color = _selectedMetric == 'treatedWater' 
                    ? Colors.green 
                    : _selectedMetric == 'freshWater' 
                        ? Colors.blue 
                        : Colors.orange;
                
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          height: height,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat('MM/dd').format(item.date),
                          style: const TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildFilterControls() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Filters & Controls',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            
            // Date Range Filter
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _selectDateRange,
                    icon: const Icon(Icons.date_range),
                    label: Text(
                      _selectedDateRange != null
                          ? '${DateFormat('MMM dd').format(_selectedDateRange!.start)} - ${DateFormat('MMM dd').format(_selectedDateRange!.end)}'
                          : 'Select Date Range',
                    ),
                  ),
                ),
                if (_selectedDateRange != null)
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _selectedDateRange = null;
                      });
                    },
                    icon: const Icon(Icons.clear),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Sort Controls
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedSortBy,
                    decoration: const InputDecoration(
                      labelText: 'Sort By',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'date', child: Text('Date')),
                      DropdownMenuItem(value: 'labourers', child: Text('Labourers')),
                      DropdownMenuItem(value: 'treatedWater', child: Text('Treated Water')),
                      DropdownMenuItem(value: 'freshWater', child: Text('Fresh Water')),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedSortBy = value!;
                        _sortData();
                      });
                    },
                  ),
                ),
                const SizedBox(width: 16),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isAscending = !_isAscending;
                      _sortData();
                    });
                  },
                  icon: Icon(_isAscending ? Icons.arrow_upward : Icons.arrow_downward),
                  label: Text(_isAscending ? 'Asc' : 'Desc'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Chart Metric Selection
            DropdownButtonFormField<String>(
              value: _selectedMetric,
              decoration: const InputDecoration(
                labelText: 'Chart Metric',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'treatedWater', child: Text('Treated Water')),
                DropdownMenuItem(value: 'freshWater', child: Text('Fresh Water')),
                DropdownMenuItem(value: 'labourers', child: Text('Labourers')),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedMetric = value!;
                });
              },
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildActionButtons() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Actions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _generateReport,
                  icon: const Icon(Icons.picture_as_pdf),
                  label: const Text('Generate Report'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[700],
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _showOCRDemo,
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('OCR Demo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _loadHistoricalData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Refresh Data'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildDataTable() {
    final data = _filteredData;
    
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Historical Data (${data.length} records)',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            if (data.isEmpty)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('No data available'),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Date')),
                    DataColumn(label: Text('Labourers')),
                    DataColumn(label: Text('Fresh Water (L)')),
                    DataColumn(label: Text('Treated Water (L)')),
                    DataColumn(label: Text('Activity')),
                  ],
                  rows: data.map((item) {
                    return DataRow(
                      cells: [
                        DataCell(Text(DateFormat('yyyy-MM-dd').format(item.date))),
                        DataCell(Text(item.labourers.toString())),
                        DataCell(Text(item.totalFreshWaterRequired.toStringAsFixed(0))),
                        DataCell(Text(item.treatedWaterAvailable.toStringAsFixed(0))),
                        DataCell(Text(item.activity ?? 'N/A')),
                      ],
                    );
                  }).toList(),
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
          'Analytics Dashboard',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.deepPurple[800],
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline, color: Colors.white),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Analytics Dashboard Help'),
                  content: const Text(
                    'Features:\n'
                    '• Date filtering and sorting\n'
                    '• Simple bar charts\n'
                    '• Text report generation\n'
                    '• OCR number plate demo\n'
                    '• Historical data analysis',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('OK'),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.deepPurple[50]!, Colors.white],
          ),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              _buildFilterControls(),
              const SizedBox(height: 16),
              _buildActionButtons(),
              const SizedBox(height: 16),
              
              // Chart Section
              Card(
                elevation: 4,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _buildSimpleChart(),
                ),
              ),
              const SizedBox(height: 16),
              _buildDataTable(),
            ],
          ),
        ),
      ),
    );
  }
}

class DailyWaterData {
  final DateTime date;
  final int labourers;
  final double totalFreshWaterRequired;
  
  final double treatedWaterAvailable;
  final String? activity;
  final List<TreatedWaterTankerDetail> tankers;
  
  DailyWaterData({
    required this.date,
    required this.labourers,
    required this.totalFreshWaterRequired,
    required this.treatedWaterAvailable,
    this.activity,
    this.tankers = const [],
  });
  
  factory DailyWaterData.fromJson(Map<String, dynamic> json) {
    return DailyWaterData(
      date: DateTime.parse(json['date']),
      labourers: json['labourers'] ?? 0,
      totalFreshWaterRequired: (json['metrics']?['totalFreshWaterRequired'] ?? 0.0).toDouble(),
      treatedWaterAvailable: (json['metrics']?['treatedWaterAvailable'] ?? 0.0).toDouble(),
      activity: json['activity'],
      tankers: (json['treatedWaterTankers'] as List<dynamic>?)
          ?.map((t) => TreatedWaterTankerDetail.fromJson(t))
          .toList() ?? [],
    );
  }
}