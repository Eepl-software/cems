import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';
import 'package:percent_indicator/percent_indicator.dart';
import 'package:animated_text_kit/animated_text_kit.dart';
import 'LabourColonyWastePage.dart';
import 'cnd/CDWasteDetailsPage.dart';
import 'ProjectWastePage.dart';
import 'MunicipalSolidWasteDetailsPage.dart';
import 'utils/ConstructionPhaseWastePage.dart'; 

class SolidWastePage extends StatefulWidget {
  const SolidWastePage({super.key});

  @override
  State<SolidWastePage> createState() => _SolidWastePageState();
}

class _SolidWastePageState extends State<SolidWastePage> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  
  // Data variables (keeping same structure)
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

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _fetchWasteStatistics();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    ));
    
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOutCubic,
    ));
    
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  // Keep all your existing API methods unchanged
  Future<void> _fetchWasteStatistics() async {
    setState(() => _isLoading = true);
    
    try {
      await _fetchMunicipalWasteStats();
      await _fetchConstructionWasteStats();
    } catch (e) {
      print('Error fetching waste statistics: $e');
      _setDefaultWasteData();
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchMunicipalWasteStats() async {
    try {
      const String baseUrl = 'http://54.146.215.18:3000';
      final response = await http.get(
        Uri.http('54.146.215.18:3000', '/municipal-solid-waste/stats'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final summary = data['summary'];
        
        double safeParseDouble(dynamic value) {
          if (value == null) return 0.0;
          if (value is num) {
            final result = value.toDouble();
            return result.isNaN || result.isInfinite ? 0.0 : result;
          }
          final parsed = double.tryParse(value.toString()) ?? 0.0;
          return parsed.isNaN || parsed.isInfinite ? 0.0 : parsed;
        }
        
        setState(() {
          _municipalWasteStats = {
            'totalRecords': safeParseDouble(summary['total_records']),
            'totalWasteGenerated': safeParseDouble(summary['total_waste_generated']),
            'totalWasteDisposed': safeParseDouble(summary['total_waste_disposed']),
            'avgDailyWaste': safeParseDouble(summary['avg_daily_waste']),
            'avgHousesOccupied': safeParseDouble(summary['avg_houses_occupied']),
          };
        });
      }
    } catch (e) {
      print('Error fetching municipal waste stats: $e');
    }
  }

  Future<void> _fetchConstructionWasteStats() async {
    try {
      const String baseUrl = 'http://54.146.215.18:3000';
      final response = await http.get(
        Uri.http('54.146.215.18:3000', '/construction-phase-waste/stats'),
      );
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final summary = data['summary'];
        
        double safeParseDouble(dynamic value) {
          if (value == null) return 0.0;
          if (value is num) {
            final result = value.toDouble();
            return result.isNaN || result.isInfinite ? 0.0 : result;
          }
          final parsed = double.tryParse(value.toString()) ?? 0.0;
          return parsed.isNaN || parsed.isInfinite ? 0.0 : parsed;
        }
        
        setState(() {
          _constructionWasteStats = {
            'totalRecords': safeParseDouble(summary['total_records']),
            'totalWasteGenerated': safeParseDouble(summary['total_waste_generated']),
            'totalDryWaste': safeParseDouble(summary['total_dry_waste']),
            'totalWetWaste': safeParseDouble(summary['total_wet_waste']),
            'avgDailyWaste': safeParseDouble(summary['avg_daily_waste']),
            'avgLabourCount': safeParseDouble(summary['avg_labour_count']),
          };
        });

        final municipalGenerated = _municipalWasteStats['totalWasteGenerated'] ?? 0;
        final municipalDisposed = _municipalWasteStats['totalWasteDisposed'] ?? 0;
        final constructionGenerated = _constructionWasteStats['totalWasteGenerated'] ?? 0;
        
        final totalGenerated = municipalGenerated + constructionGenerated;
        final totalDisposed = municipalDisposed + constructionGenerated;
        
        wasteData = {
          'Total Waste Generated': totalGenerated,
          'Waste Recycled': totalDisposed * 0.6,
          'Waste to Landfill': totalDisposed * 0.1,
          'Waste Composted': totalDisposed * 0.2,
          'Waste to Energy': totalDisposed * 0.1,
        };
      }
    } catch (e) {
      print('Error fetching construction waste stats: $e');
    }
  }

  void _setDefaultWasteData() {
    setState(() {
      wasteData = {
        'Total Waste Generated': 1200,
        'Waste Recycled': 300,
        'Waste to Landfill': 40,
        'Waste Composted': 580,
        'Waste to Energy': 280,
      };
    });
  }

  double _safeProgress(double value, double total) {
    if (total <= 0 || value.isNaN || total.isNaN || value.isInfinite || total.isInfinite) {
      return 0.0;
    }
    final result = value / total;
    return result.isNaN || result.isInfinite ? 0.0 : result.clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FFFE),
      appBar: _buildAppBar(),
      body: _isLoading ? _buildLoadingScreen() : _buildMainContent(),
      floatingActionButton: _buildFAB(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      elevation: 0,
      backgroundColor: Colors.white,
      foregroundColor: const Color(0xFF2D5A5A),
      title: const Text(
        'Waste Management',
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 20,
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh_rounded),
          onPressed: () => _fetchWasteStatistics(),
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildLoadingScreen() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF2D5A5A)),
          ),
          SizedBox(height: 24),
          Text(
            'Loading waste data...',
            style: TextStyle(
              color: Color(0xFF6B7280),
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              _buildHeroSection(),
              _buildStatsOverview(),
              _buildQuickActions(),
              _buildDetailedStats(),
              const SizedBox(height: 100), // Space for FAB
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeroSection() {
    final totalWaste = wasteData['Total Waste Generated'] ?? 0;
    final recycledWaste = wasteData['Waste Recycled'] ?? 0;
    final recyclingRate = totalWaste > 0 ? (recycledWaste / totalWaste * 100) : 0;

    return Container(
      margin: const EdgeInsets.all(20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2D5A5A), Color(0xFF4A7C7D)],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2D5A5A).withOpacity(0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Total Waste',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${totalWaste.toStringAsFixed(1)} kg',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.eco_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.recycling_rounded,
                  color: Colors.green[300],
                  size: 24,
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Recycling Rate',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      '${recyclingRate.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsOverview() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              'Records',
              '${(_municipalWasteStats['totalRecords'] ?? 0).toInt()}',
              Icons.assignment_rounded,
              const Color(0xFF3B82F6),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'Daily Avg',
              '${(_municipalWasteStats['avgDailyWaste'] ?? 0).toStringAsFixed(1)} kg',
              Icons.trending_up_rounded,
              const Color(0xFF10B981),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'Houses',
              '${(_municipalWasteStats['avgHousesOccupied'] ?? 0).toInt()}',
              Icons.home_rounded,
              const Color(0xFFF59E0B),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(
              fontSize: 16,
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
    );
  }

  Widget _buildQuickActions() {
    return Container(
      margin: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Actions',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
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
        'title': 'Construction\nPhase Waste',
        'icon': Icons.construction_rounded,
        'color': const Color(0xFF8B5CF6),
        'onTap': () => _navigateToConstructionPhaseWastePage(context),
      },
      {
        'title': 'Municipal\nSolid Waste',
        'icon': Icons.delete_outline_rounded,
        'color': const Color(0xFF10B981),
        'onTap': () => _navigateToMunicipalSolidWastePage(context),
      },
      {
        'title': 'Construction &\nDemolition',
        'icon': Icons.engineering_rounded,
        'color': const Color(0xFFF59E0B),
        'onTap': () => _navigateToCDWasteDetailsPage(context),
      },
      {
        'title': 'Labour\nColony',
        'icon': Icons.home_work_rounded,
        'color': const Color(0xFF3B82F6),
        'onTap': () => _navigateToLabourColonyPage(context),
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.3,
      ),
      itemCount: actions.length,
      itemBuilder: (context, index) {
        final action = actions[index];
        return _buildActionCard(
          title: action['title'] as String,
          icon: action['icon'] as IconData,
          color: action['color'] as Color,
          onTap: action['onTap'] as VoidCallback,
        );
      },
    );
  }

  Widget _buildActionCard({
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const Spacer(),
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2937),
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailedStats() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Waste Distribution',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 24),
          _buildWasteChart(),
        ],
      ),
    );
  }

  Widget _buildWasteChart() {
    final data = [
      {'label': 'Recycled', 'value': wasteData['Waste Recycled'] ?? 0, 'color': const Color(0xFF10B981)},
      {'label': 'Composted', 'value': wasteData['Waste Composted'] ?? 0, 'color': const Color(0xFFF59E0B)},
      {'label': 'Energy', 'value': wasteData['Waste to Energy'] ?? 0, 'color': const Color(0xFF3B82F6)},
      {'label': 'Landfill', 'value': wasteData['Waste to Landfill'] ?? 0, 'color': const Color(0xFFEF4444)},
    ];

    return Column(
      children: data.map((item) {
        final total = wasteData['Total Waste Generated'] ?? 1;
        final percentage = (item['value'] as double) / total;
        
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: item['color'] as Color,
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        item['label'] as String,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF374151),
                        ),
                      ),
                    ],
                  ),
                  Text(
                    '${(item['value'] as double).toStringAsFixed(1)} kg',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: percentage.isFinite ? percentage : 0,
                backgroundColor: const Color(0xFFF3F4F6),
                valueColor: AlwaysStoppedAnimation<Color>(item['color'] as Color),
                minHeight: 8,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFAB() {
    return FloatingActionButton.extended(
      onPressed: () => _navigateToConstructionPhaseWastePage(context),
      backgroundColor: const Color(0xFF2D5A5A),
      foregroundColor: Colors.white,
      elevation: 8,
      icon: const Icon(Icons.add_rounded),
      label: const Text('Add Entry'),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
    );
  }

  // Keep all your existing navigation methods unchanged
  void _navigateToConstructionPhaseWastePage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ConstructionPhaseWastePage(),
      ),
    ).then((_) => _fetchWasteStatistics());
  }

  void _navigateToMunicipalSolidWastePage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MunicipalSolidWasteDetailsPage(),
      ),
    ).then((_) => _fetchWasteStatistics());
  }

  void _navigateToCDWasteDetailsPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CDWasteDetailsPage(),
      ),
    );
  }

  void _navigateToLabourColonyPage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const LabourColonyPage(),
      ),
    );
  }

  void _navigateToProjectWastePage(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ProjectWastePage(),
      ),
    );
  }
}

  // Keep the original WasteDetailsPage for backward compatibility or other purposes
  void _navigateToWastePage(BuildContext context, String type) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => WasteDetailsPage(wasteType: type),
      ),
    );
  }


