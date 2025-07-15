# Frontend-Backend Integration Guide

## Overview
This guide covers integrating the Flutter frontend with the approval_server.js backend for the Prestige Park Groove water management system.

## Backend Server Details
- **Base URL**: `http://54.146.215.18:3000`
- **Type**: Express.js server with PostgreSQL database
- **Authentication**: JWT tokens
- **File Uploads**: AWS S3 integration
- **Real-time**: WebSocket support

## Current Frontend Integration Status

### Existing API Integration
The Flutter app already has several API integrations:
- Authentication service (`lib/auth_service.dart`)
- Borewell data (`lib/Borewellpage.dart`)
- Air pollution monitoring (`lib/Air_poll_api.dart`)
- Stack monitoring (`lib/airpollution/stack.dart`)

### Base URL Configuration
Currently configured in multiple places:
```dart
// auth_service.dart
static const String baseUrl = 'http://54.146.215.18:3000';

// main.dart
const String baseUrl = 'http://54.146.215.18:3000';
```

**Server URL:** `http://54.146.215.18:3000`

## 🔐 Authentication System

### Session Management Endpoints

#### 1. Token Verification
```dart
// GET /verify-token
Future<bool> verifyToken(String token) async {
  final response = await http.get(
    Uri.parse('$baseUrl/verify-token'),
    headers: {
      'Authorization': 'Bearer $token',
      'Content-Type': 'application/json',
    },
  );
  
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return data['valid'] == true;
  }
  return false;
}
```

#### 2. Token Refresh
```dart
// POST /refresh-token
Future<Map<String, String>?> refreshToken(String refreshToken) async {
  final response = await http.post(
    Uri.parse('$baseUrl/refresh-token'),
    headers: {
      'Authorization': 'Bearer $refreshToken',
      'Content-Type': 'application/json',
    },
  );
  
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return {
      'token': data['token'],
      'refreshToken': data['refreshToken'],
    };
  }
  return null;
}
```

## 🚛 Tanker Management API

### Required Headers for All Tanker Endpoints
```dart
Map<String, String> get authHeaders => {
  'Authorization': 'Bearer $authToken',
  'Content-Type': 'application/json',
};
```

#### 1. Get All Tankers
```dart
// GET /api/tankers
Future<List<Tanker>> getTankers({DateTime? date}) async {
  String url = '$baseUrl/api/tankers';
  if (date != null) {
    url += '?date=${DateFormat('yyyy-MM-dd').format(date)}';
  }
  
  final response = await http.get(
    Uri.parse(url),
    headers: authHeaders,
  );
  
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return (data['data'] as List)
        .map((json) => Tanker.fromJson(json))
        .toList();
  }
  throw Exception('Failed to load tankers');
}
```

#### 2. Get Tanker by Plate Number
```dart
// GET /api/tankers/:plateNumber
Future<Tanker> getTankerByPlate(String plateNumber) async {
  final response = await http.get(
    Uri.parse('$baseUrl/api/tankers/$plateNumber'),
    headers: authHeaders,
  );
  
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return Tanker.fromJson(data['data']);
  }
  throw Exception('Tanker not found');
}
```

#### 3. Upload Tanker Image
```dart
// POST /api/tankers/images
Future<String> uploadTankerImage(File imageFile, String plateNumber) async {
  final request = http.MultipartRequest(
    'POST',
    Uri.parse('$baseUrl/api/tankers/images'),
  );
  
  request.headers['Authorization'] = 'Bearer $authToken';
  request.files.add(
    await http.MultipartFile.fromPath('image', imageFile.path),
  );
  request.fields['plateNumber'] = plateNumber;
  
  final streamedResponse = await request.send();
  final response = await http.Response.fromStream(streamedResponse);
  
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return data['imageUrl'];
  }
  throw Exception('Failed to upload image');
}
```

#### 4. Update Tanker
```dart
// PUT /api/tankers/:plateNumber
Future<void> updateTanker(Tanker tanker) async {
  final response = await http.put(
    Uri.parse('$baseUrl/api/tankers/${tanker.plateNumber}'),
    headers: authHeaders,
    body: json.encode(tanker.toJson()),
  );
  
  if (response.statusCode != 200) {
    throw Exception('Failed to update tanker');
  }
}
```

## 💧 Water Consumption Dashboard

#### Get Dashboard Data
```dart
// GET /water-consumption/dashboard
Future<Map<String, dynamic>> getWaterConsumptionDashboard({int days = 7}) async {
  final response = await http.get(
    Uri.parse('$baseUrl/water-consumption/dashboard?days=$days'),
    headers: {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    },
  );
  
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    if (data['success'] == true) {
      return data['data'];
    }
  }
  throw Exception('Failed to fetch dashboard data');
}
```

## 🏢 BWSSB Management

