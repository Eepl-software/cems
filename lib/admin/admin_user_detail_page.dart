// admin_user_detail_page.dart
import 'package:flutter/material.dart';
import 'dart:async';

import 'package:namer_app/services/admin_service.dart' as admin_service;

class AdminUserDetailPage extends StatefulWidget {
  final AdminUser? user;
  final bool isCreateMode;

  const AdminUserDetailPage({
    Key? key,
    this.user,
    this.isCreateMode = false,
  }) : super(key: key);

  @override
  State<AdminUserDetailPage> createState() => _AdminUserDetailPageState();
}

class _AdminUserDetailPageState extends State<AdminUserDetailPage>
    with TickerProviderStateMixin {
  late TabController _tabController;
  late admin_service.AdminService _adminService;
  
  // Form controllers
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _companyController = TextEditingController();
  final _designationController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  // State variables
  bool _isLoading = false;
  bool _isEditing = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  
  // User data
  AdminUser? _currentUser;
  List<AdminActivity> _userActivities = [];
  Map<String, dynamic> _userStats = {};
  
  // Permissions
  List<String> _selectedPermissions = [];
  bool _isActive = true;
  String _selectedRole = 'user';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _adminService = admin_service.AdminService(token: 'your-admin-token'); // Get from auth service
    
    if (widget.user != null) {
      _currentUser = widget.user;
      _loadUserData();
    } else {
      _isEditing = true;
    }
    
    if (widget.isCreateMode) {
      _isEditing = true;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _companyController.dispose();
    _designationController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _loadUserData() {
    if (_currentUser != null) {
      _usernameController.text = _currentUser!.username;
      _emailController.text = _currentUser!.email ?? '';
      _phoneController.text = _currentUser!.phone ?? '';
      _companyController.text = _currentUser!.company ?? '';
      _designationController.text = _currentUser!.designation ?? '';
      _selectedRole = _currentUser!.designation ?? 'user';
      _selectedPermissions = List.from(_currentUser!.permissions);
      _isActive = _currentUser!.isActive ?? true;
      
      _loadUserActivities();
      _loadUserStats();
    }
  }

  Future<void> _loadUserActivities() async {
    if (_currentUser?.id == null) return;
    
    try {
      setState(() => _isLoading = true);
      
      // Simulate loading user activities
      await Future.delayed(const Duration(seconds: 1));
      
      _userActivities = [
        AdminActivity(
          type: 'login',
          description: 'User logged in from mobile app',
          timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        ),
        AdminActivity(
          type: 'action',
          description: 'Updated water consumption data',
          timestamp: DateTime.now().subtract(const Duration(hours: 5)),
        ),
        AdminActivity(
          type: 'login',
          description: 'User logged in from web portal',
          timestamp: DateTime.now().subtract(const Duration(days: 1)),
        ),
      ];
      
      setState(() => _isLoading = false);
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      _showErrorSnackBar('Failed to load user activities: $e');
    }
  }

  Future<void> _loadUserStats() async {
    if (_currentUser?.id == null) return;
    
    try {
      // Simulate loading user statistics
      await Future.delayed(const Duration(milliseconds: 500));
      
      _userStats = {
        'totalLogins': 245,
        'lastLogin': DateTime.now().subtract(const Duration(hours: 2)),
        'dataEntered': 156,
        'reportsGenerated': 23,
        'averageSessionTime': '15 minutes',
        'accountAge': DateTime.now().difference(_currentUser!.createdAt ?? DateTime.now()).inDays,
      };
      
      setState(() {});
    } catch (e) {
      print('Error loading user stats: $e');
    }
  }

  Future<void> _saveUser() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true;
    });
    
    try {
      final userData = {
        'username': _usernameController.text.trim(),
        'email': _emailController.text.trim(),
        'phone': _phoneController.text.trim(),
        'company': _companyController.text.trim(),
        'designation': _designationController.text.trim(),
        'role': _selectedRole,
        'permissions': _selectedPermissions,
        'isActive': _isActive,
      };
      
      if (widget.isCreateMode || _currentUser == null) {
        // Add password for new users
        userData['password'] = _passwordController.text;
        
        await _adminService.createUser(userData);
        if (mounted) {
          _showSuccessSnackBar('User created successfully');
        }
      } else {
        // Update existing user
        await _adminService.updateUser(_currentUser!.id!, userData);
        if (mounted) {
          _showSuccessSnackBar('User updated successfully');
        }
      }
      
      if (mounted) {
        setState(() {
          _isEditing = false;
          _isLoading = false;
        });
      }
      
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _showErrorSnackBar(e.toString());
      }
    }
  }

  Future<void> _deleteUser() async {
    if (_currentUser?.id == null) return;
    
    final confirmed = await _showConfirmDialog(
      'Delete User',
      'Are you sure you want to delete this user? This action cannot be undone.',
      confirmText: 'Delete',
      isDestructive: true,
    );
    
    if (!confirmed) return;
    
    setState(() => _isLoading = true);
    
    try {
      await _adminService.deleteUser(_currentUser!.id!);
      if (mounted) {
        _showSuccessSnackBar('User deleted successfully');
        Navigator.pop(context, true); // Return true to indicate user was deleted
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _showErrorSnackBar('Failed to delete user: $e');
      }
    }
  }

  Future<void> _resetPassword() async {
    if (_currentUser?.id == null) return;
    
    final confirmed = await _showConfirmDialog(
      'Reset Password',
      'Are you sure you want to reset the password for this user? They will receive an email with instructions.',
      confirmText: 'Reset Password',
    );
    
    if (!confirmed) return;
    
    try {
      // Implement password reset logic
      _showSuccessSnackBar('Password reset email sent to user');
    } catch (e) {
      _showErrorSnackBar('Failed to reset password: $e');
    }
  }

  Future<void> _toggleUserStatus() async {
    if (_currentUser?.id == null) return;
    
    final action = _isActive ? 'suspend' : 'activate';
    final confirmed = await _showConfirmDialog(
      '${action.capitalize()} User',
      'Are you sure you want to $action this user?',
      confirmText: action.capitalize(),
    );
    
    if (!confirmed) return;
    
    try {
      setState(() => _isActive = !_isActive);
      await _adminService.updateUser(_currentUser!.id!, {'isActive': _isActive});
      _showSuccessSnackBar('User ${action}d successfully');
    } catch (e) {
      setState(() => _isActive = !_isActive); // Revert on error
      _showErrorSnackBar('Failed to $action user: $e');
    }
  }

  Widget _buildOverviewTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildUserInfoCard(),
          const SizedBox(height: 16),
          _buildUserStatsCard(),
          const SizedBox(height: 16),
          _buildQuickActionsCard(),
        ],
      ),
    );
  }

  Widget _buildUserInfoCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: Colors.blue.shade100,
                  child: Text(
                    _currentUser?.username.isNotEmpty == true 
                        ? _currentUser!.username[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade700,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentUser?.username ?? 'New User',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        _currentUser?.email ?? '',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _isActive ? Colors.green.shade100 : Colors.red.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _isActive ? 'Active' : 'Inactive',
                              style: TextStyle(
                                color: _isActive ? Colors.green.shade700 : Colors.red.shade700,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.blue.shade100,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _selectedRole.capitalize(),
                              style: TextStyle(
                                color: Colors.blue.shade700,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: _handleUserAction,
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Row(
                        children: [
                          Icon(Icons.edit, size: 20, color: Colors.blue.shade600),
                          const SizedBox(width: 8),
                          const Text('Edit'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'reset_password',
                      child: Row(
                        children: [
                          Icon(Icons.lock_reset, size: 20, color: Colors.orange.shade600),
                          const SizedBox(width: 8),
                          const Text('Reset Password'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'toggle_status',
                      child: Row(
                        children: [
                          Icon(
                            _isActive ? Icons.block : Icons.check_circle,
                            size: 20,
                            color: _isActive ? Colors.red.shade600 : Colors.green.shade600,
                          ),
                          const SizedBox(width: 8),
                          Text(_isActive ? 'Suspend' : 'Activate'),
                        ],
                      ),
                    ),
                    if (!widget.isCreateMode)
                      PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete, size: 20, color: Colors.red.shade600),
                            const SizedBox(width: 8),
                            const Text('Delete'),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            _buildInfoRow('Username', _currentUser?.username ?? 'N/A'),
            _buildInfoRow('Email', _currentUser?.email ?? 'N/A'),
            _buildInfoRow('Phone', _currentUser?.phone ?? 'N/A'),
            _buildInfoRow('Company', _currentUser?.company ?? 'N/A'),
            _buildInfoRow('Designation', _currentUser?.designation ?? 'N/A'),
            _buildInfoRow(
              'Created', 
              _currentUser?.createdAt != null 
                  ? _formatDateTime(_currentUser!.createdAt!)
                  : 'N/A'
            ),
            _buildInfoRow(
              'Last Login', 
              _currentUser?.lastLogin != null 
                  ? _formatDateTime(_currentUser!.lastLogin!)
                  : 'Never'
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w400),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserStatsCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'User Statistics',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 2,
              children: [
                _buildStatItem(
                  'Total Logins',
                  _userStats['totalLogins']?.toString() ?? '0',
                  Icons.login,
                  Colors.blue,
                ),
                _buildStatItem(
                  'Data Entries',
                  _userStats['dataEntered']?.toString() ?? '0',
                  Icons.data_usage,
                  Colors.green,
                ),
                _buildStatItem(
                  'Reports Generated',
                  _userStats['reportsGenerated']?.toString() ?? '0',
                  Icons.assessment,
                  Colors.orange,
                ),
                _buildStatItem(
                  'Account Age',
                  '${_userStats['accountAge']?.toString() ?? '0'} days',
                  Icons.calendar_today,
                  Colors.purple,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.grey,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionsCard() {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Quick Actions',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildActionButton(
                  'Edit User',
                  Icons.edit,
                  Colors.blue,
                  () => setState(() => _isEditing = true),
                ),
                _buildActionButton(
                  'Reset Password',
                  Icons.lock_reset,
                  Colors.orange,
                  _resetPassword,
                ),
                _buildActionButton(
                  _isActive ? 'Suspend' : 'Activate',
                  _isActive ? Icons.block : Icons.check_circle,
                  _isActive ? Colors.red : Colors.green,
                  _toggleUserStatus,
                ),
                if (!widget.isCreateMode)
                  _buildActionButton(
                    'Delete User',
                    Icons.delete,
                    Colors.red,
                    _deleteUser,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onTap) {
    return ElevatedButton.icon(
      onPressed: _isLoading ? null : onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _buildEditTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildFormSection(
              'Basic Information',
              [
                _buildTextFormField(
                  controller: _usernameController,
                  label: 'Username',
                  icon: Icons.person,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Username is required';
                    }
                    if (value.length < 3) {
                      return 'Username must be at least 3 characters';
                    }
                    return null;
                  },
                ),
                _buildTextFormField(
                  controller: _emailController,
                  label: 'Email',
                  icon: Icons.email,
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Email is required';
                    }
                    if (!AdminUtils.isValidEmail(value)) {
                      return 'Please enter a valid email';
                    }
                    return null;
                  },
                ),
                _buildTextFormField(
                  controller: _phoneController,
                  label: 'Phone',
                  icon: Icons.phone,
                  keyboardType: TextInputType.phone,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Phone is required';
                    }
                    if (!AdminUtils.isValidPhone(value)) {
                      return 'Please enter a valid 10-digit phone number';
                    }
                    return null;
                  },
                ),
              ],
            ),
            _buildFormSection(
              'Organization Details',
              [
                _buildTextFormField(
                  controller: _companyController,
                  label: 'Company',
                  icon: Icons.business,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Company is required';
                    }
                    return null;
                  },
                ),
                _buildTextFormField(
                  controller: _designationController,
                  label: 'Designation',
                  icon: Icons.work,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Designation is required';
                    }
                    return null;
                  },
                ),
                _buildRoleDropdown(),
              ],
            ),
            if (widget.isCreateMode || _currentUser == null) ...[
              _buildFormSection(
                'Password',
                [
                  _buildTextFormField(
                    controller: _passwordController,
                    label: 'Password',
                    icon: Icons.lock,
                    obscureText: _obscurePassword,
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Password is required';
                      }
                      if (!AdminUtils.isStrongPassword(value)) {
                        return 'Password must be at least 8 characters with uppercase, lowercase, number, and special character';
                      }
                      return null;
                    },
                  ),
                  _buildTextFormField(
                    controller: _confirmPasswordController,
                    label: 'Confirm Password',
                    icon: Icons.lock_outline,
                    obscureText: _obscureConfirmPassword,
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Please confirm your password';
                      }
                      if (value != _passwordController.text) {
                        return 'Passwords do not match';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ],
            _buildFormSection(
              'Permissions & Status',
              [
                _buildPermissionsSelector(),
                _buildStatusToggle(),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isLoading ? null : () {
                      setState(() => _isEditing = false);
                    },
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _saveUser,
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(widget.isCreateMode ? 'Create User' : 'Save Changes'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        ...children,
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildTextFormField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscureText,
        validator: validator,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon),
          suffixIcon: suffixIcon,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleDropdown() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: DropdownButtonFormField<String>(
        value: _selectedRole,
        decoration: InputDecoration(
          labelText: 'Role',
          prefixIcon: const Icon(Icons.security),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        items: AdminConfig.allRoles.map((role) {
          return DropdownMenuItem(
            value: role,
            child: Text(role.replaceAll('_', ' ').capitalize()),
          );
        }).toList(),
        onChanged: (value) {
          setState(() {
            _selectedRole = value!;
            _updatePermissionsBasedOnRole(value);
          });
        },
      ),
    );
  }

  Widget _buildPermissionsSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Permissions',
          style: TextStyle(fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: AdminPermissions.allPermissions.map((permission) {
            final isSelected = _selectedPermissions.contains(permission);
            return FilterChip(
              label: Text(
                permission.replaceAll('_', ' ').capitalize(),
                style: TextStyle(
                  fontSize: 12,
                  color: isSelected ? Colors.white : Colors.black87,
                ),
              ),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  if (selected) {
                    _selectedPermissions.add(permission);
                  } else {
                    _selectedPermissions.remove(permission);
                  }
                });
              },
              selectedColor: Colors.blue,
              checkmarkColor: Colors.white,
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildStatusToggle() {
    return SwitchListTile(
      title: const Text('Active Status'),
      subtitle: Text(_isActive ? 'User is active' : 'User is suspended'),
      value: _isActive,
      onChanged: (value) => setState(() => _isActive = value),
      activeColor: Colors.green,
    );
  }

  Widget _buildActivityTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Text(
                'Recent Activities',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              IconButton(
                onPressed: _loadUserActivities,
                icon: const Icon(Icons.refresh),
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _userActivities.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.history, size: 48, color: Colors.grey),
                          SizedBox(height: 16),
                          Text('No activities found'),
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: _userActivities.length,
                      separatorBuilder: (context, index) => const Divider(),
                      itemBuilder: (context, index) {
                        final activity = _userActivities[index];
                        return _buildActivityItem(activity);
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildActivityItem(AdminActivity activity) {
    final color = _getActivityColor(activity.type);
    final icon = _getActivityIcon(activity.type);
    
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.2),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(activity.description),
      subtitle: Text(AdminUtils.getTimeAgo(activity.timestamp)),
      trailing: Text(
        _formatTime(activity.timestamp),
        style: TextStyle(
          color: Colors.grey.shade600,
          fontSize: 12,
        ),
      ),
    );
  }

  void _handleUserAction(String action) {
    switch (action) {
      case 'edit':
        setState(() => _isEditing = true);
      case 'reset_password':
        _resetPassword();
      case 'toggle_status':
        _toggleUserStatus();
      case 'delete':
        _deleteUser();
    }
  }

  void _updatePermissionsBasedOnRole(String role) {
    setState(() {
      switch (role) {
        case AdminConfig.superAdminRole:
          _selectedPermissions = List.from(AdminPermissions.superAdminPermissions);
        case AdminConfig.adminRole:
          _selectedPermissions = List.from(AdminPermissions.adminPermissions);
        case AdminConfig.moderatorRole:
          _selectedPermissions = List.from(AdminPermissions.moderatorPermissions);
        default:
          _selectedPermissions = [];
      }
    });
  }

  Color _getActivityColor(String type) {
    switch (type) {
      case 'login': return Colors.green;
      case 'action': return Colors.blue;
      case 'error': return Colors.red;
      case 'warning': return Colors.orange;
      default: return Colors.grey;
    }
  }

  IconData _getActivityIcon(String type) {
    switch (type) {
      case 'login': return Icons.login;
      case 'action': return Icons.settings;
      case 'error': return Icons.error;
      case 'warning': return Icons.warning;
      default: return Icons.info;
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.day}/${dateTime.month}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  String _formatTime(DateTime dateTime) {
    return '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }

  Future<bool> _showConfirmDialog(
    String title,
    String message, {
    String confirmText = 'Confirm',
    String cancelText = 'Cancel',
    bool isDestructive = false,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(cancelText),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isDestructive ? Colors.red : null,
            ),
            child: Text(confirmText),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isCreateMode ? 'Create User' : 'User Details'),
        backgroundColor: AdminTheme.primaryColor,
        foregroundColor: Colors.white,
        actions: [
          if (!widget.isCreateMode && !_isEditing)
            IconButton(
              onPressed: () => setState(() => _isEditing = true),
              icon: const Icon(Icons.edit),
              tooltip: 'Edit User',
            ),
        ],
        bottom: !widget.isCreateMode && !_isEditing
            ? TabBar(
                controller: _tabController,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white,
                tabs: const [
                  Tab(icon: Icon(Icons.person), text: 'Overview'),
                  Tab(icon: Icon(Icons.edit), text: 'Edit'),
                  Tab(icon: Icon(Icons.history), text: 'Activity'),
                ],
              )
            : null,
      ),
      body: widget.isCreateMode || _isEditing
          ? _buildEditTab()
          : TabBarView(
              controller: _tabController,
              children: [
                _buildOverviewTab(),
                _buildEditTab(),
                _buildActivityTab(),
              ],
            ),
    );
  }
}

// Extension for string capitalization
extension StringCapitalization on String {
  String capitalize() {
    if (isEmpty) return this;
    return this[0].toUpperCase() + substring(1);
  }
}

// Mock classes that you'll need to define or import properly
class AdminUser {
  final int? id;
  final String username;
  final String? email;
  final String? phone;
  final String? company;
  final String? designation;
  final List<String> permissions;
  final bool? isActive;
  final DateTime? createdAt;
  final DateTime? lastLogin;

  AdminUser({
    this.id,
    required this.username,
    this.email,
    this.phone,
    this.company,
    this.designation,
    this.permissions = const [],
    this.isActive,
    this.createdAt,
    this.lastLogin,
  });

  factory AdminUser.fromJson(Map<String, dynamic> json) {
    return AdminUser(
      id: json['id'],
      username: json['username'] ?? '',
      email: json['email'],
      phone: json['phone'],
      company: json['company'],
      designation: json['designation'],
      permissions: List<String>.from(json['permissions'] ?? []),
      isActive: json['isActive'],
      createdAt: json['createdAt'] != null ? DateTime.parse(json['createdAt']) : null,
      lastLogin: json['lastLogin'] != null ? DateTime.parse(json['lastLogin']) : null,
    );
  }
}

class AdminActivity {
  final String type;
  final String description;
  final DateTime timestamp;

  AdminActivity({
    required this.type,
    required this.description,
    required this.timestamp,
  });
}

// Mock classes that should be defined elsewhere in your project
class AdminConfig {
  static const String superAdminRole = 'super_admin';
  static const String adminRole = 'admin';
  static const String moderatorRole = 'moderator';
  static const String userRole = 'user';
  
  static const List<String> allRoles = [
    superAdminRole,
    adminRole,
    moderatorRole,
    userRole,
  ];
}

class AdminPermissions {
  static const List<String> allPermissions = [
    'read_users',
    'write_users',
    'delete_users',
    'read_reports',
    'write_reports',
    'manage_system',
  ];
  
  static const List<String> superAdminPermissions = allPermissions;
  static const List<String> adminPermissions = [
    'read_users',
    'write_users',
    'read_reports',
    'write_reports',
  ];
  static const List<String> moderatorPermissions = [
    'read_users',
    'read_reports',
  ];
}

class AdminUtils {
  static bool isValidEmail(String email) {
    return RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(email);
  }
  
  static bool isValidPhone(String phone) {
    return RegExp(r'^\d{10}$').hasMatch(phone.replaceAll(RegExp(r'[^\d]'), ''));
  }
  
  static bool isStrongPassword(String password) {
    return password.length >= 8 &&
           RegExp(r'[A-Z]').hasMatch(password) &&
           RegExp(r'[a-z]').hasMatch(password) &&
           RegExp(r'[0-9]').hasMatch(password) &&
           RegExp(r'[!@#$%^&*(),.?":{}|<>]').hasMatch(password);
  }
  
  static String getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays > 0) {
      return '${difference.inDays} days ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hours ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minutes ago';
    } else {
      return 'Just now';
    }
  }
}

class AdminTheme {
  static const Color primaryColor = Color(0xFF2196F3);
}