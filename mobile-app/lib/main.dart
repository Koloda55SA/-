import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'firebase_options.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  // Edge-to-edge, тёмный статус-бар на оранжево-чёрной палитре.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: AppTheme.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  runApp(const AsemProApp());
}

class AsemProApp extends StatelessWidget {
  const AsemProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AsemPro',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      home: const AuthGate(),
    );
  }
}

/// Маршрутизирует пользователя между login → home → "аккаунт заблокирован"
/// в зависимости от состояния Firebase Auth и поля `active` в профиле водителя.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnap) {
        if (authSnap.connectionState == ConnectionState.waiting) {
          return const _SplashScreen();
        }
        final user = authSnap.data;
        if (user == null) return const LoginScreen();

        // Подписываемся на документ водителя — если админ деактивирует, мгновенно разлогиниваем.
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('drivers')
              .doc(user.uid)
              .snapshots(),
          builder: (context, driverSnap) {
            if (driverSnap.connectionState == ConnectionState.waiting) {
              return const _SplashScreen();
            }
            final data = driverSnap.data?.data();
            // Если профиль не найден — может быть старая запись по authUid, попробуем найти.
            if (data == null) {
              return _DriverProfileFallback(uid: user.uid);
            }
            final active = data['active'];
            if (active == false) {
              return const _BlockedScreen();
            }
            return HomeScreen(driverData: data, driverDocId: user.uid);
          },
        );
      },
    );
  }
}

/// Падает на «бесшовный» fallback: ищем driver по полю authUid (для старых записей).
class _DriverProfileFallback extends StatelessWidget {
  final String uid;
  const _DriverProfileFallback({required this.uid});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
      future: FirebaseFirestore.instance
          .collection('drivers')
          .where('authUid', isEqualTo: uid)
          .limit(1)
          .get(),
      builder: (context, snap) {
        if (!snap.hasData) return const _SplashScreen();
        if (snap.data!.docs.isEmpty) return const _ProfileMissingScreen();
        final doc = snap.data!.docs.first;
        final data = doc.data();
        if (data['active'] == false) return const _BlockedScreen();
        return HomeScreen(driverData: data, driverDocId: doc.id);
      },
    );
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: AppTheme.primaryGradient,
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.35),
                    blurRadius: 40,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Image.asset(
                  'assets/logo/asem_logo.png',
                  width: 88,
                  height: 88,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(height: 28),
            ShaderMask(
              shaderCallback: (b) => AppTheme.titleGradient.createShader(b),
              child: const Text(
                'ASEM PRO',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.4,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 24),
            const SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(color: AppTheme.primary, strokeWidth: 2.5),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockedScreen extends StatelessWidget {
  const _BlockedScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 84,
                height: 84,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppTheme.danger.withValues(alpha: 0.15),
                ),
                child: const Icon(Icons.block, color: AppTheme.danger, size: 44),
              ),
              const SizedBox(height: 24),
              const Text(
                'Аккаунт деактивирован',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              const Text(
                'Доступ временно ограничен. Обратитесь к администратору таксопарка для активации.',
                style: TextStyle(color: AppTheme.textMuted, fontSize: 14, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => FirebaseAuth.instance.signOut(),
                  icon: const Icon(Icons.logout),
                  label: const Text('Выйти'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileMissingScreen extends StatelessWidget {
  const _ProfileMissingScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.person_off, color: AppTheme.textMuted, size: 56),
              const SizedBox(height: 16),
              const Text(
                'Профиль не найден',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Обратитесь к администратору таксопарка для регистрации профиля.',
                style: TextStyle(color: AppTheme.textMuted, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => FirebaseAuth.instance.signOut(),
                icon: const Icon(Icons.logout),
                label: const Text('Выйти'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
