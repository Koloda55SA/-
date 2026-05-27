import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF0A0A0A), Color(0xFF141414)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo
                Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF8C00), Color(0xFFFF6B00)],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF8C00).withValues(alpha: 0.35),
                        blurRadius: 32, spreadRadius: 0,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.local_taxi, color: Colors.white, size: 40),
                ),
                const SizedBox(height: 20),
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFFFF8C00), Color(0xFFFFB800)],
                  ).createShader(bounds),
                  child: const Text(
                    'ASEM PRO',
                    style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Электронные путевые листы',
                  style: TextStyle(color: Color(0xFF8A8A8A), fontSize: 14),
                ),
                const SizedBox(height: 40),

                // Card
                Container(
                  padding: const EdgeInsets.all(28),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF2A2A2A)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Вход в аккаунт',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Используйте номер и пароль, который выдал администратор',
                        style: TextStyle(color: Color(0xFF8A8A8A), fontSize: 12),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Номер телефона',
                          hintText: '+7 999 123-45-67',
                          prefixIcon: Icon(Icons.phone, color: Color(0xFFFF8C00)),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _passwordController,
                        obscureText: _obscurePassword,
                        decoration: InputDecoration(
                          labelText: 'Пароль',
                          hintText: 'Минимум 6 символов',
                          prefixIcon: const Icon(Icons.lock, color: Color(0xFFFF8C00)),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscurePassword ? Icons.visibility : Icons.visibility_off,
                              color: const Color(0xFF8A8A8A),
                            ),
                            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                          ),
                        ),
                        onSubmitted: (_) => _signIn(),
                      ),
                      if (_errorMessage != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _errorMessage!,
                          style: const TextStyle(color: Color(0xFFEF4444), fontSize: 13),
                          textAlign: TextAlign.center,
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _signIn,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF8C00),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            elevation: 0,
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 22, width: 22,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : const Text(
                                  'Войти',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                                ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Если забыли пароль — обратитесь к администратору таксопарка',
                        style: TextStyle(color: Color(0xFF6B6B6B), fontSize: 11),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],
            ),
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
