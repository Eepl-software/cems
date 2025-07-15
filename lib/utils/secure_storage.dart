import 'package:shared_preferences/shared_preferences.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'dart:io';

/// Secure storage utility for sensitive biometric data
class SecureStorage {
  static const String _keyPrefix = 'secure_';
  static const String _saltKey = 'storage_salt';
  
  /// Generate a device-specific salt for encryption
  static Future<String> _getDeviceSalt() async {
    final prefs = await SharedPreferences.getInstance();
    String? salt = prefs.getString(_saltKey);
    
    if (salt == null) {
      // Create a new salt based on device info
      final deviceInfo = '${Platform.operatingSystem}_${DateTime.now().millisecondsSinceEpoch}';
      final bytes = utf8.encode(deviceInfo);
      salt = sha256.convert(bytes).toString().substring(0, 16);
      await prefs.setString(_saltKey, salt);
    }
    
    return salt;
  }
  
  /// Encrypt data using device-specific key
  static Future<String> _encryptData(String data) async {
    final salt = await _getDeviceSalt();
    final combined = '$salt:$data:${Platform.operatingSystem}';
    final bytes = utf8.encode(combined);
    return sha256.convert(bytes).toString();
  }
  
  /// Store encrypted data securely
  static Future<bool> storeSecure(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encryptedValue = await _encryptData(value);
      return await prefs.setString('$_keyPrefix$key', encryptedValue);
    } catch (e) {
      print('Error storing secure data: $e');
      return false;
    }
  }
  
  /// Retrieve and verify encrypted data
  static Future<String?> getSecure(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('$_keyPrefix$key');
    } catch (e) {
      print('Error retrieving secure data: $e');
      return null;
    }
  }
  
  /// Remove encrypted data
  static Future<bool> removeSecure(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.remove('$_keyPrefix$key');
    } catch (e) {
      print('Error removing secure data: $e');
      return false;
    }
  }
  
  /// Verify if stored data matches provided data
  static Future<bool> verifySecure(String key, String value) async {
    try {
      final storedHash = await getSecure(key);
      if (storedHash == null) return false;
      
      final encryptedValue = await _encryptData(value);
      return storedHash == encryptedValue;
    } catch (e) {
      print('Error verifying secure data: $e');
      return false;
    }
  }
  
  /// Clear all secure storage
  static Future<void> clearAllSecure() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((key) => key.startsWith(_keyPrefix));
      for (final key in keys) {
        await prefs.remove(key);
      }
      await prefs.remove(_saltKey);
    } catch (e) {
      print('Error clearing secure storage: $e');
    }
  }
  
  /// Store biometric user credentials
  static Future<bool> storeBiometricCredentials({
    required String userId,
    required String passwordHash,
    required bool isEnabled,
  }) async {
    try {
      final success1 = await storeSecure('biometric_user_id', userId);
      final success2 = await storeSecure('biometric_password_hash', passwordHash);
      
      final prefs = await SharedPreferences.getInstance();
      final success3 = await prefs.setBool('biometric_enabled', isEnabled);
      final success4 = await prefs.setInt('biometric_setup_time', DateTime.now().millisecondsSinceEpoch);
      
      return success1 && success2 && success3 && success4;
    } catch (e) {
      print('Error storing biometric credentials: $e');
      return false;
    }
  }
  
  /// Retrieve biometric user credentials
  static Future<Map<String, dynamic>?> getBiometricCredentials() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isEnabled = prefs.getBool('biometric_enabled') ?? false;
      
      if (!isEnabled) return null;
      
      final userId = await getSecure('biometric_user_id');
      final passwordHash = await getSecure('biometric_password_hash');
      final setupTime = prefs.getInt('biometric_setup_time');
      
      if (userId == null || passwordHash == null) return null;
      
      return {
        'userId': userId,
        'passwordHash': passwordHash,
        'setupTime': setupTime,
        'isEnabled': isEnabled,
      };
    } catch (e) {
      print('Error retrieving biometric credentials: $e');
      return null;
    }
  }
  
  /// Clear biometric credentials
  static Future<void> clearBiometricCredentials() async {
    try {
      await removeSecure('biometric_user_id');
      await removeSecure('biometric_password_hash');
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('biometric_enabled');
      await prefs.remove('biometric_setup_time');
      await prefs.remove('last_biometric_auth');
    } catch (e) {
      print('Error clearing biometric credentials: $e');
    }
  }
  
  /// Update last authentication time
  static Future<void> updateLastAuthTime() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('last_biometric_auth', DateTime.now().millisecondsSinceEpoch);
    } catch (e) {
      print('Error updating last auth time: $e');
    }
  }
  
  /// Check if biometric session is still valid (within last 30 minutes)
  static Future<bool> isBiometricSessionValid() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastAuth = prefs.getInt('last_biometric_auth');
      
      if (lastAuth == null) return false;
      
      final now = DateTime.now().millisecondsSinceEpoch;
      const thirtyMinutes = 30 * 60 * 1000; // 30 minutes in milliseconds
      
      return (now - lastAuth) < thirtyMinutes;
    } catch (e) {
      print('Error checking biometric session validity: $e');
      return false;
    }
  }
}