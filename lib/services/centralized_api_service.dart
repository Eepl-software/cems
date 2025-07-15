import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../auth_service.dart';

/// Centralized API service for all backend communications
class CentralizedApiService {
  static const String baseUrl = 'http://54.146.215.18:3000';
  final AuthService _authService;
  
  CentralizedApiService(this._authService);

  /// Get headers with authentication token
  Map<String, String> get _headers {
    final Map<String, String> headers = {
      'Content-Type': 'application/json',
    };
    
    if (_authService.token != null) {
      headers['Authorization'] = 'Bearer ${_authService.token}';
    }
    
    return headers;
  }

  /// Generic HTTP request handler with error handling
  Future<Map<String, dynamic>> _makeRequest(
    String method,
    String endpoint, {
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
    bool requiresAuth = false,
  }) async {
    if (requiresAuth && _authService.token == null) {
      throw ApiException('Authentication required', 401);
    }

    // Fix URL construction to avoid null character issue
    Uri uri = Uri.http('54.146.215.18:3000', endpoint, queryParams);

    final headers = _headers;

    try {
      http.Response response;
      
      switch (method.toUpperCase()) {
        case 'GET':
          response = await http.get(uri, headers: headers);
        case 'POST':
          response = await http.post(
            uri,
            headers: headers,
            body: body != null ? json.encode(body) : null,
          );
        case 'PUT':
          response = await http.put(
            uri,
            headers: headers,
            body: body != null ? json.encode(body) : null,
          );
        case 'DELETE':
          response = await http.delete(uri, headers: headers);
        default:
          throw ApiException('Unsupported HTTP method: $method');
      }

      return _handleResponse(response);
    } catch (e) {
      if (e is ApiException) rethrow;
      throw ApiException('Network error: ${e.toString()}');
    }
  }

  /// Handle HTTP response and errors
  Map<String, dynamic> _handleResponse(http.Response response) {
    final data = json.decode(response.body);

    switch (response.statusCode) {
      case 200:
      case 201:
        return data;
      case 400:
        throw ApiException(data['error'] ?? 'Bad request', 400);
      case 401:
        throw ApiException('Authentication required', 401);
      case 403:
        throw ApiException('Insufficient permissions', 403);
      case 404:
        throw ApiException('Resource not found', 404);
      case 409:
        throw ApiException(data['error'] ?? 'Conflict', 409);
      case 500:
        throw ApiException('Server error', 500);
      default:
        throw ApiException('Unknown error', response.statusCode);
    }
  }

  /// File upload with multipart form data
  Future<Map<String, dynamic>> _uploadFile(
    String endpoint,
    File file,
    Map<String, String> fields, {
    String fileFieldName = 'file',
  }) async {
    final request = http.MultipartRequest('POST', Uri.http('54.146.215.18:3000', endpoint));
    
    if (_authService.token != null) {
      request.headers['Authorization'] = 'Bearer ${_authService.token}';
    }

    request.files.add(await http.MultipartFile.fromPath(fileFieldName, file.path));
    request.fields.addAll(fields);

    final response = await request.send();
    final responseBody = await response.stream.bytesToString();

    if (response.statusCode == 200 || response.statusCode == 201) {
      return json.decode(responseBody);
    } else {
      final error = json.decode(responseBody);
      throw ApiException(error['error'] ?? 'Upload failed', response.statusCode);
    }
  }

  // WATER MANAGEMENT ENDPOINTS

  /// Get borewell data
  Future<List<Map<String, dynamic>>> getBorewellData({
    String? date,
    String? search,
  }) async {
    final queryParams = <String, String>{};
    if (date != null) queryParams['date'] = date;
    if (search != null) queryParams['search'] = search;

    final response = await _makeRequest('GET', '/borewell', queryParams: queryParams);
    return List<Map<String, dynamic>>.from(response['data'] ?? []);
  }

  /// Create borewell entry
  Future<Map<String, dynamic>> createBorewellEntry({
    required String date,
    required String borewellNo,
    required String locatedAt,
    required double inKld,
    required double outKld,
    required double waterConsumed,
  }) async {
    final body = {
      'date': date,
      'borewell_no': borewellNo,
      'located_at': locatedAt,
      'in_kld': inKld,
      'out_kld': outKld,
      'water_consumed': waterConsumed,
    };

    return await _makeRequest('POST', '/borewell', body: body);
  }

  /// Update borewell entry
  Future<Map<String, dynamic>> updateBorewellEntry(
    int id, {
    required String date,
    required String borewellNo,
    required String locatedAt,
    required double inKld,
    required double outKld,
    required double waterConsumed,
  }) async {
    final body = {
      'date': date,
      'borewell_no': borewellNo,
      'located_at': locatedAt,
      'in_kld': inKld,
      'out_kld': outKld,
      'water_consumed': waterConsumed,
    };

    return await _makeRequest('PUT', '/borewell/$id', body: body);
  }

