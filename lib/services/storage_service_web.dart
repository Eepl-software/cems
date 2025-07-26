import 'dart:html' as html;
import 'dart:convert';
import 'dart:typed_data';

class WebStorageService {
  // Use localStorage for small data and IndexedDB for larger files
  static void saveData(String key, String value) {
    html.window.localStorage[key] = value;
  }
  
  static String? getData(String key) {
    return html.window.localStorage[key];
  }
  
  static void saveJsonData(String key, Map<String, dynamic> data) {
    html.window.localStorage[key] = jsonEncode(data);
  }
  
  static Map<String, dynamic>? getJsonData(String key) {
    final data = html.window.localStorage[key];
    if (data != null) {
      return jsonDecode(data) as Map<String, dynamic>;
    }
    return null;
  }
  
  static void removeData(String key) {
    html.window.localStorage.remove(key);
  }
  
  static void clearAll() {
    html.window.localStorage.clear();
  }
  
  // For file downloads on web
  static void downloadFile(Uint8List bytes, String filename) {
    final blob = html.Blob([bytes]);
    final url = html.Url.createObjectUrlFromBlob(blob);
    final anchor = html.AnchorElement(href: url)
      ..setAttribute('download', filename)
      ..click();
    html.Url.revokeObjectUrl(url);
  }
}