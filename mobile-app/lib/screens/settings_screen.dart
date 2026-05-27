import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_theme.dart';
import 'delete_account_screen.dart';

/// Версия приложения (синхронизирована с pubspec.yaml -> version).
const String _kAppVersion = '1.0.3+4';

/// Полный экран настроек: уведомления, безопасность, язык, тема, информация
/// о приложении, удаление аккаунта и выход.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _notifications = true;
  bool _biometrics = false;
  String _language = 'Русский';

  static const _kNotifyKey = 'pref_notifications';
  static const _kBiometricsKey = 'pref_biometrics';
  static const _kLanguageKey = 'pref_language';

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _notifications = p.getBool(_kNotifyKey) ?? true;
      _biometrics = p.getBool(_kBiometricsKey) ?? false;
      _language = p.getString(_kLanguageKey) ?? 'Русский';
    });
  }

  Future<void> _savePref(String k, dynamic v) async {
    final p = await SharedPreferences.getInstance();
    if (v is bool) await p.setBool(k, v);
    if (v is String) await p.setString(k, v);
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Настройки'),
        leading: Navigator.canPop(context)
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context))
            : null,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // Краткая карточка с email/телефоном
            if (user != null)
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: AppTheme.primaryGradient,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.account_circle, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Учётная запись', style: TextStyle(color: AppTheme.textMuted, fontSize: 11)),
                          const SizedBox(height: 2),
                          Text(
                            user.email ?? '—',
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 18),

            _section('Уведомления и безопасность'),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _switchTile(
                    Icons.notifications_outlined,
                    'Push-уведомления',
                    'О новых путевых листах',
                    _notifications,
                    (v) {
                      setState(() => _notifications = v);
                      _savePref(_kNotifyKey, v);
                    },
                  ),
                  const Divider(height: 1, color: AppTheme.border),
                  _switchTile(
                    Icons.fingerprint,
                    'Биометрия',
                    'Вход по отпечатку пальца',
                    _biometrics,
                    (v) {
                      setState(() => _biometrics = v);
                      _savePref(_kBiometricsKey, v);
                    },
                  ),
                  const Divider(height: 1, color: AppTheme.border),
                  _navTile(
                    Icons.lock_outline,
                    'Сменить пароль',
                    subtitle: 'Через администратора',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Обратитесь к администратору таксопарка')),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),
            _section('Общие'),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _navTile(
                    Icons.language,
                    'Язык',
                    trailing: _language,
                    onTap: () async {
                      final selected = await showModalBottomSheet<String>(
                        context: context,
                        backgroundColor: AppTheme.surface,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                        ),
                        builder: (ctx) => Column(
                          mainAxisSize: MainAxisSize.min,
                          children: ['Русский', 'Қазақша', 'English'].map((lang) {
                            return ListTile(
                              title: Text(lang),
                              trailing: _language == lang
                                  ? const Icon(Icons.check, color: AppTheme.primary)
                                  : null,
                              onTap: () => Navigator.pop(ctx, lang),
                            );
                          }).toList(),
                        ),
                      );
                      if (selected != null) {
                        setState(() => _language = selected);
                        _savePref(_kLanguageKey, selected);
                      }
                    },
                  ),
                  const Divider(height: 1, color: AppTheme.border),
                  _navTile(
                    Icons.brightness_2_outlined,
                    'Тёмная тема',
                    subtitle: 'Включена по умолчанию',
                    trailing: 'Auto',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Используется тёмная тема приложения')),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),
            _section('Поддержка'),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _navTile(
                    Icons.help_outline,
                    'Помощь',
                    onTap: () => showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Помощь'),
                        content: const Text(
                          'Если у вас возникли вопросы по работе с приложением '
                          'или путевыми листами — свяжитесь с администратором '
                          'вашего таксопарка.',
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: AppTheme.border),
                  _navTile(
                    Icons.info_outline,
                    'О приложении',
                    trailing: 'v$_kAppVersion',
                    onTap: () => showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('AsemPro'),
                        content: const Text(
                          'Версия $_kAppVersion\n'
                          'Электронные путевые листы для водителей таксопарка.\n\n'
                          'ASEM PRO — профессиональный подход к каждой поездке.',
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: AppTheme.border),
                  _navTile(
                    Icons.privacy_tip_outlined,
                    'Политика конфиденциальности',
                    onTap: () => showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Политика конфиденциальности'),
                        content: const SingleChildScrollView(
                          child: Text(
                            'Мы собираем и обрабатываем минимально необходимый объём '
                            'персональных данных (ФИО, телефон, документы) исключительно '
                            'для формирования путевых листов и работы в рамках таксопарка.\n\n'
                            'Данные передаются только администратору таксопарка и не '
                            'передаются третьим лицам.\n\n'
                            'Вы можете запросить удаление аккаунта в этом приложении.',
                          ),
                        ),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),
            _section('Аккаунт'),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _navTile(
                    Icons.logout,
                    'Выйти из аккаунта',
                    color: AppTheme.danger,
                    onTap: () async {
                      final ok = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Выйти?'),
                          content: const Text('Вы сможете снова войти по тому же номеру и паролю.'),
                          actions: [
                            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                            ElevatedButton(
                              style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Выйти'),
                            ),
                          ],
                        ),
                      );
                      if (ok == true) await FirebaseAuth.instance.signOut();
                    },
                  ),
                  const Divider(height: 1, color: AppTheme.border),
                  _navTile(
                    Icons.delete_forever_outlined,
                    'Удалить аккаунт',
                    color: AppTheme.danger,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const DeleteAccountScreen()),
                      );
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),
            const Center(
              child: Text(
                'Made with ♥ for AsemPro',
                style: TextStyle(color: AppTheme.textFaint, fontSize: 11),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _section(String t) => Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 10),
        child: Text(
          t,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppTheme.textMuted,
            letterSpacing: 1.2,
          ),
        ),
      );

  Widget _switchTile(IconData icon, String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      activeColor: AppTheme.primary,
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
      secondary: Icon(icon, color: AppTheme.primary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _navTile(
    IconData icon,
    String title, {
    String? subtitle,
    String? trailing,
    Color? color,
    required VoidCallback onTap,
  }) {
    final c = color ?? AppTheme.text;
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Icon(icon, color: color ?? AppTheme.primary),
      title: Text(title, style: TextStyle(color: c, fontWeight: FontWeight.w600)),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12))
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailing != null) ...[
            Text(trailing, style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
            const SizedBox(width: 6),
          ],
          const Icon(Icons.chevron_right, color: AppTheme.textFaint, size: 22),
        ],
      ),
    );
  }
}
