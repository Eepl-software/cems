import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import 'package:intl/intl.dart';

class MaterialCategoryPage extends StatefulWidget {
  final String categoryName;
  final String categoryDisplayName;
  final String categoryIcon;
  final Color categoryColor;

  const MaterialCategoryPage({
    Key? key,
    required this.categoryName,
    required this.categoryDisplayName,
    required this.categoryIcon,
    required this.categoryColor,
  }) : super(key: key);

  @override
  State<MaterialCategoryPage> createState() => _MaterialCategoryPageState();
}

class _MaterialCategoryPageState extends State<MaterialCategoryPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> materials = [];
  List<Map<String, dynamic>> transactions = [];
  List<Map<String, dynamic>> alerts = [];
  bool isLoading = true;
  String? error;
  Timer? _refreshTimer;
  IO.Socket? socket;

  final String baseUrl = 'http://54.146.215.18:3000';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _initializeSocket();
    _fetchCategoryData();
    _startRefreshTimer();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _refreshTimer?.cancel();
    socket?.disconnect();
    super.dispose();
  }

  void _initializeSocket() {
    try {
      socket = IO.io(baseUrl, {
        'transports': ['websocket', 'polling'],
        'autoConnect': false,
      });

      socket!.connect();

      socket!.on('connect', (_) {
        print('Connected to WebSocket server for ${widget.categoryName}');
        // Subscribe to category-specific updates
        socket!.emit('subscribe_to_materials', {'category': widget.categoryName});
      });

      socket!.on('material_${widget.categoryName}_updated', (data) {
        _fetchCategoryData();
      });

      socket!.on('material_transaction_added', (data) {
        if (data['category_name'] == widget.categoryName) {
          _fetchCategoryData();
        }
      });

      socket!.on('material_inventory_updated', (data) {
        if (data['category_name'] == widget.categoryName) {
          _fetchCategoryData();
        }
      });

      socket!.on('disconnect', (_) {
        print('Disconnected from WebSocket server');
      });

    } catch (e) {
      print('Socket initialization error: $e');
    }
  }

  void _startRefreshTimer() {
    _refreshTimer = Timer.periodic(const Duration(minutes: 2), (timer) {
      _fetchCategoryData();
    });
  }

  Future<void> _fetchCategoryData() async {
    await Future.wait([
      _fetchMaterials(),
      _fetchTransactions(),
      _fetchAlerts(),
    ]);
  }

  Future<void> _fetchMaterials() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/construction-materials/category/${widget.categoryName}'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() {
            materials = List<Map<String, dynamic>>.from(data['data']);
            isLoading = false;
            error = null;
          });
        }
      }
    } catch (e) {
      setState(() {
        error = 'Failed to load materials: $e';
        isLoading = false;
      });
    }
  }

  Future<void> _fetchTransactions() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/construction-materials/transactions?category_name=${widget.categoryName}&limit=20'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          setState(() {
            transactions = List<Map<String, dynamic>>.from(data['data']);
          });
        }
      }
    } catch (e) {
      print('Failed to load transactions: $e');
    }
  }

  Future<void> _fetchAlerts() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/construction-materials/alerts?is_active=true'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          final categoryAlerts = (data['data'] as List)
              .where((alert) => alert['category_name'] == widget.categoryDisplayName)
              .toList();
          setState(() {
            alerts = List<Map<String, dynamic>>.from(categoryAlerts);
          });
        }
      }
    } catch (e) {
      print('Failed to load alerts: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Text(widget.categoryIcon, style: const TextStyle(fontSize: 24)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.categoryDisplayName,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        backgroundColor: widget.categoryColor,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.inventory), text: 'Inventory'),
            Tab(icon: Icon(Icons.swap_horiz), text: 'Transactions'),
            Tab(icon: Icon(Icons.notification_important), text: 'Alerts'),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _showAddTransactionDialog(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchCategoryData,
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildInventoryTab(),
          _buildTransactionsTab(),
          _buildAlertsTab(),
        ],
      ),
    );
  }

  Widget _buildInventoryTab() {
    if (isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
            const SizedBox(height: 16),
            Text('Error: $error', style: TextStyle(color: Colors.red[600])),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _fetchCategoryData,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (materials.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No materials found',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'Add materials by recording transactions',
              style: TextStyle(color: Colors.grey[500]),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _showAddTransactionDialog(),
              icon: const Icon(Icons.add),
              label: const Text('Add Material'),
              style: ElevatedButton.styleFrom(backgroundColor: widget.categoryColor),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchCategoryData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: materials.length,
        itemBuilder: (context, index) {
          final material = materials[index];
          return _buildMaterialCard(material);
        },
      ),
    );
  }

  Widget _buildMaterialCard(Map<String, dynamic> material) {
    final currentStock = double.tryParse('${material['current_stock'] ?? 0}') ?? 0;
    final reservedStock = double.tryParse('${material['reserved_stock'] ?? 0}') ?? 0;
    final availableStock = currentStock - reservedStock;
    final unitPrice = double.tryParse('${material['unit_price'] ?? 0}') ?? 0;
    final totalValue = currentStock * unitPrice;
    final stockStatus = material['stock_status'] ?? 'ADEQUATE';

    Color statusColor;
    IconData statusIcon;
    switch (stockStatus) {
      case 'OUT':
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      case 'LOW':
        statusColor = Colors.orange;
        statusIcon = Icons.warning;
        break;
      default:
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
    }

    return Card(
      elevation: 4,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    material['material_name'] ?? 'Unknown Material',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withAlpha(51),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 16, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        stockStatus,
                        style: TextStyle(
                          color: statusColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStockInfo(
                    'Current Stock',
                    '${currentStock.toStringAsFixed(2)} ${material['unit'] ?? 'kg'}',
                    Icons.inventory,
                    widget.categoryColor,
                  ),
                ),
                Expanded(
                  child: _buildStockInfo(
                    'Available',
                    '${availableStock.toStringAsFixed(2)} ${material['unit'] ?? 'kg'}',
                    Icons.inventory_2,
                    Colors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildStockInfo(
                    'Unit Price',
                    '₹${unitPrice.toStringAsFixed(2)}',
                    Icons.currency_rupee,
                    Colors.green,
                  ),
                ),
                Expanded(
                  child: _buildStockInfo(
                    'Total Value',
                    '₹${totalValue.toStringAsFixed(2)}',
                    Icons.account_balance_wallet,
                    Colors.purple,
                  ),
                ),
              ],
            ),
            if (material['supplier_name'] != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.business, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    'Supplier: ${material['supplier_name']}',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ],
            if (material['location'] != null) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(Icons.location_on, size: 16, color: Colors.grey),
                  const SizedBox(width: 4),
                  Text(
                    'Location: ${material['location']}',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(
                  'Add Stock',
                  Icons.add,
                  Colors.green,
                  () => _showAddTransactionDialog(
                    materialName: material['material_name'],
                    transactionType: 'IN',
                  ),
                ),
                _buildActionButton(
                  'Remove Stock',
                  Icons.remove,
                  Colors.red,
                  () => _showAddTransactionDialog(
                    materialName: material['material_name'],
                    transactionType: 'OUT',
                  ),
                ),
                _buildActionButton(
                  'History',
                  Icons.history,
                  Colors.blue,
                  () => _showMaterialHistory(material['material_name']),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStockInfo(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: color.withAlpha(26),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 14,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onPressed) {
    return ElevatedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 16),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(0, 32),
      ),
    );
  }

  Widget _buildTransactionsTab() {
    if (transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.swap_horiz_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No transactions found',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchCategoryData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: transactions.length,
        itemBuilder: (context, index) {
          final transaction = transactions[index];
          return _buildTransactionCard(transaction);
        },
      ),
    );
  }

  Widget _buildTransactionCard(Map<String, dynamic> transaction) {
    final transactionType = transaction['transaction_type'] ?? 'IN';
    final quantity = double.tryParse('${transaction['quantity'] ?? 0}') ?? 0;
    final unitPrice = double.tryParse('${transaction['unit_price'] ?? 0}') ?? 0;
    final totalAmount = double.tryParse('${transaction['total_amount'] ?? 0}') ?? 0;
    final createdAt = DateTime.tryParse(transaction['created_at'] ?? '');

    Color typeColor = transactionType == 'IN' ? Colors.green : Colors.red;
    IconData typeIcon = transactionType == 'IN' ? Icons.input : Icons.output;

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: typeColor.withAlpha(51),
          child: Icon(typeIcon, color: typeColor),
        ),
        title: Text(
          transaction['material_name'] ?? 'Unknown Material',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${quantity.toStringAsFixed(2)} kg • ₹${totalAmount.toStringAsFixed(2)}'),
            if (transaction['vehicle_number'] != null)
              Text('Vehicle: ${transaction['vehicle_number']}'),
            if (createdAt != null)
              Text(DateFormat('MMM dd, yyyy HH:mm').format(createdAt)),
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: typeColor.withAlpha(51),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            transactionType,
            style: TextStyle(
              color: typeColor,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAlertsTab() {
    if (alerts.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.notifications_none, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No active alerts',
              style: TextStyle(fontSize: 18, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            Text(
              'All materials are within normal levels',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchCategoryData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: alerts.length,
        itemBuilder: (context, index) {
          final alert = alerts[index];
          return _buildAlertCard(alert);
        },
      ),
    );
  }

  Widget _buildAlertCard(Map<String, dynamic> alert) {
    final severity = alert['severity'] ?? 'MEDIUM';
    final alertType = alert['alert_type'] ?? 'LOW_STOCK';
    
    Color alertColor;
    IconData alertIcon;
    
    switch (severity) {
      case 'CRITICAL':
        alertColor = Colors.red;
        alertIcon = Icons.error;
        break;
      case 'HIGH':
        alertColor = Colors.orange;
        alertIcon = Icons.warning;
        break;
      default:
        alertColor = Colors.blue;
        alertIcon = Icons.info;
    }

    return Card(
      elevation: 3,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(alertIcon, color: alertColor, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    alert['title'] ?? '',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: alertColor.withAlpha(51),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    severity,
                    style: TextStyle(
                      color: alertColor,
                      fontWeight: FontWeight.bold,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              alert['message'] ?? '',
              style: TextStyle(color: Colors.grey[700]),
            ),
            if (alert['threshold_value'] != null && alert['current_value'] != null) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    'Threshold: ${alert['threshold_value']}',
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Current: ${alert['current_value']}',
                    style: TextStyle(color: alertColor, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _acknowledgeAlert(alert['id']),
                child: const Text('Acknowledge'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAddTransactionDialog({String? materialName, String? transactionType}) {
    final _formKey = GlobalKey<FormState>();
    String _materialName = materialName ?? '';
    String _transactionType = transactionType ?? 'IN';
    double _quantity = 0;
    double _unitPrice = 0;
    String _vehicleNumber = '';
    String _driverName = '';
    String _supplierName = '';
    String _notes = '';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Add ${_transactionType == 'IN' ? 'Stock Receipt' : 'Stock Issue'}'),
        content: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  initialValue: _materialName,
                  decoration: const InputDecoration(
                    labelText: 'Material Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => value?.isEmpty == true ? 'Required' : null,
                  onSaved: (value) => _materialName = value ?? '',
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _transactionType,
                  decoration: const InputDecoration(
                    labelText: 'Transaction Type',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'IN', child: Text('Stock IN (Receipt)')),
                    DropdownMenuItem(value: 'OUT', child: Text('Stock OUT (Issue)')),
                  ],
                  onChanged: (value) => _transactionType = value ?? 'IN',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Quantity',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  validator: (value) {
                    if (value?.isEmpty == true) return 'Required';
                    if (double.tryParse(value!) == null) return 'Invalid number';
                    return null;
                  },
                  onSaved: (value) => _quantity = double.tryParse(value!) ?? 0,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Unit Price',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.number,
                  onSaved: (value) => _unitPrice = double.tryParse(value!) ?? 0,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Vehicle Number (Optional)',
                    border: OutlineInputBorder(),
                  ),
                  onSaved: (value) => _vehicleNumber = value ?? '',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Driver Name (Optional)',
                    border: OutlineInputBorder(),
                  ),
                  onSaved: (value) => _driverName = value ?? '',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Supplier Name (Optional)',
                    border: OutlineInputBorder(),
                  ),
                  onSaved: (value) => _supplierName = value ?? '',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  decoration: const InputDecoration(
                    labelText: 'Notes (Optional)',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                  onSaved: (value) => _notes = value ?? '',
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => _submitTransaction(_formKey, _materialName, _transactionType, 
                _quantity, _unitPrice, _vehicleNumber, _driverName, _supplierName, _notes),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  void _submitTransaction(
    GlobalKey<FormState> formKey,
    String materialName,
    String transactionType,
    double quantity,
    double unitPrice,
    String vehicleNumber,
    String driverName,
    String supplierName,
    String notes,
  ) async {
    if (!formKey.currentState!.validate()) return;
    
    formKey.currentState!.save();

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/api/construction-materials/transaction'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'category_name': widget.categoryName,
          'material_name': materialName,
          'transaction_type': transactionType,
          'quantity': quantity,
          'unit_price': unitPrice,
          'vehicle_number': vehicleNumber,
          'driver_name': driverName,
          'supplier_name': supplierName,
          'notes': notes,
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success']) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Transaction recorded successfully'),
              backgroundColor: Colors.green,
            ),
          );
          _fetchCategoryData();
        } else {
          throw Exception(data['error'] ?? 'Failed to record transaction');
        }
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _showMaterialHistory(String materialName) {
    // Navigate to detailed material history page
    // This would be implemented as a separate page
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('History for $materialName'),
        action: SnackBarAction(
          label: 'OK',
          onPressed: () {},
        ),
      ),
    );
  }

  void _acknowledgeAlert(int alertId) async {
    try {
      final response = await http.patch(
        Uri.parse('$baseUrl/api/construction-materials/alerts/$alertId/acknowledge'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({'acknowledged_by': 'current_user'}),
      );

      if (response.statusCode == 200) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Alert acknowledged'),
            backgroundColor: Colors.green,
          ),
        );
        _fetchCategoryData();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error acknowledging alert: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}