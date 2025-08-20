import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:prestige_park_groove/admin/biometric_auth_page.dart';
import 'package:prestige_park_groove/services/admin_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'auth_service.dart';
import '../registration/registration_page.dart';
import 'dart:math' as math;
import '../home_page.dart';
import '../models.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../admin/admin_page.dart';
import '../services/biometric_auth_service.dart';
import '../widgets/biometric_login_widget.dart';
import '../utils/secure_storage.dart';

class EnhancedLoginPage extends StatefulWidget {
  final AuthService authService;

  const EnhancedLoginPage({
    Key? key,
    required this.authService,
  }) : super(key: key);

  @override
  State<EnhancedLoginPage> createState() => _EnhancedLoginPageState();
}

class _EnhancedLoginPageState extends State<EnhancedLoginPage>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _adminPasswordController = TextEditingController();
  
  late AnimationController _animationController;
  late AnimationController _shakeController;
  late Animation<double> _fadeAnimation;
  late Animation<double> _scaleAnimation;
  late Animation<double> _shakeAnimation;
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureAdminPassword = true;
  bool _isAdminLogin = false;
  String? _errorMessage;
  
  // Enhanced biometric authentication
  final BiometricAuthService _biometricService = BiometricAuthService();
  bool _isBiometricAvailable = false;
  List<BiometricType> _availableBiometrics = [];
  
  // Super user credentials (from original login page)
  static const String _superUsername = 'thanush';
  static const String _superPassword = 'thanush04';
  
  // Admin credentials
  static const String _adminUsername = 'thanush_admin';
  static const String _adminPassword = 'thanush';

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _checkBiometricSupport();
  }

  Widget _buildFeatureHighlights() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildFeatureItem(Icons.eco, 'Eco-Friendly'),
          _buildFeatureItem(Icons.security, 'Secure'),
          _buildFeatureItem(Icons.analytics, 'Analytics'),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(IconData icon, String label) {
    return Column(
      children: [
        Icon(
          icon,
          color: Colors.white.withValues(alpha: 0.9),
          size: 24,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.8),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildStatisticsSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.15),
            Colors.white.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          Text(
            'SYSTEM OVERVIEW',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatItem('Active Users', '248', Icons.people),
              _buildStatItem('Projects', '12', Icons.folder_special),
              _buildStatItem('Reports', '1.2K', Icons.assessment),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Colors.green.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.check_circle,
                  color: Colors.white.withValues(alpha: 0.9),
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  'System Status: Online',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            color: Colors.white.withValues(alpha: 0.8),
            size: 20,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    
    _scaleAnimation = Tween<double>(
      begin: 0.5,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.elasticOut,
    ));
    
    _shakeAnimation = Tween<double>(
      begin: -5.0,
      end: 5.0,
    ).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.elasticInOut,
    ));
    
    _animationController.forward();
  }

  Future<void> _checkBiometricSupport() async {
    try {
      bool canCheckBiometrics = await _biometricService.isBiometricAvailable();
      bool isBiometricEnabled = await _biometricService.isBiometricEnabled();
      _availableBiometrics = await _biometricService.getAvailableBiometrics();
      
      setState(() {
        _isBiometricAvailable = canCheckBiometrics && isBiometricEnabled && _availableBiometrics.isNotEmpty;
      });
    } catch (e) {
      debugPrint('Error checking biometric support: $e');
      setState(() {
        _isBiometricAvailable = false;
      });
    }
  }

  Future<void> _handleBiometricLogin() async {
    if (_isAdminLogin) {
      _showErrorSnackBar('Biometric login is not available for admin accounts');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _biometricService.authenticateWithBiometrics();
      
      if (result.success && result.userId != null) {
        _usernameController.text = result.userId!;
        
        // For the super user, auto-fill password and login
        if (result.userId == _superUsername) {
          _passwordController.text = _superPassword;
          _handleLogin();
        } else {
          // For regular users, proceed with login
          _handleLogin();
        }
        
        _showSuccessSnackBar('✅ Biometric authentication successful');
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = result.message;
        });
        _showErrorSnackBar(result.message);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error during biometric authentication: $e';
      });
      _showErrorSnackBar('Biometric authentication error: $e');
    }
  }

  UserRole _checkUserRole(String username, String password) {
    if (username == _superUsername && password == _superPassword) {
      return UserRole.superuser;
    }
    return UserRole.user;
  }

  @override
  void dispose() {
    _animationController.dispose();
    _shakeController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _adminPasswordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    FocusScope.of(context).unfocus();
    
    if (!_formKey.currentState!.validate()) {
      _triggerShakeAnimation();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_isAdminLogin) {
        await _handleAdminLogin();
      } else {
        await _handleRegularLogin();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection error. Please check your internet and try again.';
      });
      _triggerShakeAnimation();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleRegularLogin() async {
    try {
      final response = await widget.authService.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );

      if (!mounted) return;

      if (response.success) {
        // Save token to SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        if (response.token != null) {
          await prefs.setString('auth_token', response.token!);
        }
        // Check if biometric login is enabled and save credentials
        bool isBiometricEnabled = await _biometricService.isBiometricEnabled();
        
        if (isBiometricEnabled) {
          await widget.authService.saveCredentialsForBiometric(_usernameController.text.trim());
        } else {
          // Offer to enable biometric authentication after successful login
          bool biometricAvailable = await _biometricService.isBiometricAvailable();
          if (biometricAvailable) {
            _offerBiometricSetup();
          }
        }

        _showSuccessAnimation();
        
        // Navigate to regular user home page
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => MyHomePage(
                  user: User(
                    id: 1,
                    username: _usernameController.text,
                    email: '',
                    phone: '',
                    company: '',
                    designation: 'user',
                    role: _checkUserRole(_usernameController.text, _passwordController.text),
                  ),
                  authService: widget.authService,
                ),
              ),
            );
          }
        });
      } else {
        setState(() {
          _errorMessage = response.message ?? 'Login failed. Please check your credentials.';
        });
        _triggerShakeAnimation();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection error. Please check your internet and try again.';
      });
      _triggerShakeAnimation();
    }
  }

  Future<void> _handleAdminLogin() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final adminPassword = _adminPasswordController.text;

    // Validate input fields
    if (username.isEmpty || password.isEmpty || adminPassword.isEmpty) {
      setState(() {
        _errorMessage = 'All fields are required for admin login';
      });
      _triggerShakeAnimation();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // Call the backend admin login API
      final response = await AdminService.adminLogin(
        username: username,
        password: password,
        adminPassword: adminPassword,
      );

      if (response.success) {
        _showSuccessAnimation();

        // Navigate to admin dashboard
        Future.delayed(const Duration(milliseconds: 1500), () {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => EnhancedAdminPage(
                  adminToken: response.token!,
                  adminUsername: response.admin?.username ?? username,
                ),
              ),
            );
          }
        });
      } else {
        setState(() {
          _errorMessage = response.message ?? 'Admin login failed. Please check your credentials.';
        });
        _triggerShakeAnimation();
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Connection error. Please check your internet and try again.';
      });
      _triggerShakeAnimation();
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _triggerShakeAnimation() {
    _shakeController.forward().then((_) {
      _shakeController.reverse();
    });
  }

  void _showSuccessAnimation() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder(
                duration: const Duration(milliseconds: 1000),
                tween: Tween<double>(begin: 0, end: 1),
                builder: (context, double value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.check,
                        color: Colors.white,
                        size: 40,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              Text(
                _isAdminLogin ? 'Admin Login Successful!' : 'Login Successful!',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Text('Redirecting to dashboard...'),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openWebsite(String url) async {
    final Uri uri = Uri.parse(url);
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        _showErrorSnackBar('Could not open $url');
      }
    } catch (e) {
      _showErrorSnackBar('Error opening website: $e');
    }
  }

  Widget _buildHeader() {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      child: Column(
        children: [
          // Logo Section with Project Info
          Card(
            elevation: 8,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(15),
            ),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white,
                    Colors.grey.shade50,
                  ],
                ),
              ),
              child: Column(
                children: [
                  Hero(
                    tag: 'logo',
                    child: GestureDetector(
                      onTap: () => _openWebsite('https://www.prestigeconstructions.com'),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _isAdminLogin ? Colors.red.shade50 : Colors.teal.shade50,
                          boxShadow: [
                            BoxShadow(
                              color: (_isAdminLogin ? Colors.red : Colors.teal).withValues(alpha: 0.2),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Image.asset(
                          'assets/prestige_logo.png',
                          height: 70,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              height: 70,
                              width: 70,
                              decoration: BoxDecoration(
                                color: _isAdminLogin ? Colors.red.shade100 : Colors.teal.shade100,
                                borderRadius: BorderRadius.circular(35),
                              ),
                              child: Icon(
                                Icons.business,
                                color: _isAdminLogin ? Colors.red.shade700 : Colors.teal.shade700,
                                size: 35,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'PRESTIGE PARK GROOVE',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      _buildLogoButton(
                        'assets/LT.png',
                        'https://www.larsentoubro.com',
                        'L&T',
                      ),
                      Container(
                        height: 40,
                        width: 1,
                        color: Colors.grey.shade300,
                      ),
                      _buildLogoButton(
                        'assets/iisc_logo.png',
                        'https://www.iisc.ac.in',
                        'IISC',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          // Title Section
          Text(
            'Sustainable Infrastructure',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.5,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.4),
                  offset: const Offset(0, 3),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Construction & Environmental Management System',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withValues(alpha: 0.95),
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.3),
                width: 1,
              ),
            ),
            child: Text(
              _isAdminLogin ? '🔐 Admin Access Portal' : '👤 Sign in to your account',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 20),
          // Feature highlights
          _buildFeatureHighlights(),
        ],
      ),
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        );
      },
    );
  }

  Widget _buildLogoButton(String asset, String url, String name) {
    return Material(
      elevation: 4,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: () => _openWebsite(url),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            children: [
              Image.asset(
                asset, 
                height: 40, 
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    height: 40,
                    width: 40,
                    color: Colors.grey.shade200,
                    child: Icon(Icons.image, color: Colors.grey.shade400),
                  );
                },
              ),
              const SizedBox(height: 8),
              Text(
                name,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: Colors.grey.shade700,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLoginTypeToggle() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _isAdminLogin = false;
                  _errorMessage = null;
                  _adminPasswordController.clear();
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: !_isAdminLogin ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.person,
                      color: !_isAdminLogin ? Colors.teal.shade700 : Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'User Login',
                      style: TextStyle(
                        color: !_isAdminLogin ? Colors.teal.shade700 : Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _isAdminLogin = true;
                  _errorMessage = null;
                  _usernameController.clear();
                  _passwordController.clear();
                  _adminPasswordController.clear();
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: _isAdminLogin ? Colors.white : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.admin_panel_settings,
                      color: _isAdminLogin ? Colors.red.shade700 : Colors.white,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Admin Login',
                      style: TextStyle(
                        color: _isAdminLogin ? Colors.red.shade700 : Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool isPassword = false,
    bool isObscured = false,
    VoidCallback? toggleObscured,
    String? Function(String?)? validator,
    TextInputType keyboardType = TextInputType.text,
    String? hintText,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        obscureText: isPassword && isObscured,
        keyboardType: keyboardType,
        validator: validator,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          labelText: label,
          hintText: hintText,
          prefixIcon: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _isAdminLogin ? Colors.red.shade50 : Colors.teal.shade50,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: _isAdminLogin ? Colors.red.shade700 : Colors.teal.shade700,
              size: 20,
            ),
          ),
          suffixIcon: isPassword
              ? IconButton(
                  icon: Icon(
                    isObscured ? Icons.visibility_off : Icons.visibility,
                    color: Colors.grey.shade600,
                  ),
                  onPressed: toggleObscured,
                )
              : null,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.grey.shade200),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(
              color: _isAdminLogin ? Colors.red.shade500 : Colors.teal.shade500, 
              width: 2
            ),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: BorderSide(color: Colors.red.shade300),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
        ),
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
        textInputAction: isPassword ? TextInputAction.done : TextInputAction.next,
        onFieldSubmitted: isPassword && !_isAdminLogin ? (_) => _handleLogin() : null,
      ),
    );
  }

  Widget _buildAdminPasswordField() {
    if (!_isAdminLogin) return const SizedBox.shrink();
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.security, color: Colors.red.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                'Super Admin Verification Required',
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _adminPasswordController,
            obscureText: _obscureAdminPassword,
            validator: (value) {
              if (_isAdminLogin && (value == null || value.isEmpty)) {
                return 'Super admin password is required';
              }
              return null;
            },
            decoration: InputDecoration(
              labelText: 'Super Admin Password',
              hintText: 'Enter super admin password',
              prefixIcon: Icon(Icons.lock, color: Colors.red.shade700),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureAdminPassword ? Icons.visibility_off : Icons.visibility,
                  color: Colors.red.shade700,
                ),
                onPressed: () {
                  setState(() {
                    _obscureAdminPassword = !_obscureAdminPassword;
                  });
                },
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.red.shade200),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.red.shade500, width: 2),
              ),
            ),
            onFieldSubmitted: (_) => _handleLogin(),
          ),
          const SizedBox(height: 8),
          Text(
            'This additional password is required for admin access security.',
            style: TextStyle(
              color: Colors.red.shade600,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorMessage() {
    if (_errorMessage == null) return const SizedBox.shrink();

    return AnimatedBuilder(
      animation: _shakeAnimation,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(_shakeAnimation.value, 0),
          child: Container(
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.error_outline,
                  color: Colors.red.shade700,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(
                      color: Colors.red.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLoginButton() {
    return Container(
      width: double.infinity,
      height: 56,
      margin: const EdgeInsets.only(bottom: 16),
      child: ElevatedButton(
        onPressed: _isLoading ? null : _handleLogin,
        style: ElevatedButton.styleFrom(
          backgroundColor: _isAdminLogin ? Colors.red.shade600 : Colors.teal.shade600,
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.grey.shade300,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 4,
          shadowColor: _isAdminLogin 
              ? Colors.red.shade300 
              : Colors.teal.shade300,
        ),
        child: _isLoading
            ? Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _isAdminLogin ? 'Authenticating Admin...' : 'Signing in...',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isAdminLogin ? Icons.admin_panel_settings : Icons.login,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isAdminLogin ? 'Admin Login' : 'Sign In',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildBiometricButton() {
    if (!_isBiometricAvailable || _isAdminLogin) return const SizedBox.shrink();

    final biometricName = _biometricService.getBiometricTypeDisplayName(_availableBiometrics);
    final biometricIcon = _biometricService.getBiometricIcon(_availableBiometrics);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.teal.shade50, Colors.teal.shade100],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.teal.shade300),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _isLoading ? null : _handleBiometricLogin,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_isLoading)
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.teal.shade600),
                      ),
                    )
                  else
                    Text(
                      biometricIcon,
                      style: const TextStyle(fontSize: 24),
                    ),
                  const SizedBox(width: 12),
                  Text(
                    _isLoading ? 'Authenticating...' : 'Sign in with $biometricName',
                    style: TextStyle(
                      color: Colors.teal.shade700,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Column(
      children: [
        // System Info Section
        Container(
          padding: const EdgeInsets.all(12),
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.shield_outlined,
                    color: Colors.white.withValues(alpha: 0.8),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Secure Connection • 256-bit Encryption',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Version 3.2.0 • Build 8',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        if (!_isAdminLogin) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Don\'t have an account? ',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const RegistrationPage()),
                  );
                },
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(50, 30),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'Register Now',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          TextButton(
            onPressed: _showForgotPasswordDialog,
            child: Text(
              'Forgot Password?',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.8),
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        // Help & Support Links
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextButton.icon(
              onPressed: () => _showHelpDialog(),
              icon: Icon(
                Icons.help_outline,
                size: 16,
                color: Colors.white.withValues(alpha: 0.7),
              ),
              label: Text(
                'Help',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
            ),
            Text(
              ' • ',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
            TextButton.icon(
              onPressed: () => _showContactDialog(),
              icon: Icon(
                Icons.support_agent,
                size: 16,
                color: Colors.white.withValues(alpha: 0.7),
              ),
              label: Text(
                'Support',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_isAdminLogin) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.shade900.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Row(
              children: [
                Icon(Icons.warning, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Admin access requires additional verification',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  void _showHelpDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.help_outline, color: Colors.teal.shade700),
            const SizedBox(width: 8),
            const Text('Help & Documentation'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CEMS Login Help',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 12),
            _buildHelpItem('• Use your registered username and password'),
            _buildHelpItem('• Admin users require additional verification'),
            _buildHelpItem('• Biometric login available for registered devices'),
            _buildHelpItem('• Contact support for password reset'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'For security reasons, accounts are locked after 5 failed attempts.',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
        ],
      ),
    );
  }

  Widget _buildHelpItem(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.grey.shade700,
          fontSize: 14,
        ),
      ),
    );
  }

  void _showContactDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.support_agent, color: Colors.teal.shade700),
            const SizedBox(width: 8),
            const Text('Contact Support'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildContactItem(Icons.email, 'Email', 'support@prestigepark.com'),
            _buildContactItem(Icons.phone, 'Phone', '+91 80 1234 5678'),
            _buildContactItem(Icons.access_time, 'Hours', 'Mon-Fri, 9AM-6PM IST'),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.chat, color: Colors.green.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Live chat available for immediate assistance',
                      style: TextStyle(
                        color: Colors.green.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _openWebsite('mailto:support@prestigepark.com');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
            ),
            child: const Text('EMAIL SUPPORT'),
          ),
        ],
      ),
    );
  }

  Widget _buildContactItem(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: Colors.grey.shade600, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                ),
              ),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _showForgotPasswordDialog() {
    final TextEditingController emailController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.help_outline, color: Colors.teal.shade700),
            const SizedBox(width: 8),
            const Text('Forgot Password'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter your email address and we\'ll send you instructions to reset your password.'),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              decoration: InputDecoration(
                labelText: 'Email',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                prefixIcon: const Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            onPressed: () {
              if (emailController.text.isEmpty) {
                _showErrorSnackBar('Please enter your email address');
                return;
              }
              Navigator.pop(context);
              _showSuccessSnackBar('Password reset instructions sent to your email');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
            ),
            child: const Text('SEND'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => BiometricAuthPage()),
              );
            },
            child: Text('Use Biometric Authentication'),
          ),
        ],
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'DISMISS',
          textColor: Colors.white,
          onPressed: () {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  Future<void> _offerBiometricSetup() async {
    // Wait for navigation to complete before showing dialog
    await Future.delayed(const Duration(milliseconds: 2000));
    
    if (!mounted) return;
    
    final availableBiometrics = await _biometricService.getAvailableBiometrics();
    final biometricName = _biometricService.getBiometricTypeDisplayName(availableBiometrics);
    
    if (!mounted) return;
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.fingerprint, color: Colors.teal.shade700),
            const SizedBox(width: 8),
            const Text('Enable Biometric Login'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Would you like to enable $biometricName for faster and more secure login?',
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.teal.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.teal.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.security, color: Colors.teal.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your credentials will be securely stored on this device.',
                      style: TextStyle(
                        color: Colors.teal.shade700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Maybe Later'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _setupBiometricAuth();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal.shade600,
              foregroundColor: Colors.white,
            ),
            child: const Text('Enable Now'),
          ),
        ],
      ),
    );
  }

  Future<void> _setupBiometricAuth() async {
    try {
      final success = await _biometricService.enableBiometricAuth(
        _usernameController.text.trim(),
        _passwordController.text,
      );

      if (success) {
        _showSuccessSnackBar('✅ Biometric authentication enabled successfully');
      } else {
        _showErrorSnackBar('❌ Failed to enable biometric authentication');
      }
    } catch (e) {
      _showErrorSnackBar('Error enabling biometric auth: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _isAdminLogin 
                ? [Colors.red.shade800, Colors.red.shade600, Colors.orange.shade500]
                : [Colors.teal.shade800, Colors.teal.shade600, Colors.blue.shade500],
          ),
        ),
        child: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: math.min(MediaQuery.of(context).size.width, 400),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildHeader(),
                      const SizedBox(height: 40),
                      Card(
                        elevation: 20,
                        shadowColor: Colors.black.withValues(alpha: 0.3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: Container(
                          padding: const EdgeInsets.all(32.0),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24),
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                Colors.white,
                                Colors.grey.shade50,
                              ],
                            ),
                          ),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              children: [
                                // Login Form Info Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  margin: const EdgeInsets.only(bottom: 16),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: Colors.blue.shade200,
                                      width: 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.info_outline,
                                        color: Colors.blue.shade700,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Use your registered credentials to access CEMS',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.blue.shade700,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                _buildLoginTypeToggle(),
                                _buildInputField(
                                  controller: _usernameController,
                                  label: _isAdminLogin ? 'Admin Username' : 'Username',
                                  icon: _isAdminLogin ? Icons.admin_panel_settings : Icons.person,
                                  hintText: _isAdminLogin ? 'Enter admin username' : 'Enter your username',
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter your username';
                                    }
                                    return null;
                                  },
                                ),
                                _buildInputField(
                                  controller: _passwordController,
                                  label: _isAdminLogin ? 'Admin Password' : 'Password',
                                  icon: Icons.lock,
                                  isPassword: true,
                                  isObscured: _obscurePassword,
                                  toggleObscured: () {
                                    setState(() {
                                      _obscurePassword = !_obscurePassword;
                                    });
                                  },
                                  hintText: _isAdminLogin ? 'Enter admin password' : 'Enter your password',
                                  validator: (value) {
                                    if (value == null || value.isEmpty) {
                                      return 'Please enter your password';
                                    }
                                    return null;
                                  },
                                ),
                                _buildAdminPasswordField(),
                                _buildErrorMessage(),
                                _buildBiometricButton(),
                                _buildLoginButton(),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _buildStatisticsSection(),
                      const SizedBox(height: 20),
                      _buildFooter(),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}