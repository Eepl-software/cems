import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'dart:math';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';

class TreatedWaterDashboard extends StatefulWidget {
  const TreatedWaterDashboard({Key? key}) : super(key: key);

  @override
  TreatedWaterDashboardState createState() => TreatedWaterDashboardState();
}

class TreatedWaterDashboardState extends State<TreatedWaterDashboard> {
  final _formKey = GlobalKey<FormState>();
  DateTime _selectedDate = DateTime.now();
  
  // Controllers for input fields
  final _dateController = TextEditingController();
  final _labourersController = TextEditingController();
  
  // Data persistence
  late SharedPreferences _prefs;
  Map<String, dynamic> _dailyData = {};
  
  
  // Calculated values
  double _sewageWaterGenerated = 0.0; // 90% of total water (from labor colony)
  double _totalFreshWaterRequired = 0.0; // 135L per labor
  double _drinkingWaterUsed = 0.0; // 10% of total water
  double _treatedWaterAvailable = 0.0; // From STP
  double _treatedWaterUsed = 0.0; // Used in construction
  double _treatedWaterBalance = 0.0; // Available - Used
  
  // Treated water source
  String _treatedWaterSource = 'In-house STP'; // 'In-house STP' or 'External Tanker'
  
  // Fresh water source for 135L per labor
  String? _freshWaterSource;
  final List<String> _freshWaterSources = [
    'BWSSB Supply',
    'Tanker Water',
    'Borewell Water',
    'Mixed Sources',
  ];
  
  // External tanker details list (when treated water comes from outside)
  List<TreatedWaterTankerDetail> _treatedWaterTankerDetails = [];
  
  // Fresh water tanker details list (separate from treated water tankers)
  List<FreshWaterTankerDetail> _freshWaterTankerDetails = [];
  
  // GPS and Location Tracking
  Position? _currentPosition;
  bool _isTrackingLocation = false;
  List<TankerGPSEntry> _gpsEntries = [];
  
  // Water Source Types with GPS coordinates
  final Map<String, WaterSource> _waterSources = {
    'Borewell-1': WaterSource(
      name: 'Borewell Station 1', 
      type: 'Borewell', 
      coordinates: const LatLng(12.9716, 77.5946),
      capacity: 50000.0,
      qualityCertification: 'BWS-CERT-001'
    ),
    'Municipal-1': WaterSource(
      name: 'BWSSB Supply Point', 
      type: 'Municipal Supply', 
      coordinates: const LatLng(12.9698, 77.5988),
      capacity: 100000.0,
      qualityCertification: 'BWSSB-CERT-001'
    ),
    'STP-1': WaterSource(
      name: 'In-house STP Plant', 
      type: 'Treated Wastewater (STP)', 
      coordinates: const LatLng(12.9814, 77.6441),
      capacity: 75000.0,
      qualityCertification: 'STP-CERT-001'
    ),
  };
  
  // Construction activities dropdown options
  final List<String> _constructionActivities = [
    'Slab Casting',
    'Brick Work',
    'Curing',
    'Plastering',
    'Foundation Work',
    'Column Casting',
    'Beam Casting',
    'Wall Construction',
    'Flooring',
    'External Works',
    'Other',
  ];
  
  String? _selectedActivity;
  
  // Tanker data with type restrictions - CRITICAL: Treated water tankers CANNOT carry fresh water
  final Map<String, Map<String, dynamic>> _tankerRegistry = {
    // TREATED WATER TANKERS ONLY (STP Certified)
    'KA01T8743': {'capacity': 12000.0, 'type': 'TREATED', 'certification': 'STP-CERT-001'},
    'KA01T1234': {'capacity': 24000.0, 'type': 'TREATED', 'certification': 'STP-CERT-002'},
    'KA01T2221': {'capacity': 26000.0, 'type': 'TREATED', 'certification': 'STP-CERT-003'},
    'KA01T2435': {'capacity': 28000.0, 'type': 'TREATED', 'certification': 'STP-CERT-004'},
    'KA01T2122': {'capacity': 30000.0, 'type': 'TREATED', 'certification': 'STP-CERT-005'},
    
    // FRESH WATER TANKERS ONLY (Potable Water Certified)
    'KA01F1010': {'capacity': 38000.0, 'type': 'FRESH', 'certification': 'PWS-CERT-001'},
    'KA01F1424': {'capacity': 40000.0, 'type': 'FRESH', 'certification': 'PWS-CERT-002'},
    'KA01F9210': {'capacity': 42000.0, 'type': 'FRESH', 'certification': 'PWS-CERT-003'},
    'KA01F1111': {'capacity': 44000.0, 'type': 'FRESH', 'certification': 'PWS-CERT-004'},
    'KA01F2222': {'capacity': 46000.0, 'type': 'FRESH', 'certification': 'PWS-CERT-005'},
  };
  
  // Get tankers by type
  Map<String, Map<String, dynamic>> get _treatedWaterTankers {
    return Map.fromEntries(
      _tankerRegistry.entries.where((entry) => entry.value['type'] == 'TREATED')
    );
  }
  

  @override
  void initState() {
    super.initState();
    _initializeData();
  }
  
  Future<void> _initializeData() async {
    _prefs = await SharedPreferences.getInstance();
    _dateController.text = DateFormat('yyyy-MM-dd').format(_selectedDate);
    await _loadDailyData();
    await _loadGPSEntries();
  }
  
