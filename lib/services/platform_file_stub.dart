// Stub implementation for web compatibility
class PlatformFile {
  static bool get supportsFileOperations => false;
  
  static Future<String?> getFilePath(String filename) async {
    return null; // Not supported on web
  }
  
  static Future<bool> fileExists(String path) async {
    return false; // Not supported on web
  }
}