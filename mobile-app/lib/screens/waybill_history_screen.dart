import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../theme/app_theme.dart';
import '../services/waybill_pdf_service.dart';
import 'waybill_preview_screen.dart';

/// История путевых листов водителя. Поддерживает фильтр (все / открытые / закрытые)
/// и tap по карточке открывает PDF.
class WaybillHistoryScreen extends StatefulWidget {
  final String driverDocId;
  const WaybillHistoryScreen({super.key, required this.driverDocId});

  @override
  State<WaybillHistoryScreen> createState() => _WaybillHistoryScreenState();
}

class _WaybillHistoryScreenState extends State<WaybillHistoryScreen> {
  String _filter = 'all'; // all | active | closed

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: const Text('История листов'),
        leading: Navigator.canPop(context)
            ? IconButton(icon: const Icon(Icons.arrow_back), onPressed: () => Navigator.pop(context))
            : null,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Фильтр
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Expanded(child: _filterChip('all', 'Все', Icons.list_alt)),
                  const SizedBox(width: 8),
                  Expanded(child: _filterChip('active', 'Открытые', Icons.bolt)),
                  const SizedBox(width: 8),
                  Expanded(child: _filterChip('closed', 'Закрытые', Icons.check_circle_outline)),
                ],
              ),
            ),
            Expanded(
              child: user == null
                  ? const Center(child: Text('Не авторизован'))
                  : _buildList(user.uid),
            ),
          ],
        ),
      ),
    );
  }

  Widget _filterChip(String key, String label, IconData icon) {
    final active = _filter == key;
    return GestureDetector(
      onTap: () => setState(() => _filter = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: active ? AppTheme.primary.withValues(alpha: 0.15) : AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: active ? AppTheme.primary : AppTheme.border,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: active ? AppTheme.primary : AppTheme.textMuted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: active ? AppTheme.primary : AppTheme.textMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(String uid) {
    Query<Map<String, dynamic>> q = FirebaseFirestore.instance
        .collection('waybills')
        .where('authUid', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(100);
    if (_filter == 'active') {
      q = FirebaseFirestore.instance
          .collection('waybills')
          .where('authUid', isEqualTo: uid)
          .where('status', isEqualTo: 'active')
          .orderBy('createdAt', descending: true)
          .limit(100);
    } else if (_filter == 'closed') {
      q = FirebaseFirestore.instance
          .collection('waybills')
          .where('authUid', isEqualTo: uid)
          .where('status', isEqualTo: 'closed')
          .orderBy('createdAt', descending: true)
          .limit(100);
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: q.snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
        }
        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Ошибка: ${snap.error}',
              style: const TextStyle(color: AppTheme.danger),
            ),
          );
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inbox_outlined, color: AppTheme.textFaint, size: 60),
                const SizedBox(height: 16),
                const Text('Пусто', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                const Text(
                  'Здесь будут отображаться все ваши путевые листы',
                  style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final data = docs[i].data();
            final closed = data['status'] == 'closed';
            return _historyItem(data, closed);
          },
        );
      },
    );
  }

  Widget _historyItem(Map<String, dynamic> data, bool closed) {
    return InkWell(
      onTap: () async {
        try {
          final bytes = await WaybillPdfService.generateBytes(data);
          if (!mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => WaybillPreviewScreen(
                pdfBytes: bytes,
                waybillNumber: data['waybillNumber']?.toString() ?? '',
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
      borderRadius: BorderRadius.circular(16),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: (closed ? AppTheme.success : AppTheme.primary).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                closed ? Icons.check_circle_outline : Icons.bolt,
                color: closed ? AppTheme.success : AppTheme.primary,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'АП №${data['waybillNumber'] ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.calendar_today_outlined, size: 12, color: AppTheme.textMuted),
                      const SizedBox(width: 4),
                      Text(
                        (data['date'] ?? '—').toString(),
                        style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.directions_car_outlined, size: 12, color: AppTheme.textMuted),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          (data['plateNumber'] ?? '—').toString(),
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppTheme.textMuted, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            StatusChip(
              label: closed ? 'Закрыт' : 'Открыт',
              color: closed ? AppTheme.success : AppTheme.primary,
            ),
          ],
        ),
      ),
    );
  }
}
