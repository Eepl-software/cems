class User {
  final String id;
  final String username;
  final String email;
  final String role;
  final String token;
  final DateTime createdAt;
  final DateTime lastLogin;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    required this.token,
    required this.createdAt,
    required this.lastLogin,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      email: json['email'],
      role: json['role'],
      token: json['token'],
      createdAt: DateTime.parse(json['created_at']),
      lastLogin: DateTime.parse(json['last_login']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'role': role,
      'token': token,
      'created_at': createdAt.toIso8601String(),
      'last_login': lastLogin.toIso8601String(),
    };
  }

  bool get isAdmin => role == 'admin';
}
