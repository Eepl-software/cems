class Tanker {
  final String plateNumber;
  final double capacity;
  final String driverName;
  final String driverContact;
  final String vendor;
  final DateTime lastUpdated;
  final double? latitude;
  final double? longitude;
  final String? photoUrl;

  Tanker({
    required this.plateNumber,
    required this.capacity,
    required this.driverName,
    required this.driverContact,
    required this.vendor,
    required this.lastUpdated,
    this.latitude,
    this.longitude,
    this.photoUrl,
  });

  factory Tanker.fromJson(Map<String, dynamic> json) {
    return Tanker(
      plateNumber: json['plateNumber'] as String,
      capacity: json['capacity'] as double,
      driverName: json['driverName'] as String,
      driverContact: json['driverContact'] as String,
      vendor: json['vendor'] as String,
      lastUpdated: DateTime.parse(json['lastUpdated'] as String),
      latitude: json['latitude'] != null ? json['latitude'] as double : null,
      longitude: json['longitude'] != null ? json['longitude'] as double : null,
      photoUrl: json['photoUrl'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'plateNumber': plateNumber,
      'capacity': capacity,
      'driverName': driverName,
      'driverContact': driverContact,
      'vendor': vendor,
      'lastUpdated': lastUpdated.toIso8601String(),
      'latitude': latitude,
      'longitude': longitude,
      'photoUrl': photoUrl,
    };
  }
}