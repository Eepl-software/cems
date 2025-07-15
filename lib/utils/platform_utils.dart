import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;

class PlatformUtils {
  // Platform detection
  static bool get isWeb => kIsWeb;
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isIOS => !kIsWeb && Platform.isIOS;
  static bool get isWindows => !kIsWeb && Platform.isWindows;
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;
  static bool get isLinux => !kIsWeb && Platform.isLinux;
  static bool get isFuchsia => !kIsWeb && Platform.isFuchsia;
  
  // Platform groups
  static bool get isMobile => isAndroid || isIOS;
  static bool get isDesktop => isWindows || isMacOS || isLinux;
  static bool get isApple => isIOS || isMacOS;
  
  // Screen size categories
  static bool isSmallScreen(double width) => width < 600;
  static bool isMediumScreen(double width) => width >= 600 && width < 1200;
  static bool isLargeScreen(double width) => width >= 1200;
  
  // Input method detection
  static bool get supportsTouchInput => isMobile;
  static bool get supportsMouseInput => isDesktop || isWeb;
  static bool get supportsKeyboardShortcuts => isDesktop || isWeb;
  
  // Platform-specific features
  static bool get supportsFileSystemAccess => !isWeb;
  static bool get supportsNativeFilePicker => !isWeb;
  static bool get supportsShareSheet => isMobile;
  static bool get supportsSystemTray => isDesktop;
  static bool get supportsMenuBar => isDesktop;
  
  // Get platform name for debugging
  static String get platformName {
    if (isWeb) return 'Web';
    if (isAndroid) return 'Android';
    if (isIOS) return 'iOS';
    if (isWindows) return 'Windows';
    if (isMacOS) return 'macOS';
    if (isLinux) return 'Linux';
    if (isFuchsia) return 'Fuchsia';
    return 'Unknown';
  }
  
  // Get appropriate toolbar height based on platform
  static double getToolbarHeight() {
    if (isMobile) return 56.0;
    if (isDesktop) return 64.0;
    if (isWeb) return 60.0;
    return 56.0;
  }
  
  // Get appropriate padding based on platform
  static double getDefaultPadding() {
    if (isMobile) return 16.0;
    if (isDesktop) return 24.0;
    if (isWeb) return 20.0;
    return 16.0;
  }
  
  // Get appropriate icon size based on platform
  static double getIconSize() {
    if (isMobile) return 24.0;
    if (isDesktop) return 20.0;
    if (isWeb) return 22.0;
    return 24.0;
  }
  
  // Check if platform supports specific PDF features
  static bool get supportsAdvancedPDFFeatures => !isWeb;
  static bool get supportsPDFAnnotations => isDesktop || isMobile;
  static bool get supportsPDFPrinting => isDesktop || isMobile;
  
  // Get platform-specific keyboard shortcuts
  static bool get usesCmdKey => isApple;
  static bool get usesCtrlKey => !isApple;
  
  // File handling capabilities
  static bool get canWriteToDocuments => supportsFileSystemAccess;
  static bool get canAccessDownloads => supportsFileSystemAccess;
  static bool get requiresPermissions => isMobile;
}

class ResponsiveBreakpoints {
  static const double mobile = 600;
  static const double tablet = 900;
  static const double desktop = 1200;
  static const double largeDesktop = 1600;
  
  static bool isMobile(double width) => width < mobile;
  static bool isTablet(double width) => width >= mobile && width < desktop;
  static bool isDesktop(double width) => width >= desktop;
  static bool isLargeDesktop(double width) => width >= largeDesktop;
}

// Extension methods for easier use
extension PlatformContextExtension on double {
  bool get isMobileWidth => ResponsiveBreakpoints.isMobile(this);
  bool get isTabletWidth => ResponsiveBreakpoints.isTablet(this);
  bool get isDesktopWidth => ResponsiveBreakpoints.isDesktop(this);
  bool get isLargeDesktopWidth => ResponsiveBreakpoints.isLargeDesktop(this);
}