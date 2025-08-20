import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'cement/cement.dart';
import 'sand/sand.dart';
import 'metals/metals.dart';
import 'pipes/pipes.dart';
import 'tiles/tiles.dart';
import 'wood/wood.dart';
import 'electricals/electricals.dart';
import 'plastic/plastic.dart';
import 'aggregates/aggregates.dart';

class ConstructionMaterialsDashboard extends StatefulWidget {
  const ConstructionMaterialsDashboard({Key? key}) : super(key: key);

  @override
  State<ConstructionMaterialsDashboard> createState() => _ConstructionMaterialsDashboardState();
}

class _ConstructionMaterialsDashboardState extends State<ConstructionMaterialsDashboard> {
  Map<String, Map<String, dynamic>> materialsData = {};
  bool isLoading = true;
  String? error;
  Timer? _refreshTimer;

  final String baseUrl = 'http://54.146.215.18:3000';

  final List<Map<String, dynamic>> materialCategories = [
    {
      'name': 'cement',
      'displayName': 'Cement Management',
      'icon': '🔧',
      'color': Colors.brown,
      'page': const CementPage(),
      'endpoint': '/api/cement-analytics',
    },
    {
      'name': 'sand',
      'displayName': 'Sand Management', 
      'icon': '🚛',
      'color': Colors.orange,
      'page': const SandPage(),
      'endpoint': '/api/sand-analytics',
    },
    {
      'name': 'metals',
      'displayName': 'Metals Management',
      'icon': '🔧',
      'color': Colors.grey,
      'page': const MetalsPage(),
      'endpoint': '/api/metals-analytics',
    },
    {
      'name': 'pipes',
      'displayName': 'Pipes Management',
      'icon': '🔧',
      'color': Colors.blue,
      'page': const PipesPage(),
      'endpoint': '/api/pipes-analytics',
    },
    {
      'name': 'tiles',
      'displayName': 'Tiles Management',
      'icon': '⬜',
      'color': Colors.purple,
      'page': const TilesPage(),
      'endpoint': '/api/tiles-analytics',
    },
    {
      'name': 'wood',
      'displayName': 'Wood Management',
      'icon': '🌲',
      'color': Colors.green,
      'page': const WoodPage(),
      'endpoint': '/api/wood-analytics',
    },
    {
      'name': 'electricals',
      'displayName': 'Electricals Management',
      'icon': '⚡',
      'color': Colors.yellow,
      'page': const ElectricalsPage(),
      'endpoint': '/api/electricals-analytics',
    },
    {
      'name': 'plastic',
      'displayName': 'Plastic Management',
      'icon': '♻️',
      'color': Colors.teal,
      'page': const PlasticPage(),
      'endpoint': '/api/plastic-analytics',
    },
    {
      'name': 'aggregates',
      'displayName': 'Aggregates Management',
      'icon': '⚡',
      'color': Colors.deepOrange,
      'page': const AggregatesPage(),
      'endpoint': '/api/aggregates-analytics',
    },
  ];

