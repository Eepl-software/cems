import 'package:local_auth/local_auth.dart';
import 'package:local_auth/error_codes.dart' as auth_error;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';

/// Comprehensive biometric authentication service
/// Handles fingerprint, face recognition, and secure storage
class BiometricAuthService {
  static final BiometricAuthService _instance = BiometricAuthService._internal();
  factory BiometricAuthService() => _instance;
  BiometricAuthService._internal();

  final LocalAuthentication _localAuth = LocalAuthentication();
  
  // Storage keys
  static const String _biometricEnabledKey = 'biometric_enabled';
  static const String _biometricUserIdKey = 'biometric_user_id';
  static const String _biometricHashKey = 'biometric_hash';
  static const String _lastAuthTimeKey = 'last_auth_time';
  
  /// Check if biometric authentication is available on the device
  Future<bool> isBiometricAvailable() async {
    try {
      final bool isAvailable = await _localAuth.canCheckBiometrics;
      final bool isDeviceSupported = await _localAuth.isDeviceSupported();
      return isAvailable && isDeviceSupported;
    } catch (e) {
      print('Error checking biometric availability: $e');
      return false;
    }
  }

  /// Get available biometric types
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      print('Error getting available biometrics: $e');
      return [];
    }
  }

  /// Check if biometric authentication is enabled for the current user
  Future<bool> isBiometricEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_biometricEnabledKey) ?? false;
  }

  /// Enable biometric authentication for a user
  Future<bool> enableBiometricAuth(String userId, String password) async {
    try {
      // First, verify that biometrics are available
      if (!await isBiometricAvailable()) {
        throw Exception('Biometric authentication is not available on this device');
      }

      // Authenticate with biometrics to confirm setup
      final bool didAuthenticate = await _authenticateWithBiometrics(
        reason: 'Enable biometric login for your account',
        isSetup: true,
      );

      if (!didAuthenticate) {
        return false;
      }

      // Create a secure hash of the user credentials
      final String credentialHash = _createSecureHash(userId, password);
      
      // Store biometric settings
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_biometricEnabledKey, true);
      await prefs.setString(_biometricUserIdKey, userId);
      await prefs.setString(_biometricHashKey, credentialHash);
      await prefs.setInt(_lastAuthTimeKey, DateTime.now().millisecondsSinceEpoch);

      return true;
    } catch (e) {
      print('Error enabling biometric auth: $e');
      return false;
    }
  }

  /// Disable biometric authentication
  Future<void> disableBiometricAuth() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_biometricEnabledKey);
    await prefs.remove(_biometricUserIdKey);
    await prefs.remove(_biometricHashKey);
    await prefs.remove(_lastAuthTimeKey);
  }

  /// Authenticate user with biometrics
  Future<BiometricAuthResult> authenticateWithBiometrics() async {
    try {
      // Check if biometric auth is enabled
      if (!await isBiometricEnabled()) {
        return BiometricAuthResult(
          success: false,
          errorType: BiometricErrorType.notEnabled,
          message: 'Biometric authentication is not enabled',
        );
      }

      // Check if biometrics are available
      if (!await isBiometricAvailable()) {
        return BiometricAuthResult(
          success: false,
          errorType: BiometricErrorType.notAvailable,
          message: 'Biometric authentication is not available',
        );
      }

      // Perform biometric authentication
      final bool didAuthenticate = await _authenticateWithBiometrics(
        reason: 'Authenticate to access your account',
      );

      if (didAuthenticate) {
        // Get stored user credentials
        final prefs = await SharedPreferences.getInstance();
        final String? userId = prefs.getString(_biometricUserIdKey);
        
        if (userId != null) {
          // Update last authentication time
          await prefs.setInt(_lastAuthTimeKey, DateTime.now().millisecondsSinceEpoch);
          
          return BiometricAuthResult(
            success: true,
            userId: userId,
            message: 'Authentication successful',
          );
        } else {
          return BiometricAuthResult(
            success: false,
            errorType: BiometricErrorType.dataCorrupted,
            message: 'Stored authentication data is corrupted',
          );
        }
      } else {
        return BiometricAuthResult(
          success: false,
          errorType: BiometricErrorType.authenticationFailed,
          message: 'Authentication failed or was cancelled',
        );
      }
    } catch (e) {
      return BiometricAuthResult(
        success: false,
        errorType: BiometricErrorType.unknown,
        message: 'Authentication error: $e',
      );
    }
  }

  /// Get user-friendly biometric type names
  String getBiometricTypeDisplayName(List<BiometricType> types) {
    if (types.isEmpty) return 'Biometric';
    
    if (types.contains(BiometricType.face)) {
      return Platform.isIOS ? 'Face ID' : 'Face Recognition';
    } else if (types.contains(BiometricType.fingerprint)) {
      return Platform.isIOS ? 'Touch ID' : 'Fingerprint';
    } else if (types.contains(BiometricType.iris)) {
      return 'Iris Recognition';
    } else {
      return 'Biometric';
    }
  }

  /// Get the appropriate icon for biometric types
  String getBiometricIcon(List<BiometricType> types) {
    if (types.isEmpty) return '🔒';
    
    if (types.contains(BiometricType.face)) {
      return '👤';
    } else if (types.contains(BiometricType.fingerprint)) {
      return '👆';
    } else if (types.contains(BiometricType.iris)) {
      return '👁️';
    } else {
      return '🔒';
    }
  }

  /// Check if authentication session is still valid (within last 30 minutes)
  Future<bool> isAuthSessionValid() async {
    final prefs = await SharedPreferences.getInstance();
    final int? lastAuthTime = prefs.getInt(_lastAuthTimeKey);
    
    if (lastAuthTime == null) return false;
    
    final DateTime lastAuth = DateTime.fromMillisecondsSinceEpoch(lastAuthTime);
    final DateTime now = DateTime.now();
    final Duration difference = now.difference(lastAuth);
    
    // Session valid for 30 minutes
    return difference.inMinutes < 30;
  }

  /// Verify stored credentials against provided credentials
  Future<bool> verifyStoredCredentials(String userId, String password) async {
    final prefs = await SharedPreferences.getInstance();
    final String? storedHash = prefs.getString(_biometricHashKey);
    final String? storedUserId = prefs.getString(_biometricUserIdKey);
    
    if (storedHash == null || storedUserId == null) return false;
    if (storedUserId != userId) return false;
    
    final String providedHash = _createSecureHash(userId, password);
    return storedHash == providedHash;
  }

  /// Get stored user ID for biometric authentication
  Future<String?> getStoredUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_biometricUserIdKey);
  }

  /// Internal method to perform biometric authentication
  Future<bool> _authenticateWithBiometrics({
    required String reason,
    bool isSetup = false,
  }) async {
    try {
      final bool didAuthenticate = await _localAuth.authenticate(
        localizedReason: reason,
        options: AuthenticationOptions(
          biometricOnly: !isSetup, // Allow fallback to PIN/password during setup
          stickyAuth: true,
          sensitiveTransaction: true,
        ),
      );
      
      return didAuthenticate;
    } on PlatformException catch (e) {
      print('Biometric authentication error: ${e.code} - ${e.message}');
      
      switch (e.code) {
        case auth_error.notAvailable:
        case auth_error.notEnrolled:
          throw Exception('Biometric authentication is not set up on this device');
        case auth_error.lockedOut:
        case auth_error.permanentlyLockedOut:
          throw Exception('Biometric authentication is temporarily locked');
        default:
          throw Exception('Biometric authentication failed: ${e.message}');
      }
    } catch (e) {
      print('Unexpected biometric error: $e');
      throw Exception('Authentication error occurred');
    }
  }

  /// Create a secure hash of user credentials
  String _createSecureHash(String userId, String password) {
    final String combined = '$userId:$password:${Platform.operatingSystem}';
    final List<int> bytes = utf8.encode(combined);
    final Digest digest = sha256.convert(bytes);
    return digest.toString();
  }
}

/// Result of biometric authentication
class BiometricAuthResult {
  final bool success;
  final String? userId;
  final String message;
  final BiometricErrorType? errorType;

  BiometricAuthResult({
    required this.success,
    this.userId,
    required this.message,
    this.errorType,
  });
}

/// Types of biometric authentication errors
enum BiometricErrorType {
  notEnabled,
  notAvailable,
  authenticationFailed,
  dataCorrupted,
  unknown,
}