**Note:** Backend endpoints use `/bwssb/*` paths, but your frontend may expect `/bwssb-entries/*`. Update accordingly.

#### 1. Get BWSSB Entries
```dart
// GET /bwssb (adjust path if needed)
Future<List<Map<String, dynamic>>> getBWSSBEntries() async {
  final response = await http.get(
    Uri.parse('$baseUrl/bwssb'),
    headers: {'Content-Type': 'application/json'},
  );
  
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return List<Map<String, dynamic>>.from(data['data'] ?? []);
  }
  throw Exception('Failed to load BWSSB entries');
}
```

#### 2. Get BWSSB Statistics
```dart
// GET /bwssb/stats
Future<Map<String, dynamic>> getBWSSBStats({int days = 30}) async {
  final response = await http.get(
    Uri.parse('$baseUrl/bwssb/stats?days=$days'),
    headers: {'Content-Type': 'application/json'},
  );
  
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    if (data['success'] == true) {
      return data['data'];
    }
  }
  throw Exception('Failed to fetch BWSSB stats');
}
```

#### 3. Get Gates and Vehicles
```dart
// GET /bwssb/gates
Future<List<Map<String, dynamic>>> getBWSSBGates() async {
  final response = await http.get(
    Uri.parse('$baseUrl/bwssb/gates'),
    headers: {'Content-Type': 'application/json'},
  );
  
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return List<Map<String, dynamic>>.from(data['data'] ?? []);
  }
  return [];
}

// GET /bwssb/vehicles  
Future<List<Map<String, dynamic>>> getBWSSBVehicles() async {
  final response = await http.get(
    Uri.parse('$baseUrl/bwssb/vehicles'),
    headers: {'Content-Type': 'application/json'},
  );
  
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    return List<Map<String, dynamic>>.from(data['data'] ?? []);
  }
  return [];
}
```

## 🗑️ Waste Management

### Municipal Solid Waste

#### 1. Get Municipal Solid Waste Records
```dart
// GET /municipal-solid-waste
Future<List<MunicipalWasteRecord>> getMunicipalSolidWaste({int limit = 50}) async {
  final response = await http.get(
    Uri.parse('$baseUrl/municipal-solid-waste?limit=$limit'),
    headers: {'Content-Type': 'application/json'},
  );
  
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    if (data['success'] == true) {
      return (data['data'] as List)
          .map((json) => MunicipalWasteRecord.fromJson(json))
          .toList();
    }
  }
  throw Exception('Failed to load waste records');
}
```

#### 2. Create Municipal Solid Waste Record
```dart
// POST /municipal-solid-waste
Future<int> createMunicipalSolidWaste(Map<String, dynamic> wasteData) async {
  final response = await http.post(
    Uri.parse('$baseUrl/municipal-solid-waste'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode(wasteData),
  );
  
  if (response.statusCode == 201) {
    final data = json.decode(response.body);
    if (data['success'] == true) {
      return data['data']['id'];
    }
  }
  throw Exception('Failed to create waste record');
}
```

#### 3. Get Municipal Solid Waste Statistics
```dart
// GET /municipal-solid-waste/stats
Future<Map<String, dynamic>> getMunicipalSolidWasteStats() async {
  final response = await http.get(
    Uri.parse('$baseUrl/municipal-solid-waste/stats'),
    headers: {'Content-Type': 'application/json'},
  );
  
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    if (data['success'] == true) {
      return data['summary'];
    }
  }
  throw Exception('Failed to fetch waste statistics');
}
```

#### 4. Delete Municipal Solid Waste Record
```dart
// DELETE /municipal-solid-waste/:id
Future<void> deleteMunicipalSolidWaste(int id) async {
  final response = await http.delete(
    Uri.parse('$baseUrl/municipal-solid-waste/$id'),
    headers: {'Content-Type': 'application/json'},
  );
  
  if (response.statusCode != 200) {
    throw Exception('Failed to delete waste record');
  }
}
```

### Construction Phase Waste

#### 1. Get Construction Phase Waste Records
```dart
// GET /construction-phase-waste
Future<List<ConstructionPhaseWasteRecord>> getConstructionPhaseWaste({int limit = 50}) async {
  final response = await http.get(
    Uri.parse('$baseUrl/construction-phase-waste?limit=$limit'),
    headers: {'Content-Type': 'application/json'},
  );
  
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    if (data['success'] == true) {
      return (data['data'] as List)
          .map((json) => ConstructionPhaseWasteRecord.fromJson(json))
          .toList();
    }
  }
  throw Exception('Failed to load construction waste records');
}
```

