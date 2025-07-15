class LoginResponse {
  final bool success;
  final String? message;
  final String? token;
  final Map<String, dynamic>? user;

  const LoginResponse({
    required this.success,
    this.message,
    this.token,
    this.user,
  });

  factory LoginResponse.fromJson(Map<String, dynamic> json) {
    return LoginResponse(
      success: json['success'] ?? false,
      message: json['message'],
      token: json['token'],
      user: json['user'],
    );
  }
} 
// class LoginResponse {
//   final bool success;
//   final String? message;
//   final String? token;
//   final UserModel? user;
//   final DateTime? tokenExpiry;
//   final String? refreshToken;

//   const LoginResponse({
//     required this.success,
//     this.message,
//     this.token,
//     this.user,
//     this.tokenExpiry,
//     this.refreshToken,
//   });


//   factory LoginResponse.fromJson(Map<String, dynamic> json) {
//     return LoginResponse(
//       success: json['success'] ?? false,
//       message: json['message'],
//       token: json['token'],
//       // This is where the issue is - we need to convert the Map to UserModel
//       user: json['user'] != null ? UserModel.fromJson(json['user'] as Map<String, dynamic>) : null,
//       tokenExpiry: json['token_expiry'] != null 
//           ? DateTime.parse(json['token_expiry']) 
//           : null,
//       refreshToken: json['refresh_token'],
//     );
//   }

//   Map<String, dynamic> toJson() {
//     return {
//       'success': success,
//       'message': message,
//       if (token != null) 'token': token,
//       if (user != null) 'user': user!.toJson(),
//       if (tokenExpiry != null) 'token_expiry': tokenExpiry!.toIso8601String(),
//       if (refreshToken != null) 'refresh_token': refreshToken,
//     };
//   }

//   bool get isValid => token != null && (tokenExpiry == null || tokenExpiry!.isAfter(DateTime.now()));

//   LoginResponse copyWith({
//     bool? success,
//     String? message,
//     String? token,
//     UserModel? user,
//     DateTime? tokenExpiry,
//     String? refreshToken,
//   }) {
//     return LoginResponse(
//       success: success ?? this.success,
//       message: message ?? this.message,
//       token: token ?? this.token,
//       user: user ?? this.user,
//       tokenExpiry: tokenExpiry ?? this.tokenExpiry,
//       refreshToken: refreshToken ?? this.refreshToken,
//     );
//   }

//   @override
//   String toString() {
//     return 'LoginResponse(success: $success, message: $message, token: ${token != null ? '***' : 'null'}, '
//         'user: ${user?.toString() ?? 'null'}, tokenExpiry: $tokenExpiry, '
//         'refreshToken: ${refreshToken != null ? '***' : 'null'})';
//   }
// }

// class UserModel {
//   final String id;
//   final String username;
//   final String? email;
//   final String? displayName;
//   final Map<String, dynamic>? additionalData;

//   const UserModel({
//     required this.id,
//     required this.username,
//     this.email,
//     this.displayName,
//     this.additionalData,
//   });

//   factory UserModel.fromJson(Map<String, dynamic> json) {
//     return UserModel(
//       id: json['id'] ?? '',
//       username: json['username'] ?? '',
//       email: json['email'],
//       displayName: json['display_name'] ?? json['displayName'],
//       additionalData: json['additional_data'] ?? json['additionalData'],
//     );
//   }

//   Map<String, dynamic> toJson() {
//     return {
//       'id': id,
//       'username': username,
//       if (email != null) 'email': email,
//       if (displayName != null) 'display_name': displayName,
//       if (additionalData != null) 'additional_data': additionalData,
//     };
//   }

//   @override
//   String toString() {
//     return 'UserModel(id: $id, username: $username, email: $email, displayName: $displayName)';
//   }
// }