  /// Delete borewell entry
  Future<Map<String, dynamic>> deleteBorewellEntry(int id) async {
    return await _makeRequest('DELETE', '/borewell/$id');
  }

  /// Get borewell statistics
  Future<Map<String, dynamic>> getBorewellStats() async {
    return await _makeRequest('GET', '/borewell/stats');
  }

  /// Add water consumption data
  Future<Map<String, dynamic>> addWaterConsumption({
    required int total,
    required int thisMonth,
    required int today,
  }) async {
    final body = {
      'total': total,
      'thisMonth': thisMonth,
      'today': today,
    };

    return await _makeRequest('POST', '/water-consumption', body: body);
  }

  // TANKER MANAGEMENT ENDPOINTS

  /// Get tanker data
  Future<List<Map<String, dynamic>>> getTankerData() async {
    final response = await _makeRequest('GET', '/tanker');
    return List<Map<String, dynamic>>.from(response['data'] ?? []);
  }

  /// Create tanker entry with photo
  Future<Map<String, dynamic>> createTankerEntry({
    required Map<String, String> tankerData,
    File? photo,
  }) async {
    if (photo != null) {
      return await _uploadFile('/tanker', photo, tankerData, fileFieldName: 'photo');
    } else {
      return await _makeRequest('POST', '/tanker', body: tankerData);
    }
  }

  /// Update tanker entry
  Future<Map<String, dynamic>> updateTankerEntry(
    int id,
    Map<String, dynamic> tankerData,
  ) async {
    return await _makeRequest('PUT', '/tanker/$id', body: tankerData);
  }

  /// Delete tanker entry
  Future<Map<String, dynamic>> deleteTankerEntry(int id) async {
    return await _makeRequest('DELETE', '/tanker/$id');
  }

  // WASTE MANAGEMENT ENDPOINTS

  /// Labour Colony Waste Management
  Future<List<Map<String, dynamic>>> getLabourColonyWaste() async {
    final response = await _makeRequest('GET', '/labour-colony-waste');
    return List<Map<String, dynamic>>.from(response['data'] ?? []);
  }

  Future<Map<String, dynamic>> createLabourColonyWaste(
    Map<String, dynamic> wasteData,
  ) async {
    return await _makeRequest('POST', '/labour-colony-waste', body: wasteData);
  }

  Future<Map<String, dynamic>> updateLabourColonyWaste(
    int id,
    Map<String, dynamic> wasteData,
  ) async {
    return await _makeRequest('PUT', '/labour-colony-waste/$id', body: wasteData);
  }

  Future<Map<String, dynamic>> deleteLabourColonyWaste(int id) async {
    return await _makeRequest('DELETE', '/labour-colony-waste/$id');
  }

  /// Construction & Demolition Waste
  Future<List<Map<String, dynamic>>> getCDWaste() async {
    final response = await _makeRequest('GET', '/cd-waste');
    return List<Map<String, dynamic>>.from(response['data'] ?? []);
  }

  Future<Map<String, dynamic>> createCDWaste(
    Map<String, dynamic> wasteData,
  ) async {
    return await _makeRequest('POST', '/cd-waste', body: wasteData);
  }

  /// Project Waste Management
  Future<List<Map<String, dynamic>>> getProjectWaste() async {
    final response = await _makeRequest('GET', '/project-waste');
    return List<Map<String, dynamic>>.from(response['data'] ?? []);
  }

  Future<Map<String, dynamic>> createProjectWaste(
    Map<String, dynamic> wasteData,
  ) async {
    return await _makeRequest('POST', '/project-waste', body: wasteData);
  }

  Future<Map<String, dynamic>> updateProjectWaste(
    int id,
    Map<String, dynamic> wasteData,
  ) async {
    return await _makeRequest('PUT', '/project-waste/$id', body: wasteData);
  }

  Future<Map<String, dynamic>> deleteProjectWaste(int id) async {
    return await _makeRequest('DELETE', '/project-waste/$id');
  }

  // AIR POLLUTION MONITORING ENDPOINTS

  /// Stack Monitoring
  Future<List<Map<String, dynamic>>> getStackMonitoring() async {
    final response = await _makeRequest('GET', '/stack-monitoring');
    return List<Map<String, dynamic>>.from(response['data'] ?? []);
  }

  Future<Map<String, dynamic>> createStackMonitoring(
    Map<String, dynamic> monitoringData,
  ) async {
    return await _makeRequest('POST', '/stack-monitoring', body: monitoringData);
  }

