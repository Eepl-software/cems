import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'dart:math' as math;
import '../services/enhanced_api_service.dart';

/// Enhanced Water Consumption Widget with real-time data and beautiful UI
class EnhancedWaterConsumptionWidget extends StatefulWidget {
  final String title;
  final bool showHeader;
  final bool allowPhaseSelection;
  final double height;
  final EdgeInsets? padding;
  final Function(String phase)? onPhaseChanged;

  const EnhancedWaterConsumptionWidget({
    Key? key,
    this.title = 'Water Consumption',
    this.showHeader = true,
    this.allowPhaseSelection = true,
    this.height = 400,
    this.padding,
    this.onPhaseChanged,
  }) : super(key: key);

  @override
  State<EnhancedWaterConsumptionWidget> createState() => _EnhancedWaterConsumptionWidgetState();
}

class _EnhancedWaterConsumptionWidgetState extends State<EnhancedWaterConsumptionWidget>
    with TickerProviderStateMixin {
  final EnhancedAPIService _apiService = EnhancedAPIService();
  
  // Animation Controllers
  late AnimationController _animationController;
  late AnimationController _chartController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _chartAnimation;

  // Data
  Map<String, dynamic> _dashboardData = {};
  bool _isLoading = true;
  bool _hasError = false;
  String _errorMessage = '';
  String _selectedPhase = 'all';
  int _selectedDays = 7;
  DateTime _lastUpdated = DateTime.now();

  // Chart interaction
  int _touchedIndex = -1;
  bool _showingTooltip = false;

  // Water consumption metrics
  double _todayTotal = 0.0;
  double _weeklyAverage = 0.0;
  double _peakHour = 0.0;
  double _efficiency = 85.0;
  List<String> _activeSources = [];

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _loadData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _chartController.dispose();
    super.dispose();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    
    _chartController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
    ));

    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.2, 1.0, curve: Curves.elasticOut),
    ));

    _chartAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _chartController,
      curve: Curves.easeInOutCubic,
    ));

    _animationController.forward();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final data = await _apiService.getWaterConsumptionDashboard(days: _selectedDays);
      
      if (mounted) {
        setState(() {
          _dashboardData = data;
          _lastUpdated = DateTime.now();
          _calculateMetrics();
          _isLoading = false;
        });
        
        _chartController.forward();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  void _calculateMetrics() {
    final totals = _dashboardData['totals'] as Map<String, dynamic>? ?? {};
    final chartData = _dashboardData['chartData'] as List? ?? [];
    
    // Calculate today's total
    _todayTotal = 0.0;
    for (final key in totals.keys) {
      final value = totals[key];
      if (value is num) {
        _todayTotal += value.toDouble();
      }
    }
    
    // Calculate weekly average
    if (chartData.isNotEmpty) {
      final totalWeekly = chartData.fold<double>(0.0, (sum, item) {
        final consumption = item['consumption'];
        return sum + (consumption is num ? consumption.toDouble() : 0.0);
      });
      _weeklyAverage = totalWeekly / chartData.length;
    }
    
    // Calculate peak hour (simulated)
    _peakHour = _todayTotal * 0.15; // Assume peak is 15% of daily total
    
    // Determine active sources
    _activeSources = totals.entries
        .where((entry) => entry.value is num && (entry.value as num) > 0)
        .map((entry) => entry.key)
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _fadeAnimation,
      builder: (context, child) {
        return Opacity(
          opacity: _fadeAnimation.value,
          child: Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              height: widget.height,
              padding: widget.padding ?? const EdgeInsets.all(16),
              child: Card(
                elevation: 12,
                shadowColor: Colors.blue.withValues(alpha: 0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.blue.shade50,
                        Colors.cyan.shade50,
                        Colors.white,
                      ],
                    ),
                  ),
                  child: _buildContent(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return _buildLoadingState();
    }
    
    if (_hasError) {
      return _buildErrorState();
    }
    
    return Column(
      children: [
        if (widget.showHeader) _buildHeader(),
        Expanded(child: _buildMainContent()),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [Colors.blue.shade400, Colors.cyan.shade400],
              ),
            ),
            child: const CircularProgressIndicator(
              color: Colors.white,
              strokeWidth: 3,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Loading water data...',
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              Icons.water_drop_outlined,
              size: 48,
              color: Colors.red.shade400,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Unable to load water data',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.grey.shade600,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _loadData,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Retry'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue.shade600,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.blue.shade600, Colors.cyan.shade500],
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.water_drop,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.black87,
                      ),
                    ),
                    Text(
                      'Last updated: ${DateFormat('HH:mm').format(_lastUpdated)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              _buildStatusIndicator(),
            ],
          ),
          if (widget.allowPhaseSelection) ...[
            const SizedBox(height: 16),
            _buildPhaseSelector(),
          ],
        ],
      ),
    );
  }

  Widget _buildStatusIndicator() {
    final isHealthy = _activeSources.length >= 2 && _efficiency > 70;
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isHealthy ? Colors.green.shade50 : Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isHealthy ? Colors.green.shade200 : Colors.orange.shade200,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isHealthy ? Colors.green : Colors.orange,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isHealthy ? 'Optimal' : 'Warning',
            style: TextStyle(
              color: isHealthy ? Colors.green.shade700 : Colors.orange.shade700,
              fontSize: 10,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhaseSelector() {
    final phases = ['All', 'Construction', 'Labour Colony', 'Operational'];
    
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: phases.asMap().entries.map((entry) {
          final index = entry.key;
          final phase = entry.value;
          final phaseKey = index == 0 ? 'all' : phase.toLowerCase().replaceAll(' ', '_');
          final isSelected = _selectedPhase == phaseKey;
          
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedPhase = phaseKey;
                });
                widget.onPhaseChanged?.call(phaseKey);
                _loadData();
              },
              child: Container(
                margin: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue.shade600 : Colors.transparent,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Center(
                  child: Text(
                    phase,
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.grey.shade600,
                      fontSize: 10,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildMainContent() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
      child: Column(
        children: [
          _buildMetricsRow(),
          const SizedBox(height: 20),
          Expanded(child: _buildChart()),
        ],
      ),
    );
  }

  Widget _buildMetricsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildMetricCard(
            'Today',
            '${_todayTotal.toStringAsFixed(0)}L',
            Icons.today,
            Colors.blue.shade600,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            'Avg/Day',
            '${_weeklyAverage.toStringAsFixed(0)}L',
            Icons.trending_up,
            Colors.green.shade600,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetricCard(
            'Peak Hour',
            '${_peakHour.toStringAsFixed(0)}L',
            Icons.schedule,
            Colors.orange.shade600,
          ),
        ),
      ],
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: color,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart() {
    final totals = _dashboardData['totals'] as Map<String, dynamic>? ?? {};
    
    if (totals.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.bar_chart_outlined,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 12),
            Text(
              'No consumption data',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }
    
    return AnimatedBuilder(
      animation: _chartAnimation,
      builder: (context, child) {
        return Column(
          children: [
            Expanded(
              flex: 3,
              child: _buildPieChart(totals),
            ),
            const SizedBox(height: 16),
            Expanded(
              flex: 1,
              child: _buildLegend(totals),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPieChart(Map<String, dynamic> totals) {
    final total = totals.values.fold<double>(0.0, (sum, value) {
      return sum + (value is num ? value.toDouble() : 0.0);
    });
    
    if (total <= 0) {
      return Center(
        child: Text(
          'No data to display',
          style: TextStyle(color: Colors.grey.shade600),
        ),
      );
    }
    
    final sections = <PieChartSectionData>[];
    final colors = [
      Colors.blue.shade600,
      Colors.green.shade600,
      Colors.orange.shade600,
      Colors.purple.shade600,
      Colors.red.shade600,
    ];
    
    int colorIndex = 0;
    totals.entries.forEach((entry) {
      final value = entry.value is num ? (entry.value as num).toDouble() : 0.0;
      if (value > 0) {
        final percentage = (value / total * 100);
        final isTouched = sections.length == _touchedIndex;
        
        sections.add(
          PieChartSectionData(
            color: colors[colorIndex % colors.length],
            value: value,
            title: '${percentage.toStringAsFixed(1)}%',
            radius: (isTouched ? 65.0 : 55.0) * _chartAnimation.value,
            titleStyle: TextStyle(
              fontSize: isTouched ? 14 : 12,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
            titlePositionPercentageOffset: 0.6,
          ),
        );
        colorIndex++;
      }
    });
    
    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 35,
        sections: sections,
        pieTouchData: PieTouchData(
          touchCallback: (FlTouchEvent event, pieTouchResponse) {
            setState(() {
              if (!event.isInterestedForInteractions ||
                  pieTouchResponse == null ||
                  pieTouchResponse.touchedSection == null) {
                _touchedIndex = -1;
                return;
              }
              _touchedIndex = pieTouchResponse.touchedSection!.touchedSectionIndex;
            });
          },
        ),
      ),
    );
  }

  Widget _buildLegend(Map<String, dynamic> totals) {
    final colors = [
      Colors.blue.shade600,
      Colors.green.shade600,
      Colors.orange.shade600,
      Colors.purple.shade600,
      Colors.red.shade600,
    ];
    
    final activeEntries = totals.entries
        .where((entry) => entry.value is num && (entry.value as num) > 0)
        .toList();
    
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 16,
      runSpacing: 8,
      children: activeEntries.asMap().entries.map((entry) {
        final index = entry.key;
        final dataEntry = entry.value;
        final color = colors[index % colors.length];
        
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                _formatSourceName(dataEntry.key),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '${(dataEntry.value as num).toStringAsFixed(0)}L',
                style: TextStyle(
                  fontSize: 10,
                  color: color,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _formatSourceName(String source) {
    switch (source.toLowerCase()) {
      case 'borewell':
        return 'Borewell';
      case 'tanker':
        return 'Tanker';
      case 'bwssb':
        return 'BWSSB';
      case 'direct':
        return 'Direct';
      default:
        return source.toUpperCase();
    }
  }
}