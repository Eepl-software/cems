// import 'package:flutter/material.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'login/enhanced_login_page.dart';
// import 'login/auth_service.dart';
// import 'home_page.dart';
// import 'models.dart';

// void main() {
//   runApp(MyApp());
// }

// class MyApp extends StatelessWidget {
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'Prestige Park Groove - CEMS',
//       debugShowCheckedModeBanner: false,
//       theme: ThemeData(
//         primarySwatch: Colors.teal,
//         visualDensity: VisualDensity.adaptivePlatformDensity,
//         appBarTheme: const AppBarTheme(
//           backgroundColor: Colors.teal,
//           foregroundColor: Colors.white,
//           elevation: 4,
//         ),
//         elevatedButtonTheme: ElevatedButtonThemeData(
//           style: ElevatedButton.styleFrom(
//             backgroundColor: Colors.teal,
//             foregroundColor: Colors.white,
//           ),
//         ),
//       ),
//       home: FutureBuilder<bool>(
//         future: _checkAuthStatus(),
//         builder: (context, snapshot) {
//           if (snapshot.connectionState == ConnectionState.waiting) {
//             return const Scaffold(
//               body: Center(
//                 child: CircularProgressIndicator(),
//               ),
//             );
//           }
          
//           if (snapshot.data == true) {
//             return FutureBuilder<User?>(
//               future: _getCurrentUser(),
//               builder: (context, userSnapshot) {
//                 if (userSnapshot.connectionState == ConnectionState.waiting) {
//                   return const Scaffold(
//                     body: Center(
//                       child: CircularProgressIndicator(),
//                     ),
//                   );
//                 }
                
//                 if (userSnapshot.hasData && userSnapshot.data != null) {
//                   return MyHomePage(
//                     user: userSnapshot.data!,
//                     authService: AuthService(),
//                   );
//                 }
                
//                 return const EnhancedLoginPage();
//               },
//             );
//           }
          
//           return const EnhancedLoginPage();
//         },
//       ),
//     );
//   }

//   Future<bool> _checkAuthStatus() async {
//     try {
//       final prefs = await SharedPreferences.getInstance();
//       final token = prefs.getString('auth_token');
//       return token != null && token.isNotEmpty;
//     } catch (e) {
//       return false;
//     }
//   }

//   Future<User?> _getCurrentUser() async {
//     try {
//       final authService = AuthService();
//       return await authService.getCurrentUser();
//     } catch (e) {
//       return null;
//     }
//   }
// }