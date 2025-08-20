import 'package:flutter/material.dart';
import 'package:prestige_park_groove/models.dart';
import 'package:prestige_park_groove/admin/superuser_alert_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:prestige_park_groove/login/auth_service.dart';
import 'main.dart';
import 'login/login_page.dart';
import 'airpollution/airpollution.dart';
import 'rain_water.dart';
import 'solid_waste.dart';
import 'solid_waste_enhanced.dart';
import 'ground_water/ground_water.dart';
import 'water_management.dart';
import 'admin/user_management_page.dart';
import 'admin/system_settings_page.dart';
import 'security_settings_page.dart';
import 'admin/notification_settings_page.dart';
import 'admin/language_settings_page.dart';
import 'admin/theme_settings_page.dart';
import 'admin/password_settings_page.dart';
import 'admin/biometric_settings_page.dart';
import 'admin/two_factor_authentication_page.dart';
import 'cement/cement.dart';
import 'sand/sand.dart';
import 'metals/metals.dart';
import 'pipes/pipes.dart';
import 'tiles/tiles.dart';
import 'wood/wood.dart';
import 'electricals/electricals.dart';
import 'plastic/plastic.dart';
import 'aggregates/aggregates.dart';
import 'construction_materials_dashboard.dart';
import 'environmental_protection_page.dart';

class MyHomePage extends StatelessWidget {
  final User user;
  final AuthService authService;

  const MyHomePage({
    Key? key,
    required this.user,
    required this.authService,
  }) : super(key: key);

