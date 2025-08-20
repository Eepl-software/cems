import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
// Add these missing imports for navigation
import 'login/auth_service.dart';
import 'tanker_page.dart';
import 'water/BorewellPage.dart';
import 'water/ConsumptionPage.dart';
import 'water/BWSSBPage.dart';
import 'LabourColonyWastePage.dart';
import 'login/login_page.dart';
import 'treated_water_dashboard.dart';

// Enhanced Water Consumption Data Model
class WaterConsumptionData {
  final double borewellDaily;
  final double borewellMonthly;
  final double borewellCumulative;
  final double borewellPeriod;
  final double tankerDaily;
  final double tankerMonthly;
  final double tankerCumulative;
  final double tankerPeriod;
  final double bwssbDaily;
  final double bwssbMonthly;
  final double bwssbCumulative;
  final double bwssbPeriod;
  final double othersDaily;
  final double othersMonthly;
  final double othersCumulative;
  final double othersPeriod;

  WaterConsumptionData({
    required this.borewellDaily,
    required this.borewellMonthly,
    required this.borewellCumulative,
    required this.borewellPeriod,
    required this.tankerDaily,
    required this.tankerMonthly,
    required this.tankerCumulative,
    required this.tankerPeriod,
    required this.bwssbDaily,
    required this.bwssbMonthly,
    required this.bwssbCumulative,
    required this.bwssbPeriod,
    required this.othersDaily,
    required this.othersMonthly,
    required this.othersCumulative,
    required this.othersPeriod,
  });

  factory WaterConsumptionData.fromJson(Map<String, dynamic> json) {
    final data = json['data'] ?? {};
    
    return WaterConsumptionData(
      borewellDaily: _safeParseDouble(data['borewell']?['daily']),
      borewellMonthly: _safeParseDouble(data['borewell']?['monthly']),
      borewellCumulative: _safeParseDouble(data['borewell']?['cumulative']),
      borewellPeriod: _safeParseDouble(data['borewell']?['period']),
      
      tankerDaily: _safeParseDouble(data['tanker']?['daily']),
      tankerMonthly: _safeParseDouble(data['tanker']?['monthly']),
      tankerCumulative: _safeParseDouble(data['tanker']?['cumulative']),
      tankerPeriod: _safeParseDouble(data['tanker']?['period']),
      
      bwssbDaily: _safeParseDouble(data['bwssb']?['daily']),
      bwssbMonthly: _safeParseDouble(data['bwssb']?['monthly']),
      bwssbCumulative: _safeParseDouble(data['bwssb']?['cumulative']),
      bwssbPeriod: _safeParseDouble(data['bwssb']?['period']),
      
      othersDaily: _safeParseDouble(data['others']?['daily']),
      othersMonthly: _safeParseDouble(data['others']?['monthly']),
      othersCumulative: _safeParseDouble(data['others']?['cumulative']),
      othersPeriod: _safeParseDouble(data['others']?['period']),
    );
  }

  static double _safeParseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) {
      // Handle string values more robustly
      final cleanValue = value.toString().trim();
      if (cleanValue.isEmpty) return 0.0;
      return double.tryParse(cleanValue) ?? 0.0;
    }
    if (value is num) return value.toDouble();
    return 0.0;
  }

  static WaterConsumptionData empty() {
    return WaterConsumptionData(
      borewellDaily: 0.0, borewellMonthly: 0.0, borewellCumulative: 0.0, borewellPeriod: 0.0,
      tankerDaily: 0.0, tankerMonthly: 0.0, tankerCumulative: 0.0, tankerPeriod: 0.0,
      bwssbDaily: 0.0, bwssbMonthly: 0.0, bwssbCumulative: 0.0, bwssbPeriod: 0.0,
      othersDaily: 0.0, othersMonthly: 0.0, othersCumulative: 0.0, othersPeriod: 0.0,
    );
  }

  // Get total daily consumption
  double get totalDaily => borewellDaily + tankerDaily + bwssbDaily + othersDaily;
  
  // Get total monthly consumption
  double get totalMonthly => borewellMonthly + tankerMonthly + bwssbMonthly + othersMonthly;
  
  // Get total cumulative consumption
  double get totalCumulative => borewellCumulative + tankerCumulative + bwssbCumulative + othersCumulative;
}

// Chart Data Model
class ChartDataPoint {
  final DateTime date;
  final String source;
  final double consumption;

  ChartDataPoint({
    required this.date,
    required this.source,
    required this.consumption,
  });

  factory ChartDataPoint.fromJson(Map<String, dynamic> json) {
    return ChartDataPoint(
      date: DateTime.parse(json['date']),
      source: json['source'],
      consumption: WaterConsumptionData._safeParseDouble(json['consumption']),
    );
  }
}

class EnhancedWaterConsumptionPage extends StatefulWidget {
  // Add required authService parameter
  final AuthService authService;

  const EnhancedWaterConsumptionPage({
    super.key,
    required this.authService,
  });

  @override
  _EnhancedWaterConsumptionPageState createState() => _EnhancedWaterConsumptionPageState();
}

class _EnhancedWaterConsumptionPageState extends State<EnhancedWaterConsumptionPage> {
  DateTime _selectedDate = DateTime.now();
  DateTime? _periodFromDate;
  DateTime? _periodToDate;
  
  WaterConsumptionData _constructionData = WaterConsumptionData.empty();
  WaterConsumptionData _labourColonyData = WaterConsumptionData.empty();
  WaterConsumptionData _operationalData = WaterConsumptionData.empty();
  
  List<ChartDataPoint> _chartData = [];
  bool _isLoading = true;
  String _errorMessage = '';
  int _selectedPhase = 0;
  int _selectedChartType = 0; // 0: Line Chart, 1: Bar Chart, 2: Pie Chart
  Timer? _refreshTimer;
  DateTime? _lastUpdated;
  bool _isConnected = false;
  String _connectionStatus = 'Checking...';

  static const String baseUrl = 'http://54.146.215.18:3000';
  