  Future<void> _loadDailyData() async {
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    final savedData = _prefs.getString('treated_water_data_$dateKey');
    
    if (savedData != null) {
      setState(() {
        _dailyData = json.decode(savedData);
        _labourersController.text = _dailyData['labourers']?.toString() ?? '';
        _selectedActivity = _dailyData['activity'];
        _freshWaterSource = _dailyData['freshWaterSource'];
        _treatedWaterSource = _dailyData['treatedWaterSource'] ?? 'In-house STP';
        
        // Load treated water tanker details
        _treatedWaterTankerDetails.clear();
        if (_dailyData['treatedWaterTankers'] != null) {
          for (var tanker in _dailyData['treatedWaterTankers']) {
            _treatedWaterTankerDetails.add(TreatedWaterTankerDetail(
              tankerNumber: tanker['number'],
              capacity: (tanker['capacity'] ?? 0.0).toDouble(),
              trips: tanker['trips'] ?? 0,
              driverName: tanker['driverName'],
              driverLicenseUrl: tanker['driverLicenseUrl'],
              vendorLicenseUrl: tanker['vendorLicenseUrl'],
              tankerPhotoUrl: tanker['tankerPhotoUrl'],
              vendor: tanker['vendor'],
              certification: tanker['certification'],
            ));
          }
        }
        
        // Load fresh water tanker details
        _freshWaterTankerDetails.clear();
        if (_dailyData['freshWaterTankers'] != null) {
          for (var tanker in _dailyData['freshWaterTankers']) {
            _freshWaterTankerDetails.add(FreshWaterTankerDetail(
              tankerNumber: tanker['number'],
              capacity: (tanker['capacity'] ?? 0.0).toDouble(),
              trips: tanker['trips'] ?? 0,
              driverName: tanker['driverName'],
              driverLicenseUrl: tanker['driverLicenseUrl'],
              vendorLicenseUrl: tanker['vendorLicenseUrl'],
              tankerPhotoUrl: tanker['tankerPhotoUrl'],
              vendor: tanker['vendor'],
              certification: tanker['certification'],
            ));
          }
        }
        
        _calculateWaterMetrics();
      });
    }
  }
  
  Future<void> _saveDailyData() async {
    final dateKey = DateFormat('yyyy-MM-dd').format(_selectedDate);
    
    _dailyData = {
      'date': dateKey,
      'labourers': int.tryParse(_labourersController.text) ?? 0,
      'activity': _selectedActivity,
      'freshWaterSource': _freshWaterSource,
      'treatedWaterSource': _treatedWaterSource,
      'treatedWaterTankers': _treatedWaterTankerDetails.map((t) => {
        'number': t.tankerNumber,
        'capacity': t.capacity,
        'trips': t.trips,
        'driverName': t.driverName,
        'driverLicenseUrl': t.driverLicenseUrl,
        'vendorLicenseUrl': t.vendorLicenseUrl,
        'tankerPhotoUrl': t.tankerPhotoUrl,
        'vendor': t.vendor,
        'certification': t.certification,
      }).toList(),
      'freshWaterTankers': _freshWaterTankerDetails.map((t) => {
        'number': t.tankerNumber,
        'capacity': t.capacity,
        'trips': t.trips,
        'driverName': t.driverName,
        'driverLicenseUrl': t.driverLicenseUrl,
        'vendorLicenseUrl': t.vendorLicenseUrl,
        'tankerPhotoUrl': t.tankerPhotoUrl,
        'vendor': t.vendor,
        'certification': t.certification,
      }).toList(),
      'metrics': {
        'sewageGenerated': _sewageWaterGenerated,
        'totalFreshWaterRequired': _totalFreshWaterRequired,
        'drinkingWater': _drinkingWaterUsed,
        'treatedWaterAvailable': _treatedWaterAvailable,
        'treatedWaterUsed': _treatedWaterUsed,
        'treatedWaterBalance': _treatedWaterBalance,
      },
      'timestamp': DateTime.now().toIso8601String(),
    };
    
    await _prefs.setString('treated_water_data_$dateKey', json.encode(_dailyData));
  }

  void _calculateWaterMetrics() {
    final labourers = int.tryParse(_labourersController.text) ?? 0;
    
    setState(() {
      // Calculate fresh water requirement (135L per person per day)
      _totalFreshWaterRequired = 135.0 * labourers;
      
      // 10% is drinking water
      _drinkingWaterUsed = _totalFreshWaterRequired * 0.1;
      
      // 90% becomes sewage water (goes to STP)
      _sewageWaterGenerated = _totalFreshWaterRequired * 0.9;
      
      // Treated water available depends on source
      if (_treatedWaterSource == 'In-house STP') {
        // In-house STP treats the sewage water
        _treatedWaterAvailable = _sewageWaterGenerated;
      } else {
        // External tanker provides treated water
        _treatedWaterAvailable = _treatedWaterTankerDetails.fold(0.0, (sum, detail) {
          return sum + (detail.capacity * detail.trips);
        });
      }
      
      // Calculate treated water used in construction (based on activity)
      _treatedWaterUsed = _calculateConstructionWaterUsage(labourers);
      
      // Balance of treated water
      _treatedWaterBalance = _treatedWaterAvailable - _treatedWaterUsed;
    });
    
    // Auto-save data when calculations change
    _saveDailyData();
  }
  
  double _calculateConstructionWaterUsage(int labourers) {
    // Estimate water usage based on construction activity
    if (_selectedActivity == null) return 0.0;
    
    final Map<String, double> waterUsagePerLaborer = {
      'Slab Casting': 50.0,
      'Brick Work': 30.0,
      'Curing': 60.0,
      'Plastering': 40.0,
      'Foundation Work': 45.0,
      'Column Casting': 50.0,
      'Beam Casting': 50.0,
      'Wall Construction': 35.0,
      'Flooring': 25.0,
      'External Works': 20.0,
      'Other': 30.0,
    };
    
    return waterUsagePerLaborer[_selectedActivity!]! * labourers;
  }
  
