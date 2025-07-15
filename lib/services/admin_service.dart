// admin_service.dart
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;

class AdminService {
  static const String baseUrl = 'http://54.146.215.18:3000';
  final String token;
  
  AdminService({required this.token});

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    'Authorization': 'Bearer $token',
  };

  // Authentication
  static Future<AdminLoginResponse> adminLogin({
    required String username,
    required String password,
    required String adminPassword,
  }) async {
    try {
      final response = await http.post(
        Uri.http('54.146.215.18:3000', '/admin/login'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'username': username,
          'password': password,
          'adminPassword': adminPassword,
        }),
      ).timeout(const Duration(seconds: 15));

      final data = json.decode(response.body);

      if (response.statusCode == 200) {
        return AdminLoginResponse(
          success: true,
          token: data['token'],
          message: data['message'],
          admin: AdminUser.fromJson(data['admin']),
        );
      } else {
        return AdminLoginResponse(
          success: false,
          message: data['error'] ?? 'Admin login failed',
        );
      }
    } catch (e) {
      return AdminLoginResponse(
        success: false,
        message: 'Connection error: $e',
      );
    }
  }

  // Dashboard Statistics
  Future<DashboardStats> getDashboardStats() async {
    try {
      final response = await http.get(
        Uri.http('54.146.215.18:3000', '/admin/dashboard-stats'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return DashboardStats.fromJson(data);
      } else {
        throw AdminException('Failed to fetch dashboard stats: ${response.statusCode}');
      }
    } catch (e) {
      throw AdminException('Error fetching dashboard stats: $e');
    }
  }

  // Recent Activities
  Future<List<AdminActivity>> getRecentActivities() async {
    try {
      final response = await http.get(
        Uri.http('54.146.215.18:3000', '/admin/recent-activities'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return (data['activities'] as List)
            .map((activity) => AdminActivity.fromJson(activity))
            .toList();
      } else {
        throw AdminException('Failed to fetch recent activities: ${response.statusCode}');
      }
    } catch (e) {
      throw AdminException('Error fetching recent activities: $e');
    }
  }

  // User Management
  Future<UserListResponse> getUsers({
    int page = 1,
    int limit = 10,
    String search = '',
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
        if (search.isNotEmpty) 'search': search,
      };
      final uri = Uri.http('54.146.215.18:3000', '/admin/users', queryParams);

      final response = await http.get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return UserListResponse.fromJson(data);
      } else {
        throw AdminException('Failed to fetch users: ${response.statusCode}');
      }
    } catch (e) {
      throw AdminException('Error fetching users: $e');
    }
  }

  Future<AdminUser> createUser(Map<String, dynamic> userData) async {
    try {
      final response = await http.post(
        Uri.http('54.146.215.18:3000', '/admin/users'),
        headers: _headers,
        body: json.encode(userData),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        return AdminUser.fromJson(data['user']);
      } else {
        final error = json.decode(response.body);
        throw AdminException(error['error'] ?? 'Failed to create user');
      }
    } catch (e) {
      if (e is AdminException) rethrow;
      throw AdminException('Error creating user: $e');
    }
  }

  Future<AdminUser> updateUser(int userId, Map<String, dynamic> userData) async {
    try {
      final response = await http.put(
        Uri.http('54.146.215.18:3000', '/admin/users/$userId'),
        headers: _headers,
        body: json.encode(userData),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return AdminUser.fromJson(data['user']);
      } else {
        final error = json.decode(response.body);
        throw AdminException(error['error'] ?? 'Failed to update user');
      }
    } catch (e) {
      if (e is AdminException) rethrow;
      throw AdminException('Error updating user: $e');
    }
  }

  Future<void> deleteUser(int userId) async {
    try {
      final response = await http.delete(
        Uri.http('54.146.215.18:3000', '/admin/users/$userId'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        final error = json.decode(response.body);
        throw AdminException(error['error'] ?? 'Failed to delete user');
      }
    } catch (e) {
      if (e is AdminException) rethrow;
      throw AdminException('Error deleting user: $e');
    }
  }

  // System Management
  Future<BackupResponse> initiateBackup() async {
    try {
      final response = await http.post(
        Uri.http('54.146.215.18:3000', '/admin/backup'),
        headers: _headers,
      ).timeout(const Duration(seconds: 60)); // Longer timeout for backup

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return BackupResponse.fromJson(data);
      } else {
        final error = json.decode(response.body);
        throw AdminException(error['error'] ?? 'Failed to initiate backup');
      }
    } catch (e) {
      if (e is AdminException) rethrow;
      throw AdminException('Error initiating backup: $e');
    }
  }

  Future<List<SystemLog>> getSystemLogs({
    int page = 1,
    int limit = 50,
    String level = 'all',
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
        'level': level,
      };
      final uri = Uri.http('54.146.215.18:3000', '/admin/system-logs', queryParams);

      final response = await http.get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return (data['logs'] as List)
            .map((log) => SystemLog.fromJson(log))
            .toList();
      } else {
        throw AdminException('Failed to fetch system logs: ${response.statusCode}');
      }
    } catch (e) {
      throw AdminException('Error fetching system logs: $e');
    }
  }

  Future<SystemStatus> getSystemStatus() async {
    try {
      final response = await http.get(
        Uri.http('54.146.215.18:3000', '/admin/status'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return SystemStatus.fromJson(data);
      } else {
        throw AdminException('Failed to fetch system status: ${response.statusCode}');
      }
    } catch (e) {
      throw AdminException('Error fetching system status: $e');
    }
  }

  // Reports
  Future<ReportResponse> generateReport({
    required String type,
    DateTime? startDate,
    DateTime? endDate,
    String format = 'json',
  }) async {
    try {
      final body = <String, dynamic>{
        'type': type,
        'format': format,
      };

      if (startDate != null) {
        body['startDate'] = startDate.toIso8601String();
      }
      if (endDate != null) {
        body['endDate'] = endDate.toIso8601String();
      }

      final response = await http.post(
        Uri.http('54.146.215.18:3000', '/admin/reports'),
        headers: _headers,
        body: json.encode(body),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return ReportResponse.fromJson(data);
      } else {
        final error = json.decode(response.body);
        throw AdminException(error['error'] ?? 'Failed to generate report');
      }
    } catch (e) {
      if (e is AdminException) rethrow;
      throw AdminException('Error generating report: $e');
    }
  }

  Future<List<Report>> getReports() async {
    try {
      final response = await http.get(
        Uri.http('54.146.215.18:3000', '/admin/reports'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return (data['reports'] as List)
            .map((report) => Report.fromJson(report))
            .toList();
      } else {
        throw AdminException('Failed to fetch reports: ${response.statusCode}');
      }
    } catch (e) {
      throw AdminException('Error fetching reports: $e');
    }
  }

  // Alerts Management
  Future<List<SystemAlert>> getAlerts({
    int page = 1,
    int limit = 20,
    String severity = 'all',
  }) async {
    try {
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
        'severity': severity,
      };
      final uri = Uri.http('54.146.215.18:3000', '/admin/alerts', queryParams);

      final response = await http.get(uri, headers: _headers)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return (data['alerts'] as List)
            .map((alert) => SystemAlert.fromJson(alert))
            .toList();
      } else {
        throw AdminException('Failed to fetch alerts: ${response.statusCode}');
      }
    } catch (e) {
      throw AdminException('Error fetching alerts: $e');
    }
  }

  Future<SystemAlert> createAlert({
    required String title,
    required String message,
    required String severity,
    bool sendToUsers = false,
  }) async {
    try {
      final response = await http.post(
        Uri.http('54.146.215.18:3000', '/admin/alerts'),
        headers: _headers,
        body: json.encode({
          'title': title,
          'message': message,
          'severity': severity,
          'sendToUsers': sendToUsers,
        }),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        return SystemAlert.fromJson(data['alert']);
      } else {
        final error = json.decode(response.body);
        throw AdminException(error['error'] ?? 'Failed to create alert');
      }
    } catch (e) {
      if (e is AdminException) rethrow;
      throw AdminException('Error creating alert: $e');
    }
  }

  // Settings Management
  Future<List<AdminSetting>> getSettings() async {
    try {
      final response = await http.get(
        Uri.http('54.146.215.18:3000', '/admin/settings'),
        headers: _headers,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return (data['settings'] as List)
            .map((setting) => AdminSetting.fromJson(setting))
            .toList();
      } else {
        throw AdminException('Failed to fetch settings: ${response.statusCode}');
      }
    } catch (e) {
      throw AdminException('Error fetching settings: $e');
    }
  }

  Future<AdminSetting> updateSetting({
    required String key,
    required String value,
    String? description,
  }) async {
    try {
      final response = await http.put(
        Uri.http('54.146.215.18:3000', '/admin/settings/$key'),
        headers: _headers,
        body: json.encode({
          'value': value,
          if (description != null) 'description': description,
        }),
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return AdminSetting.fromJson(data['setting']);
      } else {
        final error = json.decode(response.body);
        throw AdminException(error['error'] ?? 'Failed to update setting');
      }
    } catch (e) {
      if (e is AdminException) rethrow;
      throw AdminException('Error updating setting: $e');
    }
  }

  // Utility Methods
  Future<bool> checkConnection() async {
    try {
      final response = await http.get(
        Uri.http('54.146.215.18:3000', '/health'),
      ).timeout(const Duration(seconds: 5));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    // Clean up resources if needed
  }
}

