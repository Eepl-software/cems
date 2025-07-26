import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';

class CementDashboard extends StatefulWidget {
  const CementDashboard({Key? key}) : super(key: key);

  @override
  State<CementDashboard> createState() => _CementDashboardState();
}

class _CementDashboardState extends State<CementDashboard> with TickerProviderStateMixin {
  List<Map<String, dynamic>> _submissions = [];
  List<Map<String, dynamic>> _analytics = [];
  bool _isLoading = true;
  String? _errorMessage;
  late TabController _tabController;
  
  // Filters
  String? _selectedDateFrom;
  String? _selectedDateTo;
  String _selectedTimeRange = 'All Time';

  // Platform-aware API URLs
  static const String? _customBackendUrl = 'http://54.146.215.18:3000/api';
  
  static String get _backendApiUrl {
    if (_customBackendUrl != null) {
      return _customBackendUrl!;
    }
    
    if (Platform.isAndroid) {
      return 'http://10.0.2.2:3000/api';
    } else if (Platform.isIOS) {
      return 'http://localhost:3000/api';
    } else {
      return 'http://localhost:3000/api';
    }
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await Future.wait([
        _loadSubmissions(),
        _loadAnalytics(),
      ]);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load data: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadSubmissions() async {
    String url = '$_backendApiUrl/cement-submissions?limit=100';
    
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
      String url = '$_backendApiUrl/cement-analytics';
      
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
        // Fallback to local calculation
        _calculateAnalytics();
      }
    } catch (e) {
      // Fallback to local calculation
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
        // Count submissions per day
        dailyCounts[date] = (dailyCounts[date] ?? 0) + 1;
        
        // Sum weights per day
        double grossWeight = _parseWeight(submission['gross_weight']);
        double netWeight = _parseWeight(submission['net_weight']);
        
        dailyGrossWeight[date] = (dailyGrossWeight[date] ?? 0) + grossWeight;
        dailyNetWeight[date] = (dailyNetWeight[date] ?? 0) + netWeight;
        
        // Track unique vehicles per day
        String vehicle = submission['vehicle_number'] ?? '';
        if (vehicle.isNotEmpty) {
          dailyVehicles[date] ??= <String>{};
          dailyVehicles[date]!.add(vehicle);
        }
      }
    }

    // Convert to analytics format
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

    // Sort by date
    _analytics.sort((a, b) => a['date'].compareTo(b['date']));
  }

  double _parseWeight(String? weightStr) {
    if (weightStr == null || weightStr.isEmpty) return 0.0;
    
    // Extract number from string like "28000 KG"
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
      // Try to parse as number directly
      double? directParse = double.tryParse(value);
      if (directParse != null) return directParse;
      
      // Extract number from string like "28000 KG"
      RegExp regExp = RegExp(r'(\d+(?:\.\d+)?)');
      Match? match = regExp.firstMatch(value);
      
      if (match != null) {
        return double.tryParse(match.group(1)!) ?? 0.0;
      }
    }
    
    return 0.0;
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
                _loadData();
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
        break;
      case 'Last 30 Days':
        _selectedDateFrom = DateFormat('yyyy-MM-dd').format(now.subtract(const Duration(days: 30)));
        _selectedDateTo = DateFormat('yyyy-MM-dd').format(now);
        break;
      case 'This Month':
        _selectedDateFrom = DateFormat('yyyy-MM-dd').format(DateTime(now.year, now.month, 1));
        _selectedDateTo = DateFormat('yyyy-MM-dd').format(now);
        break;
      case 'All Time':
        _selectedDateFrom = null;
        _selectedDateTo = null;
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cement Dashboard'),
        backgroundColor: const Color(0xFF2E3B55),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.analytics), text: 'Analytics'),
            Tab(icon: Icon(Icons.table_chart), text: 'Data Table'),
            Tab(icon: Icon(Icons.bar_chart), text: 'Charts'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading cement data...'),
                ],
              ),
            )
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error, size: 64, color: Colors.red[300]),
                      const SizedBox(height: 16),
                      Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadData,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildAnalyticsTab(),
                    _buildDataTableTab(),
                    _buildChartsTab(),
                  ],
                ),
    );
  }

  Widget _buildAnalyticsTab() {
    if (_submissions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No cement submissions found'),
            Text('Submit some cement data to see analytics'),
          ],
        ),
      );
    }

    // Calculate summary stats
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
          // Summary Cards
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
          
          // Recent Submissions
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.history, color: Color(0xFF2E3B55)),
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
                          backgroundColor: const Color(0xFF2E3B55),
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
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: color),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDataTableTab() {
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
            headingRowColor: MaterialStateProperty.all(const Color(0xFF2E3B55)),
            headingTextStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
            columns: const [
              DataColumn(label: Text('Date')),
              DataColumn(label: Text('Vehicle')),
              DataColumn(label: Text('Driver')),
              DataColumn(label: Text('Gross Weight')),
              DataColumn(label: Text('Net Weight')),
              DataColumn(label: Text('Location')),
              DataColumn(label: Text('Actions')),
            ],
            rows: _submissions.map((submission) {
              return DataRow(
                cells: [
                  DataCell(Text(submission['date'] ?? 'N/A')),
                  DataCell(Text(submission['vehicle_number'] ?? 'N/A')),
                  DataCell(Text(submission['driver_number'] ?? 'N/A')),
                  DataCell(Text(submission['gross_weight'] ?? 'N/A')),
                  DataCell(Text(submission['net_weight'] ?? 'N/A')),
                  DataCell(Text('${submission['latitude']}, ${submission['longitude']}')),
                  DataCell(
                    IconButton(
                      icon: const Icon(Icons.visibility, color: Color(0xFF2E3B55)),
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
    if (_analytics.isEmpty) {
      return const Center(
        child: Text('No data for charts'),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          // Submissions Chart
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
                            color: const Color(0xFF2E3B55),
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
          
          // Weight Chart
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
                                toY: _parseNumericValue(entry.value['gross_weight'] ?? entry.value['total_gross_weight'] ?? 0) / 1000, // Convert to tons
                                color: Colors.blue,
                                width: 16,
                              ),
                              BarChartRodData(
                                toY: _parseNumericValue(entry.value['net_weight'] ?? entry.value['total_net_weight'] ?? 0) / 1000, // Convert to tons
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
}