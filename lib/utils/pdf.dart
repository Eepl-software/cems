import 'dart:io';
import 'dart:typed_data';

class PDFUtils {
  /// Validates if a file is a valid PDF by checking the PDF header
  static Future<bool> isValidPDF(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return false;
      
      final bytes = await file.openRead(0, 8).first;
      
      // Check for PDF signature: %PDF-
      const pdfSignature = [0x25, 0x50, 0x44, 0x46, 0x2D]; // %PDF-
      
      if (bytes.length < pdfSignature.length) return false;
      
      for (int i = 0; i < pdfSignature.length; i++) {
        if (bytes[i] != pdfSignature[i]) return false;
      }
      
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// Gets basic file information
  static Future<PDFFileInfo> getFileInfo(String filePath) async {
    final file = File(filePath);
    final stat = await file.stat();
    
    return PDFFileInfo(
      name: file.path.split('/').last,
      path: filePath,
      size: stat.size,
      lastModified: stat.modified,
      isValid: await isValidPDF(filePath),
    );
  }
  
  /// Formats file size in human-readable format
  static String formatFileSize(int bytes) {
    const suffixes = ['B', 'KB', 'MB', 'GB'];
    int i = 0;
    double size = bytes.toDouble();
    
    while (size >= 1024 && i < suffixes.length - 1) {
      size /= 1024;
      i++;
    }
    
    return '${size.toStringAsFixed(i == 0 ? 0 : 1)} ${suffixes[i]}';
  }
  
  /// Checks if the app has permission to read the file
  static Future<bool> canReadFile(String filePath) async {
    try {
      final file = File(filePath);
      await file.openRead(0, 1).first;
      return true;
    } catch (e) {
      return false;
    }
  }
  
  /// Generates a thumbnail-like representation of the first page
  /// This is a placeholder - actual implementation would use the PDF library
  static Future<Uint8List?> generateThumbnail(String filePath, {
    int width = 150,
    int height = 200,
  }) async {
    // TODO: Implement actual thumbnail generation using pdfx
    // This would involve:
    // 1. Opening the PDF document
    // 2. Rendering the first page at the specified dimensions
    // 3. Converting to image bytes
    // 4. Returning the bytes for display
    
    // For now, return null to indicate no thumbnail available
    return null;
  }
  
  /// Validates PDF file and provides detailed error information
  static Future<PDFValidationResult> validatePDF(String filePath) async {
    final file = File(filePath);
    
    // Check if file exists
    if (!await file.exists()) {
      return PDFValidationResult(
        isValid: false,
        error: 'File does not exist',
        errorCode: PDFErrorCode.fileNotFound,
      );
    }
    
    // Check file permissions
    if (!await canReadFile(filePath)) {
      return PDFValidationResult(
        isValid: false,
        error: 'Permission denied',
        errorCode: PDFErrorCode.permissionDenied,
      );
    }
    
    // Check file size (empty files are invalid)
    final stat = await file.stat();
    if (stat.size == 0) {
      return PDFValidationResult(
        isValid: false,
        error: 'File is empty',
        errorCode: PDFErrorCode.emptyFile,
      );
    }
    
    // Check PDF signature
    if (!await isValidPDF(filePath)) {
      return PDFValidationResult(
        isValid: false,
        error: 'Not a valid PDF file',
        errorCode: PDFErrorCode.invalidFormat,
      );
    }
    
    return PDFValidationResult(
      isValid: true,
      error: null,
      errorCode: null,
    );
  }
}

/// Information about a PDF file
class PDFFileInfo {
  final String name;
  final String path;
  final int size;
  final DateTime lastModified;
  final bool isValid;
  
  const PDFFileInfo({
    required this.name,
    required this.path,
    required this.size,
    required this.lastModified,
    required this.isValid,
  });
  
  String get formattedSize => PDFUtils.formatFileSize(size);
  
  String get formattedDate {
    final now = DateTime.now();
    final difference = now.difference(lastModified);
    
    if (difference.inDays == 0) {
      return 'Today';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else {
      return '${lastModified.day}/${lastModified.month}/${lastModified.year}';
    }
  }
}

/// Result of PDF validation
class PDFValidationResult {
  final bool isValid;
  final String? error;
  final PDFErrorCode? errorCode;
  
  const PDFValidationResult({
    required this.isValid,
    this.error,
    this.errorCode,
  });
}

/// Error codes for PDF validation
enum PDFErrorCode {
  fileNotFound,
  permissionDenied,
  emptyFile,
  invalidFormat,
  corrupted,
  passwordProtected,
  unsupportedVersion,
}

/// Extension methods for PDFErrorCode
extension PDFErrorCodeExtension on PDFErrorCode {
  String get description {
    switch (this) {
      case PDFErrorCode.fileNotFound:
        return 'The specified file could not be found.';
      case PDFErrorCode.permissionDenied:
        return 'Permission denied. Check file permissions.';
      case PDFErrorCode.emptyFile:
        return 'The file is empty or has no content.';
      case PDFErrorCode.invalidFormat:
        return 'The file is not a valid PDF document.';
      case PDFErrorCode.corrupted:
        return 'The PDF file appears to be corrupted.';
      case PDFErrorCode.passwordProtected:
        return 'This PDF is password protected.';
      case PDFErrorCode.unsupportedVersion:
        return 'This PDF version is not supported.';
    }
  }
  
  String get userFriendlyMessage {
    switch (this) {
      case PDFErrorCode.fileNotFound:
        return 'File not found. It may have been moved or deleted.';
      case PDFErrorCode.permissionDenied:
        return 'Cannot access this file. Please check permissions.';
      case PDFErrorCode.emptyFile:
        return 'This file appears to be empty.';
      case PDFErrorCode.invalidFormat:
        return 'This is not a valid PDF file.';
      case PDFErrorCode.corrupted:
        return 'This PDF file is damaged and cannot be opened.';
      case PDFErrorCode.passwordProtected:
        return 'This PDF requires a password to open.';
      case PDFErrorCode.unsupportedVersion:
        return 'This PDF version is not supported by the viewer.';
    }
  }
}