  Future<void> _openWebsite(String url) async {
    final Uri uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw 'Could not launch $url';
      }
    } catch (e) {
      print('Error launching URL: $e');
    }
  }

  Widget _buildHeroSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF2E7D32), // Forest green
            const Color(0xFF4CAF50), // Material green
            const Color(0xFF66BB6A), // Light green
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2E7D32).withAlpha(77),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          // Main title with animation
          TweenAnimationBuilder(
            duration: const Duration(milliseconds: 800),
            tween: Tween<double>(begin: 0, end: 1),
            curve: Curves.easeOutBack,
            builder: (ctx, double value, child) {
              return Transform.scale(
                scale: 0.8 + (0.2 * value),
                child: Opacity(
                  opacity: value.clamp(0.0, 1.0),
                  child: Column(
                    children: [
                      Icon(
                        Icons.eco,
                        size: 48 * value,
                        color: Colors.white,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Construction and  Environmental',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.2,
                          shadows: [
                            Shadow(
                              color: Colors.black.withAlpha(77),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                      Text(
                        'Management Software',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFFE8F5E8),
                          letterSpacing: 1.5,
                          shadows: [
                            Shadow(
                              color: Colors.black.withAlpha(51),
                              blurRadius: 8,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 20),
          // Subtitle
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(51),
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                color: Colors.white.withAlpha(77),
                width: 1,
              ),
            ),
            child: Text(
              'Sustainable Infrastructure Development Initiative',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.white,
                letterSpacing: 0.8,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdminWelcomeCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                const Color(0xFF4CAF50).withAlpha(26),
                const Color(0xFF2E7D32).withAlpha(13),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1565C0), // Deep blue
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.admin_panel_settings,
                  color: Colors.white,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Welcome, ${user.username}',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Administrator Dashboard Access',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.verified_user,
                color: const Color(0xFF4CAF50),
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainContentSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Card(
        elevation: 12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                const Color(0xFFF8FFF8), // Very light green tint
              ],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.construction,
                    color: const Color(0xFF1565C0), // Deep blue
                    size: 28,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Project Overview',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF1565C0), // Deep blue
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                'Advanced environmental monitoring and management system for sustainable construction projects. Real-time tracking of air quality, water resources, waste management, and material usage.',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[700],
                  height: 1.6,
                  letterSpacing: 0.5,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _buildFeatureChip('Real-time Monitoring', Icons.analytics),
                  _buildFeatureChip('Data Analytics', Icons.bar_chart),
                  _buildFeatureChip('Compliance Tracking', Icons.verified),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureChip(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1565C0).withAlpha(26), // Deep blue background
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF1565C0).withAlpha(77),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: const Color(0xFF1565C0), // Deep blue
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1565C0),
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEnhancedPartnersSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Card(
        elevation: 16,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white,
                const Color(0xFFF8F9FF), // Very light blue-white
                const Color(0xFFF3E5F5), // Very light purple
              ],
              stops: const [0.0, 0.6, 1.0],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              // Enhanced header with animation
              TweenAnimationBuilder(
                duration: const Duration(milliseconds: 800),
                tween: Tween<double>(begin: 0, end: 1),
                curve: Curves.easeOutBack,
                builder: (ctx, double value, child) {
                  return Transform.scale(
                    scale: (0.8 + (0.2 * value)).clamp(0.1, 2.0),
                    child: Opacity(
                      opacity: value.clamp(0.0, 1.0),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF7B1FA2).withAlpha(26),
                              const Color(0xFF1565C0).withAlpha(26),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(25),
                          border: Border.all(
                            color: const Color(0xFF7B1FA2).withAlpha(77),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFF7B1FA2),
                                    const Color(0xFF9C27B0),
                                  ],
                                ),
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFF7B1FA2).withAlpha(77),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.handshake_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Column(
                              children: [
                                Text(
                                  'Strategic Partners',
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.bold,
                                    color: const Color(0xFF1565C0),
                                    letterSpacing: 0.5,
                                  ),
                                ),
                                Text(
                                  'Excellence in Collaboration',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: const Color(0xFF7B1FA2),
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 12),
              Text(
                'Collaborative excellence in sustainable construction and environmental innovation',
                style: TextStyle(
                  fontSize: 15,
                  color: Colors.grey[700],
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              // Enhanced partner grid
              _buildPartnerGrid(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPartnerGrid() {
    final partners = [
      {
        'name': 'Kalpar',
        'asset': 'assets/Kalpar_logo.png',
        'url': 'https://g.co/kgs/qUjubQb',
        'description': 'Technology Solutions',
        'color': const Color(0xFF1565C0),
      },
      {
        'name': 'IISc',
        'asset': 'assets/iisc_logo.png',
        'url': 'https://www.iisc.ac.in/',
        'description': 'Research Excellence',
        'color': const Color(0xFF7B1FA2),
      },
      {
        'name': 'L&T',
        'asset': 'assets/LT.png',
        'url': 'https://www.larsentoubro.com/',
        'description': 'Engineering Expertise',
        'color': const Color(0xFF1976D2),
      },
      {
        'name': 'Prestige',
        'asset': 'assets/prestige_logo.png',
        'url': 'https://www.prestigeconstructions.com/',
        'description': 'Construction Leadership',
        'color': const Color(0xFF9C27B0),
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 1.25, 
      ),
      itemCount: partners.length,
      itemBuilder: (context, index) {
        final partner = partners[index];
        return _buildEnhancedPartnerCard(partner, index);
      },
    );
  }

  Widget _buildEnvironmentalProtectionSection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.green.shade600,
                Colors.green.shade700,
              ],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.eco,
                    color: Colors.white,
                    size: 32,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Environmental Protection',
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Our comprehensive environmental protection measures ensure sustainable construction practices',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white.withOpacity(0.9),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 3,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1,
                children: [
                  _buildEnvironmentalFeature(
                    'Dust Control',
                    Icons.air,
                    Colors.blue.shade100,
                    Colors.blue.shade700,
                  ),
                  _buildEnvironmentalFeature(
                    'Water Management',
                    Icons.water_drop,
                    Colors.cyan.shade100,
                    Colors.cyan.shade700,
                  ),
                  _buildEnvironmentalFeature(
                    'Waste Recycling',
                    Icons.recycling,
                    Colors.green.shade100,
                    Colors.green.shade700,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const EnvironmentalProtectionPage(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.green.shade700,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 4,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'View All Measures',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.arrow_forward),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEnvironmentalFeature(String label, IconData icon, Color bgColor, Color iconColor) {
    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            color: iconColor,
            size: 28,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: iconColor,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsSection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      child: Card(
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF7B1FA2), // Deep purple
                const Color(0xFF9C27B0), // Material purple
              ],
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Text(
                'Quick Actions',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const EnhancedApprovalsPage(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF7B1FA2), // Deep purple
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 4,
                  ),
                  icon: const Icon(Icons.approval_rounded, size: 24),
                  label: const Text(
                    'Environmental Approvals',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
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

  Widget _buildEnhancedPartnerCard(Map<String, dynamic> partner, int index) {
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 800 + (index * 200)),
      tween: Tween(begin: 0, end: 1),
      curve: Curves.elasticOut,
      builder: (context, value, child) {
        return Transform.scale(
          scale: (0.8 + (0.2 * value)).clamp(0.1, 2.0),
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: Opacity(
              opacity: value.clamp(0.0, 1.0),
              child: GestureDetector(
                onTap: () => _openWebsite(partner['url']),
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white,
                        (partner['color'] as Color).withAlpha(13),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: (partner['color'] as Color).withAlpha(26),
                        blurRadius: 20,
                        spreadRadius: 2,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: Colors.white.withAlpha(128),
                        blurRadius: 8,
                        spreadRadius: -2,
                        offset: const Offset(0, -4),
                      ),
                    ],
                    border: Border.all(
                      color: (partner['color'] as Color).withAlpha(51),
                      width: 1.5,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16), // Reduced padding
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min, // Added to prevent overflow
                      children: [
                        // Logo container with enhanced styling
                        Flexible(
                          child: Container(
                            width: 70, // Reduced size
                            height: 70, // Reduced size
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.white,
                                  (partner['color'] as Color).withAlpha(26),
                                ],
                              ),
                              borderRadius: BorderRadius.circular(14), // Slightly reduced
                              boxShadow: [
                                BoxShadow(
                                  color: (partner['color'] as Color).withAlpha(77),
                                  blurRadius: 10, // Reduced blur
                                  spreadRadius: 1,
                                  offset: const Offset(0, 3), // Reduced offset
                                ),
                              ],
                              border: Border.all(
                                color: (partner['color'] as Color).withAlpha(77),
                                width: 1.5, // Reduced border width
                              ),
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                padding: const EdgeInsets.all(6), // Reduced padding
                                child: Image.asset(
                                  partner['asset'],
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8), // Reduced spacing
                        // Partner name with enhanced styling
                        Text(
                          partner['name'],
                          style: TextStyle(
                            fontSize: 15, // Slightly reduced
                            fontWeight: FontWeight.bold,
                            color: partner['color'] as Color,
                            letterSpacing: 0.5,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3), // Reduced spacing
                        // Partner description
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3), // Reduced padding
                          decoration: BoxDecoration(
                            color: (partner['color'] as Color).withAlpha(26),
                            borderRadius: BorderRadius.circular(10), // Slightly reduced
                          ),
                          child: Text(
                            partner['description'],
                            style: TextStyle(
                              fontSize: 10, // Slightly reduced
                              fontWeight: FontWeight.w600,
                              color: partner['color'] as Color,
                              letterSpacing: 0.3,
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(user.role == UserRole.superuser ? 'Admin Dashboard' : ''),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        actions: user.role == UserRole.superuser ? [
          IconButton(
            icon: const Icon(Icons.admin_panel_settings),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Admin Controls'),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.people),
                        title: const Text('User Management'),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => UserManagementPage()),
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.settings),
                        title: const Text('System Settings'),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => SystemSettingsPage()),
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.security),
                        title: const Text('Security Settings'),
                        onTap: () {
                          Navigator.pop(context);
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => SecuritySettingsPage()),
                          );
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ] : null,
      ),
      drawer: CustomDrawer(user: user, authService: authService),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0xFFE8F5E8), // Very light green
              Colors.white,
              const Color(0xFFF0F9FF), // Very light blue
            ],
            stops: const [0.0, 0.7, 1.0],
          ),
        ),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(
            children: [
              _buildHeroSection(),
              if (user.role == UserRole.superuser)
                _buildAdminWelcomeCard(),
              _buildMainContentSection(),
              _buildEnhancedPartnersSection(),
              _buildEnvironmentalProtectionSection(context),
              _buildQuickActionsSection(context),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }
}

class CustomDrawer extends StatefulWidget {
  final User user;
  final AuthService authService;

  const CustomDrawer({
    Key? key,
    required this.user,
    required this.authService,
  }) : super(key: key);

  @override
  State<CustomDrawer> createState() => _CustomDrawerState();
}

class _CustomDrawerState extends State<CustomDrawer> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  
  // Professional color scheme
  final Color primaryColor = const Color(0xFF2E7D32);    // Forest green
  final Color accentColor = const Color(0xFF4CAF50);     // Material green
  final Color highlightColor = const Color(0xFF00BCD4);  // Cyan accent
  final Color backgroundColor = const Color(0xFFFAFAFA); // Off white
  final Color cardColor = Colors.white;
  final Color textPrimaryColor = const Color(0xFF263238); // Blue grey dark
  final Color textSecondaryColor = const Color(0xFF607D8B); // Blue grey

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              backgroundColor,
              backgroundColor.withAlpha(230),
            ],
          ),
        ),
        child: Column(
          children: [
            _buildAnimatedHeader(),
            Expanded(
              child: ListView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
            if (widget.user.role == UserRole.superuser) ...[
              _buildAnimatedDrawerItem(
                title: 'Home',
                icon: Icons.home_rounded,
                onTap: () => Navigator.pushReplacement(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => 
                      MyHomePage(user: widget.user, authService: widget.authService),
                    transitionsBuilder: _buildTransition,
                  ),
                ),
              ),
              _buildExpandableDrawerItem(
                title: 'Admin',
                icon: Icons.admin_panel_settings,
                children: _buildAdminItems(),
              ),
            ],
            
            _buildExpandableDrawerItem(
              title: 'Environmental',
              icon: Icons.eco_rounded,
              children: _buildEnvironmentalItems(),
            ),
            
            _buildAnimatedDrawerItem(
              title: 'Approvals',
              icon: Icons.approval_rounded,
              onTap: () => _navigateWithAnimation(const EnhancedApprovalsPage()),
            ),

            _buildAnimatedDrawerItem(
              title: 'Post Alert Message',
              icon: Icons.notifications_active,
              onTap: () => _navigateWithAnimation(SuperuserAlertPage()),
            ),

            _buildAnimatedDrawerItem(
              title: 'Contact us',
              icon: Icons.contact_page_rounded,
              onTap: () => _navigateWithAnimation(
                const BlankPage(message: 'Contact us'),
              ),
            ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                height: 1,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      accentColor.withAlpha(77),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            _buildAnimatedDrawerItem(
              title: 'Settings',
              icon: Icons.settings_rounded,
              onTap: () {},
            ),

            _buildAnimatedDrawerItem(
              title: 'Logout',
              icon: Icons.logout_rounded,
              onTap: () => _showLogoutDialog(),
              color: const Color(0xFFF44336), // Material red
            ),

                  const SizedBox(height: 16),
                  _buildInteractivePartnerLogos(),
                  _buildVersionNumber(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedHeader() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primaryColor,
            accentColor,
            const Color(0xFF66BB6A), // Light green
          ],
          stops: const [0.0, 0.6, 1.0],
        ),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withAlpha(77),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
          child: Column(
            children: [
              // Animated logo container
              Hero(
                tag: 'app_logo',
                child: TweenAnimationBuilder(
                  duration: const Duration(milliseconds: 800),
                  tween: Tween<double>(begin: 0, end: 1),
                  curve: Curves.elasticOut,
                  builder: (ctx, double value, child) {
                    return Transform.scale(
                      scale: value,
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: highlightColor.withAlpha(102),
                              blurRadius: 20,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Image.asset(
                            'assets/LT.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              // Animated title
              TweenAnimationBuilder(
                duration: const Duration(milliseconds: 600),
                tween: Tween<double>(begin: 0, end: 1),
                curve: Curves.easeInOut,
                builder: (ctx, double value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 20 * (1 - value)),
                      child: Column(
                        children: [
                          Text(
                            'Sustainable Infra',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withAlpha(51),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            'Development',
                            style: TextStyle(
                              color: const Color(0xFFE8F5E8), // Very light green
                              fontSize: 18,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 1.5,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withAlpha(51),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 8),
              // Partner logos section with hover effect
              TweenAnimationBuilder(
                duration: const Duration(milliseconds: 1000),
                tween: Tween<double>(begin: 0, end: 1),
                curve: Curves.easeOutBack,
                builder: (ctx, double value, child) {
                  return Transform.scale(
                    scale: 0.8 + (0.2 * value),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.white.withAlpha(38),
                            Colors.white.withAlpha(51),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(
                          color: const Color(0xFF81C784).withAlpha(102), // Light green border
                          width: 1.5,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: accentColor.withAlpha(77),
                            blurRadius: 10,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.business,
                            color: const Color(0xFFE8F5E8), // Light green icon
                            size: 16,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'IISC • L&T • Kalpar • Prestige',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                              shadows: [
                                Shadow(
                                  color: Colors.black.withAlpha(77),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInteractivePartnerLogos() {
    final partners = [
      {'name': 'IISC', 'icon': Icons.school, 'color': const Color(0xFF2196F3)}, // Material blue
      {'name': 'L&T', 'icon': Icons.construction, 'color': const Color(0xFFFF9800)}, // Material orange
      {'name': 'Kalpar', 'icon': Icons.business, 'color': primaryColor}, // Use primary green
      {'name': 'Prestige', 'icon': Icons.apartment, 'color': highlightColor}, // Use cyan
    ];

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cardColor,
            cardColor.withAlpha(230),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withAlpha(26),
            blurRadius: 10,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.handshake, color: primaryColor, size: 20),
              const SizedBox(width: 8),
              Text(
                'Our Partners',
                style: TextStyle(
                  color: primaryColor,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: partners.map((partner) {
              return TweenAnimationBuilder<double>(
                duration: const Duration(milliseconds: 800),
                tween: Tween(begin: 0, end: 1),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: (partner['color'] as Color).withAlpha(26),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: partner['color'] as Color,
                              width: 2,
                            ),
                          ),
                          child: Icon(
                            partner['icon'] as IconData,
                            color: partner['color'] as Color,
                            size: 20,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          partner['name'] as String,
                          style: TextStyle(
                            color: textSecondaryColor,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedDrawerItem({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
  }) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 200),
      tween: Tween(begin: 0.0, end: 1.0),
      builder: (context, value, child) {
        return Transform.scale(
          scale: 0.95 + (0.05 * value),
          child: Opacity(
            opacity: value,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Material(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                elevation: 2 * value,
                shadowColor: Colors.black.withAlpha(51),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onTap,
                  onTapDown: (_) {},
                  splashColor: (color ?? primaryColor).withAlpha(51),
                  highlightColor: (color ?? primaryColor).withAlpha(26),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: (color ?? primaryColor).withAlpha(26),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            icon, 
                            color: color ?? primaryColor,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            title,
                            style: TextStyle(
                              color: textPrimaryColor,
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: (color ?? primaryColor).withAlpha(13),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.arrow_forward_ios,
                            color: color ?? primaryColor,
                            size: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildExpandableDrawerItem({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Theme(
        data: Theme.of(context).copyWith(
          dividerColor: Colors.transparent,
        ),
        child: Material(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          elevation: 2,
          shadowColor: Colors.black.withAlpha(51),
          child: ExpansionTile(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: primaryColor.withAlpha(26),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: primaryColor, size: 22),
            ),
            title: Text(
              title,
              style: TextStyle(
                color: textPrimaryColor,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            iconColor: primaryColor,
            collapsedIconColor: textSecondaryColor,
            backgroundColor: Colors.transparent,
            children: children.map((child) => 
              Padding(
                padding: const EdgeInsets.only(left: 16, right: 8, bottom: 4),
                child: child,
              )
            ).toList(),
          ),
        ),
      ),
    );
  }

  Widget _buildSubDrawerItem({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          splashColor: primaryColor.withAlpha(26),
          highlightColor: primaryColor.withAlpha(13),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: primaryColor.withAlpha(13),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    icon, 
                    color: primaryColor, 
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      color: textPrimaryColor.withAlpha(204),
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: textSecondaryColor,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildVersionNumber() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: primaryColor.withAlpha(26),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: primaryColor.withAlpha(51),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.info_outline,
            size: 14,
            color: primaryColor,
          ),
          const SizedBox(width: 6),
          Text(
            'Version 1.0.1',
            style: TextStyle(
              color: primaryColor,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateWithAnimation(Widget page) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => page,
        transitionsBuilder: _buildTransition,
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  Widget _buildTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    const begin = Offset(1.0, 0.0);
    const end = Offset.zero;
    const curve = Curves.easeInOutCubic;
    
    var tween = Tween(begin: begin, end: end).chain(CurveTween(curve: curve));
    var offsetAnimation = animation.drive(tween);
    
    return SlideTransition(position: offsetAnimation, child: child);
  }

    void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: backgroundColor,
        title: Row(
          children: [
            Icon(Icons.logout, color: highlightColor),
            const SizedBox(width: 10),
            Text(
              'Logout',
              style: TextStyle(color: highlightColor),
            ),
          ],
        ),
        content: Text(
          'Are you sure you want to logout?',
          style: TextStyle(color: textPrimaryColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'CANCEL',
              style: TextStyle(color: accentColor),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context); // Close dialog
              
              // Show loading indicator
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(highlightColor),
                  ),
                ),
              );
              
              widget.authService.logout();
              
              if (!mounted) return;
              
              // Close loading indicator and navigate
              Navigator.of(context).pop();
              Navigator.of(context).pushAndRemoveUntil(
                MaterialPageRoute(
                  builder: (context) => EnhancedLoginPage(authService: widget.authService)
                ),
                (route) => false
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: highlightColor,
              foregroundColor: backgroundColor,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text(
              'LOGOUT',
              style: TextStyle(
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  List<Widget> _buildAdminItems() {
    return [
      _buildSubDrawerItem(
        title: 'User Management',
        icon: Icons.people,
        onTap: () {
          Navigator.pop(context);
          _navigateWithAnimation(UserManagementPage());
        },
      ),
      _buildSubDrawerItem(
        title: 'System Settings',
        icon: Icons.settings,
        onTap: () {
          Navigator.pop(context);
          _navigateWithAnimation(SystemSettingsPage());
        },
      ),
      _buildSubDrawerItem(
        title: 'Security Settings',
        icon: Icons.security,
        onTap: () {
          Navigator.pop(context);
          _navigateWithAnimation(SecuritySettingsPage());
        },
      ),
      _buildSubDrawerItem(
        title: 'Notification Settings',
        icon: Icons.notifications,
        onTap: () {
          Navigator.pop(context);
          _navigateWithAnimation(NotificationSettingsPage());
        },
      ),
      _buildSubDrawerItem(
        title: 'Language Settings',
        icon: Icons.language,
        onTap: () {
          Navigator.pop(context);
          _navigateWithAnimation(LanguageSettingsPage());
        },
      ),
      _buildSubDrawerItem(
        title: 'Theme Settings',
        icon: Icons.dark_mode,
        onTap: () {
          Navigator.pop(context);
          _navigateWithAnimation(ThemeSettingsPage());
        },
      ),
      _buildSubDrawerItem(
        title: 'Password Settings',
        icon: Icons.lock,
        onTap: () {
          Navigator.pop(context);
          _navigateWithAnimation(PasswordSettingsPage());
        },
      ),
      _buildSubDrawerItem(
  title: 'Biometric Settings',
  icon: Icons.fingerprint,
  onTap: () {
    Navigator.pop(context);
    _navigateWithAnimation(BiometricSettingsPage(authService: widget.authService));
  },
),
      _buildSubDrawerItem(
        title: 'Two-Factor Authentication',
        icon: Icons.security_update_good,
        onTap: () {
          Navigator.pop(context);
          _navigateWithAnimation(TwoFactorAuthenticationPage());
        },
      ),
    ];
  }

  List<Widget> _buildEnvironmentalItems() {
    return [
      _buildSubDrawerItem(
        title: 'Construction Materials Dashboard',
        icon: Icons.dashboard_rounded,
        onTap: () {
          Navigator.pop(context);
          _navigateWithAnimation(const ConstructionMaterialsDashboard());
        },
      ),
      const Divider(),
      _buildSubDrawerItem(
        title: 'Water Management',
        icon: Icons.water_drop_rounded,
        onTap: () {
          Navigator.pop(context);
          _navigateWithAnimation(EnhancedWaterConsumptionPage(authService: widget.authService));
        },
      ),
      _buildSubDrawerItem(
        title: 'Air Pollution Management',
        icon: Icons.air_rounded,
        onTap: () {
          Navigator.pop(context);
          _navigateWithAnimation(const AirPollutionMonitoringPage());
        },
      ),
      _buildSubDrawerItem(
        title: 'Solid Waste Management',
        icon: Icons.delete_rounded,
        onTap: () {
          Navigator.pop(context);
          _navigateWithAnimation(const SolidWastePageEnhanced());
        },
      ),
      _buildSubDrawerItem(
        title: 'Rain Water Harvesting',
        icon: Icons.water_damage_rounded,
        onTap: () {
          Navigator.pop(context);
          _navigateWithAnimation(RainWaterPage());
        },
      ),
      _buildSubDrawerItem(
        title: 'Ground Water Data',
        icon: Icons.opacity_rounded,
        onTap: () {
          Navigator.pop(context);
          _navigateWithAnimation(GroundWaterPage());
        },
      ),
      _buildSubDrawerItem(
        title: 'Cement Management',
        icon: Icons.construction_rounded,
        onTap: () {
          Navigator.pop(context);
          _navigateWithAnimation(const CementPage());
        },
      ),
      _buildSubDrawerItem(
        title: 'Sand Management',
        icon: Icons.agriculture_rounded,
        onTap: () {
          Navigator.pop(context);
          _navigateWithAnimation(const SandPage());
        },
      ),
      _buildSubDrawerItem(
        title: 'Metals Management',
        icon: Icons.construction_rounded,
        onTap: () {
          Navigator.pop(context);
          _navigateWithAnimation(const MetalsPage());
        },
      ),
      _buildSubDrawerItem(
        title: 'Pipes Management',
        icon: Icons.plumbing_rounded,
        onTap: () {
          Navigator.pop(context);
          _navigateWithAnimation(const PipesPage());
        },
      ),
      _buildSubDrawerItem(
        title: 'Tiles Management',
        icon: Icons.grid_view_rounded,
        onTap: () {
          Navigator.pop(context);
          _navigateWithAnimation(const TilesPage());
        },
      ),
      _buildSubDrawerItem(
        title: 'Wood Management',
        icon: Icons.park_rounded,
        onTap: () {
          Navigator.pop(context);
          _navigateWithAnimation(const WoodPage());
        },
      ),
      _buildSubDrawerItem(
        title: 'Electricals Management',
        icon: Icons.electrical_services_rounded,
        onTap: () {
          Navigator.pop(context);
          _navigateWithAnimation(const ElectricalsPage());
        },
      ),
      _buildSubDrawerItem(
        title: 'Plastic Management',
        icon: Icons.recycling_rounded,
        onTap: () {
          Navigator.pop(context);
          _navigateWithAnimation(const PlasticPage());
        },
      ),
      _buildSubDrawerItem(
        title: 'Aggregates Management',
        icon: Icons.grain_rounded,
        onTap: () {
          Navigator.pop(context);
          _navigateWithAnimation(const AggregatesPage());
        },
      ),
    ];
  }
}