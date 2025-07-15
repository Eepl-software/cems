import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';


class AmbientAirMonitoringData {
  final String id;
  final String location;
  final String consentChimney;
  final String consentApcSystem;
  final String providedChimney;
  final String providedApcSystem;
  final String parameter;
  final String standard;
  final String results;
  final String comments;
  final DateTime timestamp;

  AmbientAirMonitoringData({
    required this.id,
    required this.location,
    required this.consentChimney,
    required this.consentApcSystem,
    required this.providedChimney,
    required this.providedApcSystem,
    required this.parameter,
    required this.standard,
    required this.results,
    required this.comments,
    required this.timestamp,
  });

  factory AmbientAirMonitoringData.fromJson(Map<String, dynamic> json) {
    return AmbientAirMonitoringData(
      id: json['id'].toString(),
      location: json['location'] ?? '',
      consentChimney: json['consent_chimney'] ?? '',
      consentApcSystem: json['consent_apc_system'] ?? '',
      providedChimney: json['provided_chimney'] ?? '',
      providedApcSystem: json['provided_apc_system'] ?? '',
      parameter: json['parameter'] ?? '',
      standard: json['standard'] ?? '',
      results: json['results'] ?? '',
      comments: json['comments'] ?? '',
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'location': location,
      'consent_chimney': consentChimney,
      'consent_apc_system': consentApcSystem,
      'provided_chimney': providedChimney,
      'provided_apc_system': providedApcSystem,
      'parameter': parameter,
      'standard': standard,
      'results': results,
      'comments': comments,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

class AmbientAirMonitoringPage extends StatefulWidget {
  const AmbientAirMonitoringPage({Key? key}) : super(key: key);

  @override
  AmbientAirMonitoringPageState createState() => AmbientAirMonitoringPageState();
}

class AmbientAirMonitoringPageState extends State<AmbientAirMonitoringPage> {
  List<AmbientAirMonitoringData> _monitoringData = [];
  List<AmbientAirMonitoringData> _filteredData = [];
  final String _baseUrl = 'http://54.146.215.18:3000';

  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _consentChimneyController = TextEditingController();
  final TextEditingController _consentApcController = TextEditingController();
  final TextEditingController _providedChimneyController = TextEditingController();
  final TextEditingController _providedApcController = TextEditingController();
  final TextEditingController _standardController = TextEditingController();
  final TextEditingController _resultsController = TextEditingController();
  final TextEditingController _commentsController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();

  String _selectedParameter = 'SO2';
  String _filterParameter = 'All';
  bool _isAscending = true;
  String _sortColumn = 'location';
  bool _isLoading = false;

  final List<String> _parameterOptions = [
    'SO2', 'SPM', 'PM2.5', 'PM10', 'NOx', 'CO', 'CO2', 'HCl', 'HF', 'VOC', 'O3', 'NH3'
  ];

  @override
  void initState() {
    super.initState();
    _fetchMonitoringData();
  }

  @override
  void dispose() {
    _locationController.dispose();
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
      final response = await http.get(Uri.http('54.146.215.18:3000', '/ambient-monitoring'));

      if (response.statusCode == 200) {
        final List<dynamic> responseData = json.decode(response.body)['data'];
        setState(() {
          _monitoringData = responseData
              .map((data) => AmbientAirMonitoringData.fromJson(data))
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
        title: const Text('Ambient Air Monitoring'),
        backgroundColor: Theme.of(context).primaryColor,
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddEditDialog(),
        backgroundColor: Theme.of(context).primaryColor,
        icon: const Icon(Icons.add),
        label: const Text('Add Data'),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        _buildSearchBar(),
        _buildParameterFilter(),
        Expanded(
          child: _filteredData.isEmpty
              ? _buildEmptyState()
              : _buildDataTable(),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.air,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No monitoring data available',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          labelText: 'Search by location or parameter',
          prefixIcon: const Icon(Icons.search),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
          fillColor: Colors.grey[100],
        ),
        onChanged: _filterData,
      ),
    );
  }

  Widget _buildParameterFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: ['All', ..._parameterOptions].map((parameter) {
          final isSelected = _filterParameter == parameter;
          return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: FilterChip(
              selected: isSelected,
              label: Text(parameter),
              onSelected: (selected) {
                setState(() {
                  _filterParameter = parameter;
                  _filterData(_searchController.text);
                });
              },
              backgroundColor: Colors.grey[100],
              selectedColor: Theme.of(context).primaryColor.withOpacity(0.2),
              checkmarkColor: Theme.of(context).primaryColor,
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDataTable() {
    return Card(
      margin: const EdgeInsets.all(16.0),
      elevation: 2,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SingleChildScrollView(
          child: DataTable(
            headingRowColor: MaterialStateProperty.all(Colors.grey[100]),
            dataRowHeight: 80,
            columnSpacing: 20,
            columns: [
              const DataColumn(label: Text('No.', style: TextStyle(fontWeight: FontWeight.bold))),
              _buildDataColumn('Location', 'location'),
              const DataColumn(
                label: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Consent Condition', style: TextStyle(fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        Text('Chimney', style: TextStyle(fontSize: 10)),
                        SizedBox(width: 20),
                        Text('APC System', style: TextStyle(fontSize: 10)),
                      ],
                    ),
                  ],
                ),
              ),
              const DataColumn(
                label: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Provided', style: TextStyle(fontWeight: FontWeight.bold)),
                    Row(
                      children: [
                        Text('Chimney', style: TextStyle(fontSize: 10)),
                        SizedBox(width: 20),
                        Text('APC System', style: TextStyle(fontSize: 10)),
                      ],
                    ),
                  ],
                ),
              ),
              _buildDataColumn('Parameter', 'parameter'),
              _buildDataColumn('Standard', 'standard'),
              _buildDataColumn('Results', 'results'),
              _buildDataColumn('Comments', 'comments'),
              const DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
            ],
            rows: _filteredData.asMap().entries.map((entry) {
              return _buildDataRow(entry.key + 1, entry.value);
            }).toList(),
          ),
        ),
      ),
    );
  }

  DataColumn _buildDataColumn(String label, String column) {
    final isSort = _sortColumn == column;
    return DataColumn(
      label: Row(
        children: [
          Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (isSort)
            Icon(
              _isAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 16,
            ),
        ],
      ),
      onSort: (_, __) => _sortData(column),
    );
  }

