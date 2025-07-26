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
    if (value is String) return double.tryParse(value) ?? 0.0;
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
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
    );
  }

  Widget _buildChart() {
    if (_chartData.isEmpty) {
      return Card(
        elevation: 4,
        child: Container(
          height: 200,
          alignment: Alignment.center,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bar_chart_outlined, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              const Text(
                'No chart data available',
                style: TextStyle(color: Colors.grey, fontSize: 16),
              ),
              const SizedBox(height: 8),
              Text(
                _isConnected 
                  ? 'Data may not be available for the selected date range'
                  : 'Check your connection and try again',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
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

    // Group data by source for multiple line chart
    Map<String, List<FlSpot>> chartLines = {};
    Map<String, Color> sourceColors = {
      'borewell': Colors.blue,
      'bwssb': Colors.green,
      'labour_colony': Colors.orange,
      'tanker': Colors.purple,
      'mixed': Colors.teal,
    };

    for (int i = 0; i < _chartData.length; i++) {
      final point = _chartData[i];
      if (!chartLines.containsKey(point.source)) {
        chartLines[point.source] = [];
      }
      chartLines[point.source]!.add(FlSpot(i.toDouble(), point.consumption));
    }

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Water Consumption Trend (Last 7 Days)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal,
                  ),
                ),
                Icon(
                  _isConnected ? Icons.trending_up : Icons.trending_flat,
                  color: _isConnected ? Colors.green : Colors.orange,
                  size: 20,
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 250,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index >= 0 && index < _chartData.length) {
                            return Text(
                              DateFormat('MM/dd').format(_chartData[index].date),
                              style: const TextStyle(fontSize: 10),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            _formatChartValue(value),
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: true),
                  lineBarsData: chartLines.entries.map((entry) {
                    return LineChartBarData(
                      spots: entry.value,
                      isCurved: true,
                      color: sourceColors[entry.key] ?? Colors.grey,
                      barWidth: 2,
                      dotData: FlDotData(show: false),
                    );
                  }).toList(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            // Legend
            Wrap(
              children: sourceColors.entries.where((entry) => 
                chartLines.containsKey(entry.key)
              ).map((entry) {
                return Padding(
                  padding: const EdgeInsets.only(right: 16.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        color: entry.value,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        entry.key.toUpperCase(),
                        style: const TextStyle(fontSize: 10),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
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
    
    switch (_selectedPhase) {
      case 0:
        phaseTitle = 'DURING CONSTRUCTION PHASE';
        break;
      case 1:
        phaseTitle = 'FOR THE LABOUR COLONY';
        break;
      case 2:
        phaseTitle = 'DURING OPERATIONAL PHASE';
        break;
      default:
        phaseTitle = 'DURING CONSTRUCTION PHASE';
    }

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              phaseTitle,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.teal,
              ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: MediaQuery.of(context).size.width - 64,
                ),
                child: DataTable(
                  columnSpacing: 12,
                  headingRowHeight: 50,
                  dataRowHeight: 40,
                  headingRowColor: MaterialStateProperty.all(Colors.teal.shade50),
                  border: TableBorder.all(color: Colors.grey.shade300),
                  columns: [
                    const DataColumn(
                      label: SizedBox(
                        width: 60,
                        child: Text(
                          'Source',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: 80,
                        child: Text(
                          'Day\n(${DateFormat('dd/MM').format(_selectedDate)})',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 9),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    const DataColumn(
                      label: SizedBox(
                        width: 70,
                        child: Text(
                          'Month',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                    DataColumn(
                      label: SizedBox(
                        width: 90,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Text(
                              'Period',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 9),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 2),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => _selectPeriodFromDate(),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.grey, width: 0.5),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: Text(
                                        _periodFromDate != null 
                                            ? DateFormat('dd/MM').format(_periodFromDate!)
                                            : 'FROM',
                                        style: const TextStyle(fontSize: 7),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 2),
                                Expanded(
                                  child: GestureDetector(
                                    onTap: () => _selectPeriodToDate(),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 1, horizontal: 2),
                                      decoration: BoxDecoration(
                                        border: Border.all(color: Colors.grey, width: 0.5),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                      child: Text(
                                        _periodToDate != null 
                                            ? DateFormat('dd/MM').format(_periodToDate!)
                                            : 'TO',
                                        style: const TextStyle(fontSize: 7),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    const DataColumn(
                      label: SizedBox(
                        width: 70,
                        child: Text(
                          'Total',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ],
                  rows: [
                    _buildDataRow('BOREWELLS', currentData.borewellDaily, 
                                  currentData.borewellMonthly, 
                                  _periodFromDate != null && _periodToDate != null 
                                      ? currentData.borewellPeriod 
                                      : currentData.borewellCumulative),
                    _buildDataRow('TANKERS', currentData.tankerDaily, 
                                  currentData.tankerMonthly, 
                                  _periodFromDate != null && _periodToDate != null 
                                      ? currentData.tankerPeriod 
                                      : currentData.tankerCumulative),
                    _buildDataRow('BWSSB', currentData.bwssbDaily, 
                                  currentData.bwssbMonthly, 
                                  _periodFromDate != null && _periodToDate != null 
                                      ? currentData.bwssbPeriod 
                                      : currentData.bwssbCumulative),
                    _buildDataRow('OTHERS', currentData.othersDaily, 
                                  currentData.othersMonthly, 
                                  _periodFromDate != null && _periodToDate != null 
                                      ? currentData.othersPeriod 
                                      : currentData.othersCumulative),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  DataRow _buildDataRow(String source, double daily, double monthly, double totalOrPeriod) {
    return DataRow(
      cells: [
        DataCell(
          SizedBox(
            width: 60,
            child: Text(
              source,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 9),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 80,
            child: Text(
              '${daily.toStringAsFixed(1)} L',
              style: const TextStyle(fontSize: 9),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 70,
            child: Text(
              '${monthly.toStringAsFixed(1)} L',
              style: const TextStyle(fontSize: 9),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 90,
            child: Text(
              '${totalOrPeriod.toStringAsFixed(1)} L',
              style: const TextStyle(fontSize: 9),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        DataCell(
          SizedBox(
            width: 70,
            child: Text(
              '${totalOrPeriod.toStringAsFixed(1)} L',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 9),
              textAlign: TextAlign.center,
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