  @override
  void initState() {
    super.initState();
    _fetchAllMaterialsData();
    _startRefreshTimer();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startRefreshTimer() {
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _fetchAllMaterialsData();
    });
  }

  Future<void> _fetchAllMaterialsData() async {
    setState(() {
      isLoading = true;
      error = null;
    });

    Map<String, Map<String, dynamic>> newData = {};
    
    for (var category in materialCategories) {
      try {
        final response = await http.get(
          Uri.parse('$baseUrl${category['endpoint']}'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] == true) {
            // Extract key metrics from the analytics data
            final analytics = data['data'];
            final summary = analytics['summary'] ?? {};
            
            newData[category['name']] = {
              'totalSubmissions': _parseNumber(summary['total_submissions']),
              'totalGrossWeight': _parseWeight(summary['total_gross_weight']),
              'totalNetWeight': _parseWeight(summary['total_net_weight']),
              'uniqueVehicles': _parseNumber(summary['total_unique_vehicles']),
              'status': 'success',
            };
          } else {
            newData[category['name']] = {
              'totalSubmissions': 0,
              'totalGrossWeight': 0.0,
              'totalNetWeight': 0.0,
              'uniqueVehicles': 0,
              'status': 'no_data',
            };
          }
        } else {
          newData[category['name']] = {
            'totalSubmissions': 0,
            'totalGrossWeight': 0.0,
            'totalNetWeight': 0.0,
            'uniqueVehicles': 0,
            'status': 'error',
          };
        }
      } catch (e) {
        print('Error fetching ${category['name']} data: $e');
        newData[category['name']] = {
          'totalSubmissions': 0,
          'totalGrossWeight': 0.0,
          'totalNetWeight': 0.0,
          'uniqueVehicles': 0,
          'status': 'error',
        };
      }
    }

    setState(() {
      materialsData = newData;
      isLoading = false;
    });
  }

  double _parseWeight(dynamic weight) {
    if (weight == null) return 0.0;
    if (weight is num) return weight.toDouble();
    if (weight is String) {
      final parsed = double.tryParse(weight);
      return parsed ?? 0.0;
    }
    return 0.0;
  }

  int _parseNumber(dynamic number) {
    if (number == null) return 0;
    if (number is int) return number;
    if (number is double) return number.toInt();
    if (number is String) {
      final parsed = int.tryParse(number);
      return parsed ?? 0;
    }
    return 0;
  }

  void _navigateToMaterialPage(Widget page) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => page),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Construction Materials Management'),
        backgroundColor: Colors.blue[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchAllMaterialsData,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _fetchAllMaterialsData,
        child: isLoading
            ? const Center(child: CircularProgressIndicator())
            : error != null
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                        const SizedBox(height: 16),
                        Text(
                          'Error: $error',
                          style: TextStyle(color: Colors.red[600]),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchAllMaterialsData,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : _buildDashboardContent(),
      ),
    );
  }

  Widget _buildDashboardContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildOverallSummary(),
          const SizedBox(height: 24),
          _buildMaterialCategories(),
        ],
      ),
    );
  }

  Widget _buildOverallSummary() {
    int totalSubmissions = 0;
    double totalNetWeight = 0.0;
    int totalVehicles = 0;
    int activeMaterials = 0;

    for (var data in materialsData.values) {
      totalSubmissions += (data['totalSubmissions'] ?? 0) as int;
      totalNetWeight += (data['totalNetWeight'] ?? 0.0) as double;
      totalVehicles += (data['uniqueVehicles'] ?? 0) as int;
      if (data['status'] == 'success' && (data['totalSubmissions'] ?? 0) > 0) {
        activeMaterials++;
      }
    }

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.construction, size: 28, color: Colors.blue[600]),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Overall Summary',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    'Total Materials',
                    '$activeMaterials',
                    Icons.category,
                    Colors.green,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    'Total Submissions',
                    '$totalSubmissions',
                    Icons.upload_file,
                    Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryCard(
                    'Total Net Weight',
                    '${totalNetWeight.toStringAsFixed(0)} KG',
                    Icons.scale,
                    Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildSummaryCard(
                    'Total Vehicles',
                    '$totalVehicles',
                    Icons.local_shipping,
                    Colors.purple,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withAlpha(51)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: color),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildMaterialCategories() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Material Categories',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 16),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.75,
          ),
          itemCount: materialCategories.length,
          itemBuilder: (context, index) {
            final category = materialCategories[index];
            final data = materialsData[category['name']] ?? {};
            
            return _buildMaterialCard(category, data);
          },
        ),
      ],
    );
  }

  Widget _buildMaterialCard(Map<String, dynamic> category, Map<String, dynamic> data) {
    final totalSubmissions = data['totalSubmissions'] ?? 0;
    final totalNetWeight = data['totalNetWeight'] ?? 0.0;
    final uniqueVehicles = data['uniqueVehicles'] ?? 0;
    final status = data['status'] ?? 'error';

    Color statusColor;
    String statusText;
    switch (status) {
      case 'success':
        statusColor = Colors.green;
        statusText = 'Active';
      case 'no_data':
        statusColor = Colors.grey;
        statusText = 'No Data';
      default:
        statusColor = Colors.red;
        statusText = 'Error';
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: () => _navigateToMaterialPage(category['page']),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: (category['color'] as Color).withAlpha(51),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      category['icon'],
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                  const Spacer(),
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withAlpha(51),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Flexible(
                child: Text(
                  category['displayName'],
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 8),
              _buildDataRow(Icons.scale, 'Net Weight', '${totalNetWeight.toStringAsFixed(0)} KG'),
              const SizedBox(height: 4),
              _buildDataRow(Icons.upload_file, 'Submissions', '$totalSubmissions'),
              const SizedBox(height: 4),
              _buildDataRow(Icons.local_shipping, 'Vehicles', '$uniqueVehicles'),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _navigateToMaterialPage(category['page']),
                  icon: const Icon(Icons.arrow_forward, size: 16),
                  label: const Text('Manage', style: TextStyle(fontSize: 12)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: category['color'],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    minimumSize: const Size(0, 32),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 14, color: Colors.grey[600]),
        const SizedBox(width: 6),
        Expanded(
          child: RichText(
            overflow: TextOverflow.ellipsis,
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$label: ',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey[600],
                  ),
                ),
                TextSpan(
                  text: value,
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}