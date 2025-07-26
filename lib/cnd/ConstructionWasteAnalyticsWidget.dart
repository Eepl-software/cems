import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ConstructionWasteAnalyticsWidget extends StatefulWidget {
  const ConstructionWasteAnalyticsWidget({Key? key}) : super(key: key);

  @override
  _ConstructionWasteAnalyticsWidgetState createState() => _ConstructionWasteAnalyticsWidgetState();
}

class _ConstructionWasteAnalyticsWidgetState extends State<ConstructionWasteAnalyticsWidget>
    with TickerProviderStateMixin {
  late TabController _tabController;
  
  bool _isLoading = true;
  Map<String, dynamic> _analyticsData = {};
  List<ConstructionWasteRecord> _recentRecords = [];
  String _selectedPeriod = '30'; // Days
  
  final List<String> _periodOptions = ['7', '30', '90', '365'];
  final Map<String, String> _periodLabels = {
    '7': '7 Days',
    '30': '30 Days', 
    '90': '3 Months',
    '365': '1 Year'
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _fetchAnalyticsData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchAnalyticsData() async {
    setState(() => _isLoading = true);
    
    try {
      const String baseUrl = 'http://54.146.215.18:3000';
      final endDate = DateTime.now();
      final startDate = endDate.subtract(Duration(days: int.parse(_selectedPeriod)));
      
      // Fetch analytics data
      final statsResponse = await http.get(
        Uri.http('54.146.215.18:3000', '/construction-phase-waste/stats', {
          'start_date': DateFormat('yyyy-MM-dd').format(startDate),
          'end_date': DateFormat('yyyy-MM-dd').format(endDate),
        }),
      );
      
      // Fetch recent records for trend analysis
      final recordsResponse = await http.get(
        Uri.http('54.146.215.18:3000', '/construction-phase-waste', {
          'limit': '50',
          'start_date': DateFormat('yyyy-MM-dd').format(startDate),
          'end_date': DateFormat('yyyy-MM-dd').format(endDate),
        }),
      );
      
      if (statsResponse.statusCode == 200 && recordsResponse.statusCode == 200) {
        final statsData = json.decode(statsResponse.body);
        final recordsData = json.decode(recordsResponse.body);
        
        setState(() {
          _analyticsData = statsData;
          _recentRecords = (recordsData['data'] as List? ?? [])
              .map((json) => ConstructionWasteRecord.fromJson(json))
              .toList();
        });
      }
    } catch (e) {
      print('Error fetching analytics data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Construction Waste Analytics'),
        backgroundColor: Colors.brown[700],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.trending_up), text: 'Trends'),
            Tab(icon: Icon(Icons.pie_chart), text: 'Composition'),
            Tab(icon: Icon(Icons.bar_chart), text: 'Efficiency'),
            Tab(icon: Icon(Icons.insights), text: 'Insights'),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              setState(() {
                _selectedPeriod = value;
              });
              _fetchAnalyticsData();
            },
            itemBuilder: (context) => _periodOptions.map((period) {
              return PopupMenuItem<String>(
                value: period,
                child: Row(
                  children: [
                    Icon(
                      _selectedPeriod == period ? Icons.check : Icons.schedule,
                      color: _selectedPeriod == period ? Colors.green : Colors.grey,
                    ),
                    const SizedBox(width: 8),
                    Text(_periodLabels[period]!),
                  ],
                ),
              );
            }).toList(),
            icon: const Icon(Icons.date_range),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildTrendsTab(),
                _buildCompositionTab(),
                _buildEfficiencyTab(),
                _buildInsightsTab(),
              ],
            ),
    );
  }

  Widget _buildTrendsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildPeriodSummaryCard(),
          const SizedBox(height: 16),
          _buildWasteTrendChart(),
          const SizedBox(height: 16),
          _buildLabourWasteChart(),
        ],
      ),
    );
  }

  Widget _buildPeriodSummaryCard() {
    final summary = _analyticsData['summary'] ?? {};
    
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.summarize, color: Colors.brown[700]),
                const SizedBox(width: 8),
                Text(
                  'Period Summary (${_periodLabels[_selectedPeriod]})',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.brown[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryMetric(
                    'Total Records',
                    '${_safeParseDouble(summary['total_records']).toInt()}',
                    Icons.receipt_long,
                    Colors.blue,
                  ),
                ),
                Expanded(
                  child: _buildSummaryMetric(
                    'Total Waste',
                    '${_safeParseDouble(summary['total_waste_generated']).toStringAsFixed(1)} kg',
                    Icons.scale,
                    Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildSummaryMetric(
                    'Avg Labour',
                    '${_safeParseDouble(summary['avg_labour_count']).toStringAsFixed(0)}',
                    Icons.people,
                    Colors.orange,
                  ),
                ),
                Expanded(
                  child: _buildSummaryMetric(
                    'Waste/Labour',
                    '${_safeParseDouble(summary['avg_waste_per_labour']).toStringAsFixed(2)} kg',
                    Icons.person,
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

  Widget _buildSummaryMetric(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildWasteTrendChart() {
    if (_recentRecords.isEmpty) {
      return _buildEmptyChart('No data available for waste trend');
    }

    // Group records by date and calculate daily totals
    final Map<DateTime, double> dailyWaste = {};
    for (final record in _recentRecords) {
      final date = DateTime(record.date.year, record.date.month, record.date.day);
      dailyWaste[date] = (dailyWaste[date] ?? 0) + record.totalWasteGenerated;
    }

    final sortedDates = dailyWaste.keys.toList()..sort();
    final chartData = sortedDates.asMap().entries.map((entry) {
      return FlSpot(entry.key.toDouble(), dailyWaste[entry.value]!);
    }).toList();

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.trending_up, color: Colors.brown[700]),
                const SizedBox(width: 8),
                const Text(
                  'Daily Waste Generation Trend',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: FlGridData(show: true),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${value.toInt()}kg',
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() < sortedDates.length) {
                            return Text(
                              DateFormat('MM/dd').format(sortedDates[value.toInt()]),
                              style: const TextStyle(fontSize: 10),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: true),
                  lineBarsData: [
                    LineChartBarData(
                      spots: chartData,
                      isCurved: true,
                      color: Colors.brown[700],
                      barWidth: 3,
                      dotData: const FlDotData(show: true),
                      belowBarData: BarAreaData(
                        show: true,
                        color: Colors.brown[700]!.withOpacity(0.1),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLabourWasteChart() {
    if (_recentRecords.isEmpty) {
      return _buildEmptyChart('No data available for labour analysis');
    }

    // Create scatter plot data for labour vs waste
    final chartData = _recentRecords.asMap().entries.map((entry) {
      return FlSpot(
        entry.value.approxNoOfLabour.toDouble(),
        entry.value.totalWasteGenerated,
      );
    }).toList();

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.scatter_plot, color: Colors.brown[700]),
                const SizedBox(width: 8),
                const Text(
                  'Labour vs Waste Generation',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: ScatterChart(
                ScatterChartData(
                  scatterSpots: chartData.map((spot) => ScatterSpot(
                    spot.x,
                    spot.y,
                    color: Colors.brown[700]!,
                    radius: 6,
                  )).toList(),
                  minX: 0,
                  minY: 0,
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 50,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${value.toInt()}kg',
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 30,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            '${value.toInt()}',
                            style: const TextStyle(fontSize: 10),
                          );
                        },
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(show: true),
                  borderData: FlBorderData(show: true),
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'X-axis: Number of Labour | Y-axis: Waste Generated (kg)',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompositionTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildWasteCompositionChart(),
          const SizedBox(height: 16),
          _buildCompositionBreakdown(),
        ],
      ),
    );
  }

  Widget _buildWasteCompositionChart() {
    final summary = _analyticsData['summary'] ?? {};
    final dryWaste = _safeParseDouble(summary['total_dry_waste']);
    final wetWaste = _safeParseDouble(summary['total_wet_waste']);
    final total = dryWaste + wetWaste;

    if (total <= 0) {
      return _buildEmptyChart('No waste composition data available');
    }

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                Icon(Icons.pie_chart, color: Colors.brown[700]),
                const SizedBox(width: 8),
                const Text(
                  'Waste Type Composition',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                  sections: [
                    PieChartSectionData(
                      value: dryWaste,
                      title: '${(dryWaste / total * 100).toStringAsFixed(1)}%',
                      color: Colors.orange[700],
                      radius: 80,
                      titleStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    PieChartSectionData(
                      value: wetWaste,
                      title: '${(wetWaste / total * 100).toStringAsFixed(1)}%',
                      color: Colors.blue[700],
                      radius: 80,
                      titleStyle: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildLegendItem('Dry Waste', Colors.orange[700]!),
                _buildLegendItem('Wet Waste', Colors.blue[700]!),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompositionBreakdown() {
    final summary = _analyticsData['summary'] ?? {};
    final dryWaste = _safeParseDouble(summary['total_dry_waste']);
    final wetWaste = _safeParseDouble(summary['total_wet_waste']);

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.analytics, color: Colors.brown[700]),
                const SizedBox(width: 8),
                const Text(
                  'Detailed Breakdown',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildBreakdownRow('Dry Waste', dryWaste, Colors.orange[700]!),
            const SizedBox(height: 8),
            _buildBreakdownRow('Wet Waste', wetWaste, Colors.blue[700]!),
            const SizedBox(height: 16),
            const Divider(),
            _buildBreakdownRow(
              'Total Waste',
              dryWaste + wetWaste,
              Colors.brown[700]!,
              isTotal: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBreakdownRow(String label, double value, Color color, {bool isTotal = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                fontSize: isTotal ? 16 : 14,
                fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
        Text(
          '${value.toStringAsFixed(2)} kg',
          style: TextStyle(
            fontSize: isTotal ? 16 : 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildEfficiencyTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildEfficiencyMetrics(),
          const SizedBox(height: 16),
          _buildPerformanceIndicators(),
        ],
      ),
    );
  }

  Widget _buildEfficiencyMetrics() {
    final summary = _analyticsData['summary'] ?? {};
    final wastePerLabour = _safeParseDouble(summary['avg_waste_per_labour']);
    final avgDailyWaste = _safeParseDouble(summary['avg_daily_waste']);
    final totalRecords = _safeParseDouble(summary['total_records']);

    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.speed, color: Colors.brown[700]),
                const SizedBox(width: 8),
                const Text(
                  'Efficiency Metrics',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildEfficiencyCard(
                    'Waste per Labour',
                    '${wastePerLabour.toStringAsFixed(2)} kg',
                    Icons.person,
                    Colors.orange,
                    _getEfficiencyColor(wastePerLabour, 1.0), // Good if < 1kg per person
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildEfficiencyCard(
                    'Daily Average',
                    '${avgDailyWaste.toStringAsFixed(1)} kg',
                    Icons.today,
                    Colors.blue,
                    _getEfficiencyColor(avgDailyWaste, 25.0), // Good if < 25kg per day
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildEfficiencyCard(
                    'Data Coverage',
                    '${totalRecords.toInt()} days',
                    Icons.calendar_today,
                    Colors.green,
                    totalRecords >= int.parse(_selectedPeriod) * 0.8 ? Colors.green : Colors.orange,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildEfficiencyCard(
                    'Trend',
                    _calculateTrend(),
                    Icons.trending_up,
                    Colors.purple,
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

  Widget _buildEfficiencyCard(String title, String value, IconData icon, Color iconColor, Color statusColor) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: statusColor,
            ),
            textAlign: TextAlign.center,
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
    );
  }

  Widget _buildPerformanceIndicators() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.assessment, color: Colors.brown[700]),
                const SizedBox(width: 8),
                const Text(
                  'Performance Indicators',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildIndicatorRow('Data Quality', _calculateDataQuality(), Icons.verified),
            _buildIndicatorRow('Waste Management', _calculateWasteManagement(), Icons.recycling),
            _buildIndicatorRow('Labour Efficiency', _calculateLabourEfficiency(), Icons.people),
            _buildIndicatorRow('Environmental Impact', _calculateEnvironmentalImpact(), Icons.eco),
          ],
        ),
      ),
    );
  }

  Widget _buildIndicatorRow(String label, Map<String, dynamic> indicator, IconData icon) {
    final score = indicator['score'] as double;
    final status = indicator['status'] as String;
    final color = indicator['color'] as Color;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    Text(
                      status,
                      style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: score / 100,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                  minHeight: 6,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInsightsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildKeyInsights(),
          const SizedBox(height: 16),
          _buildRecommendations(),
          const SizedBox(height: 16),
          _buildComparisonMetrics(),
        ],
      ),
    );
  }

  Widget _buildKeyInsights() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.lightbulb, color: Colors.brown[700]),
                const SizedBox(width: 8),
                const Text(
                  'Key Insights',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ..._generateInsights().map((insight) => _buildInsightItem(insight)),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightItem(Map<String, dynamic> insight) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            insight['icon'] as IconData,
            color: insight['color'] as Color,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              insight['text'] as String,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecommendations() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.recommend, color: Colors.brown[700]),
                const SizedBox(width: 8),
                const Text(
                  'Recommendations',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ..._generateRecommendations().map((rec) => _buildRecommendationItem(rec)),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendationItem(Map<String, dynamic> recommendation) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: (recommendation['priority'] as Color).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: (recommendation['priority'] as Color).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(
            recommendation['icon'] as IconData,
            color: recommendation['priority'] as Color,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              recommendation['text'] as String,
              style: const TextStyle(fontSize: 14),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: recommendation['priority'] as Color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              recommendation['level'] as String,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComparisonMetrics() {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.compare_arrows, color: Colors.brown[700]),
                const SizedBox(width: 8),
                const Text(
                  'Benchmarking',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildBenchmarkItem('Industry Average', '0.8 kg/labour', _calculateBenchmarkStatus(0.8)),
            _buildBenchmarkItem('Best Practice', '0.6 kg/labour', _calculateBenchmarkStatus(0.6)),
            _buildBenchmarkItem('Previous Period', _getPreviousPeriodData(), Colors.blue),
          ],
        ),
      ),
    );
  }

  Widget _buildBenchmarkItem(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14)),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Text(
              value,
              style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyChart(String message) {
    return Card(
      elevation: 4,
      child: Container(
        height: 200,
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.bar_chart, size: 48, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                message,
                style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem(String title, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          title,
          style: const TextStyle(fontSize: 14),
        ),
      ],
    );
  }

  // Helper methods
  double _safeParseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  Color _getEfficiencyColor(double value, double threshold) {
    if (value <= threshold * 0.8) return Colors.green;
    if (value <= threshold) return Colors.orange;
    return Colors.red;
  }

  String _calculateTrend() {
    if (_recentRecords.length < 2) return 'N/A';
    
    final first = _recentRecords.first.totalWasteGenerated;
    final last = _recentRecords.last.totalWasteGenerated;
    
    if (last > first * 1.1) return 'Rising';
    if (last < first * 0.9) return 'Declining';
    return 'Stable';
  }

  Map<String, dynamic> _calculateDataQuality() {
    final totalPossibleDays = int.parse(_selectedPeriod);
    final actualRecords = _analyticsData['summary']?['total_records'] ?? 0;
    final coverage = (actualRecords / totalPossibleDays * 100).clamp(0, 100);
    
    if (coverage >= 80) return {'score': coverage, 'status': 'Excellent', 'color': Colors.green};
    if (coverage >= 60) return {'score': coverage, 'status': 'Good', 'color': Colors.orange};
    return {'score': coverage, 'status': 'Poor', 'color': Colors.red};
  }

  Map<String, dynamic> _calculateWasteManagement() {
    // Simplified scoring based on disposal methods variety
    final score = 75.0; // Placeholder
    return {'score': score, 'status': 'Good', 'color': Colors.green};
  }

  Map<String, dynamic> _calculateLabourEfficiency() {
    final wastePerLabour = _safeParseDouble(_analyticsData['summary']?['avg_waste_per_labour']);
    final score = (1.5 - wastePerLabour).clamp(0, 1) * 100;
    
    if (score >= 80) return {'score': score, 'status': 'Excellent', 'color': Colors.green};
    if (score >= 60) return {'score': score, 'status': 'Good', 'color': Colors.orange};
    return {'score': score, 'status': 'Needs Improvement', 'color': Colors.red};
  }

  Map<String, dynamic> _calculateEnvironmentalImpact() {
    // Simplified scoring - in real app, this would be more complex
    final score = 70.0;
    return {'score': score, 'status': 'Moderate', 'color': Colors.orange};
  }

  List<Map<String, dynamic>> _generateInsights() {
    final summary = _analyticsData['summary'] ?? {};
    final wastePerLabour = _safeParseDouble(summary['avg_waste_per_labour']);
    final totalWaste = _safeParseDouble(summary['total_waste_generated']);
    
    return [
      if (wastePerLabour > 1.0)
        {
          'icon': Icons.warning,
          'color': Colors.orange,
          'text': 'Waste per labour (${wastePerLabour.toStringAsFixed(2)} kg) is above recommended threshold of 1.0 kg.'
        },
      if (totalWaste > 0)
        {
          'icon': Icons.info,
          'color': Colors.blue,
          'text': 'Total waste generated in selected period: ${totalWaste.toStringAsFixed(1)} kg.'
        },
      {
        'icon': Icons.eco,
        'color': Colors.green,
        'text': 'Consider implementing waste segregation at source to improve recycling rates.'
      },
    ];
  }

  List<Map<String, dynamic>> _generateRecommendations() {
    final summary = _analyticsData['summary'] ?? {};
    final wastePerLabour = _safeParseDouble(summary['avg_waste_per_labour']);
    
    return [
      if (wastePerLabour > 1.0)
        {
          'icon': Icons.reduce_capacity,
          'priority': Colors.red,
          'level': 'HIGH',
          'text': 'Implement waste reduction strategies to bring per-labour waste below 1.0 kg.'
        },
      {
        'icon': Icons.recycling,
        'priority': Colors.orange,
        'level': 'MED',
        'text': 'Set up separate collection points for dry and wet waste to improve sorting efficiency.'
      },
      {
        'icon': Icons.schedule,
        'priority': Colors.blue,
        'level': 'LOW',
        'text': 'Consider daily waste collection to prevent accumulation and improve site hygiene.'
      },
    ];
  }

  Color _calculateBenchmarkStatus(double benchmark) {
    final current = _safeParseDouble(_analyticsData['summary']?['avg_waste_per_labour']);
    if (current <= benchmark) return Colors.green;
    if (current <= benchmark * 1.2) return Colors.orange;
    return Colors.red;
  }

  String _getPreviousPeriodData() {
    // In a real app, this would fetch data from the previous period
    return '0.95 kg/labour';
  }
}

class ConstructionWasteRecord {
  final int id;
  final DateTime date;
  final int approxNoOfLabour;
  final double dryWasteGenerated;
  final double wetWasteGenerated;
  final double totalWasteGenerated;

  ConstructionWasteRecord({
    required this.id,
    required this.date,
    required this.approxNoOfLabour,
    required this.dryWasteGenerated,
    required this.wetWasteGenerated,
    required this.totalWasteGenerated,
  });

  factory ConstructionWasteRecord.fromJson(Map<String, dynamic> json) {
    return ConstructionWasteRecord(
      id: json['id'] ?? 0,
      date: DateTime.parse(json['date'] ?? DateTime.now().toIso8601String()),
      approxNoOfLabour: json['approx_no_of_labour'] ?? 0,
      dryWasteGenerated: double.tryParse(json['dry_waste_generated']?.toString() ?? '0') ?? 0.0,
      wetWasteGenerated: double.tryParse(json['wet_waste_generated']?.toString() ?? '0') ?? 0.0,
      totalWasteGenerated: double.tryParse(json['total_waste_generated']?.toString() ?? '0') ?? 0.0,
    );
  }
}