import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';

// Model classes for API response
class AirQualityData {
  final double pm25;
  final double pm10;
  final double so2;
  final int overallAqi;
  final String location;

  AirQualityData({
    required this.pm25,
    required this.pm10,
    required this.so2,
    required this.overallAqi,
    required this.location,
  });

  factory AirQualityData.fromJson(Map<String, dynamic> json) {
    final pollutants = json['currentConditions']['pollutants'] as List;
    
    double pm25Value = 0;
    double pm10Value = 0;
    double so2Value = 0;

    for (var pollutant in pollutants) {
      switch (pollutant['code']) {
        case 'pm25':
          pm25Value = pollutant['concentration']['value'].toDouble();
          break;
        case 'pm10':
          pm10Value = pollutant['concentration']['value'].toDouble();
          break;
        case 'so2':
          so2Value = pollutant['concentration']['value'].toDouble();
          break;
      }
    }

    return AirQualityData(
      pm25: pm25Value,
      pm10: pm10Value,
      so2: so2Value,
      overallAqi: json['currentConditions']['aqi'] ?? 0,
      location: json['location']['name'] ?? 'Unknown Location',
    );
  }
}

// Air Quality Service
class AirQualityService {
  static const String _apiKey = 'AIzaSyAXZVf--EUHLe3IfUe_G-8Z5YZoIFPT2l4';
  static const String _baseUrl = 'https://airquality.googleapis.com/v1/currentConditions:lookup';

  static Future<AirQualityData?> getAirQualityData({
    required double latitude,
    required double longitude,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl?key=$_apiKey'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'location': {
            'latitude': latitude,
            'longitude': longitude,
          },
          'extraComputations': [
            'POLLUTANT_CONCENTRATION'
          ],
          'languageCode': 'en'
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return AirQualityData.fromJson(data);
      } else {
        print('API Error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('Error fetching air quality data: $e');
      return null;
    }
  }

  static Future<Position?> getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return null;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return null;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return null;
      }

      return await Geolocator.getCurrentPosition();
    } catch (e) {
      print('Error getting location: $e');
      return null;
    }
  }
}

// Helper functions
class AirQualityHelper {
  static String getQualityComment(double value, String pollutant) {
    switch (pollutant.toLowerCase()) {
      case 'pm25':
        if (value <= 12) return 'Good';
        if (value <= 35) return 'Moderate';
        if (value <= 55) return 'Poor';
        return 'Critical';
      case 'pm10':
        if (value <= 20) return 'Good';
        if (value <= 50) return 'Moderate';
        if (value <= 100) return 'Poor';
        return 'Critical';
      case 'so2':
        if (value <= 40) return 'Good';
        if (value <= 80) return 'Moderate';
        if (value <= 380) return 'Poor';
        return 'Critical';
      default:
        return 'Unknown';
    }
  }

  static Color getQualityColor(String comment) {
    switch (comment.toLowerCase()) {
      case 'good':
        return Colors.green;
      case 'moderate':
        return Colors.yellow.shade700;
      case 'poor':
        return Colors.orange;
      case 'critical':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  static String getStandardValue(String pollutant) {
    switch (pollutant.toLowerCase()) {
      case 'pm25':
        return '25 µg/m³';
      case 'pm10':
        return '50 µg/m³';
      case 'so2':
        return '75 ppb';
      default:
        return 'N/A';
    }
  }
}

// Updated Widget with API integration
class AirQualityWidget extends StatefulWidget {
  @override
  _AirQualityWidgetState createState() => _AirQualityWidgetState();
}

class _AirQualityWidgetState extends State<AirQualityWidget> {
  AirQualityData? _airQualityData;
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadAirQualityData();
  }

  Future<void> _loadAirQualityData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Get current location
      Position? position = await AirQualityService.getCurrentLocation();
      
      if (position == null) {
        setState(() {
          _errorMessage = 'Unable to get location. Please enable location services.';
          _isLoading = false;
        });
        return;
      }

      // Fetch air quality data
      AirQualityData? data = await AirQualityService.getAirQualityData(
        latitude: position.latitude,
        longitude: position.longitude,
      );

      setState(() {
        _airQualityData = data;
        _isLoading = false;
        if (data == null) {
          _errorMessage = 'Failed to fetch air quality data.';
        }
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Error: $e';
        _isLoading = false;
      });
    }
  }

  Widget _buildCurrentStatus() {
    if (_isLoading) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              const Text(
                'Loading Air Quality Data...',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      );
    }

    if (_errorMessage.isNotEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Icon(Icons.error, color: Colors.red, size: 48),
              const SizedBox(height: 16),
              Text(
                _errorMessage,
                style: const TextStyle(color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadAirQualityData,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_airQualityData == null) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text('No data available'),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Current Ambient Air Quality',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadAirQualityData,
                ),
              ],
            ),
            Text(
              _airQualityData!.location,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            _buildAirQualityTable(),
          ],
        ),
      ),
    );
  }

  Widget _buildAirQualityTable() {
    final data = _airQualityData!;
    
    return Table(
      border: TableBorder.all(
        color: Colors.grey.shade300,
        width: 1,
      ),
      columnWidths: const {
        0: FlexColumnWidth(2),
        1: FlexColumnWidth(2),
        2: FlexColumnWidth(2),
        3: FlexColumnWidth(2),
      },
      children: [
        // Header row
        TableRow(
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
          ),
          children: const [
            TableCell(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Parameter',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            TableCell(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Standard',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            TableCell(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Result',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
            TableCell(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Text(
                  'Comment',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ),
          ],
        ),
        // PM2.5 row
        _buildTableRow('PM 2.5', data.pm25, 'µg/m³'),
        // PM10 row
        _buildTableRow('PM 10', data.pm10, 'µg/m³'),
        // SO2 row
        _buildTableRow('SO2', data.so2, 'ppb'),
      ],
    );
  }

  TableRow _buildTableRow(String parameter, double value, String unit) {
    final comment = AirQualityHelper.getQualityComment(value, parameter);
    final color = AirQualityHelper.getQualityColor(comment);
    final standard = AirQualityHelper.getStandardValue(parameter);

    return TableRow(
      children: [
        TableCell(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              parameter,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ),
        TableCell(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              standard,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ),
        TableCell(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${value.toStringAsFixed(1)} $unit',
                style: TextStyle(
                  fontSize: 14,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
        TableCell(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                comment,
                style: TextStyle(
                  fontSize: 14,
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildCurrentStatus();
  }
}