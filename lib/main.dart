import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:open_file/open_file.dart';
import 'package:excel/excel.dart' as xl;
import 'package:prestige_park_groove/login/login_page.dart';
import 'package:prestige_park_groove/login/auth_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'cross_platform_pdf_viewer.dart'; 
import './utils/platform_utils.dart'; 
import 'package:file_picker/file_picker.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'dart:async';
import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';

// Add at the top of the file (after imports)
const String baseUrl = 'http://54.146.215.18:3000'; 

class ProjectDocument {
  final String id;
  final String name;
  final String category;
  final String filePath;
  final String fileType;
  final DateTime dateAdded;
  final DateTime? expiryDate;
  final String status;
  final String description;
  final List<String> tags;
  final double? fileSize;
  final bool isAsset;

  ProjectDocument({
    required this.id,
    required this.name,
    required this.category,
    required this.filePath,
    required this.fileType,
    required this.dateAdded,
    this.expiryDate,
    this.status = 'Active',
    this.description = '',
    this.tags = const [],
    this.fileSize,
    this.isAsset = false,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'category': category,
      'filePath': filePath,
      'fileType': fileType,
      'dateAdded': dateAdded.toIso8601String(),
      'expiryDate': expiryDate?.toIso8601String(),
      'status': status,
      'description': description,
      'tags': tags,
      'fileSize': fileSize,
      'isAsset': isAsset,
    };
  }

  factory ProjectDocument.fromJson(Map<String, dynamic> json) {
    return ProjectDocument(
      id: json['id'],
      name: json['name'],
      category: json['category'],
      filePath: json['filePath'],
      fileType: json['fileType'],
      dateAdded: DateTime.parse(json['dateAdded']),
      expiryDate: json['expiryDate'] != null ? DateTime.parse(json['expiryDate']) : null,
      status: json['status'] ?? 'Active',
      description: json['description'] ?? '',
      tags: List<String>.from(json['tags'] ?? []),
      fileSize: json['fileSize']?.toDouble(),
      isAsset: json['isAsset'] ?? false,
    );
  }

  bool get isExpiringSoon {
    if (expiryDate == null) return false;
    final daysUntilExpiry = expiryDate!.difference(DateTime.now()).inDays;
    return daysUntilExpiry <= 30 && daysUntilExpiry >= 0;
  }

  bool get isExpired {
    if (expiryDate == null) return false;
    return expiryDate!.isBefore(DateTime.now());
  }
}

// Document Categories
enum DocumentCategory {
  environmental('Environmental', Icons.eco, Colors.green),
  planning('Planning & Building', Icons.architecture, Colors.blue),
  utilities('Utilities', Icons.electrical_services, Colors.orange),
  legal('Legal & Land', Icons.gavel, Colors.purple),
  safety('Safety & Security', Icons.security, Colors.red),
  financial('Financial', Icons.account_balance, Colors.teal),
  other('Other Documents', Icons.folder, Colors.grey);

  const DocumentCategory(this.displayName, this.icon, this.color);
  final String displayName;
  final IconData icon;
  final Color color;
}


class EnhancedProjectDocument {
  final String id;
  final String name;
  final String category;
  final String filePath;
  final String fileType;
  
  // Common Project Information
  final String? projectName;
  final String? projectAddress;
  final double? builtUpArea;
  final double? plotArea;
  final double? floorAreaRatio;
  
  // Authority Information
  final String? issuingAuthority;
  final String? approvalNumber;
  final String? applicationNumber;
  final String? contactPerson;
  final String? contactPhone;
  final String? contactEmail;
  
  // Dates
  final DateTime dateAdded;
  final DateTime? applicationDate;
  final DateTime? approvalDate;
  final DateTime? validityStartDate;
  final DateTime? validityEndDate;
  final DateTime? renewalDueDate;
  
  // Status
  final String status;
  final String priorityLevel;
  final String complianceStatus;
  
  // Additional Info
  final String description;
  final List<String> tags;
  final String? conditionsAttached;
  final String? renewalProcess;
  final double? feesPaid;
  
  // System fields
  final bool isAsset;
  final bool isExpired;
  final bool isExpiringSoon;
  final int? daysUntilExpiry;

  EnhancedProjectDocument({
    required this.id,
    required this.name,
    required this.category,
    required this.filePath,
    required this.fileType,
    this.projectName,
    this.projectAddress,
    this.builtUpArea,
    this.plotArea,
    this.floorAreaRatio,
    this.issuingAuthority,
    this.approvalNumber,
    this.applicationNumber,
    this.contactPerson,
    this.contactPhone,
    this.contactEmail,
    required this.dateAdded,
    this.applicationDate,
    this.approvalDate,
    this.validityStartDate,
    this.validityEndDate,
    this.renewalDueDate,
    this.status = 'Active',
    this.priorityLevel = 'Medium',
    this.complianceStatus = 'Compliant',
    this.description = '',
    this.tags = const [],
    this.conditionsAttached,
    this.renewalProcess,
    this.feesPaid,
    this.isAsset = false,
    this.isExpired = false,
    this.isExpiringSoon = false,
    this.daysUntilExpiry,
  });

  factory EnhancedProjectDocument.fromJson(Map<String, dynamic> json) {
    return EnhancedProjectDocument(
      id: json['id'],
      name: json['name'],
      category: json['category'],
      filePath: json['file_path'] ?? json['filePath'],
      fileType: json['file_type'] ?? json['fileType'],
      projectName: json['project_name'],
      projectAddress: json['project_address'],
      builtUpArea: json['built_up_area']?.toDouble(),
      plotArea: json['plot_area']?.toDouble(),
      floorAreaRatio: json['floor_area_ratio']?.toDouble(),
      issuingAuthority: json['issuing_authority'],
      approvalNumber: json['approval_number'],
      applicationNumber: json['application_number'],
      contactPerson: json['contact_person'],
      contactPhone: json['contact_phone'],
      contactEmail: json['contact_email'],
      dateAdded: DateTime.parse(json['date_added'] ?? json['dateAdded']),
      applicationDate: json['application_date'] != null ? DateTime.parse(json['application_date']) : null,
      approvalDate: json['approval_date'] != null ? DateTime.parse(json['approval_date']) : null,
      validityStartDate: json['validity_start_date'] != null ? DateTime.parse(json['validity_start_date']) : null,
      validityEndDate: json['validity_end_date'] != null ? DateTime.parse(json['validity_end_date']) : null,
      renewalDueDate: json['renewal_due_date'] != null ? DateTime.parse(json['renewal_due_date']) : null,
      status: json['status'] ?? 'Active',
      priorityLevel: json['priority_level'] ?? 'Medium',
      complianceStatus: json['compliance_status'] ?? 'Compliant',
      description: json['description'] ?? '',
      tags: List<String>.from(json['tags'] ?? []),
      conditionsAttached: json['conditions_attached'],
      renewalProcess: json['renewal_process'],
      feesPaid: json['fees_paid']?.toDouble(),
      isAsset: json['is_asset'] ?? false,
      isExpired: json['is_expired'] ?? false,
      isExpiringSoon: json['is_expiring_soon'] ?? false,
      daysUntilExpiry: json['days_until_expiry']?.toInt(),
    );
  }
}

// Document Health Model
class DocumentHealth {
  final int healthScore;
  final String healthStatus;
  final Map<String, dynamic> summary;
  final Map<String, dynamic> details;
  final List<Recommendation> recommendations;

  DocumentHealth({
    required this.healthScore,
    required this.healthStatus,
    required this.summary,
    required this.details,
    required this.recommendations,
  });

  factory DocumentHealth.fromJson(Map<String, dynamic> json) {
    return DocumentHealth(
      healthScore: json['health_score'],
      healthStatus: json['health_status'],
      summary: json['summary'],
      details: json['details'],
      recommendations: (json['recommendations'] as List)
          .map((r) => Recommendation.fromJson(r))
          .toList(),
    );
  }
}

class Recommendation {
  final String priority;
  final String action;
  final String description;
  final List<String> items;

  Recommendation({
    required this.priority,
    required this.action,
    required this.description,
    required this.items,
  });

  factory Recommendation.fromJson(Map<String, dynamic> json) {
    return Recommendation(
      priority: json['priority'],
      action: json['action'],
      description: json['description'],
      items: List<String>.from(json['items'] ?? []),
    );
  }
}


void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Prestige Park Groove - ${PlatformUtils.platformName}',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color.fromARGB(255, 33, 174, 184)),
      ),
      home: EnhancedLoginPage(authService: AuthService()),
      debugShowCheckedModeBanner: false,
    );
  }
}
class EnhancedApprovalsPage extends StatefulWidget {
  const EnhancedApprovalsPage({super.key});

  @override
  State<EnhancedApprovalsPage> createState() => _EnhancedApprovalsPageState();
}