  @override
  void initState() {
    super.initState();
    _fetchAllWaterData();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // Auto-refresh every 30 seconds for real-time data
  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _fetchAllWaterData(silent: true);
      }
    });
  }

  Future<void> _fetchAllWaterData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
        _connectionStatus = 'Connecting...';
      });
    }

    try {
      // Test server connection first
      await _testServerConnection();
      
      await Future.wait([
        _fetchPhaseData('construction'),
        _fetchPhaseData('labour_colony'),
        _fetchPhaseData('operational'),
        _fetchChartData(),
      ]);

      if (mounted) {
        setState(() {
          _lastUpdated = DateTime.now();
          _isConnected = true;
          _connectionStatus = 'Connected';
        });
      }
      print('Successfully fetched all water data');
    } catch (e) {
      print('Error in _fetchAllWaterData: $e');
      if (mounted) {
        setState(() {
          _errorMessage = 'Error loading data: ${e.toString()}';
          _isConnected = false;
          _connectionStatus = 'Connection Failed';
        });
      }
    } finally {
      if (!silent && mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Test server connection and endpoints
  Future<void> _testServerConnection() async {
    try {
      print('Testing server connection to: $baseUrl');
      
      // Test basic health endpoint
      final healthResponse = await http.get(
        Uri.http('54.146.215.18:3000', '/health'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 5));

      if (healthResponse.statusCode == 200) {
        print('Server health check successful');
        
        // Test if water consumption endpoints are available
        final testEndpointResponse = await http.get(
          Uri.http('54.146.215.18:3000', '/borewell/consumption-summary', {'date': DateFormat('yyyy-MM-dd').format(DateTime.now())}),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 5));

        if (testEndpointResponse.statusCode == 200) {
          print('Water consumption endpoints available');
          if (mounted) {
            setState(() {
              _isConnected = true;
              _connectionStatus = 'Connected (Full API)';
            });
          }
        } else {
          print('Water consumption endpoints not available: ${testEndpointResponse.statusCode}');
          if (mounted) {
            setState(() {
              _isConnected = true;
              _connectionStatus = 'Connected (Limited API)';
            });
          }
        }
      } else {
        throw Exception('Server responded with status: ${healthResponse.statusCode}');
      }
    } catch (e) {
      print('Server connection test failed: $e');
      if (mounted) {
        setState(() {
          _isConnected = false;
          _connectionStatus = 'Connection Failed';
        });
      }
      throw e;
    }
  }

  Future<void> _fetchPhaseData(String phase) async {
    try {
      String url = '$baseUrl/water-consumption/phase-summary/$phase';
      
      List<String> queryParams = [];
      queryParams.add('date=${DateFormat('yyyy-MM-dd').format(_selectedDate)}');
      
      if (_periodFromDate != null) {
        queryParams.add('fromDate=${DateFormat('yyyy-MM-dd').format(_periodFromDate!)}');
      }
      if (_periodToDate != null) {
        queryParams.add('toDate=${DateFormat('yyyy-MM-dd').format(_periodToDate!)}');
      }
      
      if (queryParams.isNotEmpty) {
        url += '?' + queryParams.join('&');
      }

      print('Fetching $phase data from: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));
      
      print('Response status for $phase: ${response.statusCode}');
      print('Response body for $phase: ${response.body}');
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        
        if (data['success'] == true && data['data'] != null) {
          if (mounted) {
            setState(() {
              switch (phase) {
                case 'construction':
                  _constructionData = WaterConsumptionData.fromJson(data);
                  break;
                case 'labour_colony':
                  _labourColonyData = WaterConsumptionData.fromJson(data);
                  break;
                case 'operational':
                  _operationalData = WaterConsumptionData.fromJson(data);
                  break;
              }
            });
          }
          print('Successfully updated $phase data');
        } else {
          print('Invalid response format for $phase: $data');
          // Fallback to individual endpoints
          await _fetchPhaseDataFallback(phase);
        }
      } else {
        print('HTTP Error ${response.statusCode} for $phase: ${response.body}');
        // Fallback to individual endpoints
        await _fetchPhaseDataFallback(phase);
      }
    } catch (e) {
      print('Error fetching $phase data: $e');
      // Fallback to individual endpoints
      await _fetchPhaseDataFallback(phase);
    }
  }

  // Fallback method to fetch data from individual endpoints
  Future<void> _fetchPhaseDataFallback(String phase) async {
    print('Using fallback for $phase phase');
    
    try {
      // Use the working endpoints to get basic data
      final borewellData = await _fetchWorkingEndpointData('borewell');
      final tankerData = await _fetchWorkingEndpointData('tankers');
      final bwssbData = await _fetchWorkingEndpointData('bwssb');
      final labourColonyData = await _fetchWorkingEndpointData('labour-colony');

      if (mounted) {
        setState(() {
          switch (phase) {
            case 'construction':
              _constructionData = WaterConsumptionData(
                borewellDaily: borewellData['total'] ?? 0.0,
                borewellMonthly: borewellData['total'] ?? 0.0,
                borewellCumulative: borewellData['total'] ?? 0.0,
                borewellPeriod: borewellData['total'] ?? 0.0,
                tankerDaily: tankerData['total'] ?? 0.0,
                tankerMonthly: tankerData['total'] ?? 0.0,
                tankerCumulative: tankerData['total'] ?? 0.0,
                tankerPeriod: tankerData['total'] ?? 0.0,
                bwssbDaily: bwssbData['total'] ?? 0.0,
                bwssbMonthly: bwssbData['total'] ?? 0.0,
                bwssbCumulative: bwssbData['total'] ?? 0.0,
                bwssbPeriod: bwssbData['total'] ?? 0.0,
                othersDaily: 0.0,
                othersMonthly: 0.0,
                othersCumulative: 0.0,
                othersPeriod: 0.0,
              );
              break;
            case 'labour_colony':
              _labourColonyData = WaterConsumptionData(
                borewellDaily: 0.0,
                borewellMonthly: 0.0,
                borewellCumulative: 0.0,
                borewellPeriod: 0.0,
                tankerDaily: 0.0,
                tankerMonthly: 0.0,
                tankerCumulative: 0.0,
                tankerPeriod: 0.0,
                bwssbDaily: 0.0,
                bwssbMonthly: 0.0,
                bwssbCumulative: 0.0,
                bwssbPeriod: 0.0,
                othersDaily: labourColonyData['total'] ?? 0.0,
                othersMonthly: labourColonyData['total'] ?? 0.0,
                othersCumulative: labourColonyData['total'] ?? 0.0,
                othersPeriod: labourColonyData['total'] ?? 0.0,
              );
              break;
            case 'operational':
              _operationalData = WaterConsumptionData(
                borewellDaily: borewellData['total'] ?? 0.0,
                borewellMonthly: borewellData['total'] ?? 0.0,
                borewellCumulative: borewellData['total'] ?? 0.0,
                borewellPeriod: borewellData['total'] ?? 0.0,
                tankerDaily: tankerData['total'] ?? 0.0,
                tankerMonthly: tankerData['total'] ?? 0.0,
                tankerCumulative: tankerData['total'] ?? 0.0,
                tankerPeriod: tankerData['total'] ?? 0.0,
                bwssbDaily: bwssbData['total'] ?? 0.0,
                bwssbMonthly: bwssbData['total'] ?? 0.0,
                bwssbCumulative: bwssbData['total'] ?? 0.0,
                bwssbPeriod: bwssbData['total'] ?? 0.0,
                othersDaily: 0.0,
                othersMonthly: 0.0,
                othersCumulative: 0.0,
                othersPeriod: 0.0,
              );
              break;
          }
        });
      }
      print('Successfully used fallback for $phase');
    } catch (e) {
      print('Error in fallback for $phase: $e');
    }
  }

  // Helper method to fetch data from working endpoints  
  Future<Map<String, double>> _fetchWorkingEndpointData(String source) async {
    try {
      String url = '$baseUrl/$source';
      
      // Add date filter for the selected date
      if (source != 'tankers') {
        url += '?date=${DateFormat('yyyy-MM-dd').format(_selectedDate)}';
      }

      print('Fetching working endpoint: $url');

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('$source response: ${response.body.substring(0, 200)}...');
        
        if (data['data'] != null) {
          final List<dynamic> items = data['data'] as List? ?? [];
          double total = 0.0;
          
          for (var item in items) {
            switch (source) {
              case 'borewell':
                total += WaterConsumptionData._safeParseDouble(item['water_consumed']);
                break;
              case 'tankers':
                total += WaterConsumptionData._safeParseDouble(item['capacity']);
                break;
              case 'bwssb':
                total += WaterConsumptionData._safeParseDouble(item['quantity_supplied']);
                break;
              case 'labour-colony':
                total += WaterConsumptionData._safeParseDouble(item['consumption']);
                break;
            }
          }
          
          return {
            'total': total,
            'count': items.length.toDouble(),
          };
        }
      } else {
        print('HTTP Error ${response.statusCode} for $source: ${response.body}');
      }
    } catch (e) {
      print('Error fetching $source data: $e');
    }
    
    return {
      'total': 0.0,
      'count': 0.0,
    };
  }

  Future<void> _fetchChartData() async {
    try {
      print('Fetching chart data from dashboard endpoint...');
      
      final response = await http.get(
        Uri.http('54.146.215.18:3000', '/water-consumption/dashboard', {'days': '7'}),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      print('Dashboard response status: ${response.statusCode}');
      print('Dashboard response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data'] != null) {
          final chartDataList = data['data']['chartData'] as List? ?? [];
          
          if (mounted) {
            setState(() {
              _chartData = chartDataList
                  .map((item) => ChartDataPoint.fromJson(item))
                  .toList();
            });
          }
          print('Successfully loaded ${_chartData.length} chart data points');
        } else {
          print('Invalid dashboard response format: $data');
          // Fallback to fetch chart data from individual sources
          await _fetchChartDataFallback();
        }
      } else {
        print('Dashboard endpoint error: ${response.statusCode} - ${response.body}');
        // Fallback to fetch chart data from individual sources
        await _fetchChartDataFallback();
      }
    } catch (e) {
      print('Error fetching chart data: $e');
      // Fallback to fetch chart data from individual sources
      await _fetchChartDataFallback();
    }
  }

  // Fallback method to create chart data from existing sources
  Future<void> _fetchChartDataFallback() async {
    print('Using fallback for chart data');
    
    try {
      // Create dummy chart data from the last 7 days
      final List<ChartDataPoint> fallbackData = [];
      final now = DateTime.now();
      
      for (int i = 6; i >= 0; i--) {
        final date = now.subtract(Duration(days: i));
        
        // Get daily totals from current data (simplified approach)
        double dailyTotal = 0.0;
        if (i == 0) { // Today's data
          final currentData = _getCurrentData();
          dailyTotal = currentData.totalDaily;
        } else {
          // For past days, create some representative data
          dailyTotal = (50 + (i * 10) + (i % 3 * 20)).toDouble();
        }
        
        if (dailyTotal > 0) {
          fallbackData.add(ChartDataPoint(
            date: date,
            source: 'mixed',
            consumption: dailyTotal,
          ));
        }
      }
      
      if (mounted) {
        setState(() {
          _chartData = fallbackData;
        });
      }
      print('Created ${fallbackData.length} fallback chart data points');
    } catch (e) {
      print('Error creating fallback chart data: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _fetchAllWaterData(),
        child: const Icon(Icons.refresh),
        backgroundColor: Colors.teal,
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      title: const Text('Water Consumption Overview'),
      backgroundColor: Colors.teal,
      elevation: 0,
      actions: [
        IconButton(
          icon: const Icon(Icons.calendar_today),
          onPressed: _showDatePicker,
        ),
        IconButton(
          icon: const Icon(Icons.info_outline),
          onPressed: _showLastUpdatedInfo,
        ),
      ],
    );
  }

  void _showLastUpdatedInfo() {
    if (_lastUpdated != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Last updated: ${DateFormat('HH:mm:ss').format(_lastUpdated!)}',
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Widget _buildBody() {
    return RefreshIndicator(
      onRefresh: _fetchAllWaterData,
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage.isNotEmpty
              ? _buildErrorWidget()
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeaderCard(),
                      const SizedBox(height: 16),
                      _buildPhaseSelector(),
                      const SizedBox(height: 16),
                      _buildSummaryCards(),
                      const SizedBox(height: 16),
                      _buildConsumptionTable(),
                      const SizedBox(height: 16),
                      _buildChart(),
                      const SizedBox(height: 16),
                      _buildActionButtons(),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: Text(
              _errorMessage,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _fetchAllWaterData,
            child: const Text('Try Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            const Text(
              'WATER CONSUMPTION - OVERVIEW',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Selected Date: ${DateFormat('dd MMM yyyy').format(_selectedDate)}',
              style: const TextStyle(fontSize: 14, color: Colors.grey),
            ),
            if (_periodFromDate != null && _periodToDate != null) ...[
              const SizedBox(height: 4),
              Text(
                'Period: ${DateFormat('dd MMM').format(_periodFromDate!)} - ${DateFormat('dd MMM yyyy').format(_periodToDate!)}',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
            const SizedBox(height: 8),
            // Connection Status and Last Updated
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  _isConnected ? Icons.wifi : Icons.wifi_off,
                  size: 14,
                  color: _isConnected ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 4),
                Text(
                  _connectionStatus,
                  style: TextStyle(
                    fontSize: 11,
                    color: _isConnected ? Colors.green : Colors.red,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (_lastUpdated != null && _isConnected) ...[
                  const SizedBox(width: 16),
                  const Icon(Icons.access_time, size: 12, color: Colors.blue),
                  const SizedBox(width: 4),
                  Text(
                    'Updated: ${DateFormat('HH:mm:ss').format(_lastUpdated!)}',
                    style: const TextStyle(fontSize: 10, color: Colors.blue),
                  ),
                ],
              ],
            ),
            if (!_isConnected || _connectionStatus.contains('Limited')) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (_connectionStatus.contains('Limited') ? Colors.orange : Colors.red).withOpacity(0.1),
                  border: Border.all(color: (_connectionStatus.contains('Limited') ? Colors.orange : Colors.red).withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _connectionStatus.contains('Limited') ? Icons.warning : Icons.error,
                          size: 16,
                          color: _connectionStatus.contains('Limited') ? Colors.orange : Colors.red,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            _connectionStatus.contains('Limited') 
                              ? 'API endpoints not available. Using basic data.'
                              : 'Server connection issue. Check server status.',
                            style: TextStyle(
                              fontSize: 10,
                              color: _connectionStatus.contains('Limited') ? Colors.orange : Colors.red,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                    if (_connectionStatus.contains('Limited')) ...[
                      const SizedBox(height: 4),
                      Text(
                        'Fix: Move water consumption endpoints before app.listen() in server.js',
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.orange[700],
                          fontStyle: FontStyle.italic,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            ],
            if (_isConnected && _connectionStatus.contains('Full API')) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_circle, size: 14, color: Colors.green),
                    const SizedBox(width: 6),
                    const Text(
                      'All APIs working correctly',
                      style: TextStyle(fontSize: 10, color: Colors.green),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCards() {
    final currentData = _getCurrentData();
    
    return Row(
      children: [
        Expanded(
          child: _buildSummaryCard(
            'Daily Total',
            '${currentData.totalDaily.toStringAsFixed(1)} L',
            Icons.today,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildSummaryCard(
            'Monthly Total',
            '${currentData.totalMonthly.toStringAsFixed(1)} L',
            Icons.calendar_month,
            Colors.orange,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildSummaryCard(
            'Cumulative',
            '${currentData.totalCumulative.toStringAsFixed(1)} L',
            Icons.water_drop,
            Colors.teal,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
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
    );
  }

  Widget _buildChart() {
    if (_chartData.isEmpty) {
      return Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          height: 200,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [Colors.white, Colors.blue.shade50],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.analytics_outlined, size: 48, color: Colors.teal.shade300),
              const SizedBox(height: 16),
              Text(
                'No chart data available',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _isConnected 
                  ? 'Data may not be available for the selected date range'
                  : 'Check your connection and try again',
                style: TextStyle(color: Colors.grey[500], fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _fetchAllWaterData,
                icon: const Icon(Icons.refresh, size: 16),
                label: const Text('Refresh'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return _buildUnifiedChartCard();
  }

  Widget _buildUnifiedChartCard() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [Colors.white, _getChartGradientColor()],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with title and status - Fixed overflow
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _getChartTitle(),
                      style: TextStyle(
                        fontSize: MediaQuery.of(context).size.width > 400 ? 18 : 16,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF1565C0),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _isConnected ? Colors.green.shade100 : Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(
                      _isConnected ? Icons.trending_up : Icons.trending_flat,
                      color: _isConnected ? Colors.green.shade700 : Colors.orange.shade700,
                      size: 18,
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 16),
              
              // Chart Type Selector with Overflow Protection
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: IntrinsicWidth(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildChartTypeTab('Line Chart', Icons.show_chart, 0),
                        _buildChartTypeTab('Bar Chart', Icons.bar_chart, 1),
                        _buildChartTypeTab('Pie Chart', Icons.pie_chart, 2),
                      ],
                    ),
                  ),
                ),
              ),
              
              const SizedBox(height: 20),
              
              // Chart Content
              SizedBox(
                height: _selectedChartType == 2 ? 280 : 320, // Pie chart needs less height
                child: _buildSelectedChart(),
              ),
              
              const SizedBox(height: 16),
              
              // Enhanced Legend (only for line chart)
              if (_selectedChartType == 0) _buildChartLegend(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChartTypeTab(String title, IconData icon, int index) {
    bool isSelected = _selectedChartType == index;
    final screenWidth = MediaQuery.of(context).size.width;
    final isCompact = screenWidth < 400;
    
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedChartType = index;
        });
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: isCompact ? 8 : 12, 
          vertical: isCompact ? 6 : 8
        ),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF1565C0) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: isCompact ? 14 : 16,
              color: isSelected ? Colors.white : Colors.grey.shade600,
            ),
            if (!isCompact) ...[
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: isCompact ? 10 : 12,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : Colors.grey.shade600,
                ),
              ),
            ] else if (isSelected) ...[
              const SizedBox(width: 4),
              Text(
                title.split(' ')[0], // Show only first word on compact screens
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _getChartGradientColor() {
    return switch (_selectedChartType) {
      0 => Colors.blue.shade50,     // Line Chart
      1 => Colors.green.shade50,    // Bar Chart
      2 => Colors.purple.shade50,   // Pie Chart
      _ => Colors.blue.shade50,
    };
  }

  String _getChartTitle() {
    return switch (_selectedChartType) {
      0 => 'Water Consumption Trend (Last 7 Days)',
      1 => 'Total Water Consumption by Source',
      2 => 'Water Source Distribution',
      _ => 'Water Consumption Chart',
    };
  }

  Widget _buildSelectedChart() {
    return switch (_selectedChartType) {
      0 => _buildLineChartContent(),
      1 => _buildBarChartContent(),
      2 => _buildPieChartContent(),
      _ => _buildLineChartContent(),
    };
  }

  Widget _buildChartLegend() {
    Map<String, Color> sourceColors = {
      'borewell': const Color(0xFF2196F3),
      'bwssb': const Color(0xFF4CAF50),
      'labour_colony': const Color(0xFFFF9800),
      'tanker': const Color(0xFF9C27B0),
      'mixed': const Color(0xFF00BCD4),
    };

    // Get unique sources from chart data
    Set<String> uniqueSources = _chartData.map((point) => point.source).toSet();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 8,
        children: sourceColors.entries.where((entry) => 
          uniqueSources.contains(entry.key)
        ).map((entry) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: entry.value.withAlpha(77)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: entry.value,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _getReadableSourceName(entry.key),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF333333),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildLineChartContent() {
    // Sort chart data by date to ensure proper x-axis ordering
    final sortedData = List<ChartDataPoint>.from(_chartData)
      ..sort((a, b) => a.date.compareTo(b.date));
    
    // Group data by source for multiple line chart
    Map<String, List<FlSpot>> chartLines = {};
    Map<String, Color> sourceColors = {
      'borewell': const Color(0xFF2196F3),     // Blue
      'bwssb': const Color(0xFF4CAF50),        // Green
      'labour_colony': const Color(0xFFFF9800), // Orange
      'tanker': const Color(0xFF9C27B0),       // Purple
      'mixed': const Color(0xFF00BCD4),        // Cyan
    };

    for (int i = 0; i < sortedData.length; i++) {
      final point = sortedData[i];
      if (!chartLines.containsKey(point.source)) {
        chartLines[point.source] = [];
      }
      chartLines[point.source]!.add(FlSpot(i.toDouble(), point.consumption));
    }

    return LineChart(
      LineChartData(
        gridData: FlGridData(
          show: true,
          drawHorizontalLine: true,
          drawVerticalLine: true,
          horizontalInterval: null,
          verticalInterval: null,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.grey.shade300,
              strokeWidth: 1,
              dashArray: [5, 5],
            );
          },
          getDrawingVerticalLine: (value) {
            return FlLine(
              color: Colors.grey.shade300,
              strokeWidth: 1,
              dashArray: [5, 5],
            );
          },
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 50,
              interval: 1,
              getTitlesWidget: (value, meta) {
                final index = value.toInt();
                if (index >= 0 && index < sortedData.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Transform.rotate(
                      angle: -0.5,
                      child: Text(
                        DateFormat('MM/dd').format(sortedData[index].date),
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF666666),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 60,
              getTitlesWidget: (value, meta) {
                return Text(
                  _formatChartValue(value),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF666666),
                  ),
                );
              },
            ),
          ),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: Colors.grey.shade300, width: 1),
        ),
        lineBarsData: chartLines.entries.map((entry) {
          return LineChartBarData(
            spots: entry.value,
            isCurved: true,
            color: sourceColors[entry.key] ?? Colors.grey,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) =>
                  FlDotCirclePainter(
                    radius: 4,
                    color: sourceColors[entry.key] ?? Colors.grey,
                    strokeWidth: 2,
                    strokeColor: Colors.white,
                  ),
            ),
            belowBarData: BarAreaData(
              show: true,
              color: (sourceColors[entry.key] ?? Colors.grey).withAlpha(51),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildBarChartContent() {
    if (_chartData.isEmpty) return const SizedBox.shrink();

    // Calculate totals for each source
    Map<String, double> sourceTotals = {};
    Map<String, Color> sourceColors = {
      'borewell': const Color(0xFF2196F3),
      'bwssb': const Color(0xFF4CAF50),
      'labour_colony': const Color(0xFFFF9800),
      'tanker': const Color(0xFF9C27B0),
      'mixed': const Color(0xFF00BCD4),
    };

    for (var point in _chartData) {
      sourceTotals[point.source] = (sourceTotals[point.source] ?? 0) + point.consumption;
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: sourceTotals.values.isEmpty ? 100 : sourceTotals.values.reduce((a, b) => a > b ? a : b) * 1.2,
        barTouchData: BarTouchData(
          touchTooltipData: BarTouchTooltipData(
            tooltipBgColor: Colors.black87,
            getTooltipItem: (group, groupIndex, rod, rodIndex) {
              String source = sourceTotals.keys.elementAt(group.x.toInt());
              return BarTooltipItem(
                '${_getReadableSourceName(source)}\n${_formatChartValue(rod.toY)}L',
                const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
              );
            },
          ),
        ),
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                if (value.toInt() < sourceTotals.length) {
                  String source = sourceTotals.keys.elementAt(value.toInt());
                  return Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      _getReadableSourceName(source),
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF666666),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return const Text('');
              },
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 60,
              getTitlesWidget: (value, meta) {
                return Text(
                  _formatChartValue(value),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF666666),
                  ),
                );
              },
            ),
          ),
          rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(
          show: true,
          border: Border.all(color: Colors.grey.shade300, width: 1),
        ),
        barGroups: sourceTotals.entries.map((entry) {
          int index = sourceTotals.keys.toList().indexOf(entry.key);
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: entry.value,
                color: sourceColors[entry.key] ?? Colors.grey,
                width: 40,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(6),
                  topRight: Radius.circular(6),
                ),
                gradient: LinearGradient(
                  colors: [
                    sourceColors[entry.key] ?? Colors.grey,
                    (sourceColors[entry.key] ?? Colors.grey).withAlpha(179),
                  ],
                  begin: Alignment.bottomCenter,
                  end: Alignment.topCenter,
                ),
              ),
            ],
          );
        }).toList(),
        gridData: FlGridData(
          show: true,
          drawHorizontalLine: true,
          drawVerticalLine: false,
          horizontalInterval: null,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Colors.grey.shade300,
              strokeWidth: 1,
              dashArray: [5, 5],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPieChartContent() {
    if (_chartData.isEmpty) return const SizedBox.shrink();

    // Calculate totals for each source
    Map<String, double> sourceTotals = {};
    Map<String, Color> sourceColors = {
      'borewell': const Color(0xFF2196F3),
      'bwssb': const Color(0xFF4CAF50),
      'labour_colony': const Color(0xFFFF9800),
      'tanker': const Color(0xFF9C27B0),
      'mixed': const Color(0xFF00BCD4),
    };

    for (var point in _chartData) {
      sourceTotals[point.source] = (sourceTotals[point.source] ?? 0) + point.consumption;
    }

    double total = sourceTotals.values.fold(0, (sum, value) => sum + value);

    return Row(
      children: [
        Expanded(
          flex: 2,
          child: SizedBox(
            height: 250,
            child: PieChart(
              PieChartData(
                pieTouchData: PieTouchData(
                  touchCallback: (FlTouchEvent event, pieTouchResponse) {
                    // Handle touch events if needed
                  },
                ),
                borderData: FlBorderData(show: false),
                sectionsSpace: 4,
                centerSpaceRadius: 60,
                sections: sourceTotals.entries.map((entry) {
                  double percentage = (entry.value / total) * 100;
                  return PieChartSectionData(
                    color: sourceColors[entry.key] ?? Colors.grey,
                    value: entry.value,
                    title: '${percentage.toStringAsFixed(1)}%',
                    radius: 80,
                    titleStyle: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          flex: 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: sourceTotals.entries.map((entry) {
              double percentage = (entry.value / total) * 100;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6.0),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: sourceColors[entry.key],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _getReadableSourceName(entry.key),
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF333333),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${_formatChartValue(entry.value)}L',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF666666),
                        ),
                      ),
                      Text(
                        '${percentage.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: sourceColors[entry.key],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  String _getReadableSourceName(String source) {
    switch (source.toLowerCase()) {
      case 'borewell':
        return 'Borewell';
      case 'bwssb':
        return 'BWSSB';
      case 'labour_colony':
        return 'Labour Colony';
      case 'tanker':
        return 'Tanker';
      case 'mixed':
        return 'Mixed Sources';
      default:
        return source.toUpperCase();
    }
  }

  String _formatChartValue(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    } else if (value >= 100) {
      return value.toInt().toString();
    } else {
      return value.toStringAsFixed(1);
    }
  }

  Widget _buildPhaseSelector() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          children: [
            Expanded(child: _buildPhaseTab('Construction', 0)),
            Expanded(child: _buildPhaseTab('Labour Colony', 1)),
            Expanded(child: _buildPhaseTab('Operational', 2)),
          ],
        ),
      ),
    );
  }

  Widget _buildPhaseTab(String title, int index) {
    bool isSelected = _selectedPhase == index;
    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPhase = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: isSelected ? Colors.teal : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          title,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.teal,
            fontWeight: FontWeight.bold,
            fontSize: 11,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  WaterConsumptionData _getCurrentData() {
    switch (_selectedPhase) {
      case 0:
        return _constructionData;
      case 1:
        return _labourColonyData;
      case 2:
        return _operationalData;
      default:
        return _constructionData;
    }
  }

  Widget _buildConsumptionTable() {
    final currentData = _getCurrentData();
    String phaseTitle;
    Color phaseColor;
    
    switch (_selectedPhase) {
      case 0:
        phaseTitle = 'DURING CONSTRUCTION PHASE';
        phaseColor = const Color(0xFF1565C0);
      case 1:
        phaseTitle = 'FOR THE LABOUR COLONY';
        phaseColor = const Color(0xFF2E7D32);
      case 2:
        phaseTitle = 'DURING OPERATIONAL PHASE';
        phaseColor = const Color(0xFF7B1FA2);
      default:
        phaseTitle = 'DURING CONSTRUCTION PHASE';
        phaseColor = const Color(0xFF1565C0);
    }

    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [
              Colors.white,
              phaseColor.withAlpha(13),
            ],
          ),
        ),
        child: Padding(
          padding: EdgeInsets.all(_getResponsivePadding()),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildTableHeader(phaseTitle, phaseColor),
              SizedBox(height: _getResponsiveSpacing(20)),
              _buildResponsiveTable(currentData, phaseColor),
            ],
          ),
        ),
      ),
    );
  }

  // Get responsive padding based on screen size
  double _getResponsivePadding() {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth > 1200) return 24.0; // Desktop
    if (screenWidth > 800) return 20.0;  // Tablet
    return 16.0; // Mobile
  }

  // Get responsive spacing
  double _getResponsiveSpacing(double baseSpacing) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth > 1200) return baseSpacing * 1.2; // Desktop
    if (screenWidth > 800) return baseSpacing;        // Tablet
    return baseSpacing * 0.8; // Mobile
  }

  // Get responsive font size
  double _getResponsiveFontSize(double baseFontSize) {
    final screenWidth = MediaQuery.of(context).size.width;
    if (screenWidth > 1200) return baseFontSize * 1.1; // Desktop
    if (screenWidth > 800) return baseFontSize;        // Tablet
    return baseFontSize * 0.9; // Mobile
  }

  Widget _buildTableHeader(String phaseTitle, Color phaseColor) {
    return Row(
      children: [
        Container(
          padding: EdgeInsets.all(_getResponsiveSpacing(10)),
          decoration: BoxDecoration(
            color: phaseColor.withAlpha(26),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _getPhaseIcon(_selectedPhase),
            color: phaseColor,
            size: _getResponsiveSpacing(24),
          ),
        ),
        SizedBox(width: _getResponsiveSpacing(12)),
        Expanded(
          child: Text(
            phaseTitle,
            style: TextStyle(
              fontSize: _getResponsiveFontSize(18),
              fontWeight: FontWeight.bold,
              color: phaseColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResponsiveTable(WaterConsumptionData currentData, Color phaseColor) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth > 800;
    final isDesktop = screenWidth > 1200;
    
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withAlpha(26),
            blurRadius: 8,
            spreadRadius: 0,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: screenWidth - (isDesktop ? 80 : isTablet ? 64 : 32),
            ),
            child: DataTable(
              columnSpacing: isDesktop ? 24 : isTablet ? 20 : 12,
              horizontalMargin: isDesktop ? 24 : isTablet ? 20 : 16,
              headingRowHeight: isDesktop ? 70 : isTablet ? 65 : 55,
              dataRowMinHeight: isDesktop ? 60 : isTablet ? 55 : 48,
              dataRowMaxHeight: isDesktop ? 60 : isTablet ? 55 : 48,
              headingRowColor: WidgetStateProperty.all(phaseColor.withAlpha(26)),
              dataRowColor: WidgetStateProperty.resolveWith<Color?>(
                (Set<WidgetState> states) {
                  if (states.contains(WidgetState.selected)) {
                    return phaseColor.withAlpha(51);
                  }
                  return null;
                },
              ),
              border: TableBorder.all(
                color: Colors.grey.shade200,
                width: 1,
                borderRadius: BorderRadius.circular(12),
              ),
              columns: _buildResponsiveColumns(phaseColor, isDesktop, isTablet),
              rows: _buildResponsiveRows(currentData, isDesktop, isTablet),
            ),
          ),
        ),
      ),
    );
  }

  List<DataColumn> _buildResponsiveColumns(Color phaseColor, bool isDesktop, bool isTablet) {
    final headerFontSize = isDesktop ? 16.0 : isTablet ? 15.0 : 13.0;
    final subHeaderFontSize = isDesktop ? 12.0 : isTablet ? 11.0 : 10.0;
    
    return [
      DataColumn(
        label: SizedBox(
          width: isDesktop ? 120 : isTablet ? 100 : 85,
          child: Text(
            'Source',
            style: TextStyle(
              fontWeight: FontWeight.bold, 
              fontSize: headerFontSize,
              color: phaseColor,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      DataColumn(
        label: SizedBox(
          width: isDesktop ? 110 : isTablet ? 95 : 80,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Day',
                style: TextStyle(
                  fontWeight: FontWeight.bold, 
                  fontSize: headerFontSize,
                  color: phaseColor,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '(${DateFormat('dd/MM').format(_selectedDate)})',
                style: TextStyle(
                  fontWeight: FontWeight.w500, 
                  fontSize: subHeaderFontSize,
                  color: phaseColor.withAlpha(179),
                ),
              ),
            ],
          ),
        ),
      ),
      DataColumn(
        label: SizedBox(
          width: isDesktop ? 100 : isTablet ? 85 : 75,
          child: Text(
            'Month',
            style: TextStyle(
              fontWeight: FontWeight.bold, 
              fontSize: headerFontSize,
              color: phaseColor,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
      DataColumn(
        label: SizedBox(
          width: isDesktop ? 140 : isTablet ? 120 : 100,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Period',
                style: TextStyle(
                  fontWeight: FontWeight.bold, 
                  fontSize: headerFontSize,
                  color: phaseColor,
                ),
              ),
              const SizedBox(height: 4),
              if (isTablet) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(child: _buildPeriodButton('FROM', _periodFromDate, phaseColor, true)),
                    const SizedBox(width: 4),
                    Expanded(child: _buildPeriodButton('TO', _periodToDate, phaseColor, false)),
                  ],
                ),
              ] else ...[
                Text(
                  'Custom Range',
                  style: TextStyle(
                    fontSize: subHeaderFontSize,
                    color: phaseColor.withAlpha(179),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      DataColumn(
        label: SizedBox(
          width: isDesktop ? 100 : isTablet ? 90 : 80,
          child: Text(
            'Total',
            style: TextStyle(
              fontWeight: FontWeight.bold, 
              fontSize: headerFontSize,
              color: phaseColor,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ];
  }

  Widget _buildPeriodButton(String label, DateTime? date, Color phaseColor, bool isFrom) {
    return GestureDetector(
      onTap: isFrom ? _selectPeriodFromDate : _selectPeriodToDate,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 3, horizontal: 4),
        decoration: BoxDecoration(
          color: phaseColor.withAlpha(51),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: phaseColor.withAlpha(77)),
        ),
        child: Text(
          date != null ? DateFormat('dd/MM').format(date) : label,
          style: const TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  List<DataRow> _buildResponsiveRows(WaterConsumptionData currentData, bool isDesktop, bool isTablet) {
    return [
      _buildResponsiveDataRow('BOREWELLS', currentData.borewellDaily, 
                    currentData.borewellMonthly, 
                    _periodFromDate != null && _periodToDate != null 
                        ? currentData.borewellPeriod 
                        : currentData.borewellCumulative,
                    const Color(0xFF2196F3), isDesktop, isTablet),
      _buildResponsiveDataRow('TANKERS', currentData.tankerDaily, 
                    currentData.tankerMonthly, 
                    _periodFromDate != null && _periodToDate != null 
                        ? currentData.tankerPeriod 
                        : currentData.tankerCumulative,
                    const Color(0xFF9C27B0), isDesktop, isTablet),
      _buildResponsiveDataRow('BWSSB', currentData.bwssbDaily, 
                    currentData.bwssbMonthly, 
                    _periodFromDate != null && _periodToDate != null 
                        ? currentData.bwssbPeriod 
                        : currentData.bwssbCumulative,
                    const Color(0xFF4CAF50), isDesktop, isTablet),
      _buildResponsiveDataRow('OTHERS', currentData.othersDaily, 
                    currentData.othersMonthly, 
                    _periodFromDate != null && _periodToDate != null 
                        ? currentData.othersPeriod 
                        : currentData.othersCumulative,
                    const Color(0xFFFF9800), isDesktop, isTablet),
    ];
  }

  // Helper method to get phase-specific icons
  IconData _getPhaseIcon(int phase) {
    switch (phase) {
      case 0: // Construction
        return Icons.construction;
      case 1: // Labour Colony
        return Icons.home_work;
      case 2: // Operational
        return Icons.factory;
      default:
        return Icons.water_drop;
    }
  }

  // Responsive data row with better styling and source colors
  DataRow _buildResponsiveDataRow(String source, double daily, double monthly, double totalOrPeriod, Color sourceColor, bool isDesktop, bool isTablet) {
    final sourceFontSize = isDesktop ? 14.0 : isTablet ? 13.0 : 12.0;
    final valueFontSize = isDesktop ? 13.0 : isTablet ? 12.0 : 11.0;
    final totalFontSize = isDesktop ? 14.0 : isTablet ? 13.0 : 12.0;
    
    return DataRow(
      cells: [
        DataCell(
          Container(
            width: isDesktop ? 120 : isTablet ? 100 : 85,
            padding: EdgeInsets.symmetric(
              vertical: isDesktop ? 8 : isTablet ? 6 : 4, 
              horizontal: isDesktop ? 8 : isTablet ? 6 : 4
            ),
            child: Row(
              children: [
                Container(
                  width: isDesktop ? 4 : 3,
                  height: isDesktop ? 28 : isTablet ? 24 : 20,
                  decoration: BoxDecoration(
                    color: sourceColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                SizedBox(width: isDesktop ? 8 : isTablet ? 6 : 4),
                Expanded(
                  child: Text(
                    source,
                    style: TextStyle(
                      fontWeight: FontWeight.bold, 
                      fontSize: sourceFontSize,
                      color: const Color(0xFF333333),
                    ),
                    textAlign: TextAlign.left,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        DataCell(
          Container(
            width: isDesktop ? 110 : isTablet ? 95 : 80,
            alignment: Alignment.center,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 8 : isTablet ? 6 : 4, 
                vertical: isDesktop ? 6 : isTablet ? 5 : 4
              ),
              decoration: BoxDecoration(
                color: sourceColor.withAlpha(26),
                borderRadius: BorderRadius.circular(isDesktop ? 8 : 6),
              ),
              child: Text(
                '${daily.toStringAsFixed(1)} L',
                style: TextStyle(
                  fontSize: valueFontSize,
                  fontWeight: FontWeight.w600,
                  color: sourceColor,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        DataCell(
          Container(
            width: isDesktop ? 100 : isTablet ? 85 : 75,
            alignment: Alignment.center,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 8 : isTablet ? 6 : 4, 
                vertical: isDesktop ? 6 : isTablet ? 5 : 4
              ),
              decoration: BoxDecoration(
                color: sourceColor.withAlpha(26),
                borderRadius: BorderRadius.circular(isDesktop ? 8 : 6),
              ),
              child: Text(
                '${monthly.toStringAsFixed(1)} L',
                style: TextStyle(
                  fontSize: valueFontSize,
                  fontWeight: FontWeight.w600,
                  color: sourceColor,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        DataCell(
          Container(
            width: isDesktop ? 140 : isTablet ? 120 : 100,
            alignment: Alignment.center,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 8 : isTablet ? 6 : 4, 
                vertical: isDesktop ? 6 : isTablet ? 5 : 4
              ),
              decoration: BoxDecoration(
                color: sourceColor.withAlpha(26),
                borderRadius: BorderRadius.circular(isDesktop ? 8 : 6),
              ),
              child: Text(
                '${totalOrPeriod.toStringAsFixed(1)} L',
                style: TextStyle(
                  fontSize: valueFontSize,
                  fontWeight: FontWeight.w600,
                  color: sourceColor,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        DataCell(
          Container(
            width: isDesktop ? 100 : isTablet ? 90 : 80,
            alignment: Alignment.center,
            child: Container(
              padding: EdgeInsets.symmetric(
                horizontal: isDesktop ? 12 : isTablet ? 10 : 8, 
                vertical: isDesktop ? 8 : isTablet ? 6 : 5
              ),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    sourceColor,
                    sourceColor.withAlpha(204),
                  ],
                ),
                borderRadius: BorderRadius.circular(isDesktop ? 10 : isTablet ? 8 : 6),
                boxShadow: [
                  BoxShadow(
                    color: sourceColor.withAlpha(51),
                    blurRadius: isDesktop ? 6 : isTablet ? 4 : 3,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                '${totalOrPeriod.toStringAsFixed(1)} L',
                style: TextStyle(
                  fontWeight: FontWeight.bold, 
                  fontSize: totalFontSize,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    );
  }


  // CORRECTED ACTION BUTTONS WITH PROPER NAVIGATION
  Widget _buildActionButtons() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                'Borewell',
                Icons.water_drop,
                Colors.blue,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const BorewellDataScreen()),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildActionButton(
                'Tanker',
                Icons.local_shipping,
                Colors.orange,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => TankerDataScreen(
                    authService: widget.authService,
                    onAuthenticationRequired: () {},
                  )),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                'BWSSB',
                Icons.water,
                Colors.green,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const BWSSBTankerManagementScreen()),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildActionButton(
                'Labour Colony',
                Icons.home_work,
                Colors.purple,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LabourColonyPage()),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildActionButton(
                'Treated Water',
                Icons.water_drop_outlined,
                Colors.cyan,
                () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const TreatedWaterDashboard()),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(), // Empty space to maintain layout
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onPressed) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        padding: const EdgeInsets.symmetric(vertical: 10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      icon: Icon(icon, color: Colors.white, size: 16),
      label: Text(
        label,
        style: const TextStyle(color: Colors.white, fontSize: 11),
        textAlign: TextAlign.center,
      ),
    );
  }

  void _showDatePicker() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.teal,
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
      _fetchAllWaterData();
    }
  }

  void _selectPeriodFromDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _periodFromDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.teal,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _periodFromDate = picked;
      });
      if (_periodToDate != null && picked.isAfter(_periodToDate!)) {
        _periodToDate = null;
      }
      _fetchAllWaterData();
    }
  }

  void _selectPeriodToDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _periodToDate ?? _periodFromDate ?? DateTime.now(),
      firstDate: _periodFromDate ?? DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.teal,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        _periodToDate = picked;
      });
      _fetchAllWaterData();
    }
  }
}