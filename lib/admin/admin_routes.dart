// admin_routes.dart
import 'package:flutter/material.dart';
import 'package:namer_app/services/admin_service.dart';

class AdminRoutes {
  static const String dashboard = '/admin/dashboard';
  static const String users = '/admin/users';
  static const String userDetail = '/admin/users/detail';
  static const String createUser = '/admin/users/create';
  static const String system = '/admin/system';
  static const String reports = '/admin/reports';
  static const String alerts = '/admin/alerts';
  static const String settings = '/admin/settings';
  static const String security = '/admin/security';
  static const String logs = '/admin/logs';
  static const String backup = '/admin/backup';

  static Map<String, WidgetBuilder> getRoutes() {
    return {
      dashboard: (context) => const AdminDashboardPage(),
      users: (context) => const AdminUsersPage(),
      userDetail: (context) => const AdminUserDetailPage(),
      createUser: (context) => const AdminCreateUserPage(),
      system: (context) => const AdminSystemPage(),
      reports: (context) => const AdminReportsPage(),
      alerts: (context) => const AdminAlertsPage(),
      settings: (context) => const AdminSettingsPage(),
      security: (context) => const AdminSecurityPage(),
      logs: (context) => const AdminLogsPage(),
      backup: (context) => const AdminBackupPage(),
    };
  }
}

class AdminNavigator {
  static final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  
  static GlobalKey<NavigatorState> get navigatorKey => _navigatorKey;

  static Future<T?> pushNamed<T>(String routeName, {Object? arguments}) {
    return _navigatorKey.currentState!.pushNamed<T>(routeName, arguments: arguments);
  }

  static Future<T?> pushReplacementNamed<T>(String routeName, {Object? arguments}) {
    return _navigatorKey.currentState!.pushReplacementNamed<T, T>(routeName, arguments: arguments);
  }

  static void pop<T>([T? result]) {
    return _navigatorKey.currentState!.pop<T>(result);
  }

  static Future<T?> pushAndRemoveUntil<T>(
    String routeName,
    bool Function(Route<dynamic>) predicate, {
    Object? arguments,
  }) {
    return _navigatorKey.currentState!.pushNamedAndRemoveUntil<T>(
      routeName,
      predicate,
      arguments: arguments,
    );
  }

  static bool canPop() {
    return _navigatorKey.currentState!.canPop();
  }
}

// Admin Permission Manager
class AdminPermissions {
  static const String viewDashboard = 'view_dashboard';
  static const String manageUsers = 'manage_users';
  static const String createUsers = 'create_users';
  static const String deleteUsers = 'delete_users';
  static const String viewSystem = 'view_system';
  static const String manageSystem = 'manage_system';
  static const String viewReports = 'view_reports';
  static const String generateReports = 'generate_reports';
  static const String manageAlerts = 'manage_alerts';
  static const String viewSettings = 'view_settings';
  static const String manageSettings = 'manage_settings';
  static const String viewLogs = 'view_logs';
  static const String manageBackup = 'manage_backup';

  static List<String> get allPermissions => [
    viewDashboard,
    manageUsers,
    createUsers,
    deleteUsers,
    viewSystem,
    manageSystem,
    viewReports,
    generateReports,
    manageAlerts,
    viewSettings,
    manageSettings,
    viewLogs,
    manageBackup,
  ];

  static List<String> get superAdminPermissions => allPermissions;

  static List<String> get adminPermissions => [
    viewDashboard,
    manageUsers,
    createUsers,
    viewSystem,
    viewReports,
    generateReports,
    manageAlerts,
    viewSettings,
    viewLogs,
  ];

  static List<String> get moderatorPermissions => [
    viewDashboard,
    viewSystem,
    viewReports,
    viewSettings,
    viewLogs,
  ];

  static bool hasPermission(List<String> userPermissions, String permission) {
    return userPermissions.contains('all') || userPermissions.contains(permission);
  }

  static bool hasAnyPermission(List<String> userPermissions, List<String> permissions) {
    if (userPermissions.contains('all')) return true;
    return permissions.any((permission) => userPermissions.contains(permission));
  }
}

