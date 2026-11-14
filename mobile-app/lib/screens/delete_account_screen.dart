import 'package:flutter/material.dart';
import '../services/api.dart';
import '../services/session.dart';
import '../theme/app_theme.dart';

class DeleteAccountScreen extends StatefulWidget {
  const DeleteAccountScreen({super.key});

  @override
  State<DeleteAccountScreen> createState() => _DeleteAccountScreenState();
}

class _DeleteAccountScreenState extends State<DeleteAccountScreen> {
  bool _isDeleting = false;
  final _passwordController = TextEditingController();

  Future<void> _deleteAccount() async {
    if (Session.instance.status != AuthStatus.signedIn) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удаление аккаунта'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Это действие необратимо. Вход будет отключён сразу, профиль удалит администратор.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Введите пароль для подтверждения',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Удалить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isDeleting = true);

    try {
      // Сервер проверяет пароль, сразу отключает вход и создаёт заявку:
      // профиль и данные удаляет администратор.
      await Api.post('/api/driver/delete-account', {'password': _passwordController.text});

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Аккаунт удалён. Данные удалит администратор'),
            backgroundColor: Colors.green,
          ),
        );
      }
      await Session.instance.forget();
    } on ApiException catch (e) {
      final msg = e.code == 'invalid-credentials' ? 'Неверный пароль' : 'Ошибка удаления: ${e.message}';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isDeleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Удаление аккаунта'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.warning_amber_rounded, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Удаление аккаунта',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              'При удалении аккаунта будут безвозвратно удалены:',
              style: TextStyle(fontSize: 15),
            ),
            const SizedBox(height: 12),
            _bulletPoint('Ваш профиль водителя'),
            _bulletPoint('Данные для входа'),
            _bulletPoint('Переписка с техподдержкой'),
            const SizedBox(height: 12),
            const Text(
              'Выданные путевые листы хранятся столько, сколько требует закон.',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            const Text(
              'Это действие необратимо. Если вы хотите продолжить, нажмите кнопку ниже.',
              style: TextStyle(color: Colors.grey),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isDeleting ? null : _deleteAccount,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isDeleting
                    ? const CircularProgressIndicator(color: Colors.white, strokeWidth: 2)
                    : const Text('Удалить мой аккаунт', style: TextStyle(fontSize: 16)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const Icon(Icons.remove_circle, size: 16, color: Colors.red),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }
}
