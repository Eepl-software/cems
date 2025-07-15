import 'dart:async';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class SessionService {
  static const String baseUrl = 'http://54.146.215.18:3000';
  static const String tokenKey = 'auth_token';
  static const String refreshTokenKey = 'refresh_token';
  
  final StreamController<bool> _authStateController = StreamController<bool>.broadcast();
  Stream<bool> get authStateStream => _authStateController.stream;

  Future<void> saveTokens({required String token, String? refreshToken}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(tokenKey, token);
    if (refreshToken != null) {
      await prefs.setString(refreshTokenKey, refreshToken);
    }
    _authStateController.add(true);
  }

  Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(tokenKey);
  }

  Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(refreshTokenKey);
  }

  Future<void> clearTokens() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(tokenKey);
    await prefs.remove(refreshTokenKey);
    _authStateController.add(false);
  }

  Future<bool> refreshToken() async {
    try {
      final refreshToken = await getRefreshToken();
      if (refreshToken == null) return false;

      final response = await http.post(
        Uri.http('54.146.215.18:3000', '/refresh-token'),
        headers: {'Authorization': 'Bearer $refreshToken'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        await saveTokens(
          token: data['token'],
          refreshToken: data['refreshToken'],
        );
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<String?> getValidToken() async {
    String? token = await getToken();
    if (token == null) return null;

    // Check if token is expired (you might want to decode JWT to check expiration)
    try {
      final response = await http.get(
        Uri.http('54.146.215.18:3000', '/verify-token'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 401) {
        // Token is expired, try to refresh
        final refreshed = await refreshToken();
        if (refreshed) {
          return await getToken();
        }
        await clearTokens();
        return null;
      }

      return token;
    } catch (e) {
      return token; // Return existing token if server is unreachable
    }
  }

  void dispose() {
    _authStateController.close();
  }
} 