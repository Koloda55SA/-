import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../theme/app_theme.dart';
import 'waybill_screen.dart';
import 'waybill_preview_screen.dart';
import 'profile_screen.dart';
import 'settings_screen.dart';
import '../services/waybill_pdf_service.dart';

/// Главный экран после входа: «дом» (новый ЭПЛ + активный лист),
/// личный кабинет (карточка водителя), история, настройки.
class HomeScreen extends StatefulWidget {
  final Map<String, dynamic> driverData;
  final String driverDocId;

  const HomeScreen({super.key, required this.driverData, required this.driverDocId});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      _DashboardPage(driverData: widget.driverData, driverDocId: widget.driverDocId),
      ProfileScreen(driverData: widget.driverData, driverDocId: widget.driverDocId),
      SettingsScreen(driverData: widget.driverData),
    ];

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: pages[_currentIndex],
      bottomNavigationBar: _BottomBar(
        index: _currentIndex,
        onTap: (i) => setState(() => _currentIndex = i),
      ),
    );
  }
}

/// ============== ГЛАВНАЯ (ЭПЛ) ==============
class _DashboardPage extends StatefulWidget {
  final Map<String, dynamic> driverData;
  final String driverDocId;

  const _DashboardPage({required this.driverData, required this.driverDocId});

  @override
  State<_DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<_DashboardPage> {
  Map<String, dynamic>? _activeWaybill;
  String? _activeWaybillId;
  bool _loadingActive = true;
  int _usedQuota = 0;
  bool _requestPending = false;

  /// Лимит выпуска ЭПЛ для водителя (по умолчанию 60).
  int get _quotaLimit {
    final v = widget.driverData['waybillLimit'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    return 60;
  }

  bool get _quotaExhausted => _usedQuota >= _quotaLimit;

  @override
  void initState() {
    super.initState();
    _refreshActive();
    _loadQuota();
  }

  Future<void> _loadQuota() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final counter = await FirebaseFirestore.instance
          .collection('driverCounters')
          .doc(user.uid)
          .get();
      int used = 0;
      final c = counter.data()?['count'];
      if (c is int) used = c;
      if (c is num) used = c.toInt();

      final pending = await FirebaseFirestore.instance
          .collection('quotaRequests')
          .where('authUid', isEqualTo: user.uid)
          .where('status', isEqualTo: 'pending')
          .limit(1)
          .get();

      if (!mounted) return;
      setState(() {
        _usedQuota = used;
        _requestPending = pending.docs.isNotEmpty;
      });
    } catch (e) {
      debugPrint('Quota load error: $e');
    }
  }

  Future<void> _requestMoreQuota() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('quotaRequests').add({
        'driverId': widget.driverDocId,
        'authUid': user.uid,
        'driverName': (widget.driverData['fullName'] ?? '').toString(),
        'phone': (widget.driverData['phone'] ?? '').toString(),
        'orgName': (widget.driverData['orgName'] ?? '').toString(),
        'currentLimit': _quotaLimit,
        'used': _usedQuota,
        'status': 'pending',
        'requestedAt': FieldValue.serverTimestamp(),
      });
      if (!mounted) return;
      setState(() => _requestPending = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Заявка на +60 ЭПЛ отправлена администратору'),
          backgroundColor: AppTheme.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка отправки заявки: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  Future<void> _onCreateWaybill() async {
    if (_quotaExhausted) {
      await _showQuotaDialog();
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WaybillScreen(
          driverData: widget.driverData,
          driverDocId: widget.driverDocId,
        ),
      ),
    );
    await _refreshActive();
    await _loadQuota();
  }

