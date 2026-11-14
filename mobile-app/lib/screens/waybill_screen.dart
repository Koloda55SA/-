import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api.dart';
import '../theme/app_theme.dart';
import '../services/waybill_pdf_service.dart';
import 'waybill_preview_screen.dart';
import 'signature_screen.dart';

/// Текущее московское время (UTC+3) — ТОЛЬКО для отображения дат/времени.
/// Для хранения моментов времени используйте DateTime.now() (настоящий UTC).
DateTime _moscowNow() => DateTime.now().toUtc().add(const Duration(hours: 3));

/// Запрос допуска на линию и получение путевого листа.
///
/// 1. Водитель вводит одометр, ставит подпись и нажимает «Запросить допуск» —
///    сервер создаёт путевой лист со статусом `pending` (данные листа берутся
///    из профиля водителя на сервере).
/// 2. Медик и мастер на сайте сами отмечают допуск под своими учётными
///    записями. Время осмотров в листе — реальное время их отметок.
/// 3. Как только оба допустили, статус становится `active` и путевой лист
///    открывается автоматически.
///
/// Если передан [existingRequestId] — экран сразу открывается в режиме
/// ожидания этого запроса (например, при переходе с главного экрана).
class WaybillScreen extends StatefulWidget {
  final Map<String, dynamic> driverData;
  final String driverDocId;
  final String? existingRequestId;

  const WaybillScreen({
    super.key,
    required this.driverData,
    required this.driverDocId,
    this.existingRequestId,
  });

  @override
  State<WaybillScreen> createState() => _WaybillScreenState();
}

class _WaybillScreenState extends State<WaybillScreen> {
  bool _isSubmitting = false;
  bool _isCancelling = false;
  bool _opened = false;
  final _odometerController = TextEditingController();
  Uint8List? _signatureImage;

  String? _requestId;
  Map<String, dynamic>? _request;
  /// Пока ждём допуска — спрашиваем сервер каждые 4 секунды.
  late final Poller _poller = Poller(_loadRequest, const Duration(seconds: 4));

  @override
  void initState() {
    super.initState();
    final existing = widget.existingRequestId;
    if (existing != null) {
      _requestId = existing;
      _listen(existing);
    }
  }

