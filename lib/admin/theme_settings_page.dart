import 'package:flutter/material.dart';
import 'dart:math' as math;

class ThemeSettingsPage extends StatefulWidget {
  @override
  _ThemeSettingsPageState createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends State<ThemeSettingsPage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _previewController;
  late Animation<double> _previewAnimation;

  // Theme Settings
  ThemeMode _themeMode = ThemeMode.system;
  String _selectedColorScheme = 'Blue';
  double _fontScale = 1.0;
  String _fontFamily = 'Default';
  bool _useMaterial3 = true;
  bool _useCustomColors = false;
  Color _primaryColor = Colors.blue;
  Color _accentColor = Colors.blueAccent;
  double _borderRadius = 12.0;
  double _elevation = 4.0;
  bool _compactMode = false;
  bool _highContrast = false;

  final Map<String, ColorScheme> _colorSchemes = {
    'Blue': ColorScheme.fromSeed(seedColor: Colors.blue),
    'Green': ColorScheme.fromSeed(seedColor: Colors.green),
    'Purple': ColorScheme.fromSeed(seedColor: Colors.purple),
    'Orange': ColorScheme.fromSeed(seedColor: Colors.orange),
    'Red': ColorScheme.fromSeed(seedColor: Colors.red),
    'Teal': ColorScheme.fromSeed(seedColor: Colors.teal),
    'Pink': ColorScheme.fromSeed(seedColor: Colors.pink),
    'Indigo': ColorScheme.fromSeed(seedColor: Colors.indigo),
  };