// Admin Theme Configuration
class AdminTheme {
  static const Color primaryColor = Color(0xFF1565C0);
  static const Color secondaryColor = Color(0xFF0D47A1);
  static const Color accentColor = Color(0xFF2196F3);
  static const Color errorColor = Color(0xFFD32F2F);
  static const Color warningColor = Color(0xFFFF9800);
  static const Color successColor = Color(0xFF388E3C);
  static const Color infoColor = Color(0xFF1976D2);

  static ThemeData get theme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.light,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 4,
        centerTitle: false,
      ),
      cardTheme: CardTheme(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: primaryColor, width: 2),
        ),
      ),
      tabBarTheme: const TabBarTheme(
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white70,
        indicatorColor: Colors.white,
      ),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: primaryColor,
        brightness: Brightness.dark,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.grey[900],
        foregroundColor: Colors.white,
        elevation: 4,
        centerTitle: false,
      ),
      cardTheme: CardTheme(
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        color: Colors.grey[800],
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryColor,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  static Color getSeverityColor(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return errorColor;
      case 'high':
        return warningColor;
      case 'medium':
        return infoColor;
      case 'low':
        return successColor;
      default:
        return Colors.grey;
    }
  }

  static IconData getSeverityIcon(String severity) {
    switch (severity.toLowerCase()) {
      case 'critical':
        return Icons.error;
      case 'high':
        return Icons.warning;
      case 'medium':
        return Icons.info;
      case 'low':
        return Icons.check_circle;
      default:
        return Icons.circle;
    }
  }
}

// Admin Configuration
class AdminConfig {
  static const String appName = 'Sustainable Infrastructure Admin';
  static const String appVersion = '1.0.0';
  static const String defaultAvatarUrl = 'https://via.placeholder.com/150';
  
  // Pagination
  static const int defaultPageSize = 10;
  static const int maxPageSize = 100;
  
  // Timeouts
  static const Duration defaultTimeout = Duration(seconds: 10);
  static const Duration longTimeout = Duration(seconds: 30);
  static const Duration uploadTimeout = Duration(minutes: 5);
  
  // Refresh intervals
  static const Duration dashboardRefreshInterval = Duration(seconds: 30);
  static const Duration logsRefreshInterval = Duration(seconds: 10);
  
  // File size limits
  static const int maxFileSize = 10 * 1024 * 1024; // 10MB
  static const int maxImageSize = 5 * 1024 * 1024; // 5MB
  
  // Admin roles
  static const String superAdminRole = 'super_admin';
  static const String adminRole = 'admin';
  static const String moderatorRole = 'moderator';
  
  static List<String> get allRoles => [superAdminRole, adminRole, moderatorRole];
  
  // Date formats
  static const String dateFormat = 'yyyy-MM-dd';
  static const String dateTimeFormat = 'yyyy-MM-dd HH:mm:ss';
  static const String displayDateFormat = 'MMM dd, yyyy';
  static const String displayDateTimeFormat = 'MMM dd, yyyy HH:mm';
  
  // Report types
  static const List<String> reportTypes = [
    'users',
    'water',
    'tankers',
    'system',
    'custom',
  ];
  
  // Alert severities
  static const List<String> alertSeverities = [
    'low',
    'medium',
    'high',
    'critical',
  ];
  
  // System health thresholds
  static const int healthGoodThreshold = 90;
  static const int healthWarningThreshold = 70;
  static const int healthCriticalThreshold = 50;
  
  static String getHealthStatus(int health) {
    if (health >= healthGoodThreshold) return 'Good';
    if (health >= healthWarningThreshold) return 'Warning';
    if (health >= healthCriticalThreshold) return 'Critical';
    return 'Severe';
  }
  
  static Color getHealthColor(int health) {
    if (health >= healthGoodThreshold) return AdminTheme.successColor;
    if (health >= healthWarningThreshold) return AdminTheme.warningColor;
    if (health >= healthCriticalThreshold) return AdminTheme.errorColor;
    return Colors.red[900]!;
  }
}

