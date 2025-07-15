import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class StackMonitoringData {
  final String? id;
  final String source;
  final String consentChimney;
  final String consentApcSystem;
  final String providedChimney;
  final String providedApcSystem;
  final String parameter;
  final String standard;
  final String results;
  final String comments;
  final DateTime timestamp;
  final String status;

  StackMonitoringData({
    this.id,
    required this.source,
    required this.consentChimney,
    required this.consentApcSystem,
    required this.providedChimney,
    required this.providedApcSystem,
    required this.parameter,
    required this.standard,
    required this.results,
    required this.comments,
    required this.timestamp,
    required this.status,
  });

  factory StackMonitoringData.fromJson(Map<String, dynamic> json) {
    return StackMonitoringData(
      id: json['id']?.toString(),
      source: json['source'] ?? '',
      consentChimney: json['consent_chimney'] ?? '',
      consentApcSystem: json['consent_apc_system'] ?? '',
      providedChimney: json['provided_chimney'] ?? '',
      providedApcSystem: json['provided_apc_system'] ?? '',
      parameter: json['parameter'] ?? '',
      standard: json['standard'] ?? '',
      results: json['results'] ?? '',
      comments: json['comments'] ?? '',
      timestamp: DateTime.parse(json['timestamp']),
      status: json['status'] ?? 'active',
    );
  }

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {
      'source': source,
      'consent_chimney': consentChimney,
      'consent_apc_system': consentApcSystem,
      'provided_chimney': providedChimney,
      'provided_apc_system': providedApcSystem,
      'parameter': parameter,
      'standard': standard,
      'results': results,
      'comments': comments,
      'status': status,
    };
    
    if (id != null) {
      json['id'] = id;
    }
    
    return json;
  }
}

class StackMonitoringPage extends StatefulWidget {
  @override
  _StackMonitoringPageState createState() => _StackMonitoringPageState();
}

class _StackMonitoringPageState extends State<StackMonitoringPage> {
  List<StackMonitoringData> _monitoringData = [];
  List<StackMonitoringData> _filteredData = [];
  final String _baseUrl = 'http://54.146.215.18:3000';

  final TextEditingController _sourceController = TextEditingController();
  final TextEditingController _consentChimneyController = TextEditingController();
  final TextEditingController _consentApcController = TextEditingController();
  final TextEditingController _providedChimneyController = TextEditingController();
  final TextEditingController _providedApcController = TextEditingController();
  final TextEditingController _standardController = TextEditingController();
  final TextEditingController _resultsController = TextEditingController();
  final TextEditingController _commentsController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  String _selectedParameter = 'SO2';
  String _selectedStatus = 'active';
  String _filterParameter = 'All';
  String _filterStatus = 'All';
  bool _isAscending = true;
  String _sortColumn = 'source';
  bool _isLoading = false;

  final List<String> _parameterOptions = [
    'SO2', 'SPM', 'PM2.5', 'PM10', 'NOx', 'CO', 'CO2', 'HCl', 'HF', 'VOC'
  ];

  final List<String> _statusOptions = ['active', 'inactive', 'maintenance', 'critical'];

  @override
  void initState() {
    super.initState();
    _fetchMonitoringData();
  }

  @override
  void dispose() {
    _sourceController.dispose();
    _consentChimneyController.dispose();
    _consentApcController.dispose();
    _providedChimneyController.dispose();
    _providedApcController.dispose();
    _standardController.dispose();
    _resultsController.dispose();
    _commentsController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchMonitoringData() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.http('54.146.215.18:3000', '/stack-monitoring'));

