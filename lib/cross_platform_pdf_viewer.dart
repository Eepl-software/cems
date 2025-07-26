import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdfx/pdfx.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import './utils/platform_utils.dart';

class CrossPlatformPDFViewer extends StatefulWidget {
  final String filePath;
  final String title;
  final bool isAsset;

  const CrossPlatformPDFViewer({
    super.key,
    required this.filePath,
    required this.title,
    this.isAsset = false,
  });

  @override
  State<CrossPlatformPDFViewer> createState() => _CrossPlatformPDFViewerState();
}

class _CrossPlatformPDFViewerState extends State<CrossPlatformPDFViewer> {
  PdfController? _pdfController;
  int _currentPage = 1;
  int _totalPages = 0;
  bool _isLoading = true;
  String? _error;
  bool _showSidebar = false;
  bool _isFullScreen = false;
  final TextEditingController _pageController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  
  // Zoom and pan
  double _scale = 1.0;
  static const double _minScale = 0.5;
  static const double _maxScale = 5.0;

  // Platform-specific settings
  late double _toolbarHeight;
  late double _defaultPadding;
  late double _iconSize;

  @override
  void initState() {
    super.initState();
    _initializePlatformSettings();
    _loadPdf();
    _setupKeyboardShortcuts();
  }

  void _initializePlatformSettings() {
    _toolbarHeight = PlatformUtils.getToolbarHeight();
    _defaultPadding = PlatformUtils.getDefaultPadding();
    _iconSize = PlatformUtils.getIconSize();
  }

  void _setupKeyboardShortcuts() {
    if (PlatformUtils.supportsKeyboardShortcuts) {
      // Add keyboard shortcuts for desktop platforms
      // This would typically be done with RawKeyboardListener or Shortcuts widget
    }
  }

