// models.dart
enum UserRole {
  user,
  superuser,
}

class User {
  final int id;
  final String username;
  final String email;
  final String phone;
  final String company;
  final String designation;
  final UserRole role;

  const User({
    required this.id,
    required this.username,
    required this.email,
    required this.phone,
    required this.company,
    required this.designation,
    required this.role,
  });
}

class AuthException implements Exception {
  final String message;
  AuthException(this.message);
}