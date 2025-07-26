import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'login/auth_service.dart';
import 'services/image_classifier.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:excel/excel.dart' as excel;
import 'services/image_service.dart';

class TankerDataScreen extends StatefulWidget {
  final AuthService authService;
  final VoidCallback onAuthenticationRequired;

  const TankerDataScreen({
    Key? key,
    required this.authService,
    required this.onAuthenticationRequired,
  }) : super(key: key);

  @override
  TankerDataScreenState createState() => TankerDataScreenState();
}

class TankerDataScreenState extends State<TankerDataScreen> {
  final _imageClassifier = ImageClassifier();
  final _imageService = ImageService();
  bool _isInitialized = false;
  bool _isLoading = true;
  List<Map<String, dynamic>> _data = [];
  DateTime? _selectedDate;
  String? _error;
  File? _selectedImage;
  
  // Sorting variables
  int _sortColumnIndex = 4; // Default sort by date column
  bool _sortAscending = false; // Newest first

  // Predefined tanker capacities based on registration numbers
  final Map<String, double> _tankerCapacities = {
    'KA01U8743': 12000.0,
    'KA01U1234': 24000.0,
    'KA01U2221': 26000.0,
    'KA01U2435': 28000.0,
    'KA01U2122': 30000.0,
    'KA01U8999': 32000.0,
    'KA01U9900': 34000.0,
    'KA01U0101': 36000.0,
    'KA01U1010': 38000.0,
    'KA01U1424': 40000.0,
    'KA01U9210': 42000.0,
    'KA01U1111': 44000.0,
    'KA01U2222': 46000.0,
    'KA01U3333': 15000.0,
    'KA01U4657': 18000.0,
    'KA01U9901': 20000.0,
    'KA01U0099': 22000.0,
  };

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  Future<void> _initializeScreen() async {
    if (!mounted) return;

    setState(() => _isLoading = true);

    try {
    await _requestPermissions();
      if (mounted) {
        setState(() {
          _isInitialized = true;
          _isLoading = false;
        });
    await _fetchTankerData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error initializing: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _requestPermissions() async {
    Map<Permission, PermissionStatus> statuses = await [
      Permission.camera,
      Permission.location,
      Permission.storage,
    ].request();

    if (statuses[Permission.location]!.isPermanentlyDenied) {
      _showPermissionError(
        'Location permission is permanently denied. Please enable it in app settings.',
        openSettings: true
      );
    } else if (statuses[Permission.location]!.isDenied) {
      _showPermissionError('Location permission is required for tracking tankers');
    }

    if (statuses[Permission.camera]!.isPermanentlyDenied) {
      _showPermissionError(
        'Camera permission is permanently denied. Please enable it in app settings.',
        openSettings: true
      );
    } else if (statuses[Permission.camera]!.isDenied) {
      _showPermissionError('Camera permission is required for taking photos');
    }
  }

  void _showPermissionError(String message, {bool openSettings = false}) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
        action: openSettings ? SnackBarAction(
          label: 'Settings',
          textColor: Colors.white,
          onPressed: () => openAppSettings(),
        ) : null,
      ),
    );
  }