// Keep the existing WasteDetailsPage class unchanged for compatibility
class WasteDetailsPage extends StatefulWidget {
  final String wasteType;

  const WasteDetailsPage({super.key, required this.wasteType});

  @override
  State<WasteDetailsPage> createState() => _WasteDetailsPageState();
}

class _WasteDetailsPageState extends State<WasteDetailsPage> {
  // Mock monthly data for chart
  final List<Map<String, dynamic>> monthlyData = [
    {'month': 'Jan', 'waste': 145},
    {'month': 'Feb', 'waste': 132},
    {'month': 'Mar', 'waste': 151},
    {'month': 'Apr', 'waste': 140},
    {'month': 'May', 'waste': 170},
    {'month': 'Jun', 'waste': 160},
  ];
  
  // Mock data for waste statistics
  final Map<String, Map<String, dynamic>> wasteSources = {
    'Labour Colony': {
      'icon': Icons.home,
      'generated': 70,
      'recycled': 45,
    },
    'Project': {
      'icon': Icons.business,
      'generated': 100,
      'recycled': 35,
    },
  };
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${widget.wasteType} Waste Details',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.teal[700],
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.file_download),
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Report download starting...'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.info_outline),
            onPressed: () {
              _showInfoDialog(context);
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.teal[700]!, Colors.teal[200]!],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildWasteTypeHeader(),
                const SizedBox(height: 24),
                
                // Trend Chart
                _buildTrendChart(),
                const SizedBox(height: 24),
                
                // Quick Info Card
                _buildSourcesCard(),
                const SizedBox(height: 24),
                
                // Navigation Buttons
                _buildDetailButton(
                  context: context,
                  title: 'Labour Colony',
                  icon: Icons.home,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const LabourColonyPage(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 16),
                _buildDetailButton(
                  context: context,
                  title: 'Project',
                  icon: Icons.business,
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ProjectWastePage(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 24),
                
                // Statistics Card
                _buildStatisticsCard(),
                
                const SizedBox(height: 24),
                // Action items card
                _buildActionItemsCard(),
              ],
            ),
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (context) => _buildAddEntryBottomSheet(),
          );
        },
        backgroundColor: Colors.teal[700],
        icon: const Icon(Icons.add),
        label: const Text('Add Entry'),
      ),
    );
  }

  Widget _buildWasteTypeHeader() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.teal[300]!, Colors.teal[100]!],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            Icon(
              widget.wasteType == 'MSW' ? Icons.delete_outline : Icons.construction,
              color: Colors.teal[700],
              size: 48.0,
            ),
            const SizedBox(height: 12),
            Text(
              '${widget.wasteType} Waste Management',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.bold,
                color: Colors.teal[900],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Efficient tracking and management',
              style: TextStyle(
                fontSize: 16,
                color: Colors.teal[700],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Last Updated: ${DateFormat('MMM dd, yyyy').format(DateTime.now())}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.teal[800],
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrendChart() {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Monthly Trend',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal[800],
                  ),
                ),
                DropdownButton<String>(
                  value: '6 Months',
                  icon: const Icon(Icons.keyboard_arrow_down),
                  items: ['3 Months', '6 Months', '1 Year'].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {},
                  underline: Container(
                    height: 0,
                  ),
                  style: TextStyle(
                    color: Colors.teal[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: 200,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      tooltipBgColor: Colors.teal.withOpacity(0.8),
                      tooltipPadding: const EdgeInsets.all(8),
                      tooltipMargin: 8,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          '${monthlyData[groupIndex]['month']}: ${rod.toY.round()} tons',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value >= 0 && value < monthlyData.length) {
                            return Text(
                              monthlyData[value.toInt()]['month'],
                              style: const TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            );
                          }
                          return const Text('');
                        },
                        reservedSize: 28,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          return Text(
                            value.toInt().toString(),
                            style: const TextStyle(
                              color: Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          );
                        },
                        reservedSize: 28,
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  borderData: FlBorderData(
                    show: false,
                  ),
                  barGroups: List.generate(
                    monthlyData.length,
                    (index) => BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: monthlyData[index]['waste'].toDouble(),
                          gradient: LinearGradient(
                            colors: [Colors.teal[400]!, Colors.teal[700]!],
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                          ),
                          width: 20,
                          borderRadius: const BorderRadius.only(
                            topLeft: Radius.circular(6),
                            topRight: Radius.circular(6),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSourcesCard() {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Waste Sources',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.teal[800],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildSourceItem(
                    'Labour Colony',
                    Icons.home,
                    '70 Tons',
                    Colors.blue[700]!,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _buildSourceItem(
                    'Project',
                    Icons.business,
                    '100 Tons',
                    Colors.amber[700]!,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildSourceItem(
    String title,
    IconData icon,
    String value,
    Color color,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 36),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildDetailButton({
    required BuildContext context,
    required String title,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return Container(
      decoration: BoxDecoration(
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 24),
        label: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const Icon(Icons.arrow_forward_ios, size: 18),
            ],
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.teal[700],
          padding: const EdgeInsets.symmetric(horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
      ),
    );
  }

  Widget _buildStatisticsCard() {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.white, Colors.teal[50]!],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${widget.wasteType} Waste Statistics',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal[800],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  color: Colors.teal[700],
                  onPressed: () {
                    // Refresh statistics
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Refreshing statistics...'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Total waste with circular progress indicator
            _buildCircularStatistic(
              'Total Waste Generated',
              '170',
              'Tons',
              Colors.teal[700]!,
              0.85,
            ),
            const SizedBox(height: 24),
            
            // Other statistics with linear progress
            _buildStatisticRow('Waste Recycled', '80 Tons', Colors.green[700]!, 0.47),
            _buildStatisticRow('Waste to Landfill', '400 kg', Colors.red[700]!, 0.02),
            _buildStatisticRow('Waste Composted', '50 Tons', Colors.amber[700]!, 0.29),
            _buildStatisticRow('Waste Repurposed', '38 Tons', Colors.blue[700]!, 0.22),
          ],
        ),
      ),
    );
  }
  
  Widget _buildCircularStatistic(
    String label,
    String value,
    String unit,
    Color color,
    double progress,
  ) {
    return Row(
      children: [
        CircularPercentIndicator(
          radius: 60.0,
          lineWidth: 10.0,
          percent: progress,
          center: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                unit,
                style: TextStyle(
                  fontSize: 12,
                  color: color,
                ),
              ),
            ],
          ),
          progressColor: color,
          backgroundColor: Colors.grey[200]!,
          circularStrokeCap: CircularStrokeCap.round,
          animation: true,
          animationDuration: 1200,
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[800],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Target: 200 Tons',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Status: On Track',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.green[700],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStatisticRow(
    String label, 
    String value, 
    Color valueColor,
    double progress,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: valueColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearPercentIndicator(
            lineHeight: 8.0,
            percent: progress,
            backgroundColor: Colors.grey[200],
            progressColor: valueColor,
            barRadius: const Radius.circular(4),
            animation: true,
            animationDuration: 1200,
          ),
        ],
      ),
    );
  }
  
  Widget _buildActionItemsCard() {
    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.assignment_turned_in, color: Colors.teal[700], size: 24),
                const SizedBox(width: 8),
                Text(
                  'Action Items',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildActionItem(
              'Increase recycling rate by 10%',
              DateTime.now().add(const Duration(days: 30)),
              'In Progress',
              Colors.orange,
            ),
            _buildActionItem(
              'Implement waste segregation at all sites',
              DateTime.now().add(const Duration(days: 15)),
              'Pending',
              Colors.red,
            ),
            _buildActionItem(
              'Complete monthly waste audit',
              DateTime.now().add(const Duration(days: 5)),
              'Completed',
              Colors.green,
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildActionItem(
    String task,
    DateTime dueDate,
    String status,
    Color statusColor,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Colors.grey[100],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            task,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Due: ${DateFormat('MMM dd, yyyy').format(dueDate)}',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[700],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: statusColor),
                ),
                child: Text(
                  status,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: statusColor,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildAddEntryBottomSheet() {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (_, controller) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(20),
              topRight: Radius.circular(20),
            ),
          ),
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.all(20),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Add New Waste Entry',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal[800],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Form Fields
              _buildFormField('Source', Icons.source),
              _buildFormField('Waste Type', Icons.category),
              _buildFormField('Quantity (Tons)', Icons.scale),
              _buildFormField('Date', Icons.calendar_today),
              _buildFormField('Notes', Icons.note),
              
              const SizedBox(height: 24),
              
              // Submit Button
              ElevatedButton(
                onPressed: () {
                  // Add entry logic
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Entry added successfully!'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal[700],
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Submit',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildFormField(String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, color: Colors.teal[600]),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[300]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.teal[700]!, width: 2),
          ),
          filled: true,
          fillColor: Colors.grey[50],
        ),
      ),
    );
  }
  
  void _showInfoDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            '${widget.wasteType} Waste Information',
            style: TextStyle(color: Colors.teal[800]),
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'About ${widget.wasteType} Waste',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  widget.wasteType == 'MSW'
                      ? 'Municipal Solid Waste (MSW) consists of everyday items we use and then throw away. It includes product packaging, grass clippings, furniture, clothing, bottles, food scraps, newspapers, and more.'
                      : 'This waste type includes various categories generated from construction and demolition activities.',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 16),
                Text(
                  'Management Guidelines',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                _buildInfoItem('Segregate waste at source'),
                _buildInfoItem('Promote recycling where possible'),
                _buildInfoItem('Ensure proper disposal methods'),
                _buildInfoItem('Maintain accurate records'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Close',
                style: TextStyle(color: Colors.teal[800]),
              ),
            ),
          ],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        );
      },
    );
  }
  
  Widget _buildInfoItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.check_circle, color: Colors.teal[600], size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}