  Future<Map<String, dynamic>> updateStackMonitoring(
    int id,
    Map<String, dynamic> monitoringData,
  ) async {
    return await _makeRequest('PUT', '/stack-monitoring/$id', body: monitoringData);
  }

  Future<Map<String, dynamic>> deleteStackMonitoring(int id) async {
    return await _makeRequest('DELETE', '/stack-monitoring/$id');
  }

  /// Ambient Monitoring
  Future<List<Map<String, dynamic>>> getAmbientMonitoring() async {
    final response = await _makeRequest('GET', '/ambient-monitoring');
    return List<Map<String, dynamic>>.from(response['data'] ?? []);
  }

  Future<Map<String, dynamic>> createAmbientMonitoring(
    Map<String, dynamic> monitoringData,
  ) async {
    return await _makeRequest('POST', '/ambient-monitoring', body: monitoringData);
  }

  Future<Map<String, dynamic>> updateAmbientMonitoring(
    int id,
    Map<String, dynamic> monitoringData,
  ) async {
    return await _makeRequest('PUT', '/ambient-monitoring/$id', body: monitoringData);
  }

  Future<Map<String, dynamic>> deleteAmbientMonitoring(int id) async {
    return await _makeRequest('DELETE', '/ambient-monitoring/$id');
  }

  // DOCUMENT MANAGEMENT ENDPOINTS

  /// Get documents with pagination and filtering
  Future<Map<String, dynamic>> getDocuments({
    int page = 1,
    int limit = 20,
    String? category,
    String? status,
    String? search,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
      if (category != null) 'category': category,
      if (status != null) 'status': status,
      if (search != null) 'search': search,
    };

    return await _makeRequest(
      'GET',
      '/api/documents',
      queryParams: queryParams,
      requiresAuth: true,
    );
  }

  /// Get document by ID
  Future<Map<String, dynamic>> getDocumentById(String id) async {
    return await _makeRequest('GET', '/api/documents/$id', requiresAuth: true);
  }

  /// Upload document
  Future<Map<String, dynamic>> uploadDocument(
    File file, {
    required String category,
    required String description,
    DateTime? expiryDate,
    List<String>? tags,
  }) async {
    final fields = <String, String>{
      'category': category,
      'description': description,
      if (expiryDate != null) 'expiry_date': expiryDate.toIso8601String(),
      if (tags != null) 'tags': json.encode(tags),
    };

    return await _uploadFile('/api/documents', file, fields);
  }

  /// Update document metadata
  Future<Map<String, dynamic>> updateDocument(
    String id,
    Map<String, dynamic> documentData,
  ) async {
    return await _makeRequest(
      'PUT',
      '/api/documents/$id',
      body: documentData,
      requiresAuth: true,
    );
  }

  /// Delete document
  Future<Map<String, dynamic>> deleteDocument(String id) async {
    return await _makeRequest('DELETE', '/api/documents/$id', requiresAuth: true);
  }

  /// Get document statistics
  Future<Map<String, dynamic>> getDocumentStats() async {
    return await _makeRequest('GET', '/api/documents/stats', requiresAuth: true);
  }

  /// Get document health dashboard
  Future<Map<String, dynamic>> getDocumentHealthDashboard({
    String? projectName,
  }) async {
    final queryParams = <String, String>{};
    if (projectName != null) queryParams['project_name'] = projectName;

    return await _makeRequest(
      'GET',
      '/api/documents/health-dashboard',
      queryParams: queryParams,
      requiresAuth: true,
    );
  }

  /// Validate document
  Future<Map<String, dynamic>> validateDocument({
    required String documentId,
    String? projectName,
  }) async {
    final body = {
      'document_id': documentId,
      if (projectName != null) 'project_name': projectName,
    };

    return await _makeRequest(
      'POST',
      '/api/documents/validate',
      body: body,
      requiresAuth: true,
    );
  }

  // ADMIN ENDPOINTS

  /// Get dashboard statistics (Admin only)
  Future<Map<String, dynamic>> getAdminDashboardStats() async {
    return await _makeRequest('GET', '/admin/dashboard-stats', requiresAuth: true);
  }

  /// Get recent activities (Admin only)
  Future<List<Map<String, dynamic>>> getAdminRecentActivities() async {
    final response = await _makeRequest('GET', '/admin/recent-activities', requiresAuth: true);
    return List<Map<String, dynamic>>.from(response['data'] ?? []);
  }

  /// Get system statistics (Admin only)
  Future<Map<String, dynamic>> getAdminSystemStats() async {
    return await _makeRequest('GET', '/admin/stats', requiresAuth: true);
  }

