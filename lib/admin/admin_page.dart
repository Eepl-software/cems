// enhanced_admin_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';

class EnhancedAdminPage extends StatefulWidget {
  final String adminToken;
  final String adminUsername;

  const EnhancedAdminPage({
    Key? key,
    required this.adminToken,
    required this.adminUsername,
  }) : super(key: key);

  @override
  State<EnhancedAdminPage> createState() => _EnhancedAdminPageState();
}

class _EnhancedAdminPageState extends State<EnhancedAdminPage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _animationController;
  
  // Dashboard data
  Map<String, dynamic> _dashboardStats = {};
  List<Map<String, dynamic>> _recentActivities = [];
  List<Map<String, dynamic>> _systemAlerts = [];
  List<Map<String, dynamic>> _users = [];
  List<Map<String, dynamic>> _reports = [];
  
  // Add metrics history state
  List<Map<String, dynamic>> _metricsHistory = [];
  
  bool _isLoading = true;
  bool _isActionLoading = false;
  String? _errorMessage;
  
  Timer? _refreshTimer;
  final String _baseUrl = 'http://54.146.215.18:3000';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _loadAdminData();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _animationController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      _loadAdminData();
    });
  }

  Future<void> _loadAdminData() async {
    try {
      await Future.wait([
        _fetchDashboardStats(),
        _fetchRecentActivities(),
        _fetchSystemAlerts(),
        _fetchUsers(),
        _fetchReports(),
        _fetchMetricsHistory(),
      ]);
      
      setState(() {
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Failed to load admin data: $e';
      });
    }
  }

  Future<void> _fetchDashboardStats() async {
    final response = await http.get(
      Uri.http('54.146.215.18:3000', '/admin/dashboard-stats'),
      headers: {'Authorization': 'Bearer ${widget.adminToken}'},
    );
    
    if (response.statusCode == 200) {
      _dashboardStats = json.decode(response.body);
    } else {
      throw Exception('Failed to fetch dashboard stats');
    }
  }

  Future<void> _fetchRecentActivities() async {
    final response = await http.get(
      Uri.http('54.146.215.18:3000', '/admin/recent-activities'),
      headers: {'Authorization': 'Bearer ${widget.adminToken}'},
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      _recentActivities = List<Map<String, dynamic>>.from(data['activities'] ?? []);
    }
  }

  Future<void> _fetchSystemAlerts() async {
    final response = await http.get(
      Uri.http('54.146.215.18:3000', '/admin/alerts'),
      headers: {'Authorization': 'Bearer ${widget.adminToken}'},
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      _systemAlerts = List<Map<String, dynamic>>.from(data['alerts'] ?? []);
    }
  }

  Future<void> _fetchUsers() async {
    final response = await http.get(
      Uri.http('54.146.215.18:3000', '/admin/users'),
      headers: {'Authorization': 'Bearer ${widget.adminToken}'},
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      _users = List<Map<String, dynamic>>.from(data['users'] ?? []);
    }
  }

  Future<void> _fetchReports() async {
    final response = await http.get(
      Uri.http('54.146.215.18:3000', '/admin/reports'),
      headers: {'Authorization': 'Bearer ${widget.adminToken}'},
    );
    
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      _reports = List<Map<String, dynamic>>.from(data['reports'] ?? []);
    }
  }

  Future<void> _fetchMetricsHistory() async {
    final response = await http.get(
      Uri.http('54.146.215.18:3000', '/admin/metrics-history'),
      headers: {'Authorization': 'Bearer ${widget.adminToken}'},
    );
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        _metricsHistory = List<Map<String, dynamic>>.from(data['metrics'] ?? []);
      });
    }
  }

  Widget _buildDashboardTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWelcomeCard(),
          const SizedBox(height: 20),
          _buildStatsGrid(),
          const SizedBox(height: 20),
          _buildRealTimeMetricsCard(),
          const SizedBox(height: 20),
          _buildChartsSection(),
          const SizedBox(height: 20),
          _buildQuickActionsGrid(),
          const SizedBox(height: 20),
          _buildRecentActivitiesCard(),
        ],
      ),
    );
  }

  Widget _buildWelcomeCard() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: [Colors.blue.shade700, Colors.blue.shade500],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            CircleAvatar(
              radius: 30,
              backgroundColor: Colors.white,
              child: Icon(
                Icons.admin_panel_settings,
                color: Colors.blue.shade700,
                size: 30,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome, ${widget.adminUsername}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Text(
                    'System Administrator',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Last login: ${DateTime.now().toString().substring(0, 16)}',
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              children: [
                IconButton(
                  onPressed: _loadAdminData,
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  tooltip: 'Refresh Data',
                ),
                IconButton(
                  onPressed: _showSystemInfo,
                  icon: const Icon(Icons.info, color: Colors.white),
                  tooltip: 'System Info',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    return SizedBox(
      height: 340, // Fixed height to prevent unbounded errors
      child: GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 1.5,
        children: [
          _buildStatCard(
            'Total Users',
            _dashboardStats['totalUsers']?.toString() ?? '0',
            Icons.people,
            Colors.blue,
            'Active: ${_dashboardStats['activeUsers'] ?? 0}',
          ),
          _buildStatCard(
            'System Health',
            '${_dashboardStats['systemHealth'] ?? 95}%',
            Icons.health_and_safety,
            Colors.green,
            'All systems operational',
          ),
          _buildStatCard(
            'Data Usage',
            '${_dashboardStats['dataUsage'] ?? 0} GB',
            Icons.storage,
            Colors.orange,
            'Monthly usage',
          ),
          _buildStatCard(
            'Active Sessions',
            _dashboardStats['activeSessions']?.toString() ?? '0',
            Icons.devices,
            Colors.purple,
            'Currently online',
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, String subtitle) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(icon, color: color, size: 24),
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.trending_up, color: color, size: 12),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
            Text(
              title,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: Colors.grey,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 9,
                color: Colors.grey.shade600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRealTimeMetricsCard() {
    final realTime = _dashboardStats['realTime'] ?? {};
    final mem = realTime['memory'] ?? {};
    final cpu = realTime['cpu'] ?? {};
    final disk = realTime['disk'] ?? {};
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Real-Time System Metrics',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildMetricTile(
                  icon: Icons.memory,
                  label: 'Memory',
                  value: mem.isNotEmpty
                      ? '${mem['usedGB'] ?? '?'} / ${mem['totalGB'] ?? '?'} GB'
                      : '--',
                  percent: mem['usagePercent']?.toDouble() ?? 0,
                  color: Colors.blue,
                ),
                _buildMetricTile(
                  icon: Icons.speed,
                  label: 'CPU',
                  value: cpu.isNotEmpty
                      ? '${cpu['usagePercent'] ?? '?'}%'
                      : '--',
                  percent: cpu['usagePercent']?.toDouble() ?? 0,
                  color: Colors.orange,
                ),
                _buildMetricTile(
                  icon: Icons.storage,
                  label: 'Disk',
                  value: disk.isNotEmpty
                      ? '${disk['usagePercent'] ?? '?'}%'
                      : '--',
                  percent: disk['usagePercent']?.toDouble() ?? 0,
                  color: Colors.green,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required IconData icon,
    required String label,
    required String value,
    required double percent,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 32),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        const SizedBox(height: 4),
        SizedBox(
          width: 60,
          child: LinearProgressIndicator(
            value: percent > 0 ? percent / 100 : 0,
            backgroundColor: color.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 6,
          ),
        ),
      ],
    );
  }

  Widget _buildChartsSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'System Analytics',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                PopupMenuButton<String>(
                  icon: const Icon(Icons.more_vert),
                  onSelected: (value) {},
                  itemBuilder: (context) => [
                    const PopupMenuItem(value: 'week', child: Text('This Week')),
                    const PopupMenuItem(value: 'month', child: Text('This Month')),
                    const PopupMenuItem(value: 'year', child: Text('This Year')),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 20),
            _buildMetricChart('CPU Usage', Colors.orange, 'cpu'),
            const SizedBox(height: 16),
            _buildMetricChart('Memory Usage', Colors.blue, 'memory'),
            const SizedBox(height: 16),
            _buildMetricChart('Disk Usage', Colors.green, 'disk'),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricChart(String title, Color color, String key) {
    if (_metricsHistory.isEmpty) {
      return const Center(child: Text('No data'));
    }
    final spots = <FlSpot>[];
    for (int i = 0; i < _metricsHistory.length; i++) {
      final value = (_metricsHistory[i][key] ?? 0).toDouble();
      spots.add(FlSpot(i.toDouble(), value));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        SizedBox(
          height: 100,
          child: LineChart(
            LineChartData(
              gridData: FlGridData(show: true, drawVerticalLine: false),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: true, reservedSize: 32),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  color: color,
                  barWidth: 2,
                  dotData: FlDotData(show: false),
                  belowBarData: BarAreaData(
                    show: true,
                    color: color.withOpacity(0.08),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionsGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Quick Actions',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        GridView.count(
          crossAxisCount: 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.2,
          children: [
            _buildQuickActionCard('Add User', Icons.person_add, Colors.green, _showAddUserDialog),
            _buildQuickActionCard('System Backup', Icons.backup, Colors.blue, _initiateBackup),
            _buildQuickActionCard('Send Alert', Icons.notification_important, Colors.orange, _showSendAlertDialog),
            _buildQuickActionCard('Generate Report', Icons.assessment, Colors.purple, _showGenerateReportDialog),
            _buildQuickActionCard('System Logs', Icons.list_alt, Colors.teal, _viewSystemLogs),
            _buildQuickActionCard('Settings', Icons.settings, Colors.grey, _openSystemSettings),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActionCard(String title, IconData icon, Color color, VoidCallback onTap) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRecentActivitiesCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent Activities',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: () {
                    // Navigate to full activity log
                  },
                  child: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _recentActivities.take(5).length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, index) {
                final activity = _recentActivities[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: _getActivityColor(activity['type']).withOpacity(0.2),
                    child: Icon(
                      _getActivityIcon(activity['type']),
                      color: _getActivityColor(activity['type']),
                      size: 20,
                    ),
                  ),
                  title: Text(
                    activity['description'] ?? 'Unknown activity',
                    style: const TextStyle(fontSize: 14),
                  ),
                  subtitle: Text(
                    activity['timestamp'] ?? '',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  trailing: Icon(
                    Icons.chevron_right,
                    color: Colors.grey.shade400,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserManagementTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'User Management',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _showAddUserDialog,
                icon: const Icon(Icons.person_add),
                label: const Text('Add User'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: TextField(
                      decoration: InputDecoration(
                        hintText: 'Search users...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onChanged: (value) {
                        // Implement search functionality
                      },
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: _users.length,
                      separatorBuilder: (context, index) => const Divider(),
                      itemBuilder: (context, index) {
                        final user = _users[index];
                        return _buildUserListItem(user);
                      },
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

  Widget _buildUserListItem(Map<String, dynamic> user) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.blue.shade100,
        child: Text(
          (user['username'] ?? '?')[0].toUpperCase(),
          style: TextStyle(
            color: Colors.blue.shade700,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Text(user['username'] ?? 'Unknown'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(user['email'] ?? ''),
          Text(
            'Role: ${user['designation'] ?? 'user'}',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
            ),
          ),
        ],
      ),
      trailing: PopupMenuButton<String>(
        onSelected: (value) => _handleUserAction(value, user),
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'edit', child: Text('Edit')),
          const PopupMenuItem(value: 'reset_password', child: Text('Reset Password')),
          const PopupMenuItem(value: 'suspend', child: Text('Suspend')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }

  Widget _buildSystemTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'System Management',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          _buildSystemHealthCard(),
          const SizedBox(height: 20),
          _buildSystemActionsCard(),
          const SizedBox(height: 20),
          _buildSystemLogsCard(),
        ],
      ),
    );
  }

  Widget _buildSystemHealthCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'System Health',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildHealthIndicator('CPU Usage', 45, Colors.green),
            _buildHealthIndicator('Memory Usage', 67, Colors.orange),
            _buildHealthIndicator('Disk Usage', 23, Colors.green),
            _buildHealthIndicator('Network', 89, Colors.red),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthIndicator(String label, int percentage, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(label),
              Text('$percentage%'),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: percentage / 100,
            backgroundColor: Colors.grey.shade300,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ],
      ),
    );
  }

  Widget _buildSystemActionsCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'System Actions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildSystemActionButton(
                  'Restart Server',
                  Icons.restart_alt,
                  Colors.orange,
                  _restartServer,
                ),
                _buildSystemActionButton(
                  'Clear Cache',
                  Icons.clear_all,
                  Colors.blue,
                  _clearCache,
                ),
                _buildSystemActionButton(
                  'Update System',
                  Icons.system_update,
                  Colors.green,
                  _updateSystem,
                ),
                _buildSystemActionButton(
                  'Export Logs',
                  Icons.download,
                  Colors.purple,
                  _exportLogs,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSystemActionButton(
    String label,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }

  Widget _buildSystemLogsCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Recent System Logs',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                TextButton(
                  onPressed: _viewSystemLogs,
                  child: const Text('View All'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              height: 200,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const SingleChildScrollView(
                padding: EdgeInsets.all(12),
                child: Text(
                  '[INFO] System startup completed\n'
                  '[INFO] Database connection established\n'
                  '[WARN] High memory usage detected\n'
                  '[INFO] User login: admin@example.com\n'
                  '[ERROR] Failed to connect to external API\n'
                  '[INFO] Backup completed successfully\n'
                  '[INFO] System health check passed',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Reports & Analytics',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _showGenerateReportDialog,
                icon: const Icon(Icons.add),
                label: const Text('Generate Report'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              childAspectRatio: 1.2,
              children: [
                _buildReportCard('User Activity', Icons.people, Colors.blue),
                _buildReportCard('System Performance', Icons.speed, Colors.green),
                _buildReportCard('Data Usage', Icons.storage, Colors.orange),
                _buildReportCard('Security Logs', Icons.security, Colors.red),
                _buildReportCard('Error Reports', Icons.error, Colors.purple),
                _buildReportCard('Custom Reports', Icons.analytics, Colors.teal),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(String title, IconData icon, Color color) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 36),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAlertsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'System Alerts',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              ElevatedButton.icon(
                onPressed: _showSendAlertDialog,
                icon: const Icon(Icons.add_alert),
                label: const Text('Send Alert'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Expanded(
            child: ListView.separated(
              itemCount: _systemAlerts.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final alert = _systemAlerts[index];
                return _buildAlertCard(alert);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    final severity = alert['severity'] ?? 'low';
    final color = _getAlertColor(severity);
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    severity.toUpperCase(),
                    style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  alert['created_at'] ?? '',
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              alert['title'] ?? 'No title',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              alert['message'] ?? 'No message',
              style: TextStyle(
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Admin Settings',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          _buildSettingsCard('Account Settings', Icons.account_circle, _openAccountSettings),
          _buildSettingsCard('Security Settings', Icons.security, _openSecuritySettings),
          _buildSettingsCard('Notification Settings', Icons.notifications, _openNotificationSettings),
          _buildSettingsCard('System Configuration', Icons.settings, _openSystemConfiguration),
          _buildSettingsCard('Backup Settings', Icons.backup, _openBackupSettings),
          _buildSettingsCard('API Settings', Icons.api, _openApiSettings),
        ],
      ),
    );
  }

  Widget _buildSettingsCard(String title, IconData icon, VoidCallback onTap) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(icon, color: Colors.blue),
        title: Text(title),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  // Action methods
  void _showAddUserDialog() {
    // Implement add user dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New User'),
        content: const Text('Add user functionality will be implemented here.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showSendAlertDialog() {
    // Implement send alert dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send System Alert'),
        content: const Text('Send alert functionality will be implemented here.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Send'),
          ),
        ],
      ),
    );
  }

  void _showGenerateReportDialog() {
    // Implement generate report dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Generate Report'),
        content: const Text('Report generation functionality will be implemented here.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Generate'),
          ),
        ],
      ),
    );
  }

  void _initiateBackup() async {
    setState(() => _isActionLoading = true);
    
    try {
      final response = await http.post(
        Uri.http('54.146.215.18:3000', '/admin/backup'),
        headers: {'Authorization': 'Bearer ${widget.adminToken}'},
      );
      
      if (response.statusCode == 200) {
        _showSuccessSnackBar('Backup initiated successfully');
      } else {
        _showErrorSnackBar('Failed to initiate backup');
      }
    } catch (e) {
      _showErrorSnackBar('Error: $e');
    } finally {
      setState(() => _isActionLoading = false);
    }
  }

  void _handleUserAction(String action, Map<String, dynamic> user) {
    // Implement user actions
    switch (action) {
      case 'edit':
        // Edit user
        break;
      case 'reset_password':
        // Reset password
        break;
      case 'suspend':
        // Suspend user
        break;
      case 'delete':
        // Delete user
        break;
    }
  }

  void _generateSpecificReport(String reportType) {
    // Implement specific report generation
    _showInfoSnackBar('Generating $reportType report...');
  }

  void _viewSystemLogs() {
    // Implement system logs viewer
    _showInfoSnackBar('Opening system logs...');
  }

  void _openSystemSettings() {
    // Implement system settings
    _showInfoSnackBar('Opening system settings...');
  }

  void _restartServer() {
    // Implement server restart
    _showWarningDialog('Restart Server', 'Are you sure you want to restart the server?');
  }

  void _clearCache() {
    // Implement cache clearing
    _showInfoSnackBar('Clearing cache...');
  }

  void _updateSystem() {
    // Implement system update
    _showInfoSnackBar('Checking for system updates...');
  }

  void _exportLogs() {
    // Implement log export
    _showInfoSnackBar('Exporting logs...');
  }

  void _openAccountSettings() {
    _showInfoSnackBar('Opening account settings...');
  }

  void _openSecuritySettings() {
    _showInfoSnackBar('Opening security settings...');
  }

  void _openNotificationSettings() {
    _showInfoSnackBar('Opening notification settings...');
  }

  void _openSystemConfiguration() {
    _showInfoSnackBar('Opening system configuration...');
  }

  void _openBackupSettings() {
    _showInfoSnackBar('Opening backup settings...');
  }

  void _openApiSettings() {
    _showInfoSnackBar('Opening API settings...');
  }

  void _showSystemInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('System Information'),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('System Version: 1.0.0'),
            Text('Database: PostgreSQL'),
            Text('Server: Node.js'),
            Text('Platform: Flutter'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Utility methods
  Color _getActivityColor(String? type) {
    switch (type) {
      case 'login': return Colors.green;
      case 'error': return Colors.red;
      case 'warning': return Colors.orange;
      case 'info': return Colors.blue;
      default: return Colors.grey;
    }
  }

  IconData _getActivityIcon(String? type) {
    switch (type) {
      case 'login': return Icons.login;
      case 'error': return Icons.error;
      case 'warning': return Icons.warning;
      case 'info': return Icons.info;
      default: return Icons.circle;
    }
  }

  Color _getAlertColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical': return Colors.red;
      case 'high': return Colors.orange;
      case 'medium': return Colors.yellow;
      case 'low': return Colors.blue;
      default: return Colors.grey;
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showInfoSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.blue,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showWarningDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showInfoSnackBar('Action confirmed');
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
          backgroundColor: Colors.blue.shade700,
          foregroundColor: Colors.white,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_errorMessage != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Admin Dashboard'),
          backgroundColor: Colors.blue.shade700,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error, size: 64, color: Colors.red.shade300),
              const SizedBox(height: 16),
              Text(_errorMessage!),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadAdminData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        backgroundColor: Colors.blue.shade700,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard), text: 'Dashboard'),
            Tab(icon: Icon(Icons.people), text: 'Users'),
            Tab(icon: Icon(Icons.computer), text: 'System'),
            Tab(icon: Icon(Icons.analytics), text: 'Reports'),
            Tab(icon: Icon(Icons.notifications), text: 'Alerts'),
            Tab(icon: Icon(Icons.settings), text: 'Settings'),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loadAdminData,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                Navigator.pop(context);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDashboardTab(),
          _buildUserManagementTab(),
          _buildSystemTab(),
          _buildReportsTab(),
          _buildAlertsTab(),
          _buildSettingsTab(),
        ],
      ),
    );
  }
}