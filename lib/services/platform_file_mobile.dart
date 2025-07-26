import 'dart:io';
import 'package:path_provider/path_provider.dart';

class PlatformFile {
  static bool get supportsFileOperations => true;
  
  static Future<String?> getFilePath(String filename) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      return '${directory.path}/$filename';
    } catch (e) {
      return null;
    }
  }
  
  static Future<bool> fileExists(String path) async {
    try {
      return await File(path).exists();
    } catch (e) {
      return false;
    }
  }
}