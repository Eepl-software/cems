import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';

class EnhancedWaterConsumptionWidget extends StatefulWidget {
  final String title;
  final bool showControls;
  final Function()? onRefresh;
  final Function()? onFilter;
  
  const EnhancedWaterConsumptionWidget({
    Key? key,
    this.title = 'Water Consumption',
    this.showControls = true,
    this.onRefresh,
    this.onFilter,
  }) : super(key: key);

  @override
  _EnhancedWaterConsumptionWidgetState createState() => _EnhancedWaterConsumptionWidgetState();
}

class _EnhancedWaterConsumptionWidgetState extends State<EnhancedWaterConsumptionWidget> {
  List<Map<String, dynamic>> _consumptionData = [];
  Map<String, dynamic> _dashboardData = {};
  bool _isLoading = true;
  String _errorMessage = '';
  Timer? _refreshTimer;
  DateTime? _lastUpdated;

  static const String baseUrl = 'http://54.146.215.18:3000';

  @override
  void initState() {
    super.initState();
    _fetchData();
    _startAutoRefresh();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) {
        _fetchData(silent: true);
      }
    });
  }

  Future<void> _fetchData({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = '';
      });
    }

    try {
      // Fetch dashboard data
      final dashboardResponse = await http.get(
        Uri.http('54.146.215.18:3000', '/water-consumption/dashboard', {'days': '7'}),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 10));

      if (dashboardResponse.statusCode == 200) {
        final dashboardJson = json.decode(dashboardResponse.body);
        if (dashboardJson['success'] == true) {
          setState(() {
            _dashboardData = dashboardJson['data'];
            _lastUpdated = DateTime.now();
          });
        }
      }

      // Convert chart data to consumption data format for backward compatibility
      if (_dashboardData['chartData'] != null) {
        final chartData = _dashboardData['chartData'] as List;
        final consumptionData = <Map<String, dynamic>>[];

        // Group by date and aggregate
        Map<String, double> dailyTotals = {};
        for (var item in chartData) {
          final date = item['date'];
          final consumption = double.tryParse(item['consumption'].toString()) ?? 0.0;
          dailyTotals[date] = (dailyTotals[date] ?? 0.0) + consumption;
        }

        // Convert to the expected format
        dailyTotals.forEach((date, consumption) {
          consumptionData.add({
            'date': date,
            'water_consumed': consumption,
            'source': 'Mixed Sources'
          });
        });

        setState(() {
          _consumptionData = consumptionData;
        });
      }

    } catch (e) {
      print('Error fetching water consumption data: $e');
      if (!silent) {
        setState(() {
          _errorMessage = 'Failed to load data: ${e.toString()}';
        });
      }
    } finally {
      if (!silent) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          if (_isLoading) 
            _buildLoadingIndicator()
          else if (_errorMessage.isNotEmpty)
            _buildErrorIndicator()
          else ...[
            _buildStatistics(),
            _buildChart(),
            _buildSourceBreakdown(),
          ],
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.teal.shade400, Colors.teal.shade600],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.water_drop, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                  if (_lastUpdated != null)
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 12,
                          color: Colors.grey[600],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Updated: ${DateFormat('HH:mm').format(_lastUpdated!)}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: const BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ],
          ),
          if (widget.showControls)
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.teal),
                  onPressed: () {
                    _fetchData();
                    widget.onRefresh?.call();
                  },
                  tooltip: 'Refresh data',
                ),
                if (widget.onFilter != null)
                  IconButton(
                    icon: const Icon(Icons.filter_list, color: Colors.teal),
                    onPressed: widget.onFilter,
                    tooltip: 'Filter data',
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator() {
    return Container(
      height: 200,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          CircularProgressIndicator(),
          SizedBox(height: 16),
          Text('Loading consumption data...'),
        ],
      ),
    );
  }

  Widget _buildErrorIndicator() {
    return Container(
      height: 200,
      alignment: Alignment.center,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 48, color: Colors.red),
          const SizedBox(height: 16),
          Text(
            _errorMessage,
            style: const TextStyle(color: Colors.red),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _fetchData,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatistics() {
    if (_dashboardData['totals'] == null) {
      return Container();
    }

    final totals = _dashboardData['totals'];
    final totalBorewell = double.tryParse(totals['total_borewell']?.toString() ?? '0') ?? 0.0;
    final totalBwssb = double.tryParse(totals['total_bwssb']?.toString() ?? '0') ?? 0.0;
    final totalLabourColony = double.tryParse(totals['total_labour_colony']?.toString() ?? '0') ?? 0.0;
    final totalTankerCapacity = double.tryParse(totals['total_tanker_capacity']?.toString() ?? '0') ?? 0.0;

    final grandTotal = totalBorewell + totalBwssb + totalLabourColony;
    final average = _consumptionData.isNotEmpty ? grandTotal / _consumptionData.length : 0.0;
    final maxValue = _consumptionData.isEmpty ? 0.0 : _consumptionData
        .map((item) => double.tryParse(item['water_consumed']?.toString() ?? '0') ?? 0.0)
        .reduce((a, b) => a > b ? a : b);

    final formatter = NumberFormat('#,##0.00');

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatItem(
            'Total',
            '${formatter.format(grandTotal)} L',
            Icons.water,
            Colors.blue,
          ),
          _buildStatItem(
            'Average',
            '${formatter.format(average)} L/day',
            Icons.show_chart,
            Colors.orange,
          ),
          _buildStatItem(
            'Peak',
            '${formatter.format(maxValue)} L',
            Icons.trending_up,
            Colors.red,
          ),
          _buildStatItem(
            'Sources',
            '${_getActiveSourcesCount()}',
            Icons.source,
            Colors.green,
          ),
        ],
      ),
    );
  }

  int _getActiveSourcesCount() {
    if (_dashboardData['totals'] == null) return 0;
    
    final totals = _dashboardData['totals'];
    int count = 0;
    
    if ((double.tryParse(totals['total_borewell']?.toString() ?? '0') ?? 0.0) > 0) count++;
    if ((double.tryParse(totals['total_bwssb']?.toString() ?? '0') ?? 0.0) > 0) count++;
    if ((double.tryParse(totals['total_labour_colony']?.toString() ?? '0') ?? 0.0) > 0) count++;
    
    return count;
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildChart() {
    if (_consumptionData.isEmpty) {
      return Container(
        height: 150,
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.bar_chart_outlined, size: 48, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No consumption data available',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Container(
      height: 180,
      padding: const EdgeInsets.only(right: 16, left: 0, top: 8, bottom: 12),
      child: LineChart(
        LineChartData(
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: _getChartInterval(),
            getDrawingHorizontalLine: (value) {
              return FlLine(
                color: Colors.grey.shade200,
                strokeWidth: 1,
              );
            },
          ),
          titlesData: FlTitlesData(
            show: true,
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 30,
                getTitlesWidget: (value, meta) {
                  final int index = value.toInt();
                  if (index >= 0 && index < _consumptionData.length && index % 2 == 0) {
                    final date = DateTime.parse(_consumptionData[index]['date']);
                    return Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: Text(
                        DateFormat('MM/dd').format(date),
                        style: const TextStyle(
                          color: Colors.grey,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    );
                  }
                  return const SizedBox();
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  return Text(
                    _formatChartValue(value),
                    style: const TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                    textAlign: TextAlign.center,
                  );
                },
                reservedSize: 35,
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
            border: const Border(
              bottom: BorderSide(color: Colors.grey, width: 1),
              left: BorderSide(color: Colors.grey, width: 1),
            ),
          ),
          minX: 0,
          maxX: (_consumptionData.length - 1).toDouble(),
          minY: 0,
          maxY: _getMaxY(),
          lineBarsData: [
            LineChartBarData(
              spots: _createSpots(),
              isCurved: true,
              gradient: LinearGradient(
                colors: [Colors.teal.shade400, Colors.teal.shade700],
              ),
              barWidth: 3,
              isStrokeCapRound: true,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, barData, index) {
                  return FlDotCirclePainter(
                    radius: 4,
                    color: Colors.teal.shade700,
                    strokeWidth: 2,
                    strokeColor: Colors.white,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  colors: [
                    Colors.teal.shade200.withOpacity(0.5),
                    Colors.teal.shade200.withOpacity(0.0),
                  ],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
            ),
          ],
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              tooltipBgColor: Colors.teal.withOpacity(0.9),
              getTooltipItems: (List<LineBarSpot> touchedBarSpots) {
                return touchedBarSpots.map((barSpot) {
                  final index = barSpot.x.toInt();
                  if (index >= 0 && index < _consumptionData.length) {
                    final item = _consumptionData[index];
                    final date = DateTime.parse(item['date']);
                    return LineTooltipItem(
                      '${DateFormat('dd MMM').format(date)}\n${barSpot.y.toStringAsFixed(1)} L',
                      const TextStyle(color: Colors.white, fontSize: 12),
                    );
                  }
                  return null;
                }).toList();
              },
            ),
          ),
        ),
      ),
    );
  }

  String _formatChartValue(double value) {
    if (value >= 1000000) {
      return '${(value / 1000000).toStringAsFixed(1)}M';
    } else if (value >= 1000) {
      return '${(value / 1000).toStringAsFixed(1)}K';
    } else {
      return value.toInt().toString();
    }
  }

  double _getChartInterval() {
    final maxValue = _getMaxY();
    if (maxValue <= 100) return 20;
    if (maxValue <= 1000) return 200;
    if (maxValue <= 10000) return 2000;
    return maxValue / 5;
  }

  Widget _buildSourceBreakdown() {
    if (_dashboardData['totals'] == null) {
      return Container();
    }

    final totals = _dashboardData['totals'];
    final sources = [
      {
        'name': 'Borewell',
        'value': double.tryParse(totals['total_borewell']?.toString() ?? '0') ?? 0.0,
        'color': Colors.blue,
        'icon': Icons.water_drop,
      },
      {
        'name': 'BWSSB',
        'value': double.tryParse(totals['total_bwssb']?.toString() ?? '0') ?? 0.0,
        'color': Colors.green,
        'icon': Icons.water,
      },
      {
        'name': 'Labour Colony',
        'value': double.tryParse(totals['total_labour_colony']?.toString() ?? '0') ?? 0.0,
        'color': Colors.orange,
        'icon': Icons.home_work,
      },
    ];

    final totalValue = sources.fold(0.0, (sum, source) => sum + (source['value'] as double));

    if (totalValue == 0) {
      return Container();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Source Breakdown',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.teal,
            ),
          ),
          const SizedBox(height: 12),
          ...sources.where((source) => (source['value'] as double) > 0).map((source) {
            final percentage = ((source['value'] as double) / totalValue * 100);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    source['icon'] as IconData,
                    color: source['color'] as Color,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              source['name'] as String,
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                            ),
                            Text(
                              '${percentage.toStringAsFixed(1)}%',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        LinearProgressIndicator(
                          value: percentage / 100,
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(source['color'] as Color),
                          minHeight: 4,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ],
      ),
    );
  }

  List<FlSpot> _createSpots() {
    return List.generate(_consumptionData.length, (index) {
      return FlSpot(
        index.toDouble(),
        double.tryParse(_consumptionData[index]['water_consumed']?.toString() ?? '0') ?? 0,
      );
    });
  }

  double _getMaxY() {
    if (_consumptionData.isEmpty) return 10;
    double maxValue = _consumptionData.fold(
      0,
      (max, item) {
        final value = double.tryParse(item['water_consumed']?.toString() ?? '0') ?? 0;
        return value > max ? value : max;
      },
    );
    return (maxValue * 1.2).ceilToDouble(); // Add 20% padding
  }
}