// Admin State Management
abstract class AdminState {
  const AdminState();
}

class AdminInitial extends AdminState {
  const AdminInitial();
}

class AdminLoading extends AdminState {
  final String? message;
  const AdminLoading({this.message});
}

class AdminLoaded<T> extends AdminState {
  final T data;
  const AdminLoaded(this.data);
}

class AdminError extends AdminState {
  final String message;
  final String? details;
  const AdminError(this.message, {this.details});
}

// Admin Event Base Class
abstract class AdminEvent {
  const AdminEvent();
}

class AdminLoadEvent extends AdminEvent {
  const AdminLoadEvent();
}

class AdminRefreshEvent extends AdminEvent {
  const AdminRefreshEvent();
}

class AdminUpdateEvent<T> extends AdminEvent {
  final T data;
  const AdminUpdateEvent(this.data);
}

class AdminDeleteEvent extends AdminEvent {
  final dynamic id;
  const AdminDeleteEvent(this.id);
}

// Utility Classes
class AdminUtils {
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
  
  static String formatDuration(Duration duration) {
    final days = duration.inDays;
    final hours = duration.inHours % 24;
    final minutes = duration.inMinutes % 60;
    final seconds = duration.inSeconds % 60;
    
    if (days > 0) {
      return '${days}d ${hours}h ${minutes}m';
    } else if (hours > 0) {
      return '${hours}h ${minutes}m';
    } else if (minutes > 0) {
      return '${minutes}m ${seconds}s';
    } else {
      return '${seconds}s';
    }
  }
  
  static String getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }
  
  static bool isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }
  
  static bool isValidPhone(String phone) {
    return RegExp(r'^\d{10}$').hasMatch(phone);
  }
  
  static bool isStrongPassword(String password) {
    return password.length >= 8 &&
           RegExp(r'[A-Z]').hasMatch(password) &&
           RegExp(r'[a-z]').hasMatch(password) &&
           RegExp(r'[0-9]').hasMatch(password) &&
           RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password);
  }
  
  static String generateRandomId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
}

// Admin Error Handling
class AdminErrorHandler {
  static void handleError(dynamic error, VoidCallback? onRetry) {
    // Log error
    print('Admin Error: $error');
    
    // Show error dialog or snackbar
    // Implementation depends on the context
  }
  
  static String getErrorMessage(dynamic error) {
    if (error is AdminException) {
      return error.message;
    } else if (error is Exception) {
      return error.toString();
    } else {
      return 'An unexpected error occurred';
    }
  }
}

// Placeholder pages (these would be implemented separately)
class AdminDashboardPage extends StatelessWidget {
  const AdminDashboardPage({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Admin Dashboard')),
    );
  }
}

class AdminUsersPage extends StatelessWidget {
  const AdminUsersPage({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Admin Users')),
    );
  }
}

class AdminUserDetailPage extends StatelessWidget {
  const AdminUserDetailPage({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Admin User Detail')),
    );
  }
}

class AdminCreateUserPage extends StatelessWidget {
  const AdminCreateUserPage({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Admin Create User')),
    );
  }
}

class AdminSystemPage extends StatelessWidget {
  const AdminSystemPage({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Admin System')),
    );
  }
}

class AdminReportsPage extends StatelessWidget {
  const AdminReportsPage({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Admin Reports')),
    );
  }
}

class AdminAlertsPage extends StatelessWidget {
  const AdminAlertsPage({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Admin Alerts')),
    );
  }
}

class AdminSettingsPage extends StatelessWidget {
  const AdminSettingsPage({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Admin Settings')),
    );
  }
}

class AdminSecurityPage extends StatelessWidget {
  const AdminSecurityPage({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Admin Security')),
    );
  }
}

class AdminLogsPage extends StatelessWidget {
  const AdminLogsPage({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Admin Logs')),
    );
  }
}

class AdminBackupPage extends StatelessWidget {
  const AdminBackupPage({Key? key}) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: Text('Admin Backup')),
    );
  }
}