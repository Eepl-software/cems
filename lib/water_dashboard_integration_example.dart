import 'package:flutter/material.dart';
import 'enhanced_water_dashboard.dart';
import 'widgets/enhanced_water_consumption_widget.dart';
import 'auth_service.dart';

/// Example showing how to integrate the enhanced water dashboard
/// Replace your existing water management page with this implementation
class WaterDashboardIntegrationExample extends StatefulWidget {
  final AuthService authService;

  const WaterDashboardIntegrationExample({
    Key? key,
    required this.authService,
  }) : super(key: key);

  @override
  State<WaterDashboardIntegrationExample> createState() => _WaterDashboardIntegrationExampleState();
}

class _WaterDashboardIntegrationExampleState extends State<WaterDashboardIntegrationExample> {
  int _selectedIndex = 0;
  String _selectedPhase = 'all';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Water Management Dashboard'),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              _showSettingsDialog();
            },
          ),
        ],
      ),
      body: IndexedStack(
        index: _selectedIndex,
        children: [
          // Enhanced Dashboard (Full-screen)
          const EnhancedWaterDashboard(),
          
          // Widget Integration Example
          _buildWidgetIntegrationExample(),
          
          // Comparison with Original
          _buildComparisonPage(),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.widgets),
            label: 'Widgets',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.compare),
            label: 'Compare',
          ),
        ],
      ),
    );
  }

  Widget _buildWidgetIntegrationExample() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Page header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.blue.shade600, Colors.cyan.shade500],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.water_drop,
                  color: Colors.white,
                  size: 32,
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
                        'Enhanced monitoring & analytics',
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.9),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Enhanced Water Consumption Widget
          EnhancedWaterConsumptionWidget(
            title: 'Real-time Consumption',
            height: 350,
            onPhaseChanged: (phase) {
              setState(() {
                _selectedPhase = phase;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Switched to: ${_formatPhaseName(phase)}'),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
          ),
          
          const SizedBox(height: 20),
          
          // Phase-specific widget
          EnhancedWaterConsumptionWidget(
            title: 'Phase: ${_formatPhaseName(_selectedPhase)}',
            height: 300,
            showHeader: true,
            allowPhaseSelection: false,
          ),
          
          const SizedBox(height: 20),
          
          // Compact widgets row
          Row(
            children: [
              Expanded(
                child: EnhancedWaterConsumptionWidget(
                  title: 'Today',
                  height: 200,
                  allowPhaseSelection: false,
                  padding: const EdgeInsets.all(8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: EnhancedWaterConsumptionWidget(
                  title: 'This Week',
                  height: 200,
                  allowPhaseSelection: false,
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 20),
          
          // Integration instructions
          _buildIntegrationInstructions(),
        ],
      ),
    );
  }

  Widget _buildComparisonPage() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dashboard Comparison',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 20),
          
          // Feature comparison table
          _buildFeatureComparison(),
          
          const SizedBox(height: 20),
          
          // Migration guide
          _buildMigrationGuide(),
        ],
      ),
    );
  }

  Widget _buildFeatureComparison() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Feature Comparison',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Table(
              border: TableBorder.all(color: Colors.grey.shade300),
              columnWidths: const {
                0: FlexColumnWidth(2),
                1: FlexColumnWidth(1),
                2: FlexColumnWidth(1),
              },
              children: [
                _buildTableRow('Feature', 'Original', 'Enhanced', isHeader: true),
                _buildTableRow('Real-time Updates', '❌', '✅'),
                _buildTableRow('Animated Charts', '❌', '✅'),
                _buildTableRow('Water Quality Monitoring', '❌', '✅'),
                _buildTableRow('Predictive Analytics', '❌', '✅'),
                _buildTableRow('Alert System', '❌', '✅'),
                _buildTableRow('Mobile Responsive', '✅', '✅'),
                _buildTableRow('Phase Selection', '✅', '✅'),
                _buildTableRow('Data Export', '❌', '✅'),
                _buildTableRow('Efficiency Metrics', '❌', '✅'),
                _buildTableRow('Beautiful UI/UX', '⚠️', '✅'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  TableRow _buildTableRow(String feature, String original, String enhanced, {bool isHeader = false}) {
    return TableRow(
      decoration: BoxDecoration(
        color: isHeader ? Colors.grey.shade100 : null,
      ),
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            feature,
            style: TextStyle(
              fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            original,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text(
            enhanced,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMigrationGuide() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Migration Guide',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildMigrationStep(
              '1',
              'Replace Existing Page',
              'Replace your current water_management.dart with enhanced_water_dashboard.dart',
              Colors.blue,
            ),
            _buildMigrationStep(
              '2',
              'Update Navigation',
              'Update your navigation routes to point to the new dashboard',
              Colors.green,
            ),
            _buildMigrationStep(
              '3',
              'Test Integration',
              'Test all functionality with your backend endpoints',
              Colors.orange,
            ),
            _buildMigrationStep(
              '4',
              'Customize',
              'Customize colors, layouts, and features to match your brand',
              Colors.purple,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMigrationStep(String step, String title, String description, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                step,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.grey.shade700,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIntegrationInstructions() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Integration Instructions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildInstructionItem(
              'Import the Widget',
              "import 'widgets/enhanced_water_consumption_widget.dart';",
            ),
            _buildInstructionItem(
              'Use in Your Page',
              '''EnhancedWaterConsumptionWidget(
  title: 'Water Consumption',
  height: 350,
  onPhaseChanged: (phase) {
    // Handle phase change
  },
)''',
            ),
            _buildInstructionItem(
              'Customize Appearance',
              '''EnhancedWaterConsumptionWidget(
  title: 'Custom Title',
  height: 300,
  showHeader: false,
  allowPhaseSelection: true,
  padding: EdgeInsets.all(16),
)''',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstructionItem(String title, String code) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Text(
              code,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatPhaseName(String phase) {
    switch (phase) {
      case 'all':
        return 'All Phases';
      case 'construction':
        return 'Construction';
      case 'labour_colony':
        return 'Labour Colony';
      case 'operational':
        return 'Operational';
      default:
        return phase.replaceAll('_', ' ').toUpperCase();
    }
  }

  void _showSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dashboard Settings'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.refresh),
              title: const Text('Auto-refresh'),
              subtitle: const Text('Refresh data every 30 seconds'),
              trailing: Switch(
                value: true,
                onChanged: (value) {
                  // Handle auto-refresh toggle
                },
              ),
            ),
            ListTile(
              leading: const Icon(Icons.notifications),
              title: const Text('Alerts'),
              subtitle: const Text('Show consumption alerts'),
              trailing: Switch(
                value: true,
                onChanged: (value) {
                  // Handle alerts toggle
                },
              ),
            ),
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
}