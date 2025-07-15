import 'package:flutter/material.dart';
import 'package:namer_app/models.dart';
import 'package:namer_app/admin/superuser_alert_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:namer_app/auth_service.dart';
import 'main.dart';
import 'login/login_page.dart';
import 'airpollution/airpollution.dart';
import 'rain_water.dart';
import 'solid_waste.dart';
import 'ground_water.dart';
import 'water_management.dart';
import 'models.dart';
import 'admin/user_management_page.dart';
import 'admin/system_settings_page.dart';
import 'security_settings_page.dart';
import 'admin/notification_settings_page.dart';
import 'admin/language_settings_page.dart';
import 'admin/theme_settings_page.dart';
import 'admin/password_settings_page.dart';
import 'admin/biometric_settings_page.dart';
import 'admin/two_factor_authentication_page.dart';
import 'macos_pdf_viewer.dart';
import 'cement.dart';

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

  Widget _buildPartnerLogo(String assetPath, String url) {
    return GestureDetector(
      onTap: () => _openWebsite(url),
      child: Image.asset(
        assetPath,
        width: 100,
        height: 100,
      ),
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
            colors: [Colors.teal.shade50, Colors.white],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              if (user.role == UserRole.superuser)
                Card(
                  elevation: 5,
                  color: Colors.teal.shade100,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        const Icon(Icons.admin_panel_settings, color: Colors.teal),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Welcome, ${user.username}',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Text('You have full administrative access'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              Card(
                elevation: 5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text(
                        'Sustainable Infrastructure Development',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'A joint initiative for sustainable construction',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.black54,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              Card(
                elevation: 5,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Text(
                        'Our Partners',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.teal,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _buildPartnerLogo(
                            'assets/IISC_logo.jpeg',
                            'https://www.iisc.ac.in/',
                          ),
                          _buildPartnerLogo(
                            'assets/L&T.png',
                            'https://www.iisc.ac.in/',
                          ),
                          _buildPartnerLogo(
                            'assets/Kalpar logo.png',
                            'https://g.co/kgs/qUjubQb',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const EnhancedApprovalsPage(),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.teal,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    elevation: 5,
                  ),
                  child: const Text(
                    'Approvals',
                    style: TextStyle(
                      fontSize: 20,
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
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
  
  final Color primaryColor = const Color(0xFF2D3250);  // Deep blue-grey
  final Color accentColor = const Color(0xFF7077A1);   // Dusty blue
  final Color highlightColor = const Color(0xFFF6B17A); // Warm orange
  final Color backgroundColor = const Color(0xFF424769); // Dark blue-grey

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
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
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [primaryColor, backgroundColor],
          ),
        ),
        child: ListView(
          physics: const BouncingScrollPhysics(),
          children: [
            _buildAnimatedHeader(),
            const SizedBox(height: 8),
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
              child: Divider(color: accentColor.withOpacity(0.3)),
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
              color: const Color(0xFFFF6B6B),
            ),

            const SizedBox(height: 16),
            _buildVersionNumber(),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedHeader() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: 180,
      decoration: BoxDecoration(
        color: primaryColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder(
            duration: const Duration(milliseconds: 500),
            tween: Tween<double>(begin: 0, end: 1),
            builder: (context, double value, child) {
              return Transform.scale(
                scale: value,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: highlightColor, width: 2),
                  ),
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: Colors.white,
                    child: Image.asset(
                      'assets/FoxCon Logo.png',
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 12),
          Text(
            'Sustainable Infra Development',
            style: TextStyle(
              color: highlightColor,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
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
    return TweenAnimationBuilder(
      duration: const Duration(milliseconds: 200),
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, double value, child) {
        return Transform.scale(
          scale: 0.95 + (0.05 * value),
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              color: Colors.transparent,
            ),
            child: ListTile(
              leading: Icon(icon, color: color ?? Colors.white),
              title: Text(
                title,
                style: TextStyle(
                  color: color ?? Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
              onTap: onTap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              hoverColor: accentColor.withOpacity(0.1),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
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
  return Theme(
    data: Theme.of(context).copyWith(
      dividerColor: Colors.transparent,
    ),
    child: ExpansionTile(
      leading: Icon(icon, color: Colors.white),
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w500,
        ),
      ),
      iconColor: highlightColor,
      collapsedIconColor: Colors.white,
      backgroundColor: accentColor.withOpacity(0.1),
      collapsedBackgroundColor: Colors.transparent,
      children: children,
    ),
  );
}

  Widget _buildSubDrawerItem({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70, size: 20),
      title: Text(
        title,
        style: TextStyle(
          color: Colors.white.withOpacity(0.9),
          fontSize: 14,
          fontWeight: FontWeight.w400,
        ),
      ),
      onTap: onTap,
      contentPadding: const EdgeInsets.only(left: 32, right: 16),
      dense: true,
      hoverColor: accentColor.withOpacity(0.1),
    );
  }

  Widget _buildVersionNumber() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        'Version 1.0.1',
        style: TextStyle(
          color: Colors.white.withOpacity(0.5),
          fontSize: 12,
          fontWeight: FontWeight.w400,
        ),
        textAlign: TextAlign.center,
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
        content: const Text(
          'Are you sure you want to logout?',
          style: TextStyle(color: Colors.white),
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
          _navigateWithAnimation(const SolidWastePage());
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
    ];
  }
}