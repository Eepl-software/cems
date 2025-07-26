import 'package:flutter/foundation.dart';

abstract class PlatformService {
  static bool get isWeb => kIsWeb;
  static bool get isMobile => !kIsWeb;
  
  // Platform-specific capabilities
  static bool get supportsFileSystem => !kIsWeb;
  static bool get supportsBiometrics => !kIsWeb;
  static bool get supportsCamera => true; // Available on web with limitations
  static bool get supportsLocation => true; // Available on web with HTTPS
  static bool get supportsLocalStorage => true;
  
  // Storage paths - web uses browser storage, mobile uses file system
  static String get documentsPath => kIsWeb ? 'web_documents' : 'mobile_documents';
  static String get cachePath => kIsWeb ? 'web_cache' : 'mobile_cache';
}