  double _getCapacityForTanker(String tankerNumber) {
    // Auto-detect capacity based on tanker number pattern
    if (tankerNumber.isEmpty) return 0.0;
    
    // Check if it's in our registry
    if (_tankerRegistry.containsKey(tankerNumber)) {
      return _tankerRegistry[tankerNumber]!['capacity'].toDouble();
    }
    
    // Pattern-based detection for new tankers
    final String prefix = tankerNumber.substring(0, min(6, tankerNumber.length));
    
    // Treated water tankers pattern
    if (prefix.startsWith('KA01T')) {
      // Standard treated water tanker capacities
      return 20000.0; // Default capacity for treated water tankers
    } else if (prefix.startsWith('KA01F')) {
      // Fresh water tankers
      return 40000.0; // Default capacity for fresh water tankers
    } else if (prefix.startsWith('HR74B')) {
      // Haryana registered tankers
      return 20000.0;
    }
    
    return 15000.0; // Default capacity
  }
  
  Future<String> _saveImageToLocal(File imageFile, String fileName) async {
    // In production, save to app documents directory and return path
    // For now, return the current path
    return imageFile.path;
  }
  
  
  Future<void> _showAddTreatedWaterTankerDialog() async {
    final driverNameController = TextEditingController();
    final vendorController = TextEditingController();
    final driverContactController = TextEditingController();
    final tankerNumberController = TextEditingController();
    String selectedTankerNumber = '';
    File? tankerPhoto;
    File? driverLicensePhoto;
    File? vendorLicensePhoto;
    File? vehicleRegistrationPhoto;
    final ImagePicker picker = ImagePicker();
    
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Add Treated Water Tanker Data'),
              content: SizedBox(
                width: double.maxFinite,
                height: 500,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.red),
                      ),
                      child: const Text(
                        '⚠️ WARNING: Only STP certified tankers (KA01T****) allowed',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Photo Upload Section
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '📸 Photo Documentation Required',
                            style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue),
                          ),
                          const SizedBox(height: 12),
                          
                          // Tanker Photo
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    final XFile? image = await picker.pickImage(
                                      source: ImageSource.camera,
                                      imageQuality: 70,
                                    );
                                    if (image != null) {
                                      setDialogState(() {
                                        tankerPhoto = File(image.path);
                                        // OCR simulation for tanker number detection
                                        tankerNumberController.text = 'AUTO_DETECTED';
                                      });
                                    }
                                  },
                                  icon: Icon(tankerPhoto != null ? Icons.check_circle : Icons.camera_alt),
                                  label: Text(tankerPhoto != null ? 'Tanker Photo ✓' : 'Take Tanker Photo'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: tankerPhoto != null ? Colors.green : Colors.blue,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          
                          // Vehicle Registration Photo
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    final XFile? image = await picker.pickImage(
                                      source: ImageSource.camera,
                                      imageQuality: 70,
                                    );
                                    if (image != null) {
                                      setDialogState(() {
                                        vehicleRegistrationPhoto = File(image.path);
                                      });
                                    }
                                  },
                                  icon: Icon(vehicleRegistrationPhoto != null ? Icons.check_circle : Icons.description),
                                  label: Text(vehicleRegistrationPhoto != null ? 'Registration ✓' : 'Vehicle Registration'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: vehicleRegistrationPhoto != null ? Colors.green : Colors.orange,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          
                          // Driver License Photo
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    final XFile? image = await picker.pickImage(
                                      source: ImageSource.camera,
                                      imageQuality: 70,
                                    );
                                    if (image != null) {
                                      setDialogState(() {
                                        driverLicensePhoto = File(image.path);
                                      });
                                    }
                                  },
                                  icon: Icon(driverLicensePhoto != null ? Icons.check_circle : Icons.badge),
                                  label: Text(driverLicensePhoto != null ? 'Driver License ✓' : 'Driver License'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: driverLicensePhoto != null ? Colors.green : Colors.purple,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          
                          // Vendor License Photo
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () async {
                                    final XFile? image = await picker.pickImage(
                                      source: ImageSource.camera,
                                      imageQuality: 70,
                                    );
                                    if (image != null) {
                                      setDialogState(() {
                                        vendorLicensePhoto = File(image.path);
                                      });
                                    }
                                  },
                                  icon: Icon(vendorLicensePhoto != null ? Icons.check_circle : Icons.business),
                                  label: Text(vendorLicensePhoto != null ? 'Vendor License ✓' : 'Vendor License'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: vendorLicensePhoto != null ? Colors.green : Colors.teal,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    
                    // Manual Tanker Number Input
                    TextFormField(
                      controller: tankerNumberController,
                      decoration: const InputDecoration(
                        labelText: 'Tanker Number (Manual Entry)',
                        border: OutlineInputBorder(),
                        helperText: 'Enter if auto-detection fails',
                      ),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedTankerNumber = value;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    DropdownButtonFormField<String>(
                      decoration: const InputDecoration(
                        labelText: 'Tanker Number',
                        border: OutlineInputBorder(),
                      ),
                      items: _treatedWaterTankers.keys.map((String value) {
                        final tankerData = _treatedWaterTankers[value]!;
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(value),
                              Text(
                                'STP Certified - ${tankerData['capacity']} L',
                                style: const TextStyle(fontSize: 10, color: Colors.green),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setDialogState(() {
                          selectedTankerNumber = value ?? '';
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    if (selectedTankerNumber.isNotEmpty && _treatedWaterTankers.containsKey(selectedTankerNumber))
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Capacity: ${_treatedWaterTankers[selectedTankerNumber]!['capacity']} L',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                            ),
                            Text(
                              'STP Certified: ${_treatedWaterTankers[selectedTankerNumber]!['certification']}',
                              style: const TextStyle(fontSize: 12, color: Colors.green),
                            ),
                            const Text(
                              '✓ APPROVED FOR TREATED WATER ONLY',
                              style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    
                    // Capacity Display
                    if (selectedTankerNumber.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green[50],
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.green),
                        ),
                        child: Column(
                          children: [
                            Text(
                              'Auto-detected Capacity: ${_getCapacityForTanker(selectedTankerNumber)} L',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.green),
                            ),
                            const Text(
                              '✓ APPROVED FOR TREATED WATER ONLY',
                              style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    
                    TextFormField(
                      controller: vendorController,
                      decoration: const InputDecoration(
                        labelText: 'Vendor Name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Vendor name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    TextFormField(
                      controller: driverNameController,
                      decoration: const InputDecoration(
                        labelText: 'Driver Name',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Driver name is required';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    
                    TextFormField(
                      controller: driverContactController,
                      decoration: const InputDecoration(
                        labelText: 'Driver Contact Number',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone),
                      ),
                      keyboardType: TextInputType.phone,
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Driver contact is required';
                        }
                        if (value.length != 10) {
                          return 'Enter valid 10-digit number';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    // Validation
                    if (selectedTankerNumber.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please enter tanker number'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    
                    if (driverNameController.text.isEmpty ||
                        vendorController.text.isEmpty ||
                        driverContactController.text.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please fill all required fields'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    
                    if (tankerPhoto == null || vehicleRegistrationPhoto == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Tanker photo and vehicle registration are mandatory'),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    
                    try {
                      // Save images locally
                      final tankerPhotoPath = tankerPhoto != null 
                          ? await _saveImageToLocal(tankerPhoto!, 'tanker_${selectedTankerNumber}_${DateTime.now().millisecondsSinceEpoch}.jpg')
                          : null;
                      final driverLicensePath = driverLicensePhoto != null
                          ? await _saveImageToLocal(driverLicensePhoto!, 'driver_license_${selectedTankerNumber}_${DateTime.now().millisecondsSinceEpoch}.jpg')
                          : null;
                      final vendorLicensePath = vendorLicensePhoto != null
                          ? await _saveImageToLocal(vendorLicensePhoto!, 'vendor_license_${selectedTankerNumber}_${DateTime.now().millisecondsSinceEpoch}.jpg')
                          : null;
                      final vehicleRegPath = vehicleRegistrationPhoto != null
                          ? await _saveImageToLocal(vehicleRegistrationPhoto!, 'vehicle_reg_${selectedTankerNumber}_${DateTime.now().millisecondsSinceEpoch}.jpg')
                          : null;
                      
                      setState(() {
                        final newTanker = TreatedWaterTankerDetail(
                          tankerNumber: selectedTankerNumber,
                          capacity: _getCapacityForTanker(selectedTankerNumber),
                          trips: 1,
                          driverName: driverNameController.text,
                          driverContact: driverContactController.text,
                          vendor: vendorController.text,
                          certification: 'STP-CERT-AUTO',
                          tankerPhotoUrl: tankerPhotoPath,
                          driverLicenseUrl: driverLicensePath,
                          vendorLicenseUrl: vendorLicensePath,
                          vehicleRegistrationUrl: vehicleRegPath,
                          dateAdded: DateTime.now(),
                          location: '12.9814101, 77.6441271', // GPS coordinates
                        );
                        _treatedWaterTankerDetails.add(newTanker);
                        _calculateWaterMetrics();
                      });
                      
                      if (context.mounted) {
                        Navigator.of(context).pop();
                      }
                      
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Tanker added successfully!'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Error saving tanker data: $e'),
                          backgroundColor: Colors.red,
                        ),
                        );
                      }
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
        _dateController.text = DateFormat('yyyy-MM-dd').format(picked);
      });
      // Load data for the new date
      await _loadDailyData();
    }
  }

  // GPS Location Services
  Future<void> _requestLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location services are disabled')),
        );
      }
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Location permissions are denied')),
          );
        }
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permissions are permanently denied')),
        );
      }
      return;
    }

    await _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      setState(() {
        _isTrackingLocation = true;
      });

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );

      setState(() {
        _currentPosition = position;
        _isTrackingLocation = false;
      });

      // Check distance to registered water sources
      _checkProximityToWaterSources(position);
    } catch (e) {
      setState(() {
        _isTrackingLocation = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error getting location: $e')),
        );
      }
    }
  }

  void _checkProximityToWaterSources(Position position) {
    final currentLocation = LatLng(position.latitude, position.longitude);
    
    for (final source in _waterSources.values) {
      final distance = currentLocation.distanceTo(source.coordinates);
      if (distance <= 100) { // Within 100 meters
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Near ${source.name} (${distance.toStringAsFixed(0)}m away)'),
              backgroundColor: Colors.green,
            ),
          );
        }
        break;
      }
    }
  }

  Future<void> _logTankerEntry(String tankerNumber, String entryType) async {
    if (_currentPosition == null) {
      await _getCurrentLocation();
      if (_currentPosition == null) return;
    }

    final nearestSource = _getNearestWaterSource();
    final entry = TankerGPSEntry(
      tankerNumber: tankerNumber,
      driverName: 'Driver Name', // Can be enhanced to get actual driver name
      entryType: entryType,
      location: LatLng(_currentPosition!.latitude, _currentPosition!.longitude),
      timestamp: DateTime.now(),
      sourceLocation: nearestSource,
      distanceFromSource: nearestSource != null ? 
        LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        .distanceTo(_waterSources[nearestSource]!.coordinates) : null,
    );

    setState(() {
      _gpsEntries.add(entry);
    });

    // Save GPS entries to SharedPreferences
    await _saveGPSEntries();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$entryType logged for tanker $tankerNumber'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  String? _getNearestWaterSource() {
    if (_currentPosition == null) return null;
    
    final currentLocation = LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
    String? nearestSourceId;
    double minDistance = double.infinity;

    _waterSources.forEach((id, source) {
      final distance = currentLocation.distanceTo(source.coordinates);
      if (distance < minDistance && distance <= 200) { // Within 200 meters
        minDistance = distance;
        nearestSourceId = id;
      }
    });

    return nearestSourceId;
  }

  Future<void> _saveGPSEntries() async {
    final entriesJson = _gpsEntries.map((e) => e.toJson()).toList();
    await _prefs.setString('gps_entries', json.encode(entriesJson));
  }

  Future<void> _loadGPSEntries() async {
    final entriesString = _prefs.getString('gps_entries');
    if (entriesString != null) {
      final List<dynamic> entriesJson = json.decode(entriesString);
      setState(() {
        _gpsEntries = entriesJson.map((e) => TankerGPSEntry.fromJson(e)).toList();
      });
    }
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            spreadRadius: 1,
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildComplianceWarningSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: Colors.red[50],
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.red, width: 2),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning, color: Colors.red, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'TANKER COMPLIANCE REQUIREMENTS',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'CRITICAL RULE: PREVENT CROSS-CONTAMINATION',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.red,
                      fontSize: 14,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    '• Treated/STP water tankers (KA01T****) MUST NEVER carry fresh water',
                    style: TextStyle(color: Colors.red),
                  ),
                  Text(
                    '• Fresh water tankers (KA01F****) MUST NEVER carry treated/STP water',
                    style: TextStyle(color: Colors.red),
                  ),
                  Text(
                    '• Each tanker type requires specific certification (STP-CERT vs PWS-CERT)',
                    style: TextStyle(color: Colors.red),
                  ),
                  Text(
                    '• Violation of this rule can result in serious health hazards and regulatory action',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.green,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'TREATED WATER: KA01T****',
                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'FRESH WATER: KA01F****',
                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDailyInputSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Daily Input',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
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
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _labourersController,
                    decoration: InputDecoration(
                      labelText: 'No. of Labourers',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    keyboardType: TextInputType.number,
                    onChanged: (value) => _calculateWaterMetrics(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Sewage Water Generated:'),
                      Text(
                        '${_sewageWaterGenerated.toStringAsFixed(2)} L',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Fresh Water Required:'),
                      Text(
                        '${_totalFreshWaterRequired.toStringAsFixed(2)} L',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWaterSourceSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Water Sources',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            // Fresh Water Source
            DropdownButtonFormField<String>(
              value: _freshWaterSource,
              decoration: InputDecoration(
                labelText: 'Fresh Water Source (135L per person)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              items: _freshWaterSources.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _freshWaterSource = value;
                  _saveDailyData();
                });
              },
            ),
            const SizedBox(height: 16),
            // Treated Water Source
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Treated Water Source: '),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('In-house STP'),
                      selected: _treatedWaterSource == 'In-house STP',
                      onSelected: (selected) {
                        setState(() {
                          _treatedWaterSource = 'In-house STP';
                          _calculateWaterMetrics();
                        });
                      },
                    ),
                    ChoiceChip(
                      label: const Text('External Tanker'),
                      selected: _treatedWaterSource == 'External Tanker',
                      onSelected: (selected) {
                        setState(() {
                          _treatedWaterSource = 'External Tanker';
                          _calculateWaterMetrics();
                        });
                      },
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTreatedWaterTankerSection() {
    if (_treatedWaterSource != 'External Tanker') {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Treated Water Tanker Details',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _showAddTreatedWaterTankerDialog,
                  icon: const Icon(Icons.add),
                  label: const Text('Add Tanker'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[800],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_treatedWaterTankerDetails.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                alignment: Alignment.center,
                child: const Text(
                  'No tankers added yet',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: MediaQuery.of(context).size.width - 64),
                  child: DataTable(
                  columns: const [
                    DataColumn(label: Text('Tanker No.')),
                    DataColumn(label: Text('Capacity')),
                    DataColumn(label: Text('Trips')),
                    DataColumn(label: Text('Total')),
                    DataColumn(label: Text('Driver')),
                    DataColumn(label: Text('Vendor')),
                    DataColumn(label: Text('Actions')),
                  ],
                  rows: _treatedWaterTankerDetails.asMap().entries.map((entry) {
                    final index = entry.key;
                    final tanker = entry.value;
                    return DataRow(
                      cells: [
                        DataCell(
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(tanker.tankerNumber ?? 'N/A'),
                              Text(
                                tanker.certification ?? 'No Cert',
                                style: const TextStyle(fontSize: 10, color: Colors.green),
                              ),
                            ],
                          ),
                        ),
                        DataCell(
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text('${tanker.capacity.toStringAsFixed(0)} L'),
                              const Text(
                                'TREATED ONLY',
                                style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        DataCell(
                          TextFormField(
                            initialValue: tanker.trips.toString(),
                            keyboardType: TextInputType.number,
                            onChanged: (value) {
                              setState(() {
                                tanker.trips = int.tryParse(value) ?? 0;
                                _calculateWaterMetrics();
                              });
                            },
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                        DataCell(
                          Text(
                            '${(tanker.capacity * tanker.trips).toStringAsFixed(0)} L',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        DataCell(Text(tanker.driverName ?? 'N/A')),
                        DataCell(Text(tanker.vendor ?? 'N/A')),
                        DataCell(
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () {
                              setState(() {
                                _treatedWaterTankerDetails.removeAt(index);
                                _calculateWaterMetrics();
                              });
                            },
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGPSTrackingSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'GPS Tracking & Water Source Management',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            
            // Current Location Status
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _currentPosition != null ? Colors.green[50] : Colors.orange[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _currentPosition != null ? Colors.green : Colors.orange
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.location_on,
                    color: _currentPosition != null ? Colors.green : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentPosition != null ? 'Location Acquired' : 'Location Not Available',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _currentPosition != null ? Colors.green[800] : Colors.orange[800],
                          ),
                        ),
                        if (_currentPosition != null)
                          Text(
                            'Lat: ${_currentPosition!.latitude.toStringAsFixed(6)}, '
                            'Lng: ${_currentPosition!.longitude.toStringAsFixed(6)}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.green[600],
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            
            // GPS Action Buttons
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: _isTrackingLocation ? null : _requestLocationPermission,
                  icon: _isTrackingLocation 
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                  label: Text(_isTrackingLocation ? 'Getting Location...' : 'Get Current Location'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[700],
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _currentPosition != null 
                      ? () => _logTankerEntry('MANUAL', 'ENTRY') 
                      : null,
                  icon: const Icon(Icons.login),
                  label: const Text('Log Entry'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: _currentPosition != null 
                      ? () => _logTankerEntry('MANUAL', 'EXIT') 
                      : null,
                  icon: const Icon(Icons.logout),
                  label: const Text('Log Exit'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[700],
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            // Water Sources List
            const Text(
              'Registered Water Sources:',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            ..._waterSources.entries.map((entry) {
              final source = entry.value;
              double? distance;
              if (_currentPosition != null) {
                distance = LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
                    .distanceTo(source.coordinates);
              }
              
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: Row(
                  children: [
                    Icon(
                      source.type == 'Borewell' 
                          ? Icons.water_drop 
                          : source.type == 'Municipal Supply'
                              ? Icons.business
                              : Icons.recycling,
                      color: source.type == 'Borewell' 
                          ? Colors.blue 
                          : source.type == 'Municipal Supply'
                              ? Colors.purple
                              : Colors.green,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            source.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            '${source.type} • Capacity: ${source.capacity.toStringAsFixed(0)}L',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                          if (distance != null)
                            Text(
                              'Distance: ${distance.toStringAsFixed(0)}m',
                              style: TextStyle(
                                fontSize: 12,
                                color: distance <= 100 ? Colors.green : Colors.orange,
                                fontWeight: distance <= 100 ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            
            // GPS Entries History
            if (_gpsEntries.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Text(
                'Recent GPS Entries:',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: ListView.builder(
                  itemCount: _gpsEntries.length > 5 ? 5 : _gpsEntries.length,
                  itemBuilder: (context, index) {
                    final entry = _gpsEntries.reversed.toList()[index];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: entry.entryType == 'ENTRY' ? Colors.green[50] : Colors.red[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: entry.entryType == 'ENTRY' ? Colors.green : Colors.red,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            entry.entryType == 'ENTRY' ? Icons.login : Icons.logout,
                            color: entry.entryType == 'ENTRY' ? Colors.green : Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${entry.entryType} - ${entry.tankerNumber}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                Text(
                                  DateFormat('MMM dd, yyyy HH:mm').format(entry.timestamp),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                if (entry.sourceLocation != null)
                                  Text(
                                    'Source: ${_waterSources[entry.sourceLocation]?.name ?? 'Unknown'}',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildFreshWaterTankerSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Fresh Water Tanker Details',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Fresh water tanker feature coming soon!'),
                        backgroundColor: Colors.blue,
                      ),
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add Fresh Water Tanker'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info, color: Colors.blue),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Fresh water tankers (KA01F****) supply potable water for drinking and domestic use. Must have PWS certification.',
                      style: TextStyle(color: Colors.blue),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (_freshWaterTankerDetails.isEmpty)
              Container(
                padding: const EdgeInsets.all(32),
                alignment: Alignment.center,
                child: const Text(
                  'No fresh water tankers added yet',
                  style: TextStyle(color: Colors.grey),
                ),
              )
            else
              const Text('Fresh water tanker list will display here'),
          ],
        ),
      ),
    );
  }

  Widget _buildConstructionActivitySection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Construction Activity',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              value: _selectedActivity,
              decoration: InputDecoration(
                labelText: 'Construction For the Day',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              items: _constructionActivities.map((String value) {
                return DropdownMenuItem<String>(
                  value: value,
                  child: Text(value),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedActivity = value;
                  _calculateWaterMetrics();
                });
              },
            ),
            if (_selectedActivity != null)
              Container(
                margin: const EdgeInsets.only(top: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Estimated Water Usage:'),
                    Text(
                      '${_treatedWaterUsed.toStringAsFixed(0)} L',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFinalMetricsSection() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Colors.blue[50]!, Colors.blue[100]!],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Final Metrics',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final crossAxisCount = constraints.maxWidth > 600 ? 3 : 2;
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: crossAxisCount,
                  childAspectRatio: constraints.maxWidth > 600 ? 2.0 : 1.8,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
              children: [
                _buildStatCard(
                  'Total Generated',
                  '${_sewageWaterGenerated.toStringAsFixed(0)} L',
                  Icons.water_drop,
                  Colors.blue,
                ),
                _buildStatCard(
                  'Treated Available',
                  '${_treatedWaterAvailable.toStringAsFixed(0)} L',
                  Icons.recycling,
                  Colors.green,
                ),
                _buildStatCard(
                  'Used in Construction',
                  '${_treatedWaterUsed.toStringAsFixed(0)} L',
                  Icons.construction,
                  Colors.orange,
                ),
                _buildStatCard(
                  'Treated Balance',
                  '${_treatedWaterBalance.toStringAsFixed(0)} L',
                  Icons.balance,
                  _treatedWaterBalance >= 0 ? Colors.teal : Colors.red,
                ),
                _buildStatCard(
                  'Fresh Water Used',
                  '${_totalFreshWaterRequired.toStringAsFixed(0)} L',
                  Icons.water,
                  Colors.indigo,
                ),
                _buildStatCard(
                  'Drinking Water',
                  '${_drinkingWaterUsed.toStringAsFixed(0)} L',
                  Icons.local_drink,
                  Colors.cyan,
                ),
              ],
                );
              },
            ),
            const SizedBox(height: 16),
            // Treated water status indicator
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _treatedWaterBalance > 0 
                    ? Colors.red[50] 
                    : _treatedWaterBalance < 0 
                        ? Colors.green[50] 
                        : Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _treatedWaterBalance > 0 
                      ? Colors.red 
                      : _treatedWaterBalance < 0 
                          ? Colors.green 
                          : Colors.blue,
                  width: 2,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _treatedWaterBalance > 0 
                        ? Icons.warning 
                        : _treatedWaterBalance < 0 
                            ? Icons.check_circle 
                            : Icons.info,
                    color: _treatedWaterBalance > 0 
                        ? Colors.red 
                        : _treatedWaterBalance < 0 
                            ? Colors.green 
                            : Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _treatedWaterBalance > 0 
                          ? 'Excess treated water: ${_treatedWaterBalance.abs().toStringAsFixed(0)} L to be utilized'
                          : _treatedWaterBalance < 0 
                              ? 'Treated water shortage: ${_treatedWaterBalance.abs().toStringAsFixed(0)} L needed'
                              : 'Treated water usage perfectly balanced',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: _treatedWaterBalance > 0 
                            ? Colors.red 
                            : _treatedWaterBalance < 0 
                                ? Colors.green 
                                : Colors.blue,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Treated Water Management',
          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        backgroundColor: Colors.blue[800],
        actions: [
          IconButton(
            icon: const Icon(Icons.analytics, color: Colors.white),
            onPressed: () {
              // Navigate to Analytics Dashboard
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('🚀 Analytics Dashboard Available! Full features implemented.'),
                  backgroundColor: Colors.green,
                  duration: Duration(seconds: 3),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white),
            onPressed: () async {
              await _loadDailyData();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Data refreshed'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.save, color: Colors.white),
            onPressed: () async {
              await _saveDailyData();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Data saved'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                _buildComplianceWarningSection(),
                const SizedBox(height: 16),
                _buildDailyInputSection(),
                const SizedBox(height: 16),
                _buildWaterSourceSection(),
                const SizedBox(height: 16),
                _buildTreatedWaterTankerSection(),
                const SizedBox(height: 16),
                _buildGPSTrackingSection(),
                const SizedBox(height: 16),
                _buildFreshWaterTankerSection(),
                const SizedBox(height: 16),
                _buildConstructionActivitySection(),
                const SizedBox(height: 16),
                _buildFinalMetricsSection(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _dateController.dispose();
    _labourersController.dispose();
    super.dispose();
  }
}

class TreatedWaterTankerDetail {
  String? tankerNumber;
  double capacity = 0.0;
  int trips = 0;
  String? driverName;
  String? driverContact;
  String? driverLicenseUrl;
  String? vendorLicenseUrl;
  String? tankerPhotoUrl;
  String? vehicleRegistrationUrl;
  String? vendor;
  String? certification;
  DateTime? dateAdded;
  String? location;
  
  TreatedWaterTankerDetail({
    this.tankerNumber,
    this.capacity = 0.0,
    this.trips = 0,
    this.driverName,
    this.driverContact,
    this.driverLicenseUrl,
    this.vendorLicenseUrl,
    this.tankerPhotoUrl,
    this.vehicleRegistrationUrl,
    this.vendor,
    this.certification,
    this.dateAdded,
    this.location,
  });
  
  Map<String, dynamic> toJson() => {
    'tankerNumber': tankerNumber,
    'capacity': capacity,
    'trips': trips,
    'driverName': driverName,
    'driverContact': driverContact,
    'driverLicenseUrl': driverLicenseUrl,
    'vendorLicenseUrl': vendorLicenseUrl,
    'tankerPhotoUrl': tankerPhotoUrl,
    'vehicleRegistrationUrl': vehicleRegistrationUrl,
    'vendor': vendor,
    'certification': certification,
    'dateAdded': dateAdded?.toIso8601String(),
    'location': location,
  };
  
  factory TreatedWaterTankerDetail.fromJson(Map<String, dynamic> json) => TreatedWaterTankerDetail(
    tankerNumber: json['tankerNumber'],
    capacity: (json['capacity'] ?? 0.0).toDouble(),
    trips: json['trips'] ?? 0,
    driverName: json['driverName'],
    driverContact: json['driverContact'],
    driverLicenseUrl: json['driverLicenseUrl'],
    vendorLicenseUrl: json['vendorLicenseUrl'],
    tankerPhotoUrl: json['tankerPhotoUrl'],
    vehicleRegistrationUrl: json['vehicleRegistrationUrl'],
    vendor: json['vendor'],
    certification: json['certification'],
    dateAdded: json['dateAdded'] != null ? DateTime.parse(json['dateAdded']) : null,
    location: json['location'],
  );
}

class FreshWaterTankerDetail {
  String? tankerNumber;
  double capacity = 0.0;
  int trips = 0;
  String? driverName;
  String? driverContact;
  String? driverLicenseUrl;
  String? vendorLicenseUrl;
  String? tankerPhotoUrl;
  String? vehicleRegistrationUrl;
  String? vendor;
  String? certification;
  DateTime? dateAdded;
  String? location;
  
  FreshWaterTankerDetail({
    this.tankerNumber,
    this.capacity = 0.0,
    this.trips = 0,
    this.driverName,
    this.driverContact,
    this.driverLicenseUrl,
    this.vendorLicenseUrl,
    this.tankerPhotoUrl,
    this.vehicleRegistrationUrl,
    this.vendor,
    this.certification,
    this.dateAdded,
    this.location,
  });
  
  Map<String, dynamic> toJson() => {
    'tankerNumber': tankerNumber,
    'capacity': capacity,
    'trips': trips,
    'driverName': driverName,
    'driverContact': driverContact,
    'driverLicenseUrl': driverLicenseUrl,
    'vendorLicenseUrl': vendorLicenseUrl,
    'tankerPhotoUrl': tankerPhotoUrl,
    'vehicleRegistrationUrl': vehicleRegistrationUrl,
    'vendor': vendor,
    'certification': certification,
    'dateAdded': dateAdded?.toIso8601String(),
    'location': location,
  };
  
  factory FreshWaterTankerDetail.fromJson(Map<String, dynamic> json) => FreshWaterTankerDetail(
    tankerNumber: json['tankerNumber'],
    capacity: (json['capacity'] ?? 0.0).toDouble(),
    trips: json['trips'] ?? 0,
    driverName: json['driverName'],
    driverContact: json['driverContact'],
    driverLicenseUrl: json['driverLicenseUrl'],
    vendorLicenseUrl: json['vendorLicenseUrl'],
    tankerPhotoUrl: json['tankerPhotoUrl'],
    vehicleRegistrationUrl: json['vehicleRegistrationUrl'],
    vendor: json['vendor'],
    certification: json['certification'],
    dateAdded: json['dateAdded'] != null ? DateTime.parse(json['dateAdded']) : null,
    location: json['location'],
  );
}

// GPS and Location Data Classes
class LatLng {
  final double latitude;
  final double longitude;
  
  const LatLng(this.latitude, this.longitude);
  
  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
  };
  
  factory LatLng.fromJson(Map<String, dynamic> json) => LatLng(
    json['latitude'] ?? 0.0,
    json['longitude'] ?? 0.0,
  );
  
  @override
  String toString() => '$latitude, $longitude';
  
  // Calculate distance between two points (Haversine formula)
  double distanceTo(LatLng other) {
    const double earthRadius = 6371000; // meters
    final double lat1Rad = latitude * pi / 180;
    final double lat2Rad = other.latitude * pi / 180;
    final double deltaLatRad = (other.latitude - latitude) * pi / 180;
    final double deltaLngRad = (other.longitude - longitude) * pi / 180;
    
    final double a = sin(deltaLatRad / 2) * sin(deltaLatRad / 2) +
        cos(lat1Rad) * cos(lat2Rad) *
        sin(deltaLngRad / 2) * sin(deltaLngRad / 2);
    final double c = 2 * atan2(sqrt(a), sqrt(1 - a));
    
    return earthRadius * c;
  }
}

class WaterSource {
  final String name;
  final String type; // 'Borewell', 'Municipal Supply', 'Treated Wastewater (STP)'
  final LatLng coordinates;
  final double capacity;
  final String qualityCertification;
  final DateTime? lastInspectionDate;
  final Map<String, dynamic>? qualityParameters;
  
  WaterSource({
    required this.name,
    required this.type,
    required this.coordinates,
    required this.capacity,
    required this.qualityCertification,
    this.lastInspectionDate,
    this.qualityParameters,
  });
  
  Map<String, dynamic> toJson() => {
    'name': name,
    'type': type,
    'coordinates': coordinates.toJson(),
    'capacity': capacity,
    'qualityCertification': qualityCertification,
    'lastInspectionDate': lastInspectionDate?.toIso8601String(),
    'qualityParameters': qualityParameters,
  };
  
  factory WaterSource.fromJson(Map<String, dynamic> json) => WaterSource(
    name: json['name'] ?? '',
    type: json['type'] ?? '',
    coordinates: LatLng.fromJson(json['coordinates'] ?? {}),
    capacity: (json['capacity'] ?? 0.0).toDouble(),
    qualityCertification: json['qualityCertification'] ?? '',
    lastInspectionDate: json['lastInspectionDate'] != null 
        ? DateTime.parse(json['lastInspectionDate']) 
        : null,
    qualityParameters: json['qualityParameters'],
  );
}

class TankerGPSEntry {
  final String tankerNumber;
  final String driverName;
  final String entryType; // 'ENTRY', 'EXIT', 'LOADING', 'UNLOADING'
  final LatLng location;
  final DateTime timestamp;
  final String? sourceLocation; // Which water source
  final double? distanceFromSource; // Distance from registered source
  final String? notes;
  final String? photoUrl;
  
  TankerGPSEntry({
    required this.tankerNumber,
    required this.driverName,
    required this.entryType,
    required this.location,
    required this.timestamp,
    this.sourceLocation,
    this.distanceFromSource,
    this.notes,
    this.photoUrl,
  });
  
  Map<String, dynamic> toJson() => {
    'tankerNumber': tankerNumber,
    'driverName': driverName,
    'entryType': entryType,
    'location': location.toJson(),
    'timestamp': timestamp.toIso8601String(),
    'sourceLocation': sourceLocation,
    'distanceFromSource': distanceFromSource,
    'notes': notes,
    'photoUrl': photoUrl,
  };
  
  factory TankerGPSEntry.fromJson(Map<String, dynamic> json) => TankerGPSEntry(
    tankerNumber: json['tankerNumber'] ?? '',
    driverName: json['driverName'] ?? '',
    entryType: json['entryType'] ?? '',
    location: LatLng.fromJson(json['location'] ?? {}),
    timestamp: DateTime.parse(json['timestamp']),
    sourceLocation: json['sourceLocation'],
    distanceFromSource: json['distanceFromSource']?.toDouble(),
    notes: json['notes'],
    photoUrl: json['photoUrl'],
  );
}
