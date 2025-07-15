import 'package:flutter/material.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:web_socket_channel/io.dart';
import 'dart:convert';
import 'dart:async';

enum AlertType { info, warning, critical, success }
enum ConnectionStatus { disconnected, connecting, connected, error }

class AlertMessage {
  final String message;
  final AlertType type;
  final DateTime timestamp;
  final bool sent;

  AlertMessage({
    required this.message,
    required this.type,
    required this.timestamp,
    this.sent = false,
  });
}

class SuperuserAlertPage extends StatefulWidget {
  @override
  _SuperuserAlertPageState createState() => _SuperuserAlertPageState();
}

class _SuperuserAlertPageState extends State<SuperuserAlertPage>
    with TickerProviderStateMixin {
  WebSocketChannel? channel;
  final TextEditingController _messageController = TextEditingController();
  final List<AlertMessage> _messageHistory = [];
  ConnectionStatus _connectionStatus = ConnectionStatus.disconnected;
  AlertType _selectedAlertType = AlertType.info;
  bool _isLoading = false;
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  final int _maxReconnectAttempts = 5;
  
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;

  // WebSocket URL - replace with your actual URL
  final String _websocketUrl = 'ws://your-websocket-url:8080';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: Duration(seconds: 1),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.8, end: 1.2).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    _connectWebSocket();
  }

  void _connectWebSocket() {
    setState(() {
      _connectionStatus = ConnectionStatus.connecting;
    });

    try {
      channel = IOWebSocketChannel.connect(_websocketUrl);
      
      channel!.stream.listen(
        (data) {
          setState(() {
            _connectionStatus = ConnectionStatus.connected;
            _reconnectAttempts = 0;
          });
          _pulseController.stop();
          _showSnackBar('Connected to server', Colors.green);
        },
        onError: (error) {
          _handleConnectionError();
        },
        onDone: () {
          _handleConnectionError();
        },
      );
    } catch (e) {
      _handleConnectionError();
    }
  }

  void _handleConnectionError() {
    setState(() {
      _connectionStatus = ConnectionStatus.error;
    });
    _pulseController.repeat(reverse: true);
    
    if (_reconnectAttempts < _maxReconnectAttempts) {
      _reconnectAttempts++;
      _showSnackBar(
        'Connection failed. Retrying... (${_reconnectAttempts}/${_maxReconnectAttempts})',
        Colors.orange,
      );
      
      _reconnectTimer = Timer(Duration(seconds: 3), () {
        _connectWebSocket();
      });
    } else {
      _showSnackBar('Connection failed. Max retry attempts reached.', Colors.red);
    }
  }

  void _sendMessage() async {
    if (_messageController.text.trim().isEmpty) {
      _showSnackBar('Please enter a message', Colors.orange);
      return;
    }

    if (_connectionStatus != ConnectionStatus.connected) {
      _showSnackBar('Not connected to server', Colors.red);
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final alertData = {
        'message': _messageController.text.trim(),
        'type': _selectedAlertType.toString().split('.').last,
        'timestamp': DateTime.now().toIso8601String(),
        'sender': 'superuser',
      };

      channel!.sink.add(jsonEncode(alertData));

      final sentMessage = AlertMessage(
        message: _messageController.text.trim(),
        type: _selectedAlertType,
        timestamp: DateTime.now(),
        sent: true,
      );

      setState(() {
        _messageHistory.insert(0, sentMessage);
        _messageController.clear();
        _isLoading = false;
      });

      _showSnackBar('Alert sent successfully!', Colors.green);
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showSnackBar('Failed to send alert: $e', Colors.red);
    }
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        duration: Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Widget _buildConnectionIndicator() {
    Color color;
    IconData icon;
    String status;

    switch (_connectionStatus) {
      case ConnectionStatus.connected:
        color = Colors.green;
        icon = Icons.wifi;
        status = 'Connected';
        break;
      case ConnectionStatus.connecting:
        color = Colors.orange;
        icon = Icons.wifi_find;
        status = 'Connecting...';
        break;
      case ConnectionStatus.error:
        color = Colors.red;
        icon = Icons.wifi_off;
        status = 'Disconnected';
        break;
      default:
        color = Colors.grey;
        icon = Icons.wifi_off;
        status = 'Disconnected';
    }

    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _connectionStatus == ConnectionStatus.error 
              ? _pulseAnimation.value 
              : 1.0,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: color, size: 16),
                SizedBox(width: 4),
                Text(
                  status,
                  style: TextStyle(
                    color: color,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildAlertTypeSelector() {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: AlertType.values.map((type) {
          final isSelected = _selectedAlertType == type;
          Color color = _getAlertTypeColor(type);
          
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedAlertType = type;
                });
              },
              child: Container(
                padding: EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Icon(
                      _getAlertTypeIcon(type),
                      color: isSelected ? color : Colors.grey,
                      size: 20,
                    ),
                    SizedBox(height: 4),
                    Text(
                      type.toString().split('.').last.toUpperCase(),
                      style: TextStyle(
                        color: isSelected ? color : Colors.grey,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Color _getAlertTypeColor(AlertType type) {
    switch (type) {
      case AlertType.info:
        return Colors.blue;
      case AlertType.warning:
        return Colors.orange;
      case AlertType.critical:
        return Colors.red;
      case AlertType.success:
        return Colors.green;
    }
  }

  IconData _getAlertTypeIcon(AlertType type) {
    switch (type) {
      case AlertType.info:
        return Icons.info;
      case AlertType.warning:
        return Icons.warning;
      case AlertType.critical:
        return Icons.error;
      case AlertType.success:
        return Icons.check_circle;
    }
  }

  Widget _buildMessageHistory() {
    if (_messageHistory.isEmpty) {
      return Container(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            Icon(Icons.history, size: 48, color: Colors.grey.shade400),
            SizedBox(height: 8),
            Text(
              'No messages sent yet',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: NeverScrollableScrollPhysics(),
      itemCount: _messageHistory.length,
      itemBuilder: (context, index) {
        final message = _messageHistory[index];
        final color = _getAlertTypeColor(message.type);
        
        return Container(
          margin: EdgeInsets.only(bottom: 8),
          padding: EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withOpacity(0.05),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    _getAlertTypeIcon(message.type),
                    color: color,
                    size: 16,
                  ),
                  SizedBox(width: 6),
                  Text(
                    message.type.toString().split('.').last.toUpperCase(),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  Spacer(),
                  Text(
                    '${message.timestamp.hour.toString().padLeft(2, '0')}:${message.timestamp.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              SizedBox(height: 6),
              Text(
                message.message,
                style: TextStyle(
                  color: Colors.grey.shade800,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _reconnectTimer?.cancel();
    channel?.sink.close();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Superuser Alert Center',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(child: _buildConnectionIndicator()),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Alert Type Selector
            Text(
              'Alert Type',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            SizedBox(height: 8),
            _buildAlertTypeSelector(),
            SizedBox(height: 20),

            // Message Input
            Text(
              'Alert Message',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            SizedBox(height: 8),
            TextField(
              controller: _messageController,
              maxLines: 3,
              decoration: InputDecoration(
                hintText: 'Enter your alert message...',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(15),
                  borderSide: BorderSide(color: Colors.teal, width: 2),
                ),
                contentPadding: EdgeInsets.all(16),
              ),
            ),
            SizedBox(height: 20),

            // Send Button
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _connectionStatus == ConnectionStatus.connected && !_isLoading
                    ? _sendMessage
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  elevation: 3,
                ),
                child: _isLoading
                    ? SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.send, color: Colors.white),
                          SizedBox(width: 8),
                          Text(
                            'Send Alert',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            SizedBox(height: 30),

            // Message History
            Row(
              children: [
                Text(
                  'Message History',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey.shade700,
                  ),
                ),
                Spacer(),
                if (_messageHistory.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      setState(() {
                        _messageHistory.clear();
                      });
                    },
                    child: Text('Clear All'),
                  ),
              ],
            ),
            SizedBox(height: 12),
            _buildMessageHistory(),
          ],
        ),
      ),
      floatingActionButton: _connectionStatus == ConnectionStatus.error
          ? FloatingActionButton(
              onPressed: _connectWebSocket,
              backgroundColor: Colors.teal,
              child: Icon(Icons.refresh, color: Colors.white),
              tooltip: 'Retry Connection',
            )
          : null,
    );
  }
}