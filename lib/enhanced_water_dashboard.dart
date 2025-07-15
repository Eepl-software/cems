import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:shimmer/shimmer.dart';
import 'services/enhanced_api_service.dart';

/// Enhanced Water Management Dashboard with advanced features
class EnhancedWaterDashboard extends StatefulWidget {
  const EnhancedWaterDashboard({Key? key}) : super(key: key);

  @override
  State<EnhancedWaterDashboard> createState() => _EnhancedWaterDashboardState();
}

class _EnhancedWaterDashboardState extends State<EnhancedWaterDashboard>
    with TickerProviderStateMixin {
  final EnhancedAPIService _apiService = EnhancedAPIService();
  
  // Animation Controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late AnimationController _pulseController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _pulseAnimation;

  // Data Models
  Map<String, dynamic> _dashboardData = {};
  List<WaterConsumptionEntry> _recentEntries = [];
  List<WaterTrendData> _trendData = [];
  WaterQualityData? _waterQuality;
  Map<String, double> _sourceBreakdown = {};
  
  // UI State
  bool _isLoading = true;
  bool _isRefreshing = false;
  String _errorMessage = '';
  DateTime _selectedDate = DateTime.now();
  int _selectedDays = 7;
  String _selectedPhase = 'all';
  int _selectedTabIndex = 0;
  Timer? _refreshTimer;
  bool _isRealTimeEnabled = true;

  // Water Management Metrics
  double _todayConsumption = 0.0;
  double _weeklyAverage = 0.0;
  double _monthlyTotal = 0.0;
  double _efficiencyRating = 0.0;
  double _wastagePercentage = 0.0;
  String _alertStatus = 'normal';
  int _activeAlerts = 0;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadDashboardData();
    _startRealTimeUpdates();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _slideController.dispose();
    _pulseController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _initializeAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    ));

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutCubic,
    ));

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    ));

    _fadeController.forward();
    _slideController.forward();
    _pulseController.repeat(reverse: true);
  }

  void _startRealTimeUpdates() {
    if (_isRealTimeEnabled) {
      _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
        if (mounted) {
          _loadDashboardData(silent: true);
        }
      });
    }
  }

  Future<void> _loadDashboardData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });
    } else {
      setState(() {
        _isRefreshing = true;
      });
    }

    try {
      await Future.wait([
        _fetchDashboardOverview(),
        _fetchConsumptionTrends(),
        _fetchWaterQuality(),
        _fetchRecentEntries(),
        _calculateMetrics(),
      ]);

      if (mounted) {
        setState(() {
          _errorMessage = '';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load dashboard data: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    }
  }

  Future<void> _fetchDashboardOverview() async {
    try {
      final data = await _apiService.getWaterConsumptionDashboard(days: _selectedDays);
      if (mounted) {
        setState(() {
          _dashboardData = data;
          _sourceBreakdown = Map<String, double>.from(data['sourceBreakdown'] ?? {});
        });
      }
    } catch (e) {
      print('Error fetching dashboard overview: $e');
    }
  }

  Future<void> _fetchConsumptionTrends() async {
    try {
      // Create trend data from dashboard data
      final chartData = _dashboardData['chartData'] as List? ?? [];
      final trends = <WaterTrendData>[];
      
      for (var item in chartData) {
        trends.add(WaterTrendData.fromJson(item));
      }
      
      if (mounted) {
        setState(() {
          _trendData = trends;
        });
      }
    } catch (e) {
      print('Error fetching trends: $e');
    }
  }

  Future<void> _fetchWaterQuality() async {
    try {
      // Simulate water quality data (you can implement real API)
      if (mounted) {
        setState(() {
          _waterQuality = WaterQualityData(
            ph: 7.2 + (DateTime.now().second % 10) * 0.1,
            turbidity: 2.1 + (DateTime.now().second % 5) * 0.2,
            tds: 145 + (DateTime.now().second % 20),
            temperature: 24.5 + (DateTime.now().second % 8) * 0.5,
            timestamp: DateTime.now(),
          );
        });
      }
    } catch (e) {
      print('Error fetching water quality: $e');
    }
  }

  Future<void> _fetchRecentEntries() async {
    try {
      // Create sample recent entries (implement with real API)
      final entries = <WaterConsumptionEntry>[];
      final now = DateTime.now();
      
      for (int i = 0; i < 10; i++) {
        entries.add(WaterConsumptionEntry(
          id: i.toString(),
          source: ['Borewell', 'Tanker', 'BWSSB'][i % 3],
          consumption: 50.0 + (i * 15),
          timestamp: now.subtract(Duration(hours: i * 2)),
          phase: ['Construction', 'Labour Colony', 'Operational'][i % 3],
        ));
      }
      
      if (mounted) {
        setState(() {
          _recentEntries = entries;
        });
      }
    } catch (e) {
      print('Error fetching recent entries: $e');
    }
  }

  Future<void> _calculateMetrics() async {
    try {
      // Calculate key metrics from data
      final total = _sourceBreakdown.values.fold(0.0, (sum, val) => sum + val);
      
      if (mounted) {
        setState(() {
          _todayConsumption = total;
          _weeklyAverage = total / 7;
          _monthlyTotal = total * 4.33; // Approximate month
          _efficiencyRating = _calculateEfficiency();
          _wastagePercentage = _calculateWastage();
          _activeAlerts = _calculateAlerts();
          _alertStatus = _getAlertStatus();
        });
      }
    } catch (e) {
      print('Error calculating metrics: $e');
    }
  }

  double _calculateEfficiency() {
    if (_todayConsumption <= 0) return 0.0;
    // Simple efficiency calculation (you can enhance this)
    final baseline = 1000.0; // Baseline consumption
    return ((baseline - _todayConsumption) / baseline * 100).clamp(0.0, 100.0);
  }

  double _calculateWastage() {
    // Calculate wastage percentage (implement your logic)
    return (DateTime.now().second % 15).toDouble();
  }

  int _calculateAlerts() {
    int alerts = 0;
    if (_todayConsumption > 1200) alerts++;
    if (_waterQuality?.ph != null && (_waterQuality!.ph < 6.5 || _waterQuality!.ph > 8.5)) alerts++;
    if (_wastagePercentage > 10) alerts++;
    return alerts;
  }

  String _getAlertStatus() {
    if (_activeAlerts >= 3) return 'critical';
    if (_activeAlerts >= 1) return 'warning';
    return 'normal';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.blue.shade50,
              Colors.cyan.shade50,
              Colors.teal.shade50,
            ],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: _buildBody(),
            ),
          ),
        ),
      ),
      floatingActionButton: _buildFloatingActionButtons(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return _buildLoadingShimmer();
    }

    if (_errorMessage.isNotEmpty) {
      return _buildErrorWidget();
    }

    return Column(
      children: [
        _buildAppHeader(),
        _buildTabBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _loadDashboardData,
            child: _buildTabContent(),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingShimmer() {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: 6,
        itemBuilder: (context, index) {
          return Container(
            height: 120,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
          );
        },
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.water_drop_outlined,
            size: 80,
            color: Colors.blue.shade300,
          ),
          const SizedBox(height: 24),
          Text(
            'Unable to Load Water Data',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _errorMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _loadDashboardData,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Again'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(25),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.blue.shade600, Colors.cyan.shade500],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.shade200,
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: const Icon(
                        Icons.water_drop,
                        color: Colors.white,
                        size: 32,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Water Management',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Real-time monitoring & analytics',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              _buildStatusIndicator(),
            ],
          ),
          const SizedBox(height: 20),
          _buildQuickMetrics(),
        ],
      ),
    );
  }

  Widget _buildStatusIndicator() {
    Color statusColor;
    IconData statusIcon;
    String statusText;

    switch (_alertStatus) {
      case 'critical':
        statusColor = Colors.red;
        statusIcon = Icons.warning;
        statusText = 'Critical';
        break;
      case 'warning':
        statusColor = Colors.orange;
        statusIcon = Icons.info;
        statusText = 'Warning';
        break;
      default:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        statusText = 'Normal';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: statusColor.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, color: statusColor, size: 16),
          const SizedBox(width: 6),
          Text(
            statusText,
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
          if (_activeAlerts > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _activeAlerts.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuickMetrics() {
    return Row(
      children: [
        Expanded(
          child: _buildQuickMetricCard(
            'Today',
            '${_todayConsumption.toStringAsFixed(0)}L',
            Icons.today,
            Colors.white.withOpacity(0.2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildQuickMetricCard(
            'Efficiency',
            '${_efficiencyRating.toStringAsFixed(1)}%',
            Icons.eco,
            Colors.white.withOpacity(0.2),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildQuickMetricCard(
            'Quality',
            _waterQuality?.getQualityRating() ?? 'Good',
            Icons.verified,
            Colors.white.withOpacity(0.2),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickMetricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              color: Colors.white.withOpacity(0.9),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabBar() {
    final tabs = ['Overview', 'Analytics', 'Quality', 'Alerts'];
    
    return Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(25),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade300,
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: tabs.asMap().entries.map((entry) {
          final index = entry.key;
          final tab = entry.value;
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
                  color: isSelected ? Colors.blue.shade600 : Colors.transparent,
                  borderRadius: BorderRadius.circular(25),
                ),
                child: Text(
                  tab,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isSelected ? Colors.white : Colors.grey.shade600,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_selectedTabIndex) {
      case 0:
        return _buildOverviewTab();
      case 1:
        return _buildAnalyticsTab();
      case 2:
        return _buildQualityTab();
      case 3:
        return _buildAlertsTab();
      default:
        return _buildOverviewTab();
    }
  }

  Widget _buildOverviewTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildConsumptionChart(),
        const SizedBox(height: 20),
        _buildSourceBreakdown(),
        const SizedBox(height: 20),
        _buildRecentActivity(),
      ],
    );
  }

  Widget _buildAnalyticsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildTrendAnalysis(),
        const SizedBox(height: 20),
        _buildEfficiencyMetrics(),
        const SizedBox(height: 20),
        _buildPredictiveAnalytics(),
      ],
    );
  }

  Widget _buildQualityTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildWaterQualityOverview(),
        const SizedBox(height: 20),
        _buildQualityTrends(),
        const SizedBox(height: 20),
        _buildQualityAlerts(),
      ],
    );
  }

  Widget _buildAlertsTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildActiveAlerts(),
        const SizedBox(height: 20),
        _buildAlertHistory(),
      ],
    );
  }

  Widget _buildFloatingActionButtons() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FloatingActionButton(
          onPressed: () {
            setState(() {
              _isRealTimeEnabled = !_isRealTimeEnabled;
              if (_isRealTimeEnabled) {
                _startRealTimeUpdates();
              } else {
                _refreshTimer?.cancel();
              }
            });
          },
          backgroundColor: _isRealTimeEnabled ? Colors.green : Colors.grey,
          child: Icon(_isRealTimeEnabled ? Icons.pause : Icons.play_arrow),
          heroTag: "realtime",
        ),
        const SizedBox(height: 10),
        FloatingActionButton(
          onPressed: _loadDashboardData,
          backgroundColor: Colors.blue.shade600,
          child: _isRefreshing
              ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
              : const Icon(Icons.refresh),
          heroTag: "refresh",
        ),
      ],
    );
  }

  // Placeholder methods for different sections
  Widget _buildConsumptionChart() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        height: 300,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Water Consumption Trends',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: _trendData.isEmpty
                  ? Center(
                      child: Text(
                        'No trend data available',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    )
                  : LineChart(_buildLineChartData()),
            ),
          ],
        ),
      ),
    );
  }

  LineChartData _buildLineChartData() {
    return LineChartData(
      gridData: FlGridData(show: true),
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) {
              return Text(
                '${value.toInt()}L',
                style: const TextStyle(fontSize: 10),
              );
            },
          ),
        ),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (value, meta) {
              final index = value.toInt();
              if (index >= 0 && index < _trendData.length) {
                return Text(
                  DateFormat('MM/dd').format(_trendData[index].timestamp),
                  style: const TextStyle(fontSize: 10),
                );
              }
              return const Text('');
            },
          ),
        ),
        rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
        topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
      ),
      borderData: FlBorderData(show: true),
      lineBarsData: [
        LineChartBarData(
          spots: _trendData.asMap().entries.map((entry) {
            return FlSpot(entry.key.toDouble(), entry.value.consumption);
          }).toList(),
          isCurved: true,
          color: Colors.blue.shade600,
          barWidth: 3,
          dotData: FlDotData(show: false),
          belowBarData: BarAreaData(
            show: true,
            color: Colors.blue.shade600.withOpacity(0.1),
          ),
        ),
      ],
    );
  }

  Widget _buildSourceBreakdown() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Water Source Breakdown',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 20),
            if (_sourceBreakdown.isEmpty)
              Center(
                child: Text(
                  'No source data available',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              )
            else
              ..._sourceBreakdown.entries.map((entry) {
                final total = _sourceBreakdown.values.fold(0.0, (sum, val) => sum + val);
                final percentage = total > 0 ? (entry.value / total * 100) : 0.0;
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: _buildSourceProgressBar(
                    entry.key,
                    entry.value,
                    percentage,
                    _getSourceColor(entry.key),
                  ),
                );
              }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceProgressBar(String source, double value, double percentage, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              source,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            Text(
              '${value.toStringAsFixed(0)}L (${percentage.toStringAsFixed(1)}%)',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 12,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearPercentIndicator(
          lineHeight: 8,
          percent: percentage / 100,
          backgroundColor: Colors.grey.shade200,
          progressColor: color,
          barRadius: const Radius.circular(4),
          animation: true,
          animationDuration: 1000,
        ),
      ],
    );
  }

  Color _getSourceColor(String source) {
    switch (source.toLowerCase()) {
      case 'borewell':
        return Colors.blue.shade600;
      case 'tanker':
        return Colors.orange.shade600;
      case 'bwssb':
        return Colors.green.shade600;
      default:
        return Colors.purple.shade600;
    }
  }

  Widget _buildRecentActivity() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Recent Activity',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade800,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    // Navigate to detailed activity
                  },
                  child: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_recentEntries.isEmpty)
              Center(
                child: Text(
                  'No recent activity',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
              )
            else
              ..._recentEntries.take(5).map((entry) {
                return _buildActivityItem(entry);
              }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityItem(WaterConsumptionEntry entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _getSourceColor(entry.source),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _getSourceIcon(entry.source),
              color: Colors.white,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.source} - ${entry.phase}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                Text(
                  '${entry.consumption.toStringAsFixed(0)}L consumed',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Text(
            DateFormat('HH:mm').format(entry.timestamp),
            style: TextStyle(
              color: Colors.grey.shade500,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getSourceIcon(String source) {
    switch (source.toLowerCase()) {
      case 'borewell':
        return Icons.water_drop;
      case 'tanker':
        return Icons.local_shipping;
      case 'bwssb':
        return Icons.water;
      default:
        return Icons.water_drop_outlined;
    }
  }

  // Placeholder methods for other tabs
  Widget _buildTrendAnalysis() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Trend Analysis',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Detailed trend analysis will be implemented here.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEfficiencyMetrics() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Efficiency Metrics',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 20),
            CircularPercentIndicator(
              radius: 60,
              lineWidth: 8,
              percent: _efficiencyRating / 100,
              center: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${_efficiencyRating.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const Text(
                    'Efficiency',
                    style: TextStyle(fontSize: 10),
                  ),
                ],
              ),
              progressColor: _efficiencyRating > 70 ? Colors.green : Colors.orange,
              backgroundColor: Colors.grey.shade200,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPredictiveAnalytics() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Predictive Analytics',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'AI-powered predictions will be shown here.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaterQualityOverview() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Water Quality Overview',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 20),
            if (_waterQuality != null)
              Column(
                children: [
                  _buildQualityParameter('pH Level', _waterQuality!.ph.toStringAsFixed(1), '6.5-8.5'),
                  const SizedBox(height: 16),
                  _buildQualityParameter('Turbidity', '${_waterQuality!.turbidity.toStringAsFixed(1)} NTU', '<5 NTU'),
                  const SizedBox(height: 16),
                  _buildQualityParameter('TDS', '${_waterQuality!.tds.toInt()} ppm', '<500 ppm'),
                  const SizedBox(height: 16),
                  _buildQualityParameter('Temperature', '${_waterQuality!.temperature.toStringAsFixed(1)}°C', '20-30°C'),
                ],
              )
            else
              Text(
                'No quality data available',
                style: TextStyle(color: Colors.grey.shade600),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildQualityParameter(String name, String value, String ideal) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            Text(
              'Ideal: $ideal',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 11,
              ),
            ),
          ],
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.blue.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blue.shade200),
          ),
          child: Text(
            value,
            style: TextStyle(
              color: Colors.blue.shade700,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQualityTrends() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quality Trends',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Quality trend charts will be implemented here.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQualityAlerts() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quality Alerts',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Quality-related alerts will be shown here.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveAlerts() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Active Alerts',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 20),
            if (_activeAlerts == 0)
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.check_circle, color: Colors.green.shade600),
                    const SizedBox(width: 12),
                    Text(
                      'No active alerts',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                'Alert details will be shown here.',
                style: TextStyle(color: Colors.grey.shade600),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertHistory() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Alert History',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Historical alerts will be shown here.',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}

// Data Models
class WaterConsumptionEntry {
  final String id;
  final String source;
  final double consumption;
  final DateTime timestamp;
  final String phase;

  WaterConsumptionEntry({
    required this.id,
    required this.source,
    required this.consumption,
    required this.timestamp,
    required this.phase,
  });

  factory WaterConsumptionEntry.fromJson(Map<String, dynamic> json) {
    return WaterConsumptionEntry(
      id: json['id'].toString(),
      source: json['source'] ?? '',
      consumption: (json['consumption'] ?? 0.0).toDouble(),
      timestamp: DateTime.parse(json['timestamp']),
      phase: json['phase'] ?? '',
    );
  }
}

class WaterTrendData {
  final DateTime timestamp;
  final double consumption;
  final String source;

  WaterTrendData({
    required this.timestamp,
    required this.consumption,
    required this.source,
  });

  factory WaterTrendData.fromJson(Map<String, dynamic> json) {
    return WaterTrendData(
      timestamp: DateTime.parse(json['date']),
      consumption: (json['consumption'] ?? 0.0).toDouble(),
      source: json['source'] ?? '',
    );
  }
}

class WaterQualityData {
  final double ph;
  final double turbidity;
  final double tds;
  final double temperature;
  final DateTime timestamp;

  WaterQualityData({
    required this.ph,
    required this.turbidity,
    required this.tds,
    required this.temperature,
    required this.timestamp,
  });

  String getQualityRating() {
    if (ph >= 6.5 && ph <= 8.5 && turbidity < 5 && tds < 500) {
      return 'Excellent';
    } else if (ph >= 6.0 && ph <= 9.0 && turbidity < 10 && tds < 1000) {
      return 'Good';
    } else {
      return 'Poor';
    }
  }
}