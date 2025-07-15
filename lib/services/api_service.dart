import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/tanker.dart';

class APIService {
  static final APIService _instance = APIService._internal();
  factory APIService() => _instance;
  APIService._internal();

  final String baseUrl = 'http://54.146.215.18:3000';
  String? _authToken;

  void setAuthToken(String token) {
    _authToken = token;
  }

  Map<String, String> get _headers {
    final headers = {
      'Content-Type': 'application/json',
    };
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  // Tanker endpoints
  Future<List<Tanker>> getTankers({DateTime? date}) async {
    try {

      final response = await http.get(Uri.http('54.146.215.18:3000', '/api/tankers', date != null ? {'date': date.toIso8601String().split('T')[0]} : null), headers: _headers);
      _handleResponse(response);

      final List<dynamic> data = json.decode(response.body)['data'];
      return data.map((json) => Tanker.fromJson(json)).toList();
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<Tanker> getTankerByPlate(String plateNumber) async {
    try {
      final response = await http.get(
        Uri.http('54.146.215.18:3000', '/api/tankers/$plateNumber'),
        headers: _headers,
      );
      _handleResponse(response);

      return Tanker.fromJson(json.decode(response.body));
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<String> uploadTankerImage(File imageFile, String plateNumber) async {
    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.http('54.146.215.18:3000', '/api/tankers/images'),
      );

      if (_authToken != null) {
        request.headers['Authorization'] = 'Bearer $_authToken';
      }

      request.files.add(
        await http.MultipartFile.fromPath('image', imageFile.path),
      );
      request.fields['plateNumber'] = plateNumber;

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);
      _handleResponse(response);

      return json.decode(response.body)['imageUrl'];
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> updateTankerStatus(Tanker tanker) async {
    try {
      final response = await http.put(
        Uri.http('54.146.215.18:3000', '/api/tankers/${tanker.plateNumber}'),
        headers: _headers,
        body: json.encode(tanker.toJson()),
      );
      _handleResponse(response);
    } catch (e) {
      throw _handleError(e);
    }
  }

  Future<void> deleteTankerImage(String imageUrl) async {
    try {
      final response = await http.delete(
        Uri.http('54.146.215.18:3000', '/api/tankers/images'),
        headers: _headers,
        body: json.encode({'imageUrl': imageUrl}),
      );
      _handleResponse(response);
    } catch (e) {
      throw _handleError(e);
    }
  }

  // Helper methods
  void _handleResponse(http.Response response) {
    if (response.statusCode >= 400) {
      throw HttpException(
        json.decode(response.body)['message'] ?? 'Server error',
        uri: response.request?.url,
      );
    }
  }

  Exception _handleError(dynamic error) {
    if (error is SocketException) {
      return const HttpException('Network error. Please check your connection.');
    }
    if (error is HttpException) {
      return error;
    }
    if (error is FormatException) {
      return const HttpException('Invalid response format from server.');
    }
    return HttpException(error.toString());
  }
} 