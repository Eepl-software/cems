/// Updated Air Pollution Monitoring Models
/// These models match the corrected backend schema

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
    final Map<String, dynamic> json = {
      'source': source,
      'as_per_consent': asPerConsent,
      'provided': provided,
      'status': status,
    };
    
    if (id != null) {
      json['id'] = id;
    }
    
    return json;
  }

  // For backward compatibility with existing frontend code
  String get consentChimney => asPerConsent;
  String get providedChimney => provided;
  String get consentApcSystem => asPerConsent;
  String get providedApcSystem => provided;
  String get parameter => 'Not specified';
  String get standard => 'Not specified';
  String get results => 'Not specified';
  String get comments => 'Not specified';

  StackMonitoringData copyWith({
    String? id,
    String? source,
    String? asPerConsent,
    String? provided,
    String? status,
    DateTime? timestamp,
  }) {
    return StackMonitoringData(
      id: id ?? this.id,
      source: source ?? this.source,
      asPerConsent: asPerConsent ?? this.asPerConsent,
      provided: provided ?? this.provided,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

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

  // For backward compatibility with existing frontend code
  String get consentChimney => limitValue;
  String get providedChimney => measured;
  String get consentApcSystem => limitValue;
  String get providedApcSystem => measured;
  String get standard => limitValue;
  String get results => measured;
  String get comments => 'Status: $status';

  AmbientAirMonitoringData copyWith({
    String? id,
    String? location,
    String? parameter,
    String? limitValue,
    String? measured,
    String? status,
    DateTime? timestamp,
  }) {
    return AmbientAirMonitoringData(
      id: id ?? this.id,
      location: location ?? this.location,
      parameter: parameter ?? this.parameter,
      limitValue: limitValue ?? this.limitValue,
      measured: measured ?? this.measured,
      status: status ?? this.status,
      timestamp: timestamp ?? this.timestamp,
    );
  }
}

// Factory class to create instances with proper defaults
class AirPollutionDataFactory {
  static StackMonitoringData createStackMonitoring({
    String? source,
    String? asPerConsent,
    String? provided,
    String? status,
  }) {
    return StackMonitoringData(
      source: source ?? '',
      asPerConsent: asPerConsent ?? '',
      provided: provided ?? '',
      status: status ?? 'Active',
      timestamp: DateTime.now(),
    );
  }

  static AmbientAirMonitoringData createAmbientMonitoring({
    String? id,
    String? location,
    String? parameter,
    String? limitValue,
    String? measured,
    String? status,
  }) {
    return AmbientAirMonitoringData(
      id: id ?? 'ambient_${DateTime.now().millisecondsSinceEpoch}',
      location: location ?? '',
      parameter: parameter ?? '',
      limitValue: limitValue ?? '',
      measured: measured ?? '',
      status: status ?? 'Active',
      timestamp: DateTime.now(),
    );
  }
}

// Parameters for air pollution monitoring
class AirPollutionParameters {
  static const List<String> stackParameters = [
    'SO2',
    'NOx',
    'PM',
    'CO',
    'CO2',
    'HCl',
    'HF',
  ];

  static const List<String> ambientParameters = [
    'SO2',
    'SPM',
    'PM2.5',
    'PM10',
    'NOx',
    'CO',
    'CO2',
    'HCl',
    'HF',
    'VOC',
    'O3',
    'NH3',
  ];

  static const List<String> statusOptions = [
    'Active',
    'Inactive',
    'Maintenance',
    'Normal',
    'Warning',
    'Critical',
  ];
}