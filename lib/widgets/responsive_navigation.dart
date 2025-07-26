import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../services/responsive_service.dart';

class ResponsiveNavigation extends StatelessWidget {
  final Widget child;
  final String title;
  final List<NavigationItem>? navigationItems;
  final VoidCallback? onMenuTap;
  final Widget? floatingActionButton;

  const ResponsiveNavigation({
    Key? key,
    required this.child,
    required this.title,
    this.navigationItems,
    this.onMenuTap,
    this.floatingActionButton,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && ResponsiveService.isDesktop(context)) {
      return _buildWebLayout(context);
    } else {
      return _buildMobileLayout(context);
    }
  }

  Widget _buildWebLayout(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          // Side navigation for web
          if (navigationItems != null)
            Container(
              width: 250,
              color: Theme.of(context).primaryColor.withOpacity(0.1),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'CEMS',
                      style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView(
                      children: navigationItems!
                          .map((item) => _buildWebNavItem(context, item))
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
          // Main content
          Expanded(
            child: Column(
              children: [
                // Top bar for web
                Container(
                  height: 60,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).appBarTheme.backgroundColor,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      // User profile or settings can go here
                    ],
                  ),
                ),
                Expanded(
                  child: Container(
                    padding: ResponsiveService.getAdaptivePadding(context),
                    child: child,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        leading: onMenuTap != null
            ? IconButton(
                icon: const Icon(Icons.menu),
                onPressed: onMenuTap,
              )
            : null,
      ),
      body: Container(
        padding: ResponsiveService.getAdaptivePadding(context),
        child: child,
      ),
      floatingActionButton: floatingActionButton,
      drawer: navigationItems != null ? _buildMobileDrawer(context) : null,
    );
  }

  Widget _buildWebNavItem(BuildContext context, NavigationItem item) {
    return ListTile(
      leading: Icon(item.icon),
      title: Text(item.label),
      onTap: item.onTap,
      hoverColor: Theme.of(context).primaryColor.withOpacity(0.1),
    );
  }

  Widget _buildMobileDrawer(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          DrawerHeader(
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor,
            ),
            child: const Center(
              child: Text(
                'CEMS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              children: navigationItems!
                  .map((item) => ListTile(
                        leading: Icon(item.icon),
                        title: Text(item.label),
                        onTap: () {
                          Navigator.pop(context);
                          item.onTap();
                        },
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class NavigationItem {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  NavigationItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });
}