import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

class SystemSettingsPage extends StatefulWidget {
  @override
  _SystemSettingsPageState createState() => _SystemSettingsPageState();
}

class _SystemSettingsPageState extends State<SystemSettingsPage>
    with TickerProviderStateMixin {
  final TextEditingController _searchController = TextEditingController();
  late TabController _tabController;
  
  // Settings state
  Map<String, dynamic> _settings = {
    // Security Settings
    'twoFactorAuth': true,
    'biometricLogin': false,
    'sessionTimeout': 30,
    'autoLock': true,
    'encryptData': true,
    
    // Network Settings
    'autoSync': true,
    'backgroundData': false,
    'wifiOnly': true,
    'connectionTimeout': 10,
    'maxRetries': 3,
    
    // Display Settings
    'darkMode': false,
    'fontSize': 16.0,
    'brightness': 0.8,
    'animations': true,
    'reducedMotion': false,
    
    // Notification Settings
    'pushNotifications': true,
    'emailNotifications': false,
    'soundEnabled': true,
    'vibrationEnabled': true,
    'doNotDisturb': false,
    'notificationSound': 'Default',
    
    // Performance Settings
    'cacheSizeMB': 100,
    'maxConcurrentTasks': 5,
    'enableLogs': false,
    'compressionLevel': 'Medium',
    
    // Privacy Settings
    'collectAnalytics': false,
    'shareLocation': false,
    'cookiesEnabled': true,
    'trackingProtection': true,
  };

  String _searchQuery = '';
  
  final List<String> _categories = [
    'All',
    'Security',
    'Network',
    'Display',
    'Notifications',
    'Performance',
    'Privacy',
    'About'
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _categories.length, vsync: this);
    _loadSettings();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    // Simulate loading settings from storage
    await Future.delayed(Duration(milliseconds: 500));
    // In a real app, you'd load from SharedPreferences or secure storage
  }

  Future<void> _saveSettings() async {
    // Simulate saving settings
    await Future.delayed(Duration(milliseconds: 200));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Settings saved successfully'),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _updateSetting(String key, dynamic value) {
    setState(() {
      _settings[key] = value;
    });
    _saveSettings();
  }

  void _resetSettings() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reset Settings'),
        content: Text('Are you sure you want to reset all settings to default values?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _settings = Map.from(_getDefaultSettings());
              });
              Navigator.pop(context);
              _saveSettings();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text('Reset'),
          ),
        ],
      ),
    );
  }

  Map<String, dynamic> _getDefaultSettings() {
    return {
      'twoFactorAuth': false,
      'biometricLogin': false,
      'sessionTimeout': 15,
      'autoLock': false,
      'encryptData': true,
      'autoSync': false,
      'backgroundData': false,
      'wifiOnly': false,
      'connectionTimeout': 5,
      'maxRetries': 1,
      'darkMode': false,
      'fontSize': 14.0,
      'brightness': 0.5,
      'animations': true,
      'reducedMotion': false,
      'pushNotifications': false,
      'emailNotifications': false,
      'soundEnabled': false,
      'vibrationEnabled': false,
      'doNotDisturb': false,
      'notificationSound': 'Default',
      'cacheSizeMB': 50,
      'maxConcurrentTasks': 3,
      'enableLogs': false,
      'compressionLevel': 'Low',
      'collectAnalytics': false,
      'shareLocation': false,
      'cookiesEnabled': false,
      'trackingProtection': true,
    };
  }

  void _exportSettings() async {
    final settingsJson = jsonEncode(_settings);
    await Clipboard.setData(ClipboardData(text: settingsJson));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Settings exported to clipboard'),
        backgroundColor: Colors.blue,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      margin: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search settings...',
          prefixIcon: Icon(Icons.search, color: Colors.grey.shade600),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: Icon(Icons.clear),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                )
              : null,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value.toLowerCase();
          });
        },
      ),
    );
  }

  Widget _buildSettingTile({
    required String title,
    String? subtitle,
    required IconData icon,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    if (_searchQuery.isNotEmpty && 
        !title.toLowerCase().contains(_searchQuery) &&
        (subtitle == null || !subtitle.toLowerCase().contains(_searchQuery))) {
      return SizedBox.shrink();
    }

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.blue.shade50,
          child: Icon(icon, color: Colors.blue.shade600, size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: subtitle != null ? Text(subtitle) : null,
        trailing: trailing,
        onTap: onTap,
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    String? subtitle,
    required IconData icon,
    required String settingKey,
  }) {
    return _buildSettingTile(
      title: title,
      subtitle: subtitle,
      icon: icon,
      trailing: Switch(
        value: _settings[settingKey] ?? false,
        onChanged: (value) => _updateSetting(settingKey, value),
        activeColor: Colors.blue,
      ),
    );
  }

  Widget _buildSliderTile({
    required String title,
    String? subtitle,
    required IconData icon,
    required String settingKey,
    required double min,
    required double max,
    int? divisions,
    String Function(double)? labelFormatter,
  }) {
    return _buildSettingTile(
      title: title,
      subtitle: subtitle,
      icon: icon,
      trailing: SizedBox(
        width: 120,
        child: Slider(
          value: (_settings[settingKey] ?? min).toDouble(),
          min: min,
          max: max,
          divisions: divisions,
          label: labelFormatter?.call((_settings[settingKey] ?? min).toDouble()),
          onChanged: (value) => _updateSetting(settingKey, value),
          activeColor: Colors.blue,
        ),
      ),
    );
  }

  Widget _buildDropdownTile({
    required String title,
    String? subtitle,
    required IconData icon,
    required String settingKey,
    required List<String> options,
  }) {
    return _buildSettingTile(
      title: title,
      subtitle: subtitle,
      icon: icon,
      trailing: DropdownButton<String>(
        value: _settings[settingKey] ?? options.first,
        items: options.map((option) {
          return DropdownMenuItem(
            value: option,
            child: Text(option),
          );
        }).toList(),
        onChanged: (value) => _updateSetting(settingKey, value),
        underline: SizedBox(),
      ),
    );
  }

  Widget _buildSecuritySettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Security',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        _buildSwitchTile(
          title: 'Two-Factor Authentication',
          subtitle: 'Add an extra layer of security',
          icon: Icons.security,
          settingKey: 'twoFactorAuth',
        ),
        _buildSwitchTile(
          title: 'Biometric Login',
          subtitle: 'Use fingerprint or face recognition',
          icon: Icons.fingerprint,
          settingKey: 'biometricLogin',
        ),
        _buildSliderTile(
          title: 'Session Timeout',
          subtitle: 'Auto-logout after inactivity',
          icon: Icons.timer,
          settingKey: 'sessionTimeout',
          min: 5,
          max: 60,
          divisions: 11,
          labelFormatter: (value) => '${value.round()} min',
        ),
        _buildSwitchTile(
          title: 'Auto Lock',
          subtitle: 'Lock screen when idle',
          icon: Icons.lock,
          settingKey: 'autoLock',
        ),
        _buildSwitchTile(
          title: 'Encrypt Data',
          subtitle: 'Encrypt stored data',
          icon: Icons.enhanced_encryption,
          settingKey: 'encryptData',
        ),
      ],
    );
  }

  Widget _buildNetworkSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Network',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        _buildSwitchTile(
          title: 'Auto Sync',
          subtitle: 'Automatically sync data',
          icon: Icons.sync,
          settingKey: 'autoSync',
        ),
        _buildSwitchTile(
          title: 'Background Data',
          subtitle: 'Allow data usage in background',
          icon: Icons.data_usage,
          settingKey: 'backgroundData',
        ),
        _buildSwitchTile(
          title: 'WiFi Only',
          subtitle: 'Use WiFi only for data transfer',
          icon: Icons.wifi,
          settingKey: 'wifiOnly',
        ),
        _buildSliderTile(
          title: 'Connection Timeout',
          subtitle: 'Network request timeout',
          icon: Icons.timer_outlined,
          settingKey: 'connectionTimeout',
          min: 5,
          max: 60,
          divisions: 11,
          labelFormatter: (value) => '${value.round()}s',
        ),
        _buildSliderTile(
          title: 'Max Retries',
          subtitle: 'Maximum retry attempts',
          icon: Icons.refresh,
          settingKey: 'maxRetries',
          min: 1,
          max: 10,
          divisions: 9,
          labelFormatter: (value) => '${value.round()}',
        ),
      ],
    );
  }

  Widget _buildDisplaySettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Display',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        _buildSwitchTile(
          title: 'Dark Mode',
          subtitle: 'Use dark theme',
          icon: Icons.dark_mode,
          settingKey: 'darkMode',
        ),
        _buildSliderTile(
          title: 'Font Size',
          subtitle: 'Adjust text size',
          icon: Icons.text_fields,
          settingKey: 'fontSize',
          min: 12,
          max: 24,
          divisions: 12,
          labelFormatter: (value) => '${value.round()}px',
        ),
        _buildSliderTile(
          title: 'Brightness',
          subtitle: 'Screen brightness',
          icon: Icons.brightness_6,
          settingKey: 'brightness',
          min: 0.1,
          max: 1.0,
          divisions: 9,
          labelFormatter: (value) => '${(value * 100).round()}%',
        ),
        _buildSwitchTile(
          title: 'Animations',
          subtitle: 'Enable UI animations',
          icon: Icons.animation,
          settingKey: 'animations',
        ),
        _buildSwitchTile(
          title: 'Reduced Motion',
          subtitle: 'Minimize motion effects',
          icon: Icons.accessibility,
          settingKey: 'reducedMotion',
        ),
      ],
    );
  }

  Widget _buildNotificationSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Notifications',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        _buildSwitchTile(
          title: 'Push Notifications',
          subtitle: 'Receive push notifications',
          icon: Icons.notifications,
          settingKey: 'pushNotifications',
        ),
        _buildSwitchTile(
          title: 'Email Notifications',
          subtitle: 'Receive email alerts',
          icon: Icons.email,
          settingKey: 'emailNotifications',
        ),
        _buildSwitchTile(
          title: 'Sound',
          subtitle: 'Play notification sounds',
          icon: Icons.volume_up,
          settingKey: 'soundEnabled',
        ),
        _buildSwitchTile(
          title: 'Vibration',
          subtitle: 'Vibrate for notifications',
          icon: Icons.vibration,
          settingKey: 'vibrationEnabled',
        ),
        _buildSwitchTile(
          title: 'Do Not Disturb',
          subtitle: 'Silence all notifications',
          icon: Icons.do_not_disturb,
          settingKey: 'doNotDisturb',
        ),
        _buildDropdownTile(
          title: 'Notification Sound',
          subtitle: 'Choose notification sound',
          icon: Icons.music_note,
          settingKey: 'notificationSound',
          options: ['Default', 'Bell', 'Chime', 'Ping', 'Silent'],
        ),
      ],
    );
  }

  Widget _buildPerformanceSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Performance',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        _buildSliderTile(
          title: 'Cache Size',
          subtitle: 'Storage for temporary files',
          icon: Icons.storage,
          settingKey: 'cacheSizeMB',
          min: 50,
          max: 500,
          divisions: 9,
          labelFormatter: (value) => '${value.round()} MB',
        ),
        _buildSliderTile(
          title: 'Concurrent Tasks',
          subtitle: 'Maximum parallel operations',
          icon: Icons.trending_up,
          settingKey: 'maxConcurrentTasks',
          min: 1,
          max: 10,
          divisions: 9,
          labelFormatter: (value) => '${value.round()}',
        ),
        _buildSwitchTile(
          title: 'Enable Logs',
          subtitle: 'Generate debug logs',
          icon: Icons.bug_report,
          settingKey: 'enableLogs',
        ),
        _buildDropdownTile(
          title: 'Compression Level',
          subtitle: 'Data compression setting',
          icon: Icons.compress,
          settingKey: 'compressionLevel',
          options: ['Low', 'Medium', 'High', 'Maximum'],
        ),
      ],
    );
  }

  Widget _buildPrivacySettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Privacy',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        _buildSwitchTile(
          title: 'Collect Analytics',
          subtitle: 'Help improve the app',
          icon: Icons.analytics,
          settingKey: 'collectAnalytics',
        ),
        _buildSwitchTile(
          title: 'Share Location',
          subtitle: 'Allow location access',
          icon: Icons.location_on,
          settingKey: 'shareLocation',
        ),
        _buildSwitchTile(
          title: 'Cookies Enabled',
          subtitle: 'Accept web cookies',
          icon: Icons.cookie,
          settingKey: 'cookiesEnabled',
        ),
        _buildSwitchTile(
          title: 'Tracking Protection',
          subtitle: 'Block online trackers',
          icon: Icons.shield,
          settingKey: 'trackingProtection',
        ),
      ],
    );
  }

  Widget _buildAboutSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'About',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
        ),
        _buildSettingTile(
          title: 'App Version',
          subtitle: '1.0.0 (Build 123)',
          icon: Icons.info,
          trailing: Icon(Icons.chevron_right),
        ),
        _buildSettingTile(
          title: 'System Info',
          subtitle: 'View device information',
          icon: Icons.phone_android,
          trailing: Icon(Icons.chevron_right),
          onTap: () => _showSystemInfo(),
        ),
        _buildSettingTile(
          title: 'Export Settings',
          subtitle: 'Copy settings to clipboard',
          icon: Icons.download,
          trailing: Icon(Icons.chevron_right),
          onTap: _exportSettings,
        ),
        _buildSettingTile(
          title: 'Reset Settings',
          subtitle: 'Restore default settings',
          icon: Icons.restore,
          trailing: Icon(Icons.chevron_right, color: Colors.red),
          onTap: _resetSettings,
        ),
        _buildSettingTile(
          title: 'Privacy Policy',
          subtitle: 'Read our privacy policy',
          icon: Icons.privacy_tip,
          trailing: Icon(Icons.open_in_new),
        ),
        _buildSettingTile(
          title: 'Terms of Service',
          subtitle: 'View terms and conditions',
          icon: Icons.description,
          trailing: Icon(Icons.open_in_new),
        ),
      ],
    );
  }

  void _showSystemInfo() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('System Information'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildInfoRow('Platform', 'Android'),
            _buildInfoRow('Version', '14.0'),
            _buildInfoRow('Build', 'API 34'),
            _buildInfoRow('Device', 'Pixel 7'),
            _buildInfoRow('RAM', '8 GB'),
            _buildInfoRow('Storage', '128 GB'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontWeight: FontWeight.w500)),
          Text(value, style: TextStyle(color: Colors.grey.shade600)),
        ],
      ),
    );
  }

  Widget _buildAllSettings() {
    return SingleChildScrollView(
      child: Column(
        children: [
          _buildSecuritySettings(),
          SizedBox(height: 16),
          _buildNetworkSettings(),
          SizedBox(height: 16),
          _buildDisplaySettings(),
          SizedBox(height: 16),
          _buildNotificationSettings(),
          SizedBox(height: 16),
          _buildPerformanceSettings(),
          SizedBox(height: 16),
          _buildPrivacySettings(),
          SizedBox(height: 16),
          _buildAboutSection(),
          SizedBox(height: 80),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          'System Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: _categories.map((category) => Tab(text: category)).toList(),
        ),
      ),
      body: Column(
        children: [
          _buildSearchBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAllSettings(),
                _buildSecuritySettings(),
                _buildNetworkSettings(),
                _buildDisplaySettings(),
                _buildNotificationSettings(),
                _buildPerformanceSettings(),
                _buildPrivacySettings(),
                _buildAboutSection(),
              ].map((widget) => SingleChildScrollView(child: widget)).toList(),
            ),
          ),
        ],
      ),
    );
  }
}