  final List<String> _fontFamilies = [
    'Default',
    'Roboto',
    'Open Sans',
    'Lato',
    'Montserrat',
    'Poppins',
    'Inter',
    'Source Sans Pro',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _previewController = AnimationController(
      duration: Duration(milliseconds: 1500),
      vsync: this,
    );
    _previewAnimation = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _previewController, curve: Curves.easeInOut),
    );
    _previewController.repeat();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _previewController.dispose();
    super.dispose();
  }

  ThemeData _getCurrentTheme({bool isDark = false}) {
    final colorScheme = _useCustomColors
        ? ColorScheme.fromSeed(
            seedColor: _primaryColor,
            brightness: isDark ? Brightness.dark : Brightness.light,
          )
        : isDark
            ? _colorSchemes[_selectedColorScheme]!.copyWith(brightness: Brightness.dark)
            : _colorSchemes[_selectedColorScheme]!;

    return ThemeData(
      useMaterial3: _useMaterial3,
      colorScheme: colorScheme,
      fontFamily: _fontFamily == 'Default' ? null : _fontFamily,
      textTheme: _buildTextTheme(isDark),
      cardTheme: CardTheme(
        elevation: _elevation,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_borderRadius),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_borderRadius),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_borderRadius),
        ),
      ),
    );
  }

  TextTheme _buildTextTheme(bool isDark) {
    final baseTheme = isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme;
    return baseTheme.apply(
      fontSizeFactor: _fontScale,
      fontFamily: _fontFamily == 'Default' ? null : _fontFamily,
    );
  }

  Widget _buildThemeModeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Theme Mode',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 16),
        ...ThemeMode.values.map((mode) => _buildThemeModeOption(mode)),
        SizedBox(height: 24),
        Text(
          'Color Scheme',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 16),
        _buildColorSchemeGrid(),
        SizedBox(height: 24),
        _buildCustomColorToggle(),
        if (_useCustomColors) _buildCustomColorPickers(),
      ],
    );
  }

  Widget _buildThemeModeOption(ThemeMode mode) {
    final isSelected = _themeMode == mode;
    IconData icon;
    String title;
    String subtitle;

    switch (mode) {
      case ThemeMode.light:
        icon = Icons.light_mode;
        title = 'Light';
        subtitle = 'Use light theme';
        break;
      case ThemeMode.dark:
        icon = Icons.dark_mode;
        title = 'Dark';
        subtitle = 'Use dark theme';
        break;
      case ThemeMode.system:
        icon = Icons.brightness_auto;
        title = 'System';
        subtitle = 'Follow system setting';
        break;
    }

    return Container(
      margin: EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        border: Border.all(
          color: isSelected ? Theme.of(context).primaryColor : Colors.grey.shade300,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: RadioListTile<ThemeMode>(
        value: mode,
        groupValue: _themeMode,
        onChanged: (value) {
          setState(() {
            _themeMode = value!;
          });
        },
        title: Row(
          children: [
            Icon(icon, color: isSelected ? Theme.of(context).primaryColor : null),
            SizedBox(width: 12),
            Text(title),
          ],
        ),
        subtitle: Text(subtitle),
      ),
    );
  }

  Widget _buildColorSchemeGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1,
      ),
      itemCount: _colorSchemes.length,
      itemBuilder: (context, index) {
        final schemeName = _colorSchemes.keys.elementAt(index);
        final colorScheme = _colorSchemes[schemeName]!;
        final isSelected = _selectedColorScheme == schemeName;

        return GestureDetector(
          onTap: () {
            setState(() {
              _selectedColorScheme = schemeName;
              _useCustomColors = false;
            });
          },
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? Theme.of(context).primaryColor : Colors.grey.shade300,
                width: isSelected ? 3 : 1,
              ),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
                    ),
                  ),
                ),
                Container(
                  padding: EdgeInsets.symmetric(vertical: 4),
                  child: Text(
                    schemeName,
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCustomColorToggle() {
    return SwitchListTile(
      title: Text('Use Custom Colors'),
      subtitle: Text('Create your own color scheme'),
      value: _useCustomColors,
      onChanged: (value) {
        setState(() {
          _useCustomColors = value;
        });
      },
    );
  }

  Widget _buildCustomColorPickers() {
    return Column(
      children: [
        SizedBox(height: 16),
        _buildColorPicker('Primary Color', _primaryColor, (color) {
          setState(() {
            _primaryColor = color;
          });
        }),
        SizedBox(height: 12),
        _buildColorPicker('Accent Color', _accentColor, (color) {
          setState(() {
            _accentColor = color;
          });
        }),
      ],
    );
  }

  Widget _buildColorPicker(String title, Color color, ValueChanged<Color> onChanged) {
    return Row(
      children: [
        Expanded(
          child: Text(title, style: TextStyle(fontWeight: FontWeight.w500)),
        ),
        GestureDetector(
          onTap: () => _showColorPickerDialog(color, onChanged),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.grey.shade300),
            ),
          ),
        ),
      ],
    );
  }

  void _showColorPickerDialog(Color initialColor, ValueChanged<Color> onChanged) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Choose Color'),
        content: SingleChildScrollView(
          child: ColorPickerGrid(
            initialColor: initialColor,
            onColorSelected: onChanged,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _buildTypographySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Typography',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 16),
        Text(
          'Font Scale',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        Slider(
          value: _fontScale,
          min: 0.8,
          max: 1.5,
          divisions: 7,
          label: '${(_fontScale * 100).round()}%',
          onChanged: (value) {
            setState(() {
              _fontScale = value;
            });
          },
        ),
        SizedBox(height: 16),
        Text(
          'Font Family',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _fontFamily,
          items: _fontFamilies.map((font) {
            return DropdownMenuItem(
              value: font,
              child: Text(font, style: TextStyle(fontFamily: font == 'Default' ? null : font)),
            );
          }).toList(),
          onChanged: (value) {
            setState(() {
              _fontFamily = value!;
            });
          },
          decoration: InputDecoration(
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        SizedBox(height: 24),
        _buildTypographyPreview(),
      ],
    );
  }

  Widget _buildTypographyPreview() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Typography Preview', style: Theme.of(context).textTheme.headlineSmall),
            SizedBox(height: 8),
            Text('Headline Large', style: Theme.of(context).textTheme.headlineLarge),
            Text('Headline Medium', style: Theme.of(context).textTheme.headlineMedium),
            Text('Title Large', style: Theme.of(context).textTheme.titleLarge),
            Text('Body Large', style: Theme.of(context).textTheme.bodyLarge),
            Text('Body Medium', style: Theme.of(context).textTheme.bodyMedium),
            Text('Caption', style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _buildAppearanceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Appearance',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 16),
        SwitchListTile(
          title: Text('Material 3 Design'),
          subtitle: Text('Use latest Material Design system'),
          value: _useMaterial3,
          onChanged: (value) {
            setState(() {
              _useMaterial3 = value;
            });
          },
        ),
        SwitchListTile(
          title: Text('Compact Mode'),
          subtitle: Text('Reduce spacing and padding'),
          value: _compactMode,
          onChanged: (value) {
            setState(() {
              _compactMode = value;
            });
          },
        ),
        SwitchListTile(
          title: Text('High Contrast'),
          subtitle: Text('Increase contrast for better visibility'),
          value: _highContrast,
          onChanged: (value) {
            setState(() {
              _highContrast = value;
            });
          },
        ),
        SizedBox(height: 16),
        Text(
          'Border Radius',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        Slider(
          value: _borderRadius,
          min: 0,
          max: 24,
          divisions: 12,
          label: '${_borderRadius.round()}px',
          onChanged: (value) {
            setState(() {
              _borderRadius = value;
            });
          },
        ),
        SizedBox(height: 8),
        Text(
          'Elevation',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        Slider(
          value: _elevation,
          min: 0,
          max: 12,
          divisions: 12,
          label: '${_elevation.round()}px',
          onChanged: (value) {
            setState(() {
              _elevation = value;
            });
          },
        ),
      ],
    );
  }

  Widget _buildPreviewSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Live Preview',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        SizedBox(height: 16),
        Row(
          children: [
            Expanded(child: _buildThemePreview(false)),
            SizedBox(width: 16),
            Expanded(child: _buildThemePreview(true)),
          ],
        ),
        SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _resetToDefaults,
                icon: Icon(Icons.restore),
                label: Text('Reset to Defaults'),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
              ),
            ),
            SizedBox(width: 16),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: _applyTheme,
                icon: Icon(Icons.check),
                label: Text('Apply Theme'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildThemePreview(bool isDark) {
    final theme = _getCurrentTheme(isDark: isDark);
    
    return AnimatedBuilder(
      animation: _previewAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + (_previewAnimation.value * 0.02),
          child: Card(
            elevation: 8,
            child: Theme(
              data: theme,
              child: Container(
                height: 200,
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(_borderRadius),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isDark ? Icons.dark_mode : Icons.light_mode,
                          color: theme.colorScheme.primary,
                        ),
                        SizedBox(width: 8),
                        Text(
                          isDark ? 'Dark' : 'Light',
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      height: 32,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(_borderRadius / 2),
                      ),
                      child: Center(
                        child: Text(
                          'Primary Button',
                          style: TextStyle(
                            color: theme.colorScheme.onPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      height: 32,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondary,
                        borderRadius: BorderRadius.circular(_borderRadius / 2),
                      ),
                      child: Center(
                        child: Text(
                          'Secondary Button',
                          style: TextStyle(
                            color: theme.colorScheme.onSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 12),
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceVariant,
                          borderRadius: BorderRadius.circular(_borderRadius / 2),
                        ),
                        padding: EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sample Card',
                              style: theme.textTheme.titleSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                            SizedBox(height: 4),
                            Text(
                              'This is sample text content',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _resetToDefaults() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Reset Theme Settings'),
        content: Text('Are you sure you want to reset all theme settings to default values?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              setState(() {
                _themeMode = ThemeMode.system;
                _selectedColorScheme = 'Blue';
                _fontScale = 1.0;
                _fontFamily = 'Default';
                _useMaterial3 = true;
                _useCustomColors = false;
                _primaryColor = Colors.blue;
                _accentColor = Colors.blueAccent;
                _borderRadius = 12.0;
                _elevation = 4.0;
                _compactMode = false;
                _highContrast = false;
              });
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Theme settings reset to defaults'),
                  backgroundColor: Colors.green,
                ),
              );
            },
            child: Text('Reset'),
          ),
        ],
      ),
    );
  }

  void _applyTheme() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Theme applied successfully! Changes will take effect on app restart.'),
        backgroundColor: Colors.green,
        action: SnackBarAction(
          label: 'OK',
          onPressed: () {},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Theme Settings',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        bottom: TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).colorScheme.onPrimary,
          unselectedLabelColor: Theme.of(context).colorScheme.onPrimary.withOpacity(0.7),
          indicatorColor: Theme.of(context).colorScheme.onPrimary,
          tabs: [
            Tab(icon: Icon(Icons.palette), text: 'Colors'),
            Tab(icon: Icon(Icons.text_fields), text: 'Typography'),
            Tab(icon: Icon(Icons.tune), text: 'Appearance'),
            Tab(icon: Icon(Icons.preview), text: 'Preview'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: _buildThemeModeSection(),
          ),
          SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: _buildTypographySection(),
          ),
          SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: _buildAppearanceSection(),
          ),
          SingleChildScrollView(
            padding: EdgeInsets.all(16),
            child: _buildPreviewSection(),
          ),
        ],
      ),
    );
  }
}

class ColorPickerGrid extends StatelessWidget {
  final Color initialColor;
  final ValueChanged<Color> onColorSelected;

  const ColorPickerGrid({
    Key? key,
    required this.initialColor,
    required this.onColorSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final colors = [
      Colors.red, Colors.pink, Colors.purple, Colors.deepPurple,
      Colors.indigo, Colors.blue, Colors.lightBlue, Colors.cyan,
      Colors.teal, Colors.green, Colors.lightGreen, Colors.lime,
      Colors.yellow, Colors.amber, Colors.orange, Colors.deepOrange,
      Colors.brown, Colors.grey, Colors.blueGrey, Colors.black,
    ];

    return Container(
      width: 300,
      child: GridView.builder(
        shrinkWrap: true,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: colors.length,
        itemBuilder: (context, index) {
          final color = colors[index];
          final isSelected = color.value == initialColor.value;

          return GestureDetector(
            onTap: () => onColorSelected(color),
            child: Container(
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isSelected ? Colors.white : Colors.transparent,
                  width: 3,
                ),
              ),
              child: isSelected
                  ? Icon(Icons.check, color: Colors.white)
                  : null,
            ),
          );
        },
      ),
    );
  }
}