// Data Models
class AdminLoginResponse {
  final bool success;
  final String? token;
  final String? message;
  final AdminUser? admin;

  AdminLoginResponse({
    required this.success,
    this.token,
    this.message,
    this.admin,
  });
}

class AdminUser {
  final String username;
  final String role;
  final List<String> permissions;
  final DateTime? lastLogin;

  AdminUser({
    required this.username,
    required this.role,
    required this.permissions,
    this.lastLogin,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      username: json['username'] ?? '',
      role: json['role'] ?? 'admin',
      permissions: List<String>.from(json['permissions'] ?? ['all']),
      lastLogin: json['lastLogin'] != null 
          ? DateTime.parse(json['lastLogin']) 
          : null,
    );
  }
}

class DashboardStats {
  final int totalUsers;
  final int activeUsers;
  final int activeTankers;
  final int waterConsumption;
  final int alerts;
  final int systemHealth;
  final double dataUsage;
  final int activeSessions;

  DashboardStats({
    required this.totalUsers,
    required this.activeUsers,
    required this.activeTankers,
    required this.waterConsumption,
    required this.alerts,
    required this.systemHealth,
    required this.dataUsage,
    required this.activeSessions,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    return DashboardStats(
      totalUsers: json['totalUsers'] ?? 0,
      activeUsers: json['activeUsers'] ?? 0,
      activeTankers: json['activeTankers'] ?? 0,
      waterConsumption: json['waterConsumption'] ?? 0,
      alerts: json['alerts'] ?? 0,
      systemHealth: json['systemHealth'] ?? 95,
      dataUsage: (json['dataUsage'] ?? 0).toDouble(),
      activeSessions: json['activeSessions'] ?? 0,
    );
  }
}

class AdminActivity {
  final String type;
  final String description;
  final DateTime timestamp;

