import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import '../services/biometric_auth_service.dart';
import '../utils/secure_storage.dart';

/// Comprehensive biometric management page for admin settings
class BiometricManagementPage extends StatefulWidget {
  const BiometricManagementPage({Key? key}) : super(key: key);

  @override
  State<BiometricManagementPage> createState() => _BiometricManagementPageState();
}

class _BiometricManagementPageState extends State<BiometricManagementPage> {
  final BiometricAuthService _biometricService = BiometricAuthService();
  
  bool _isBiometricAvailable = false;
  bool _isBiometricEnabled = false;
  bool _isLoading = false;
  List<BiometricType> _availableBiometrics = [];
  Map<String, dynamic>? _biometricCredentials;
  DateTime? _setupTime;
  DateTime? _lastAuthTime;
  bool _sessionValid = false;

  @override
  void initState() {
    super.initState();
    _loadBiometricStatus();
  }

  Future<void> _loadBiometricStatus() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final isAvailable = await _biometricService.isBiometricAvailable();
      final isEnabled = await _biometricService.isBiometricEnabled();
      final availableBiometrics = await _biometricService.getAvailableBiometrics();
      final credentials = await SecureStorage.getBiometricCredentials();
      final sessionValid = await SecureStorage.isBiometricSessionValid();

      DateTime? setupTime;
      if (credentials != null && credentials['setupTime'] != null) {
        setupTime = DateTime.fromMillisecondsSinceEpoch(credentials['setupTime']);
      }

      if (mounted) {
        setState(() {
          _isBiometricAvailable = isAvailable;
          _isBiometricEnabled = isEnabled;
          _availableBiometrics = availableBiometrics;
          _biometricCredentials = credentials;
          _setupTime = setupTime;
          _sessionValid = sessionValid;
        });
      }
    } catch (e) {
      print('Error loading biometric status: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading biometric status: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _enableBiometrics() async {
    // Show dialog to get user credentials
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (context) => _CredentialsDialog(),
    );

    if (result == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final success = await _biometricService.enableBiometricAuth(
        result['username']!,
        result['password']!,
      );

      if (success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Biometric authentication enabled successfully'),
              backgroundColor: Colors.green,
            ),
          );
          _loadBiometricStatus();
        }
      } else {
        if (mounted) {
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
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _disableBiometrics() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Disable Biometric Authentication'),
        content: const Text(
          'Are you sure you want to disable biometric authentication? '
          'You will need to enter your username and password to log in.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Disable'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _isLoading = true;
    });

    try {
      await _biometricService.disableBiometricAuth();
      await SecureStorage.clearBiometricCredentials();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Biometric authentication disabled'),
            backgroundColor: Colors.orange,
          ),
        );
        _loadBiometricStatus();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error disabling biometrics: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _testBiometricAuth() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final result = await _biometricService.authenticateWithBiometrics();
      
      if (mounted) {
        if (result.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Biometric authentication test successful'),
              backgroundColor: Colors.green,
            ),
          );
          _loadBiometricStatus();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('❌ Authentication test failed: ${result.message}'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error testing biometrics: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildStatusCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  _isBiometricEnabled ? Icons.security : Icons.security_outlined,
                  color: _isBiometricEnabled ? Colors.green : Colors.grey,
                ),
                const SizedBox(width: 8),
                Text(
                  'Biometric Authentication',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _isBiometricEnabled ? Colors.green : Colors.grey,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _isBiometricEnabled ? 'ENABLED' : 'DISABLED',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Device Support', _isBiometricAvailable ? 'Available' : 'Not Available'),
            if (_availableBiometrics.isNotEmpty)
              _buildInfoRow('Available Types', _biometricService.getBiometricTypeDisplayName(_availableBiometrics)),
            if (_setupTime != null)
              _buildInfoRow('Setup Date', '${_setupTime!.day}/${_setupTime!.month}/${_setupTime!.year}'),
            _buildInfoRow('Session Valid', _sessionValid ? 'Yes' : 'No'),
            if (_biometricCredentials != null)
              _buildInfoRow('User ID', _biometricCredentials!['userId'] ?? 'Unknown'),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
                color: Colors.grey[600],
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Actions',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (!_isBiometricEnabled && _isBiometricAvailable) ...[
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _enableBiometrics,
                icon: const Icon(Icons.fingerprint),
                label: const Text('Enable Biometric Authentication'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
            if (_isBiometricEnabled) ...[
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _testBiometricAuth,
                icon: const Icon(Icons.verified_user),
                label: const Text('Test Biometric Authentication'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: _isLoading ? null : _disableBiometrics,
                icon: const Icon(Icons.security_outlined),
                label: const Text('Disable Biometric Authentication'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
            if (!_isBiometricAvailable) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange[200]!),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning, color: Colors.orange[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Biometric authentication is not available on this device.',
                        style: TextStyle(color: Colors.orange[700]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Biometric Management'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadBiometricStatus,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildStatusCard(),
                  const SizedBox(height: 16),
                  _buildActionButtons(),
                ],
              ),
            ),
    );
  }
}

/// Dialog to collect user credentials for biometric setup
class _CredentialsDialog extends StatefulWidget {
  @override
  State<_CredentialsDialog> createState() => _CredentialsDialogState();
}

class _CredentialsDialogState extends State<_CredentialsDialog> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Enter Your Credentials'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Please enter your username and password to enable biometric authentication.',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: 'Username',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your username';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: 'Password',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() {
                      _obscurePassword = !_obscurePassword;
                    });
                  },
                ),
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter your password';
                }
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.of(context).pop({
                'username': _usernameController.text,
                'password': _passwordController.text,
              });
            }
          },
          child: const Text('Continue'),
        ),
      ],
    );
  }
}