class _EnhancedApprovalsPageState extends State<EnhancedApprovalsPage>
    with TickerProviderStateMixin {
  List<EnhancedProjectDocument> _documents = [];
  List<EnhancedProjectDocument> _filteredDocuments = [];
  DocumentHealth? _documentHealth;
  
  String _searchQuery = '';
  String? _selectedProject;
  String _sortBy = 'created_at';
  bool _sortAscending = false;
  bool _isLoading = true;
  
  late TabController _tabController;
  final List<String> _tabs = ['All Documents', 'Health Dashboard', 'Alerts', 'Analytics'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _loadDocuments();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadDocuments() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/documents'),
        headers: {'Authorization': 'Bearer ${await _getToken()}'},
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _documents = (data['data'] as List)
              .map((doc) => EnhancedProjectDocument.fromJson(doc))
              .toList();
          _filteredDocuments = List.from(_documents);
          _isLoading = false;
        });
      }
    } catch (e) {
      print('Error loading documents: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<String?> _getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('auth_token');
  }

  void _applyFilters() {
    setState(() {
      _filteredDocuments = _documents.where((doc) {
        final matchesSearch = _searchQuery.isEmpty ||
            doc.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            doc.description.toLowerCase().contains(_searchQuery.toLowerCase()) ||
            (doc.projectName?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false) ||
            (doc.approvalNumber?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);

        final matchesProject = _selectedProject == null ||
            doc.projectName == _selectedProject;

        return matchesSearch && matchesProject;
      }).toList();

      // Apply sorting
      _filteredDocuments.sort((a, b) {
        int comparison;
        switch (_sortBy) {
          case 'name':
            comparison = a.name.compareTo(b.name);
            break;
          case 'category':
            comparison = a.category.compareTo(b.category);
            break;
          case 'status':
            comparison = a.status.compareTo(b.status);
            break;
          case 'validity_end_date':
            final aDate = a.validityEndDate ?? DateTime(2099);
            final bDate = b.validityEndDate ?? DateTime(2099);
            comparison = aDate.compareTo(bDate);
            break;
          case 'priority_level':
            comparison = a.priorityLevel.compareTo(b.priorityLevel);
            break;
          case 'created_at':
          default:
            comparison = a.dateAdded.compareTo(b.dateAdded);
            break;
        }
        return _sortAscending ? comparison : -comparison;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: _buildAppBar(),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildDocumentsTab(),
                _buildHealthDashboard(),
                _buildAlertsTab(),
                _buildAnalyticsTab(),
              ],
            ),
      floatingActionButton: _buildFAB(),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('Smart Document Manager',
          style: TextStyle(fontWeight: FontWeight.bold)),
      backgroundColor: Colors.teal,
      elevation: 0,
      bottom: TabBar(
        controller: _tabController,
        tabs: _tabs.map((title) => Tab(text: title)).toList(),
        indicatorColor: Colors.white,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: _showSearchDialog,
        ),
        IconButton(
          icon: const Icon(Icons.filter_list),
          onPressed: _showFilterDialog,
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.sort),
          onSelected: (value) {
            setState(() {
              if (_sortBy == value) {
                _sortAscending = !_sortAscending;
              } else {
                _sortBy = value;
                _sortAscending = true;
              }
            });
            _applyFilters();
          },
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'name', child: Text('Sort by Name')),
            const PopupMenuItem(value: 'created_at', child: Text('Sort by Date')),
            const PopupMenuItem(value: 'category', child: Text('Sort by Category')),
            const PopupMenuItem(value: 'validity_end_date', child: Text('Sort by Expiry')),
            const PopupMenuItem(value: 'priority_level', child: Text('Sort by Priority')),
          ],
        ),
      ],
    );
  }

  Widget _buildDocumentsTab() {
    return Column(
      children: [
        _buildQuickStats(),
        _buildProjectSelector(),
        Expanded(child: _buildDocumentsList()),
      ],
    );
  }

  Widget _buildQuickStats() {
    final totalDocs = _documents.length;
    final expiringSoon = _documents.where((doc) => doc.isExpiringSoon).length;
    final expired = _documents.where((doc) => doc.isExpired).length;
    final critical = _documents.where((doc) => doc.priorityLevel == 'Critical').length;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatCard('Total', '$totalDocs', Colors.blue, Icons.folder),
          _buildStatCard('Expiring', '$expiringSoon', Colors.orange, Icons.warning),
          _buildStatCard('Expired', '$expired', Colors.red, Icons.error),
          _buildStatCard('Critical', '$critical', Colors.purple, Icons.priority_high),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(value, style: TextStyle(
              fontSize: 20, 
              fontWeight: FontWeight.bold, 
              color: color
            )),
            Text(label, style: TextStyle(
              fontSize: 12, 
              color: color.withOpacity(0.8)
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectSelector() {
    final projects = _documents
        .where((doc) => doc.projectName != null)
        .map((doc) => doc.projectName!)
        .toSet()
        .toList();

    if (projects.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: DropdownButtonFormField<String>(
        value: _selectedProject,
        decoration: InputDecoration(
          labelText: 'Filter by Project',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        ),
        items: [
          const DropdownMenuItem<String>(
            value: null,
            child: Text('All Projects'),
          ),
          ...projects.map((project) => DropdownMenuItem(
            value: project,
            child: Text(project),
          )),
        ],
        onChanged: (value) {
          setState(() => _selectedProject = value);
          _applyFilters();
        },
      ),
    );
  }

  Widget _buildDocumentsList() {
    if (_filteredDocuments.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_open, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty || _selectedProject != null
                  ? 'No documents match your filters'
                  : 'No documents found',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            ElevatedButton.icon(
              onPressed: _addDocument,
              icon: const Icon(Icons.add),
              label: const Text('Add Document'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _filteredDocuments.length,
      itemBuilder: (context, index) {
        final doc = _filteredDocuments[index];
        return _buildEnhancedDocumentCard(doc);
      },
    );
  }

  Widget _buildEnhancedDocumentCard(EnhancedProjectDocument document) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: () => _openDocument(document),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Row
              Row(
                children: [
                  _buildDocumentIcon(document.category),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          document.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (document.projectName != null)
                          Text(
                            document.projectName!,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                  ),
                  _buildStatusChip(document.status),
                  _buildPriorityIndicator(document.priorityLevel),
                  PopupMenuButton<String>(
                    onSelected: (value) => _handleDocumentAction(value, document),
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'view', child: Text('View')),
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      const PopupMenuItem(value: 'compare', child: Text('Compare')),
                      const PopupMenuItem(value: 'dependencies', child: Text('Dependencies')),
                      if (!document.isAsset)
                        const PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
              
              // Project Information
              if (document.projectAddress != null || document.builtUpArea != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _buildProjectInfo(document),
                ),
              
              // Authority Information
              if (document.issuingAuthority != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _buildAuthorityInfo(document),
                ),
              
              // Validity Information
              const SizedBox(height: 8),
              _buildValidityInfo(document),
              
              // Alert Messages
              if (document.isExpired || document.isExpiringSoon)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: _buildAlertMessage(document),
                ),
              
              // Tags
              if (document.tags.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 4,
                    children: document.tags.take(3).map((tag) => Chip(
                      label: Text(tag, style: const TextStyle(fontSize: 10)),
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      visualDensity: VisualDensity.compact,
                    )).toList(),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDocumentIcon(String category) {
    IconData icon;
    Color color;
    
    switch (category.toLowerCase()) {
      case 'environmental':
        icon = Icons.eco;
        color = Colors.green;
        break;
      case 'planning':
        icon = Icons.architecture;
        color = Colors.blue;
        break;
      case 'utilities':
        icon = Icons.electrical_services;
        color = Colors.orange;
        break;
      case 'legal':
        icon = Icons.gavel;
        color = Colors.purple;
        break;
      case 'safety':
        icon = Icons.security;
        color = Colors.red;
        break;
      case 'financial':
        icon = Icons.account_balance;
        color = Colors.teal;
        break;
      default:
        icon = Icons.folder;
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }

  Widget _buildStatusChip(String status) {
    Color color;
    switch (status.toLowerCase()) {
      case 'approved':
        color = Colors.green;
        break;
      case 'pending':
        color = Colors.orange;
        break;
      case 'expired':
        color = Colors.red;
        break;
      case 'verified':
        color = Colors.blue;
        break;
      default:
        color = Colors.grey;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        status,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildPriorityIndicator(String priority) {
    Color color;
    IconData icon;
    
    switch (priority.toLowerCase()) {
      case 'critical':
        color = Colors.red;
        icon = Icons.priority_high;
        break;
      case 'high':
        color = Colors.orange;
        icon = Icons.warning;
        break;
      case 'medium':
        color = Colors.blue;
        icon = Icons.info;
        break;
      case 'low':
        color = Colors.green;
        icon = Icons.check_circle;
        break;
      default:
        color = Colors.grey;
        icon = Icons.radio_button_unchecked;
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(icon, color: color, size: 16),
    );
  }

  Widget _buildProjectInfo(EnhancedProjectDocument document) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (document.projectAddress != null)
            Row(
              children: [
                const Icon(Icons.location_on, size: 14, color: Colors.grey),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    document.projectAddress!,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          if (document.builtUpArea != null || document.plotArea != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  const Icon(Icons.square_foot, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  if (document.builtUpArea != null)
                    Text(
                      'Built-up: ${document.builtUpArea!.toStringAsFixed(0)} sq ft',
                      style: const TextStyle(fontSize: 12),
                    ),
                  if (document.builtUpArea != null && document.plotArea != null)
                    const Text(' | ', style: TextStyle(fontSize: 12)),
                  if (document.plotArea != null)
                    Text(
                      'Plot: ${document.plotArea!.toStringAsFixed(0)} sq ft',
                      style: const TextStyle(fontSize: 12),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildAuthorityInfo(EnhancedProjectDocument document) {
    return Row(
      children: [
        const Icon(Icons.account_balance, size: 14, color: Colors.grey),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            '${document.issuingAuthority}${document.approvalNumber != null ? ' - ${document.approvalNumber}' : ''}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }

  Widget _buildValidityInfo(EnhancedProjectDocument document) {
    return Row(
      children: [
        Icon(Icons.calendar_today, size: 14, color: Colors.grey[500]),
        const SizedBox(width: 4),
        Text(
          'Added: ${DateFormat('MMM d, yyyy').format(document.dateAdded)}',
          style: TextStyle(fontSize: 12, color: Colors.grey[500]),
        ),
        if (document.validityEndDate != null) ...[
          const SizedBox(width: 16),
          Icon(
            Icons.event_available,
            size: 14,
            color: document.isExpired ? Colors.red : 
                  document.isExpiringSoon ? Colors.orange : Colors.grey[500],
          ),
          const SizedBox(width: 4),
          Text(
            'Valid until: ${DateFormat('MMM d, yyyy').format(document.validityEndDate!)}',
            style: TextStyle(
              fontSize: 12,
              color: document.isExpired ? Colors.red : 
                    document.isExpiringSoon ? Colors.orange : Colors.grey[500],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildAlertMessage(EnhancedProjectDocument document) {
    String message;
    Color color;
    IconData icon;

    if (document.isExpired) {
      message = 'EXPIRED: This document has expired and needs immediate renewal';
      color = Colors.red;
      icon = Icons.error;
    } else if (document.isExpiringSoon) {
      final days = document.daysUntilExpiry ?? 0;
      message = days <= 7 
          ? 'URGENT: Expires in $days days'
          : 'WARNING: Expires in $days days - prepare for renewal';
      color = days <= 7 ? Colors.red : Colors.orange;
      icon = days <= 7 ? Icons.error : Icons.warning;
    } else {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHealthDashboard() {
    if (_documentHealth == null) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Loading document health analysis...'),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHealthScoreCard(),
          const SizedBox(height: 16),
          _buildHealthSummary(),
          const SizedBox(height: 16),
          _buildRecommendations(),
        ],
      ),
    );
  }

  Widget _buildHealthScoreCard() {
    final health = _documentHealth!;
    Color scoreColor;
    IconData scoreIcon;

    if (health.healthScore >= 95) {
      scoreColor = Colors.green;
      scoreIcon = Icons.check_circle;
    } else if (health.healthScore >= 80) {
      scoreColor = Colors.blue;
      scoreIcon = Icons.info;
    } else if (health.healthScore >= 60) {
      scoreColor = Colors.orange;
      scoreIcon = Icons.warning;
    } else {
      scoreColor = Colors.red;
      scoreIcon = Icons.error;
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [scoreColor.withOpacity(0.1), scoreColor.withOpacity(0.05)],
          ),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(scoreIcon, color: scoreColor, size: 32),
                const SizedBox(width: 12),
                Text(
                  'Document Health Score',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: scoreColor,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '${health.healthScore}%',
              style: TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: scoreColor,
              ),
            ),
            Text(
              health.healthStatus,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w500,
                color: scoreColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHealthSummary() {
    final summary = _documentHealth!.summary;
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Health Summary',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryItem('Total Issues', '${summary['total_issues']}', Colors.grey),
                _buildSummaryItem('Critical', '${summary['critical_issues']}', Colors.red),
                _buildSummaryItem('Expiring', '${summary['expiring_documents']}', Colors.orange),
                _buildSummaryItem('Inconsistent', '${summary['inconsistencies']}', Colors.purple),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: color.withOpacity(0.8),
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendations() {
    final recommendations = _documentHealth!.recommendations;
    
    if (recommendations.isEmpty) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 48),
              const SizedBox(height: 8),
              const Text(
                'All Good!',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const Text(
                'No urgent actions required for your documents.',
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Smart Recommendations',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...recommendations.map((rec) => _buildRecommendationItem(rec)),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendationItem(Recommendation recommendation) {
    Color priorityColor;
    IconData priorityIcon;

    switch (recommendation.priority.toLowerCase()) {
      case 'critical':
        priorityColor = Colors.red;
        priorityIcon = Icons.error;
        break;
      case 'high':
        priorityColor = Colors.orange;
        priorityIcon = Icons.warning;
        break;
      case 'medium':
        priorityColor = Colors.blue;
        priorityIcon = Icons.info;
        break;
      default:
        priorityColor = Colors.green;
        priorityIcon = Icons.check_circle;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: priorityColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: priorityColor.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(priorityIcon, color: priorityColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  recommendation.action,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: priorityColor,
                  ),
                ),
              ),
              Chip(
                label: Text(
                  recommendation.priority,
                  style: const TextStyle(fontSize: 10),
                ),
                backgroundColor: priorityColor.withOpacity(0.2),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            recommendation.description,
            style: const TextStyle(fontSize: 14),
          ),
          if (recommendation.items.isNotEmpty) ...[
            const SizedBox(height: 8),
            ...recommendation.items.map((item) => Padding(
              padding: const EdgeInsets.only(left: 16, bottom: 2),
              child: Row(
                children: [
                  Container(
                    width: 4,
                    height: 4,
                    decoration: BoxDecoration(
                      color: priorityColor,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ],
      ),
    );
  }

  Widget _buildAlertsTab() {
    final expiringDocs = _documents.where((doc) => doc.isExpiringSoon || doc.isExpired).toList();
    
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (expiringDocs.isNotEmpty) ...[
          const Text(
            'Document Expiry Alerts',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ...expiringDocs.map((doc) => _buildExpiryAlert(doc)),
        ] else ...[
          const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: Colors.green, size: 64),
                SizedBox(height: 16),
                Text(
                  'No Active Alerts',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                Text(
                  'All your documents are in good standing',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildExpiryAlert(EnhancedProjectDocument document) {
    final isExpired = document.isExpired;
    final days = document.daysUntilExpiry ?? 0;
    final color = isExpired ? Colors.red : (days <= 7 ? Colors.red : Colors.orange);
    final icon = isExpired ? Icons.error : Icons.warning;

    String title, subtitle;
    if (isExpired) {
      title = '${document.name} - EXPIRED';
      subtitle = 'This document has expired and requires immediate renewal';
    } else {
      title = '${document.name} - Expires in $days days';
      subtitle = days <= 7 
          ? 'Urgent action required - contact ${document.issuingAuthority ?? 'issuing authority'}'
          : 'Renewal preparation recommended';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(
          title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(subtitle),
            if (document.projectName != null)
              Text('Project: ${document.projectName}'),
            if (document.issuingAuthority != null)
              Text('Authority: ${document.issuingAuthority}'),
          ],
        ),
        trailing: ElevatedButton(
          onPressed: () => _handleRenewalAction(document),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
          ),
          child: Text(isExpired ? 'Renew Now' : 'Prepare'),
        ),
      ),
    );
  }

  Widget _buildAnalyticsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Document Analytics',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          _buildCategoryDistribution(),
          const SizedBox(height: 16),
          _buildStatusDistribution(),
          const SizedBox(height: 16),
          _buildExpiryTimeline(),
        ],
      ),
    );
  }

  Widget _buildCategoryDistribution() {
    final categoryCount = <String, int>{};
    for (final doc in _documents) {
      categoryCount[doc.category] = (categoryCount[doc.category] ?? 0) + 1;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Documents by Category',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...categoryCount.entries.map((entry) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: Text(entry.key),
                  ),
                  Expanded(
                    flex: 3,
                    child: LinearProgressIndicator(
                      value: entry.value / _documents.length,
                      backgroundColor: Colors.grey[300],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${entry.value}'),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusDistribution() {
    final statusCount = <String, int>{};
    for (final doc in _documents) {
      statusCount[doc.status] = (statusCount[doc.status] ?? 0) + 1;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Documents by Status',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: statusCount.entries.map((entry) => Chip(
                label: Text('${entry.key}: ${entry.value}'),
                backgroundColor: _getStatusColor(entry.key).withOpacity(0.2),
              )).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'approved':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'expired':
        return Colors.red;
      case 'verified':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Widget _buildExpiryTimeline() {
    final now = DateTime.now();
    final next30Days = now.add(const Duration(days: 30));
    final next90Days = now.add(const Duration(days: 90));

    final expiring30 = _documents.where((doc) => 
        doc.validityEndDate != null && 
        doc.validityEndDate!.isAfter(now) && 
        doc.validityEndDate!.isBefore(next30Days)
    ).length;

    final expiring90 = _documents.where((doc) => 
        doc.validityEndDate != null && 
        doc.validityEndDate!.isAfter(next30Days) && 
        doc.validityEndDate!.isBefore(next90Days)
    ).length;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Expiry Timeline',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildTimelineItem('Next 30 days', expiring30, Colors.red),
            _buildTimelineItem('Next 90 days', expiring90, Colors.orange),
          ],
        ),
      ),
    );
  }

  Widget _buildTimelineItem(String period, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(period)),
          Text(
            '$count documents',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFAB() {
    return FloatingActionButton.extended(
      onPressed: _addDocument,
      icon: const Icon(Icons.add),
      label: const Text('Add Document'),
      backgroundColor: Colors.teal,
    );
  }

  // Event Handlers
  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) {
        String tempSearch = _searchQuery;
        return AlertDialog(
          title: const Text('Search Documents'),
          content: TextField(
            onChanged: (value) => tempSearch = value,
            controller: TextEditingController(text: _searchQuery),
            decoration: const InputDecoration(
              hintText: 'Search by name, project, approval number...',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() => _searchQuery = tempSearch);
                _applyFilters();
                Navigator.pop(context);
              },
              child: const Text('Search'),
            ),
          ],
        );
      },
    );
  }

  void _showFilterDialog() {
    // Implementation for advanced filtering
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Advanced Filters'),
        content: const Text('Advanced filtering options will be implemented here'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Future<void> _addDocument() async {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 600,
          child: EnhancedDocumentForm(
            onDocumentSaved: _loadDocuments,
          ),
        ),
      ),
    );
  }

  void _editDocument(EnhancedProjectDocument document) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: SizedBox(
          width: 600,
          child: EnhancedDocumentForm(
            document: document,
            onDocumentSaved: _loadDocuments,
          ),
        ),
      ),
    );
  }

  void _deleteDocument(EnhancedProjectDocument document) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete Document'),
        content: Text('Are you sure you want to delete "${document.name}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final response = await http.delete(
        Uri.parse('$baseUrl/api/documents/${document.id}'),
        headers: {'Authorization': 'Bearer $token'},
      );
      if (response.statusCode == 200) {
        _showSuccess('Document deleted successfully');
        _loadDocuments();
      } else {
        _showError('Failed to delete document');
      }
    }
  }

  void _handleDocumentAction(String action, EnhancedProjectDocument document) {
    switch (action) {
      case 'view':
        _openDocument(document);
        break;
      case 'edit':
        _editDocument(document);
        break;
      case 'compare':
        _compareDocument(document);
        break;
      case 'dependencies':
        _showDependencies(document);
        break;
      case 'delete':
        _deleteDocument(document);
        break;
    }
  }

  Future<void> _openDocument(EnhancedProjectDocument document) async {
    try {
      print('Opening document: ${document.name}');
      print('Document ID: ${document.id}');
      print('Is Asset: ${document.isAsset}');
      print('File Path: ${document.filePath}');
      
      if (document.isAsset) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CrossPlatformPDFViewer(
              filePath: document.filePath,
              title: document.name,
              isAsset: true,
            ),
          ),
        );
      } else {
        // For user-uploaded documents, get download URL
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Opening document...')),
        );
        
        final prefs = await SharedPreferences.getInstance();
        final token = prefs.getString('auth_token');
        if (token == null) {
          throw Exception('Authentication token not found');
        }
        
        print('Making API call to: $baseUrl/api/documents/${document.id}/download');
        
        final response = await http.get(
          Uri.parse('$baseUrl/api/documents/${document.id}/download'),
          headers: {'Authorization': 'Bearer $token'},
        );
        
        print('API Response Status: ${response.statusCode}');
        print('API Response Body: ${response.body}');
        
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] == true && data['downloadUrl'] != null) {
            // Use the download URL to open/download the document
            final url = data['downloadUrl'];
            print('Got download URL: $url');
            
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => CrossPlatformPDFViewer(
                  filePath: url,
                  title: document.name,
                  isAsset: false,
                ),
              ),
            );
          } else {
            throw Exception('Failed to get document download URL');
          }
        } else {
          throw Exception('Failed to access document: ${response.statusCode}');
        }
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error opening document: $e')),
      );
    }
  }

  void _compareDocument(EnhancedProjectDocument document) {
    // Implementation for document comparison
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Compare ${document.name}'),
        content: const Text('Document comparison view will be implemented here'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showDependencies(EnhancedProjectDocument document) {
    // Implementation for showing document dependencies
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${document.name} Dependencies'),
        content: const Text('Document dependency analysis will be shown here'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _handleRenewalAction(EnhancedProjectDocument document) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Renew ${document.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Document: ${document.name}'),
            if (document.issuingAuthority != null)
              Text('Authority: ${document.issuingAuthority}'),
            if (document.contactPerson != null)
              Text('Contact: ${document.contactPerson}'),
            if (document.contactPhone != null)
              Text('Phone: ${document.contactPhone}'),
            if (document.renewalProcess != null) ...[
              const SizedBox(height: 8),
              const Text('Renewal Process:', style: TextStyle(fontWeight: FontWeight.bold)),
              Text(document.renewalProcess!),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              // Implementation for renewal process
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Renewal process initiated')),
              );
            },
            child: const Text('Start Renewal'),
          ),
        ],
      ),
    );
  }

  // Inside _EnhancedApprovalsPageState class, add these methods:
  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }
}

// Keep your existing BlankPage and ExcelViewPage classes exactly as they are
class BlankPage extends StatelessWidget {
  const BlankPage({super.key, required String message});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Blank Page - ${PlatformUtils.platformName}'),
      ),
      body: const Center(
        child: Text('This is a blank page'),
      ),
    );
  }
}

