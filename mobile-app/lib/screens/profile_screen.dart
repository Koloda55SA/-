import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../theme/app_theme.dart';

/// Личный кабинет водителя: ФИО, фото-инициалы, контактная информация,
/// данные автомобиля, документы и организация. Все данные read-only —
/// меняет только администратор таксопарка.
class ProfileScreen extends StatelessWidget {
  final Map<String, dynamic> driverData;
  final String driverDocId;

  const ProfileScreen({super.key, required this.driverData, required this.driverDocId});

  String _initials(String? fullName) {
    final t = (fullName ?? '').trim();
    if (t.isEmpty) return 'AP';
    final parts = t.split(RegExp(r'\s+'));
    final a = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0][0] : '';
    final b = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
    final v = (a + b).toUpperCase();
    return v.isEmpty ? 'AP' : v;
  }

  @override
  Widget build(BuildContext context) {
    final fullName = (driverData['fullName'] ?? '').toString();
    final isActive = driverData['active'] != false;
    final phone = (driverData['phone'] ?? '').toString();

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('Личный кабинет'),
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              )
            : null,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            // ===== Аватар + имя =====
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1B1408), Color(0xFF120E0A)],
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
                boxShadow: [
                  BoxShadow(
                    color: AppTheme.primary.withValues(alpha: 0.18),
                    blurRadius: 32,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: AppTheme.primaryGradient,
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.35),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        _initials(fullName),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fullName.isEmpty ? 'Водитель' : fullName,
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          phone,
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
                        ),
                        const SizedBox(height: 10),
                        StatusChip(
                          label: isActive ? 'Активен' : 'Неактивен',
                          color: isActive ? AppTheme.success : AppTheme.danger,
                          icon: isActive ? Icons.check_circle : Icons.block,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 22),

            // ===== Статистика =====
            _StatsRow(driverDocId: driverDocId),

            const SizedBox(height: 22),

            // ===== Контакты =====
            _section('Контакты'),
            AppCard(
              child: Column(
                children: [
                  _row(Icons.phone, 'Телефон', phone.isEmpty ? '—' : phone),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // ===== Автомобиль =====
            _section('Автомобиль'),
            AppCard(
              child: Column(
                children: [
                  _row(Icons.directions_car, 'Марка', (driverData['carModel'] ?? '—').toString()),
                  const _RowDiv(),
                  _row(Icons.confirmation_number, 'Гос. номер', (driverData['plateNumber'] ?? '—').toString()),
                  const _RowDiv(),
                  _row(Icons.garage, 'Гаражный №', (driverData['garageNumber'] ?? '—').toString()),
                  const _RowDiv(),
                  _row(Icons.badge_outlined, 'Табельный №', (driverData['tabNumber'] ?? '—').toString()),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // ===== Документы =====
            _section('Документы'),
            AppCard(
              child: Column(
                children: [
                  _row(Icons.credit_card, 'Удостоверение', (driverData['license'] ?? '—').toString()),
                  const _RowDiv(),
                  _row(Icons.school_outlined, 'Класс', (driverData['licenseClass'] ?? '—').toString()),
                  const _RowDiv(),
                  _row(Icons.fingerprint, 'ID водителя', (driverData['driverIdNumber'] ?? '—').toString()),
                  const _RowDiv(),
                  _row(Icons.account_balance_outlined, 'СНИЛС', (driverData['snils'] ?? '—').toString()),
                  const _RowDiv(),
                  _row(Icons.receipt_long, 'ИНН', (driverData['inn'] ?? '—').toString()),
                  const _RowDiv(),
                  _row(Icons.verified_outlined, 'ОСГОП', (driverData['osgop'] ?? '—').toString()),
                  const _RowDiv(),
                  _row(Icons.assignment_outlined, 'Разрешение №', (driverData['permit'] ?? '—').toString()),
                ],
              ),
            ),

            const SizedBox(height: 18),

            // ===== Организация =====
            _section('Организация'),
            AppCard(
              child: Column(
                children: [
                  _row(Icons.business, 'Название', (driverData['orgName'] ?? '—').toString()),
                  const _RowDiv(),
                  _row(Icons.tag, 'ОГРН (ИП)', (driverData['orgOgrn'] ?? '—').toString()),
                  const _RowDiv(),
                  _row(Icons.tag, 'ИНН', (driverData['orgInn'] ?? '—').toString()),
                  const _RowDiv(),
                  _row(Icons.phone_in_talk_outlined, 'Телефон', (driverData['orgPhone'] ?? '—').toString()),
                  const _RowDiv(),
                  _row(Icons.place_outlined, 'Адрес', (driverData['orgAddress'] ?? '—').toString(), wrap: true),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Подсказка
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.info.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.info.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline, color: AppTheme.info, size: 18),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Если данные неточные — обратитесь к администратору таксопарка.',
                      style: TextStyle(color: AppTheme.textMuted, fontSize: 12, height: 1.4),
                    ),
                  ),
                ],
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

  Widget _row(IconData icon, String label, String value, {bool wrap = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: wrap ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Icon(icon, color: AppTheme.primary, size: 18),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              overflow: wrap ? TextOverflow.visible : TextOverflow.ellipsis,
              maxLines: wrap ? 3 : 1,
            ),
          ),
        ],
      ),
    );
  }
}

class _RowDiv extends StatelessWidget {
  const _RowDiv();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: AppTheme.border.withValues(alpha: 0.5));
  }
}

class _StatsRow extends StatelessWidget {
  final String driverDocId;
  const _StatsRow({required this.driverDocId});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox();
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('waybills')
          .where('authUid', isEqualTo: user.uid)
          .limit(100)
          .snapshots(),
      builder: (context, snap) {
        int total = 0, closed = 0, open = 0;
        if (snap.hasData) {
          for (final d in snap.data!.docs) {
            total++;
            if (d.data()['status'] == 'closed') {
              closed++;
            } else {
              open++;
            }
          }
        }
        return Row(
          children: [
            Expanded(child: _stat('Всего', '$total', AppTheme.primary, Icons.description_outlined)),
            const SizedBox(width: 10),
            Expanded(child: _stat('Закрыто', '$closed', AppTheme.success, Icons.check_circle_outline)),
            const SizedBox(width: 10),
            Expanded(child: _stat('Активно', '$open', AppTheme.info, Icons.bolt)),
          ],
        );
      },
    );
  }

  Widget _stat(String label, String value, Color color, IconData icon) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(color: color, fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
        ],
      ),
    );
  }
}
