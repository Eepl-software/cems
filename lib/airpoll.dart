

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

// Constants
const double kSpacing = 16.0;
const EdgeInsets kPadding = EdgeInsets.all(kSpacing);
const String baseUrl = 'http://54.146.215.18:3000';

class CDWasteDetailsPage extends StatefulWidget {
  const CDWasteDetailsPage({Key? key}) : super(key: key);

  @override
  _CDWasteDetailsPageState createState() => _CDWasteDetailsPageState();
}

class _CDWasteDetailsPageState extends State<CDWasteDetailsPage> {
  // Controllers
  final TextEditingController _projectAreaController = TextEditingController();
  final TextEditingController _quantityController = TextEditingController();
  final TextEditingController _storageController = TextEditingController();
  final TextEditingController _disposalController = TextEditingController();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  // State variables
  DateTime? _startDate;
  DateTime? _endDate;
  DateTime? _selectedDate;
  bool _isLoading = false;
  bool _showWasteHistory = false;
  bool _showDailyWaste = false;
  List<dynamic> _wasteData = [];
  List<dynamic> _dailyWasteData = [];
  double _totalWaste = 0;

  @override
  void initState() {
    super.initState();
    _fetchInitialData();
  }

  @override
  void dispose() {
    _projectAreaController.dispose();
    _quantityController.dispose();
    _storageController.dispose();
    _disposalController.dispose();
    super.dispose();
  }

