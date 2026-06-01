import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удаление аккаунта'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Это действие необратимо. Все ваши данные и путевые листы будут удалены.',
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
      // Re-authenticate user before deletion
      final email = user.email;
      if (email == null || email.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Email пользователя не найден'),
              backgroundColor: Colors.red,
            ),
          );
        }
        setState(() => _isDeleting = false);
        return;
      }
      final credential = EmailAuthProvider.credential(
        email: email,
        password: _passwordController.text,
      );
      await user.reauthenticateWithCredential(credential);

      // Create deletion request in Firestore (for admin to clean up data)
      await FirebaseFirestore.instance.collection('deletionRequests').add({
        'uid': user.uid,
        'email': user.email,
        'requestedAt': FieldValue.serverTimestamp(),
        'status': 'pending',
      });

      // Delete user's waybills
      final waybills = await FirebaseFirestore.instance
          .collection('waybills')
          .where('authUid', isEqualTo: user.uid)
          .limit(100)
          .get();
      for (final doc in waybills.docs) {
        await doc.reference.delete();
      }

      // Delete driver profile
      await FirebaseFirestore.instance
          .collection('drivers')
          .doc(user.uid)
          .delete();

      // Delete Firebase Auth account
      await user.delete();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Аккаунт успешно удалён'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on FirebaseAuthException catch (e) {
      String msg = 'Ошибка удаления';
      if (e.code == 'wrong-password') {
        msg = 'Неверный пароль';
      } else if (e.code == 'requires-recent-login') {
        msg = 'Войдите заново и повторите попытку';
      }
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
            _bulletPoint('Все ваши путевые листы'),
            _bulletPoint('Данные авторизации'),
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
