import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'waybill_screen.dart';
import 'waybill_preview_screen.dart';
import 'signature_screen.dart';
import 'delete_account_screen.dart';
import '../services/waybill_pdf_service.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;
  Map<String, dynamic>? _driverData;
  String? _driverDocId;
  bool _isLoading = true;
  Map<String, dynamic>? _activeWaybill;
  String? _activeWaybillId;

  @override
  void initState() {
    super.initState();
    _loadDriverData();
  }

  Future<void> _loadDriverData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // Doc ID водителя = authUid (так создаёт админ-панель).
      // Сначала пробуем по uid, потом fallback по полю authUid.
      final docByUid = await FirebaseFirestore.instance
          .collection('drivers')
          .doc(user.uid)
          .get();
      if (docByUid.exists) {
        if (mounted) {
          setState(() {
            _driverData = docByUid.data();
            _driverDocId = docByUid.id;
            _isLoading = false;
          });
        }
        await _checkActiveWaybill();
        return;
      }

      // Fallback: запросом по authUid (для старых записей)
      final snap = await FirebaseFirestore.instance
          .collection('drivers')
          .where('authUid', isEqualTo: user.uid)
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty) {
        final doc = snap.docs.first;
        if (mounted) {
          setState(() {
            _driverData = doc.data();
            _driverDocId = doc.id;
            _isLoading = false;
          });
        }
        await _checkActiveWaybill();
      } else {
        if (mounted) setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Driver data load error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkActiveWaybill() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final snap = await FirebaseFirestore.instance
          .collection('waybills')
          .where('driverId', isEqualTo: _driverDocId ?? user.uid)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();
      if (snap.docs.isNotEmpty && mounted) {
        setState(() {
          _activeWaybill = snap.docs.first.data();
          _activeWaybillId = snap.docs.first.id;
        });
      }
    } catch (e) {
      debugPrint('Check active waybill error: $e');
    }
  }

  Future<void> _closeWaybill() async {
    if (_activeWaybillId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('waybills')
          .doc(_activeWaybillId)
          .update({'status': 'closed'});
      if (mounted) {
        setState(() {
          _activeWaybill = null;
          _activeWaybillId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Путевой лист закрыт'),
            backgroundColor: Color(0xFF22C55E),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator(color: Color(0xFFFF8C00))),
      );
    }

    final pages = [
      _buildEplPage(),
      _buildProfilePage(),
      _buildSettingsPage(),
    ];

    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Color(0xFF0D0D0D),
          border: Border(top: BorderSide(color: Color(0xFF2A2A2A))),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _navItem(0, Icons.description, 'ЭПЛ'),
                _navItem(1, Icons.person, 'Профиль'),
                _navItem(2, Icons.settings, 'Настройки'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _navItem(int index, IconData icon, String label) {
    final active = _currentIndex == index;
    return GestureDetector(
      onTap: () => setState(() => _currentIndex = index),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: active ? const Color(0xFFFF8C00) : const Color(0xFF6B6B6B), size: 26),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(
            color: active ? const Color(0xFFFF8C00) : const Color(0xFF6B6B6B),
            fontSize: 12, fontWeight: active ? FontWeight.w600 : FontWeight.normal,
          )),
        ],
      ),
    );
  }

  // ========== ЭПЛ PAGE ==========
  Widget _buildEplPage() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: const LinearGradient(colors: [Color(0xFFFF8C00), Color(0xFFFF6B00)]),
                  ),
                  child: const Icon(Icons.local_taxi, color: Colors.white, size: 24),
                ),
                const SizedBox(width: 12),
                ShaderMask(
                  shaderCallback: (b) => const LinearGradient(
                    colors: [Color(0xFFFF8C00), Color(0xFFFFB800)],
                  ).createShader(b),
                  child: const Text('ASEM PRO', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Active waybill card
            if (_activeWaybill != null) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFFF8C00).withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF8C00).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('Активен', style: TextStyle(color: Color(0xFFFF8C00), fontSize: 12, fontWeight: FontWeight.w600)),
                        ),
                        const Spacer(),
                        Text('ЭПЛ № ${_activeWaybill!['waybillNumber'] ?? ''}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _eplInfoRow('Дата', _activeWaybill!['date']?.toString() ?? ''),
                    _eplInfoRow('Автомобиль', _activeWaybill!['carModel']?.toString() ?? ''),
                    _eplInfoRow('Гос. номер', _activeWaybill!['plateNumber']?.toString() ?? ''),
                    _eplInfoRow('Действует до', _formatExpiresAt(_activeWaybill!['expiresAt'])),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () async {
                              try {
                                final pdfBytes = await WaybillPdfService.generateBytes(_activeWaybill!);
                                if (!mounted) return;
                                Navigator.push(context, MaterialPageRoute(
                                  builder: (_) => WaybillPreviewScreen(
                                    pdfBytes: pdfBytes,
                                    waybillNumber: _activeWaybill!['waybillNumber']?.toString() ?? '',
                                  ),
                                ));
                              } catch (e) {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
                                  );
                                }
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF8C00),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Открыть ЭПЛ'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () async {
                              final ok = await showDialog<bool>(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  backgroundColor: const Color(0xFF1A1A1A),
                                  title: const Text('Закрыть путевой лист?'),
                                  content: const Text('После закрытия можно будет создать новый.'),
                                  actions: [
                                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                                    ElevatedButton(
                                      onPressed: () => Navigator.pop(ctx, true),
                                      child: const Text('Закрыть'),
                                    ),
                                  ],
                                ),
                              );
                              if (ok == true) await _closeWaybill();
                            },
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: Color(0xFFEF4444)),
                              foregroundColor: const Color(0xFFEF4444),
                              padding: const EdgeInsets.symmetric(vertical: 14),
                            ),
                            child: const Text('Закрыть ЭПЛ'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Create new waybill
            if (_activeWaybill == null && _driverData != null)
              SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WaybillScreen(
                          driverData: _driverData!,
                          driverDocId: _driverDocId ?? '',
                        ),
                      ),
                    );
                    await _checkActiveWaybill();
                  },
                  icon: const Icon(Icons.add_circle_outline, size: 28),
                  label: const Text('Создать ЭПЛ', style: TextStyle(fontSize: 16)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8C00),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            if (_activeWaybill != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF2A2A2A)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFFFF8C00), size: 20),
                    SizedBox(width: 10),
                    Expanded(child: Text(
                      'Закройте текущий путевой лист, чтобы создать новый',
                      style: TextStyle(color: Color(0xFF8A8A8A), fontSize: 13),
                    )),
                  ],
                ),
              ),

            const SizedBox(height: 24),

            // History
            const Text('История выпусков', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            _buildWaybillHistory(),
          ],
        ),
      ),
    );
  }

  Widget _eplInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF8A8A8A), fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13)),
        ],
      ),
    );
  }

  /// Форматирует Timestamp expiresAt в строку "dd.MM.yyyy HH:mm" (МСК).
  String _formatExpiresAt(dynamic expiresAt) {
    if (expiresAt == null) return '—';
    DateTime? dt;
    if (expiresAt is Timestamp) {
      dt = expiresAt.toDate();
    } else if (expiresAt is DateTime) {
      dt = expiresAt;
    }
    if (dt == null) return '—';
    // Переводим в МСК (UTC+3)
    final msk = dt.toUtc().add(const Duration(hours: 3));
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(msk.day)}.${two(msk.month)}.${msk.year} ${two(msk.hour)}:${two(msk.minute)}';
  }

  Widget _buildWaybillHistory() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('waybills')
          .where('driverId', isEqualTo: _driverDocId ?? user.uid)
          .orderBy('createdAt', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFFFF8C00)));
        }
        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(child: Text('Нет путевых листов', style: TextStyle(color: Color(0xFF8A8A8A)))),
          );
        }
        return Column(
          children: docs.map((doc) {
            final data = doc.data() as Map<String, dynamic>;
            final isClosed = data['status'] == 'closed';
            return Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: const Color(0xFFFF8C00).withValues(alpha: 0.15),
                  child: Icon(Icons.description, color: isClosed ? const Color(0xFF22C55E) : const Color(0xFFFF8C00)),
                ),
                title: Text('АП №${data['waybillNumber'] ?? ''}'),
                subtitle: Text(data['date']?.toString() ?? '', style: const TextStyle(color: Color(0xFF8A8A8A))),
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: isClosed ? const Color(0xFF22C55E).withValues(alpha: 0.15) : const Color(0xFFFF8C00).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    isClosed ? 'Закрыт' : 'Открыт',
                    style: TextStyle(color: isClosed ? const Color(0xFF22C55E) : const Color(0xFFFF8C00), fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
                onTap: () async {
                  try {
                    final pdfBytes = await WaybillPdfService.generateBytes(data);
                    if (!mounted) return;
                    Navigator.push(context, MaterialPageRoute(
                      builder: (_) => WaybillPreviewScreen(
                        pdfBytes: pdfBytes,
                        waybillNumber: data['waybillNumber']?.toString() ?? '',
                      ),
                    ));
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
                      );
                    }
                  }
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }

  // ========== PROFILE PAGE ==========
  Widget _buildProfilePage() {
    if (_driverData == null) {
      return const SafeArea(
        child: Center(child: Text('Данные водителя не найдены.\nОбратитесь к администратору.', textAlign: TextAlign.center)),
      );
    }
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const SizedBox(height: 16),
            // Avatar
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFFF8C00), width: 3),
              ),
              child: const CircleAvatar(
                radius: 36,
                backgroundColor: Color(0xFF1A1A1A),
                child: Icon(Icons.person, size: 44, color: Color(0xFFFF8C00)),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _driverData?['fullName']?.toString() ?? '',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            _profileCard([
              _profileRow(Icons.phone, 'Телефон', _driverData?['phone']?.toString() ?? ''),
              _profileRow(Icons.directions_car, 'Автомобиль', _driverData?['carModel']?.toString() ?? ''),
              _profileRow(Icons.confirmation_number, 'Гос. номер', _driverData?['plateNumber']?.toString() ?? ''),
              _profileRow(Icons.garage, 'Гаражный №', _driverData?['garageNumber']?.toString() ?? ''),
              _profileRow(Icons.business, 'Организация', _driverData?['orgName']?.toString() ?? ''),
              _profileRow(Icons.star, 'Тариф', 'Стандарт'),
            ]),
          ],
        ),
      ),
    );
  }

  Widget _profileCard(List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: Column(children: children),
    );
  }

  Widget _profileRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFFF8C00), size: 20),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(color: Color(0xFF8A8A8A), fontSize: 14)),
          const Spacer(),
          Flexible(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  // ========== SETTINGS PAGE ==========
  Widget _buildSettingsPage() {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            const Text('Настройки', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            _settingsItem(Icons.person_outline, 'Профиль', () => setState(() => _currentIndex = 1)),
            _settingsItem(Icons.notifications_outlined, 'Уведомления', () {}),
            _settingsItem(Icons.security_outlined, 'Безопасность', () {}),
            _settingsItem(Icons.language, 'Язык', () {}, trailing: 'Русский'),
            _settingsItem(Icons.info_outline, 'О приложении', () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1A1A1A),
                  title: const Text('AsemPro'),
                  content: const Text('Версия 2.0\nЭлектронные путевые листы\n\nASEM PRO - Профессиональный подход к каждой поездке'),
                  actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
                ),
              );
            }),
            const SizedBox(height: 16),
            _settingsItem(Icons.delete_forever, 'Удалить аккаунт', () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => const DeleteAccountScreen()));
            }, isDestructive: true),
            _settingsItem(Icons.logout, 'Выйти из аккаунта', () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: const Color(0xFF1A1A1A),
                  title: const Text('Выйти?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
                      child: const Text('Выйти'),
                    ),
                  ],
                ),
              );
              if (ok == true) await FirebaseAuth.instance.signOut();
            }, isDestructive: true),
          ],
        ),
      ),
    );
  }

  Widget _settingsItem(IconData icon, String title, VoidCallback onTap, {String? trailing, bool isDestructive = false}) {
    final color = isDestructive ? const Color(0xFFEF4444) : const Color(0xFFFF8C00);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF2A2A2A)),
      ),
      child: ListTile(
        leading: Icon(icon, color: color, size: 22),
        title: Text(title, style: TextStyle(color: isDestructive ? const Color(0xFFEF4444) : Colors.white)),
        trailing: trailing != null
            ? Text(trailing, style: const TextStyle(color: Color(0xFF8A8A8A)))
            : Icon(Icons.chevron_right, color: const Color(0xFF8A8A8A).withValues(alpha: 0.5)),
        onTap: onTap,
      ),
    );
  }
}