#### 2. Create Construction Phase Waste Record
```dart
// POST /construction-phase-waste
Future<int> createConstructionPhaseWaste(Map<String, dynamic> wasteData) async {
  final response = await http.post(
    Uri.parse('$baseUrl/construction-phase-waste'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode(wasteData),
  );
  
  if (response.statusCode == 201) {
    final data = json.decode(response.body);
    if (data['success'] == true) {
      return data['data']['id'];
    }
  }
  throw Exception('Failed to create construction waste record');
}
```

#### 3. Get Construction Phase Waste Statistics
```dart
// GET /construction-phase-waste/stats
Future<Map<String, dynamic>> getConstructionPhaseWasteStats() async {
  final response = await http.get(
    Uri.parse('$baseUrl/construction-phase-waste/stats'),
    headers: {'Content-Type': 'application/json'},
  );
  
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    if (data['success'] == true) {
      return data['summary'];
    }
  }
  throw Exception('Failed to fetch construction waste statistics');
}
```

## 🌬️ Air Pollution Monitoring

### Stack Monitoring Enhanced

#### 1. Get Stack Monitoring Data
```dart
// GET /stack-monitoring-enhanced
Future<List<StackMonitoringData>> getStackMonitoringData() async {
  final response = await http.get(
    Uri.parse('$baseUrl/stack-monitoring-enhanced'),
    headers: {'Content-Type': 'application/json'},
  );
  
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    if (data['success'] == true) {
      return (data['data'] as List)
          .map((json) => StackMonitoringData.fromJson(json))
          .toList();
    }
  }
  throw Exception('Failed to load stack monitoring data');
}
```

#### 2. Create Stack Monitoring Record
```dart
// POST /stack-monitoring-enhanced
Future<Map<String, dynamic>> createStackMonitoringRecord(Map<String, dynamic> recordData) async {
  final response = await http.post(
    Uri.parse('$baseUrl/stack-monitoring-enhanced'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode(recordData),
  );
  
  if (response.statusCode == 201) {
    final data = json.decode(response.body);
    if (data['success'] == true) {
      return data['data'];
    }
  }
  throw Exception('Failed to create stack monitoring record');
}
```

#### 3. Update Stack Monitoring Record
```dart
// PUT /stack-monitoring-enhanced/:id
Future<void> updateStackMonitoringRecord(String id, Map<String, dynamic> recordData) async {
  final response = await http.put(
    Uri.parse('$baseUrl/stack-monitoring-enhanced/$id'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode(recordData),
  );
  
  if (response.statusCode != 200) {
    throw Exception('Failed to update stack monitoring record');
  }
}
```

#### 4. Delete Stack Monitoring Record
```dart
// DELETE /stack-monitoring-enhanced/:id
Future<void> deleteStackMonitoringRecord(String id) async {
  final response = await http.delete(
    Uri.parse('$baseUrl/stack-monitoring-enhanced/$id'),
    headers: {'Content-Type': 'application/json'},
  );
  
  if (response.statusCode != 200) {
    throw Exception('Failed to delete stack monitoring record');
  }
}
```

### Ambient Monitoring Enhanced

#### 1. Get Ambient Monitoring Data
```dart
// GET /ambient-monitoring-enhanced
Future<List<AmbientAirMonitoringData>> getAmbientMonitoringData() async {
  final response = await http.get(
    Uri.parse('$baseUrl/ambient-monitoring-enhanced'),
    headers: {'Content-Type': 'application/json'},
  );
  
  if (response.statusCode == 200) {
    final data = json.decode(response.body);
    if (data['success'] == true) {
      return (data['data'] as List)
          .map((json) => AmbientAirMonitoringData.fromJson(json))
          .toList();
    }
  }
  throw Exception('Failed to load ambient monitoring data');
}
```

#### 2. Create Ambient Monitoring Record
```dart
// POST /ambient-monitoring-enhanced
Future<Map<String, dynamic>> createAmbientMonitoringRecord(Map<String, dynamic> recordData) async {
  final response = await http.post(
    Uri.parse('$baseUrl/ambient-monitoring-enhanced'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode(recordData),
  );
  
  if (response.statusCode == 201) {
    final data = json.decode(response.body);
    if (data['success'] == true) {
      return data['data'];
    }
  }
  throw Exception('Failed to create ambient monitoring record');
}
```

#### 3. Update Ambient Monitoring Record
```dart
// PUT /ambient-monitoring-enhanced/:id
Future<void> updateAmbientMonitoringRecord(String id, Map<String, dynamic> recordData) async {
  final response = await http.put(
    Uri.parse('$baseUrl/ambient-monitoring-enhanced/$id'),
    headers: {'Content-Type': 'application/json'},
    body: json.encode(recordData),
  );
  
  if (response.statusCode != 200) {
    throw Exception('Failed to update ambient monitoring record');
  }
}
```

