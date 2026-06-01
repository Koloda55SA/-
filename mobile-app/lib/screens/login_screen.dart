import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../theme/app_theme.dart';

/// Экран входа водителя.
/// Логин — номер телефона, пароль задаётся админом при регистрации.
/// Под капотом используется Firebase Email Auth с синтетическим email
/// формата "<digits>@asempro.driver" (например, "79991234567@asempro.driver").
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  /// Приводим номер к формату "+79991234567"
  String _normalizePhone(String raw) {
    String phone = raw.replaceAll(RegExp(r'[\s\(\)\-]'), '');
    if (phone.startsWith('8') && phone.length == 11) {
      phone = '+7${phone.substring(1)}';
    }
    if (!phone.startsWith('+')) phone = '+$phone';
    return phone;
  }

  /// "+79991234567" -> "79991234567@asempro.driver"
  String _phoneToEmail(String normalizedPhone) {
    final digits = normalizedPhone.replaceAll(RegExp(r'\D'), '');
    return '$digits@asempro.driver';
  }

  Future<void> _signIn() async {
    final phone = _normalizePhone(_phoneController.text.trim());
    final password = _passwordController.text.trim();

    if (phone.replaceAll(RegExp(r'\D'), '').length < 10) {
      setState(() => _errorMessage = 'Введите корректный номер телефона');
      return;
    }
    if (password.length < 6) {
      setState(() => _errorMessage = 'Пароль должен быть не короче 6 символов');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final email = _phoneToEmail(phone);
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      // AuthGate в main.dart автоматически переключит на HomeScreen
    } on FirebaseAuthException catch (e) {
      String msg = 'Ошибка входа';
      switch (e.code) {
        case 'user-not-found':
        case 'invalid-credential':
        case 'wrong-password':
          msg = 'Неверный номер или пароль';
          break;
        case 'invalid-email':
          msg = 'Некорректный номер телефона';
          break;
        case 'user-disabled':
          msg = 'Аккаунт отключён администратором';
          break;
        case 'too-many-requests':
          msg = 'Слишком много попыток. Попробуйте позже';
          break;
        case 'network-request-failed':
          msg = 'Нет соединения с интернетом';
          break;
      }
      if (mounted) {
        setState(() {
          _errorMessage = msg;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Ошибка: $e';
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Фоновые «световые пятна»
          Positioned(
            top: -120,
            right: -80,
            child: _glowBlob(280, AppTheme.primary.withValues(alpha: 0.18)),
          ),
          Positioned(
            bottom: -100,
            left: -60,
            child: _glowBlob(260, AppTheme.primaryDeep.withValues(alpha: 0.16)),
          ),

          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(height: 16),
                    Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(22),
                        gradient: AppTheme.primaryGradient,
                        boxShadow: [
                          BoxShadow(
                            color: AppTheme.primary.withValues(alpha: 0.4),
                            blurRadius: 36,
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
                    const SizedBox(height: 22),
                    ShaderMask(
                      shaderCallback: (b) => AppTheme.titleGradient.createShader(b),
                      child: const Text(
                        'ASEM PRO',
                        style: TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.6,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Электронные путевые листы',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 14),
                    ),
                    const SizedBox(height: 36),
                    AppCard(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Добро пожаловать',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.text,
                            ),
                          ),
                          const SizedBox(height: 6),
                          const Text(
                            'Войдите по номеру и паролю, который выдал администратор',
                            style: TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.4),
                          ),
                          const SizedBox(height: 24),
                          TextField(
                            controller: _phoneController,
                            keyboardType: TextInputType.phone,
                            style: const TextStyle(fontSize: 16),
                            decoration: const InputDecoration(
                              labelText: 'Номер телефона',
                              hintText: '+7 999 123-45-67',
                              prefixIcon: Icon(Icons.phone, color: AppTheme.primary, size: 20),
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            style: const TextStyle(fontSize: 16),
                            decoration: InputDecoration(
                              labelText: 'Пароль',
                              hintText: 'Минимум 6 символов',
                              prefixIcon: const Icon(Icons.lock, color: AppTheme.primary, size: 20),
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword ? Icons.visibility : Icons.visibility_off,
                                  color: AppTheme.textMuted,
                                  size: 20,
                                ),
                                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                              ),
                            ),
                            onSubmitted: (_) => _signIn(),
                          ),
                          if (_errorMessage != null) ...[
                            const SizedBox(height: 14),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: AppTheme.danger.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppTheme.danger.withValues(alpha: 0.3)),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.error_outline, color: AppTheme.danger, size: 18),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      _errorMessage!,
                                      style: const TextStyle(color: AppTheme.danger, fontSize: 13),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          const SizedBox(height: 22),
                          ElevatedButton(
                            onPressed: _isLoading ? null : _signIn,
                            child: _isLoading
                                ? const SizedBox(
                                    height: 22,
                                    width: 22,
                                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                                  )
                                : const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text('Войти', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                                      SizedBox(width: 8),
                                      Icon(Icons.arrow_forward, size: 18),
                                    ],
                                  ),
                          ),
                          const SizedBox(height: 12),
                          const Center(
                            child: Text(
                              'Забыли пароль? Обратитесь к администратору',
                              style: TextStyle(color: AppTheme.textFaint, fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.shield_outlined, size: 14, color: AppTheme.textFaint),
                        const SizedBox(width: 6),
                        Text(
                          'Безопасное соединение',
                          style: TextStyle(color: AppTheme.textFaint, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _glowBlob(double size, Color color) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0)],
            stops: const [0, 1],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }
}
