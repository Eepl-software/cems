import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:image_picker/image_picker.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class BWSSBTankerManagementScreen extends StatefulWidget {
  const BWSSBTankerManagementScreen({Key? key}) : super(key: key);

  @override
  _BWSSBTankerManagementScreenState createState() => _BWSSBTankerManagementScreenState();
}

class _BWSSBTankerManagementScreenState extends State<BWSSBTankerManagementScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  String? _errorMessage;
  Position? _currentPosition;
  List<Map<String, dynamic>> _entries = [];
  List<Map<String, dynamic>> _registeredVehicles = [];
  List<Map<String, dynamic>> _gates = [];

  // Filters
  DateTime? _selectedDate;
  String? _vehicleFilter;
  String? _waterTypeFilter;
  String? _statusFilter;

  // Statistics
  Map<String, dynamic> _statistics = {
    'quantityByType': [],
    'dailyQuantity': [],
    'ongoingEntries': 0,
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _checkLocationPermission();
    _fetchData();
    _fetchStatistics();
    _fetchGates();
    _fetchRegisteredVehicles();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // Check and request location permissions
  Future<void> _checkLocationPermission() async {
    final status = await Permission.location.request();
    if (status.isGranted) {
      _getCurrentLocation();
    } else {
      setState(() {
        _errorMessage = 'Location permission denied. Some features may not work properly.';
      });
    }
  }

  // Get current location
  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      setState(() {
        _currentPosition = position;
        _errorMessage = null;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to get current location: $e';
      });
    }
  }

  // Fetch all entries from API
  Future<void> _fetchData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // Construct query parameters
      Map<String, String> queryParams = {};
      if (_selectedDate != null) {
        queryParams['date'] = DateFormat('yyyy-MM-dd').format(_selectedDate!);
      }
      if (_vehicleFilter != null && _vehicleFilter!.isNotEmpty) {
        queryParams['vehicleNumber'] = _vehicleFilter!;
      }
      if (_waterTypeFilter != null && _waterTypeFilter!.isNotEmpty) {
        queryParams['waterType'] = _waterTypeFilter!;
      }
      if (_statusFilter != null && _statusFilter!.isNotEmpty) {
        queryParams['status'] = _statusFilter!;
      }

      final url = Uri.parse('http://54.146.215.18:3000/bwssb')
          .replace(queryParameters: queryParams);

      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _entries = List<Map<String, dynamic>>.from(data['data']);
          _isLoading = false;
        });
      } else {
        throw Exception('Failed to load data: ${response.reasonPhrase}');
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error: ${e.toString()}';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    }
  }

  // Fetch statistics
  Future<void> _fetchStatistics() async {
    try {
      final url = Uri.parse('http://54.146.215.18:3000/bwssb/stats');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _statistics = data['data'];
        });
      }
    } catch (e) {
      print('Error fetching statistics: $e');
    }
  }

  // Fetch all gate locations
  Future<void> _fetchGates() async {
    try {
      final url = Uri.parse('http://54.146.215.18:3000/bwssb/gates');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _gates = List<Map<String, dynamic>>.from(data['data']);
        });
      }
    } catch (e) {
      print('Error fetching gates: $e');
    }
  }

  // Fetch registered vehicles
  Future<void> _fetchRegisteredVehicles() async {
    try {
      final url = Uri.parse('http://54.146.215.18:3000/bwssb/vehicles');
      final response = await http.get(url);

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _registeredVehicles = List<Map<String, dynamic>>.from(data['data']);
        });
      }
    } catch (e) {
      print('Error fetching registered vehicles: $e');
    }
  }

  // Compress image file for upload
  Future<File?> _compressImage(File file) async {
    final dir = await getTemporaryDirectory();
    final targetPath = p.join(dir.path, '${DateTime.now().millisecondsSinceEpoch}.jpg');
    
    var result = await FlutterImageCompress.compressAndGetFile(
      file.absolute.path,
      targetPath,
      quality: 70,
      minWidth: 800,
      minHeight: 600,
    );
    
    return result != null ? File(result.path) : null;
  }

  // Pick image from camera or gallery
  Future<File?> _pickImage(ImageSource source) async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 1600,
      maxHeight: 1200,
    );

    if (pickedFile != null) {
      File file = File(pickedFile.path);
      return await _compressImage(file);
    }
    return null;
  }

  // Recognize license plate from image
  Future<Map<String, dynamic>?> _recognizeLicensePlate(File imageFile) async {
    try {
      setState(() {
        _isLoading = true;
      });

      final url = Uri.parse('http://54.146.215.18:3000/bwssb/recognize-plate');
      
      var request = http.MultipartRequest('POST', url);
      request.files.add(await http.MultipartFile.fromPath('photo', imageFile.path));
      
      var response = await request.send();
      var responseData = await response.stream.bytesToString();
      
      if (response.statusCode == 200) {
        final data = jsonDecode(responseData);
        return data['data'];
      } else {
        throw Exception('Failed to recognize plate: ${jsonDecode(responseData)['message']}');
      }
    } catch (e) {
      print('Error recognizing license plate: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error recognizing license plate: $e')),
      );
      return null;
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // Show image picker modal
  Future<File?> _showImagePickerModal() async {
    File? imageFile;
    await showModalBottomSheet(
      context: context,
      builder: (BuildContext context) {
        return SafeArea(
          child: Wrap(
            children: <Widget>[
              ListTile(
                leading: const Icon(Icons.camera_alt),
                title: const Text('Take a picture'),
                onTap: () async {
                  Navigator.of(context).pop();
                  imageFile = await _pickImage(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: const Text('Choose from gallery'),
                onTap: () async {
                  Navigator.of(context).pop();
                  imageFile = await _pickImage(ImageSource.gallery);
                },
              ),
            ],
          ),
        );
      },
    );
    return imageFile;
  }

  // Record tanker entry
  Future<void> _recordTankerEntry(BuildContext context, {String? prefilledVehicleNumber}) async {
    final _formKey = GlobalKey<FormState>();
    String? vehicleNumber = prefilledVehicleNumber;
    String waterType = 'Fresh';
    String entryGate = 'Fresh';
    double initialReading = 0.0;
    String? driverName;
    String? driverContact;
    String? remarks;
    File? imageFile;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Record Tanker Entry'),
              content: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // License plate recognition / Vehicle selection
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<String>(
                              decoration: const InputDecoration(
                                labelText: 'Vehicle Number',
                                border: OutlineInputBorder(),
                              ),
                              value: vehicleNumber,
                              items: _registeredVehicles.map((vehicle) {
                                return DropdownMenuItem<String>(
                                  value: vehicle['vehicleNumber'],
                                  child: Text(vehicle['vehicleNumber']),
                                );
                              }).toList(),
                              onChanged: (value) {
                                setState(() {
                                  vehicleNumber = value;
                                  // Auto-select water type based on registered type
                                  final selectedVehicle = _registeredVehicles.firstWhere(
                                    (v) => v['vehicleNumber'] == value,
                                    orElse: () => <String, dynamic>{},
                                  );
                                  if (selectedVehicle.isNotEmpty) {
                                    waterType = selectedVehicle['waterType'];
                                    entryGate = selectedVehicle['waterType']; // Default same gate as water type
                                    driverName = selectedVehicle['driverName'];
                                    driverContact = selectedVehicle['driverContact'];
                                  }
                                });
                              },
                              validator: (value) => 
                                  value == null ? 'Please select a vehicle' : null,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.camera_alt),
                            onPressed: () async {
                              imageFile = await _showImagePickerModal();
                              if (imageFile != null) {
                                // Recognize license plate
                                final recognizedData = await _recognizeLicensePlate(imageFile!);
                                if (recognizedData != null) {
                                  setState(() {
                                    vehicleNumber = recognizedData['vehicleNumber'];
                                    // Auto-select water type based on recognized vehicle
                                    final selectedVehicle = _registeredVehicles.firstWhere(
                                      (v) => v['vehicleNumber'] == vehicleNumber,
                                      orElse: () => <String, dynamic>{},
                                    );
                                    if (selectedVehicle.isNotEmpty) {
                                      waterType = selectedVehicle['waterType'];
                                      entryGate = selectedVehicle['waterType'];
                                      driverName = selectedVehicle['driverName'];
                                      driverContact = selectedVehicle['driverContact'];
                                    }
                                  });
                                }
                              }
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      
                      // Water type selection
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Water Type',
                          border: OutlineInputBorder(),
                        ),
                        value: waterType,
                        items: const [
                          DropdownMenuItem(value: 'Fresh', child: Text('Fresh Water')),
                          DropdownMenuItem(value: 'Treated', child: Text('Treated Water')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            waterType = value!;
                            // Auto-select same entry gate as water type
                            entryGate = value;
                          });
                        },
                        validator: (value) => value == null ? 'Please select water type' : null,
                      ),
                      const SizedBox(height: 16),
                      
                      // Entry gate selection
                      DropdownButtonFormField<String>(
                        decoration: const InputDecoration(
                          labelText: 'Entry Gate',
                          border: OutlineInputBorder(),
                        ),
                        value: entryGate,
                        items: const [
                          DropdownMenuItem(value: 'Fresh', child: Text('Fresh Water Gate')),
                          DropdownMenuItem(value: 'Treated', child: Text('Treated Water Gate')),
                        ],
                        onChanged: (value) {
                          setState(() {
                            entryGate = value!;
                          });
                        },
                        validator: (value) => value == null ? 'Please select entry gate' : null,
                      ),
                      const SizedBox(height: 16),
                      
                      // Initial reading
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Initial Reading (L)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          initialReading = double.tryParse(value) ?? 0.0;
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter initial reading';
                          }
                          if (double.tryParse(value) == null || double.parse(value) <= 0) {
                            return 'Please enter a valid positive number';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // Driver name
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Driver Name (Optional)',
                          border: OutlineInputBorder(),
                        ),
                        initialValue: driverName,
                        onChanged: (value) {
                          driverName = value;
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // Driver contact
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Driver Contact (Optional)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.phone,
                        initialValue: driverContact,
                        onChanged: (value) {
                          driverContact = value;
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // Remarks
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Remarks (Optional)',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                        onChanged: (value) {
                          remarks = value;
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // Photo
                      if (imageFile != null)
                        Container(
                          height: 150,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.file(
                              imageFile!,
                              fit: BoxFit.cover,
                            ),
                          ),
                        )
                      else
                        ElevatedButton.icon(
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Take Entry Photo'),
                          onPressed: () async {
                            final File? capturedImage = await _showImagePickerModal();
                            if (capturedImage != null) {
                              setState(() {
                                imageFile = capturedImage;
                              });
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                ),
                ElevatedButton(
                  child: const Text('Submit'),
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      Navigator.of(context).pop(true);
                    }
                  },
                ),
              ],
            );
          }
        );
      },
    );

    if (result == true) {
      // Form validated and user clicked Submit
      try {
        setState(() {
          _isLoading = true;
        });

        // Ensure we have location
        if (_currentPosition == null) {
          await _getCurrentLocation();
        }

        // Create multipart request
        var request = http.MultipartRequest(
          'POST',
          Uri.parse('http://54.146.215.18:3000/bwssb/entry'),
        );

        // Add text fields
        request.fields['vehicleNumber'] = vehicleNumber!;
        request.fields['waterType'] = waterType;
        request.fields['entryGate'] = entryGate;
        request.fields['initialReading'] = initialReading.toString();
        
        if (driverName != null && driverName!.isNotEmpty) {
          request.fields['driverName'] = driverName!;
        }
        
        if (driverContact != null && driverContact!.isNotEmpty) {
          request.fields['driverContact'] = driverContact!;
        }
        
        if (remarks != null && remarks!.isNotEmpty) {
          request.fields['remarks'] = remarks!;
        }
        
        // Add location
        request.fields['latitude'] = (_currentPosition?.latitude ?? 0.0).toString();
        request.fields['longitude'] = (_currentPosition?.longitude ?? 0.0).toString();
        
        // Add photo if available
        if (imageFile != null) {
          request.files.add(
            await http.MultipartFile.fromPath('photo', imageFile!.path),
          );
        }

        // Send request
        var response = await request.send();
        var responseData = await response.stream.bytesToString();
        
        if (response.statusCode == 201) {
          // Success
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tanker entry recorded successfully'),
              backgroundColor: Colors.green,
            ),
          );
          
          // Refresh data
          _fetchData();
          _fetchStatistics();
        } else {
          // Error
          final errorMessage = jsonDecode(responseData)['message'] ?? 'Unknown error';
          throw Exception('Failed to record entry: $errorMessage');
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // Record tanker exit
  Future<void> _recordTankerExit(BuildContext context, Map<String, dynamic> entry) async {
    final _formKey = GlobalKey<FormState>();
    double finalReading = 0.0;
    String? remarks;
    File? imageFile;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Record Tanker Exit'),
              content: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Vehicle information display
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Vehicle: ${entry['vehicleNumber']}', 
                              style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text('Water Type: ${entry['waterType']}'),
                            Text('Initial Reading: ${entry['initialReading']}'),
                            Text('Entry Time: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(entry['entryTime']))}'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      
                      // Final reading
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Final Reading (L)',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onChanged: (value) {
                          finalReading = double.tryParse(value) ?? 0.0;
                        },
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return 'Please enter final reading';
                          }
                          final reading = double.tryParse(value);
                          if (reading == null || reading <= 0) {
                            return 'Please enter a valid positive number';
                          }
                          if (reading <= entry['initialReading']) {
                            return 'Final reading must be greater than initial reading';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // Remarks
                      TextFormField(
                        decoration: const InputDecoration(
                          labelText: 'Remarks (Optional)',
                          border: OutlineInputBorder(),
                        ),
                        maxLines: 2,
                        onChanged: (value) {
                          remarks = value;
                        },
                      ),
                      const SizedBox(height: 16),
                      
                      // Photo
                      if (imageFile != null)
                        Container(
                          height: 150,
                          width: double.infinity,
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: Image.file(
                              imageFile!,
                              fit: BoxFit.cover,
                            ),
                          ),
                        )
                      else
                        ElevatedButton.icon(
                          icon: const Icon(Icons.camera_alt),
                          label: const Text('Take Exit Photo'),
                          onPressed: () async {
                            final File? capturedImage = await _showImagePickerModal();
                            if (capturedImage != null) {
                              setState(() {
                                imageFile = capturedImage;
                              });
                            }
                          },
                        ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('Cancel'),
                  onPressed: () {
                    Navigator.of(context).pop(false);
                  },
                ),
                ElevatedButton(
                  child: const Text('Submit'),
                  onPressed: () {
                    if (_formKey.currentState!.validate()) {
                      Navigator.of(context).pop(true);
                    }
                  },
                ),
              ],
            );
          }
        );
      },
    );

    if (result == true) {
      // Form validated and user clicked Submit
      try {
        setState(() {
          _isLoading = true;
        });

        // Ensure we have location
        if (_currentPosition == null) {
          await _getCurrentLocation();
        }

        // Create multipart request
        var request = http.MultipartRequest(
          'PUT',
          Uri.parse('http://54.146.215.18:3000/bwssb/exit/${entry['id']}'),
        );

        // Add text fields
        request.fields['finalReading'] = finalReading.toString();
        
        if (remarks != null && remarks!.isNotEmpty) {
          request.fields['remarks'] = remarks!;
        }
        
        // Add location
        request.fields['latitude'] = (_currentPosition?.latitude ?? 0.0).toString();
        request.fields['longitude'] = (_currentPosition?.longitude ?? 0.0).toString();
        
        // Add photo if available
        if (imageFile != null) {
          request.files.add(
            await http.MultipartFile.fromPath('photo', imageFile!.path),
          );
        }

        // Send request
        var response = await request.send();
        var responseData = await response.stream.bytesToString();
        
        if (response.statusCode == 200) {
          // Success
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Tanker exit recorded successfully'),
              backgroundColor: Colors.green,
            ),
          );
          
          // Refresh data
          _fetchData();
          _fetchStatistics();
        } else {
          // Error
          final errorMessage = jsonDecode(responseData)['message'] ?? 'Unknown error';
          throw Exception('Failed to record exit: $errorMessage');
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      } finally {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  // View entry details
  void _viewEntryDetails(Map<String, dynamic> entry) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Tanker ${entry['vehicleNumber']}'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Status: ${entry['status']}', 
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: entry['status'] == 'Completed' ? Colors.green : Colors.blue,
                        )),
                      Text('Water Type: ${entry['waterType']}'),
                      Text('Entry Gate: ${entry['entryGate']}'),
                      Text('Entry Time: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(entry['entryTime']))}'),
                      if (entry['exitTime'] != null)
                        Text('Exit Time: ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.parse(entry['exitTime']))}'),
                      const SizedBox(height: 8),
                      Text('Initial Reading: ${entry['initialReading']} L'),
                      if (entry['finalReading'] != null)
                        Text('Final Reading: ${entry['finalReading']} L'),
                      if (entry['quantitySupplied'] != null)
                        Text('Quantity Supplied: ${entry['quantitySupplied']} L', 
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      if (entry['driverName'] != null)
                        Text('Driver: ${entry['driverName']}'),
                      if (entry['driverContact'] != null)
                        Text('Contact: ${entry['driverContact']}'),
                      if (entry['remarks'] != null && entry['remarks'].isNotEmpty)
                        Text('Remarks: ${entry['remarks']}'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        children: [
                          const Text('Entry Photo', 
                            style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          if (entry['entryPhotoUrl'] != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: entry['entryPhotoUrl'],
                                height: 150,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => 
                                    const Center(child: CircularProgressIndicator()),
                                errorWidget: (context, url, error) => 
                                    const Icon(Icons.error),
                              ),
                            )
                          else
                            Container(
                              height: 150,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Center(
                                child: Text('No entry photo'),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        children: [
                          const Text('Exit Photo', 
                            style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          if (entry['exitPhotoUrl'] != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: CachedNetworkImage(
                                imageUrl: entry['exitPhotoUrl'],
                                height: 150,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => 
                                    const Center(child: CircularProgressIndicator()),
                                errorWidget: (context, url, error) => 
                                    const Icon(Icons.error),
                              ),
                            )
                          else
                            Container(
                              height: 150,
                              width: double.infinity,
                              decoration: BoxDecoration(
                                border: Border.all(color: Colors.grey),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Center(
                                child: Text('No exit photo'),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              child: const Text('Close'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            if (entry['status'] == 'In Progress')
              ElevatedButton(
                child: const Text('Record Exit'),
                onPressed: () {
                  Navigator.of(context).pop();
                  _recordTankerExit(context, entry);
                },
              ),
          ],
        );
      },
    );
  }

  // Filter dialog
  void _showFilterDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Filter Data'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Date filter
                    ListTile(
                      title: Text(
                        _selectedDate == null 
                            ? 'All Dates' 
                            : 'Date: ${DateFormat('yyyy-MM-dd').format(_selectedDate!)}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_selectedDate != null)
                            IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                setState(() {
                                  _selectedDate = null;
                                });
                              },
                            ),
                          IconButton(
                            icon: const Icon(Icons.calendar_today),
                            onPressed: () async {
                              final DateTime? picked = await showDatePicker(
                                context: context,
                                initialDate: _selectedDate ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030),
                              );
                              if (picked != null) {
                                setState(() {
                                  _selectedDate = picked;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                    
                    // Vehicle filter
                    TextField(
                      decoration: InputDecoration(
                        labelText: 'Vehicle Number',
                        hintText: 'Filter by vehicle number',
                        suffixIcon: _vehicleFilter != null && _vehicleFilter!.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  setState(() {
                                    _vehicleFilter = null;
                                  });
                                },
                              )
                            : null,
                      ),
                      onChanged: (value) {
                        setState(() {
                          _vehicleFilter = value.isEmpty ? null : value;
                        });
                      },
                      controller: TextEditingController(text: _vehicleFilter),
                    ),
                    
                    // Water type filter
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Water Type',
                      ),
                      value: _waterTypeFilter,
                      items: const [
                        DropdownMenuItem(value: '', child: Text('All Types')),
                        DropdownMenuItem(value: 'Fresh', child: Text('Fresh Water')),
                        DropdownMenuItem(value: 'Treated', child: Text('Treated Water')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _waterTypeFilter = value == '' ? null : value;
                        });
                      },
                    ),
                    
                    // Status filter
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Status',
                      ),
                      value: _statusFilter,
                      items: const [
                        DropdownMenuItem(value: '', child: Text('All Statuses')),
                        DropdownMenuItem(value: 'In Progress', child: Text('In Progress')),
                        DropdownMenuItem(value: 'Completed', child: Text('Completed')),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _statusFilter = value == '' ? null : value;
                        });
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  child: const Text('Reset'),
                  onPressed: () {
                    setState(() {
                      _selectedDate = null;
                      _vehicleFilter = null;
                      _waterTypeFilter = null;
                      _statusFilter = null;
                    });
                  },
                ),
                ElevatedButton(
                  child: const Text('Apply'),
                  onPressed: () {
                    Navigator.of(context).pop();
                    _fetchData();
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Build statistics tab
  Widget _buildStatisticsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Water Supply Summary',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  
                  // Fresh water total
                  Row(
                    children: [
                      const Icon(Icons.water_drop, color: Colors.blue),
                      const SizedBox(width: 8),
                      const Text('Fresh Water Supply:'),
                      const Spacer(),
                      Text(
                        '${_statistics['quantityByType'].firstWhere((e) => e['water_type'] == 'Fresh', orElse: () => {'total_quantity': 0})['total_quantity']} L',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // Treated water total
                  Row(
                    children: [
                      const Icon(Icons.water, color: Colors.green),
                      const SizedBox(width: 8),
                      const Text('Treated Water Supply:'),
                      const Spacer(),
                      Text(
                        '${_statistics['quantityByType'].firstWhere((e) => e['water_type'] == 'Treated', orElse: () => {'total_quantity': 0})['total_quantity']} L',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // Total tankers count
                  Row(
                    children: [
                      const Icon(Icons.local_shipping, color: Colors.orange),
                      const SizedBox(width: 8),
                      const Text('Total Tankers Served:'),
                      const Spacer(),
                      Text(
                        _statistics['quantityByType'].fold(0, (sum, e) => sum + e['tanker_count']).toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  
                  // Ongoing entries
                  Row(
                    children: [
                      const Icon(Icons.pending_actions, color: Colors.purple),
                      const SizedBox(width: 8),
                      const Text('Ongoing Entries:'),
                      const Spacer(),
                      Text(
                        _statistics['ongoingEntries'].toString(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          
          // Daily supply chart (simplified for this implementation)
          Card(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Daily Supply Data',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Divider(),
                  const SizedBox(height: 8),
                  
                  // In a real implementation, you would use a proper charting library
                  // This is a simplified representation
                  if (_statistics['dailyQuantity'].isEmpty)
                    const Center(
                      child: Text('No daily data available'),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _statistics['dailyQuantity'].length < 7 
                          ? _statistics['dailyQuantity'].length 
                          : 7,
                      itemBuilder: (context, index) {
                        final data = _statistics['dailyQuantity'][index];
                        final date = DateFormat('yyyy-MM-dd')
                            .format(DateTime.parse(data['supply_date']));
                        return ListTile(
                          title: Text(date),
                          subtitle: Text('${data['water_type']} Water'),
                          trailing: Text(
                            '${data['total_quantity']} L (${data['tanker_count']} tankers)',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // Build data entries tab
  Widget _buildEntriesTab() {
    return Column(
      children: [
        // Filter bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _selectedDate != null 
                      ? 'Date: ${DateFormat('yyyy-MM-dd').format(_selectedDate!)}'
                      : 'All Entries',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.filter_list),
                onPressed: _showFilterDialog,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  setState(() {
                    _selectedDate = null;
                    _vehicleFilter = null;
                    _waterTypeFilter = null;
                    _statusFilter = null;
                  });
                  _fetchData();
                },
              ),
            ],
          ),
        ),
        
        // Data table
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _entries.isEmpty
                  ? const Center(child: Text('No data found'))
                  : ListView.builder(
                      itemCount: _entries.length,
                      itemBuilder: (context, index) {
                        final entry = _entries[index];
                        final bool isCompleted = entry['status'] == 'Completed';
                        
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: isCompleted ? Colors.green : Colors.blue,
                              width: 1,
                            ),
                          ),
                          child: ListTile(
                            title: Row(
                              children: [
                                Text(
                                  entry['vehicleNumber'],
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: entry['waterType'] == 'Fresh'
                                        ? Colors.blue.shade100
                                        : Colors.green.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    entry['waterType'],
                                    style: TextStyle(
                                      color: entry['waterType'] == 'Fresh'
                                          ? Colors.blue.shade900
                                          : Colors.green.shade900,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Entry: ${DateFormat('MM/dd HH:mm').format(DateTime.parse(entry['entryTime']))}'),
                                if (isCompleted)
                                  Text('Quantity: ${entry['quantitySupplied']} L'),
                              ],
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: isCompleted
                                        ? Colors.green.shade100
                                        : Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    entry['status'],
                                    style: TextStyle(
                                      color: isCompleted
                                          ? Colors.green.shade900
                                          : Colors.orange.shade900,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.info_outline),
                                  onPressed: () => _viewEntryDetails(entry),
                                ),
                              ],
                            ),
                            onTap: () => _viewEntryDetails(entry),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // Build registered vehicles tab
  Widget _buildVehiclesTab() {
    return Column(
      children: [
        // Filter bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  decoration: const InputDecoration(
                    labelText: 'Water Type',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  value: _waterTypeFilter ?? '',
                  items: const [
                    DropdownMenuItem(value: '', child: Text('All Types')),
                    DropdownMenuItem(value: 'Fresh', child: Text('Fresh Water')),
                    DropdownMenuItem(value: 'Treated', child: Text('Treated Water')),
                  ],
                  onChanged: (value) {
                    setState(() {
                      _waterTypeFilter = value == '' ? null : value;
                    });
                  },
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: () {
                  setState(() {
                    _waterTypeFilter = null;
                  });
                  _fetchRegisteredVehicles();
                },
              ),
            ],
          ),
        ),
        
        // Vehicles list
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _registeredVehicles.isEmpty
                  ? const Center(child: Text('No registered vehicles found'))
                  : ListView.builder(
                      itemCount: _registeredVehicles.length,
                      itemBuilder: (context, index) {
                        final vehicle = _registeredVehicles[index];
                        final bool isFresh = vehicle['waterType'] == 'Fresh';
                        
                        if (_waterTypeFilter != null && vehicle['waterType'] != _waterTypeFilter) {
                          return const SizedBox.shrink();
                        }
                        
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color: isFresh ? Colors.blue : Colors.green,
                              width: 1,
                            ),
                          ),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isFresh ? Colors.blue : Colors.green,
                              child: Icon(
                                isFresh ? Icons.water_drop : Icons.water,
                                color: Colors.white,
                              ),
                            ),
                            title: Text(
                              vehicle['vehicleNumber'],
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Capacity: ${vehicle['capacity']} L'),
                                if (vehicle['vendorName'] != null)
                                  Text('Vendor: ${vehicle['vendorName']}'),
                              ],
                            ),
                            trailing: ElevatedButton(
                              child: const Text('Record Entry'),
                              onPressed: () {
                                _recordTankerEntry(context, prefilledVehicleNumber: vehicle['vehicleNumber']);
                              },
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'BWSSB Water Supply Management',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.grid_view), text: 'Entries'),
            Tab(icon: Icon(Icons.bar_chart), text: 'Statistics'),
            Tab(icon: Icon(Icons.local_shipping), text: 'Vehicles'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.my_location),
            onPressed: _getCurrentLocation,
          ),
        ],
      ),
      body: _isLoading && _entries.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildEntriesTab(),
                _buildStatisticsTab(),
                _buildVehiclesTab(),
              ],
            ),
      floatingActionButton: _tabController.index == 0
          ? FloatingActionButton.extended(
              onPressed: () => _recordTankerEntry(context),
              backgroundColor: Colors.blue,
              icon: const Icon(Icons.add),
              label: const Text('Record Entry'),
            )
          : null,
    );
  }
}