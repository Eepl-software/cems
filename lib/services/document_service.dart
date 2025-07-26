import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class DocumentService {
  static const String baseUrl = 'http://54.146.215.18:3000'; 
  
  // Get authentication token
  Future<String?> _getAuthToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  // Get headers with authentication
  Future<Map<String, String>> _getHeaders() async {
    final token = await _getAuthToken();
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
    };
  }

  // Get multipart headers with authentication
  Future<Map<String, String>> _getMultipartHeaders() async {
    final token = await _getAuthToken();
    return {
      'Authorization': 'Bearer $token',
    };
  }

  // Fetch all documents with filtering
  Future<Map<String, dynamic>> getDocuments({
    int page = 1,
    int limit = 20,
    String? category,
    String? status,
    String? search,
    String sortBy = 'date_added',
    String sortOrder = 'DESC',
    bool expiringSoon = false,
  }) async {
    try {
      final headers = await _getHeaders();
      
      // Build query parameters
      final queryParams = <String, String>{
        'page': page.toString(),
        'limit': limit.toString(),
        'sort_by': sortBy,
        'sort_order': sortOrder,
      };

      if (category != null) queryParams['category'] = category;
      if (status != null) queryParams['status'] = status;
      if (search != null && search.isNotEmpty) queryParams['search'] = search;
      if (expiringSoon) queryParams['expiring_soon'] = 'true';

      // Fix potential string interpolation issue by constructing URI properly
      final uri = Uri.parse('$baseUrl/api/documents').replace(queryParameters: queryParams);
      print('DocumentService: Loading documents from URI: $uri');
      
      final response = await http.get(uri, headers: headers);

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load documents: ${response.statusCode}');
      }
    } catch (e) {
      print('DocumentService: Error loading documents: $e');
      throw Exception('Error fetching documents: $e');
    }
  }

  // Get document by ID
  Future<Map<String, dynamic>> getDocument(String id) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/api/documents/$id'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else if (response.statusCode == 404) {
        throw Exception('Document not found');
      } else {
        throw Exception('Failed to load document: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching document: $e');
    }
  }

  // Upload new document
  Future<Map<String, dynamic>> uploadDocument({
    required String name,
    required String category,
    required File file,
    String status = 'Active',
  }) async {
    try {
      final headers = await _getMultipartHeaders();
      
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/documents'),
      );

      // Add headers
      request.headers.addAll(headers);

      // Add file
      request.files.add(await http.MultipartFile.fromPath('file', file.path));

      // Add form fields
      request.fields['name'] = name;
      request.fields['category'] = category;
      request.fields['status'] = status;

      final streamedResponse = await request.send();
      final response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 201) {
        return json.decode(response.body);
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to upload document');
      }
    } catch (e) {
      throw Exception('Error uploading document: $e');
    }
  }

  // Update document metadata
  Future<Map<String, dynamic>> updateDocument({
    required String id,
    required String name,
    required String category,
    String? description,
    List<String>? tags,
    String status = 'Active',
    DateTime? expiryDate,
  }) async {
    try {
      final headers = await _getHeaders();
      
      final body = {
        'name': name,
        'category': category,
        'status': status,
      };

      if (description != null) body['description'] = description;
      if (tags != null) body['tags'] = tags as String;
      if (expiryDate != null) {
        body['expiry_date'] = expiryDate.toIso8601String().split('T')[0];
      }

      final response = await http.put(
        Uri.parse('$baseUrl/api/documents/$id'),
        headers: headers,
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to update document');
      }
    } catch (e) {
      throw Exception('Error updating document: $e');
    }
  }

  // Delete document
  Future<Map<String, dynamic>> deleteDocument(String id) async {
    try {
      final headers = await _getHeaders();
      
      final response = await http.delete(
        Uri.parse('$baseUrl/api/documents/$id'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to delete document');
      }
    } catch (e) {
      throw Exception('Error deleting document: $e');
    }
  }

  // Get document categories
  Future<List<Map<String, dynamic>>> getCategories() async {
    try {
      final headers = await _getHeaders();
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/document-categories'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return List<Map<String, dynamic>>.from(data['data']);
      } else {
        throw Exception('Failed to load categories: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching categories: $e');
    }
  }

  // Get document statistics
  Future<Map<String, dynamic>> getStatistics() async {
    try {
      final headers = await _getHeaders();
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/documents/stats'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load statistics: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Error fetching statistics: $e');
    }
  }

  // Get download URL for document
  Future<String> getDownloadUrl(String id) async {
    try {
      final headers = await _getHeaders();
      
      final response = await http.get(
        Uri.parse('$baseUrl/api/documents/$id/download'),
        headers: headers,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['downloadUrl'];
      } else {
        final errorData = json.decode(response.body);
        throw Exception(errorData['message'] ?? 'Failed to get download URL');
      }
    } catch (e) {
      throw Exception('Error getting download URL: $e');
    }
  }

  // Search documents
  Future<Map<String, dynamic>> searchDocuments(String query, {
    String? category,
    int page = 1,
    int limit = 20,
  }) async {
    return getDocuments(
      search: query,
      category: category,
      page: page,
      limit: limit,
    );
  }

  // Get expiring documents
  Future<Map<String, dynamic>> getExpiringDocuments({
    int page = 1,
    int limit = 20,
  }) async {
    return getDocuments(
      expiringSoon: true,
      page: page,
      limit: limit,
    );
  }

  // Get documents by category
  Future<Map<String, dynamic>> getDocumentsByCategory(String category, {
    int page = 1,
    int limit = 20,
  }) async {
    return getDocuments(
      category: category,
      page: page,
      limit: limit,
    );
  }

  // Get documents by status
  Future<Map<String, dynamic>> getDocumentsByStatus(String status, {
    int page = 1,
    int limit = 20,
  }) async {
    return getDocuments(
      status: status,
      page: page,
      limit: limit,
    );
  }
}

