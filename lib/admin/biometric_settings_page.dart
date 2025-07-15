import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth_service.dart';

class BiometricSettingsPage extends StatefulWidget {
  final AuthService authService;

  const BiometricSettingsPage({
    Key? key,
    required this.authService,
  }) : super(key: key);

  @override
  State<BiometricSettingsPage> createState() => _BiometricSettingsPageState();
}

class _BiometricSettingsPageState extends State<BiometricSettingsPage> {
  final LocalAuthentication _localAuth = LocalAuthentication();
  
  bool _isBiometricAvailable = false;
  bool _isBiometricEnabled = false;
  bool _isLoading = true;
  
  List<BiometricType> _availableBiometrics = [];
  String _statusMessage = 'Checking biometric support...';
  
  // Shared preferences keys
  static const String _biometricEnabledKey = 'biometric_enabled';
  static const String _lastUsernameKey = 'last_username';

  @override
  void initState() {
    super.initState();
    _checkBiometricSupport();
  }

  Future<void> _checkBiometricSupport() async {
    try {
      // Check if device supports biometrics
      bool canCheckBiometrics = await _localAuth.canCheckBiometrics;
      bool isDeviceSupported = await _localAuth.isDeviceSupported();
      
      _isBiometricAvailable = canCheckBiometrics && isDeviceSupported;
      
      if (_isBiometricAvailable) {
        // Get available biometrics
        _availableBiometrics = await _localAuth.getAvailableBiometrics();
        
        // Get current enabled status
        final prefs = await SharedPreferences.getInstance();
        _isBiometricEnabled = prefs.getBool(_biometricEnabledKey) ?? false;
        
        setState(() {
          _statusMessage = 'Biometric authentication available';
          _isLoading = false;
        });
      } else {
        setState(() {
          _statusMessage = 'Biometric authentication not supported on this device';
          _isLoading = false;
        });
      }
    } on PlatformException catch (e) {
      setState(() {
        _statusMessage = 'Error checking biometric support: ${e.message}';
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleBiometricAuthentication() async {
    if (!_isBiometricAvailable) {
      _showErrorDialog('Biometric authentication is not available on this device');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      // If enabling biometrics, verify user identity first
      if (!_isBiometricEnabled) {
        bool authenticated = await _localAuth.authenticate(
          localizedReason: 'Please authenticate to enable biometric login',
          options: const AuthenticationOptions(
            stickyAuth: true,
            biometricOnly: true,
          ),
        );

        if (!authenticated) {
          setState(() {
            _statusMessage = 'Authentication failed. Biometric login not enabled.';
            _isLoading = false;
          });
          return;
        }
      }

      // Toggle the setting
      final newValue = !_isBiometricEnabled;
      
      // Save to shared preferences
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_biometricEnabledKey, newValue);
      
      setState(() {
        _isBiometricEnabled = newValue;
        _statusMessage = newValue 
          ? 'Biometric login enabled successfully'
          : 'Biometric login disabled';
        _isLoading = false;
      });

      // Show success message
      _showSnackBar(
        newValue 
          ? 'Biometric login enabled. You can now log in using your biometrics.'
          : 'Biometric login disabled',
      );
      
    } catch (e) {
      setState(() {
        _statusMessage = 'Error: ${e.toString()}';
        _isLoading = false;
      });
      _showErrorDialog('Failed to configure biometric authentication: ${e.toString()}');
    }
  }

  void _saveCredentials() async {
    final TextEditingController usernameController = TextEditingController();
    
    // Check if there's a saved username already and pre-fill it
    final prefs = await SharedPreferences.getInstance();
    String? savedUsername = prefs.getString(_lastUsernameKey);
    if (savedUsername != null) {
      usernameController.text = savedUsername;
    }
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            'Save Credentials for Biometric Login',
            style: TextStyle(color: Colors.teal.shade700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Enter the username you want to use with biometric login:',
                style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: usernameController,
                decoration: InputDecoration(
                  labelText: 'Username',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  prefixIcon: const Icon(Icons.person),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('CANCEL', style: TextStyle(color: Colors.grey.shade600)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (usernameController.text.isEmpty) {
                  _showSnackBar('Please enter a username');
                  return;
                }
                
                // Save username to shared preferences
                final prefs = await SharedPreferences.getInstance();
                await prefs.setString(_lastUsernameKey, usernameController.text);
                
                if (!mounted) return;
                
                Navigator.pop(context);
                _showSnackBar('Credentials saved for biometric login');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade600,
                foregroundColor: Colors.white,
              ),
              child: const Text('SAVE'),
            ),
          ],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        );
      },
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.teal.shade700,
        action: SnackBarAction(
          label: 'DISMISS',
          textColor: Colors.white,
          onPressed: () => ScaffoldMessenger.of(context).hideCurrentSnackBar(),
        ),
      ),
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.error_outline, color: Colors.red.shade600),
            const SizedBox(width: 10),
            const Text('Error'),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  String _getBiometricTypeString() {
    if (_availableBiometrics.contains(BiometricType.fingerprint)) {
      return 'Fingerprint';
    } else if (_availableBiometrics.contains(BiometricType.face)) {
      return 'Face ID';
    } else if (_availableBiometrics.contains(BiometricType.iris)) {
      return 'Iris';
    } else {
      return 'Biometric';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Biometric Login Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.teal,
        elevation: 0,
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.teal.shade50, Colors.white],
          ),
        ),
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: Colors.teal))
            : Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeaderCard(),
                    const SizedBox(height: 24),
                    _buildStatusCard(),
                    const SizedBox(height: 24),
                    _buildActionCards(),
                    const Spacer(),
                    _buildHelpSection(),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.teal.shade50,
                  radius: 25,
                  child: Icon(
                    _availableBiometrics.contains(BiometricType.fingerprint)
                        ? Icons.fingerprint
                        : _availableBiometrics.contains(BiometricType.face)
                            ? Icons.face
                            : Icons.security,
                    color: Colors.teal.shade700,
                    size: 30,
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_getBiometricTypeString()} Login',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.teal.shade700,
                      ),
                    ),
                    Text(
                      'Configure biometric login settings',
                      style: TextStyle(
                        color: Colors.grey.shade600,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard() {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _isBiometricEnabled
                ? [Colors.teal.shade400, Colors.teal.shade700]
                : [Colors.grey.shade300, Colors.grey.shade500],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isBiometricAvailable
                      ? _isBiometricEnabled
                          ? Icons.check_circle
                          : Icons.info_outline
                      : Icons.error_outline,
                  color: Colors.white,
                  size: 24,
                ),
                const SizedBox(width: 10),
                Text(
                  'Status',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              _statusMessage,
              style: const TextStyle(
                fontSize: 14,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  _isBiometricEnabled ? Icons.lock_open : Icons.lock,
                  color: Colors.white70,
                  size: 16,
                ),
                const SizedBox(width: 8),
                Text(
                  _isBiometricEnabled ? 'Biometric login is enabled' : 'Biometric login is disabled',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCards() {
    return Column(
      children: [
        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: InkWell(
            onTap: _isBiometricAvailable ? _toggleBiometricAuthentication : null,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _isBiometricAvailable
                        ? Colors.teal.shade50
                        : Colors.grey.shade100,
                    child: Icon(
                      _isBiometricEnabled ? Icons.toggle_on : Icons.toggle_off,
                      color: _isBiometricAvailable
                          ? _isBiometricEnabled
                              ? Colors.teal.shade700
                              : Colors.grey.shade700
                          : Colors.grey.shade400,
                      size: 28,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isBiometricEnabled
                              ? 'Disable Biometric Login'
                              : 'Enable Biometric Login',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _isBiometricAvailable
                                ? Colors.black87
                                : Colors.grey.shade500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _isBiometricEnabled
                              ? 'Turn off the ability to login with biometrics'
                              : 'Allow login with biometrics instead of password',
                          style: TextStyle(
                            fontSize: 12,
                            color: _isBiometricAvailable
                                ? Colors.grey.shade600
                                : Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: _isBiometricAvailable
                        ? Colors.grey.shade700
                        : Colors.grey.shade300,
                  ),
                ],
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        Card(
          elevation: 2,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: InkWell(
            onTap: _isBiometricEnabled ? _saveCredentials : null,
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: _isBiometricEnabled
                        ? Colors.teal.shade50
                        : Colors.grey.shade100,
                    child: Icon(
                      Icons.save,
                      color: _isBiometricEnabled
                          ? Colors.teal.shade700
                          : Colors.grey.shade400,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Save Login Credentials',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: _isBiometricEnabled
                                ? Colors.black87
                                : Colors.grey.shade500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Store your username to use with biometric login',
                          style: TextStyle(
                            fontSize: 12,
                            color: _isBiometricEnabled
                                ? Colors.grey.shade600
                                : Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: _isBiometricEnabled
                        ? Colors.grey.shade700
                        : Colors.grey.shade300,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHelpSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.teal.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.teal.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.help_outline, color: Colors.teal.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                'How Biometric Login Works',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.teal.shade700,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '1. Enable biometric login here\n'
            '2. Save your username\n'
            '3. When logging in, tap the fingerprint/face icon on the login screen\n'
            '4. Authenticate with your biometric',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}