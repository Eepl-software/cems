import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/login_response.dart';
import '../models.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static const String baseUrl = 'http://54.146.215.18:3000';
  User? _currentUser;
  String? _token;

  // Getter for current user
  User? get currentUser => _currentUser;
  
  // Getter for token
  String? get token => _token;

  Future<LoginResponse> login(String username, String password) async {
    try {
      final response = await http.post(
        Uri.http('54.146.215.18:3000', '/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
        }),
      );

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        _token = data['token'];
        
        if (data['user'] != null) {
          _currentUser = User(
            id: data['user']['id'] ?? 1,
            username: data['user']['username'] ?? username,
            email: data['user']['email'] ?? '',
            phone: data['user']['phone'] ?? '',
            company: data['user']['company'] ?? '',
            designation: data['user']['designation'] ?? 'user',
            role: data['user']['designation']?.toString().toLowerCase() == 'admin' 
                ? UserRole.superuser 
                : UserRole.user,
          );
        }

        return LoginResponse(
          success: true,
          token: data['token'],
          message: data['message'] ?? 'Login successful',
          user: data['user'],
        );
      } else {
        return LoginResponse(
          success: false,
          message: data['error'] ?? 'Login failed',
        );
      }
    } catch (e) {
      return LoginResponse(
        success: false,
        message: e.toString(),
      );
    }
  }
Future<void> saveCredentialsForBiometric(String username) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString('last_username', username);
}

  Future<RegistrationResponse> register({
    required String username,
    required String email,
    required String password,
    required String phone,
    required String company,
    required String designation,
  }) async {
    try {
      final response = await http.post(
        Uri.http('54.146.215.18:3000', '/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'email': email,
          'password': password,
          'phone': phone,
          'company': company,
          'designation': designation,
        }),
      );

      // Check if the response is JSON
      String contentType = response.headers['content-type'] ?? '';
      if (!contentType.contains('application/json')) {
        throw AuthException(
          'Server error: Expected JSON response but received different format',
        );
      }

      // Try to parse the response body
      Map<String, dynamic> bodyMap;
      try {
        bodyMap = json.decode(response.body);
      } catch (e) {
        throw AuthException('Failed to parse server response');
      }

      switch (response.statusCode) {
        case 201:
          final registrationResponse = RegistrationResponse.fromJson(bodyMap);
          _currentUser = registrationResponse.user;
          return registrationResponse;
        case 400:
          throw AuthException(bodyMap['error'] ?? 'Invalid registration data');
        case 409:
          throw AuthException(bodyMap['error'] ?? 'User already exists');
        case 500:
          throw AuthException('Internal server error');
        default:
          throw AuthException(
            bodyMap['error'] ?? 'An unexpected error occurred',
          );
      }
    } on http.ClientException catch (e) {
      throw AuthException('Connection error: Please check your internet connection');
    } catch (e) {
      if (e is AuthException) rethrow;
      throw AuthException('An unexpected error occurred: ${e.toString()}');
    }
  }

  // Check if user is super user
  bool isSuperUser() {
    return _currentUser?.designation.toLowerCase() == 'admin' ||
           _currentUser?.designation.toLowerCase() == 'superuser';
  }

  // Check if user is authenticated
  bool get isAuthenticated => _token != null;

  // Logout method
  void logout() {
    _currentUser = null;
    _token = null;
  }
}




// Check if biometric login is enabled
Future<bool> isBiometricLoginEnabled() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool('biometric_enabled') ?? false;
}

// Get saved username for biometric login
Future<String?> getSavedUsername() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getString('last_username');
}

// Enable or disable biometric login
Future<void> setBiometricLogin(bool enabled) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool('biometric_enabled', enabled);
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}

class RegistrationResponse {
  final String message;
  final User user;

  RegistrationResponse({
    required this.message,
    required this.user,
  });

  factory RegistrationResponse.fromJson(Map<String, dynamic> json) {
    try {
      return RegistrationResponse(
        message: json['message'] ?? '',
        user: User(
          id: json['user']['id'] ?? -1,
          username: json['user']['username'] ?? '',
          email: json['user']['email'] ?? '',
          phone: json['user']['phone'] ?? '',
          company: json['user']['company'] ?? '',
          designation: json['user']['designation'] ?? '',
          role: json['user']['designation']?.toString().toLowerCase() == 'admin' 
              ? UserRole.superuser 
              : UserRole.user,
        ),
      );
    } catch (e) {
      throw AuthException('Invalid response format from server');
    }
  }
}