  @override
  void dispose() {
    _poller.stop();
    _odometerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: Text(_requestId == null ? 'Новый путевой лист' : 'Допуск на линию')),
      body: SafeArea(child: _requestId == null ? _buildForm() : _buildWaiting()),
    );
  }

  // ───────────────────────── Форма запроса ─────────────────────────
  Widget _buildForm() {
    final driver = widget.driverData;
    final today = DateFormat('dd.MM.yyyy').format(_moscowNow());

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        // ─── Сводка
        AppCard(
          padding: const EdgeInsets.all(18),
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF1B1408), Color(0xFF120E0A)],
          ),
          border: Border.all(color: AppTheme.primary.withValues(alpha: 0.3)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      gradient: AppTheme.primaryGradient,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.description, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Сводка путевого листа',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _row(Icons.calendar_today_outlined, 'Дата', today),
              _row(Icons.person_outline, 'Водитель', (driver['fullName'] ?? '').toString()),
              _row(
                Icons.directions_car_outlined,
                'Автомобиль',
                '${driver['carModel'] ?? ''} (${driver['plateNumber'] ?? ''})',
              ),
              _row(Icons.business_outlined, 'Организация', (driver['orgName'] ?? '').toString()),
              const SizedBox(height: 6),
              _infoBox('После запроса подойдите к медику и мастеру. Путевой лист '
                  'выпускается, когда оба отметят допуск, и действует 12 часов.'),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ─── Одометр
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.speed, color: AppTheme.primary, size: 18),
                  SizedBox(width: 8),
                  Text('Одометр', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _odometerController,
                keyboardType: TextInputType.number,
                style: const TextStyle(fontSize: 16),
                decoration: const InputDecoration(
                  labelText: 'Показание (км)',
                  hintText: 'Например, 152340',
                  prefixIcon: Icon(Icons.speed, color: AppTheme.primary, size: 20),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: const [
                  Icon(Icons.lightbulb_outline, size: 12, color: AppTheme.textFaint),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Укажите текущее показание — мастер сверит его при техконтроле',
                      style: TextStyle(color: AppTheme.textFaint, fontSize: 11),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // ─── Подпись
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.draw_outlined, color: AppTheme.primary, size: 18),
                  SizedBox(width: 8),
                  Text('Подпись водителя', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                height: 110,
                decoration: BoxDecoration(
                  color: _signatureImage != null ? Colors.white : AppTheme.bgSoft,
                  borderRadius: BorderRadius.circular(12),
                  border: _signatureImage != null ? null : Border.all(color: AppTheme.border),
                ),
                child: _signatureImage != null
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(_signatureImage!, fit: BoxFit.contain),
                      )
                    : const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.gesture, color: AppTheme.textFaint, size: 32),
                            SizedBox(height: 6),
                            Text('Подпись не добавлена',
                                style: TextStyle(color: AppTheme.textFaint, fontSize: 12)),
                          ],
                        ),
                      ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final result = await Navigator.push<Uint8List>(
                    context,
                    MaterialPageRoute(builder: (_) => const SignatureScreen()),
                  );
                  if (result != null && mounted) {
                    setState(() => _signatureImage = result);
                  }
                },
                icon: const Icon(Icons.draw, color: AppTheme.primary, size: 18),
                label: Text(_signatureImage != null ? 'Изменить подпись' : 'Добавить подпись'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppTheme.primary,
                  side: const BorderSide(color: AppTheme.primary),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 22),

        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: _isSubmitting ? null : _submitRequest,
            icon: _isSubmitting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                : const Icon(Icons.how_to_reg, size: 22),
            label: Text(
              _isSubmitting ? 'Отправка...' : 'Запросить допуск',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
          ),
        ),
      ],
    );
  }

  // ───────────────────────── Ожидание допуска ─────────────────────────
  Widget _buildWaiting() {
    final r = _request;
    if (r == null) {
      return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
    }
    final status = (r['status'] ?? 'pending').toString();
    final rejected = status == 'rejected';
    final cancelled = status == 'cancelled';
    final active = status == 'active';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        AppCard(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    rejected || cancelled
                        ? Icons.block
                        : active
                            ? Icons.check_circle
                            : Icons.hourglass_top,
                    color: rejected || cancelled
                        ? AppTheme.danger
                        : active
                            ? AppTheme.success
                            : AppTheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      rejected
                          ? 'Не допущен к выезду'
                          : cancelled
                              ? 'Запрос отменён'
                              : active
                                  ? 'Допуск получен'
                                  : 'Ожидает допуска',
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _checkRow('Медосмотр', r, 'med'),
              _checkRow('Техконтроль', r, 'tech'),
              if (rejected && (r['rejectReason'] ?? '').toString().isNotEmpty) ...[
                const SizedBox(height: 10),
                _infoBox('Причина: ${r['rejectReason']}', color: AppTheme.danger),
              ],
              if (!rejected && !cancelled && !active) ...[
                const SizedBox(height: 10),
                _infoBox('Подойдите к медику и мастеру. Как только оба отметят допуск, '
                    'путевой лист откроется здесь автоматически.'),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (active)
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () => _openPdf(r),
              icon: const Icon(Icons.picture_as_pdf),
              label: const Text('Открыть путевой лист'),
            ),
          )
        else if (status == 'pending')
          SizedBox(
            height: 52,
            child: OutlinedButton.icon(
              onPressed: _isCancelling ? null : _cancelRequest,
              icon: const Icon(Icons.close, color: AppTheme.danger),
              label: const Text('Отменить запрос', style: TextStyle(color: AppTheme.danger)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.5)),
              ),
            ),
          )
        else
          SizedBox(
            height: 52,
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Назад'),
            ),
          ),
      ],
    );
  }

  Widget _checkRow(String label, Map<String, dynamic> r, String prefix) {
    final st = (r['${prefix}Status'] ?? '').toString();
    final name = (r['${prefix}Name'] ?? '').toString();
    final time = (r['${prefix}Time'] ?? '').toString();
    final IconData icon;
    final Color color;
    final String text;
    if (st == 'ok') {
      icon = Icons.check_circle;
      color = AppTheme.success;
      text = [name, if (time.length >= 5) time.substring(0, 5)].where((s) => s.isNotEmpty).join(' · ');
    } else if (st == 'rejected') {
      icon = Icons.cancel;
      color = AppTheme.danger;
      text = name.isEmpty ? 'Не допущен' : '$name · не допущен';
    } else {
      icon = Icons.schedule;
      color = AppTheme.textMuted;
      text = 'Ожидает отметки';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: color, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoBox(String text, {Color color = AppTheme.info}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: color, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(color: AppTheme.textMuted, fontSize: 12)),
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
          Icon(icon, size: 14, color: AppTheme.textMuted),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(color: AppTheme.textMuted, fontSize: 13)),
          const Spacer(),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  // ───────────────────────── Логика ─────────────────────────
  void _listen(String id) {
    _requestId = id;
    _poller.start();
  }

  Future<void> _loadRequest() async {
    final id = _requestId;
    if (id == null) return;
    try {
      final data = await Api.get('/api/driver/waybills/${Uri.encodeComponent(id)}');
      _applyRequest(data);
    } on ApiException catch (e) {
      // Без связи молча ждём следующего опроса.
      if (!e.isNetwork) _showError(e.message);
    }
  }

  void _applyRequest(Map<String, dynamic> data) {
    if (!mounted) return;
    setState(() => _request = data);
    final status = data['status'];
    // Решение принято — дальше опрашивать незачем.
    if (status != 'pending') _poller.stop();
    // Оба допустили — сразу показываем путевой лист.
    if (status == 'active' && !_opened) {
      _opened = true;
      _openPdf(data);
    }
  }

  Future<void> _submitRequest() async {
    final odometer = int.tryParse(_odometerController.text.trim());
    if (odometer == null || odometer <= 0) {
      _showError('Введите корректное показание одометра');
      return;
    }

    setState(() => _isSubmitting = true);

    final body = <String, dynamic>{'odometer': odometer};
    if (_signatureImage != null) {
      body['signatureData'] = 'data:image/png;base64,${base64Encode(_signatureImage!)}';
    }

    Map<String, dynamic> created;
    try {
      created = await Api.post('/api/driver/waybills', body);
    } on ApiException catch (e) {
      if (e.code == 'already-exists') {
        // Запрос уже есть (например, ответ сервера не дошёл с первого раза) —
        // переходим к нему, а не создаём второй.
        try {
          final r = await Api.get('/api/driver/waybills/current');
          final w = r['waybill'];
          if (w is Map<String, dynamic> && w['id'] != null) {
            if (!mounted) return;
            setState(() => _isSubmitting = false);
            _listen(w['id'].toString());
            _applyRequest(w);
            return;
          }
        } catch (_) {}
      }
      _showError(e.message);
      if (mounted) setState(() => _isSubmitting = false);
      return;
    }
    if (!mounted) return;
    final id = (created['id'] ?? '').toString();
    setState(() => _isSubmitting = false);
    _listen(id);
    _applyRequest(created);
  }

  Future<void> _cancelRequest() async {
    final id = _requestId;
    if (id == null) return;
    setState(() => _isCancelling = true);
    try {
      await Api.post('/api/driver/waybills/${Uri.encodeComponent(id)}/cancel');
      if (mounted) Navigator.pop(context);
    } on ApiException catch (e) {
      // Пока отменяли, медик/мастер уже приняли решение — показываем его.
      _showError(e.code == 'wrong-status' ? 'Запрос уже обработан' : 'Не удалось отменить: ${e.message}');
      if (mounted) setState(() => _isCancelling = false);
      await _poller.refresh();
    }
  }

  Future<void> _openPdf(Map<String, dynamic> data) async {
    try {
      final merged = <String, dynamic>{...data, 'docId': _requestId};
      if (_signatureImage != null) merged['_signatureBytes'] = _signatureImage;
      final pdfBytes = await WaybillPdfService.generateBytes(merged);
      if (!mounted) return;
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => WaybillPreviewScreen(
            pdfBytes: pdfBytes,
            waybillNumber: (data['waybillNumber'] ?? '').toString(),
          ),
        ),
      );
    } catch (e, st) {
      debugPrint('Waybill PDF error: $e\n$st');
      _opened = false;
      _showError('Не удалось сформировать PDF: $e');
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.danger),
    );
  }
}