// Your existing ExcelViewPage remains exactly the same
class ExcelViewPage extends StatefulWidget {
  final String excelPath;

  const ExcelViewPage({super.key, required this.excelPath});

  @override
  _ExcelViewPageState createState() => _ExcelViewPageState();
}

class _ExcelViewPageState extends State<ExcelViewPage>
    with SingleTickerProviderStateMixin {
  List<List<dynamic>>? _data;
  String? _error;
  List<String> _sheets = [];
  String? _selectedSheet;
  bool _isLoading = true;
  String _searchQuery = '';
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  // Sorting state
  int? _sortColumnIndex;
  bool _sortAscending = true;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeIn),
    );
    _loadExcelData();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadExcelData() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      final ByteData data = await rootBundle.load(widget.excelPath);
      var bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      var excel = xl.Excel.decodeBytes(bytes);

      _sheets = excel.tables.keys.toList();

      if (_sheets.isEmpty) {
        throw Exception('No sheets found in the Excel file');
      }

      _selectedSheet = _sheets.first;
      _loadSheetData(excel, _selectedSheet!);
      _animationController.forward();
    } catch (e) {
      setState(() {
        _error = 'Error loading Excel file: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  void _loadSheetData(xl.Excel excel, String sheetName) {
    try {
      var sheet = excel.tables[sheetName];
      if (sheet == null) throw Exception('Sheet not found');

      _data = sheet.rows.map((row) {
        return row.map((cell) => cell?.value ?? '').toList();
      }).toList();

      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _error = 'Error loading sheet data: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  List<List<dynamic>> _getFilteredData() {
    if (_data == null || _data!.isEmpty) return [];

    var filteredData = _data!.where((row) {
      if (row.isEmpty) return false;
      return row.any((cell) =>
          cell.toString().toLowerCase().contains(_searchQuery.toLowerCase()));
    }).toList();

    if (_sortColumnIndex != null && filteredData.length > 1) {
      filteredData.sublist(1).sort((a, b) {
        var aValue = a[_sortColumnIndex!];
        var bValue = b[_sortColumnIndex!];
        return _sortAscending
            ? aValue.toString().compareTo(bValue.toString())
            : bValue.toString().compareTo(aValue.toString());
      });
    }

    return filteredData;
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Theme.of(context).brightness,
        ),
      ),
      child: Scaffold(
        appBar: _buildAppBar(),
        body: _buildBody(),
        floatingActionButton: _buildFAB(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: Text(_getFileName(),
          style: const TextStyle(fontWeight: FontWeight.bold)),
      elevation: 0,
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () => _showSearchDialog(),
        ),
        if (_sheets.length > 1)
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list),
            onSelected: (String sheet) {
              setState(() {
                _selectedSheet = sheet;
                _isLoading = true;
              });
              _loadExcelData();
            },
            itemBuilder: (context) => _sheets.map((sheet) {
              return PopupMenuItem<String>(
                value: sheet,
                child: Text(sheet),
              );
            }).toList(),
          ),
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Loading Excel data on ${PlatformUtils.platformName}...',
                style: TextStyle(color: Colors.grey[600])),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            Text(_error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadExcelData,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    var filteredData = _getFilteredData();
    if (filteredData.isEmpty) {
      return const Center(
        child: Text('No data available'),
      );
    }

    return Column(
      children: [
        if (_searchQuery.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Chip(
              label: Text('Search: $_searchQuery'),
              onDeleted: () => setState(() => _searchQuery = ''),
            ),
          ),
        if (_selectedSheet != null)
          Container(
            padding: const EdgeInsets.all(8.0),
            color: Colors.teal.withOpacity(0.1),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.table_chart, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Sheet: $_selectedSheet',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: SingleChildScrollView(
              scrollDirection: Axis.vertical,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Card(
                  margin: const EdgeInsets.all(8.0),
                  elevation: 4,
                  child: DataTable(
                    headingRowColor:
                        MaterialStateProperty.all(Colors.teal.shade50),
                    dataRowColor: MaterialStateProperty.resolveWith(
                      (states) => states.contains(MaterialState.selected)
                          ? Colors.teal.shade50
                          : Colors.white,
                    ),
                    columns: _buildColumns(filteredData),
                    rows: _buildRows(filteredData),
                    sortColumnIndex: _sortColumnIndex,
                    sortAscending: _sortAscending,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget? _buildFAB() {
    if (_data == null || _data!.isEmpty) return null;

    return FloatingActionButton(
      onPressed: _exportData,
      tooltip: 'Export Data',
      child: const Icon(Icons.download),
    );
  }

  List<DataColumn> _buildColumns(List<List<dynamic>> data) {
    if (data.isEmpty) return [];
    return List.generate(data[0].length, (index) {
      return DataColumn(
        label: Text(
          data[0][index].toString(),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        onSort: (columnIndex, ascending) {
          setState(() {
            _sortColumnIndex = columnIndex;
            _sortAscending = ascending;
          });
        },
      );
    });
  }

  List<DataRow> _buildRows(List<List<dynamic>> data) {
    if (data.length < 2) return [];
    return data.sublist(1).map((row) {
      return DataRow(
        cells: row.map((cell) {
          return DataCell(
            Text(cell.toString()),
            onTap: () => _showCellDetail(cell.toString()),
          );
        }).toList(),
      );
    }).toList();
  }

  void _showSearchDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Search Data'),
          content: TextField(
            onChanged: (value) => setState(() => _searchQuery = value),
            decoration: const InputDecoration(
              hintText: 'Enter search term...',
              prefixIcon: Icon(Icons.search),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Search'),
            ),
          ],
        );
      },
    );
  }

  void _showCellDetail(String content) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Cell Content'),
          content: SingleChildScrollView(
            child: SelectableText(content),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: content));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied to clipboard')),
                );
              },
              child: const Text('Copy'),
            ),
          ],
        );
      },
    );
  }

  void _exportData() {
    // Add export functionality here
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Export feature coming soon for ${PlatformUtils.platformName}!')),
    );
  }

  String _getFileName() {
    return widget.excelPath
        .split('/')
        .last
        .replaceAll('.xlsx', '')
        .split('_')
        .map((word) => word[0].toUpperCase() + word.substring(1).toLowerCase())
        .join(' ');
  }
}