  Future<void> _showQuotaDialog() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Лимит ЭПЛ исчерпан'),
        content: Text(
          _requestPending
              ? 'Вы использовали все $_quotaLimit ЭПЛ. Заявка на дополнительные листы уже отправлена — дождитесь подтверждения администратора.'
              : 'Вы использовали все $_quotaLimit ЭПЛ. Отправить администратору заявку на дополнительные 60 листов?',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Закрыть')),
          if (!_requestPending)
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _requestMoreQuota();
              },
              child: const Text('Отправить заявку'),
            ),
        ],
      ),
    );
  }

  Future<void> _refreshActive() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
      final snap = await FirebaseFirestore.instance
          .collection('waybills')
          .where('authUid', isEqualTo: user.uid)
          .where('status', isEqualTo: 'active')
          .limit(1)
          .get();
      if (!mounted) return;
      setState(() {
        if (snap.docs.isNotEmpty) {
          _activeWaybill = snap.docs.first.data();
          _activeWaybillId = snap.docs.first.id;
        } else {
          _activeWaybill = null;
          _activeWaybillId = null;
        }
        _loadingActive = false;
      });
    } catch (e) {
      debugPrint('Active waybill check error: $e');
      if (mounted) setState(() => _loadingActive = false);
    }
  }

  Future<void> _closeWaybill() async {
    if (_activeWaybillId == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('waybills')
          .doc(_activeWaybillId)
          .update({'status': 'closed', 'closedAt': FieldValue.serverTimestamp()});
      if (mounted) {
        setState(() {
          _activeWaybill = null;
          _activeWaybillId = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Путевой лист закрыт'),
            backgroundColor: AppTheme.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: AppTheme.danger),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final fullName = (widget.driverData['fullName'] ?? '').toString();
    final firstName = fullName.split(' ').length > 1 ? fullName.split(' ')[1] : fullName;

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          await _refreshActive();
          await _loadQuota();
        },
        color: AppTheme.primary,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            // ───── Header
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    gradient: AppTheme.primaryGradient,
                    boxShadow: [
                      BoxShadow(
                        color: AppTheme.primary.withValues(alpha: 0.3),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      'assets/logo/asem_logo.png',
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Добро пожаловать',
                        style: TextStyle(color: AppTheme.textMuted, fontSize: 12),
                      ),
                      Text(
                        firstName.isEmpty ? 'Водитель' : firstName,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const StatusChip(
                  label: 'Активен',
                  color: AppTheme.success,
                  icon: Icons.check_circle,
                ),
              ],
            ),
            const SizedBox(height: 22),

            // ───── Статистика (компактные карточки)
            Row(
              children: [
                Expanded(
                  child: _StatTile(
                    icon: Icons.description_outlined,
                    label: 'Выпущено ЭПЛ',
                    value: '$_usedQuota / $_quotaLimit',
                    color: AppTheme.primary,
                    valueSize: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _StatTile(
                    icon: Icons.directions_car_outlined,
                    label: 'Автомобиль',
                    value: (widget.driverData['plateNumber'] ?? '—').toString(),
                    color: AppTheme.info,
                    valueSize: 14,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // ───── Активный путевой лист
            if (_loadingActive)
              const AppCard(
                child: SizedBox(
                  height: 80,
                  child: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
                ),
              )
            else if (_activeWaybill != null)
              _ActiveWaybillCard(
                data: _activeWaybill!,
                onOpen: () async {
                  try {
                    final bytes = await WaybillPdfService.generateBytes(_activeWaybill!);
                    if (!mounted) return;
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => WaybillPreviewScreen(
                          pdfBytes: bytes,
                          waybillNumber: _activeWaybill!['waybillNumber']?.toString() ?? '',
                        ),
                      ),
                    );
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка: $e'), backgroundColor: AppTheme.danger),
                    );
                  }
                },
                onClose: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Закрыть путевой лист?'),
                      content: const Text('После закрытия можно создать новый.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Отмена')),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Закрыть'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) await _closeWaybill();
                },
              )
            else
              _NewWaybillCard(onTap: _onCreateWaybill),

            if (_quotaExhausted) ...[
              const SizedBox(height: 12),
              _QuotaBanner(
                limit: _quotaLimit,
                pending: _requestPending,
                onRequest: _requestMoreQuota,
              ),
            ],

            const SizedBox(height: 22),

            // ───── Быстрые действия
            const Padding(
              padding: EdgeInsets.only(left: 4, bottom: 10),
              child: Text(
                'Быстрый доступ',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textMuted, letterSpacing: 0.4),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _QuickAction(
                    icon: Icons.person_outline,
                    label: 'Профиль',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => ProfileScreen(
                            driverData: widget.driverData,
                            driverDocId: widget.driverDocId,
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _QuickAction(
                    icon: Icons.settings_outlined,
                    label: 'Настройки',
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SettingsScreen(driverData: widget.driverData),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final double valueSize;

  const _StatTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.valueSize = 22,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(height: 10),
          Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 11)),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(fontSize: valueSize, fontWeight: FontWeight.w800, color: AppTheme.text),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _ActiveWaybillCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  const _ActiveWaybillCard({
    required this.data,
    required this.onOpen,
    required this.onClose,
  });

  String _formatExpires(dynamic v) {
    if (v == null) return '—';
    DateTime? dt;
    if (v is Timestamp) dt = v.toDate();
    if (v is DateTime) dt = v;
    if (dt == null) return '—';
    final msk = dt.toUtc().add(const Duration(hours: 3));
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(msk.day)}.${two(msk.month)}.${msk.year} ${two(msk.hour)}:${two(msk.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(18),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF1B1408), Color(0xFF120E0A)],
      ),
      border: Border.all(color: AppTheme.primary.withValues(alpha: 0.4)),
      shadow: [
        BoxShadow(
          color: AppTheme.primary.withValues(alpha: 0.15),
          blurRadius: 28,
          offset: const Offset(0, 6),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const StatusChip(label: 'АКТИВЕН', color: AppTheme.primary, icon: Icons.bolt),
              const Spacer(),
              Text(
                'АП №${data['waybillNumber'] ?? ''}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _row(Icons.calendar_today_outlined, 'Дата', (data['date'] ?? '').toString()),
          _row(Icons.directions_car_outlined, 'Авто', (data['carModel'] ?? '').toString()),
          _row(Icons.numbers, 'Номер', (data['plateNumber'] ?? '').toString()),
          _row(Icons.timer_outlined, 'Действует до', _formatExpires(data['expiresAt'])),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onOpen,
                  icon: const Icon(Icons.picture_as_pdf, size: 18),
                  label: const Text('Открыть PDF'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onClose,
                  icon: const Icon(Icons.stop_circle_outlined, size: 18, color: AppTheme.danger),
                  label: const Text('Закрыть', style: TextStyle(color: AppTheme.danger)),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.5)),
                    foregroundColor: AppTheme.danger,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.textMuted),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}

class _NewWaybillCard extends StatelessWidget {
  final VoidCallback onTap;
  const _NewWaybillCard({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: AppTheme.primaryGradient,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primary.withValues(alpha: 0.4),
              blurRadius: 32,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.add_circle_outline, color: Colors.white, size: 32),
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Создать ЭПЛ',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  SizedBox(height: 4),
                  Text(
                    'Электронный путевой лист на смену',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AppCard(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, color: AppTheme.primary, size: 22),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}

class _QuotaBanner extends StatelessWidget {
  final int limit;
  final bool pending;
  final VoidCallback onRequest;

  const _QuotaBanner({
    required this.limit,
    required this.pending,
    required this.onRequest,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_clock, color: AppTheme.accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Лимит $limit ЭПЛ исчерпан',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            pending
                ? 'Заявка на дополнительные листы отправлена. Дождитесь подтверждения администратора.'
                : 'Чтобы продолжить выпускать ЭПЛ, запросите у администратора дополнительные 60 листов.',
            style: const TextStyle(color: AppTheme.textMuted, fontSize: 13),
          ),
          if (!pending) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onRequest,
                icon: const Icon(Icons.send_outlined, size: 18),
                label: const Text('Запросить +60 ЭПЛ'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// ============== НИЖНЯЯ НАВИГАЦИЯ ==============
class _BottomBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _BottomBar({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final items = [
      (Icons.home_outlined, Icons.home, 'Главная'),
      (Icons.person_outline, Icons.person, 'Профиль'),
      (Icons.settings_outlined, Icons.settings, 'Настройки'),
    ];
    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: AppTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 18,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: List.generate(items.length, (i) {
            final isActive = i == index;
            return Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onTap(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: isActive ? AppTheme.primary.withValues(alpha: 0.13) : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        isActive ? items[i].$2 : items[i].$1,
                        color: isActive ? AppTheme.primary : AppTheme.textFaint,
                        size: 22,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        items[i].$3,
                        style: TextStyle(
                          color: isActive ? AppTheme.primary : AppTheme.textFaint,
                          fontSize: 11,
                          fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}