#### 4. Delete Ambient Monitoring Record
```dart
// DELETE /ambient-monitoring-enhanced/:id
Future<void> deleteAmbientMonitoringRecord(String id) async {
  final response = await http.delete(
    Uri.parse('$baseUrl/ambient-monitoring-enhanced/$id'),
    headers: {'Content-Type': 'application/json'},
  );
  
  if (response.statusCode != 200) {
    throw Exception('Failed to delete ambient monitoring record');
  }
}
```

## 📊 Data Models

### Updated Air Pollution Models

#### Stack Monitoring Data Model
```dart
class StackMonitoringData {
  final String? id;
  final String source;
  final String asPerConsent;
  final String provided;
  final String status;
  final DateTime timestamp;

  StackMonitoringData({
    this.id,
    required this.source,
    required this.asPerConsent,
    required this.provided,
    required this.status,
    required this.timestamp,
  });

  factory StackMonitoringData.fromJson(Map<String, dynamic> json) {
    return StackMonitoringData(
      id: json['id']?.toString(),
      source: json['source'] ?? '',
      asPerConsent: json['as_per_consent'] ?? '',
      provided: json['provided'] ?? '',
      status: json['status'] ?? '',
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'source': source,
      'as_per_consent': asPerConsent,
      'provided': provided,
      'status': status,
    };
  }
}
```

#### Ambient Air Monitoring Data Model
```dart
class AmbientAirMonitoringData {
  final String id;
  final String location;
  final String parameter;
  final String limitValue;
  final String measured;
  final String status;
  final DateTime timestamp;

  AmbientAirMonitoringData({
    required this.id,
    required this.location,
    required this.parameter,
    required this.limitValue,
    required this.measured,
    required this.status,
    required this.timestamp,
  });

  factory AmbientAirMonitoringData.fromJson(Map<String, dynamic> json) {
    return AmbientAirMonitoringData(
      id: json['id'].toString(),
      location: json['location'] ?? '',
      parameter: json['parameter'] ?? '',
      limitValue: json['limit_value'] ?? '',
      measured: json['measured'] ?? '',
      status: json['status'] ?? '',
      timestamp: DateTime.parse(json['timestamp']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'location': location,
      'parameter': parameter,
      'limit_value': limitValue,
      'measured': measured,
      'status': status,
    };
  }
}
```

## 🔧 Error Handling

### Common Error Handler
```dart
void handleApiError(http.Response response) {
  final data = json.decode(response.body);
  final errorMessage = data['error'] ?? data['message'] ?? 'Unknown error';
  
  switch (response.statusCode) {
    case 400:
      throw Exception('Bad Request: $errorMessage');
    case 401:
      throw Exception('Unauthorized: Please login again');
    case 403:
      throw Exception('Forbidden: Insufficient permissions');
    case 404:
      throw Exception('Not Found: $errorMessage');
    case 500:
      throw Exception('Server Error: $errorMessage');
    default:
      throw Exception('Error ${response.statusCode}: $errorMessage');
  }
}
```

## 📝 Usage Examples

### Complete Service Integration Example
```dart
class ApiService {
  static const String baseUrl = 'http://54.146.215.18:3000';
  String? _authToken;

  void setAuthToken(String token) {
    _authToken = token;
  }

  Map<String, String> get _headers {
    final headers = {'Content-Type': 'application/json'};
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  // Example: Complete waste management workflow
  Future<void> manageWaste() async {
    try {
      // 1. Get current waste records
      final records = await getMunicipalSolidWaste();
      
      // 2. Create new waste record
      final wasteData = {
        'date': DateFormat('yyyy-MM-dd').format(DateTime.now()),
        'no_of_houses_occupied': 150,
        'dry_generated_quantity': 50.5,
        'wet_generated_quantity': 30.2,
      };
      final newId = await createMunicipalSolidWaste(wasteData);
      
      // 3. Get updated statistics
      final stats = await getMunicipalSolidWasteStats();
      
      print('Created record ID: $newId');
      print('Total waste generated: ${stats['total_waste_generated']}');
      
    } catch (e) {
      print('Error managing waste: $e');
    }
  }
}
```

## 🎯 Next Steps

1. **Update your existing API service** with these endpoint methods
2. **Update data models** to match the corrected schemas
3. **Test each integration** with the running backend server
4. **Handle authentication** properly with token management
5. **Add proper error handling** for all API calls
6. **Update UI components** to use the new service methods

## 🚨 Important Notes

- **Authentication Required**: Tanker endpoints require Bearer token
- **Path Mismatches**: BWSSB endpoints use `/bwssb/*` not `/bwssb-entries/*`
- **Schema Changes**: Air pollution models need schema updates
- **Error Handling**: Always implement proper error handling
- **Token Management**: Implement token refresh for expired tokens

All endpoints are now fully functional and ready for frontend integration! 🎉