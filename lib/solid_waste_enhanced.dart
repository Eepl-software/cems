import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:shimmer/shimmer.dart';
import 'dart:async';
import 'dart:math' as math;
import 'LabourColonyWastePage.dart';
import 'cnd/CDWasteDetailsPage.dart';
import 'MunicipalSolidWasteDetailsPage.dart';
import 'utils/ConstructionPhaseWastePage.dart';

class SolidWastePageEnhanced extends StatefulWidget {
  const SolidWastePageEnhanced({super.key});

  @override
  State<SolidWastePageEnhanced> createState() => _SolidWastePageEnhancedState();
}

class _SolidWastePageEnhancedState extends State<SolidWastePageEnhanced> 
    with TickerProviderStateMixin {
  // Animation Controllers
  late AnimationController _animationController;
  late AnimationController _chartAnimationController;
  late AnimationController _pulseAnimationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _chartAnimation;
  late Animation<double> _pulseAnimation;
  
  // Data variables
  Map<String, double> wasteData = {
    'Total Waste Generated': 0,
    'Waste Recycled': 0,
    'Waste to Landfill': 0,
    'Waste Composted': 0,
    'Waste to Energy': 0,
  };

  bool _isLoading = false;
  Map<String, double> _municipalWasteStats = {};
  Map<String, double> _constructionWasteStats = {};
  List<Map<String, dynamic>> _recentActivities = [];
  List<Map<String, dynamic>> _weeklyTrends = [];
  Map<String, double> _wasteGoals = {
    'recyclingTarget': 75.0,
    'landfillReduction': 20.0,
    'compostingTarget': 60.0,
  };
  
  Timer? _refreshTimer;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _fetchWasteStatistics();
    _startAutoRefresh();
    _generateMockData();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _chartAnimationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    
    _pulseAnimationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat(reverse: true);
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
    ));
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.3, 0.8, curve: Curves.easeOutCubic),
    ));
    
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.5, 1.0, curve: Curves.elasticOut),
    ));
    
    _chartAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _chartAnimationController,
      curve: Curves.easeInOutCubic,
    ));
    
    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(CurvedAnimation(
      parent: _pulseAnimationController,
      curve: Curves.easeInOut,
    ));
    
    _animationController.forward();
    _chartAnimationController.forward();
  }

  void _startAutoRefresh() {
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      if (mounted) {
        _fetchWasteStatistics();
      }
    });
  }

  void _generateMockData() {
    final now = DateTime.now();
    _weeklyTrends = List.generate(7, (index) {
      final date = now.subtract(Duration(days: 6 - index));
      return {
        'date': date,
        'total': 150 + math.Random().nextDouble() * 50,
        'recycled': 60 + math.Random().nextDouble() * 30,
        'landfill': 10 + math.Random().nextDouble() * 10,
      };
    });
    
    _recentActivities = [
      {
        'type': 'collection',
        'message': 'Waste collection completed in Block A',
        'time': DateTime.now().subtract(const Duration(minutes: 30)),
        'icon': Icons.delete_sweep,
        'color': Colors.green,
      },
      {
        'type': 'alert',
        'message': 'High contamination detected in recycling bin B12',
        'time': DateTime.now().subtract(const Duration(hours: 1)),
        'icon': Icons.warning,
        'color': Colors.orange,
      },
      {
        'type': 'achievement',
        'message': 'Recycling target achieved for this week!',
        'time': DateTime.now().subtract(const Duration(hours: 2)),
        'icon': Icons.emoji_events,
        'color': Colors.blue,
      },
    ];
  }

  @override
  void dispose() {
    _animationController.dispose();
    _chartAnimationController.dispose();
    _pulseAnimationController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchWasteStatistics() async {
    if (!mounted) return;
    
    setState(() => _isLoading = true);
    
    try {
      await Future.wait([
        _fetchMunicipalWasteStats(),
        _fetchConstructionWasteStats(),
      ]);
      if (mounted) {
        _calculateTotalWasteData();
      }
    } catch (e) {
      print('Error fetching waste statistics: $e');
      if (mounted) {
        _setDefaultWasteData();
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchMunicipalWasteStats() async {
    try {
      final response = await http.get(
        Uri.http('54.146.215.18:3000', '/municipal-solid-waste/stats'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final summary = data['summary'];
        
        setState(() {
          _municipalWasteStats = {
            'totalRecords': _safeParseDouble(summary['total_records']),
            'totalWasteGenerated': _safeParseDouble(summary['total_waste_generated']),
            'totalWasteDisposed': _safeParseDouble(summary['total_waste_disposed']),
            'avgDailyWaste': _safeParseDouble(summary['avg_daily_waste']),
            'avgHousesOccupied': _safeParseDouble(summary['avg_houses_occupied']),
          };
        });
      }
    } catch (e) {
      print('Error fetching municipal waste stats: $e');
    }
  }

  Future<void> _fetchConstructionWasteStats() async {
    try {
      final response = await http.get(
        Uri.http('54.146.215.18:3000', '/construction-phase-waste/stats'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final summary = data['summary'];
        
        setState(() {
          _constructionWasteStats = {
            'totalRecords': _safeParseDouble(summary['total_records']),
            'totalWasteGenerated': _safeParseDouble(summary['total_waste_generated']),
            'totalDryWaste': _safeParseDouble(summary['total_dry_waste']),
            'totalWetWaste': _safeParseDouble(summary['total_wet_waste']),
            'avgDailyWaste': _safeParseDouble(summary['avg_daily_waste']),
            'avgLabourCount': _safeParseDouble(summary['avg_labour_count']),
          };
        });
      }
    } catch (e) {
      print('Error fetching construction waste stats: $e');
    }
  }

  void _calculateTotalWasteData() {
    final municipalGenerated = _municipalWasteStats['totalWasteGenerated'] ?? 0;
    final municipalDisposed = _municipalWasteStats['totalWasteDisposed'] ?? 0;
    final constructionGenerated = _constructionWasteStats['totalWasteGenerated'] ?? 0;
    
    final totalGenerated = municipalGenerated + constructionGenerated;
    final totalDisposed = municipalDisposed + constructionGenerated;
    
    setState(() {
      if (totalGenerated > 0) {
        wasteData = {
          'Total Waste Generated': totalGenerated,
          'Waste Recycled': totalDisposed * 0.6,
          'Waste to Landfill': totalDisposed * 0.1,
          'Waste Composted': totalDisposed * 0.2,
          'Waste to Energy': totalDisposed * 0.1,
        };
      } else {
        _setDefaultWasteData();
      }
    });
  }

  double _safeParseDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) {
      final result = value.toDouble();
      return result.isNaN || result.isInfinite ? 0.0 : result;
    }
    final parsed = double.tryParse(value.toString()) ?? 0.0;
    return parsed.isNaN || parsed.isInfinite ? 0.0 : parsed;
  }

  void _setDefaultWasteData() {
    setState(() {
      wasteData = {
        'Total Waste Generated': 1200,
        'Waste Recycled': 720,
        'Waste to Landfill': 120,
        'Waste Composted': 240,
        'Waste to Energy': 120,
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: const Color(0xFFF0F4F8),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildSliverAppBar(),
          SliverToBoxAdapter(
            child: _isLoading ? _buildShimmerLoading() : _buildMainContent(),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _fetchWasteStatistics,
        backgroundColor: const Color(0xFF2D5A5A),
        child: const Icon(Icons.refresh, color: Colors.white),
      ),
    );
  }

  Widget _buildSliverAppBar() {
    return SliverAppBar(
      expandedHeight: 200,
      floating: false,
      pinned: true,
      elevation: 0,
      backgroundColor: const Color(0xFF2D5A5A),
      flexibleSpace: FlexibleSpaceBar(
        title: const Text(
          'Waste Management',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF2D5A5A),
                const Color(0xFF4A7C7D).withOpacity(0.8),
              ],
            ),
          ),
          child: Stack(
            children: [
              Positioned(
                right: -50,
                top: -50,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.1),
                  ),
                ),
              ),
              Positioned(
                left: -30,
                bottom: -30,
                child: Container(
                  width: 150,
                  height: 150,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.05),
                  ),
                ),
              ),
              Center(
                child: Icon(
                  Icons.eco_rounded,
                  size: 80,
                  color: Colors.white.withOpacity(0.2),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShimmerLoading() {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: List.generate(3, (index) => _buildShimmerCard()),
      ),
    );
  }

  Widget _buildShimmerCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      child: Shimmer.fromColors(
        baseColor: Colors.grey[300]!,
        highlightColor: Colors.grey[100]!,
        child: Container(
          height: 150,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Column(
        children: [
          _buildLiveStatusCard(),
          _buildMetricsOverview(),
          _buildQuickActions(),
          const SizedBox(height: 100),
        ],
      ),
    );
  }

  Widget _buildLiveStatusCard() {
    final totalWaste = wasteData['Total Waste Generated'] ?? 0;
    final recycledWaste = wasteData['Waste Recycled'] ?? 0;
    final recyclingRate = totalWaste > 0 ? (recycledWaste / totalWaste * 100) : 0;

    return Container(
      margin: const EdgeInsets.all(20),
      child: SlideTransition(
        position: _slideAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF2D5A5A),
                  const Color(0xFF4A7C7D),
                ],
              ),
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF2D5A5A).withOpacity(0.3),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            ScaleTransition(
                              scale: _pulseAnimation,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.greenAccent,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.greenAccent.withOpacity(0.8),
                                      blurRadius: 8,
                                      spreadRadius: 2,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              'LIVE STATUS',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 500),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 36,
                            fontWeight: FontWeight.bold,
                          ),
                          child: Text('${totalWaste.toStringAsFixed(1)} kg'),
                        ),
                        const Text(
                          'Total Waste Today',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(
                      width: 120,
                      height: 120,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CircularPercentIndicator(
                            radius: 60,
                            lineWidth: 8,
                            percent: recyclingRate / 100,
                            center: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${recyclingRate.toStringAsFixed(1)}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const Text(
                                  'Recycled',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            progressColor: Colors.greenAccent,
                            backgroundColor: Colors.white.withOpacity(0.2),
                            circularStrokeCap: CircularStrokeCap.round,
                            animation: true,
                            animationDuration: 2000,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetricsOverview() {
    return Container(
      height: 120,
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        children: [
          _buildMetricCard(
            'Municipal',
            '${(_municipalWasteStats['totalWasteGenerated'] ?? 0).toStringAsFixed(1)} kg',
            Icons.location_city,
            const Color(0xFF3B82F6),
            () => _safeNavigateToMunicipalSolidWastePage(),
          ),
          _buildMetricCard(
            'Construction',
            '${(_constructionWasteStats['totalWasteGenerated'] ?? 0).toStringAsFixed(1)} kg',
            Icons.construction,
            const Color(0xFF10B981),
            () => _safeNavigateToConstructionPhaseWastePage(),
          ),
          _buildMetricCard(
            'Daily Average',
            '${((_municipalWasteStats['avgDailyWaste'] ?? 0) + (_constructionWasteStats['avgDailyWaste'] ?? 0)).toStringAsFixed(1)} kg',
            Icons.trending_up,
            const Color(0xFFF59E0B),
            null,
          ),
          _buildMetricCard(
            'Active Sites',
            '${(_municipalWasteStats['totalRecords'] ?? 0).toInt()}',
            Icons.dashboard,
            const Color(0xFF8B5CF6),
            null,
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard(String title, String value, IconData icon, Color color, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 150,
        margin: const EdgeInsets.only(right: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const Spacer(),
            Text(
              value,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Color(0xFF1F2937),
              ),
            ),
            Text(
              title,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF6B7280),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Container(
      margin: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Waste Categories',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1F2937),
                ),
              ),
              TextButton(
                onPressed: () {},
                child: const Text('View All'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildActionGrid(),
        ],
      ),
    );
  }

  Widget _buildActionGrid() {
    final actions = [
      {
        'title': 'Construction\nPhase',
        'icon': Icons.construction_rounded,
        'color': const Color(0xFF8B5CF6),
        'value': '${(_constructionWasteStats['totalRecords'] ?? 0).toInt()} entries',
        'onTap': () => _safeNavigateToConstructionPhaseWastePage(),
      },
      {
        'title': 'Municipal\nSolid',
        'icon': Icons.delete_outline_rounded,
        'color': const Color(0xFF10B981),
        'value': '${(_municipalWasteStats['totalRecords'] ?? 0).toInt()} entries',
        'onTap': () => _safeNavigateToMunicipalSolidWastePage(),
      },
      {
        'title': 'C&D\nWaste',
        'icon': Icons.engineering_rounded,
        'color': const Color(0xFFF59E0B),
        'value': 'Track debris',
        'onTap': () => _safeNavigateToCDWasteDetailsPage(),
      },
      {
        'title': 'Labour\nColony',
        'icon': Icons.home_work_rounded,
        'color': const Color(0xFF3B82F6),
        'value': 'Monitor waste',
        'onTap': () => _safeNavigateToLabourColonyPage(),
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.2,
      ),
      itemCount: actions.length,
      itemBuilder: (context, index) {
        final action = actions[index];
        return _buildEnhancedActionCard(
          title: action['title'] as String,
          icon: action['icon'] as IconData,
          color: action['color'] as Color,
          value: action['value'] as String,
          onTap: action['onTap'] as VoidCallback,
        );
      },
    );
  }

  Widget _buildEnhancedActionCard({
    required String title,
    required IconData icon,
    required Color color,
    required String value,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Colors.white,
              color.withOpacity(0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
              color: color.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                Icon(
                  Icons.arrow_forward_ios,
                  color: color.withOpacity(0.5),
                  size: 16,
                ),
              ],
            ),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
                height: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Safe navigation methods with mounted checks
  void _safeNavigateToConstructionPhaseWastePage() {
    if (!mounted) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ConstructionPhaseWastePage(),
      ),
    ).then((_) {
      if (mounted) {
        _fetchWasteStatistics();
      }
    }).catchError((error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Navigation error: $error')),
        );
      }
    });
  }

  void _safeNavigateToMunicipalSolidWastePage() {
    if (!mounted) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MunicipalSolidWasteDetailsPage(),
      ),
    ).then((_) {
      if (mounted) {
        _fetchWasteStatistics();
      }
    }).catchError((error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Navigation error: $error')),
        );
      }
    });
  }

  void _safeNavigateToCDWasteDetailsPage() {
    if (!mounted) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CDWasteDetailsPage(),
      ),
    ).catchError((error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Navigation error: $error')),
        );
      }
    });
  }

  void _safeNavigateToLabourColonyPage() {
    if (!mounted) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const LabourColonyPage(),
      ),
    ).catchError((error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Navigation error: $error')),
        );
      }
    });
  }
}