import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import './ambient.dart';
import './stack.dart';
import '../Air_poll_api.dart' as AirAPI;

// Alert type enum for categorizing notifications
enum AlertType {
  info,
  caution,
  warning,
  critical,
}

class AirPollutionMonitoringPage extends StatefulWidget {
  const AirPollutionMonitoringPage({super.key});

  @override
  State<AirPollutionMonitoringPage> createState() => _AirPollutionMonitoringPageState();
}

class _AirPollutionMonitoringPageState extends State<AirPollutionMonitoringPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<Map<String, dynamic>> _notifications = [];
  Timer? _autoRefreshTimer;
  Timer? _notificationTimer;

  AirAPI.AirQualityData? _airQualityData;
  bool _isLoadingAirQuality = true;
  String _airQualityErrorMessage = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadAirQualityData();
    _startRealTimeMonitoring();
    _startNotificationSimulation();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _autoRefreshTimer?.cancel();
    _notificationTimer?.cancel();
    super.dispose();
  }

  void _startRealTimeMonitoring() {
    // Auto-refresh air quality data every 5 minutes
    _autoRefreshTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (mounted) {
        _loadAirQualityData();
        _addRealTimeNotification('Air quality data auto-updated');
      }
    });
  }

  void _startNotificationSimulation() {
    // Simulate real-time air quality alerts
    _notificationTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      if (mounted) {
        _generateSmartNotifications();
      }
    });
    
    // Initial notification after 10 seconds
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) {
        _addRealTimeNotification('Real-time monitoring activated', AlertType.info);
      }
    });
  }

  void _generateSmartNotifications() {
    if (_airQualityData != null) {
      final data = _airQualityData!;
      
      // Check PM2.5 levels
      if (data.pm25 > 35) {
        _addRealTimeNotification(
          'PM2.5 levels (${data.pm25.toStringAsFixed(1)} µg/m³) exceed WHO guidelines',
          AlertType.warning
        );
      } else if (data.pm25 > 25) {
        _addRealTimeNotification(
          'PM2.5 levels (${data.pm25.toStringAsFixed(1)} µg/m³) are moderate',
          AlertType.caution
        );
      }
      
      // Check PM10 levels
      if (data.pm10 > 50) {
        _addRealTimeNotification(
          'PM10 levels (${data.pm10.toStringAsFixed(1)} µg/m³) exceed recommended limits',
          AlertType.warning
        );
      }
      
      // Check overall air quality
      if (data.overallAqi > 100) {
        _addRealTimeNotification(
          'Air Quality Index (${data.overallAqi}) indicates unhealthy conditions',
          AlertType.critical
        );
      } else if (data.overallAqi > 50) {
        _addRealTimeNotification(
          'Air quality is moderate (AQI: ${data.overallAqi})',
          AlertType.info
        );
      }
    }
  }

  void _addRealTimeNotification(String message, [AlertType type = AlertType.info]) {
    if (mounted) {
      setState(() {
        _notifications.insert(0, {
          'message': message,
          'timestamp': DateTime.now(),
          'type': type,
          'id': DateTime.now().millisecondsSinceEpoch.toString(),
        });
        
        // Keep only the latest 20 notifications
        if (_notifications.length > 20) {
          _notifications.removeLast();
        }
      });
    }
  }

  Future<void> _loadAirQualityData() async {
    setState(() {
      _isLoadingAirQuality = true;
      _airQualityErrorMessage = '';
    });

    try {
      // Get current location
      final position = await AirAPI.AirQualityService.getCurrentLocation();
      
      if (position == null) {
        setState(() {
          _airQualityErrorMessage = 'Unable to get location. Please enable location services.';
          _isLoadingAirQuality = false;
        });
        return;
      }

      // Fetch air quality data
      final data = await AirAPI.AirQualityService.getAirQualityData(
        latitude: position.latitude,
        longitude: position.longitude,
      );

      setState(() {
        _airQualityData = data;
        _isLoadingAirQuality = false;
        if (data == null) {
          _airQualityErrorMessage = 'Failed to fetch air quality data.';
        }
      });
    } catch (e) {
      setState(() {
        _airQualityErrorMessage = 'Error: $e';
        _isLoadingAirQuality = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _buildBody(),
      floatingActionButton: _buildFAB(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('Air Pollution Management'),
      backgroundColor: const Color(0xFF1565C0),
      foregroundColor: Colors.white,
      bottom: TabBar(
        controller: _tabController,
        indicatorColor: Colors.white,
        tabs: const [
          Tab(text: 'Overview'),
          Tab(text: 'Standards'),
          Tab(text: 'Alerts'),
        ],
      ),
      actions: [
        Builder(
          builder: (context) => Stack(
            children: [
              Container(
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.white.withAlpha(26),
                      Colors.white.withAlpha(13),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: IconButton(
                  icon: const Icon(Icons.notifications_active, size: 26),
                  onPressed: _showEnhancedNotifications,
                  tooltip: 'Air Quality Alerts',
                ),
              ),
              if (_notifications.isNotEmpty)
                Positioned(
                  right: 12,
                  top: 6,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Colors.red, Color(0xFFD32F2F)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.red.withAlpha(77),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ],
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      '${_notifications.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBody() {
    return TabBarView(
      controller: _tabController,
      children: [
        _buildOverviewTab(),
        _buildStandardsTab(),
        _buildAlertsTab(),
      ],
    );
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCurrentStatus(),
          const SizedBox(height: 24),
          _buildMonitoringGrids(),
        ],
      ),
    );
  }

  Widget _buildCurrentStatus() {
    if (_isLoadingAirQuality) {
      return Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white,
                const Color(0xFF1565C0).withAlpha(13),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            children: [
              Text(
                'Loading Air Quality Data...',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              SizedBox(height: 16),
              CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1565C0)),
              ),
            ],
          ),
        ),
      );
    }

    if (_airQualityErrorMessage.isNotEmpty) {
      return Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white,
                Colors.red.withAlpha(13),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              const Icon(Icons.error_outline, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                _airQualityErrorMessage,
                style: const TextStyle(color: Colors.red, fontSize: 16),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadAirQualityData,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_airQualityData == null) {
      return Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.white,
                Colors.grey.withAlpha(13),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Text('No data available'),
        ),
      );
    }

    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.white,
              const Color(0xFF1565C0).withAlpha(13),
            ],
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Current Ambient Air Quality',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1565C0),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1565C0).withAlpha(26),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.refresh, color: Color(0xFF1565C0)),
                    onPressed: _loadAirQualityData,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _airQualityData!.location,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 20),
            _buildAirQualityTable(),
          ],
        ),
      ),
    );
  }

  Widget _buildAirQualityTable() {
    final data = _airQualityData!;
    
    return Table(
      border: TableBorder.all(
        color: Colors.grey.shade300,
        width: 1.5,
        borderRadius: BorderRadius.circular(8),
      ),
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(2),
        2: FlexColumnWidth(2),
        3: FlexColumnWidth(2),
      },
      children: [
        // Header row
        TableRow(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF1565C0).withAlpha(26),
                const Color(0xFF1976D2).withAlpha(26),
              ],
            ),
          ),
          children: const [
            TableCell(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Parameter',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF1565C0),
                  ),
                ),
              ),
            ),
            TableCell(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Standard',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF1565C0),
                  ),
                ),
              ),
            ),
            TableCell(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Result',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF1565C0),
                  ),
                ),
              ),
            ),
            TableCell(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Comment',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Color(0xFF1565C0),
                  ),
                ),
              ),
            ),
          ],
        ),
        // PM2.5 row
        _buildTableRow('PM 2.5', data.pm25, 'µg/m³'),
        // PM10 row
        _buildTableRow('PM 10', data.pm10, 'µg/m³'),
        // SO2 row
        _buildTableRow('SO2', data.so2, 'ppb'),
      ],
    );
  }

  TableRow _buildTableRow(String parameter, double value, String unit) {
    final comment = AirAPI.AirQualityHelper.getQualityComment(value, parameter);
    final color = AirAPI.AirQualityHelper.getQualityColor(comment);
    final standard = AirAPI.AirQualityHelper.getStandardValue(parameter);

    return TableRow(
      children: [
        TableCell(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              parameter,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
        TableCell(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              standard,
              style: const TextStyle(fontSize: 15),
            ),
          ),
        ),
        TableCell(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color.withAlpha(51),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withAlpha(77), width: 1),
              ),
              child: Text(
                '${value.toStringAsFixed(1)} $unit',
                style: TextStyle(
                  fontSize: 14,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        TableCell(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: color.withAlpha(51),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withAlpha(77), width: 1),
              ),
              child: Text(
                comment,
                style: TextStyle(
                  fontSize: 14,
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMonitoringGrids() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Air Quality Monitoring',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1565C0),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildMonitoringGridItem(
                context,
                'Stack Emissions',
                Icons.analytics_outlined,
                StackMonitoringPage(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildMonitoringGridItem(
                context,
                'Ambient Air Quality',
                Icons.dashboard_outlined,
                const AmbientAirMonitoringPage(),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMonitoringGridItem(
    BuildContext context,
    String title,
    IconData icon,
    Widget page,
  ) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => page),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1565C0),
                Color(0xFF1976D2),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF1565C0).withAlpha(77),
                blurRadius: 12,
                spreadRadius: 2,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 32,
                color: Colors.white,
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStandardsTab() {
    return const Center(
      child: Text(
        'Standards Tab\n(Add your existing standards content here)',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 18),
      ),
    );
  }

  Widget _buildAlertsTab() {
    return _notifications.isEmpty
        ? Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.notifications_none,
                  size: 80,
                  color: Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'No active alerts',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Air quality alerts will appear here when conditions change',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _notifications.length,
            itemBuilder: (context, index) {
              final notification = _notifications[index];
              return _buildNotificationCard(notification, index);
            },
          );
  }

  void _showEnhancedNotifications() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.8,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF1565C0).withAlpha(13),
                Colors.white,
              ],
            ),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF1565C0), Color(0xFF1976D2)],
                            ),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.notifications_active,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Air Quality Alerts',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1565C0),
                              ),
                            ),
                            Text(
                              '${_notifications.length} active notifications',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _notifications.clear();
                            });
                            Navigator.pop(context);
                          },
                          child: const Text('Clear All'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _notifications.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.notifications_none,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'No notifications yet',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Air quality alerts will appear here',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _notifications.length,
                        itemBuilder: (context, index) {
                          final notification = _notifications[index];
                          return _buildNotificationCard(notification, index);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildNotificationCard(Map<String, dynamic> notification, int index) {
    final type = notification['type'] as AlertType;
    final timestamp = notification['timestamp'] as DateTime;
    final message = notification['message'] as String;
    
    Color getTypeColor(AlertType type) {
      switch (type) {
        case AlertType.critical:
          return Colors.red;
        case AlertType.warning:
          return Colors.orange;
        case AlertType.caution:
          return Colors.yellow.shade700;
        case AlertType.info:
          return const Color(0xFF1565C0);
      }
    }
    
    IconData getTypeIcon(AlertType type) {
      switch (type) {
        case AlertType.critical:
          return Icons.error;
        case AlertType.warning:
          return Icons.warning;
        case AlertType.caution:
          return Icons.info;
        case AlertType.info:
          return Icons.notifications;
      }
    }
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              colors: [
                Colors.white,
                getTypeColor(type).withAlpha(13),
              ],
            ),
            border: Border.all(
              color: getTypeColor(type).withAlpha(51),
              width: 1,
            ),
          ),
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: getTypeColor(type).withAlpha(26),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                getTypeIcon(type),
                color: getTypeColor(type),
                size: 24,
              ),
            ),
            title: Text(
              message,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(
              _formatTimestamp(timestamp),
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey[600],
              ),
            ),
            trailing: IconButton(
              icon: Icon(Icons.close, color: Colors.grey[400], size: 20),
              onPressed: () {
                setState(() {
                  _notifications.removeAt(index);
                });
              },
            ),
          ),
        ),
      ),
    );
  }

  String _formatTimestamp(DateTime timestamp) {
    final now = DateTime.now();
    final difference = now.difference(timestamp);
    
    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else {
      return DateFormat('MMM d, HH:mm').format(timestamp);
    }
  }

  Widget _buildFAB() {
    return FloatingActionButton.extended(
      onPressed: () {
        _addRealTimeNotification('Data refreshed at ${DateFormat('HH:mm:ss').format(DateTime.now())}');
        _loadAirQualityData();
      },
      backgroundColor: const Color(0xFF1565C0),
      foregroundColor: Colors.white,
      icon: const Icon(Icons.refresh_rounded),
      label: const Text('Refresh'),
      elevation: 8,
    );
  }
}