      if (response.statusCode == 200) {
        final List<dynamic> responseData = json.decode(response.body)['data'];
        setState(() {
          _monitoringData = responseData
              .map((data) => StackMonitoringData.fromJson(data))
              .toList();
          _filteredData = _monitoringData;
        });
      } else {
        _showErrorSnackBar('Failed to load monitoring data');
      }
    } catch (e) {
      _showErrorSnackBar('Error connecting to server');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Stack Monitoring System',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.teal,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchMonitoringData,
            tooltip: 'Refresh Data',
          ),
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
            tooltip: 'Filter Data',
          ),
        ],
      ),
      body: _buildBody(),
      floatingActionButton: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.teal.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: FloatingActionButton.extended(
          onPressed: () => _showAddEditDialog(),
          backgroundColor: Colors.teal,
          foregroundColor: Colors.white,
          elevation: 0,
          icon: const Icon(Icons.add_circle_outline),
          label: const Text(
            'Add Data',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.teal),
            ),
            const SizedBox(height: 16),
            Text(
              'Loading stack monitoring data...',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      color: Colors.grey[50],
      child: Column(
        children: [
          _buildSearchBar(),
          _buildParameterFilter(),
          _buildStatusFilter(),
          Expanded(
            child: _filteredData.isEmpty
                ? _buildEmptyState()
                : _buildDataTable(),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Container(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(50),
              ),
              child: Icon(
                Icons.factory,
                size: 64,
                color: Colors.grey[400],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No stack monitoring data available',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: Colors.grey[700],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Start by adding your first stack monitoring record',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _showAddEditDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Add First Record'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(16.0),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          decoration: InputDecoration(
            labelText: 'Search by source or parameter',
            labelStyle: TextStyle(color: Colors.grey[600]),
            prefixIcon: Icon(
              Icons.search,
              color: Colors.teal,
            ),
            suffixIcon: _searchController.text.isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.clear, color: Colors.grey[600]),
                    onPressed: () {
                      _searchController.clear();
                      _filterData('');
                    },
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            filled: true,
            fillColor: Colors.grey[50],
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
          ),
          onChanged: _filterData,
        ),
      ),
    );
  }

  Widget _buildParameterFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Filter by Parameter:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['All', ..._parameterOptions].map((parameter) {
                final isSelected = _filterParameter == parameter;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: FilterChip(
                    selected: isSelected,
                    label: Text(
                      parameter,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                    onSelected: (selected) {
                      setState(() {
                        _filterParameter = parameter;
                        _filterData(_searchController.text);
                      });
                    },
                    backgroundColor: Colors.grey[100],
                    selectedColor: parameter == 'All' 
                        ? Colors.teal.withOpacity(0.2)
                        : _getParameterColor(parameter).withOpacity(0.2),
                    checkmarkColor: parameter == 'All' 
                        ? Colors.teal
                        : _getParameterColor(parameter),
                    side: BorderSide(
                      color: isSelected 
                          ? (parameter == 'All' 
                              ? Colors.teal 
                              : _getParameterColor(parameter))
                          : Colors.grey.withOpacity(0.3),
                      width: isSelected ? 2 : 1,
                    ),
                    elevation: isSelected ? 2 : 0,
                    pressElevation: 4,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusFilter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Filter by Status:',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: ['All', ..._statusOptions].map((status) {
                final isSelected = _filterStatus == status;
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: FilterChip(
                    selected: isSelected,
                    label: Text(
                      status.capitalize(),
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        fontSize: 12,
                      ),
                    ),
                    onSelected: (selected) {
                      setState(() {
                        _filterStatus = status;
                        _filterData(_searchController.text);
                      });
                    },
                    backgroundColor: Colors.grey[100],
                    selectedColor: status == 'All' 
                        ? Colors.teal.withOpacity(0.2)
                        : _getStatusColor(status).withOpacity(0.2),
                    checkmarkColor: status == 'All' 
                        ? Colors.teal
                        : _getStatusColor(status),
                    side: BorderSide(
                      color: isSelected 
                          ? (status == 'All' 
                              ? Colors.teal 
                              : _getStatusColor(status))
                          : Colors.grey.withOpacity(0.3),
                      width: isSelected ? 2 : 1,
                    ),
                    elevation: isSelected ? 2 : 0,
                    pressElevation: 4,
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDataTable() {
    // Define more compact column widths to prevent overflow
    final List<double> columnWidths = [
      50,   // No.
      120,  // Source  
      160,  // Consent Condition
      160,  // Provided
      80,   // Parameter
      80,   // Standard
      80,   // Results
      80,   // Status
      100,  // Comments
      90,   // Actions
    ];

    // Group data by source for multiple parameters per source
    final Map<String, List<StackMonitoringData>> groupedData = {};
    for (final data in _filteredData) {
      if (!groupedData.containsKey(data.source)) {
        groupedData[data.source] = [];
      }
      groupedData[data.source]!.add(data);
    }

    return Card(
      margin: const EdgeInsets.all(16.0),
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          // Fixed Header
          Container(
            decoration: BoxDecoration(
              color: Colors.teal.withOpacity(0.1),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: _buildSyncedHeader(columnWidths),
          ),
          // Divider
          Divider(height: 1, color: Colors.grey[300]),
          // Scrollable Data
          Expanded(
            child: _buildGroupedDataRows(groupedData, columnWidths),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedDataRows(Map<String, List<StackMonitoringData>> groupedData, List<double> columnWidths) {
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: Column(
          children: groupedData.entries.expand((entry) {
            final String source = entry.key;
            final List<StackMonitoringData> sourceData = entry.value;
            
            return sourceData.asMap().entries.map((paramEntry) {
              final int paramIndex = paramEntry.key;
              final StackMonitoringData data = paramEntry.value;
              final bool isFirstParam = paramIndex == 0;
              final bool isLastParam = paramIndex == sourceData.length - 1;
              
              return _buildGroupedDataRow(
                source, 
                data, 
                columnWidths, 
                isFirstParam, 
                isLastParam,
                paramIndex + 1,
                sourceData.length,
              );
            }).toList();
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildGroupedDataRow(
    String source, 
    StackMonitoringData data, 
    List<double> columnWidths, 
    bool isFirstParam, 
    bool isLastParam,
    int paramNumber,
    int totalParams,
  ) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isLastParam ? Colors.grey[400]! : Colors.grey[200]!, 
            width: isLastParam ? 1.0 : 0.5,
          ),
          left: isFirstParam ? BorderSide.none : BorderSide(
            color: Colors.teal.withOpacity(0.3),
            width: 2.0,
          ),
        ),
        color: isFirstParam ? Colors.white : Colors.teal.withOpacity(0.02),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // 1. No. (show source info for first param, param number for others)
            Container(
              width: columnWidths[0],
              padding: const EdgeInsets.all(6),
              alignment: Alignment.center,
              child: isFirstParam
                  ? Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.teal.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Source',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                              fontSize: 9,
                            ),
                          ),
                          Text(
                            '$totalParams',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'P$paramNumber',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: Colors.orange[700],
                          fontSize: 10,
                        ),
                      ),
                    ),
            ),
            
            // 2. Source (only show for first parameter)
            Container(
              width: columnWidths[1],
              padding: const EdgeInsets.all(6),
              alignment: Alignment.centerLeft,
              child: isFirstParam
                  ? Text(
                      source,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 11,
                        color: Colors.black87,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    )
                  : Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Container(
                        width: 3,
                        height: 20,
                        decoration: BoxDecoration(
                          color: Colors.teal.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
            ),
            
            // 3. Consent Condition (only show for first parameter)
            Container(
              width: columnWidths[2],
              padding: const EdgeInsets.all(3),
              child: isFirstParam
                  ? Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.05),
                              border: Border.all(color: Colors.blue.withOpacity(0.2)),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              data.consentChimney,
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.blue[700],
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.05),
                              border: Border.all(color: Colors.blue.withOpacity(0.2)),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              data.consentApcSystem,
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.blue[700],
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
            
            // 4. Provided (only show for first parameter)
            Container(
              width: columnWidths[3],
              padding: const EdgeInsets.all(3),
              child: isFirstParam
                  ? Row(
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.05),
                              border: Border.all(color: Colors.green.withOpacity(0.2)),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              data.providedChimney,
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.green[700],
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: Colors.green.withOpacity(0.05),
                              border: Border.all(color: Colors.green.withOpacity(0.2)),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              data.providedApcSystem,
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.green[700],
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
            ),
            
            // 5. Parameter
            Container(
              width: columnWidths[4],
              padding: const EdgeInsets.all(6),
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: _getParameterColor(data.parameter).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: _getParameterColor(data.parameter).withOpacity(0.3),
                  ),
                ),
                child: Text(
                  data.parameter,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _getParameterColor(data.parameter),
                    fontWeight: FontWeight.w600,
                    fontSize: 9,
                  ),
                ),
              ),
            ),
            
            // 6. Standard
            Container(
              width: columnWidths[5],
              padding: const EdgeInsets.all(6),
              alignment: Alignment.center,
              child: Text(
                data.standard,
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            
            // 7. Results
            Container(
              width: columnWidths[6],
              padding: const EdgeInsets.all(6),
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: _getResultsColor(data.results).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  data.results,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w500,
                    color: _getResultsColor(data.results),
                  ),
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            
            // 8. Status
            Container(
              width: columnWidths[7],
              padding: const EdgeInsets.all(6),
              alignment: Alignment.center,
              child: _buildVeryCompactStatusCell(data.status),
            ),
            
            // 9. Comments
            Container(
              width: columnWidths[8],
              padding: const EdgeInsets.all(6),
              alignment: Alignment.centerLeft,
              child: Text(
                data.comments.isEmpty ? '-' : data.comments,
                style: TextStyle(
                  fontSize: 9,
                  color: data.comments.isEmpty ? Colors.grey[500] : Colors.black87,
                  fontStyle: data.comments.isEmpty ? FontStyle.italic : FontStyle.normal,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
            
            // 10. Actions
            Container(
              width: columnWidths[9],
              padding: const EdgeInsets.all(4),
              alignment: Alignment.center,
              child: _buildVeryCompactActionButtons(data, source),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVeryCompactStatusCell(String status) {
    final statusColor = _getStatusColor(status);
    final statusIcon = _getStatusIcon(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, size: 10, color: statusColor),
          const SizedBox(width: 2),
          Text(
            status.substring(0, 1).toUpperCase(),
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.bold,
              fontSize: 8,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVeryCompactActionButtons(StackMonitoringData data, String source) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.green.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: IconButton(
            icon: const Icon(Icons.add, color: Colors.green, size: 12),
            onPressed: () => _showAddParameterDialog(source),
            tooltip: 'Add Parameter',
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
          ),
        ),
        const SizedBox(width: 2),
        Container(
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: IconButton(
            icon: const Icon(Icons.edit, color: Colors.blue, size: 12),
            onPressed: () => _showAddEditDialog(data: data),
            tooltip: 'Edit',
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
          ),
        ),
        const SizedBox(width: 2),
        Container(
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(4),
          ),
          child: IconButton(
            icon: const Icon(Icons.delete, color: Colors.red, size: 12),
            onPressed: () => _showDeleteDialog(data),
            tooltip: 'Delete',
            padding: const EdgeInsets.all(2),
            constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
          ),
        ),
      ],
    );
  }

  void _showAddParameterDialog(String source) {
    // Pre-fill the source field and focus on parameter selection
    final existingSourceData = _monitoringData.where((data) => data.source == source).first;
    
    _sourceController.text = source;
    _consentChimneyController.text = existingSourceData.consentChimney;
    _consentApcController.text = existingSourceData.consentApcSystem;
    _providedChimneyController.text = existingSourceData.providedChimney;
    _providedApcController.text = existingSourceData.providedApcSystem;
    
    _selectedParameter = 'SO2';
    _standardController.clear();
    _resultsController.clear();
    _commentsController.clear();
    _selectedStatus = 'active';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.add_circle, color: Colors.green),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Add Parameter to: $source',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.6,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Source: $source',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[700],
                  ),
                ),
                const SizedBox(height: 16),
                
                // Parameter & Status Section
                Text(
                  'New Parameter Details',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedParameter,
                        decoration: InputDecoration(
                          labelText: 'Parameter',
                          prefixIcon: const Icon(Icons.science),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        items: _parameterOptions.map((parameter) {
                          return DropdownMenuItem(
                            value: parameter,
                            child: Text(parameter),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedParameter = value!;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedStatus,
                        decoration: InputDecoration(
                          labelText: 'Status',
                          prefixIcon: const Icon(Icons.info),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        items: _statusOptions.map((status) {
                          return DropdownMenuItem(
                            value: status,
                            child: Text(status.capitalize()),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedStatus = value!;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildDialogTextField(
                        controller: _standardController,
                        label: 'Standard',
                        icon: Icons.rule,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildDialogTextField(
                        controller: _resultsController,
                        label: 'Results',
                        icon: Icons.assessment,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildDialogTextField(
                  controller: _commentsController,
                  label: 'Comments (Optional)',
                  icon: Icons.comment,
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.cancel),
            label: const Text('Cancel'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey[600],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              if (_validateParameterInputs()) {
                _addMonitoringData();
              }
            },
            icon: const Icon(Icons.add),
            label: const Text('Add Parameter'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _validateParameterInputs() {
    if (_standardController.text.isEmpty ||
        _resultsController.text.isEmpty) {
      _showErrorSnackBar('Please fill standard and results fields');
      return false;
    }
    return true;
  }

  Widget _buildSyncedHeader(List<double> columnWidths) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const ClampingScrollPhysics(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Row(
          children: [
            // No. Column
            Container(
              width: columnWidths[0],
              alignment: Alignment.center,
              child: Text(
                'No.',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                  color: Colors.teal,
                ),
              ),
            ),
            
            // Source Column
            Container(
              width: columnWidths[1],
              alignment: Alignment.centerLeft,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Source',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: Colors.teal,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => _sortData('source'),
                    icon: Icon(
                      _sortColumn == 'source'
                          ? (_isAscending ? Icons.arrow_upward : Icons.arrow_downward)
                          : Icons.unfold_more,
                      size: 12,
                      color: Colors.teal,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
                  ),
                ],
              ),
            ),
            
            // Consent Condition Section
            Container(
              width: columnWidths[2],
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        'Consent Condition',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          color: Colors.blue[700],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.blue.withOpacity(0.3)),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            'Chimney',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w500,
                              color: Colors.blue[600],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.blue.withOpacity(0.3)),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            'APC System',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w500,
                              color: Colors.blue[600],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Provided Section
            Container(
              width: columnWidths[3],
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Text(
                        'Provided',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                          color: Colors.green[700],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.green.withOpacity(0.3)),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            'Chimney',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w500,
                              color: Colors.green[600],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.green.withOpacity(0.3)),
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(
                            'APC System',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: FontWeight.w500,
                              color: Colors.green[600],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            
            // Parameter Column
            Container(
              width: columnWidths[4],
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                'Parameter',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  color: Colors.teal,
                ),
              ),
            ),
            
            // Standard Column
            Container(
              width: columnWidths[5],
              alignment: Alignment.center,
              child: Text(
                'Standard',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  color: Colors.teal,
                ),
              ),
            ),
            
            // Results Column
            Container(
              width: columnWidths[6],
              alignment: Alignment.center,
              child: Text(
                'Results',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  color: Colors.teal,
                ),
              ),
            ),
            
            // Status Column
            Container(
              width: columnWidths[7],
              alignment: Alignment.center,
              child: Text(
                'Status',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  color: Colors.teal,
                ),
              ),
            ),
            
            // Comments Column
            Container(
              width: columnWidths[8],
              alignment: Alignment.center,
              child: Text(
                'Comments',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  color: Colors.teal,
                ),
              ),
            ),
            
            // Actions Column
            Container(
              width: columnWidths[9],
              alignment: Alignment.center,
              child: Text(
                'Actions',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  color: Colors.teal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSyncedDataRows(List<double> columnWidths) {
    return SingleChildScrollView(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const ClampingScrollPhysics(),
        child: Column(
          children: _filteredData.asMap().entries.map((entry) {
            return _buildSyncedDataRow(entry.key + 1, entry.value, columnWidths);
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildSyncedDataRow(int index, StackMonitoringData data, List<double> columnWidths) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.grey[200]!, width: 0.5),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: [
            // 1. No.
            Container(
              width: columnWidths[0],
              padding: const EdgeInsets.all(8),
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.teal.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  index.toString(),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.teal,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            
            // 2. Source
            Container(
              width: columnWidths[1],
              padding: const EdgeInsets.all(8),
              alignment: Alignment.centerLeft,
              child: Text(
                data.source,
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
            
            // 3. Consent Condition
            Container(
              width: columnWidths[2],
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.05),
                        border: Border.all(color: Colors.blue.withOpacity(0.2)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        data.consentChimney,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.blue[700],
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.05),
                        border: Border.all(color: Colors.blue.withOpacity(0.2)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        data.consentApcSystem,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.blue[700],
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // 4. Provided
            Container(
              width: columnWidths[3],
              padding: const EdgeInsets.all(4),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.05),
                        border: Border.all(color: Colors.green.withOpacity(0.2)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        data.providedChimney,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.green[700],
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.05),
                        border: Border.all(color: Colors.green.withOpacity(0.2)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        data.providedApcSystem,
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.green[700],
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            // 5. Parameter
            Container(
              width: columnWidths[4],
              padding: const EdgeInsets.all(8),
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _getParameterColor(data.parameter).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _getParameterColor(data.parameter).withOpacity(0.3),
                  ),
                ),
                child: Text(
                  data.parameter,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _getParameterColor(data.parameter),
                    fontWeight: FontWeight.w600,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
            
            // 6. Standard
            Container(
              width: columnWidths[5],
              padding: const EdgeInsets.all(8),
              alignment: Alignment.centerLeft,
              child: Text(
                data.standard,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            
            // 7. Results
            Container(
              width: columnWidths[6],
              padding: const EdgeInsets.all(8),
              alignment: Alignment.centerLeft,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: _getResultsColor(data.results).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  data.results,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: _getResultsColor(data.results),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            
            // 8. Status
            Container(
              width: columnWidths[7],
              padding: const EdgeInsets.all(8),
              alignment: Alignment.centerLeft,
              child: _buildCompactStatusCell(data.status),
            ),
            
            // 9. Comments
            Container(
              width: columnWidths[8],
              padding: const EdgeInsets.all(8),
              alignment: Alignment.centerLeft,
              child: Text(
                data.comments.isEmpty ? 'No comments' : data.comments,
                style: TextStyle(
                  fontSize: 10,
                  color: data.comments.isEmpty ? Colors.grey[600] : Colors.black87,
                  fontStyle: data.comments.isEmpty ? FontStyle.italic : FontStyle.normal,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
            
            // 10. Actions
            Container(
              width: columnWidths[9],
              padding: const EdgeInsets.all(4),
              alignment: Alignment.center,
              child: _buildCompactActionButtons(data),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactStatusCell(String status) {
    final statusColor = _getStatusColor(status);
    final statusIcon = _getStatusIcon(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: statusColor.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, size: 12, color: statusColor),
          const SizedBox(width: 3),
          Text(
            status.capitalize(),
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactActionButtons(StackMonitoringData data) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: IconButton(
            icon: const Icon(Icons.edit, color: Colors.blue, size: 16),
            onPressed: () => _showAddEditDialog(data: data),
            tooltip: 'Edit',
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ),
        const SizedBox(width: 4),
        Container(
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: IconButton(
            icon: const Icon(Icons.delete, color: Colors.red, size: 16),
            onPressed: () => _showDeleteDialog(data),
            tooltip: 'Delete',
            padding: const EdgeInsets.all(4),
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ),
      ],
    );
  }

  Widget _buildCustomHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // No. Column
            Container(
              width: 50,
              alignment: Alignment.center,
              child: Text(
                'No.',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.teal,
                ),
              ),
            ),
            const SizedBox(width: 15),
            
            // Source Column
            Container(
              width: 120,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Text(
                    'Source',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.teal,
                    ),
                  ),
                  IconButton(
                    onPressed: () => _sortData('source'),
                    icon: Icon(
                      _sortColumn == 'source'
                          ? (_isAscending ? Icons.arrow_upward : Icons.arrow_downward)
                          : Icons.unfold_more,
                      size: 16,
                      color: Colors.teal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 15),
            
            // Consent Condition Section
            Container(
              width: 200,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.blue.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        'Consent Condition',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.blue[700],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.blue.withOpacity(0.3)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Chimney',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.blue[600],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.blue.withOpacity(0.3)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'APC System',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.blue[600],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 15),
            
            // Provided Section
            Container(
              width: 200,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.green.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        'Provided',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: Colors.green[700],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.green.withOpacity(0.3)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Chimney',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.green[600],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.green.withOpacity(0.3)),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'APC System',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: Colors.green[600],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 15),
            
            // Parameter Column
            Container(
              width: 100,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Text(
                    'Parameter',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.teal,
                    ),
                  ),
                  IconButton(
                    onPressed: () => _sortData('parameter'),
                    icon: Icon(
                      _sortColumn == 'parameter'
                          ? (_isAscending ? Icons.arrow_upward : Icons.arrow_downward)
                          : Icons.unfold_more,
                      size: 16,
                      color: Colors.teal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 15),
            
            // Standard Column
            Container(
              width: 100,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Text(
                    'Standard',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.teal,
                    ),
                  ),
                  IconButton(
                    onPressed: () => _sortData('standard'),
                    icon: Icon(
                      _sortColumn == 'standard'
                          ? (_isAscending ? Icons.arrow_upward : Icons.arrow_downward)
                          : Icons.unfold_more,
                      size: 16,
                      color: Colors.teal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 15),
            
            // Results Column
            Container(
              width: 100,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Text(
                    'Results',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.teal,
                    ),
                  ),
                  IconButton(
                    onPressed: () => _sortData('results'),
                    icon: Icon(
                      _sortColumn == 'results'
                          ? (_isAscending ? Icons.arrow_upward : Icons.arrow_downward)
                          : Icons.unfold_more,
                      size: 16,
                      color: Colors.teal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 15),
            
            // Status Column
            Container(
              width: 100,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Text(
                    'Status',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.teal,
                    ),
                  ),
                  IconButton(
                    onPressed: () => _sortData('status'),
                    icon: Icon(
                      _sortColumn == 'status'
                          ? (_isAscending ? Icons.arrow_upward : Icons.arrow_downward)
                          : Icons.unfold_more,
                      size: 16,
                      color: Colors.teal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 15),
            
            // Comments Column
            Container(
              width: 120,
              alignment: Alignment.centerLeft,
              child: Row(
                children: [
                  Text(
                    'Comments',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: Colors.teal,
                    ),
                  ),
                  IconButton(
                    onPressed: () => _sortData('comments'),
                    icon: Icon(
                      _sortColumn == 'comments'
                          ? (_isAscending ? Icons.arrow_upward : Icons.arrow_downward)
                          : Icons.unfold_more,
                      size: 16,
                      color: Colors.teal,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 15),
            
            // Actions Column
            Container(
              width: 100,
              alignment: Alignment.center,
              child: Text(
                'Actions',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: Colors.teal,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  DataRow _buildDataRow(int index, StackMonitoringData data) {
    return DataRow(
      cells: [
        // 1. No.
        DataCell(
          Container(
            width: 50,
            alignment: Alignment.center,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.teal.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                index.toString(),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.teal,
                ),
              ),
            ),
          ),
        ),
        
        // 2. Source
        DataCell(
          Container(
            width: 120,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  data.source,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 2,
                ),
              ],
            ),
          ),
        ),
        
        // 3. Consent Condition (Chimney + APC System)
        DataCell(
          Container(
            width: 200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.05),
                          border: Border.all(color: Colors.blue.withOpacity(0.2)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          data.consentChimney,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue[700],
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.05),
                          border: Border.all(color: Colors.blue.withOpacity(0.2)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          data.consentApcSystem,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.blue[700],
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        
        // 4. Provided (Chimney + APC System)
        DataCell(
          Container(
            width: 200,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.05),
                          border: Border.all(color: Colors.green.withOpacity(0.2)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          data.providedChimney,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.green[700],
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green.withOpacity(0.05),
                          border: Border.all(color: Colors.green.withOpacity(0.2)),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          data.providedApcSystem,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.green[700],
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        
        // 5. Parameter
        DataCell(
          Container(
            width: 100,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: _getParameterColor(data.parameter).withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: _getParameterColor(data.parameter).withOpacity(0.3),
                ),
              ),
              child: Text(
                data.parameter,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _getParameterColor(data.parameter),
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ),
        
        // 6. Standard
        DataCell(
          Container(
            width: 100,
            child: Text(
              data.standard,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        
        // 7. Results
        DataCell(
          Container(
            width: 100,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _getResultsColor(data.results).withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                data.results,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: _getResultsColor(data.results),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
        
        // 8. Status
        DataCell(
          Container(
            width: 100,
            child: _buildStatusCell(data.status),
          ),
        ),
        
        // 9. Comments
        DataCell(
          Container(
            width: 120,
            child: Text(
              data.comments.isEmpty ? 'No comments' : data.comments,
              style: TextStyle(
                fontSize: 11,
                color: data.comments.isEmpty ? Colors.grey[600] : Colors.black87,
                fontStyle: data.comments.isEmpty ? FontStyle.italic : FontStyle.normal,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 2,
            ),
          ),
        ),
        
        // 10. Actions
        DataCell(
          Container(
            width: 100,
            child: _buildActionButtons(data),
          ),
        ),
      ],
    );
  }

  Widget _buildStatusCell(String status) {
    final statusColor = _getStatusColor(status);
    final statusIcon = _getStatusIcon(status);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: statusColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: statusColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(statusIcon, size: 14, color: statusColor),
          const SizedBox(width: 4),
          Text(
            status.capitalize(),
            style: TextStyle(
              color: statusColor,
              fontWeight: FontWeight.bold,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Color _getParameterColor(String parameter) {
    switch (parameter) {
      case 'SO2':
        return Colors.red;
      case 'SPM':
        return Colors.orange;
      case 'PM2.5':
        return Colors.purple;
      case 'PM10':
        return Colors.brown;
      case 'NOx':
        return Colors.blue;
      case 'CO':
        return Colors.green;
      case 'CO2':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Colors.green;
      case 'inactive':
        return Colors.grey;
      case 'maintenance':
        return Colors.orange;
      case 'critical':
        return Colors.red;
      default:
        return Colors.blue;
    }
  }

  IconData _getStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Icons.check_circle;
      case 'inactive':
        return Icons.cancel;
      case 'maintenance':
        return Icons.build;
      case 'critical':
        return Icons.warning;
      default:
        return Icons.info;
    }
  }

  Color _getResultsColor(String results) {
    if (results.toLowerCase().contains('good') || results.toLowerCase().contains('normal')) {
      return Colors.green;
    } else if (results.toLowerCase().contains('moderate') || results.toLowerCase().contains('warning')) {
      return Colors.orange;
    } else if (results.toLowerCase().contains('poor') || results.toLowerCase().contains('critical')) {
      return Colors.red;
    }
    return Colors.blue;
  }

  Widget _buildActionButtons(StackMonitoringData data) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.blue.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: IconButton(
            icon: const Icon(Icons.edit, color: Colors.blue, size: 18),
            onPressed: () => _showAddEditDialog(data: data),
            tooltip: 'Edit',
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          decoration: BoxDecoration(
            color: Colors.red.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: IconButton(
            icon: const Icon(Icons.delete, color: Colors.red, size: 18),
            onPressed: () => _showDeleteDialog(data),
            tooltip: 'Delete',
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
        ),
      ],
    );
  }

  void _filterData(String query) {
    setState(() {
      _filteredData = _monitoringData.where((data) {
        final parameter = _filterParameter == 'All' || data.parameter == _filterParameter;
        final status = _filterStatus == 'All' || data.status == _filterStatus;
        final search = data.source.toLowerCase().contains(query.toLowerCase()) ||
            data.parameter.toLowerCase().contains(query.toLowerCase()) ||
            data.results.toLowerCase().contains(query.toLowerCase());
        return parameter && status && search;
      }).toList();
    });
  }

  void _sortData(String column) {
    setState(() {
      if (_sortColumn == column) {
        _isAscending = !_isAscending;
      } else {
        _sortColumn = column;
        _isAscending = true;
      }

      _filteredData.sort((a, b) {
        var comparison;
        switch (column) {
          case 'source':
            comparison = a.source.compareTo(b.source);
            break;
          case 'parameter':
            comparison = a.parameter.compareTo(b.parameter);
            break;
          case 'standard':
            comparison = a.standard.compareTo(b.standard);
            break;
          case 'results':
            comparison = a.results.compareTo(b.results);
            break;
          case 'status':
            comparison = a.status.compareTo(b.status);
            break;
          case 'comments':
            comparison = a.comments.compareTo(b.comments);
            break;
          default:
            comparison = 0;
        }
        return _isAscending ? comparison : -comparison;
      });
    });
  }

  void _showAddEditDialog({StackMonitoringData? data}) {
    if (data != null) {
      _sourceController.text = data.source;
      _consentChimneyController.text = data.consentChimney;
      _consentApcController.text = data.consentApcSystem;
      _providedChimneyController.text = data.providedChimney;
      _providedApcController.text = data.providedApcSystem;
      _selectedParameter = data.parameter;
      _standardController.text = data.standard;
      _resultsController.text = data.results;
      _commentsController.text = data.comments;
      _selectedStatus = data.status;
    } else {
      _sourceController.clear();
      _consentChimneyController.clear();
      _consentApcController.clear();
      _providedChimneyController.clear();
      _providedApcController.clear();
      _selectedParameter = 'SO2';
      _standardController.clear();
      _resultsController.clear();
      _commentsController.clear();
      _selectedStatus = 'active';
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.factory, color: Colors.teal),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                data == null ? 'Add Stack Monitoring Data' : 'Edit Stack Monitoring Data',
                style: const TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Container(
          width: MediaQuery.of(context).size.width * 0.9,
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Source Section
                Text(
                  'Source Information',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal,
                  ),
                ),
                const SizedBox(height: 12),
                _buildDialogTextField(
                  controller: _sourceController,
                  label: 'Air Pollution Source',
                  icon: Icons.source,
                ),
                const SizedBox(height: 20),
                
                // Consent Section
                Text(
                  'Consent Condition',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                  ),
                ),
                const SizedBox(height: 12),
                _buildDialogTextField(
                  controller: _consentChimneyController,
                  label: 'Consent Chimney',
                  icon: Icons.account_tree,
                ),
                const SizedBox(height: 12),
                _buildDialogTextField(
                  controller: _consentApcController,
                  label: 'Consent APC System',
                  icon: Icons.settings,
                ),
                const SizedBox(height: 20),
                
                // Provided Section
                Text(
                  'Provided',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.green[700],
                  ),
                ),
                const SizedBox(height: 12),
                _buildDialogTextField(
                  controller: _providedChimneyController,
                  label: 'Provided Chimney',
                  icon: Icons.account_tree_outlined,
                ),
                const SizedBox(height: 12),
                _buildDialogTextField(
                  controller: _providedApcController,
                  label: 'Provided APC System',
                  icon: Icons.settings_outlined,
                ),
                const SizedBox(height: 20),
                
                // Parameter & Status Section
                Text(
                  'Monitoring Details',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.teal,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedParameter,
                        decoration: InputDecoration(
                          labelText: 'Parameter',
                          prefixIcon: const Icon(Icons.science),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        items: _parameterOptions.map((parameter) {
                          return DropdownMenuItem(
                            value: parameter,
                            child: Text(parameter),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedParameter = value!;
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedStatus,
                        decoration: InputDecoration(
                          labelText: 'Status',
                          prefixIcon: const Icon(Icons.info),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                        ),
                        items: _statusOptions.map((status) {
                          return DropdownMenuItem(
                            value: status,
                            child: Text(status.capitalize()),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setState(() {
                            _selectedStatus = value!;
                          });
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildDialogTextField(
                        controller: _standardController,
                        label: 'Standard',
                        icon: Icons.rule,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildDialogTextField(
                        controller: _resultsController,
                        label: 'Results',
                        icon: Icons.assessment,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildDialogTextField(
                  controller: _commentsController,
                  label: 'Comments (Optional)',
                  icon: Icons.comment,
                  maxLines: 2,
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.pop(context),
            icon: const Icon(Icons.cancel),
            label: const Text('Cancel'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.grey[600],
            ),
          ),
          ElevatedButton.icon(
            onPressed: () {
              if (_validateInputs()) {
                if (data == null) {
                  _addMonitoringData();
                } else {
                  _updateMonitoringData(data);
                }
              }
            },
            icon: const Icon(Icons.save),
            label: Text(data == null ? 'Add' : 'Update'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDialogTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 8,
        ),
        isDense: true,
      ),
      keyboardType: keyboardType,
      maxLines: maxLines,
      style: const TextStyle(fontSize: 14),
    );
  }

  bool _validateInputs() {
    if (_sourceController.text.isEmpty ||
        _consentChimneyController.text.isEmpty ||
        _consentApcController.text.isEmpty ||
        _providedChimneyController.text.isEmpty ||
        _providedApcController.text.isEmpty ||
        _standardController.text.isEmpty ||
        _resultsController.text.isEmpty) {
      _showErrorSnackBar('Please fill all required fields');
      return false;
    }
    return true;
  }

  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Filter Data'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              value: _filterParameter,
              decoration: const InputDecoration(
                labelText: 'Parameter',
                border: OutlineInputBorder(),
              ),
              items: ['All', ..._parameterOptions].map((parameter) {
                return DropdownMenuItem(
                  value: parameter,
                  child: Text(parameter),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _filterParameter = value!;
                  _filterData(_searchController.text);
                });
              },
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _filterStatus,
              decoration: const InputDecoration(
                labelText: 'Status',
                border: OutlineInputBorder(),
              ),
              items: ['All', ..._statusOptions].map((status) {
                return DropdownMenuItem(
                  value: status,
                  child: Text(status.capitalize()),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _filterStatus = value!;
                  _filterData(_searchController.text);
                });
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(StackMonitoringData data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Stack Monitoring Data'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.warning,
              color: Colors.orange,
              size: 48,
            ),
            const SizedBox(height: 16),
            const Text('Are you sure you want to delete this data?'),
            const SizedBox(height: 8),
            Text(
              'Source: ${data.source}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            Text(
              'Parameter: ${data.parameter}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteMonitoringData(data);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  Future<void> _addMonitoringData() async {
    final newData = StackMonitoringData(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      source: _sourceController.text.trim(),
      consentChimney: _consentChimneyController.text.trim(),
      consentApcSystem: _consentApcController.text.trim(),
      providedChimney: _providedChimneyController.text.trim(),
      providedApcSystem: _providedApcController.text.trim(),
      parameter: _selectedParameter,
      standard: _standardController.text.trim(),
      results: _resultsController.text.trim(),
      comments: _commentsController.text.trim(),
      timestamp: DateTime.now(),
      status: _selectedStatus,
    );

    try {
      setState(() => _isLoading = true);
      final response = await http.post(
        Uri.http('54.146.215.18:3000', '/stack-monitoring'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(newData.toJson()),
      );

      if (response.statusCode == 201) {
        setState(() {
          _monitoringData.add(newData);
          _filterData(_searchController.text);
        });
        Navigator.pop(context);
        _showSuccessSnackBar('Stack monitoring data added successfully');
      } else {
        _showErrorSnackBar('Failed to add stack monitoring data');
      }
    } catch (e) {
      _showErrorSnackBar('Error connecting to server');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateMonitoringData(StackMonitoringData oldData) async {
    final updatedData = StackMonitoringData(
      id: oldData.id,
      source: _sourceController.text.trim(),
      consentChimney: _consentChimneyController.text.trim(),
      consentApcSystem: _consentApcController.text.trim(),
      providedChimney: _providedChimneyController.text.trim(),
      providedApcSystem: _providedApcController.text.trim(),
      parameter: _selectedParameter,
      standard: _standardController.text.trim(),
      results: _resultsController.text.trim(),
      comments: _commentsController.text.trim(),
      timestamp: DateTime.now(),
      status: _selectedStatus,
    );

    try {
      setState(() => _isLoading = true);
      final response = await http.put(
        Uri.http('54.146.215.18:3000', '/stack-monitoring/${oldData.id}'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(updatedData.toJson()),
      );

      if (response.statusCode == 200) {
        setState(() {
          final index = _monitoringData.indexWhere((data) => data.id == oldData.id);
          if (index != -1) {
            _monitoringData[index] = updatedData;
            _filterData(_searchController.text);
          }
        });
        Navigator.pop(context);
        _showSuccessSnackBar('Stack monitoring data updated successfully');
      } else {
        _showErrorSnackBar('Failed to update stack monitoring data');
      }
    } catch (e) {
      _showErrorSnackBar('Error connecting to server');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteMonitoringData(StackMonitoringData data) async {
    try {
      setState(() => _isLoading = true);
      final response = await http.delete(
        Uri.http('54.146.215.18:3000', '/stack-monitoring/${data.id}'),
      );

      if (response.statusCode == 200) {
        setState(() {
          _monitoringData.removeWhere((item) => item.id == data.id);
          _filterData(_searchController.text);
        });
        _showSuccessSnackBar('Stack monitoring data deleted successfully');
      } else {
        _showErrorSnackBar('Failed to delete stack monitoring data');
      }
    } catch (e) {
      _showErrorSnackBar('Error connecting to server');
    } finally {
      setState(() => _isLoading = false);
    }
  }
}

extension StringExtension on String {
  String capitalize() {
    return "${this[0].toUpperCase()}${substring(1).toLowerCase()}";
  }
}