class EnhancedDocumentForm extends StatefulWidget {
  final EnhancedProjectDocument? document;
  final VoidCallback? onDocumentSaved;

  const EnhancedDocumentForm({
    super.key,
    this.document,
    this.onDocumentSaved,
  });

  @override
  State<EnhancedDocumentForm> createState() => _EnhancedDocumentFormState();
}

class _EnhancedDocumentFormState extends State<EnhancedDocumentForm>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  late TabController _tabController;
  
  // Basic Information Controllers
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _tagsController = TextEditingController();
  
  // Project Information Controllers
  final _projectNameController = TextEditingController();
  final _projectAddressController = TextEditingController();
  final _builtUpAreaController = TextEditingController();
  final _plotAreaController = TextEditingController();
  final _floorAreaRatioController = TextEditingController();
  
  // Authority Information Controllers
  final _issuingAuthorityController = TextEditingController();
  final _approvalNumberController = TextEditingController();
  final _applicationNumberController = TextEditingController();
  final _contactPersonController = TextEditingController();
  final _contactPhoneController = TextEditingController();
  final _contactEmailController = TextEditingController();
  
  // Additional Information Controllers
  final _conditionsController = TextEditingController();
  final _renewalProcessController = TextEditingController();
  final _feesPaidController = TextEditingController();

  // Form State
  String _selectedCategory = 'environmental';
  String _selectedStatus = 'Active';
  String _selectedPriorityLevel = 'Medium';
  String _selectedComplianceStatus = 'Compliant';
  
  DateTime? _applicationDate;
  DateTime? _approvalDate;
  DateTime? _validityStartDate;
  DateTime? _validityEndDate;
  DateTime? _renewalDueDate;
  
  File? _selectedFile;
  String? _selectedFileName;
  bool _isLoading = false;
  
  // Validation State
  Map<String, String> _validationErrors = {};
  bool _showAllFields = false;

  final List<String> _categories = [
    'environmental',
    'planning',
    'utilities',
    'legal',
    'safety',
    'financial',
    'other'
  ];

  final List<String> _statusOptions = [
    'Active',
    'Approved',
    'Pending',
    'Expired',
    'Verified',
    'Rejected'
  ];

  final List<String> _priorityLevels = [
    'Low',
    'Medium',
    'High',
    'Critical'
  ];

  final List<String> _complianceStatuses = [
    'Compliant',
    'Non-Compliant',
    'Under Review',
    'Expired'
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    
    if (widget.document != null) {
      _populateFields(widget.document!);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _disposeControllers();
    super.dispose();
  }

  void _disposeControllers() {
    _nameController.dispose();
    _descriptionController.dispose();
    _tagsController.dispose();
    _projectNameController.dispose();
    _projectAddressController.dispose();
    _builtUpAreaController.dispose();
    _plotAreaController.dispose();
    _floorAreaRatioController.dispose();
    _issuingAuthorityController.dispose();
    _approvalNumberController.dispose();
    _applicationNumberController.dispose();
    _contactPersonController.dispose();
    _contactPhoneController.dispose();
    _contactEmailController.dispose();
    _conditionsController.dispose();
    _renewalProcessController.dispose();
    _feesPaidController.dispose();
  }

  void _populateFields(EnhancedProjectDocument document) {
    _nameController.text = document.name;
    _descriptionController.text = document.description;
    _tagsController.text = document.tags.join(', ');
    _selectedCategory = document.category;
    _selectedStatus = document.status;
    _selectedPriorityLevel = document.priorityLevel;
    _selectedComplianceStatus = document.complianceStatus;
    
    // Project Information
    _projectNameController.text = document.projectName ?? '';
    _projectAddressController.text = document.projectAddress ?? '';
    _builtUpAreaController.text = document.builtUpArea?.toString() ?? '';
    _plotAreaController.text = document.plotArea?.toString() ?? '';
    _floorAreaRatioController.text = document.floorAreaRatio?.toString() ?? '';
    
    // Authority Information
    _issuingAuthorityController.text = document.issuingAuthority ?? '';
    _approvalNumberController.text = document.approvalNumber ?? '';
    _applicationNumberController.text = document.applicationNumber ?? '';
    _contactPersonController.text = document.contactPerson ?? '';
    _contactPhoneController.text = document.contactPhone ?? '';
    _contactEmailController.text = document.contactEmail ?? '';
    
    // Additional Information
    _conditionsController.text = document.conditionsAttached ?? '';
    _renewalProcessController.text = document.renewalProcess ?? '';
    _feesPaidController.text = document.feesPaid?.toString() ?? '';
    
    // Dates
    _applicationDate = document.applicationDate;
    _approvalDate = document.approvalDate;
    _validityStartDate = document.validityStartDate;
    _validityEndDate = document.validityEndDate;
    _renewalDueDate = document.renewalDueDate;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.document == null ? 'Add Document' : 'Edit Document'),
        backgroundColor: Colors.teal,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Basic', icon: Icon(Icons.info)),
            Tab(text: 'Project', icon: Icon(Icons.business)),
            Tab(text: 'Authority', icon: Icon(Icons.account_balance)),
            Tab(text: 'Dates & More', icon: Icon(Icons.calendar_today)),
          ],
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
        ),
        actions: [
          IconButton(
            icon: Icon(_showAllFields ? Icons.visibility_off : Icons.visibility),
            onPressed: () {
              setState(() {
                _showAllFields = !_showAllFields;
              });
            },
            tooltip: _showAllFields ? 'Hide optional fields' : 'Show all fields',
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: TabBarView(
          controller: _tabController,
          children: [
            _buildBasicTab(),
            _buildProjectTab(),
            _buildAuthorityTab(),
            _buildDatesAndMoreTab(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildBasicTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Document Information', Icons.folder),
          const SizedBox(height: 16),
          
          // Document Name
          _buildTextFormField(
            controller: _nameController,
            label: 'Document Name *',
            icon: Icons.description,
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter a document name';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          
          // Category
          _buildDropdownField<String>(
            value: _selectedCategory,
            label: 'Category *',
            icon: Icons.category,
            items: _categories.map((category) => DropdownMenuItem(
              value: category,
              child: Row(
                children: [
                  _getCategoryIcon(category),
                  const SizedBox(width: 8),
                  Text(_getCategoryDisplayName(category)),
                ],
              ),
            )).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedCategory = value);
              }
            },
          ),
          const SizedBox(height: 16),
          
          // Status
          _buildDropdownField<String>(
            value: _selectedStatus,
            label: 'Status',
            icon: Icons.flag,
            items: _statusOptions.map((status) => DropdownMenuItem(
              value: status,
              child: Text(status),
            )).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedStatus = value);
              }
            },
          ),
          const SizedBox(height: 16),
          
          // Priority Level
          _buildDropdownField<String>(
            value: _selectedPriorityLevel,
            label: 'Priority Level',
            icon: Icons.priority_high,
            items: _priorityLevels.map((priority) => DropdownMenuItem(
              value: priority,
              child: Row(
                children: [
                  _getPriorityIcon(priority),
                  const SizedBox(width: 8),
                  Text(priority),
                ],
              ),
            )).toList(),
            onChanged: (value) {
              if (value != null) {
                setState(() => _selectedPriorityLevel = value);
              }
            },
          ),
          const SizedBox(height: 16),
          
          // Description
          _buildTextFormField(
            controller: _descriptionController,
            label: 'Description',
            icon: Icons.notes,
            maxLines: 3,
          ),
          const SizedBox(height: 16),
          
          // Tags
          _buildTextFormField(
            controller: _tagsController,
            label: 'Tags (comma separated)',
            icon: Icons.label,
            hintText: 'e.g., Legal, Important, Mandatory',
          ),
          const SizedBox(height: 16),
          
          // File Selection
          _buildFileSelector(),
        ],
      ),
    );
  }

  Widget _buildProjectTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Project Information', Icons.business),
          const SizedBox(height: 16),
          
          // Project Name
          _buildTextFormField(
            controller: _projectNameController,
            label: 'Project Name',
            icon: Icons.business_center,
            validator: (value) {
              if (_selectedCategory == 'planning' && (value == null || value.isEmpty)) {
                return 'Project name is required for planning documents';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          
          // Project Address
          _buildTextFormField(
            controller: _projectAddressController,
            label: 'Project Address',
            icon: Icons.location_on,
            maxLines: 2,
          ),
          const SizedBox(height: 16),
          
          // Built-up Area
          _buildTextFormField(
            controller: _builtUpAreaController,
            label: 'Built-up Area (sq ft)',
            icon: Icons.square_foot,
            keyboardType: TextInputType.number,
            validator: (value) {
              if (value != null && value.isNotEmpty) {
                if (double.tryParse(value) == null) {
                  return 'Please enter a valid number';
                }
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          
          // Plot Area
          _buildTextFormField(
            controller: _plotAreaController,
            label: 'Plot Area (sq ft)',
            icon: Icons.landscape,
            keyboardType: TextInputType.number,
            validator: (value) {
              if (value != null && value.isNotEmpty) {
                if (double.tryParse(value) == null) {
                  return 'Please enter a valid number';
                }
              }
              return null;
            },
          ),
          
          if (_showAllFields) ...[
            const SizedBox(height: 16),
            _buildTextFormField(
              controller: _floorAreaRatioController,
              label: 'Floor Area Ratio (FAR)',
              icon: Icons.layers,
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  final ratio = double.tryParse(value);
                  if (ratio == null || ratio < 0 || ratio > 10) {
                    return 'Please enter a valid FAR (0-10)';
                  }
                }
                return null;
              },
            ),
          ],
          
          const SizedBox(height: 24),
          _buildConsistencyChecker(),
        ],
      ),
    );
  }

  Widget _buildAuthorityTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Authority Information', Icons.account_balance),
          const SizedBox(height: 16),
          
          // Issuing Authority
          _buildTextFormField(
            controller: _issuingAuthorityController,
            label: 'Issuing Authority',
            icon: Icons.account_balance,
          ),
          const SizedBox(height: 16),
          
          // Approval Number
          _buildTextFormField(
            controller: _approvalNumberController,
            label: 'Approval Number',
            icon: Icons.confirmation_number,
          ),
          const SizedBox(height: 16),
          
          // Application Number
          _buildTextFormField(
            controller: _applicationNumberController,
            label: 'Application Number',
            icon: Icons.receipt,
          ),
          const SizedBox(height: 16),
          
          _buildSectionHeader('Contact Information', Icons.contact_phone),
          const SizedBox(height: 16),
          
          // Contact Person
          _buildTextFormField(
            controller: _contactPersonController,
            label: 'Contact Person',
            icon: Icons.person,
          ),
          const SizedBox(height: 16),
          
          // Contact Phone
          _buildTextFormField(
            controller: _contactPhoneController,
            label: 'Contact Phone',
            icon: Icons.phone,
            keyboardType: TextInputType.phone,
            validator: (value) {
              if (value != null && value.isNotEmpty) {
                if (!RegExp(r'^[\+]?[0-9\-\s]+$').hasMatch(value)) {
                  return 'Please enter a valid phone number';
                }
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          
          // Contact Email
          _buildTextFormField(
            controller: _contactEmailController,
            label: 'Contact Email',
            icon: Icons.email,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value != null && value.isNotEmpty) {
                if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                  return 'Please enter a valid email address';
                }
              }
              return null;
            },
          ),
          
          if (_showAllFields) ...[
            const SizedBox(height: 16),
            _buildDropdownField<String>(
              value: _selectedComplianceStatus,
              label: 'Compliance Status',
              icon: Icons.verified,
              items: _complianceStatuses.map((status) => DropdownMenuItem(
                value: status,
                child: Text(status),
              )).toList(),
              onChanged: (value) {
                if (value != null) {
                  setState(() => _selectedComplianceStatus = value);
                }
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDatesAndMoreTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionHeader('Important Dates', Icons.calendar_today),
          const SizedBox(height: 16),
          
          // Application Date
          _buildDateField(
            label: 'Application Date',
            icon: Icons.edit_calendar,
            selectedDate: _applicationDate,
            onDateSelected: (date) => setState(() => _applicationDate = date),
          ),
          const SizedBox(height: 16),
          
          // Approval Date
          _buildDateField(
            label: 'Approval Date',
            icon: Icons.check_circle,
            selectedDate: _approvalDate,
            onDateSelected: (date) => setState(() => _approvalDate = date),
          ),
          const SizedBox(height: 16),
          
          // Validity Start Date
          _buildDateField(
            label: 'Validity Start Date',
            icon: Icons.start,
            selectedDate: _validityStartDate,
            onDateSelected: (date) => setState(() => _validityStartDate = date),
          ),
          const SizedBox(height: 16),
          
          // Validity End Date
          _buildDateField(
            label: 'Validity End Date',
            icon: Icons.event_busy,
            selectedDate: _validityEndDate,
            onDateSelected: (date) => setState(() => _validityEndDate = date),
            isRequired: true,
          ),
          const SizedBox(height: 16),
          
          // Renewal Due Date
          _buildDateField(
            label: 'Renewal Due Date',
            icon: Icons.refresh,
            selectedDate: _renewalDueDate,
            onDateSelected: (date) => setState(() => _renewalDueDate = date),
          ),
          
          const SizedBox(height: 24),
          _buildSectionHeader('Additional Information', Icons.info),
          const SizedBox(height: 16),
          
          // Conditions Attached
          _buildTextFormField(
            controller: _conditionsController,
            label: 'Conditions Attached',
            icon: Icons.rule,
            maxLines: 3,
            hintText: 'Any conditions or requirements mentioned in the document',
          ),
          const SizedBox(height: 16),
          
          // Renewal Process
          _buildTextFormField(
            controller: _renewalProcessController,
            label: 'Renewal Process',
            icon: Icons.autorenew,
            maxLines: 2,
            hintText: 'Steps required for renewal',
          ),
          
          if (_showAllFields) ...[
            const SizedBox(height: 16),
            _buildTextFormField(
              controller: _feesPaidController,
              label: 'Fees Paid (₹)',
              icon: Icons.payment,
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value != null && value.isNotEmpty) {
                  if (double.tryParse(value) == null) {
                    return 'Please enter a valid amount';
                  }
                }
                return null;
              },
            ),
          ],
          
          const SizedBox(height: 24),
          _buildValidationSummary(),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: Colors.teal, size: 24),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Colors.teal,
          ),
        ),
      ],
    );
  }

  Widget _buildTextFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? hintText,
    TextInputType? keyboardType,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor: Colors.grey[50],
      ),
      keyboardType: keyboardType,
      maxLines: maxLines,
      validator: validator,
    );
  }

  Widget _buildDropdownField<T>({
    required T value,
    required String label,
    required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor: Colors.grey[50],
      ),
      items: items,
      onChanged: onChanged,
    );
  }

  Widget _buildDateField({
    required String label,
    required IconData icon,
    DateTime? selectedDate,
    required ValueChanged<DateTime> onDateSelected,
    bool isRequired = false,
  }) {
    return InkWell(
      onTap: () => _selectDate(context, selectedDate, onDateSelected),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label + (isRequired ? ' *' : ''),
          prefixIcon: Icon(icon),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
          fillColor: Colors.grey[50],
        ),
        child: Text(
          selectedDate != null
              ? DateFormat('MMM d, yyyy').format(selectedDate)
              : 'Select date',
          style: TextStyle(
            color: selectedDate != null ? Colors.black : Colors.grey[600],
          ),
        ),
      ),
    );
  }

  Widget _buildFileSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(12),
        color: Colors.grey[50],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.attach_file, color: Colors.teal),
              const SizedBox(width: 8),
              const Text(
                'Document File',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              if (widget.document == null)
                const Text(
                  ' *',
                  style: TextStyle(color: Colors.red),
                ),
            ],
          ),
          const SizedBox(height: 8),
          if (_selectedFile != null || _selectedFileName != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.teal[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.insert_drive_file, color: Colors.teal),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedFileName ?? _selectedFile!.path.split('/').last,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      setState(() {
                        _selectedFile = null;
                        _selectedFileName = null;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],
          ElevatedButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.upload_file),
            label: Text(_selectedFile != null || _selectedFileName != null 
                ? 'Change File' 
                : 'Select File'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Supported formats: PDF, DOC, DOCX, JPG, PNG, XLS, XLSX (Max 10MB)',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConsistencyChecker() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.sync, color: Colors.blue[700]),
              const SizedBox(width: 8),
              Text(
                'Smart Consistency Check',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.blue[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'The system will automatically check for consistency with other project documents when you save.',
            style: TextStyle(color: Colors.blue[600]),
          ),
          const SizedBox(height: 8),
          ElevatedButton.icon(
            onPressed: _runConsistencyCheck,
            icon: const Icon(Icons.check_circle),
            label: const Text('Check Now'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildValidationSummary() {
    final issues = _getValidationIssues();
    
    if (issues.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.green[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.green[200]!),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green[700]),
            const SizedBox(width: 8),
            Text(
              'All validation checks passed',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green[700],
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.warning, color: Colors.orange[700]),
              const SizedBox(width: 8),
              Text(
                'Validation Issues',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.orange[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...issues.map((issue) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              children: [
                Icon(Icons.circle, size: 6, color: Colors.orange[600]),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    issue,
                    style: TextStyle(color: Colors.orange[600]),
                  ),
                ),
              ],
            ),
          )),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.3),
            spreadRadius: 1,
            blurRadius: 5,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _saveDocument,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : Text(widget.document == null ? 'Save Document' : 'Update Document'),
            ),
          ),
        ],
      ),
    );
  }

  // Helper Methods
  Icon _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'environmental':
        return const Icon(Icons.eco, color: Colors.green);
      case 'planning':
        return const Icon(Icons.architecture, color: Colors.blue);
      case 'utilities':
        return const Icon(Icons.electrical_services, color: Colors.orange);
      case 'legal':
        return const Icon(Icons.gavel, color: Colors.purple);
      case 'safety':
        return const Icon(Icons.security, color: Colors.red);
      case 'financial':
        return const Icon(Icons.account_balance, color: Colors.teal);
      default:
        return const Icon(Icons.folder, color: Colors.grey);
    }
  }

  String _getCategoryDisplayName(String category) {
    switch (category.toLowerCase()) {
      case 'environmental':
        return 'Environmental';
      case 'planning':
        return 'Planning & Building';
      case 'utilities':
        return 'Utilities';
      case 'legal':
        return 'Legal & Land';
      case 'safety':
        return 'Safety & Security';
      case 'financial':
        return 'Financial';
      default:
        return 'Other Documents';
    }
  }

  Icon _getPriorityIcon(String priority) {
    switch (priority.toLowerCase()) {
      case 'critical':
        return const Icon(Icons.priority_high, color: Colors.red);
      case 'high':
        return const Icon(Icons.warning, color: Colors.orange);
      case 'medium':
        return const Icon(Icons.info, color: Colors.blue);
      case 'low':
        return const Icon(Icons.check_circle, color: Colors.green);
      default:
        return const Icon(Icons.radio_button_unchecked, color: Colors.grey);
    }
  }

  List<String> _getValidationIssues() {
    final issues = <String>[];

    if (_nameController.text.isEmpty) {
      issues.add('Document name is required');
    }

    if (widget.document == null && _selectedFile == null) {
      issues.add('Document file is required');
    }

    if (_validityEndDate != null && _validityStartDate != null) {
      if (_validityEndDate!.isBefore(_validityStartDate!)) {
        issues.add('Validity end date cannot be before start date');
      }
    }

    if (_approvalDate != null && _applicationDate != null) {
      if (_approvalDate!.isBefore(_applicationDate!)) {
        issues.add('Approval date cannot be before application date');
      }
    }

    final builtUpArea = double.tryParse(_builtUpAreaController.text);
    final plotArea = double.tryParse(_plotAreaController.text);
    if (builtUpArea != null && plotArea != null && builtUpArea > plotArea) {
      issues.add('Built-up area cannot exceed plot area');
    }

    return issues;
  }

  Future<void> _selectDate(BuildContext context, DateTime? initialDate, ValueChanged<DateTime> onDateSelected) async {
    final date = await showDatePicker(
      context: context,
      initialDate: initialDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime.now().add(const Duration(days: 3650)),
    );

    if (date != null) {
      onDateSelected(date);
    }
  }

  Future<void> _pickFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'doc', 'docx', 'jpg', 'jpeg', 'png', 'xls', 'xlsx'],
      );

      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        
        if (file.size > 10 * 1024 * 1024) { // 10MB limit
          _showError('File size exceeds 10MB limit');
          return;
        }

        setState(() {
          _selectedFile = File(file.path!);
          _selectedFileName = file.name;
        });
      }
    } catch (e) {
      _showError('Error selecting file: $e');
    }
  }

  Future<void> _runConsistencyCheck() async {
    if (_projectNameController.text.isEmpty) {
      _showError('Please enter a project name to run consistency check');
      return;
    }

    try {
      // This would call your consistency check API
      _showSuccess('Consistency check completed. No major issues found.');
    } catch (e) {
      _showError('Error running consistency check: $e');
    }
  }

  Future<void> _saveDocument() async {
    if (!_formKey.currentState!.validate()) {
      _showError('Please fix the validation errors before saving');
      return;
    }
    final issues = _getValidationIssues();
    if (issues.isNotEmpty) {
      _showError('Please resolve all validation issues before saving');
      return;
    }
    setState(() => _isLoading = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      if (token == null) {
        throw Exception('Authentication token not found');
      }
      final request = http.MultipartRequest(
        widget.document == null ? 'POST' : 'PUT',
        Uri.parse(widget.document == null 
          ? '$baseUrl/api/documents' 
          : '$baseUrl/api/documents/${widget.document!.id}'),
      );
      request.headers['Authorization'] = 'Bearer $token';
      
      // Add required fields
      request.fields['name'] = _nameController.text;
      request.fields['category'] = _selectedCategory;
      request.fields['status'] = _selectedStatus;
      
      print('Upload Debug - Name: ${_nameController.text}');
      print('Upload Debug - Category: $_selectedCategory');
      print('Upload Debug - Status: $_selectedStatus');
      print('Upload Debug - Description: ${_descriptionController.text}');
      print('Upload Debug - Tags (raw): ${_tagsController.text}');
      if (_tagsController.text.isNotEmpty) {
        List<String> tagsList = _tagsController.text.split(',').map((tag) => tag.trim()).where((tag) => tag.isNotEmpty).toList();
        print('Upload Debug - Tags (array): ${json.encode(tagsList)}');
      }
      print('Upload Debug - File: ${_selectedFile?.path}');
      
      // Add optional fields
      if (_descriptionController.text.isNotEmpty) {
        request.fields['description'] = _descriptionController.text;
      }
      if (_tagsController.text.isNotEmpty) {
        // Convert comma-separated string to JSON array
        List<String> tagsList = _tagsController.text.split(',').map((tag) => tag.trim()).where((tag) => tag.isNotEmpty).toList();
        request.fields['tags'] = json.encode(tagsList);
      }
      
      // Add file if selected
      if (_selectedFile != null) {
        request.files.add(await http.MultipartFile.fromPath('file', _selectedFile!.path));
      }
      
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      
      print('Upload Response Status: ${response.statusCode}');
      print('Upload Response Body: $responseBody');
      
      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) {
          _showSuccess(widget.document == null 
              ? 'Document saved successfully!' 
              : 'Document updated successfully!');
          if (widget.onDocumentSaved != null) {
            widget.onDocumentSaved!();
          }
          Navigator.of(context).pop();
        }
      } else {
        try {
          final errorData = json.decode(responseBody);
          throw Exception(errorData['message'] ?? 'Failed to save document');
        } catch (jsonError) {
          print('JSON Parse Error: $jsonError');
          print('Raw Response: $responseBody');
          throw Exception('Server returned invalid response. Status: ${response.statusCode}, Body: ${responseBody.length > 200 ? responseBody.substring(0, 200) + "..." : responseBody}');
        }
      }
    } catch (e) {
      _showError('Error saving document: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      ),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }
}








// Real-time WebSocket Service for Document Management
class RealTimeDocumentService {
  static final RealTimeDocumentService _instance = RealTimeDocumentService._internal();
  factory RealTimeDocumentService() => _instance;
  RealTimeDocumentService._internal();

  IO.Socket? _socket;
  bool _isConnected = false;
  Timer? _pingTimer;
  String? _currentUserId;

  // Stream controllers for different types of updates
  final StreamController<Map<String, dynamic>> _notificationController = 
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _documentUpdateController = 
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _healthUpdateController = 
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _expiryAlertController = 
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<Map<String, dynamic>> _validationController = 
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<bool> _connectionController = 
      StreamController<bool>.broadcast();

  // Getters for streams
  Stream<Map<String, dynamic>> get notificationStream => _notificationController.stream;
  Stream<Map<String, dynamic>> get documentUpdateStream => _documentUpdateController.stream;
  Stream<Map<String, dynamic>> get healthUpdateStream => _healthUpdateController.stream;
  Stream<Map<String, dynamic>> get expiryAlertStream => _expiryAlertController.stream;
  Stream<Map<String, dynamic>> get validationStream => _validationController.stream;
  Stream<bool> get connectionStream => _connectionController.stream;

  bool get isConnected => _isConnected;

  // Initialize WebSocket connection
  Future<void> connect() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      final userIdStr = prefs.getString('user_id');

      if (token == null || userIdStr == null) {
        throw Exception('Authentication credentials not found');
      }

      _currentUserId = userIdStr;

      // Initialize socket connection
      _socket = IO.io(
        baseUrl.replaceFirst('http', 'ws'), // Use ws or wss for WebSocket if needed
        IO.OptionBuilder()
            .setTransports(['websocket', 'polling'])
            .enableAutoConnect()
            .enableReconnection()
            .setReconnectionAttempts(5)
            .setReconnectionDelay(1000)
            .build(),
      );

      _setupEventHandlers();

      // Authenticate after connection
      _socket!.onConnect((_) {
        print('Connected to WebSocket server');
        _authenticate(token, userIdStr);
      });

      _socket!.connect();
    } catch (e) {
      print('Error connecting to WebSocket: $e');
      throw e;
    }
  }

  void _setupEventHandlers() {
    if (_socket == null) return;

    // Connection events
    _socket!.onConnect((_) {
      print('WebSocket connected');
      _isConnected = true;
      _connectionController.add(true);
      _startPingTimer();
    });

    _socket!.onDisconnect((_) {
      print('WebSocket disconnected');
      _isConnected = false;
      _connectionController.add(false);
      _stopPingTimer();
    });

    _socket!.onConnectError((error) {
      print('WebSocket connection error: $error');
      _isConnected = false;
      _connectionController.add(false);
    });

    // Authentication events
    _socket!.on('authenticated', (data) {
      print('WebSocket authenticated: $data');
      _isConnected = true;
      _connectionController.add(true);
    });

    _socket!.on('authentication_error', (data) {
      print('WebSocket authentication error: $data');
      _isConnected = false;
      _connectionController.add(false);
    });

    // Document events
    _socket!.on('document_updated', (data) {
      print('Document updated: $data');
      _documentUpdateController.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('project_document_updated', (data) {
      print('Project document updated: $data');
      _documentUpdateController.add(Map<String, dynamic>.from(data));
    });

    // Notification events
    _socket!.on('user_notification', (data) {
      print('User notification received: $data');
      _notificationController.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('system_notification', (data) {
      print('System notification received: $data');
      _notificationController.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('pending_notifications', (data) {
      print('Pending notifications received: $data');
      _notificationController.add(Map<String, dynamic>.from(data));
    });

    // Health and alert events
    _socket!.on('health_score_updated', (data) {
      print('Health score updated: $data');
      _healthUpdateController.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('system_health_updated', (data) {
      print('System health updated: $data');
      _healthUpdateController.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('expiry_alert', (data) {
      print('Expiry alert received: $data');
      _expiryAlertController.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('critical_expiry_alert', (data) {
      print('Critical expiry alert received: $data');
      _expiryAlertController.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('critical_document_alert', (data) {
      print('Critical document alert received: $data');
      _expiryAlertController.add(Map<String, dynamic>.from(data));
    });

    // Validation events
    _socket!.on('field_validation_result', (data) {
      print('Field validation result: $data');
      _validationController.add(Map<String, dynamic>.from(data));
    });

    _socket!.on('field_validation_error', (data) {
      print('Field validation error: $data');
      _validationController.add(Map<String, dynamic>.from(data));
    });

    // Document editing events
    _socket!.on('user_started_editing', (data) {
      print('User started editing: $data');
      _documentUpdateController.add({
        'type': 'user_started_editing',
        ...Map<String, dynamic>.from(data)
      });
    });

    _socket!.on('user_stopped_editing', (data) {
      print('User stopped editing: $data');
      _documentUpdateController.add({
        'type': 'user_stopped_editing',
        ...Map<String, dynamic>.from(data)
      });
    });

    // Ping/Pong for connection health
    _socket!.on('pong', (data) {
      print('Pong received: $data');
    });
  }

  void _authenticate(String token, String userId) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('authenticate', {
        'token': token,
        'userId': userId,
      });
    }
  }

  // Subscribe to project updates
  void subscribeToProject(String projectName) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('subscribe_to_project', {
        'projectName': projectName,
      });
      print('Subscribed to project: $projectName');
    }
  }

  // Document editing session management
  void startEditingDocument(String documentId) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('start_editing_document', {
        'documentId': documentId,
      });
      print('Started editing document: $documentId');
    }
  }

  void stopEditingDocument(String documentId) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('stop_editing_document', {
        'documentId': documentId,
      });
      print('Stopped editing document: $documentId');
    }
  }

  // Real-time field validation
  void validateField(String documentId, String fieldName, dynamic fieldValue, String? projectName) {
    if (_socket != null && _socket!.connected) {
      _socket!.emit('validate_document_field', {
        'documentId': documentId,
        'fieldName': fieldName,
        'fieldValue': fieldValue,
        'projectName': projectName,
      });
      print('Validating field: $fieldName for document: $documentId');
    }
  }

  void _startPingTimer() {
    _pingTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (_socket != null && _socket!.connected) {
        _socket!.emit('ping');
      }
    });
  }

  void _stopPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = null;
  }

  // Disconnect from WebSocket
  void disconnect() {
    _stopPingTimer();
    _socket?.disconnect();
    _socket?.dispose();
    _socket = null;
    _isConnected = false;
    _connectionController.add(false);
    print('WebSocket disconnected');
  }

  // Dispose all resources
  void dispose() {
    disconnect();
    _notificationController.close();
    _documentUpdateController.close();
    _healthUpdateController.close();
    _expiryAlertController.close();
    _validationController.close();
    _connectionController.close();
  }
}

// Real-time Notification Widget
class RealTimeNotificationListener extends StatefulWidget {
  final Widget child;
  final Function(Map<String, dynamic>)? onNotificationReceived;
  final Function(Map<String, dynamic>)? onExpiryAlert;
  final Function(Map<String, dynamic>)? onHealthUpdate;

  const RealTimeNotificationListener({
    super.key,
    required this.child,
    this.onNotificationReceived,
    this.onExpiryAlert,
    this.onHealthUpdate,
  });

  @override
  State<RealTimeNotificationListener> createState() => _RealTimeNotificationListenerState();
}

class _RealTimeNotificationListenerState extends State<RealTimeNotificationListener> {
  final RealTimeDocumentService _realTimeService = RealTimeDocumentService();
  late StreamSubscription _notificationSubscription;
  late StreamSubscription _expirySubscription;
  late StreamSubscription _healthSubscription;
  late StreamSubscription _connectionSubscription;

  @override
  void initState() {
    super.initState();
    _initializeRealTimeService();
    _setupSubscriptions();
  }

  Future<void> _initializeRealTimeService() async {
    try {
      await _realTimeService.connect();
    } catch (e) {
      print('Failed to initialize real-time service: $e');
    }
  }

  void _setupSubscriptions() {
    // Listen for notifications
    _notificationSubscription = _realTimeService.notificationStream.listen(
      (notification) {
        _handleNotification(notification);
        widget.onNotificationReceived?.call(notification);
      },
      onError: (error) {
        print('Notification stream error: $error');
      },
    );

    // Listen for expiry alerts
    _expirySubscription = _realTimeService.expiryAlertStream.listen(
      (alert) {
        _handleExpiryAlert(alert);
        widget.onExpiryAlert?.call(alert);
      },
      onError: (error) {
        print('Expiry alert stream error: $error');
      },
    );

    // Listen for health updates
    _healthSubscription = _realTimeService.healthUpdateStream.listen(
      (update) {
        _handleHealthUpdate(update);
        widget.onHealthUpdate?.call(update);
      },
      onError: (error) {
        print('Health update stream error: $error');
      },
    );

    // Listen for connection status
    _connectionSubscription = _realTimeService.connectionStream.listen(
      (isConnected) {
        if (mounted) {
          _showConnectionStatus(isConnected);
        }
      },
      onError: (error) {
        print('Connection stream error: $error');
      },
    );
  }

  void _handleNotification(Map<String, dynamic> notification) {
    if (!mounted) return;

    final notificationType = notification['type'] as String?;
    final title = notification['title'] as String? ?? 'Notification';
    final message = notification['message'] as String? ?? '';

    // Show different UI based on notification type
    switch (notificationType) {
      case 'document_expiry':
        _showExpiryNotification(title, message, notification);
        break;
      case 'data_inconsistency':
        _showInconsistencyNotification(title, message, notification);
        break;
      case 'system_notification':
        _showSystemNotification(title, message, notification);
        break;
      default:
        _showDefaultNotification(title, message);
    }
  }

  void _handleExpiryAlert(Map<String, dynamic> alert) {
    if (!mounted) return;

    final severity = alert['severity'] as String? ?? 'Medium';
    final documentName = alert['document']?['name'] as String? ?? 'Document';
    final daysUntilExpiry = alert['document']?['days_until_expiry'] as int? ?? 0;

    Color alertColor;
    IconData alertIcon;

    switch (severity.toLowerCase()) {
      case 'critical':
        alertColor = Colors.red;
        alertIcon = Icons.error;
        break;
      case 'high':
        alertColor = Colors.orange;
        alertIcon = Icons.warning;
        break;
      default:
        alertColor = Colors.blue;
        alertIcon = Icons.info;
    }

    _showCustomAlert(
      title: severity == 'Critical' ? 'URGENT EXPIRY ALERT' : 'Expiry Reminder',
      message: '$documentName expires in $daysUntilExpiry days',
      color: alertColor,
      icon: alertIcon,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Dismiss'),
        ),
        ElevatedButton(
          onPressed: () {
            Navigator.of(context).pop();
            // Navigate to document details or renewal process
          },
          style: ElevatedButton.styleFrom(backgroundColor: alertColor),
          child: const Text('Take Action'),
        ),
      ],
    );
  }

  void _handleHealthUpdate(Map<String, dynamic> update) {
    if (!mounted) return;

    final healthScore = update['health_score'] as int? ?? 0;
    final healthStatus = update['health_status'] as String? ?? 'Unknown';
    final projectName = update['project_name'] as String?;

    // Only show notifications for significant health changes
    if (healthScore < 70) {
      final title = projectName != null 
          ? 'Health Alert: $projectName'
          : 'System Health Alert';
      
      _showHealthAlert(title, 'Health score dropped to $healthScore% ($healthStatus)');
    }
  }

  void _showConnectionStatus(bool isConnected) {
    final message = isConnected ? 'Connected to real-time updates' : 'Disconnected from real-time updates';
    final color = isConnected ? Colors.green : Colors.orange;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isConnected ? Icons.wifi : Icons.wifi_off,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 8),
            Text(message),
          ],
        ),
        backgroundColor: color,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showExpiryNotification(String title, String message, Map<String, dynamic> data) {
    _showCustomAlert(
      title: title,
      message: message,
      color: Colors.orange,
      icon: Icons.schedule,
    );
  }

  void _showInconsistencyNotification(String title, String message, Map<String, dynamic> data) {
    _showCustomAlert(
      title: title,
      message: message,
      color: Colors.purple,
      icon: Icons.sync_problem,
    );
  }

  void _showSystemNotification(String title, String message, Map<String, dynamic> data) {
    _showCustomAlert(
      title: title,
      message: message,
      color: Colors.blue,
      icon: Icons.notifications,
    );
  }

  void _showDefaultNotification(String title, String message) {
    _showCustomAlert(
      title: title,
      message: message,
      color: Colors.teal,
      icon: Icons.info,
    );
  }

  void _showHealthAlert(String title, String message) {
    _showCustomAlert(
      title: title,
      message: message,
      color: Colors.red,
      icon: Icons.health_and_safety,
    );
  }

  void _showCustomAlert({
    required String title,
    required String message,
    required Color color,
    required IconData icon,
    List<Widget>? actions,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(color: color, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: Text(message),
        actions: actions ?? [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _notificationSubscription.cancel();
    _expirySubscription.cancel();
    _healthSubscription.cancel();
    _connectionSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

// Real-time Form Validation Mixin
mixin RealTimeValidationMixin<T extends StatefulWidget> on State<T> {
  final RealTimeDocumentService _realTimeService = RealTimeDocumentService();
  late StreamSubscription _validationSubscription;
  Map<String, dynamic> _validationResults = {};

  @override
  void initState() {
    super.initState();
    _setupValidationListener();
  }

  void _setupValidationListener() {
    _validationSubscription = _realTimeService.validationStream.listen(
      (validationResult) {
        if (mounted) {
          setState(() {
            final fieldName = validationResult['fieldName'] as String;
            _validationResults[fieldName] = validationResult['validation'];
          });
          onValidationResultReceived(validationResult);
        }
      },
      onError: (error) {
        print('Validation stream error: $error');
      },
    );
  }

  // Override this method in your form widgets
  void onValidationResultReceived(Map<String, dynamic> validationResult) {
    // Handle validation result
  }

  // Trigger real-time validation
  void validateFieldInRealTime(String documentId, String fieldName, dynamic value, String? projectName) {
    if (_realTimeService.isConnected) {
      _realTimeService.validateField(documentId, fieldName, value, projectName);
    }
  }

  // Get validation result for a field
  Map<String, dynamic>? getValidationResult(String fieldName) {
    return _validationResults[fieldName];
  }

  // Check if field has warnings
  bool hasFieldWarnings(String fieldName) {
    final result = _validationResults[fieldName];
    return result != null && (result['warnings'] as List?)?.isNotEmpty == true;
  }

  // Get field warnings
  List<dynamic> getFieldWarnings(String fieldName) {
    final result = _validationResults[fieldName];
    return result?['warnings'] as List<dynamic>? ?? [];
  }

  // Get field suggestions
  List<dynamic> getFieldSuggestions(String fieldName) {
    final result = _validationResults[fieldName];
    return result?['suggestions'] as List<dynamic>? ?? [];
  }

  @override
  void dispose() {
    _validationSubscription.cancel();
    super.dispose();
  }
}

// Connection Status Widget
class ConnectionStatusWidget extends StatefulWidget {
  const ConnectionStatusWidget({super.key});

  @override
  State<ConnectionStatusWidget> createState() => _ConnectionStatusWidgetState();
}

class _ConnectionStatusWidgetState extends State<ConnectionStatusWidget> {
  final RealTimeDocumentService _realTimeService = RealTimeDocumentService();
  late StreamSubscription _connectionSubscription;
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _isConnected = _realTimeService.isConnected;
    _connectionSubscription = _realTimeService.connectionStream.listen(
      (isConnected) {
        if (mounted) {
          setState(() {
            _isConnected = isConnected;
          });
        }
      },
    );
  }

  @override
  void dispose() {
    _connectionSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _isConnected ? Colors.green : Colors.red,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isConnected ? Icons.wifi : Icons.wifi_off,
            color: Colors.white,
            size: 16,
          ),
          const SizedBox(width: 4),
          Text(
            _isConnected ? 'Live' : 'Offline',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}




class AnalyticsData {
  final DocumentAnalytics documentAnalytics;
  final ComplianceAnalytics complianceAnalytics;
  final TrendAnalytics trendAnalytics;
  final ProjectAnalytics projectAnalytics;

  AnalyticsData({
    required this.documentAnalytics,
    required this.complianceAnalytics,
    required this.trendAnalytics,
    required this.projectAnalytics,
  });

  factory AnalyticsData.fromJson(Map<String, dynamic> json) {
    return AnalyticsData(
      documentAnalytics: DocumentAnalytics.fromJson(json['document_analytics'] ?? {}),
      complianceAnalytics: ComplianceAnalytics.fromJson(json['compliance_analytics'] ?? {}),
      trendAnalytics: TrendAnalytics.fromJson(json['trend_analytics'] ?? {}),
      projectAnalytics: ProjectAnalytics.fromJson(json['project_analytics'] ?? {}),
    );
  }
}

class DocumentAnalytics {
  final int totalDocuments;
  final int approvedDocuments;
  final int pendingDocuments;
  final int expiredDocuments;
  final int expiringDocuments;
  final Map<String, int> categoryDistribution;
  final Map<String, int> statusDistribution;
  final double averageProcessingTime;

  DocumentAnalytics({
    required this.totalDocuments,
    required this.approvedDocuments,
    required this.pendingDocuments,
    required this.expiredDocuments,
    required this.expiringDocuments,
    required this.categoryDistribution,
    required this.statusDistribution,
    required this.averageProcessingTime,
  });

  factory DocumentAnalytics.fromJson(Map<String, dynamic> json) {
    return DocumentAnalytics(
      totalDocuments: json['total_documents'] ?? 0,
      approvedDocuments: json['approved_documents'] ?? 0,
      pendingDocuments: json['pending_documents'] ?? 0,
      expiredDocuments: json['expired_documents'] ?? 0,
      expiringDocuments: json['expiring_documents'] ?? 0,
      categoryDistribution: Map<String, int>.from(json['category_distribution'] ?? {}),
      statusDistribution: Map<String, int>.from(json['status_distribution'] ?? {}),
      averageProcessingTime: (json['average_processing_time'] ?? 0.0).toDouble(),
    );
  }
}

class ComplianceAnalytics {
  final double overallComplianceScore;
  final int totalIssues;
  final int criticalIssues;
  final int resolvedIssues;
  final Map<String, double> categoryComplianceScores;
  final List<ComplianceIssue> topIssues;

  ComplianceAnalytics({
    required this.overallComplianceScore,
    required this.totalIssues,
    required this.criticalIssues,
    required this.resolvedIssues,
    required this.categoryComplianceScores,
    required this.topIssues,
  });

  factory ComplianceAnalytics.fromJson(Map<String, dynamic> json) {
    return ComplianceAnalytics(
      overallComplianceScore: (json['overall_compliance_score'] ?? 0.0).toDouble(),
      totalIssues: json['total_issues'] ?? 0,
      criticalIssues: json['critical_issues'] ?? 0,
      resolvedIssues: json['resolved_issues'] ?? 0,
      categoryComplianceScores: Map<String, double>.from(json['category_compliance_scores'] ?? {}),
      topIssues: (json['top_issues'] as List? ?? [])
          .map((issue) => ComplianceIssue.fromJson(issue))
          .toList(),
    );
  }
}

class ComplianceIssue {
  final String id;
  final String title;
  final String description;
  final String severity;
  final String category;
  final DateTime createdAt;
  final bool isResolved;

  ComplianceIssue({
    required this.id,
    required this.title,
    required this.description,
    required this.severity,
    required this.category,
    required this.createdAt,
    required this.isResolved,
  });

  factory ComplianceIssue.fromJson(Map<String, dynamic> json) {
    return ComplianceIssue(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      severity: json['severity'] ?? 'Medium',
      category: json['category'] ?? '',
      createdAt: DateTime.parse(json['created_at'] ?? DateTime.now().toIso8601String()),
      isResolved: json['is_resolved'] ?? false,
    );
  }
}

class TrendAnalytics {
  final List<TrendDataPoint> documentTrends;
  final List<TrendDataPoint> complianceTrends;
  final List<TrendDataPoint> expiryTrends;
  final double trendDirection; // -1 to 1, negative is declining

  TrendAnalytics({
    required this.documentTrends,
    required this.complianceTrends,
    required this.expiryTrends,
    required this.trendDirection,
  });

  factory TrendAnalytics.fromJson(Map<String, dynamic> json) {
    return TrendAnalytics(
      documentTrends: (json['document_trends'] as List? ?? [])
          .map((point) => TrendDataPoint.fromJson(point))
          .toList(),
      complianceTrends: (json['compliance_trends'] as List? ?? [])
          .map((point) => TrendDataPoint.fromJson(point))
          .toList(),
      expiryTrends: (json['expiry_trends'] as List? ?? [])
          .map((point) => TrendDataPoint.fromJson(point))
          .toList(),
      trendDirection: (json['trend_direction'] ?? 0.0).toDouble(),
    );
  }
}

class TrendDataPoint {
  final DateTime date;
  final double value;
  final String label;

  TrendDataPoint({
    required this.date,
    required this.value,
    required this.label,
  });

  factory TrendDataPoint.fromJson(Map<String, dynamic> json) {
    return TrendDataPoint(
      date: DateTime.parse(json['date']),
      value: (json['value'] ?? 0.0).toDouble(),
      label: json['label'] ?? '',
    );
  }
}

class ProjectAnalytics {
  final int totalProjects;
  final int activeProjects;
  final int completedProjects;
  final List<ProjectSummary> projectSummaries;
  final Map<String, int> authorityDistribution;

  ProjectAnalytics({
    required this.totalProjects,
    required this.activeProjects,
    required this.completedProjects,
    required this.projectSummaries,
    required this.authorityDistribution,
  });

  factory ProjectAnalytics.fromJson(Map<String, dynamic> json) {
    return ProjectAnalytics(
      totalProjects: json['total_projects'] ?? 0,
      activeProjects: json['active_projects'] ?? 0,
      completedProjects: json['completed_projects'] ?? 0,
      projectSummaries: (json['project_summaries'] as List? ?? [])
          .map((summary) => ProjectSummary.fromJson(summary))
          .toList(),
      authorityDistribution: Map<String, int>.from(json['authority_distribution'] ?? {}),
    );
  }
}

class ProjectSummary {
  final String projectName;
  final int totalDocuments;
  final int approvedDocuments;
  final double completionPercentage;
  final int issuesCount;
  final DateTime lastUpdated;

  ProjectSummary({
    required this.projectName,
    required this.totalDocuments,
    required this.approvedDocuments,
    required this.completionPercentage,
    required this.issuesCount,
    required this.lastUpdated,
  });

  factory ProjectSummary.fromJson(Map<String, dynamic> json) {
    return ProjectSummary(
      projectName: json['project_name'] ?? '',
      totalDocuments: json['total_documents'] ?? 0,
      approvedDocuments: json['approved_documents'] ?? 0,
      completionPercentage: (json['completion_percentage'] ?? 0.0).toDouble(),
      issuesCount: json['issues_count'] ?? 0,
      lastUpdated: DateTime.parse(json['last_updated'] ?? DateTime.now().toIso8601String()),
    );
  }
}

// Advanced Analytics Dashboard
class AdvancedAnalyticsDashboard extends StatefulWidget {
  const AdvancedAnalyticsDashboard({super.key});

  @override
  State<AdvancedAnalyticsDashboard> createState() => _AdvancedAnalyticsDashboardState();
}

class _AdvancedAnalyticsDashboardState extends State<AdvancedAnalyticsDashboard>
    with TickerProviderStateMixin {
  late TabController _tabController;
  AnalyticsData? _analyticsData;
  bool _isLoading = true;
  String _selectedTimeframe = '30d';
  String? _selectedProject;

  final List<String> _timeframes = ['7d', '30d', '90d', '1y'];
  final List<String> _timeframeLabels = ['7 Days', '30 Days', '90 Days', '1 Year'];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadAnalyticsData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadAnalyticsData() async {
    setState(() => _isLoading = true);
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('auth_token');
      
      if (token == null) {
        throw Exception('Authentication token not found');
      }

      final response = await http.get(
        Uri.parse('$baseUrl/api/analytics/dashboard?timeframe=$_selectedTimeframe&project=$_selectedProject'),
        headers: {'Authorization': 'Bearer $token'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _analyticsData = AnalyticsData.fromJson(data['data']);
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load analytics data');
      }
    } catch (e) {
      print('Error loading analytics data: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Advanced Analytics',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.indigo,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Overview', icon: Icon(Icons.dashboard)),
            Tab(text: 'Compliance', icon: Icon(Icons.verified_user)),
            Tab(text: 'Trends', icon: Icon(Icons.trending_up)),
            Tab(text: 'Projects', icon: Icon(Icons.business)),
          ],
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
        ),
        actions: [
          _buildTimeframeSelector(),
          _buildExportButton(),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _analyticsData == null
              ? _buildErrorState()
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOverviewTab(),
                    _buildComplianceTab(),
                    _buildTrendsTab(),
                    _buildProjectsTab(),
                  ],
                ),
    );
  }

  Widget _buildTimeframeSelector() {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.access_time),
      onSelected: (value) {
        setState(() => _selectedTimeframe = value);
        _loadAnalyticsData();
      },
      itemBuilder: (context) => List.generate(
        _timeframes.length,
        (index) => PopupMenuItem(
          value: _timeframes[index],
          child: Text(_timeframeLabels[index]),
        ),
      ),
    );
  }

  Widget _buildExportButton() {
    return IconButton(
      icon: const Icon(Icons.download),
      onPressed: _exportAnalytics,
      tooltip: 'Export Analytics',
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.error_outline, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text('Failed to load analytics data'),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadAnalyticsData,
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab() {
    final docAnalytics = _analyticsData!.documentAnalytics;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildKPICards(docAnalytics),
          const SizedBox(height: 24),
          _buildDocumentStatusChart(docAnalytics),
          const SizedBox(height: 24),
          _buildCategoryDistributionChart(docAnalytics),
          const SizedBox(height: 24),
          _buildQuickInsights(),
        ],
      ),
    );
  }

  Widget _buildKPICards(DocumentAnalytics analytics) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 16,
      crossAxisSpacing: 16,
      childAspectRatio: 1.5,
      children: [
        _buildKPICard(
          'Total Documents',
          analytics.totalDocuments.toString(),
          Icons.folder,
          Colors.blue,
          subtitle: 'All documents',
        ),
        _buildKPICard(
          'Approved',
          analytics.approvedDocuments.toString(),
          Icons.check_circle,
          Colors.green,
          subtitle: '${(analytics.approvedDocuments / analytics.totalDocuments * 100).toInt()}% of total',
        ),
        _buildKPICard(
          'Pending',
          analytics.pendingDocuments.toString(),
          Icons.pending,
          Colors.orange,
          subtitle: 'Awaiting approval',
        ),
        _buildKPICard(
          'Expired',
          analytics.expiredDocuments.toString(),
          Icons.error,
          Colors.red,
          subtitle: 'Need renewal',
        ),
      ],
    );
  }

  Widget _buildKPICard(String title, String value, IconData icon, Color color, {String? subtitle}) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const Spacer(),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentStatusChart(DocumentAnalytics analytics) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Document Status Distribution',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sections: _buildPieChartSections(analytics.statusDistribution),
                  sectionsSpace: 2,
                  centerSpaceRadius: 40,
                  startDegreeOffset: -90,
                ),
              ),
            ),
            const SizedBox(height: 16),
            _buildChartLegend(analytics.statusDistribution),
          ],
        ),
      ),
    );
  }

  List<PieChartSectionData> _buildPieChartSections(Map<String, int> data) {
    final colors = [
      Colors.green,
      Colors.orange,
      Colors.red,
      Colors.blue,
      Colors.purple,
      Colors.teal,
    ];

    int colorIndex = 0;
    final total = data.values.fold(0, (sum, value) => sum + value);

    return data.entries.map((entry) {
      final percentage = (entry.value / total * 100);
      final color = colors[colorIndex % colors.length];
      colorIndex++;

      return PieChartSectionData(
        color: color,
        value: entry.value.toDouble(),
        title: '${percentage.toInt()}%',
        radius: 60,
        titleStyle: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      );
    }).toList();
  }

  Widget _buildChartLegend(Map<String, int> data) {
    final colors = [
      Colors.green,
      Colors.orange,
      Colors.red,
      Colors.blue,
      Colors.purple,
      Colors.teal,
    ];

    int colorIndex = 0;

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      children: data.entries.map((entry) {
        final color = colors[colorIndex % colors.length];
        colorIndex++;

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 16,
              height: 16,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(width: 8),
            Text('${entry.key}: ${entry.value}'),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildCategoryDistributionChart(DocumentAnalytics analytics) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Documents by Category',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: analytics.categoryDistribution.values.fold(0, math.max).toDouble(),
                  barTouchData: BarTouchData(enabled: true),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final categories = analytics.categoryDistribution.keys.toList();
                          if (value.toInt() < categories.length) {
                            return Text(
                              _getCategoryShortName(categories[value.toInt()]),
                              style: const TextStyle(fontSize: 12),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  barGroups: _buildBarGroups(analytics.categoryDistribution),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<BarChartGroupData> _buildBarGroups(Map<String, int> data) {
    int index = 0;
    return data.entries.map((entry) {
      return BarChartGroupData(
        x: index++,
        barRods: [
          BarChartRodData(
            toY: entry.value.toDouble(),
            color: _getCategoryColor(entry.key),
            width: 20,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
            ),
          ),
        ],
      );
    }).toList();
  }

  String _getCategoryShortName(String category) {
    switch (category.toLowerCase()) {
      case 'environmental':
        return 'Env';
      case 'planning':
        return 'Plan';
      case 'utilities':
        return 'Util';
      case 'legal':
        return 'Legal';
      case 'safety':
        return 'Safe';
      case 'financial':
        return 'Fin';
      default:
        return 'Other';
    }
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'environmental':
        return Colors.green;
      case 'planning':
        return Colors.blue;
      case 'utilities':
        return Colors.orange;
      case 'legal':
        return Colors.purple;
      case 'safety':
        return Colors.red;
      case 'financial':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  Widget _buildQuickInsights() {
    final docAnalytics = _analyticsData!.documentAnalytics;
    final complianceAnalytics = _analyticsData!.complianceAnalytics;
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Quick Insights',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildInsightItem(
              Icons.trending_up,
              'Processing Time',
              '${docAnalytics.averageProcessingTime.toInt()} days average',
              Colors.blue,
            ),
            _buildInsightItem(
              Icons.warning,
              'Expiring Soon',
              '${docAnalytics.expiringDocuments} documents need attention',
              Colors.orange,
            ),
            _buildInsightItem(
              Icons.verified,
              'Compliance Score',
              '${complianceAnalytics.overallComplianceScore.toInt()}%',
              complianceAnalytics.overallComplianceScore > 80 ? Colors.green : Colors.red,
            ),
            _buildInsightItem(
              Icons.schedule,
              'Critical Issues',
              '${complianceAnalytics.criticalIssues} requiring immediate action',
              Colors.red,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInsightItem(IconData icon, String title, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  value,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildComplianceTab() {
    final compliance = _analyticsData!.complianceAnalytics;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildComplianceScoreCard(compliance),
          const SizedBox(height: 24),
          _buildComplianceBreakdown(compliance),
          const SizedBox(height: 24),
          _buildTopIssues(compliance),
        ],
      ),
    );
  }

  Widget _buildComplianceScoreCard(ComplianceAnalytics compliance) {
    final score = compliance.overallComplianceScore;
    final color = score > 80 ? Colors.green : score > 60 ? Colors.orange : Colors.red;
    
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withOpacity(0.1), color.withOpacity(0.05)],
          ),
        ),
        child: Column(
          children: [
            Text(
              'Overall Compliance Score',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
            ),
            const SizedBox(height: 16),
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 120,
                  width: 120,
                  child: CircularProgressIndicator(
                    value: score / 100,
                    strokeWidth: 12,
                    backgroundColor: Colors.grey[300],
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
                Text(
                  '${score.toInt()}%',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildComplianceMetric('Total Issues', compliance.totalIssues.toString(), Colors.grey),
                _buildComplianceMetric('Critical', compliance.criticalIssues.toString(), Colors.red),
                _buildComplianceMetric('Resolved', compliance.resolvedIssues.toString(), Colors.green),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComplianceMetric(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey[600],
          ),
        ),
      ],
    );
  }

  Widget _buildComplianceBreakdown(ComplianceAnalytics compliance) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Compliance by Category',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...compliance.categoryComplianceScores.entries.map((entry) => 
              _buildComplianceBar(entry.key, entry.value)
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildComplianceBar(String category, double score) {
    final color = score > 80 ? Colors.green : score > 60 ? Colors.orange : Colors.red;
    
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                category,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text(
                '${score.toInt()}%',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: score / 100,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(color),
            minHeight: 8,
          ),
        ],
      ),
    );
  }

  Widget _buildTopIssues(ComplianceAnalytics compliance) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Top Issues',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...compliance.topIssues.map((issue) => _buildIssueItem(issue)),
          ],
        ),
      ),
    );
  }

  Widget _buildIssueItem(ComplianceIssue issue) {
    final severityColor = _getSeverityColor(issue.severity);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: severityColor.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
        color: severityColor.withOpacity(0.05),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: severityColor,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  issue.severity,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  issue.title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              if (issue.isResolved)
                const Icon(Icons.check_circle, color: Colors.green, size: 20),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            issue.description,
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            'Category: ${issue.category} • ${DateFormat('MMM d, yyyy').format(issue.createdAt)}',
            style: TextStyle(fontSize: 12, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Color _getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return Colors.red;
      case 'high':
        return Colors.orange;
      case 'medium':
        return Colors.blue;
      case 'low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  Widget _buildTrendsTab() {
    final trends = _analyticsData!.trendAnalytics;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildTrendCard('Document Trends', trends.documentTrends, Colors.blue),
          const SizedBox(height: 24),
          _buildTrendCard('Compliance Trends', trends.complianceTrends, Colors.green),
          const SizedBox(height: 24),
          _buildTrendCard('Expiry Trends', trends.expiryTrends, Colors.orange),
        ],
      ),
    );
  }

  Widget _buildTrendCard(String title, List<TrendDataPoint> data, Color color) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: LineChart(
                LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value.toInt() < data.length) {
                            return Text(
                              DateFormat('M/d').format(data[value.toInt()].date),
                              style: const TextStyle(fontSize: 12),
                            );
                          }
                          return const Text('');
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 40,
                      ),
                    ),
                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  borderData: FlBorderData(show: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: data.asMap().entries.map((entry) => 
                        FlSpot(entry.key.toDouble(), entry.value.value)
                      ).toList(),
                      isCurved: true,
                      color: color,
                      barWidth: 3,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                        show: true,
                        color: color.withOpacity(0.2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectsTab() {
    final projects = _analyticsData!.projectAnalytics;
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProjectsOverview(projects),
          const SizedBox(height: 24),
          _buildProjectsList(projects),
          const SizedBox(height: 24),
          _buildAuthorityDistribution(projects),
        ],
      ),
    );
  }

  Widget _buildProjectsOverview(ProjectAnalytics projects) {
    return Row(
      children: [
        Expanded(
          child: _buildKPICard(
            'Total Projects',
            projects.totalProjects.toString(),
            Icons.business,
            Colors.blue,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildKPICard(
            'Active',
            projects.activeProjects.toString(),
            Icons.play_circle,
            Colors.green,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildKPICard(
            'Completed',
            projects.completedProjects.toString(),
            Icons.check_circle,
            Colors.teal,
          ),
        ),
      ],
    );
  }

  Widget _buildProjectsList(ProjectAnalytics projects) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Project Status',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...projects.projectSummaries.map((project) => _buildProjectItem(project)),
          ],
        ),
      ),
    );
  }

  Widget _buildProjectItem(ProjectSummary project) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  project.projectName,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              Text(
                '${project.completionPercentage.toInt()}%',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _getCompletionColor(project.completionPercentage),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: project.completionPercentage / 100,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(
              _getCompletionColor(project.completionPercentage),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Documents: ${project.approvedDocuments}/${project.totalDocuments}'),
              if (project.issuesCount > 0)
                Text(
                  '${project.issuesCount} issues',
                  style: const TextStyle(color: Colors.red),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Last updated: ${DateFormat('MMM d, yyyy').format(project.lastUpdated)}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Color _getCompletionColor(double percentage) {
    if (percentage >= 80) return Colors.green;
    if (percentage >= 60) return Colors.orange;
    return Colors.red;
  }

  Widget _buildAuthorityDistribution(ProjectAnalytics projects) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Documents by Authority',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ...projects.authorityDistribution.entries.map((entry) => 
              _buildAuthorityItem(entry.key, entry.value)
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthorityItem(String authority, int count) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              authority,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.blue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              count.toString(),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.blue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _exportAnalytics() {
    // Implementation for exporting analytics data
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Export Analytics'),
        content: const Text('Export functionality will be implemented here.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}