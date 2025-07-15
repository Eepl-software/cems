import 'package:intl/intl.dart';

class TankerData {
  final int? id;
  final String vehicleNo;
  final double capacity;
  final double? latitude;
  final double? longitude;
  final String? photoUrl;
  final DateTime timestamp;
  final String? location;

  TankerData({
    this.id,
    required this.vehicleNo,
    required this.capacity,
    this.latitude,
    this.longitude,
    this.photoUrl,
    required this.timestamp,
    this.location,
  });

  factory TankerData.fromJson(Map<String, dynamic> json) {
    return TankerData(
      id: json['id'],
      vehicleNo: json['vehicle_no'] ?? '',
      capacity: double.tryParse(json['capacity']?.toString() ?? '0') ?? 0.0,
      latitude: double.tryParse(json['latitude']?.toString() ?? ''),
      longitude: double.tryParse(json['longitude']?.toString() ?? ''),
      photoUrl: json['photo_url'],
      timestamp: DateTime.tryParse(json['timestamp'] ?? '') ?? DateTime.now(),
      location: json['location'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'vehicle_no': vehicleNo,
      'capacity': capacity,
      'latitude': latitude,
      'longitude': longitude,
      'photo_url': photoUrl,
      'timestamp': DateFormat('yyyy-MM-dd HH:mm:ss').format(timestamp),
      'location': location,
    };
  }
}