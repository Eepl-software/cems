import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'storage_service_web.dart' if (dart.library.io) 'storage_service_mobile.dart' as platform_storage;
import 'storage_service_mobile.dart' if (dart.library.html) 'storage_service_web.dart' as platform_storage;

class UnifiedStorageService {
  // Unified interface that works on both web and mobile
  static Future<void> saveData(String key, String value) async {
    if (kIsWeb) {
      platform_storage.WebStorageService.saveData(key, value);
    } else {
      await platform_storage.MobileStorageService.saveData(key, value);
    }
  }
  
  static Future<String?> getData(String key) async {
    if (kIsWeb) {
      return platform_storage.WebStorageService.getData(key);
    } else {
      return await platform_storage.MobileStorageService.getData(key);
    }
  }
  
  static Future<void> saveJsonData(String key, Map<String, dynamic> data) async {
    if (kIsWeb) {
      platform_storage.WebStorageService.saveJsonData(key, data);
    } else {
      await platform_storage.MobileStorageService.saveJsonData(key, data);
    }
  }
  
  static Future<Map<String, dynamic>?> getJsonData(String key) async {
    if (kIsWeb) {
      return platform_storage.WebStorageService.getJsonData(key);
    } else {
      return await platform_storage.MobileStorageService.getJsonData(key);
    }
  }
  
  static Future<void> removeData(String key) async {
    if (kIsWeb) {
      platform_storage.WebStorageService.removeData(key);
    } else {
      await platform_storage.MobileStorageService.removeData(key);
    }
  }
  
  static Future<void> clearAll() async {
    if (kIsWeb) {
      platform_storage.WebStorageService.clearAll();
    } else {
      await platform_storage.MobileStorageService.clearAll();
    }
  }
  
  // File handling with platform-specific implementations
  static Future<void> saveOrDownloadFile(Uint8List bytes, String filename) async {
    if (kIsWeb) {
      platform_storage.WebStorageService.downloadFile(bytes, filename);
    } else {
      await platform_storage.MobileStorageService.saveFile(bytes, filename);
    }
  }
}