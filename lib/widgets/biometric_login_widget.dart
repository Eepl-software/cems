import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../services/biometric_auth_service.dart';
import '../services/enhanced_api_service.dart';

/// Biometric login widget that can be integrated into any login page
class BiometricLoginWidget extends StatefulWidget {
  final Function(String userId)? onBiometricSuccess;
  final Function(String error)? onBiometricError;
  final Function()? onBiometricSetup;
  final bool showSetupOption;
  final EdgeInsets? margin;

  const BiometricLoginWidget({
    Key? key,
    this.onBiometricSuccess,
    this.onBiometricError,
    this.onBiometricSetup,
    this.showSetupOption = true,
    this.margin,
  }) : super(key: key);

  @override
  State<BiometricLoginWidget> createState() => _BiometricLoginWidgetState();
}

class _BiometricLoginWidgetState extends State<BiometricLoginWidget>
    with SingleTickerProviderStateMixin {
  final BiometricAuthService _biometricService = BiometricAuthService();
  final EnhancedAPIService _apiService = EnhancedAPIService();
  
  bool _isBiometricAvailable = false;
  bool _isBiometricEnabled = false;
  bool _isAuthenticating = false;
  List<BiometricType> _availableBiometrics = [];
  late AnimationController _animationController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _checkBiometricStatus();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
  }

  Future<void> _checkBiometricStatus() async {
    try {
      final isAvailable = await _biometricService.isBiometricAvailable();
      final isEnabled = await _biometricService.isBiometricEnabled();
      final availableBiometrics = await _biometricService.getAvailableBiometrics();
      
      if (mounted) {
        setState(() {
          _isBiometricAvailable = isAvailable;
          _isBiometricEnabled = isEnabled;
          _availableBiometrics = availableBiometrics;
        });
      }
    } catch (e) {
      print('Error checking biometric status: $e');
    }
  }

  Future<void> _performBiometricAuthentication() async {
    if (_isAuthenticating) return;

    setState(() {
      _isAuthenticating = true;
    });

    _animationController.forward();

    try {
      final result = await _biometricService.authenticateWithBiometrics();
      
      if (result.success && result.userId != null) {
        // Set the authentication token in the API service
        // Note: In a real app, you might want to get a fresh token from the server
        // using the biometric authentication result
        
        if (widget.onBiometricSuccess != null) {
          widget.onBiometricSuccess!(result.userId!);
        }
        
        _showSuccessAnimation();
      } else {
        if (widget.onBiometricError != null) {
          widget.onBiometricError!(result.message);
        }
        _showErrorFeedback();
      }
    } catch (e) {
      if (widget.onBiometricError != null) {
        widget.onBiometricError!('Authentication failed: $e');
      }
      _showErrorFeedback();
    } finally {
      setState(() {
        _isAuthenticating = false;
      });
      _animationController.reverse();
    }
  }

  void _showSuccessAnimation() {
    // You can add a success animation here
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('✅ Authentication successful'),
        backgroundColor: Colors.green,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showErrorFeedback() {
    // Vibrate or show error animation
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('❌ Authentication failed'),
        backgroundColor: Colors.red,
        duration: Duration(seconds: 2),
      ),
    );
  }

  Widget _buildBiometricIcon() {
    final String icon = _biometricService.getBiometricIcon(_availableBiometrics);
    final String displayName = _biometricService.getBiometricTypeDisplayName(_availableBiometrics);
    
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                Theme.of(context).primaryColor.withOpacity(0.8),
                Theme.of(context).primaryColor,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).primaryColor.withOpacity(0.3),
                blurRadius: 15,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: _isAuthenticating
              ? const CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 3,
                )
              : Center(
                  child: Text(
                    icon,
                    style: const TextStyle(fontSize: 32),
                  ),
                ),
        ),
        const SizedBox(height: 12),
        Text(
          displayName,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w500,
            color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.8),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_isBiometricAvailable) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: widget.margin ?? const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_isBiometricEnabled) ...[
            // Biometric authentication button
            AnimatedBuilder(
              animation: _scaleAnimation,
              builder: (context, child) {
                return Transform.scale(
                  scale: _scaleAnimation.value,
                  child: GestureDetector(
                    onTap: _isAuthenticating ? null : _performBiometricAuthentication,
                    child: _buildBiometricIcon(),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Text(
              'Tap to authenticate',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6),
              ),
            ),
          ] else if (widget.showSetupOption) ...[
            // Setup biometric authentication
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.fingerprint,
                      size: 48,
                      color: Theme.of(context).primaryColor.withOpacity(0.7),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Enable Biometric Login',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Login faster and more securely using ${_biometricService.getBiometricTypeDisplayName(_availableBiometrics)}',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: widget.onBiometricSetup,
                        icon: const Icon(Icons.security, size: 20),
                        label: const Text('Set Up Now'),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
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
          ],
          
          // Divider
          if (_isBiometricEnabled || widget.showSetupOption) ...[
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(child: Divider(color: Colors.grey.withOpacity(0.5))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    'OR',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.withOpacity(0.7),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(child: Divider(color: Colors.grey.withOpacity(0.5))),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ],
      ),
    );
  }
}

/// Simple biometric setup dialog
class BiometricSetupDialog extends StatefulWidget {
  final String userId;
  final String password;

  const BiometricSetupDialog({
    Key? key,
    required this.userId,
    required this.password,
  }) : super(key: key);

  @override
  State<BiometricSetupDialog> createState() => _BiometricSetupDialogState();
}

class _BiometricSetupDialogState extends State<BiometricSetupDialog> {
  final BiometricAuthService _biometricService = BiometricAuthService();
  bool _isSetupInProgress = false;

  Future<void> _setupBiometricAuth() async {
    setState(() {
      _isSetupInProgress = true;
    });

    try {
      final success = await _biometricService.enableBiometricAuth(
        widget.userId,
        widget.password,
      );

      if (mounted) {
        if (success) {
          Navigator.of(context).pop(true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Biometric authentication enabled successfully'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('❌ Failed to enable biometric authentication'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSetupInProgress = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enable Biometric Login'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.fingerprint,
            size: 64,
            color: Theme.of(context).primaryColor,
          ),
          const SizedBox(height: 16),
          const Text(
            'Would you like to enable biometric authentication for faster and more secure login?',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (_isSetupInProgress)
            const Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 8),
                Text('Setting up biometric authentication...'),
              ],
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _isSetupInProgress ? null : () => Navigator.of(context).pop(false),
          child: const Text('Maybe Later'),
        ),
        ElevatedButton(
          onPressed: _isSetupInProgress ? null : _setupBiometricAuth,
          child: Text(_isSetupInProgress ? 'Setting up...' : 'Enable'),
        ),
      ],
    );
  }
}