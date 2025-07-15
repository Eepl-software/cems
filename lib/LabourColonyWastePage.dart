import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class LabourColonyPage extends StatefulWidget {
  const LabourColonyPage({Key? key}) : super(key: key);

  @override
  _LabourColonyPageState createState() => _LabourColonyPageState();
}

class _LabourColonyPageState extends State<LabourColonyPage> {
  List<Map<String, dynamic>> _data = [];
  bool _isLoading = false;
  DateTime? _selectedDate;
  final String baseUrl = 'http://54.146.215.18:3000/labour-colony-waste';

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    try {
      String url = baseUrl;
      if (_selectedDate != null) {
        url += '?date=${DateFormat('yyyy-MM-dd').format(_selectedDate!)}';
      }

      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final Map<String, dynamic> responseData = jsonDecode(response.body);
        setState(() {
          _data = List<Map<String, dynamic>>.from(responseData['data']);
        });
      } else {
        throw Exception('Failed to load data: ${response.body}');
      }
    } catch (e) {
      _showError('Error loading data: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addRecord(Map<String, dynamic> data) async {
    try {
      final response = await http.post(
        Uri.parse(baseUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );

      final responseData = jsonDecode(response.body);

      if (response.statusCode == 201) {
        await _fetchData();
        _showSuccess('Record added successfully');
      } else {
        throw Exception(responseData['error'] ?? 'Failed to add record');
      }
    } catch (e) {
      _showError('Error adding record: $e');
    }
  }

  Future<void> _updateRecord(int id, Map<String, dynamic> data) async {
    try {
      final response = await http.put(
        Uri.http('54.146.215.18:3000', '/$id'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(data),
      );

      if (response.statusCode == 200) {
        await _fetchData();
        _showSuccess('Record updated successfully');
      } else {
        final responseData = jsonDecode(response.body);
        throw Exception(responseData['error'] ?? 'Failed to update record');
      }
    } catch (e) {
      _showError('Error updating record: $e');
    }
  }

  Future<void> _deleteRecord(int id) async {
    try {
      final response = await http.delete(Uri.http('54.146.215.18:3000', '/$id'));

      if (response.statusCode == 200) {
        await _fetchData();
        _showSuccess('Record deleted successfully');
      } else {
        final responseData = jsonDecode(response.body);
        throw Exception(responseData['error'] ?? 'Failed to delete record');
      }
    } catch (e) {
      _showError('Error deleting record: $e');
    }
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      ),
    );
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showAddDialog() {
    showDialog(
      context: context,
      builder: (context) => LabourColonyFormDialog(
        onSubmit: _addRecord,
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Labour Colony Management',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.indigo,
        actions: [
          IconButton(
            icon: const Icon(Icons.calendar_today),
            onPressed: () => _selectDate(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_selectedDate != null)
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Chip(
                      label: Text(
                        'Date: ${DateFormat('yyyy-MM-dd').format(_selectedDate!)}',
                      ),
                      onDeleted: () {
                        setState(() => _selectedDate = null);
                        _fetchData();
                      },
                    ),
                  ),
                Expanded(
                  child: Card(
                    margin: const EdgeInsets.all(16.0),
                    elevation: 4,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(16),
                          color: Colors.indigo.shade50,
                          child: const Row(
                            children: [
                              Text(
                                'Labour Colony Records',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: SingleChildScrollView(
                              child: DataTable(
                                headingRowColor: MaterialStateProperty.all(
                                  Colors.indigo.shade50,
                                ),
                                columnSpacing: 20,
                                headingTextStyle: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo,
                                ),
                                dataRowColor: MaterialStateProperty.resolveWith(
                                  (states) => states.contains(MaterialState.selected)
                                      ? Colors.indigo.shade50
                                      : null,
                                ),
                                border: TableBorder.all(
                                  color: Colors.grey.shade300,
                                  width: 1,
                                ),
                                columns: const [
                                  DataColumn(label: Text('Date')),
                                  DataColumn(label: Text('Source')),
                                  DataColumn(label: Text('Consumption (KLD)')),
                                  DataColumn(label: Text('Discharge')),
                                  DataColumn(label: Text('Discharged To')),
                                  DataColumn(label: Text('Mode')),
                                  DataColumn(label: Text('Actions')),
                                ],
                                rows: _data.map((item) => _buildDataRow(item)).toList(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddDialog,
        backgroundColor: Colors.indigo,
        icon: const Icon(Icons.add),
        label: const Text('Add Record'),
      ),
    );
  }

  DataRow _buildDataRow(Map<String, dynamic> item) {
    return DataRow(
      cells: [
        DataCell(Text(DateFormat('yyyy-MM-dd').format(DateTime.parse(item['date'])))),
        DataCell(Text(item['source'])),
        DataCell(Text(item['consumption'].toString())),
        DataCell(Text(item['discharge'])),
        DataCell(Text(item['discharged_to'])),
        DataCell(Text(item['mode'])),
        DataCell(Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.edit, color: Colors.indigo),
              onPressed: () => _showEditDialog(item),
            ),
            IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _showDeleteDialog(item),
            ),
          ],
        )),
      ],
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2025),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Colors.indigo,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      await _fetchData();
    }
  }

  // void _showAddDialog() {
  //   showDialog(
  //     context: context,
  //     builder: (context) => LabourColonyFormDialog(
  //       onSubmit: _addRecord,
  //     ),
  //   );
  // }

  void _showEditDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (context) => LabourColonyFormDialog(
        initialData: item,
        onSubmit: (data) => _updateRecord(item['id'], data),
      ),
    );
  }

  void _showDeleteDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Record'),
        content: const Text('Are you sure you want to delete this record?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _deleteRecord(item['id']);
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

  // Future<void> _addRecord(Map<String, dynamic> data) async {
  //   try {
  //     final response = await http.post(
  //       Uri.parse('http://54.146.215.18:3000/labour-colony-waste'),
  //       headers: {'Content-Type': 'application/json'},
  //       body: jsonEncode(data),
  //     );
  //     if (response.statusCode == 201) {
  //       _fetchData();
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         const SnackBar(
  //           content: Text('Record added successfully'),
  //           backgroundColor: Colors.green,
  //         ),
  //       );
  //     } else {
  //       throw Exception('Failed to add record');
  //     }
  //   } catch (e) {
  //     _showError('Error adding record: $e');
  //   }
  // }

  
}

class LabourColonyFormDialog extends StatefulWidget {
  final Map<String, dynamic>? initialData;
  final Function(Map<String, dynamic>) onSubmit;

  const LabourColonyFormDialog({
    Key? key,
    this.initialData,
    required this.onSubmit,
  }) : super(key: key);

  @override
  _LabourColonyFormDialogState createState() => _LabourColonyFormDialogState();
}

class _LabourColonyFormDialogState extends State<LabourColonyFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late DateTime _selectedDate;
  final _sourceController = TextEditingController();
  final _consumptionController = TextEditingController();
  final _dischargeController = TextEditingController();
  final _dischargedToController = TextEditingController();
  String _selectedMode = 'Pipeline';

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialData != null 
        ? DateTime.parse(widget.initialData!['date'])
        : DateTime.now();

    if (widget.initialData != null) {
      _sourceController.text = widget.initialData!['source'];
      _consumptionController.text = widget.initialData!['consumption'].toString();
      _dischargeController.text = widget.initialData!['discharge'];
      _dischargedToController.text = widget.initialData!['discharged_to'];
      _selectedMode = widget.initialData!['mode'];
    }
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      final data = {
        'date': DateFormat('yyyy-MM-dd').format(_selectedDate),
        'source': _sourceController.text.trim(),
        'consumption': double.parse(_consumptionController.text.trim()),
        'discharge': _dischargeController.text.trim(),
        'discharged_to': _dischargedToController.text.trim(),
        'mode': _selectedMode,
      };

      widget.onSubmit(data);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.initialData == null ? 'Add Record' : 'Edit Record'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: Text(
                  'Date: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}',
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.calendar_today),
                  onPressed: () => _selectDate(context),
                ),
              ),
              _buildTextField(
                controller: _sourceController,
                label: 'Source',
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              _buildTextField(
                controller: _consumptionController,
                label: 'Consumption (KLD)',
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v!.isEmpty) return 'Required';
                  if (double.tryParse(v) == null) return 'Must be a number';
                  if (double.parse(v) <= 0) return 'Must be greater than 0';
                  return null;
                },
              ),
              _buildTextField(
                controller: _dischargeController,
                label: 'Discharge',
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              _buildTextField(
                controller: _dischargedToController,
                label: 'Discharged To',
                validator: (v) => v!.isEmpty ? 'Required' : null,
              ),
              DropdownButtonFormField<String>(
                value: _selectedMode,
                decoration: const InputDecoration(labelText: 'Mode'),
                items: ['Pipeline', 'Tanker', 'Other']
                    .map((mode) => DropdownMenuItem(
                          value: mode,
                          child: Text(mode),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _selectedMode = value!),
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
          onPressed: _submit,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.indigo,
          ),
          child: const Text('Submit'),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        keyboardType: keyboardType,
        validator: validator,
      ),
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2025),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
    }
  }

  @override
  void dispose() {
    _sourceController.dispose();
    _consumptionController.dispose();
    _dischargeController.dispose();
    _dischargedToController.dispose();
    super.dispose();
  }
}