  /// Get users list (Admin only)
  Future<Map<String, dynamic>> getAdminUsers({
    int page = 1,
    int limit = 20,
    String? search,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
      if (search != null) 'search': search,
    };

    return await _makeRequest(
      'GET',
      '/admin/users',
      queryParams: queryParams,
      requiresAuth: true,
    );
  }

  /// Create user (Admin only)
  Future<Map<String, dynamic>> createUser(Map<String, dynamic> userData) async {
    return await _makeRequest('POST', '/admin/users', body: userData, requiresAuth: true);
  }

  /// Update user (Admin only)
  Future<Map<String, dynamic>> updateUser(int id, Map<String, dynamic> userData) async {
    return await _makeRequest('PUT', '/admin/users/$id', body: userData, requiresAuth: true);
  }

  /// Delete user (Admin only)
  Future<Map<String, dynamic>> deleteUser(int id) async {
    return await _makeRequest('DELETE', '/admin/users/$id', requiresAuth: true);
  }

  /// Generate report (Admin only)
  Future<Map<String, dynamic>> generateReport({
    required String type,
    DateTime? startDate,
    DateTime? endDate,
    String format = 'json',
  }) async {
    final body = {
      'type': type,
      if (startDate != null) 'startDate': startDate.toIso8601String(),
      if (endDate != null) 'endDate': endDate.toIso8601String(),
      'format': format,
    };

    return await _makeRequest('POST', '/admin/reports', body: body, requiresAuth: true);
  }

  /// Get reports list (Admin only)
  Future<List<Map<String, dynamic>>> getReports() async {
    final response = await _makeRequest('GET', '/admin/reports', requiresAuth: true);
    return List<Map<String, dynamic>>.from(response['reports'] ?? []);
  }

  /// Create backup (Admin only)
  Future<Map<String, dynamic>> createBackup() async {
    return await _makeRequest('POST', '/admin/backup', requiresAuth: true);
  }

  /// Get system logs (Admin only)
  Future<Map<String, dynamic>> getSystemLogs({
    int page = 1,
    int limit = 50,
    String? level,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
      if (level != null) 'level': level,
    };

    return await _makeRequest(
      'GET',
      '/admin/system-logs',
      queryParams: queryParams,
      requiresAuth: true,
    );
  }

  // NOTIFICATION ENDPOINTS

  /// Get notifications
  Future<Map<String, dynamic>> getNotifications({
    int page = 1,
    int limit = 20,
    bool unreadOnly = false,
    String? type,
  }) async {
    final queryParams = <String, String>{
      'page': page.toString(),
      'limit': limit.toString(),
      'unread_only': unreadOnly.toString(),
      if (type != null) 'type': type,
    };

    return await _makeRequest(
      'GET',
      '/api/notifications',
      queryParams: queryParams,
      requiresAuth: true,
    );
  }

  /// Mark notification as read
  Future<Map<String, dynamic>> markNotificationAsRead(String id) async {
    return await _makeRequest('PUT', '/api/notifications/$id/read', requiresAuth: true);
  }

  /// Mark all notifications as read
  Future<Map<String, dynamic>> markAllNotificationsAsRead() async {
    return await _makeRequest('PUT', '/api/notifications/read-all', requiresAuth: true);
  }

  /// Get notification preferences
  Future<Map<String, dynamic>> getNotificationPreferences() async {
    return await _makeRequest('GET', '/api/notifications/preferences', requiresAuth: true);
  }

  /// Update notification preferences
  Future<Map<String, dynamic>> updateNotificationPreferences(
    Map<String, dynamic> preferences,
  ) async {
    return await _makeRequest(
      'PUT',
      '/api/notifications/preferences',
      body: preferences,
      requiresAuth: true,
    );
  }

  // UTILITY ENDPOINTS

  /// Health check
  Future<Map<String, dynamic>> healthCheck() async {
    return await _makeRequest('GET', '/health');
  }

  /// Get consumption sources
  Future<List<Map<String, dynamic>>> getConsumptionSources() async {
    final response = await _makeRequest('GET', '/consumption/sources');
    return List<Map<String, dynamic>>.from(response['data'] ?? []);
  }

  /// Get consumption summary by phase
  Future<Map<String, dynamic>> getConsumptionSummaryByPhase(String phase) async {
    return await _makeRequest('GET', '/water-consumption/phase-summary/$phase');
  }

  /// Get water consumption dashboard
  Future<Map<String, dynamic>> getWaterConsumptionDashboard() async {
    return await _makeRequest('GET', '/water-consumption/dashboard');
  }
}

/// Custom exception for API errors
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  ApiException(this.message, [this.statusCode]);

  @override
  String toString() => message;
}