  Future<void> _loadPdf() async {
    try {
      setState(() {
        _isLoading = true;
        _error = null;
      });

      PdfDocument document;
      
      if (widget.isAsset) {
        // Load from assets (works on all platforms)
        document = await PdfDocument.openAsset(widget.filePath);
      } else if (widget.filePath.startsWith('http://') || widget.filePath.startsWith('https://')) {
        // Load from URL (S3 or web URL)
        print('Loading PDF from URL: ${widget.filePath}');
        final response = await http.get(Uri.parse(widget.filePath));
        if (response.statusCode == 200) {
          document = await PdfDocument.openData(response.bodyBytes);
        } else {
          throw Exception('Failed to load PDF from URL: ${response.statusCode}');
        }
      } else {
        // Load from file path
        if (PlatformUtils.isWeb) {
          // For web, we might need to handle differently
          // This is a simplified approach - you might need to load via HTTP
          document = await PdfDocument.openAsset(widget.filePath);
        } else {
          // For native platforms
          document = await PdfDocument.openFile(widget.filePath);
        }
      }

      _pdfController = PdfController(
        document: Future.value(document),
        initialPage: 1,
      );
      
      _totalPages = document.pagesCount;
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load PDF: ${e.toString()}';
        _isLoading = false;
      });
    }
  }

  Future<void> _goToPage(int page) async {
    if (_pdfController != null && page >= 1 && page <= _totalPages) {
      await _pdfController!.animateToPage(
        page,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
      setState(() {
        _currentPage = page;
      });
    }
  }

  void _zoomIn() {
    if (_scale < _maxScale) {
      setState(() {
        _scale = (_scale * 1.2).clamp(_minScale, _maxScale);
      });
    }
  }

  void _zoomOut() {
    if (_scale > _minScale) {
      setState(() {
        _scale = (_scale / 1.2).clamp(_minScale, _maxScale);
      });
    }
  }

  void _resetZoom() {
    setState(() {
      _scale = 1.0;
    });
  }

  void _toggleFullScreen() {
    setState(() {
      _isFullScreen = !_isFullScreen;
    });
  }

  void _toggleSidebar() {
    setState(() {
      _showSidebar = !_showSidebar;
    });
  }

  Future<void> _shareDocument() async {
    if (PlatformUtils.supportsShareSheet && !widget.isAsset) {
      try {
        await Share.shareXFiles([XFile(widget.filePath)], text: widget.title);
      } catch (e) {
        _showSnackBar('Sharing not available on this platform');
      }
    } else {
      _showSnackBar('Sharing not available for this document');
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  void _showPageJumpDialog() {
    _pageController.text = _currentPage.toString();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Go to Page'),
        content: TextField(
          controller: _pageController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'Page number (1-$_totalPages)',
            border: const OutlineInputBorder(),
          ),
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final page = int.tryParse(_pageController.text);
              if (page != null && page >= 1 && page <= _totalPages) {
                _goToPage(page);
                Navigator.pop(context);
              }
            },
            child: const Text('Go'),
          ),
        ],
      ),
    );
  }

  Widget _buildResponsiveToolbar(double screenWidth) {
    final isCompact = screenWidth.isMobileWidth;
    
    return Container(
      height: _toolbarHeight,
      decoration: BoxDecoration(
        color: const Color.fromARGB(255, 43, 171, 150).withOpacity(0.1),
        border: const Border(bottom: BorderSide(color: Colors.grey)),
      ),
      child: isCompact ? _buildCompactToolbar() : _buildFullToolbar(),
    );
  }

  Widget _buildCompactToolbar() {
    return Row(
      children: [
        IconButton(
          onPressed: _currentPage > 1 ? () => _goToPage(_currentPage - 1) : null,
          icon: Icon(Icons.navigate_before, size: _iconSize),
          tooltip: 'Previous page',
        ),
        Expanded(
          child: GestureDetector(
            onTap: _showPageJumpDialog,
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: _defaultPadding / 2, vertical: 8),
              decoration: BoxDecoration(
                border: Border.all(color: const Color.fromARGB(255, 43, 171, 150)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '$_currentPage / $_totalPages',
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  color: Color.fromARGB(255, 43, 171, 150),
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: _currentPage < _totalPages ? () => _goToPage(_currentPage + 1) : null,
          icon: Icon(Icons.navigate_next, size: _iconSize),
          tooltip: 'Next page',
        ),
        PopupMenuButton<String>(
          icon: Icon(Icons.more_vert, size: _iconSize),
          onSelected: _handleMenuSelection,
          itemBuilder: (context) => [
            const PopupMenuItem(value: 'zoom_in', child: Text('Zoom In')),
            const PopupMenuItem(value: 'zoom_out', child: Text('Zoom Out')),
            const PopupMenuItem(value: 'reset_zoom', child: Text('Reset Zoom')),
            const PopupMenuItem(value: 'fullscreen', child: Text('Full Screen')),
            if (!PlatformUtils.isMobile)
              const PopupMenuItem(value: 'sidebar', child: Text('Toggle Sidebar')),
            if (PlatformUtils.supportsShareSheet)
              const PopupMenuItem(value: 'share', child: Text('Share')),
          ],
        ),
      ],
    );
  }

  Widget _buildFullToolbar() {
    return Row(
      children: [
        // Navigation controls
        IconButton(
          onPressed: _currentPage > 1 ? () => _goToPage(_currentPage - 1) : null,
          icon: Icon(Icons.navigate_before, size: _iconSize),
          tooltip: 'Previous page',
        ),
        GestureDetector(
          onTap: _showPageJumpDialog,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: _defaultPadding, vertical: 8),
            decoration: BoxDecoration(
              border: Border.all(color: const Color.fromARGB(255, 43, 171, 150)),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$_currentPage / $_totalPages',
              style: const TextStyle(
                fontWeight: FontWeight.w500,
                color: Color.fromARGB(255, 43, 171, 150),
              ),
            ),
          ),
        ),
        IconButton(
          onPressed: _currentPage < _totalPages ? () => _goToPage(_currentPage + 1) : null,
          icon: Icon(Icons.navigate_next, size: _iconSize),
          tooltip: 'Next page',
        ),
        
        const VerticalDivider(),
        
        // Zoom controls
        IconButton(
          onPressed: _zoomOut,
          icon: Icon(Icons.zoom_out, size: _iconSize),
          tooltip: 'Zoom out',
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: _defaultPadding / 2),
          child: Text(
            '${(_scale * 100).round()}%',
            style: const TextStyle(
              color: Color.fromARGB(255, 43, 171, 150),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        IconButton(
          onPressed: _zoomIn,
          icon: Icon(Icons.zoom_in, size: _iconSize),
          tooltip: 'Zoom in',
        ),
        IconButton(
          onPressed: _resetZoom,
          icon: Icon(Icons.zoom_out_map, size: _iconSize),
          tooltip: 'Reset zoom',
        ),
        
        const VerticalDivider(),
        
        // View controls
        if (!PlatformUtils.isMobile) ...[
          IconButton(
            onPressed: _toggleSidebar,
            icon: Icon(_showSidebar ? Icons.view_list : Icons.view_sidebar, size: _iconSize),
            tooltip: 'Toggle sidebar',
          ),
        ],
        IconButton(
          onPressed: _toggleFullScreen,
          icon: Icon(_isFullScreen ? Icons.fullscreen_exit : Icons.fullscreen, size: _iconSize),
          tooltip: 'Toggle full screen',
        ),
        
        const Spacer(),
        
        // Search (desktop and web only)
        if (PlatformUtils.isDesktop || PlatformUtils.isWeb) ...[
          SizedBox(
            width: 200,
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 8),
                isDense: true,
              ),
              onSubmitted: (value) => _showSnackBar('Search feature coming soon!'),
            ),
          ),
          SizedBox(width: _defaultPadding),
        ],
        
        // Share button (mobile only)
        if (PlatformUtils.supportsShareSheet) ...[
          IconButton(
            onPressed: _shareDocument,
            icon: Icon(Icons.share, size: _iconSize),
            tooltip: 'Share document',
          ),
        ],
      ],
    );
  }

  void _handleMenuSelection(String value) {
    switch (value) {
      case 'zoom_in':
        _zoomIn();
        break;
      case 'zoom_out':
        _zoomOut();
        break;
      case 'reset_zoom':
        _resetZoom();
        break;
      case 'fullscreen':
        _toggleFullScreen();
        break;
      case 'sidebar':
        _toggleSidebar();
        break;
      case 'share':
        _shareDocument();
        break;
    }
  }

  Widget _buildSidebar() {
    if (_pdfController == null || !_showSidebar || PlatformUtils.isMobile) {
      return const SizedBox.shrink();
    }
    
    return Container(
      width: 250,
      decoration: const BoxDecoration(
        border: Border(right: BorderSide(color: Colors.grey)),
        color: Colors.white,
      ),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(_defaultPadding / 2),
            decoration: BoxDecoration(
              color: const Color.fromARGB(255, 43, 171, 150).withOpacity(0.1),
              border: const Border(bottom: BorderSide(color: Colors.grey)),
            ),
            child: Row(
              children: [
                Icon(Icons.photo_library, 
                     size: _iconSize, 
                     color: const Color.fromARGB(255, 43, 171, 150)),
                SizedBox(width: _defaultPadding / 2),
                const Text(
                  'Pages', 
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Color.fromARGB(255, 43, 171, 150),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _totalPages,
              itemBuilder: (context, index) {
                final page = index + 1;
                return Container(
                  margin: EdgeInsets.all(_defaultPadding / 4),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: page == _currentPage 
                          ? const Color.fromARGB(255, 43, 171, 150)
                          : Colors.grey,
                      width: page == _currentPage ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(4),
                    color: page == _currentPage 
                        ? const Color.fromARGB(255, 43, 171, 150).withOpacity(0.1)
                        : null,
                  ),
                  child: ListTile(
                    dense: true,
                    leading: Container(
                      width: 40,
                      height: 50,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        border: Border.all(color: Colors.grey),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Center(
                        child: Text(
                          '$page',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    title: Text(
                      'Page $page',
                      style: TextStyle(
                        color: page == _currentPage 
                            ? const Color.fromARGB(255, 43, 171, 150)
                            : null,
                        fontWeight: page == _currentPage 
                            ? FontWeight.bold 
                            : null,
                      ),
                    ),
                    onTap: () => _goToPage(page),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPdfViewer() {
    if (_pdfController == null) return const SizedBox.shrink();

    return Expanded(
      child: InteractiveViewer(
        minScale: _minScale,
        maxScale: _maxScale,
        scaleEnabled: true,
        panEnabled: true,
        child: PdfView(
          controller: _pdfController!,
          onPageChanged: (page) {
            setState(() {
              _currentPage = page;
            });
          },
          scrollDirection: Axis.vertical,
          physics: const BouncingScrollPhysics(),
        ),
      ),
    );
  }

  Widget? _buildFloatingActionButton(double screenWidth) {
    if (_isFullScreen) {
      return SpeedDial(
        icon: Icons.menu,
        activeIcon: Icons.close,
        backgroundColor: const Color.fromARGB(255, 43, 171, 150),
        children: [
          SpeedDialChild(
            child: const Icon(Icons.fullscreen_exit, color: Colors.white),
            label: 'Exit Full Screen',
            backgroundColor: const Color.fromARGB(255, 43, 171, 150),
            onTap: _toggleFullScreen,
          ),
          SpeedDialChild(
            child: const Icon(Icons.navigate_before, color: Colors.white),
            label: 'Previous Page',
            backgroundColor: const Color.fromARGB(255, 43, 171, 150),
            onTap: _currentPage > 1 ? () => _goToPage(_currentPage - 1) : null,
          ),
          SpeedDialChild(
            child: const Icon(Icons.navigate_next, color: Colors.white),
            label: 'Next Page',
            backgroundColor: const Color.fromARGB(255, 43, 171, 150),
            onTap: _currentPage < _totalPages ? () => _goToPage(_currentPage + 1) : null,
          ),
          SpeedDialChild(
            child: const Icon(Icons.zoom_in, color: Colors.white),
            label: 'Zoom In',
            backgroundColor: const Color.fromARGB(255, 43, 171, 150),
            onTap: _zoomIn,
          ),
          SpeedDialChild(
            child: const Icon(Icons.zoom_out, color: Colors.white),
            label: 'Zoom Out',
            backgroundColor: const Color.fromARGB(255, 43, 171, 150),
            onTap: _zoomOut,
          ),
        ],
      );
    }

    if (screenWidth.isMobileWidth) {
      return FloatingActionButton.extended(
        onPressed: _showQuickActions,
        backgroundColor: const Color.fromARGB(255, 43, 171, 150),
        foregroundColor: Colors.white,
        label: Text('$_currentPage/$_totalPages'),
        icon: const Icon(Icons.picture_as_pdf),
      );
    }

    return null;
  }

  void _showQuickActions() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: EdgeInsets.all(_defaultPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Quick Actions',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: _defaultPadding),
            Wrap(
              spacing: _defaultPadding,
              runSpacing: _defaultPadding,
              children: [
                _buildQuickActionButton(
                  icon: Icons.first_page,
                  label: 'First',
                  onTap: () {
                    Navigator.pop(context);
                    _goToPage(1);
                  },
                ),
                _buildQuickActionButton(
                  icon: Icons.last_page,
                  label: 'Last',
                  onTap: () {
                    Navigator.pop(context);
                    _goToPage(_totalPages);
                  },
                ),
                _buildQuickActionButton(
                  icon: Icons.zoom_out_map,
                  label: 'Reset',
                  onTap: () {
                    Navigator.pop(context);
                    _resetZoom();
                  },
                ),
                if (PlatformUtils.supportsShareSheet)
                  _buildQuickActionButton(
                    icon: Icons.share,
                    label: 'Share',
                    onTap: () {
                      Navigator.pop(context);
                      _shareDocument();
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          vertical: _defaultPadding * 0.75, 
          horizontal: _defaultPadding
        ),
        decoration: BoxDecoration(
          color: const Color.fromARGB(255, 43, 171, 150),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: _iconSize),
            SizedBox(height: _defaultPadding / 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = constraints.maxWidth;
        
        return Scaffold(
          appBar: _isFullScreen ? null : AppBar(
            title: Text(
              widget.title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            backgroundColor: const Color.fromARGB(255, 43, 171, 150),
            foregroundColor: Colors.white,
            elevation: 2,
            actions: [
              if (PlatformUtils.isDesktop) ...[
                IconButton(
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Document Info'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Title: ${widget.title}'),
                            Text('Platform: ${PlatformUtils.platformName}'),
                            Text('Pages: $_totalPages'),
                            Text('Current Page: $_currentPage'),
                            Text('Zoom: ${(_scale * 100).round()}%'),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Close'),
                          ),
                        ],
                      ),
                    );
                  },
                  icon: const Icon(Icons.info_outline),
                  tooltip: 'Document info',
                ),
              ],
            ],
          ),
          body: _isLoading
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(
                        color: Color.fromARGB(255, 43, 171, 150),
                      ),
                      SizedBox(height: _defaultPadding),
                      Text('Loading PDF for ${PlatformUtils.platformName}...'),
                    ],
                  ),
                )
              : _error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, size: 64, color: Colors.red),
                          SizedBox(height: _defaultPadding),
                          Text(_error!, textAlign: TextAlign.center),
                          SizedBox(height: _defaultPadding),
                          ElevatedButton(
                            onPressed: _loadPdf,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color.fromARGB(255, 43, 171, 150),
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        if (!_isFullScreen) _buildResponsiveToolbar(screenWidth),
                        Expanded(
                          child: Row(
                            children: [
                              _buildSidebar(),
                              _buildPdfViewer(),
                            ],
                          ),
                        ),
                      ],
                    ),
          floatingActionButton: _buildFloatingActionButton(screenWidth),
        );
      },
    );
  }

  @override
  void dispose() {
    _pdfController?.dispose();
    _pageController.dispose();
    _searchController.dispose();
    super.dispose();
  }
}