import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Hide status bar clock - fullscreen immersive
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
  ));
  runApp(const AsemProApp());
}

class AsemProApp extends StatelessWidget {
  const AsemProApp({super.key});

  static const Color primaryOrange = Color(0xFFFF8C00);
  static const Color darkBg = Color(0xFF0A0A0A);
  static const Color cardDark = Color(0xFF1A1A1A);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AsemPro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: darkBg,
        primaryColor: primaryOrange,
        colorScheme: const ColorScheme.dark(
          primary: primaryOrange,
          secondary: Color(0xFFFFB800),
          surface: cardDark,
          onPrimary: Colors.white,
          onSecondary: Colors.white,
          onSurface: Color(0xFFF5F5F5),
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0D0D0D),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: cardDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF2A2A2A)),
          ),
          elevation: 0,
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: primaryOrange,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF111111),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: primaryOrange, width: 2),
          ),
          labelStyle: const TextStyle(color: Color(0xFF8A8A8A)),
          hintStyle: const TextStyle(color: Color(0xFF555555)),
        ),
        fontFamily: 'Roboto',
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Scaffold(
            backgroundColor: const Color(0xFF0A0A0A),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 80, height: 80,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF8C00), Color(0xFFFF6B00)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFFF8C00).withValues(alpha: 0.3),
                          blurRadius: 32, spreadRadius: 0,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.local_taxi, color: Colors.white, size: 40),
                  ),
                  const SizedBox(height: 24),
                  const CircularProgressIndicator(color: Color(0xFFFF8C00)),
                ],
              ),
            ),
          );
        }
        if (snapshot.hasData) {
          return const HomeScreen();
        }
        return const LoginScreen();
      },
    );
  }
}
