
// import 'package:flutter/material.dart';

// class GroundWaterPage extends StatefulWidget {
//   @override
//   _GroundWaterPageState createState() => _GroundWaterPageState();
// }

// class _GroundWaterPageState extends State<GroundWaterPage> {
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('Ground Water Management'),
//       ),
//       body: Padding(
//         padding: const EdgeInsets.all(16.0),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             Text(
//               'Ground Water Management',
//               style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
//             ),
//             SizedBox(height: 16),
//             Text(
//               'Effective management of groundwater resources is essential for sustainable water supply.',
//               style: TextStyle(fontSize: 16),
//             ),
//             SizedBox(height: 16),
//             Icon(Icons.opacity, size: 100, color: Colors.brown),
//             // Add more content and features here
//           ],
//         ),
//       ),
//     );
//   }
// }





import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';

class GroundWaterPage extends StatefulWidget {
  @override
  _GroundWaterPageState createState() => _GroundWaterPageState();
}

class _GroundWaterPageState extends State<GroundWaterPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  double _currentWaterLevel = 75.0; // Sample data - percentage of capacity
  
  // Sample water level history data
  final List<FlSpot> waterLevelData = [
    FlSpot(0, 65),
    FlSpot(1, 68),
    FlSpot(2, 75),
    FlSpot(3, 72),
    FlSpot(4, 70),
    FlSpot(5, 75),
    FlSpot(6, 78),
  ];
  
  // Sample water quality parameters
  final Map<String, double> waterQualityParams = {
    'pH': 7.2,
    'TDS (ppm)': 320,
    'Hardness': 150,
    'Nitrate (mg/L)': 3.5,
    'Fluoride (mg/L)': 0.8,
  };

  // Sample conservation tips
  final List<Map<String, dynamic>> conservationTips = [
    {
      'title': 'Reduce Irrigation Waste',
      'description': 'Use drip irrigation and water early morning or evening to reduce evaporation.',
      'icon': Icons.whatshot,
    },
    {
      'title': 'Harvest Rainwater',
      'description': 'Collect and store rainwater for garden use during dry periods.',
      'icon': Icons.water_drop,
    },
    {
      'title': 'Fix Leaks Immediately',
      'description': 'A small leak can waste thousands of gallons annually.',
      'icon': Icons.plumbing,
    },
    {
      'title': 'Use Water-Efficient Appliances',
      'description': 'Modern appliances can reduce water consumption by 30-50%.',
      'icon': Icons.wash,
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Ground Water Management'),
        backgroundColor: Colors.blue[700],
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(Icons.notifications),
            onPressed: () {
              // Show notifications
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Water level alerts will appear here')),
              );
            },
          ),
          IconButton(
            icon: Icon(Icons.info_outline),
            onPressed: () {
              // Show info dialog
              showAboutDialog(
                context: context,
                applicationName: 'Ground Water Management',
                applicationVersion: '1.0.0',
                applicationIcon: Icon(Icons.water, color: Colors.blue),
                children: [
                  Text('A comprehensive tool for monitoring and managing groundwater resources effectively.'),
                ],
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          tabs: [
            Tab(icon: Icon(Icons.dashboard), text: "Dashboard"),
            Tab(icon: Icon(Icons.analytics), text: "Analytics"),
            Tab(icon: Icon(Icons.tips_and_updates), text: "Tips"),
            Tab(icon: Icon(Icons.settings), text: "Settings"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildDashboardTab(),
          _buildAnalyticsTab(),
          _buildTipsTab(),
          _buildSettingsTab(),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          // Add action for reporting issues or adding data points
          showDialog(
            context: context,
            builder: (context) => AlertDialog(
              title: Text('Report Water Issue'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    decoration: InputDecoration(
                      labelText: 'Issue Description',
                      border: OutlineInputBorder(),
                    ),
                    maxLines: 3,
                  ),
                  SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.attach_file),
                      Text('Add photo or document'),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('CANCEL'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Report submitted successfully')),
                    );
                  },
                  child: Text('SUBMIT'),
                ),
              ],
            ),
          );
        },
        child: Icon(Icons.add),
        backgroundColor: Colors.blue[700],
      ),
    );
  }

  Widget _buildDashboardTab() {
    return SingleChildScrollView(
      padding: EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildWaterLevelCard(),
          SizedBox(height: 16),
          _buildWaterQualityCard(),
          SizedBox(height: 16),
          _buildWeatherForecastCard(),
          SizedBox(height: 16),
          _buildRecentActivityCard(),
        ],
      ),
    );
  }

  Widget _buildWaterLevelCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Current Water Level',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Icon(Icons.opacity, color: Colors.blue),
              ],
            ),
            SizedBox(height: 16),
            Center(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    height: 120,
                    width: 120,
                    child: CircularProgressIndicator(
                      value: _currentWaterLevel / 100,
                      strokeWidth: 12,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        _getWaterLevelColor(_currentWaterLevel),
                      ),
                    ),
                  ),
                  Column(
                    children: [
                      Text(
                        '${_currentWaterLevel.toStringAsFixed(1)}%',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: _getWaterLevelColor(_currentWaterLevel),
                        ),
                      ),
                      Text(
                        'of capacity',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildStatusIndicator('Daily Change', '+0.3%', Colors.green),
                _buildStatusIndicator('Safe Level', '> 60%', Colors.blue),
                _buildStatusIndicator('Critical', '< 30%', Colors.red),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusIndicator(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
        SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildWaterQualityCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Water Quality Parameters',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Icon(Icons.science, color: Colors.purple),
              ],
            ),
            SizedBox(height: 16),
            ...waterQualityParams.entries.map((entry) {
              return Padding(
                padding: EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(entry.key),
                    Text(
                      entry.value.toString(),
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              );
            }).toList(),
            SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                // Action to show detailed quality report
              },
              child: Text('VIEW DETAILED REPORT'),
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 40),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeatherForecastCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Weather Forecast',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Icon(Icons.wb_sunny, color: Colors.orange),
              ],
            ),
            SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildWeatherDay('Today', Icons.wb_sunny, '32°C', '0%'),
                _buildWeatherDay('Wed', Icons.cloud, '28°C', '30%'),
                _buildWeatherDay('Thu', Icons.grain, '27°C', '70%'),
                _buildWeatherDay('Fri', Icons.wb_sunny, '30°C', '10%'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWeatherDay(String day, IconData icon, String temp, String rain) {
    return Column(
      children: [
        Text(day, style: TextStyle(fontWeight: FontWeight.w500)),
        SizedBox(height: 8),
        Icon(icon, size: 24),
        SizedBox(height: 8),
        Text(temp),
        Text('Rain: $rain', style: TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildRecentActivityCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16.0),
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
                  ),
                ),
                Icon(Icons.history, color: Colors.blueGrey),
              ],
            ),
            SizedBox(height: 16),
            _buildActivityItem(
              Icons.arrow_downward,
              Colors.red,
              'Water level decreased by 0.5%',
              '2 hours ago',
            ),
            _buildActivityItem(
              Icons.warning,
              Colors.amber,
              'pH level slightly above normal',
              '6 hours ago',
            ),
            _buildActivityItem(
              Icons.check_circle,
              Colors.green,
              'Maintenance check completed',
              'Yesterday',
            ),
            _buildActivityItem(
              Icons.cloud_download,
              Colors.blue,
              'Rainfall added 2.3% to reserves',
              '2 days ago',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityItem(
      IconData icon, Color color, String text, String time) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text),
                Text(
                  time,
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsTab() {
  return Padding(
    padding: EdgeInsets.all(16.0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Water Level History',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 8),
        Text(
          'Last 7 days trend',
          style: TextStyle(
            color: Colors.grey[600],
          ),
        ),
        SizedBox(height: 16),
        Container(
          height: 300,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.2),
                spreadRadius: 1,
                blurRadius: 5,
                offset: Offset(0, 3),
              ),
            ],
          ),
          padding: EdgeInsets.all(16),
          child: LineChart(
            LineChartData(
              gridData: FlGridData(
                show: true,
                drawVerticalLine: true,
                getDrawingHorizontalLine: (value) {
                  return FlLine(
                    color: Colors.grey[300],
                    strokeWidth: 1,
                  );
                },
                getDrawingVerticalLine: (value) {
                  return FlLine(
                    color: Colors.grey[300],
                    strokeWidth: 1,
                  );
                },
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    getTitlesWidget: (value, meta) {
                      final style = TextStyle(
                        color: Color(0xff68737d),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      );
                      String text;
                      switch (value.toInt()) {
                        case 0:
                          text = 'Mon';
                          break;
                        case 1:
                          text = 'Tue';
                          break;
                        case 2:
                          text = 'Wed';
                          break;
                        case 3:
                          text = 'Thu';
                          break;
                        case 4:
                          text = 'Fri';
                          break;
                        case 5:
                          text = 'Sat';
                          break;
                        case 6:
                          text = 'Sun';
                          break;
                        default:
                          text = '';
                          break;
                      }
                      return Text(text, style: style);
                    },
                    interval: 1,
                  ),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final style = TextStyle(
                        color: Color(0xff67727d),
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      );
                      
                      if (value % 10 == 0) {
                        return Text('${value.toInt()}%', style: style);
                      }
                      return Text('');
                    },
                    reservedSize: 28,
                    interval: 10,
                  ),
                ),
                topTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border.all(color: const Color(0xff37434d), width: 1),
              ),
              minX: 0,
              maxX: 6,
              minY: 60,
              maxY: 80,
              lineBarsData: [
                LineChartBarData(
                  spots: waterLevelData,
                  isCurved: true,
                  color: Colors.blue[700],
                  barWidth: 4,
                  isStrokeCapRound: true,
                  dotData: FlDotData(show: true),
                  belowBarData: BarAreaData(
                    show: true,
                    color: Colors.blue[200]!.withOpacity(0.3),
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 24),
        _buildDataFilterChips(),
        SizedBox(height: 24),
        Text(
          'Analytical Insights',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 16),
        _buildInsightCard(
          'Seasonal Pattern',
          'Water levels typically rise during monsoon (Jul-Sep) and fall during summer (Apr-Jun).',
          Icons.timeline,
        ),
        SizedBox(height: 12),
        _buildInsightCard(
          'Usage Trend',
          'Consumption increased by 12% compared to same period last year.',
          Icons.trending_up,
        ),
      ],
    ),
  );
}

  Widget _buildDataFilterChips() {
    return Wrap(
      spacing: 8.0,
      children: [
        ChoiceChip(
          label: Text('7 Days'),
          selected: true,
          onSelected: (selected) {},
        ),
        ChoiceChip(
          label: Text('1 Month'),
          selected: false,
          onSelected: (selected) {},
        ),
        ChoiceChip(
          label: Text('3 Months'),
          selected: false,
          onSelected: (selected) {},
        ),
        ChoiceChip(
          label: Text('1 Year'),
          selected: false,
          onSelected: (selected) {},
        ),
      ],
    );
  }

  Widget _buildInsightCard(String title, String description, IconData icon) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: EdgeInsets.all(16.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.blue),
            ),
            SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    description,
                    style: TextStyle(color: Colors.grey[700]),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipsTab() {
    return ListView(
      padding: EdgeInsets.all(16.0),
      children: [
        Text(
          'Water Conservation Tips',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        SizedBox(height: 16),
        ...conservationTips.map((tip) => _buildTipCard(tip)).toList(),
        SizedBox(height: 24),
        ElevatedButton.icon(
          onPressed: () {
            
            // Action to show more tips or resources
          },
          icon: Icon(Icons.library_books),
          label: Text('WATER CONSERVATION RESOURCES'),
          style: ElevatedButton.styleFrom(
            padding: EdgeInsets.symmetric(vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildTipCard(Map<String, dynamic> tip) {
    return Card(
      margin: EdgeInsets.only(bottom: 16),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(tip['icon'], color: Colors.blue),
        ),
        title: Text(
          tip['title'],
          style: TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        children: [
          Padding(
            padding: EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tip['description'],
                  style: TextStyle(fontSize: 16),
                ),
                SizedBox(height: 12),
                Divider(),
                SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildActionButton(Icons.share, 'Share'),
                    _buildActionButton(Icons.bookmark_border, 'Save'),
                    _buildActionButton(Icons.thumb_up_outlined, 'Helpful'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(IconData icon, String label) {
    return InkWell(
      onTap: () {},
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Column(
          children: [
            Icon(icon, size: 20),
            SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsTab() {
    return ListView(
      padding: EdgeInsets.all(16.0),
      children: [
        _buildSettingSection('Alerts & Notifications'),
        SwitchListTile(
          title: Text('Water Level Alerts'),
          subtitle: Text('Get notified when levels change significantly'),
          value: true,
          onChanged: (value) {},
        ),
        SwitchListTile(
          title: Text('Quality Warnings'),
          subtitle: Text('Be alerted of water quality issues'),
          value: true,
          onChanged: (value) {},
        ),
        SwitchListTile(
          title: Text('Weather Updates'),
          subtitle: Text('Receive rainfall forecasts'),
          value: false,
          onChanged: (value) {},
        ),
        Divider(),
        _buildSettingSection('Data & Privacy'),
        ListTile(
          title: Text('Data Usage'),
          subtitle: Text('Manage how your data is collected and used'),
          trailing: Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () {},
        ),
        ListTile(
          title: Text('Export Data'),
          subtitle: Text('Download your water usage statistics'),
          trailing: Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () {},
        ),
        Divider(),
        _buildSettingSection('About'),
        ListTile(
          title: Text('App Version'),
          subtitle: Text('1.0.0'),
        ),
        ListTile(
          title: Text('Terms of Service'),
          trailing: Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () {},
        ),
        ListTile(
          title: Text('Privacy Policy'),
          trailing: Icon(Icons.arrow_forward_ios, size: 16),
          onTap: () {},
        ),
        SizedBox(height: 24),
        ElevatedButton(
  onPressed: () {
    // Logout action
  },
  style: ElevatedButton.styleFrom(
    backgroundColor: Colors.red, // Replace 'primary' with 'backgroundColor'
    padding: EdgeInsets.symmetric(vertical: 12),
  ),
  child: Text('LOG OUT'),
),
      ],
    );
  }

  Widget _buildSettingSection(String title) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.0),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.blue[700],
        ),
      ),
    );
  }

  Color _getWaterLevelColor(double level) {
    if (level < 30) {
      return Colors.red;
    } else if (level < 60) {
      return Colors.orange;
    } else {
      return Colors.green;
    }
  }
}