  AdminActivity({
    required this.type,
    required this.description,
    required this.timestamp,
  });

  factory AdminActivity.fromJson(Map<String, dynamic> json) {
    return AdminActivity(
      type: json['type'] ?? 'unknown',
      description: json['description'] ?? '',
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

class UserListResponse {
  final List<AdminUser> users;
  final Pagination pagination;

  UserListResponse({
    required this.users,
    required this.pagination,
  });

  factory UserListResponse.fromJson(Map<String, dynamic> json) {
    return UserListResponse(
      users: (json['users'] as List)
          .map((user) => AdminUser.fromJson(user))
          .toList(),
      pagination: Pagination.fromJson(json['pagination']),
    );
  }
}

class Pagination {
  final int page;
  final int limit;
  final int total;
  final int pages;

  Pagination({
    required this.page,
    required this.limit,
    required this.total,
    required this.pages,
  });

  factory Pagination.fromJson(Map<String, dynamic> json) {
    return Pagination(
      page: json['page'] ?? 1,
      limit: json['limit'] ?? 10,
      total: json['total'] ?? 0,
      pages: json['pages'] ?? 0,
    );
  }
}

class BackupResponse {
  final String message;
  final String backupId;
  final String filename;
  final DateTime timestamp;
  final int tablesBackedUp;

  BackupResponse({
    required this.message,
    required this.backupId,
    required this.filename,
    required this.timestamp,
    required this.tablesBackedUp,
  });

  factory BackupResponse.fromJson(Map<String, dynamic> json) {
    return BackupResponse(
      message: json['message'] ?? '',
      backupId: json['backupId'] ?? '',
      filename: json['filename'] ?? '',
      timestamp: DateTime.parse(json['timestamp']),
      tablesBackedUp: json['tablesBackedUp'] ?? 0,
    );
  }
}

class SystemLog {
  final String source;
  final String level;
  final String message;
  final String userInfo;
  final String? ipAddress;
  final DateTime timestamp;

  SystemLog({
    required this.source,
    required this.level,
    required this.message,
    required this.userInfo,
    this.ipAddress,
    required this.timestamp,
  });

  factory SystemLog.fromJson(Map<String, dynamic> json) {
    return SystemLog(
      source: json['source'] ?? '',
      level: json['level'] ?? '',
      message: json['message'] ?? '',
      userInfo: json['user_info'] ?? '',
      ipAddress: json['ip_address'],
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

class SystemStatus {
  final String database;
  final double uptime;
  final Map<String, int> memory;
  final String nodeVersion;
  final String platform;
  final DateTime timestamp;

  SystemStatus({
    required this.database,
    required this.uptime,
    required this.memory,
    required this.nodeVersion,
    required this.platform,
    required this.timestamp,
  });

  factory SystemStatus.fromJson(Map<String, dynamic> json) {
    return SystemStatus(
      database: json['database'] ?? 'unknown',
      uptime: (json['uptime'] ?? 0).toDouble(),
      memory: Map<String, int>.from(json['memory'] ?? {}),
      nodeVersion: json['nodeVersion'] ?? '',
      platform: json['platform'] ?? '',
      timestamp: DateTime.parse(json['timestamp']),
    );
  }
}

class ReportResponse {
  final String message;
  final String reportId;
  final String filename;
  final Map<String, dynamic> data;

  ReportResponse({
    required this.message,
    required this.reportId,
    required this.filename,
    required this.data,
  });

  factory ReportResponse.fromJson(Map<String, dynamic> json) {
    return ReportResponse(
      message: json['message'] ?? '',
      reportId: json['reportId'] ?? '',
      filename: json['filename'] ?? '',
      data: json['data'] ?? {},
    );
  }
}

class Report {
  final String filename;
  final String id;
  final int size;
  final DateTime created;
  final DateTime modified;

  Report({
    required this.filename,
    required this.id,
    required this.size,
    required this.created,
    required this.modified,
  });

  factory Report.fromJson(Map<String, dynamic> json) {
    return Report(
      filename: json['filename'] ?? '',
      id: json['id'] ?? '',
      size: json['size'] ?? 0,
      created: DateTime.parse(json['created']),
      modified: DateTime.parse(json['modified']),
    );
  }
}

class SystemAlert {
  final int id;
  final String title;
  final String message;
  final String severity;
  final bool isActive;
  final DateTime createdAt;
  final String? createdByUsername;

  SystemAlert({
    required this.id,
    required this.title,
    required this.message,
    required this.severity,
    required this.isActive,
    required this.createdAt,
    this.createdByUsername,
  });

  factory SystemAlert.fromJson(Map<String, dynamic> json) {
    return SystemAlert(
      id: json['id'] ?? 0,
      title: json['title'] ?? '',
      message: json['message'] ?? '',
      severity: json['severity'] ?? 'low',
      isActive: json['is_active'] ?? true,
      createdAt: DateTime.parse(json['created_at']),
      createdByUsername: json['created_by_username'],
    );
  }
}

class AdminSetting {
  final int id;
  final String settingKey;
  final String settingValue;
  final String? description;
  final String? updatedBy;
  final DateTime updatedAt;

  AdminSetting({
    required this.id,
    required this.settingKey,
    required this.settingValue,
    this.description,
    this.updatedBy,
    required this.updatedAt,
  });

  factory AdminSetting.fromJson(Map<String, dynamic> json) {
    return AdminSetting(
      id: json['id'] ?? 0,
      settingKey: json['setting_key'] ?? '',
      settingValue: json['setting_value'] ?? '',
      description: json['description'],
      updatedBy: json['updated_by'],
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }
}

class AdminException implements Exception {
  final String message;
  
  AdminException(this.message);
  
  @override
  String toString() => 'AdminException: $message';
}