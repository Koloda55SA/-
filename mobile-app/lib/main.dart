import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/session.dart';
import 'theme/app_theme.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Edge-to-edge, тёмный статус-бар на оранжево-чёрной палитре.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarColor: AppTheme.bg,
    systemNavigationBarIconBrightness: Brightness.light,
  ));
  // Вход восстанавливается из сохранённого токена; пока идёт — заставка.
  Session.instance.restore();
  runApp(const AsemProApp());
}

/// Корневой навигатор: при выходе из аккаунта закрываем все экраны,
/// открытые поверх главного (настройки, удаление аккаунта и т.п.).
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

class AsemProApp extends StatefulWidget {
  const AsemProApp({super.key});

  @override
  State<AsemProApp> createState() => _AsemProAppState();
}

class _AsemProAppState extends State<AsemProApp> {
  AuthStatus _last = Session.instance.status;

  @override
  void initState() {
    super.initState();
    Session.instance.addListener(_onSession);
  }

  // Вышел, удалил аккаунт или отключён — закрываем все экраны поверх главного
  // (в т.ч. создание ЭПЛ).
  void _onSession() {
    final s = Session.instance.status;
    if (s != _last && s != AuthStatus.signedIn) {
      rootNavigatorKey.currentState?.popUntil((route) => route.isFirst);
    }
    _last = s;
  }

  @override
  void dispose() {
    Session.instance.removeListener(_onSession);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AsemPro',
      debugShowCheckedModeBanner: false,
      navigatorKey: rootNavigatorKey,
      theme: AppTheme.dark(),
      home: const AuthGate(),
    );
  }
}

/// Маршрутизирует пользователя между login → home → "аккаунт заблокирован"
/// в зависимости от сессии и поля `active` в профиле водителя.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    final session = Session.instance;
    return ListenableBuilder(
      listenable: session,
      builder: (context, _) {
        switch (session.status) {
          case AuthStatus.loading:
            return const _SplashScreen();
          case AuthStatus.signedOut:
            return const LoginScreen();
          case AuthStatus.blocked:
            return const _BlockedScreen();
          case AuthStatus.missing:
            return const _ProfileMissingScreen();
          case AuthStatus.signedIn:
            return HomeScreen(
              driverData: session.driver ?? const {},
              driverDocId: session.userId,
            );
        }
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
                  onPressed: () => Session.instance.signOut(),
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
                onPressed: () => Session.instance.signOut(),
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
