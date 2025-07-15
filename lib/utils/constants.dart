class Constants {
  static const String baseUrl = 'http://54.146.215.18:3000';
  
  static const Map<String, double> defaultTankerCapacities = {
    'KA01': 12000.0,
    'KA02': 15000.0,
    'KA03': 18000.0,
    'KA04': 20000.0,
    'KA05': 22000.0,
    // Add more default capacities based on registration series
  };

  static double getTankerCapacity(String registrationNumber) {
    String series = registrationNumber.substring(0, 4);
    return defaultTankerCapacities[series] ?? 15000.0; // Default capacity if series not found
    }
  
  }