  Future<void> _fetchTankerData() async {
    if (!mounted) return;

    setState(() => _isLoading = true);
    try {
      String url = 'http://54.146.215.18:3000/tanker';
      if (_selectedDate != null) {
        url += '?date=${DateFormat('yyyy-MM-dd').format(_selectedDate!)}';
      }

      final response = await http.get(
        Uri.parse(url),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          if (data is Map<String, dynamic> && data.containsKey('data')) {
            _data = List<Map<String, dynamic>>.from(data['data'] ?? []);
          } else if (data is List) {
            // Handle direct array response
            _data = List<Map<String, dynamic>>.from(data);
          } else {
            _data = [];
          }
          // Sort data by date (newest first) by default
          _sortData(_sortColumnIndex, _sortAscending);
        });
      } else {
        throw Exception('Server returned ${response.statusCode}');
      }
    } catch (e) {
      _showError('Error loading data: ${e.toString()}');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  double _getCapacityAsDouble(Map<String, dynamic> item) {
    try {
      final capacity = item['capacity'];
      if (capacity == null) return 0.0;
      if (capacity is double) return capacity;
      if (capacity is int) return capacity.toDouble();
      if (capacity is String) return double.tryParse(capacity) ?? 0.0;
      return 0.0;
    } catch (e) {
      return 0.0;
    }
  }

  String _formatDateTime(dynamic dateTime) {
    try {
      if (dateTime == null) return 'N/A';
      if (dateTime is String) {
        final parsed = DateTime.parse(dateTime);
        return DateFormat('dd MMM yyyy HH:mm').format(parsed);
      }
      if (dateTime is DateTime) {
        return DateFormat('dd MMM yyyy HH:mm').format(dateTime);
      }
      return dateTime.toString();
    } catch (e) {
      return 'N/A';
    }
  }
  
  String _formatDate(dynamic date) {
    try {
      if (date == null) return 'N/A';
      if (date is String) {
        final parsed = DateTime.parse(date);
        return DateFormat('dd MMM yyyy').format(parsed);
      }
      if (date is DateTime) {
        return DateFormat('dd MMM yyyy').format(date);
      }
      return date.toString();
    } catch (e) {
      return 'N/A';
    }
  }

  void _sortData(int columnIndex, bool ascending) {
    setState(() {
      _sortColumnIndex = columnIndex;
      _sortAscending = ascending;
      
      _data.sort((a, b) {
        dynamic aValue;
        dynamic bValue;
        
        switch (columnIndex) {
          case 0: // Vehicle No
            aValue = a['plateNumber'] ?? a['vehicle_no'] ?? a['plate_number'] ?? '';
            bValue = b['plateNumber'] ?? b['vehicle_no'] ?? b['plate_number'] ?? '';
            break;
          case 1: // Capacity
            aValue = _getCapacityAsDouble(a);
            bValue = _getCapacityAsDouble(b);
            break;
          case 2: // Driver
            aValue = a['driverName'] ?? a['driver_name'] ?? '';
            bValue = b['driverName'] ?? b['driver_name'] ?? '';
            break;
          case 3: // Vendor
            aValue = a['vendor'] ?? '';
            bValue = b['vendor'] ?? '';
            break;
          case 4: // Date
            try {
              aValue = a['date'] != null ? DateTime.parse(a['date']) : DateTime(1970);
              bValue = b['date'] != null ? DateTime.parse(b['date']) : DateTime(1970);
            } catch (e) {
              aValue = DateTime(1970);
              bValue = DateTime(1970);
            }
            break;
          default:
            return 0;
        }
        
        if (aValue == null && bValue == null) return 0;
        if (aValue == null) return ascending ? -1 : 1;
        if (bValue == null) return ascending ? 1 : -1;
        
        int result = Comparable.compare(aValue, bValue);
        return ascending ? result : -result;
      });
    });
  }

  void _showPhoto(String? url) {
    if (url == null || url.isEmpty) {
      _showError('No photo URL available');
      return;
    }
    showDialog(
      context: context,
      builder: (context) => Dialog(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: const Text('Vehicle Photo'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _deletePhoto(url),
                  ),
              ],
            ),
            Image.network(
              url,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Center(
                  child: CircularProgressIndicator(
                    value: progress.expectedTotalBytes != null
                        ? progress.cumulativeBytesLoaded /
                            progress.expectedTotalBytes!
                        : null,
                  ),
                );
              },
              errorBuilder: (context, error, stackTrace) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text(
                        'Error loading image',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deletePhoto(String? url) async {
    if (url == null || url.isEmpty) {
      _showError('No photo URL to delete');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Photo'),
        content: const Text('Are you sure you want to delete this photo?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    

    if (confirmed != true) return;

    try {
      final response = await http.delete(
        Uri.parse(url),
      );

      if (response.statusCode == 200) {
        Navigator.of(context).pop(); // Close photo dialog
        _fetchTankerData(); // Refresh data
      } else {
        throw Exception('Failed to delete photo');
      }
    } catch (e) {
      _showError('Error deleting photo: ${e.toString()}');
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() => _selectedDate = picked);
      await _fetchTankerData();
    }
  }

  Widget _buildDataTable() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Card(
        elevation: 4,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          children: [
            // Header with summary stats
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _buildStatCard(
                      'Total Tankers',
                      _data.length.toString(),
                      Icons.local_shipping,
                      Colors.blue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      'Total Capacity',
                      '${_data.fold<double>(0, (sum, item) => sum + _getCapacityAsDouble(item)).toStringAsFixed(0)}L',
                      Icons.water_drop,
                      Colors.cyan,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildStatCard(
                      'With Photos',
                      _data.where((item) => item['photoUrl'] != null || item['photo_url'] != null).length.toString(),
                      Icons.photo_camera,
                      Colors.green,
                    ),
                  ),
                ],
              ),
            ),
            // Data table
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: MaterialStateProperty.all(Colors.grey[100]),
                sortColumnIndex: _sortColumnIndex,
                sortAscending: _sortAscending,
                columns: [
                  DataColumn(
                    label: const Text('Vehicle No', style: TextStyle(fontWeight: FontWeight.bold)),
                    onSort: (columnIndex, ascending) => _sortData(columnIndex, ascending),
                  ),
                  DataColumn(
                    label: const Text('Capacity (L)', style: TextStyle(fontWeight: FontWeight.bold)),
                    numeric: true,
                    onSort: (columnIndex, ascending) => _sortData(columnIndex, ascending),
                  ),
                  DataColumn(
                    label: const Text('Driver', style: TextStyle(fontWeight: FontWeight.bold)),
                    onSort: (columnIndex, ascending) => _sortData(columnIndex, ascending),
                  ),
                  DataColumn(
                    label: const Text('Vendor', style: TextStyle(fontWeight: FontWeight.bold)),
                    onSort: (columnIndex, ascending) => _sortData(columnIndex, ascending),
                  ),
                  DataColumn(
                    label: const Text('Date', style: TextStyle(fontWeight: FontWeight.bold)),
                    onSort: (columnIndex, ascending) => _sortData(columnIndex, ascending),
                  ),
                  const DataColumn(label: Text('Photo', style: TextStyle(fontWeight: FontWeight.bold))),
                  const DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: _data.map((item) {
                  return DataRow(
                    cells: [
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.blue[100],
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item['plateNumber'] ?? item['vehicle_no'] ?? item['plate_number'] ?? '',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${item['capacity']?.toString() ?? ''}L',
                          style: const TextStyle(color: Colors.cyan),
                        ),
                      ),
                      DataCell(
                        Text(
                          item['driverName'] ?? item['driver_name'] ?? 'N/A',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ),
                      DataCell(
                        Text(
                          item['vendor'] ?? 'N/A',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ),
                      DataCell(
                        Text(
                          _formatDate(item['date']),
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ),
                      DataCell(
                        (item['photoUrl'] != null || item['photo_url'] != null)
                            ? IconButton(
                                icon: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: Colors.green[100],
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Icon(Icons.photo, color: Colors.green),
                                ),
                                onPressed: () => _showPhoto(item['photoUrl'] ?? item['photo_url']),
                                tooltip: 'View Photo',
                              )
                            : Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.orange[100],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: const Text(
                                  'No photo',
                                  style: TextStyle(color: Colors.orange, fontSize: 12),
                                ),
                              ),
                      ),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.info, color: Colors.blue),
                              onPressed: () => _showTankerDetails(item),
                              tooltip: 'View Details',
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit, color: Colors.orange),
                              onPressed: () => _editTanker(item),
                              tooltip: 'Edit',
                            ),
                          ],
                        ),
                      ),
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

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: const TextStyle(
              fontSize: 10,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  void _showTankerDetails(Map<String, dynamic> tanker) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Tanker Details: ${tanker['plateNumber'] ?? tanker['vehicle_no'] ?? tanker['plate_number']}'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDetailRow('Vehicle Number', tanker['plateNumber'] ?? tanker['vehicle_no'] ?? tanker['plate_number'] ?? 'N/A'),
              _buildDetailRow('Capacity', '${tanker['capacity'] ?? 'N/A'}L'),
              _buildDetailRow('Driver Name', tanker['driverName'] ?? tanker['driver_name'] ?? 'N/A'),
              _buildDetailRow('Driver Contact', tanker['driverContact'] ?? tanker['driver_contact'] ?? 'N/A'),
              _buildDetailRow('Vendor', tanker['vendor'] ?? 'N/A'),
              _buildDetailRow('Date', _formatDate(tanker['date'])),
              if (tanker['latitude'] != null && tanker['longitude'] != null)
                _buildDetailRow('Location', '${tanker['latitude']}, ${tanker['longitude']}'),
              if (tanker['lastUpdated'] != null || tanker['last_updated'] != null)
                _buildDetailRow('Last Updated', _formatDateTime(tanker['lastUpdated'] ?? tanker['last_updated'])),
            ],
          ),
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

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: Text(value),
          ),
        ],
      ),
    );
  }

  void _editTanker(Map<String, dynamic> tanker) {
    showDialog(
      context: context,
      builder: (context) => EditTankerDialog(data: tanker),
    ).then((result) {
      if (result != null) {
        // Handle the edit result if needed
        _fetchTankerData();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (!_isInitialized) {
      return const Scaffold(
        body: Center(
          child: Text('Initializing...'),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Tanker Tracking',
            style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: Colors.blue[800],
        actions: [
            IconButton(
              icon: const Icon(Icons.calendar_today),
              onPressed: () => _selectDate(context),
              tooltip: 'Select Date',
            ),
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _fetchTankerData,
              tooltip: 'Refresh Data',
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.blue[50]!, Colors.white],
          ),
        ),
        child: _isLoading
            ? const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Loading data...'),
                  ],
                ),
              )
            : RefreshIndicator(
                onRefresh: _fetchTankerData,
                child: _data.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.no_drinks,
                                size: 64, color: Colors.grey[400]),
                            const SizedBox(height: 16),
                            Text(
                              'No tanker data available',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                            if (_selectedDate != null) ...[
                              const SizedBox(height: 8),
                              Text(
                                'for ${DateFormat('dd MMM yyyy').format(_selectedDate!)}',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    : _buildDataTable(),
              ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          showDialog(
      context: context,
      builder: (context) => AddTankerDialog(
        tankerCapacities: _tankerCapacities,
              onSuccess: _fetchTankerData,
        imageClassifier: _imageClassifier,
              authService: widget.authService,
            ),
          );
        },
        backgroundColor: Colors.blue[800],
        child: const Icon(Icons.add),
      ),
    );
  }
}