  DataRow _buildDataRow(int index, AmbientAirMonitoringData data) {
    return DataRow(
      cells: [
        DataCell(Text(index.toString())),
        DataCell(Container(
          width: 120,
          child: Text(data.location, overflow: TextOverflow.ellipsis),
        )),
        DataCell(
          Container(
            width: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        data.consentChimney,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        data.consentApcSystem,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        DataCell(
          Container(
            width: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        data.providedChimney,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        data.providedApcSystem,
                        style: const TextStyle(fontSize: 12),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        DataCell(
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _getParameterColor(data.parameter).withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              data.parameter,
              style: TextStyle(
                color: _getParameterColor(data.parameter),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        DataCell(Text(data.standard)),
        DataCell(Text(data.results)),
        DataCell(Container(
          width: 120,
          child: Text(data.comments, overflow: TextOverflow.ellipsis),
        )),
        DataCell(_buildActionButtons(data)),
      ],
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
      case 'O3':
        return Colors.indigo;
      case 'NH3':
        return Colors.pink;
      default:
        return Colors.grey;
    }
  }

  Widget _buildActionButtons(AmbientAirMonitoringData data) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.edit, color: Colors.blue),
          onPressed: () => _showAddEditDialog(data: data),
          tooltip: 'Edit',
        ),
        IconButton(
          icon: const Icon(Icons.delete, color: Colors.red),
          onPressed: () => _showDeleteDialog(data),
          tooltip: 'Delete',
        ),
      ],
    );
  }

  void _filterData(String query) {
    setState(() {
      _filteredData = _monitoringData.where((data) {
        final parameter = _filterParameter == 'All' || data.parameter == _filterParameter;
        final search = data.location.toLowerCase().contains(query.toLowerCase()) ||
            data.parameter.toLowerCase().contains(query.toLowerCase());
        return parameter && search;
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
          case 'location':
            comparison = a.location.compareTo(b.location);
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

  void _showAddEditDialog({AmbientAirMonitoringData? data}) {
    if (data != null) {
      _locationController.text = data.location;
      _consentChimneyController.text = data.consentChimney;
      _consentApcController.text = data.consentApcSystem;
      _providedChimneyController.text = data.providedChimney;
      _providedApcController.text = data.providedApcSystem;
      _selectedParameter = data.parameter;
      _standardController.text = data.standard;
      _resultsController.text = data.results;
      _commentsController.text = data.comments;
    } else {
      _locationController.clear();
      _consentChimneyController.clear();
      _consentApcController.clear();
      _providedChimneyController.clear();
      _providedApcController.clear();
      _selectedParameter = 'SO2';
      _standardController.clear();
      _resultsController.clear();
      _commentsController.clear();
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(data == null ? 'Add Monitoring Data' : 'Edit Monitoring Data'),
        content: SingleChildScrollView(
          child: SizedBox(
            width: MediaQuery.of(context).size.width * 0.8,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDialogTextField(
                  controller: _locationController,
                  label: 'Location',
                  icon: Icons.location_on,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildDialogTextField(
                        controller: _consentChimneyController,
                        label: 'Consent Chimney',
                        icon: Icons.account_tree,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildDialogTextField(
                        controller: _consentApcController,
                        label: 'Consent APC System',
                        icon: Icons.settings,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildDialogTextField(
                        controller: _providedChimneyController,
                        label: 'Provided Chimney',
                        icon: Icons.account_tree_outlined,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildDialogTextField(
                        controller: _providedApcController,
                        label: 'Provided APC System',
                        icon: Icons.settings_outlined,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedParameter,
                  decoration: InputDecoration(
                    labelText: 'Parameter',
                    prefixIcon: const Icon(Icons.science),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
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
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildDialogTextField(
                        controller: _standardController,
                        label: 'Standard',
                        icon: Icons.rule,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildDialogTextField(
                        controller: _resultsController,
                        label: 'Results',
                        icon: Icons.assessment,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _buildDialogTextField(
                  controller: _commentsController,
                  label: 'Comments',
                  icon: Icons.comment,
                  maxLines: 3,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_validateInputs()) {
                if (data == null) {
                  _addMonitoringData();
                } else {
                  _updateMonitoringData(data);
                }
              }
            },
            child: Text(data == null ? 'Add' : 'Update'),
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
        prefixIcon: Icon(icon),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      keyboardType: keyboardType,
      maxLines: maxLines,
    );
  }

  bool _validateInputs() {
    if (_locationController.text.isEmpty ||
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
        title: const Text('Filter by Parameter'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: ['All', ..._parameterOptions].map((parameter) {
            return ListTile(
              title: Text(parameter),
              leading: Radio<String>(
                value: parameter,
                groupValue: _filterParameter,
                onChanged: (value) {
                  setState(() {
                    _filterParameter = value!;
                    _filterData(_searchController.text);
                  });
                  Navigator.pop(context);
                },
              ),
            );
          }).toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog(AmbientAirMonitoringData data) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Monitoring Data'),
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
              'Location: ${data.location}',
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
    final newData = AmbientAirMonitoringData(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      location: _locationController.text.trim(),
      consentChimney: _consentChimneyController.text.trim(),
      consentApcSystem: _consentApcController.text.trim(),
      providedChimney: _providedChimneyController.text.trim(),
      providedApcSystem: _providedApcController.text.trim(),
      parameter: _selectedParameter,
      standard: _standardController.text.trim(),
      results: _resultsController.text.trim(),
      comments: _commentsController.text.trim(),
      timestamp: DateTime.now(),
    );

    try {
      setState(() => _isLoading = true);
      final response = await http.post(
        Uri.http('54.146.215.18:3000', '/ambient-monitoring'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(newData.toJson()),
      );

      if (response.statusCode == 201) {
        setState(() {
          _monitoringData.add(newData);
          _filterData(_searchController.text);
        });
        Navigator.pop(context);
        _showSuccessSnackBar('Monitoring data added successfully');
      } else {
        _showErrorSnackBar('Failed to add monitoring data');
      }
    } catch (e) {
      _showErrorSnackBar('Error connecting to server');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateMonitoringData(AmbientAirMonitoringData oldData) async {
    final updatedData = AmbientAirMonitoringData(
      id: oldData.id,
      location: _locationController.text.trim(),
      consentChimney: _consentChimneyController.text.trim(),
      consentApcSystem: _consentApcController.text.trim(),
      providedChimney: _providedChimneyController.text.trim(),
      providedApcSystem: _providedApcController.text.trim(),
      parameter: _selectedParameter,
      standard: _standardController.text.trim(),
      results: _resultsController.text.trim(),
      comments: _commentsController.text.trim(),
      timestamp: DateTime.now(),
    );

    try {
      setState(() => _isLoading = true);
      final response = await http.put(
        Uri.http('54.146.215.18:3000', '/ambient-monitoring/${oldData.id}'),
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
        _showSuccessSnackBar('Monitoring data updated successfully');
      } else {
        _showErrorSnackBar('Failed to update monitoring data');
      }
    } catch (e) {
      _showErrorSnackBar('Error connecting to server');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _deleteMonitoringData(AmbientAirMonitoringData data) async {
    try {
      setState(() => _isLoading = true);
      final response = await http.delete(
        Uri.http('54.146.215.18:3000', '/ambient-monitoring/${data.id}'),
      );

      if (response.statusCode == 200) {
        setState(() {
          _monitoringData.removeWhere((item) => item.id == data.id);
          _filterData(_searchController.text);
        });
        _showSuccessSnackBar('Monitoring data deleted successfully');
      } else {
        _showErrorSnackBar('Failed to delete monitoring data');
      }
    } catch (e) {
      _showErrorSnackBar('Error connecting to server');
    } finally {
      setState(() => _isLoading = false);
    }
  }
}













// class AmbientAirMonitoringData {
//   final String id;
//   final String location;
//   final String consentChimney;
//   final String consentApcSystem;
//   final String providedChimney;
//   final String providedApcSystem;
//   final String parameter;
//   final String standard;
//   final String results;
//   final String comments;
//   final DateTime timestamp;

//   AmbientAirMonitoringData({
//     required this.id,
//     required this.location,
//     required this.consentChimney,
//     required this.consentApcSystem,
//     required this.providedChimney,
//     required this.providedApcSystem,
//     required this.parameter,
//     required this.standard,
//     required this.results,
//     required this.comments,
//     required this.timestamp,
//   });

//   factory AmbientAirMonitoringData.fromJson(Map<String, dynamic> json) {
//     return AmbientAirMonitoringData(
//       id: json['id'].toString(),
//       location: json['location'] ?? '',
//       consentChimney: json['consent_chimney'] ?? '',
//       consentApcSystem: json['consent_apc_system'] ?? '',
//       providedChimney: json['provided_chimney'] ?? '',
//       providedApcSystem: json['provided_apc_system'] ?? '',
//       parameter: json['parameter'] ?? '',
//       standard: json['standard'] ?? '',
//       results: json['results'] ?? '',
//       comments: json['comments'] ?? '',
//       timestamp: DateTime.parse(json['timestamp']),
//     );
//   }

//   Map<String, dynamic> toJson() {
//     return {
//       'id': id,
//       'location': location,
//       'consent_chimney': consentChimney,
//       'consent_apc_system': consentApcSystem,
//       'provided_chimney': providedChimney,
//       'provided_apc_system': providedApcSystem,
//       'parameter': parameter,
//       'standard': standard,
//       'results': results,
//       'comments': comments,
//       'timestamp': timestamp.toIso8601String(),
//     };
//   }
// }

// class AmbientAirMonitoringPage extends StatefulWidget {
//   const AmbientAirMonitoringPage({Key? key}) : super(key: key);

//   @override
//   AmbientAirMonitoringPageState createState() => AmbientAirMonitoringPageState();
// }

// class AmbientAirMonitoringPageState extends State<AmbientAirMonitoringPage> {
//   List<AmbientAirMonitoringData> _monitoringData = [];
//   List<AmbientAirMonitoringData> _filteredData = [];
//   final String _baseUrl = 'http://54.146.215.18:3000';

//   final TextEditingController _locationController = TextEditingController();
//   final TextEditingController _consentChimneyController = TextEditingController();
//   final TextEditingController _consentApcController = TextEditingController();
//   final TextEditingController _providedChimneyController = TextEditingController();
//   final TextEditingController _providedApcController = TextEditingController();
//   final TextEditingController _standardController = TextEditingController();
//   final TextEditingController _resultsController = TextEditingController();
//   final TextEditingController _commentsController = TextEditingController();
//   final TextEditingController _searchController = TextEditingController();

//   String _selectedParameter = 'SO2';
//   String _filterParameter = 'All';
//   bool _isAscending = true;
//   String _sortColumn = 'location';
//   bool _isLoading = false;

//   final List<String> _parameterOptions = [
//     'SO2', 'SPM', 'PM2.5', 'PM10', 'NOx', 'CO', 'CO2', 'HCl', 'HF', 'VOC', 'O3', 'NH3'
//   ];

//   @override
//   void initState() {
//     super.initState();
//     _fetchMonitoringData();
//   }

//   @override
//   void dispose() {
//     _locationController.dispose();
//     _consentChimneyController.dispose();
//     _consentApcController.dispose();
//     _providedChimneyController.dispose();
//     _providedApcController.dispose();
//     _standardController.dispose();
//     _resultsController.dispose();
//     _commentsController.dispose();
//     _searchController.dispose();
//     super.dispose();
//   }

//   Future<void> _fetchMonitoringData() async {
//     setState(() => _isLoading = true);
//     try {
//       final response = await http.get(Uri.parse('$_baseUrl/ambient-monitoring-enhanced'));

//       if (response.statusCode == 200) {
//         final List<dynamic> responseData = json.decode(response.body)['data'];
//         setState(() {
//           _monitoringData = responseData
//               .map((data) => AmbientAirMonitoringData.fromJson(data))
//               .toList();
//           _filteredData = _monitoringData;
//         });
//       } else {
//         _showErrorSnackBar('Failed to load monitoring data');
//       }
//     } catch (e) {
//       _showErrorSnackBar('Error connecting to server');
//     } finally {
//       setState(() => _isLoading = false);
//     }
//   }

//   void _showErrorSnackBar(String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text(message),
//         backgroundColor: Colors.red,
//         behavior: SnackBarBehavior.floating,
//         shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(10),
//         ),
//       ),
//     );
//   }

//   void _showSuccessSnackBar(String message) {
//     ScaffoldMessenger.of(context).showSnackBar(
//       SnackBar(
//         content: Text(message),
//         backgroundColor: Colors.green,
//         behavior: SnackBarBehavior.floating,
//         shape: RoundedRectangleBorder(
//           borderRadius: BorderRadius.circular(10),
//         ),
//       ),
//     );
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: const Text('Ambient Air Monitoring'),
//         backgroundColor: Theme.of(context).primaryColor,
//         elevation: 0,
//         actions: [
//           IconButton(
//             icon: const Icon(Icons.refresh),
//             onPressed: _fetchMonitoringData,
//             tooltip: 'Refresh Data',
//           ),
//           IconButton(
//             icon: const Icon(Icons.filter_list),
//             onPressed: _showFilterDialog,
//             tooltip: 'Filter Data',
//           ),
//         ],
//       ),
//       body: _buildBody(),
//       floatingActionButton: Container(
//         decoration: BoxDecoration(
//           borderRadius: BorderRadius.circular(16),
//           boxShadow: [
//             BoxShadow(
//               color: Theme.of(context).primaryColor.withOpacity(0.3),
//               blurRadius: 8,
//               offset: const Offset(0, 4),
//             ),
//           ],
//         ),
//         child: FloatingActionButton.extended(
//           onPressed: () => _showAddEditDialog(),
//           backgroundColor: Theme.of(context).primaryColor,
//           foregroundColor: Colors.white,
//           elevation: 0,
//           icon: const Icon(Icons.add_circle_outline),
//           label: const Text(
//             'Add Data',
//             style: TextStyle(fontWeight: FontWeight.w600),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildBody() {
//     if (_isLoading) {
//       return Center(
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             CircularProgressIndicator(
//               valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).primaryColor),
//             ),
//             const SizedBox(height: 16),
//             Text(
//               'Loading monitoring data...',
//               style: TextStyle(
//                 color: Colors.grey[600],
//                 fontSize: 16,
//               ),
//             ),
//           ],
//         ),
//       );
//     }

//     return Container(
//       color: Colors.grey[50],
//       child: Column(
//         children: [
//           _buildSearchBar(),
//           _buildParameterFilter(),
//           Expanded(
//             child: _filteredData.isEmpty
//                 ? _buildEmptyState()
//                 : _buildDataTable(),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildEmptyState() {
//     return Center(
//       child: Container(
//         padding: const EdgeInsets.all(32),
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             Container(
//               padding: const EdgeInsets.all(24),
//               decoration: BoxDecoration(
//                 color: Colors.grey[100],
//                 borderRadius: BorderRadius.circular(50),
//               ),
//               child: Icon(
//                 Icons.air,
//                 size: 64,
//                 color: Colors.grey[400],
//               ),
//             ),
//             const SizedBox(height: 24),
//             Text(
//               'No monitoring data available',
//               style: TextStyle(
//                 fontSize: 20,
//                 fontWeight: FontWeight.w600,
//                 color: Colors.grey[700],
//               ),
//             ),
//             const SizedBox(height: 12),
//             Text(
//               'Start by adding your first ambient air monitoring record',
//               style: TextStyle(
//                 fontSize: 16,
//                 color: Colors.grey[600],
//               ),
//               textAlign: TextAlign.center,
//             ),
//             const SizedBox(height: 32),
//             ElevatedButton.icon(
//               onPressed: () => _showAddEditDialog(),
//               icon: const Icon(Icons.add),
//               label: const Text('Add First Record'),
//               style: ElevatedButton.styleFrom(
//                 backgroundColor: Theme.of(context).primaryColor,
//                 foregroundColor: Colors.white,
//                 padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
//                 shape: RoundedRectangleBorder(
//                   borderRadius: BorderRadius.circular(12),
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildSearchBar() {
//     return Container(
//       padding: const EdgeInsets.all(16.0),
//       child: Container(
//         decoration: BoxDecoration(
//           color: Colors.white,
//           borderRadius: BorderRadius.circular(12),
//           boxShadow: [
//             BoxShadow(
//               color: Colors.grey.withOpacity(0.1),
//               blurRadius: 8,
//               offset: const Offset(0, 2),
//             ),
//           ],
//         ),
//         child: TextField(
//           controller: _searchController,
//           decoration: InputDecoration(
//             labelText: 'Search by location or parameter',
//             labelStyle: TextStyle(color: Colors.grey[600]),
//             prefixIcon: Icon(
//               Icons.search,
//               color: Theme.of(context).primaryColor,
//             ),
//             suffixIcon: _searchController.text.isNotEmpty
//                 ? IconButton(
//                     icon: Icon(Icons.clear, color: Colors.grey[600]),
//                     onPressed: () {
//                       _searchController.clear();
//                       _filterData('');
//                     },
//                   )
//                 : null,
//             border: OutlineInputBorder(
//               borderRadius: BorderRadius.circular(12),
//               borderSide: BorderSide.none,
//             ),
//             filled: true,
//             fillColor: Colors.grey[50],
//             contentPadding: const EdgeInsets.symmetric(
//               horizontal: 16,
//               vertical: 16,
//             ),
//           ),
//           onChanged: _filterData,
//         ),
//       ),
//     );
//   }

//   Widget _buildParameterFilter() {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Text(
//             'Filter by Parameter:',
//             style: TextStyle(
//               fontSize: 14,
//               fontWeight: FontWeight.w600,
//               color: Colors.grey[700],
//             ),
//           ),
//           const SizedBox(height: 8),
//           SingleChildScrollView(
//             scrollDirection: Axis.horizontal,
//             child: Row(
//               children: ['All', ..._parameterOptions].map((parameter) {
//                 final isSelected = _filterParameter == parameter;
//                 return Padding(
//                   padding: const EdgeInsets.only(right: 8.0),
//                   child: FilterChip(
//                     selected: isSelected,
//                     label: Text(
//                       parameter,
//                       style: TextStyle(
//                         fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
//                         fontSize: 12,
//                       ),
//                     ),
//                     onSelected: (selected) {
//                       setState(() {
//                         _filterParameter = parameter;
//                         _filterData(_searchController.text);
//                       });
//                     },
//                     backgroundColor: Colors.grey[100],
//                     selectedColor: parameter == 'All' 
//                         ? Theme.of(context).primaryColor.withOpacity(0.2)
//                         : _getParameterColor(parameter).withOpacity(0.2),
//                     checkmarkColor: parameter == 'All' 
//                         ? Theme.of(context).primaryColor
//                         : _getParameterColor(parameter),
//                     side: BorderSide(
//                       color: isSelected 
//                           ? (parameter == 'All' 
//                               ? Theme.of(context).primaryColor 
//                               : _getParameterColor(parameter))
//                           : Colors.grey.withOpacity(0.3),
//                       width: isSelected ? 2 : 1,
//                     ),
//                     elevation: isSelected ? 2 : 0,
//                     pressElevation: 4,
//                   ),
//                 );
//               }).toList(),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildDataTable() {
//     return Card(
//       margin: const EdgeInsets.all(16.0),
//       elevation: 4,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
//       child: Column(
//         children: [
//           // Custom Header
//           Container(
//             decoration: BoxDecoration(
//               color: Theme.of(context).primaryColor.withOpacity(0.1),
//               borderRadius: const BorderRadius.only(
//                 topLeft: Radius.circular(12),
//                 topRight: Radius.circular(12),
//               ),
//             ),
//             child: _buildCustomHeader(),
//           ),
//           // Table Body
//           Expanded(
//             child: SingleChildScrollView(
//               scrollDirection: Axis.horizontal,
//               child: SingleChildScrollView(
//                 child: DataTable(
//                   headingRowHeight: 0, // Hide default headers
//                   dataRowHeight: 70,
//                   columnSpacing: 15,
//                   horizontalMargin: 12,
//                   columns: [
//                     const DataColumn(label: SizedBox.shrink()),
//                     const DataColumn(label: SizedBox.shrink()),
//                     const DataColumn(label: SizedBox.shrink()),
//                     const DataColumn(label: SizedBox.shrink()),
//                     const DataColumn(label: SizedBox.shrink()),
//                     const DataColumn(label: SizedBox.shrink()),
//                     const DataColumn(label: SizedBox.shrink()),
//                     const DataColumn(label: SizedBox.shrink()),
//                     const DataColumn(label: SizedBox.shrink()),
//                     const DataColumn(label: SizedBox.shrink()),
//                   ],
//                   rows: _filteredData.asMap().entries.map((entry) {
//                     return _buildDataRow(entry.key + 1, entry.value);
//                   }).toList(),
//                 ),
//               ),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildCustomHeader() {
//     return Container(
//       padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
//       child: SingleChildScrollView(
//         scrollDirection: Axis.horizontal,
//         child: Row(
//           children: [
//             // No. Column
//             Container(
//               width: 50,
//               alignment: Alignment.center,
//               child: Text(
//                 'No.',
//                 style: TextStyle(
//                   fontWeight: FontWeight.bold,
//                   fontSize: 14,
//                   color: Theme.of(context).primaryColor,
//                 ),
//               ),
//             ),
//             const SizedBox(width: 15),
            
//             // Location Column
//             Container(
//               width: 120,
//               alignment: Alignment.centerLeft,
//               child: Row(
//                 children: [
//                   Text(
//                     'Location',
//                     style: TextStyle(
//                       fontWeight: FontWeight.bold,
//                       fontSize: 14,
//                       color: Theme.of(context).primaryColor,
//                     ),
//                   ),
//                   IconButton(
//                     onPressed: () => _sortData('location'),
//                     icon: Icon(
//                       _sortColumn == 'location'
//                           ? (_isAscending ? Icons.arrow_upward : Icons.arrow_downward)
//                           : Icons.unfold_more,
//                       size: 16,
//                       color: Theme.of(context).primaryColor,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//             const SizedBox(width: 15),
            
//             // Consent Condition Section
//             Container(
//               width: 200,
//               child: Column(
//                 children: [
//                   Container(
//                     padding: const EdgeInsets.symmetric(vertical: 8),
//                     decoration: BoxDecoration(
//                       color: Colors.blue.withOpacity(0.1),
//                       borderRadius: BorderRadius.circular(8),
//                     ),
//                     child: Center(
//                       child: Text(
//                         'Consent Condition',
//                         style: TextStyle(
//                           fontWeight: FontWeight.bold,
//                           fontSize: 14,
//                           color: Colors.blue[700],
//                         ),
//                       ),
//                     ),
//                   ),
//                   const SizedBox(height: 8),
//                   Row(
//                     children: [
//                       Expanded(
//                         child: Container(
//                           padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
//                           decoration: BoxDecoration(
//                             border: Border.all(color: Colors.blue.withOpacity(0.3)),
//                             borderRadius: BorderRadius.circular(6),
//                           ),
//                           child: Text(
//                             'Chimney',
//                             textAlign: TextAlign.center,
//                             style: TextStyle(
//                               fontSize: 12,
//                               fontWeight: FontWeight.w500,
//                               color: Colors.blue[600],
//                             ),
//                           ),
//                         ),
//                       ),
//                       const SizedBox(width: 8),
//                       Expanded(
//                         child: Container(
//                           padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
//                           decoration: BoxDecoration(
//                             border: Border.all(color: Colors.blue.withOpacity(0.3)),
//                             borderRadius: BorderRadius.circular(6),
//                           ),
//                           child: Text(
//                             'APC System',
//                             textAlign: TextAlign.center,
//                             style: TextStyle(
//                               fontSize: 12,
//                               fontWeight: FontWeight.w500,
//                               color: Colors.blue[600],
//                             ),
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ],
//               ),
//             ),
//             const SizedBox(width: 15),
            
//             // Provided Section
//             Container(
//               width: 200,
//               child: Column(
//                 children: [
//                   Container(
//                     padding: const EdgeInsets.symmetric(vertical: 8),
//                     decoration: BoxDecoration(
//                       color: Colors.green.withOpacity(0.1),
//                       borderRadius: BorderRadius.circular(8),
//                     ),
//                     child: Center(
//                       child: Text(
//                         'Provided',
//                         style: TextStyle(
//                           fontWeight: FontWeight.bold,
//                           fontSize: 14,
//                           color: Colors.green[700],
//                         ),
//                       ),
//                     ),
//                   ),
//                   const SizedBox(height: 8),
//                   Row(
//                     children: [
//                       Expanded(
//                         child: Container(
//                           padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
//                           decoration: BoxDecoration(
//                             border: Border.all(color: Colors.green.withOpacity(0.3)),
//                             borderRadius: BorderRadius.circular(6),
//                           ),
//                           child: Text(
//                             'Chimney',
//                             textAlign: TextAlign.center,
//                             style: TextStyle(
//                               fontSize: 12,
//                               fontWeight: FontWeight.w500,
//                               color: Colors.green[600],
//                             ),
//                           ),
//                         ),
//                       ),
//                       const SizedBox(width: 8),
//                       Expanded(
//                         child: Container(
//                           padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
//                           decoration: BoxDecoration(
//                             border: Border.all(color: Colors.green.withOpacity(0.3)),
//                             borderRadius: BorderRadius.circular(6),
//                           ),
//                           child: Text(
//                             'APC System',
//                             textAlign: TextAlign.center,
//                             style: TextStyle(
//                               fontSize: 12,
//                               fontWeight: FontWeight.w500,
//                               color: Colors.green[600],
//                             ),
//                           ),
//                         ),
//                       ),
//                     ],
//                   ),
//                 ],
//               ),
//             ),
//             const SizedBox(width: 15),
            
//             // Parameter Column
//             Container(
//               width: 100,
//               alignment: Alignment.centerLeft,
//               child: Row(
//                 children: [
//                   Text(
//                     'Parameter',
//                     style: TextStyle(
//                       fontWeight: FontWeight.bold,
//                       fontSize: 14,
//                       color: Theme.of(context).primaryColor,
//                     ),
//                   ),
//                   IconButton(
//                     onPressed: () => _sortData('parameter'),
//                     icon: Icon(
//                       _sortColumn == 'parameter'
//                           ? (_isAscending ? Icons.arrow_upward : Icons.arrow_downward)
//                           : Icons.unfold_more,
//                       size: 16,
//                       color: Theme.of(context).primaryColor,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//             const SizedBox(width: 15),
            
//             // Standard Column
//             Container(
//               width: 100,
//               alignment: Alignment.centerLeft,
//               child: Row(
//                 children: [
//                   Text(
//                     'Standard',
//                     style: TextStyle(
//                       fontWeight: FontWeight.bold,
//                       fontSize: 14,
//                       color: Theme.of(context).primaryColor,
//                     ),
//                   ),
//                   IconButton(
//                     onPressed: () => _sortData('standard'),
//                     icon: Icon(
//                       _sortColumn == 'standard'
//                           ? (_isAscending ? Icons.arrow_upward : Icons.arrow_downward)
//                           : Icons.unfold_more,
//                       size: 16,
//                       color: Theme.of(context).primaryColor,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//             const SizedBox(width: 15),
            
//             // Results Column
//             Container(
//               width: 100,
//               alignment: Alignment.centerLeft,
//               child: Row(
//                 children: [
//                   Text(
//                     'Results',
//                     style: TextStyle(
//                       fontWeight: FontWeight.bold,
//                       fontSize: 14,
//                       color: Theme.of(context).primaryColor,
//                     ),
//                   ),
//                   IconButton(
//                     onPressed: () => _sortData('results'),
//                     icon: Icon(
//                       _sortColumn == 'results'
//                           ? (_isAscending ? Icons.arrow_upward : Icons.arrow_downward)
//                           : Icons.unfold_more,
//                       size: 16,
//                       color: Theme.of(context).primaryColor,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//             const SizedBox(width: 15),
            
//             // Comments Column
//             Container(
//               width: 120,
//               alignment: Alignment.centerLeft,
//               child: Row(
//                 children: [
//                   Text(
//                     'Comments',
//                     style: TextStyle(
//                       fontWeight: FontWeight.bold,
//                       fontSize: 14,
//                       color: Theme.of(context).primaryColor,
//                     ),
//                   ),
//                   IconButton(
//                     onPressed: () => _sortData('comments'),
//                     icon: Icon(
//                       _sortColumn == 'comments'
//                           ? (_isAscending ? Icons.arrow_upward : Icons.arrow_downward)
//                           : Icons.unfold_more,
//                       size: 16,
//                       color: Theme.of(context).primaryColor,
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//             const SizedBox(width: 15),
            
//             // Actions Column
//             Container(
//               width: 100,
//               alignment: Alignment.center,
//               child: Text(
//                 'Actions',
//                 style: TextStyle(
//                   fontWeight: FontWeight.bold,
//                   fontSize: 14,
//                   color: Theme.of(context).primaryColor,
//                 ),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   DataColumn _buildDataColumn(String label, String column) {
//     final isSort = _sortColumn == column;
//     return DataColumn(
//       label: Row(
//         children: [
//           Text(
//             label,
//             style: const TextStyle(fontWeight: FontWeight.bold),
//           ),
//           if (isSort)
//             Icon(
//               _isAscending ? Icons.arrow_upward : Icons.arrow_downward,
//               size: 16,
//             ),
//         ],
//       ),
//       onSort: (_, __) => _sortData(column),
//     );
//   }

//   DataRow _buildDataRow(int index, AmbientAirMonitoringData data) {
//     return DataRow(
//       cells: [
//         // No.
//         DataCell(
//           Container(
//             width: 50,
//             alignment: Alignment.center,
//             child: Container(
//               padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//               decoration: BoxDecoration(
//                 color: Theme.of(context).primaryColor.withOpacity(0.1),
//                 borderRadius: BorderRadius.circular(12),
//               ),
//               child: Text(
//                 index.toString(),
//                 style: TextStyle(
//                   fontWeight: FontWeight.bold,
//                   color: Theme.of(context).primaryColor,
//                 ),
//               ),
//             ),
//           ),
//         ),
        
//         // Location
//         DataCell(
//           Container(
//             width: 120,
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: [
//                 Text(
//                   data.location,
//                   style: const TextStyle(
//                     fontWeight: FontWeight.w500,
//                     fontSize: 13,
//                   ),
//                   overflow: TextOverflow.ellipsis,
//                   maxLines: 2,
//                 ),
//               ],
//             ),
//           ),
//         ),
        
//         // Consent Condition (Chimney + APC System)
//         DataCell(
//           Container(
//             width: 200,
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: [
//                 Row(
//                   children: [
//                     Expanded(
//                       child: Container(
//                         padding: const EdgeInsets.all(8),
//                         decoration: BoxDecoration(
//                           color: Colors.blue.withOpacity(0.05),
//                           border: Border.all(color: Colors.blue.withOpacity(0.2)),
//                           borderRadius: BorderRadius.circular(6),
//                         ),
//                         child: Text(
//                           data.consentChimney,
//                           style: TextStyle(
//                             fontSize: 11,
//                             color: Colors.blue[700],
//                           ),
//                           overflow: TextOverflow.ellipsis,
//                           maxLines: 2,
//                         ),
//                       ),
//                     ),
//                     const SizedBox(width: 8),
//                     Expanded(
//                       child: Container(
//                         padding: const EdgeInsets.all(8),
//                         decoration: BoxDecoration(
//                           color: Colors.blue.withOpacity(0.05),
//                           border: Border.all(color: Colors.blue.withOpacity(0.2)),
//                           borderRadius: BorderRadius.circular(6),
//                         ),
//                         child: Text(
//                           data.consentApcSystem,
//                           style: TextStyle(
//                             fontSize: 11,
//                             color: Colors.blue[700],
//                           ),
//                           overflow: TextOverflow.ellipsis,
//                           maxLines: 2,
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ],
//             ),
//           ),
//         ),
        
//         // Provided (Chimney + APC System)
//         DataCell(
//           Container(
//             width: 200,
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               mainAxisAlignment: MainAxisAlignment.center,
//               children: [
//                 Row(
//                   children: [
//                     Expanded(
//                       child: Container(
//                         padding: const EdgeInsets.all(8),
//                         decoration: BoxDecoration(
//                           color: Colors.green.withOpacity(0.05),
//                           border: Border.all(color: Colors.green.withOpacity(0.2)),
//                           borderRadius: BorderRadius.circular(6),
//                         ),
//                         child: Text(
//                           data.providedChimney,
//                           style: TextStyle(
//                             fontSize: 11,
//                             color: Colors.green[700],
//                           ),
//                           overflow: TextOverflow.ellipsis,
//                           maxLines: 2,
//                         ),
//                       ),
//                     ),
//                     const SizedBox(width: 8),
//                     Expanded(
//                       child: Container(
//                         padding: const EdgeInsets.all(8),
//                         decoration: BoxDecoration(
//                           color: Colors.green.withOpacity(0.05),
//                           border: Border.all(color: Colors.green.withOpacity(0.2)),
//                           borderRadius: BorderRadius.circular(6),
//                         ),
//                         child: Text(
//                           data.providedApcSystem,
//                           style: TextStyle(
//                             fontSize: 11,
//                             color: Colors.green[700],
//                           ),
//                           overflow: TextOverflow.ellipsis,
//                           maxLines: 2,
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//               ],
//             ),
//           ),
//         ),
        
//         // Parameter
//         DataCell(
//           Container(
//             width: 100,
//             child: Container(
//               padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
//               decoration: BoxDecoration(
//                 color: _getParameterColor(data.parameter).withOpacity(0.15),
//                 borderRadius: BorderRadius.circular(20),
//                 border: Border.all(
//                   color: _getParameterColor(data.parameter).withOpacity(0.3),
//                 ),
//               ),
//               child: Text(
//                 data.parameter,
//                 textAlign: TextAlign.center,
//                 style: TextStyle(
//                   color: _getParameterColor(data.parameter),
//                   fontWeight: FontWeight.w600,
//                   fontSize: 12,
//                 ),
//               ),
//             ),
//           ),
//         ),
        
//         // Standard
//         DataCell(
//           Container(
//             width: 100,
//             child: Text(
//               data.standard,
//               style: const TextStyle(
//                 fontSize: 12,
//                 fontWeight: FontWeight.w500,
//               ),
//               overflow: TextOverflow.ellipsis,
//             ),
//           ),
//         ),
        
//         // Results
//         DataCell(
//           Container(
//             width: 100,
//             child: Container(
//               padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//               decoration: BoxDecoration(
//                 color: _getResultsColor(data.results).withOpacity(0.1),
//                 borderRadius: BorderRadius.circular(8),
//               ),
//               child: Text(
//                 data.results,
//                 style: TextStyle(
//                   fontSize: 12,
//                   fontWeight: FontWeight.w500,
//                   color: _getResultsColor(data.results),
//                 ),
//                 overflow: TextOverflow.ellipsis,
//               ),
//             ),
//           ),
//         ),
        
//         // Comments
//         DataCell(
//           Container(
//             width: 120,
//             child: Text(
//               data.comments.isEmpty ? 'No comments' : data.comments,
//               style: TextStyle(
//                 fontSize: 11,
//                 color: data.comments.isEmpty ? Colors.grey[600] : Colors.black87,
//                 fontStyle: data.comments.isEmpty ? FontStyle.italic : FontStyle.normal,
//               ),
//               overflow: TextOverflow.ellipsis,
//               maxLines: 2,
//             ),
//           ),
//         ),
        
//         // Actions
//         DataCell(
//           Container(
//             width: 100,
//             child: _buildActionButtons(data),
//           ),
//         ),
//       ],
//     );
//   }

//   Color _getResultsColor(String results) {
//     // You can implement logic to determine color based on results
//     // For now, returning a default color
//     if (results.toLowerCase().contains('good') || results.toLowerCase().contains('normal')) {
//       return Colors.green;
//     } else if (results.toLowerCase().contains('moderate') || results.toLowerCase().contains('warning')) {
//       return Colors.orange;
//     } else if (results.toLowerCase().contains('poor') || results.toLowerCase().contains('critical')) {
//       return Colors.red;
//     }
//     return Colors.blue;
//   }

//   Color _getParameterColor(String parameter) {
//     switch (parameter) {
//       case 'SO2':
//         return Colors.red;
//       case 'SPM':
//         return Colors.orange;
//       case 'PM2.5':
//         return Colors.purple;
//       case 'PM10':
//         return Colors.brown;
//       case 'NOx':
//         return Colors.blue;
//       case 'CO':
//         return Colors.green;
//       case 'CO2':
//         return Colors.teal;
//       case 'O3':
//         return Colors.indigo;
//       case 'NH3':
//         return Colors.pink;
//       default:
//         return Colors.grey;
//     }
//   }

//   Widget _buildActionButtons(AmbientAirMonitoringData data) {
//     return Row(
//       mainAxisSize: MainAxisSize.min,
//       mainAxisAlignment: MainAxisAlignment.center,
//       children: [
//         Container(
//           decoration: BoxDecoration(
//             color: Colors.blue.withOpacity(0.1),
//             borderRadius: BorderRadius.circular(8),
//           ),
//           child: IconButton(
//             icon: const Icon(Icons.edit, color: Colors.blue, size: 18),
//             onPressed: () => _showAddEditDialog(data: data),
//             tooltip: 'Edit',
//             padding: const EdgeInsets.all(8),
//             constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
//           ),
//         ),
//         const SizedBox(width: 8),
//         Container(
//           decoration: BoxDecoration(
//             color: Colors.red.withOpacity(0.1),
//             borderRadius: BorderRadius.circular(8),
//           ),
//           child: IconButton(
//             icon: const Icon(Icons.delete, color: Colors.red, size: 18),
//             onPressed: () => _showDeleteDialog(data),
//             tooltip: 'Delete',
//             padding: const EdgeInsets.all(8),
//             constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
//           ),
//         ),
//       ],
//     );
//   }

//   void _filterData(String query) {
//     setState(() {
//       _filteredData = _monitoringData.where((data) {
//         final parameter = _filterParameter == 'All' || data.parameter == _filterParameter;
//         final search = data.location.toLowerCase().contains(query.toLowerCase()) ||
//             data.parameter.toLowerCase().contains(query.toLowerCase());
//         return parameter && search;
//       }).toList();
//     });
//   }

//   void _sortData(String column) {
//     setState(() {
//       if (_sortColumn == column) {
//         _isAscending = !_isAscending;
//       } else {
//         _sortColumn = column;
//         _isAscending = true;
//       }

//       _filteredData.sort((a, b) {
//         var comparison;
//         switch (column) {
//           case 'location':
//             comparison = a.location.compareTo(b.location);
//             break;
//           case 'parameter':
//             comparison = a.parameter.compareTo(b.parameter);
//             break;
//           case 'standard':
//             comparison = a.standard.compareTo(b.standard);
//             break;
//           case 'results':
//             comparison = a.results.compareTo(b.results);
//             break;
//           case 'comments':
//             comparison = a.comments.compareTo(b.comments);
//             break;
//           default:
//             comparison = 0;
//         }
//         return _isAscending ? comparison : -comparison;
//       });
//     });
//   }

//   void _showAddEditDialog({AmbientAirMonitoringData? data}) {
//     if (data != null) {
//       _locationController.text = data.location;
//       _consentChimneyController.text = data.consentChimney;
//       _consentApcController.text = data.consentApcSystem;
//       _providedChimneyController.text = data.providedChimney;
//       _providedApcController.text = data.providedApcSystem;
//       _selectedParameter = data.parameter;
//       _standardController.text = data.standard;
//       _resultsController.text = data.results;
//       _commentsController.text = data.comments;
//     } else {
//       _locationController.clear();
//       _consentChimneyController.clear();
//       _consentApcController.clear();
//       _providedChimneyController.clear();
//       _providedApcController.clear();
//       _selectedParameter = 'SO2';
//       _standardController.clear();
//       _resultsController.clear();
//       _commentsController.clear();
//     }

//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: Text(data == null ? 'Add Monitoring Data' : 'Edit Monitoring Data'),
//         content: SingleChildScrollView(
//           child: SizedBox(
//             width: MediaQuery.of(context).size.width * 0.8,
//             child: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: [
//                 _buildDialogTextField(
//                   controller: _locationController,
//                   label: 'Location',
//                   icon: Icons.location_on,
//                 ),
//                 const SizedBox(height: 16),
//                 Row(
//                   children: [
//                     Expanded(
//                       child: _buildDialogTextField(
//                         controller: _consentChimneyController,
//                         label: 'Consent Chimney',
//                         icon: Icons.account_tree,
//                       ),
//                     ),
//                     const SizedBox(width: 16),
//                     Expanded(
//                       child: _buildDialogTextField(
//                         controller: _consentApcController,
//                         label: 'Consent APC System',
//                         icon: Icons.settings,
//                       ),
//                     ),
//                   ],
//                 ),
//                 const SizedBox(height: 16),
//                 Row(
//                   children: [
//                     Expanded(
//                       child: _buildDialogTextField(
//                         controller: _providedChimneyController,
//                         label: 'Provided Chimney',
//                         icon: Icons.account_tree_outlined,
//                       ),
//                     ),
//                     const SizedBox(width: 16),
//                     Expanded(
//                       child: _buildDialogTextField(
//                         controller: _providedApcController,
//                         label: 'Provided APC System',
//                         icon: Icons.settings_outlined,
//                       ),
//                     ),
//                   ],
//                 ),
//                 const SizedBox(height: 16),
//                 DropdownButtonFormField<String>(
//                   value: _selectedParameter,
//                   decoration: InputDecoration(
//                     labelText: 'Parameter',
//                     prefixIcon: const Icon(Icons.science),
//                     border: OutlineInputBorder(
//                       borderRadius: BorderRadius.circular(12),
//                     ),
//                   ),
//                   items: _parameterOptions.map((parameter) {
//                     return DropdownMenuItem(
//                       value: parameter,
//                       child: Text(parameter),
//                     );
//                   }).toList(),
//                   onChanged: (value) {
//                     setState(() {
//                       _selectedParameter = value!;
//                     });
//                   },
//                 ),
//                 const SizedBox(height: 16),
//                 Row(
//                   children: [
//                     Expanded(
//                       child: _buildDialogTextField(
//                         controller: _standardController,
//                         label: 'Standard',
//                         icon: Icons.rule,
//                       ),
//                     ),
//                     const SizedBox(width: 16),
//                     Expanded(
//                       child: _buildDialogTextField(
//                         controller: _resultsController,
//                         label: 'Results',
//                         icon: Icons.assessment,
//                       ),
//                     ),
//                   ],
//                 ),
//                 const SizedBox(height: 16),
//                 _buildDialogTextField(
//                   controller: _commentsController,
//                   label: 'Comments',
//                   icon: Icons.comment,
//                   maxLines: 3,
//                 ),
//               ],
//             ),
//           ),
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context),
//             child: const Text('Cancel'),
//           ),
//           ElevatedButton(
//             onPressed: () {
//               if (_validateInputs()) {
//                 if (data == null) {
//                   _addMonitoringData();
//                 } else {
//                   _updateMonitoringData(data);
//                 }
//               }
//             },
//             child: Text(data == null ? 'Add' : 'Update'),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildDialogTextField({
//     required TextEditingController controller,
//     required String label,
//     required IconData icon,
//     TextInputType? keyboardType,
//     int maxLines = 1,
//   }) {
//     return TextField(
//       controller: controller,
//       decoration: InputDecoration(
//         labelText: label,
//         prefixIcon: Icon(icon),
//         border: OutlineInputBorder(
//           borderRadius: BorderRadius.circular(12),
//         ),
//       ),
//       keyboardType: keyboardType,
//       maxLines: maxLines,
//     );
//   }

//   bool _validateInputs() {
//     if (_locationController.text.isEmpty ||
//         _consentChimneyController.text.isEmpty ||
//         _consentApcController.text.isEmpty ||
//         _providedChimneyController.text.isEmpty ||
//         _providedApcController.text.isEmpty ||
//         _standardController.text.isEmpty ||
//         _resultsController.text.isEmpty) {
//       _showErrorSnackBar('Please fill all required fields');
//       return false;
//     }
//     return true;
//   }

//   void _showFilterDialog() {
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: const Text('Filter by Parameter'),
//         content: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: ['All', ..._parameterOptions].map((parameter) {
//             return ListTile(
//               title: Text(parameter),
//               leading: Radio<String>(
//                 value: parameter,
//                 groupValue: _filterParameter,
//                 onChanged: (value) {
//                   setState(() {
//                     _filterParameter = value!;
//                     _filterData(_searchController.text);
//                   });
//                   Navigator.pop(context);
//                 },
//               ),
//             );
//           }).toList(),
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context),
//             child: const Text('Cancel'),
//           ),
//         ],
//       ),
//     );
//   }

//   void _showDeleteDialog(AmbientAirMonitoringData data) {
//     showDialog(
//       context: context,
//       builder: (context) => AlertDialog(
//         title: const Text('Delete Monitoring Data'),
//         content: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             const Icon(
//               Icons.warning,
//               color: Colors.orange,
//               size: 48,
//             ),
//             const SizedBox(height: 16),
//             const Text('Are you sure you want to delete this data?'),
//             const SizedBox(height: 8),
//             Text(
//               'Location: ${data.location}',
//               style: const TextStyle(fontWeight: FontWeight.bold),
//             ),
//             Text(
//               'Parameter: ${data.parameter}',
//               style: const TextStyle(fontWeight: FontWeight.bold),
//             ),
//           ],
//         ),
//         actions: [
//           TextButton(
//             onPressed: () => Navigator.pop(context),
//             child: const Text('Cancel'),
//           ),
//           ElevatedButton(
//             onPressed: () {
//               Navigator.pop(context);
//               _deleteMonitoringData(data);
//             },
//             style: ElevatedButton.styleFrom(
//               backgroundColor: Colors.red,
//             ),
//             child: const Text('Delete'),
//           ),
//         ],
//       ),
//     );
//   }

//   Future<void> _addMonitoringData() async {
//     final newData = AmbientAirMonitoringData(
//       id: DateTime.now().millisecondsSinceEpoch.toString(),
//       location: _locationController.text.trim(),
//       consentChimney: _consentChimneyController.text.trim(),
//       consentApcSystem: _consentApcController.text.trim(),
//       providedChimney: _providedChimneyController.text.trim(),
//       providedApcSystem: _providedApcController.text.trim(),
//       parameter: _selectedParameter,
//       standard: _standardController.text.trim(),
//       results: _resultsController.text.trim(),
//       comments: _commentsController.text.trim(),
//       timestamp: DateTime.now(),
//     );

//     try {
//       setState(() => _isLoading = true);
//       final response = await http.post(
//         Uri.parse('$_baseUrl/ambient-monitoring-enhanced'),
//         headers: {'Content-Type': 'application/json'},
//         body: json.encode(newData.toJson()),
//       );

//       if (response.statusCode == 201) {
//         setState(() {
//           _monitoringData.add(newData);
//           _filterData(_searchController.text);
//         });
//         Navigator.pop(context);
//         _showSuccessSnackBar('Monitoring data added successfully');
//       } else {
//         _showErrorSnackBar('Failed to add monitoring data');
//       }
//     } catch (e) {
//       _showErrorSnackBar('Error connecting to server');
//     } finally {
//       setState(() => _isLoading = false);
//     }
//   }

//   Future<void> _updateMonitoringData(AmbientAirMonitoringData oldData) async {
//     final updatedData = AmbientAirMonitoringData(
//       id: oldData.id,
//       location: _locationController.text.trim(),
//       consentChimney: _consentChimneyController.text.trim(),
//       consentApcSystem: _consentApcController.text.trim(),
//       providedChimney: _providedChimneyController.text.trim(),
//       providedApcSystem: _providedApcController.text.trim(),
//       parameter: _selectedParameter,
//       standard: _standardController.text.trim(),
//       results: _resultsController.text.trim(),
//       comments: _commentsController.text.trim(),
//       timestamp: DateTime.now(),
//     );

//     try {
//       setState(() => _isLoading = true);
//       final response = await http.put(
//         Uri.parse('$_baseUrl/ambient-monitoring-enhanced/${oldData.id}'),
//         headers: {'Content-Type': 'application/json'},
//         body: json.encode(updatedData.toJson()),
//       );

//       if (response.statusCode == 200) {
//         setState(() {
//           final index = _monitoringData.indexWhere((data) => data.id == oldData.id);
//           if (index != -1) {
//             _monitoringData[index] = updatedData;
//             _filterData(_searchController.text);
//           }
//         });
//         Navigator.pop(context);
//         _showSuccessSnackBar('Monitoring data updated successfully');
//       } else {
//         _showErrorSnackBar('Failed to update monitoring data');
//       }
//     } catch (e) {
//       _showErrorSnackBar('Error connecting to server');
//     } finally {
//       setState(() => _isLoading = false);
//     }
//   }

//   Future<void> _deleteMonitoringData(AmbientAirMonitoringData data) async {
//     try {
//       setState(() => _isLoading = true);
//       final response = await http.delete(
//         Uri.parse('$_baseUrl/ambient-monitoring-enhanced/${data.id}'),
//       );

//       if (response.statusCode == 200) {
//         setState(() {
//           _monitoringData.removeWhere((item) => item.id == data.id);
//           _filterData(_searchController.text);
//         });
//         _showSuccessSnackBar('Monitoring data deleted successfully');
//       } else {
//         _showErrorSnackBar('Failed to delete monitoring data');
//       }
//     } catch (e) {
//       _showErrorSnackBar('Error connecting to server');
//     } finally {
//       setState(() => _isLoading = false);
//     }
//   }
// }