  // API Calls
  Future<void> _fetchInitialData() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.http('54.146.215.18:3000', '/cd-waste'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _wasteData = data['data'] ?? [];
        });
      } else {
        _showError('Failed to fetch initial data');
      }
    } catch (e) {
      _showError('Error: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _fetchDailyWasteData() async {
    setState(() => _isLoading = true);
    try {
      final response = await http.get(Uri.http('54.146.215.18:3000', '/daily-waste'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _dailyWasteData = data['data'] ?? [];
          _totalWaste = double.parse(data['total_waste'].toString());
        });
      }
    } catch (e) {
      _showError('Error: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _calculateAndStoreWaste() async {
    if (!_formKey.currentState!.validate()) return;
    if (_startDate == null || _endDate == null) {
      _showError('Please select both start and end dates');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final projectArea = double.tryParse(_projectAreaController.text) ?? 0.0;

      final response = await http.post(
        Uri.http('54.146.215.18:3000', '/waste-calculations'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'project_area': projectArea,
          'start_date': _startDate?.toIso8601String(),
          'end_date': _endDate?.toIso8601String(),
        }),
      );

      if (response.statusCode == 201) {
        final data = json.decode(response.body);
        setState(() {
          _wasteData.add(data);
        });
        _showSuccess('Waste calculation stored successfully');
        _resetForm();
      } else {
        _showError('Failed to calculate waste');
      }
    } catch (e) {
      _showError('Error: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _addDailyWaste() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDate == null) {
      _showError('Please select a date');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final response = await http.post(
        Uri.http('54.146.215.18:3000', '/daily-waste'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'date': _selectedDate?.toIso8601String(),
          'quantity_kg': double.parse(_quantityController.text),
          'mode_of_storage': _storageController.text,
          'mode_of_disposal': _disposalController.text,
        }),
      );

      if (response.statusCode == 201) {
        _showSuccess('Daily waste data added successfully');
        _resetDailyWasteForm();
        _fetchDailyWasteData();
      } else {
        _showError('Failed to add daily waste data');
      }
    } catch (e) {
      _showError('Error: ${e.toString()}');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // UI Helper Methods
  Future<void> _selectDate(bool isStartDate) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2101),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: Colors.teal,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStartDate) {
          if (_endDate != null && picked.isAfter(_endDate!)) {
            _showError('Start date cannot be after end date');
            return;
          }
          _startDate = picked;
        } else {
          if (_startDate != null && picked.isBefore(_startDate!)) {
            _showError('End date cannot be before start date');
            return;
          }
          _endDate = picked;
        }
      });
    }
  }

  void _resetForm() {
    _projectAreaController.clear();
    setState(() {
      _startDate = null;
      _endDate = null;
    });
  }

  void _resetDailyWasteForm() {
    _quantityController.clear();
    _storageController.clear();
    _disposalController.clear();
    setState(() => _selectedDate = null);
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red[700],
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        duration: Duration(seconds: 3),
      ),
    );
  }

  String _formatNumber(dynamic value) {
    if (value == null) return 'N/A';

    if (value is num) {
      return value.toStringAsFixed(2);
    }

    if (value is String) {
      try {
        final number = double.parse(value);
        return number.toStringAsFixed(2);
      } catch (e) {
        return value;
      }
    }

    return 'N/A';
  }

  // Widget Building Methods
  Widget _buildLoadingIndicator() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Colors.teal),
            strokeWidth: 3,
          ),
          SizedBox(height: kSpacing),
          Text(
            'Loading data...',
            style: TextStyle(
              color: Colors.teal[700],
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return SingleChildScrollView(
      padding: kPadding,
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildWasteComponentsCard(),
            SizedBox(height: kSpacing),
            _buildCalculationSection(),
            SizedBox(height: kSpacing),
            _buildActionButtons(),
            SizedBox(height: kSpacing),
            if (_showWasteHistory) _buildWasteDataTable(),
            if (_showDailyWaste) ...[
              _buildDailyWasteForm(),
              SizedBox(height: kSpacing),
              _buildDailyWasteTable(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildWasteComponentsCard() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: kPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Components of C&D Waste',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.teal[700],
              ),
            ),
            Divider(color: Colors.teal[100]),
            _buildWasteComponent('Concrete Waste'),
            _buildWasteComponent('Wood Waste'),
            _buildWasteComponent('Metal Scrap'),
            _buildWasteComponent('Ceramic and Tile Waste'),
            _buildWasteComponent('Packaging Materials'),
          ],
        ),
      ),
    );
  }

  Widget _buildWasteComponent(String text) {
    return ListTile(
      leading: Icon(Icons.circle, size: 8, color: Colors.teal),
      title: Text(text),
      dense: true,
    );
  }

  Widget _buildCalculationSection() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: kPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Waste Generation Estimation',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.teal[700],
              ),
            ),
            SizedBox(height: kSpacing),
            TextFormField(
              controller: _projectAreaController,
              decoration: InputDecoration(
                labelText: 'Project Area (m²)',
                hintText: 'Enter project area in square meters',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.teal.shade200),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.teal.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.teal, width: 2),
                ),
                filled: true,
                fillColor: Colors.grey[50],
                prefixIcon: Icon(Icons.area_chart, color: Colors.teal),
                contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Please enter project area';
                }
                final number = double.tryParse(value);
                if (number == null || number <= 0) {
                  return 'Please enter a valid positive number';
                }
                return null;
              },
            ),
            SizedBox(height: kSpacing),
            Row(
              children: [
                Expanded(
                  child: _buildDateField(
                    'Start Date',
                    _startDate,
                    () => _selectDate(true),
                  ),
                ),
                SizedBox(width: kSpacing),
                Expanded(
                  child: _buildDateField(
                    'End Date',
                    _endDate,
                    () => _selectDate(false),
                  ),
                ),
              ],
            ),
            SizedBox(height: kSpacing),
            ElevatedButton(
              onPressed: _calculateAndStoreWaste,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calculate),
                  SizedBox(width: 8),
                  Text('Calculate Waste'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDateField(String label, DateTime? date, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          filled: true,
          fillColor: Colors.grey[50],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              date != null
                  ? DateFormat('yyyy-MM-dd').format(date)
                  : 'Select Date',
              style: TextStyle(fontSize: 16),
            ),
            Icon(Icons.calendar_today, color: Colors.teal),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        ElevatedButton.icon(
          icon: Icon(Icons.history),
          label: Text('Waste Data History'),
          onPressed: () {
            setState(() {
              _showWasteHistory = !_showWasteHistory;
              _showDailyWaste = false;
            });
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
        ElevatedButton.icon(
          icon: Icon(Icons.add_chart),
          label: Text('C&D Waste Generated'),
          onPressed: () {
            setState(() {
              _showDailyWaste = !_showDailyWaste;
              _showWasteHistory = false;
            });
            if (_showDailyWaste) {
              _fetchDailyWasteData();
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildWasteDataTable() {
    if (_wasteData.isEmpty) {
      return Card(
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: kPadding,
          child: Center(
            child: Text(
              'No waste data available',
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
          ),
        ),
      );
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: kPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Waste Data History',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.teal[700],
              ),
            ),
            SizedBox(height: kSpacing),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: MaterialStateProperty.all(Colors.teal.shade50),
                columnSpacing: 24,
                horizontalMargin: 12,
                columns: [
                  DataColumn(
                    label: Text('Date',
                      style: TextStyle(fontWeight: FontWeight.bold)
                    ),
                  ),
                  DataColumn(
                    label: Text('Project Area (m²)',
                      style: TextStyle(fontWeight: FontWeight.bold)
                    ),
                    numeric: true,
                  ),
                  DataColumn(
                    label: Text('Waste Amount (kg)',
                      style: TextStyle(fontWeight: FontWeight.bold)
                    ),
                    numeric: true,
                  ),
                ],
                rows: _wasteData.map<DataRow>((waste) {
                  return DataRow(
                    cells: [
                      DataCell(Text(DateFormat('yyyy-MM-dd')
                          .format(DateTime.parse(waste['date'])))),
                      DataCell(Text(_formatNumber(waste['project_area']))),
                      DataCell(Text(_formatNumber(waste['waste_amount']))),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyWasteForm() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: kPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daily C&D Waste Entry',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.teal[700],
              ),
            ),
            SizedBox(height: kSpacing),
            _buildDateField('Date', _selectedDate,
              () async {
                final date = await showDatePicker(
                  context: context,
                  initialDate: DateTime.now(),
                  firstDate: DateTime(2000),
                  lastDate: DateTime.now(),
                );
                if (date != null) {
                  setState(() => _selectedDate = date);
                }
              }
            ),
            SizedBox(height: kSpacing),
            TextFormField(
              controller: _quantityController,
              decoration: InputDecoration(
                labelText: 'Quantity (kg)',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
            ),
            SizedBox(height: kSpacing),
            TextFormField(
              controller: _storageController,
              decoration: InputDecoration(
                labelText: 'Mode of Storage',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
            ),
            SizedBox(height: kSpacing),
            TextFormField(
              controller: _disposalController,
              decoration: InputDecoration(
                labelText: 'Mode of Disposal',
                border: OutlineInputBorder(),
              ),
              validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
            ),
            SizedBox(height: kSpacing),
            ElevatedButton(
              onPressed: _addDailyWaste,
              child: Text('Submit Daily Waste Data'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal,
                padding: EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyWasteTable() {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: kPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Daily Waste Data',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.teal[700],
              ),
            ),
            SizedBox(height: kSpacing),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columns: [
                  DataColumn(label: Text('No')),
                  DataColumn(label: Text('Date')),
                  DataColumn(label: Text('Quantity (kg)')),
                  DataColumn(label: Text('Storage')),
                  DataColumn(label: Text('Disposal')),
                ],
                rows: _dailyWasteData.asMap().entries.map((entry) {
                  final index = entry.key;
                  final waste = entry.value;
                  return DataRow(cells: [
                    DataCell(Text('${index + 1}')),
                    DataCell(Text(DateFormat('yyyy-MM-dd')
                        .format(DateTime.parse(waste['date'])))),
                    DataCell(Text(waste['quantity_kg'].toString())),
                    DataCell(Text(waste['mode_of_storage'])),
                    DataCell(Text(waste['mode_of_disposal'])),
                  ]);
                }).toList(),
              ),
            ),
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Total Waste Generated: ${_totalWaste.toStringAsFixed(2)} kg',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal[700],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: ThemeData(
        primarySwatch: Colors.teal,
        scaffoldBackgroundColor: Colors.grey[50],
      ),
      child: Scaffold(
        appBar: AppBar(
          title: const Text('C&D Waste Details'),
          centerTitle: true,
          elevation: 0,
        ),
        body: _isLoading
            ? _buildLoadingIndicator()
            : _buildContent(),
      ),
    );
  }
}