class AddTankerDialog extends StatefulWidget {
  final Map<String, double> tankerCapacities;
  final VoidCallback onSuccess;
  final ImageClassifier imageClassifier;
  final AuthService authService;

  const AddTankerDialog({
    Key? key,
    required this.tankerCapacities,
    required this.onSuccess,
    required this.imageClassifier,
    required this.authService,
  }) : super(key: key);

  @override
  _AddTankerDialogState createState() => _AddTankerDialogState();
}

class _AddTankerDialogState extends State<AddTankerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _vehicleController = TextEditingController();
  final _capacityController = TextEditingController();
  final _driverNameController = TextEditingController();
  final _driverContactController = TextEditingController();
  final _vendorController = TextEditingController();
  final _dateController = TextEditingController();
  File? _photoFile;
  Position? _location;
  bool _isProcessing = false;
  String? _photoError;
  bool _isValidatingImage = false;
  double? _capacity;
  DateTime _selectedDate = DateTime.now();

  @override
  void initState() {
    super.initState();
    _getCurrentLocation();
    _dateController.text = DateFormat('yyyy-MM-dd').format(_selectedDate);
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
    }
  }

  Future<void> _getCurrentLocation() async {
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 5),
      );
      if (mounted) {
        setState(() => _location = position);
      }
    } catch (e) {
      debugPrint('Error getting location: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Unable to get current location. Please try again.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> _takePhoto() async {
    try {
      FocusManager.instance.primaryFocus?.unfocus();

      final status = await Permission.camera.status;
      if (status.isDenied) {
        final result = await Permission.camera.request();
        if (result.isDenied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Camera permission is required to take photos'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
      }

      setState(() => _isValidatingImage = true);

      final ImagePicker picker = ImagePicker();
      final XFile? photo = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (photo != null) {
        final File imageFile = File(photo.path);

        try {
          final validationResult = await widget.imageClassifier.validateAndClassifyImage(imageFile);
          if (!validationResult['isValid']) {
            if (mounted) {
              setState(() {
                _photoError = validationResult['message'] ?? 'Please take a clear photo of a tanker vehicle';
                _photoFile = null;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(validationResult['message'] ?? 'Image validation failed. Please take a clear photo of a tanker vehicle.'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 3),
                ),
              );
            }
            return;
          }
        } catch (validationError) {
          debugPrint('Image validation error: $validationError');
        }

        if (mounted) {
          setState(() {
            _photoFile = imageFile;
            _photoError = null;
          });
        }
      }
    } catch (e) {
      debugPrint('Error taking photo: $e');
      if (mounted) {
        setState(() => _photoError = 'Error capturing photo');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error taking photo: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isValidatingImage = false);
      }
    }
  }

  void _updateCapacity(String vehicleNo) {
    if (vehicleNo.length >= 4) {
      String prefix = vehicleNo.substring(0, 4).toUpperCase();
      setState(() {
        _capacity = widget.tankerCapacities[prefix];
      });
    } else {
      setState(() {
        _capacity = null;
      });
    }
  }

  Future<void> _submitData() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_photoFile == null) {
      setState(() => _photoError = 'Please take a photo of the tanker');
      return;
    }

    if (_location == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Waiting for location... Please try again.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isProcessing = true);
    try {
      debugPrint('Starting data submission...');
      
      // Add authentication token if available
      final token = widget.authService.token;
      
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('http://54.146.215.18:3000/tanker'),
      );

      // Add authorization header if token exists
      if (token != null) {
        request.headers['Authorization'] = 'Bearer $token';
      }

      debugPrint('Adding photo file: ${_photoFile!.path}');
      request.files.add(
        await http.MultipartFile.fromPath('photo', _photoFile!.path),
      );

      final fields = {
        'plateNumber': _vehicleController.text.trim().toUpperCase(),
        'capacity': _capacityController.text.trim(),
        'driverName': _driverNameController.text.trim(),
        'driverContact': _driverContactController.text.trim(),
        'vendor': _vendorController.text.trim(),
        'date': _dateController.text.trim(),
        'lastUpdated': DateTime.now().toIso8601String(),
        'latitude': _location?.latitude.toString() ?? '',
        'longitude': _location?.longitude.toString() ?? '',
      };

      debugPrint('Adding fields: $fields');
      request.fields.addAll(fields);

      debugPrint('Sending request...');
      final response = await request.send();
      final responseBody = await response.stream.bytesToString();
      debugPrint('Response status: ${response.statusCode}');
      debugPrint('Response body: $responseBody');

      if (response.statusCode == 201 || response.statusCode == 200) {
        if (mounted) {
          // Show success message
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tanker data saved successfully!'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 2),
            ),
          );
          Navigator.pop(context);
          widget.onSuccess();
        }
      } else {
        // Parse error message from response if possible
        String errorMessage = 'Failed to submit data';
        try {
          final errorData = jsonDecode(responseBody);
          errorMessage = errorData['message'] ?? errorMessage;
        } catch (e) {
          // Use default message if parsing fails
        }
        throw Exception('$errorMessage (Status: ${response.statusCode})');
      }
    } catch (e) {
      debugPrint('Error in _submitData: $e');
      if (mounted) {
        String userFriendlyMessage = 'Failed to save tanker data';
        
        if (e.toString().contains('TimeoutException')) {
          userFriendlyMessage = 'Request timed out. Please check your internet connection.';
        } else if (e.toString().contains('SocketException')) {
          userFriendlyMessage = 'Network error. Please check your internet connection.';
        } else if (e.toString().contains('401')) {
          userFriendlyMessage = 'Authentication failed. Please log in again.';
        } else if (e.toString().contains('500')) {
          userFriendlyMessage = 'Server error. Please try again later.';
        }
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(userFriendlyMessage, style: const TextStyle(fontWeight: FontWeight.bold)),
                if (e.toString().length < 100) Text(e.toString(), style: const TextStyle(fontSize: 12)),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 8),
            action: SnackBarAction(
              label: 'Retry',
              onPressed: () => _submitData(),
              textColor: Colors.white,
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New Tanker Entry'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_photoFile != null)
                Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Image.file(_photoFile!, fit: BoxFit.cover),
                ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _isValidatingImage ? null : _takePhoto,
                icon: const Icon(Icons.camera),
                label: Text(_isValidatingImage
                    ? 'Validating...'
                    : _photoFile == null ? 'Take Photo' : 'Retake Photo'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue[800],
                ),
              ),
              if (_photoError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _photoError!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _vehicleController,
                decoration: InputDecoration(
                  labelText: 'Vehicle Number',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onChanged: _updateCapacity,
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _dateController,
                decoration: InputDecoration(
                  labelText: 'Date',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  suffixIcon: const Icon(Icons.calendar_today),
                ),
                readOnly: true,
                onTap: () => _selectDate(context),
                validator: (value) =>
                    value?.isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _capacityController,
                decoration: const InputDecoration(labelText: 'Capacity (L)'),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value?.isEmpty ?? true) return 'Required';
                  if (double.tryParse(value!) == null) return 'Invalid number';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _driverNameController,
                decoration: const InputDecoration(labelText: 'Driver Name'),
                validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _driverContactController,
                decoration: const InputDecoration(labelText: 'Driver Contact'),
                validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _vendorController,
                decoration: const InputDecoration(labelText: 'Vendor'),
                validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              if (_location != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Text(
                    'Location: ${_location!.latitude.toStringAsFixed(6)}, '
                    '${_location!.longitude.toStringAsFixed(6)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
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
          onPressed: _isProcessing ? null : _submitData,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.blue[800],
          ),
          child: _isProcessing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Submit'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _vehicleController.dispose();
    _capacityController.dispose();
    _driverNameController.dispose();
    _driverContactController.dispose();
    _vendorController.dispose();
    _dateController.dispose();
    super.dispose();
  }
}

class EditTankerDialog extends StatefulWidget {
  final Map<String, dynamic> data;

  const EditTankerDialog({
    Key? key,
    required this.data,
  }) : super(key: key);

  @override
  _EditTankerDialogState createState() => _EditTankerDialogState();
}

class _EditTankerDialogState extends State<EditTankerDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _vehicleController;
  late TextEditingController _capacityController;

  @override
  void initState() {
    super.initState();
    _vehicleController = TextEditingController(text: widget.data['plateNumber'] ?? widget.data['vehicle_no'] ?? '');
    _capacityController = TextEditingController(text: (widget.data['capacity'] ?? 0).toString());
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit Tanker Entry'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: _vehicleController,
              decoration: const InputDecoration(labelText: 'Vehicle Number'),
              validator: (value) => value?.isEmpty ?? true ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _capacityController,
              decoration: const InputDecoration(labelText: 'Capacity (L)'),
              keyboardType: TextInputType.number,
              validator: (value) {
                if (value?.isEmpty ?? true) return 'Required';
                if (double.tryParse(value!) == null) return 'Invalid number';
                return null;
              },
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, {
                'vehicle_no': _vehicleController.text,
                'capacity': double.parse(_capacityController.text),
              });
            }
          },
          child: const Text('Save'),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _vehicleController.dispose();
    _capacityController.dispose();
    super.dispose();
  }
}