// Document model class for type safety
class DocumentModel {
  final String id;
  final String name;
  final String category;
  final String filePath;
  final String fileType;
  final int? fileSize;
  final DateTime dateAdded;
  final DateTime? expiryDate;
  final String status;
  final String description;
  final List<String> tags;
  final bool isAsset;
  final int? uploadedBy;
  final bool isExpired;
  final bool isExpiringSoon;

  DocumentModel({
    required this.id,
    required this.name,
    required this.category,
    required this.filePath,
    required this.fileType,
    this.fileSize,
    required this.dateAdded,
    this.expiryDate,
    required this.status,
    required this.description,
    required this.tags,
    required this.isAsset,
    this.uploadedBy,
    required this.isExpired,
    required this.isExpiringSoon,
  });

  factory DocumentModel.fromJson(Map<String, dynamic> json) {
    return DocumentModel(
      id: json['id'],
      name: json['name'],
      category: json['category'],
      filePath: json['file_path'],
      fileType: json['file_type'],
      fileSize: json['file_size'],
      dateAdded: DateTime.parse(json['date_added']),
      expiryDate: json['expiry_date'] != null ? DateTime.parse(json['expiry_date']) : null,
      status: json['status'],
      description: json['description'] ?? '',
      tags: List<String>.from(json['tags'] ?? []),
      isAsset: json['is_asset'] ?? false,
      uploadedBy: json['uploaded_by'],
      isExpired: json['is_expired'] ?? false,
      isExpiringSoon: json['is_expiring_soon'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'file_path': filePath,
      'file_type': fileType,
      'file_size': fileSize,
      'date_added': dateAdded.toIso8601String(),
      'expiry_date': expiryDate?.toIso8601String(),
      'status': status,
      'description': description,
      'tags': tags,
      'is_asset': isAsset,
      'uploaded_by': uploadedBy,
      'is_expired': isExpired,
      'is_expiring_soon': isExpiringSoon,
    };
  }
}

// Category model class
class CategoryModel {
  final int id;
  final String name;
  final String displayName;
  final String? icon;
  final String? color;
  final String? description;
  final bool isActive;

  CategoryModel({
    required this.id,
    required this.name,
    required this.displayName,
    this.icon,
    this.color,
    this.description,
    required this.isActive,
  });

  factory CategoryModel.fromJson(Map<String, dynamic> json) {
    return CategoryModel(
      id: json['id'],
      name: json['name'],
      displayName: json['display_name'],
      icon: json['icon'],
      color: json['color'],
      description: json['description'],
      isActive: json['is_active'] ?? true,
    );
  }
}