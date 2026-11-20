import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import '../services/waybill_pdf_service.dart';
import 'waybill_preview_screen.dart';
import 'signature_screen.dart';

/// Текущее московское время (UTC+3) — ТОЛЬКО для отображения дат/времени.
/// Для хранения моментов времени используйте DateTime.now() (настоящий UTC).
DateTime _moscowNow() => DateTime.now().toUtc().add(const Duration(hours: 3));

const _months = [
  '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
];

/// Запрос допуска на линию и получение путевого листа.
///
/// 1. Водитель вводит одометр, ставит подпись и нажимает «Запросить допуск» —
///    создаётся путевой лист со статусом `pending`.
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
  Timer? _previewRetry;
  bool _checkingPreview = false;
  bool _previewUnavailable = false;
  final _odometerController = TextEditingController();
  Uint8List? _signatureImage;

  String? _requestId;
  Map<String, dynamic>? _request;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;

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
    _previewRetry?.cancel();
    _sub?.cancel();
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
              _infoBox('Если медик и мастер включили автодопуск, ЭПЛ откроется сразу. '
                  'В листе будут видны результаты осмотров, которые уже поступили.'),
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
                _infoBox(_previewUnavailable
                    ? 'Не удалось загрузить настройки. Приложение повторит проверку автоматически.'
                    : 'Проверяем автодопуск. Если он выключен, ЭПЛ откроется после обеих отметок.'),
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
    _sub?.cancel();
    _sub = FirebaseFirestore.instance
        .collection('waybills')
        .doc(id)
        .snapshots()
        .listen((snap) {
      final data = snap.data();
      if (!mounted || data == null) return;
      setState(() => _request = data);
      _previewRetry?.cancel();
      // Оба допустили — сразу показываем путевой лист.
      if (data['status'] == 'active') {
        _openPdf(data);
      } else if (data['status'] == 'pending') {
        _checkPreview(id);
      }
    }, onError: (e) => _showError('Ошибка связи: $e'));
  }

  Future<void> _checkPreview(String id) async {
    final user = FirebaseAuth.instance.currentUser;
    if (_checkingPreview || _opened || user == null || _isCancelling) return;
    _previewRetry?.cancel();
    _checkingPreview = true;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      Future<bool> load() async {
        final token = await user.getIdToken();
        final req = await client.postUrl(Uri.https('admin.radev.digital', '/api/inspections/waybill-preview'));
        req.headers.contentType = ContentType.json;
        req.write(jsonEncode({'idToken': token, 'waybillId': id}));
        final response = await req.close();
        final body = await response.transform(utf8.decoder).join();
        if (response.statusCode != 200) throw HttpException('HTTP ${response.statusCode}');
        return jsonDecode(body)['enabled'] == true;
      }
      final enabled = await load().timeout(const Duration(seconds: 12));
      if (mounted && _previewUnavailable) setState(() => _previewUnavailable = false);
      if (mounted && !_isCancelling && user.uid == FirebaseAuth.instance.currentUser?.uid &&
          _requestId == id && _request?['status'] == 'pending' && enabled) {
        await _openPdf(_request!);
      }
    } catch (e) {
      if (mounted && !_previewUnavailable) setState(() => _previewUnavailable = true);
      debugPrint('Waybill preview: $e');
    } finally {
      client.close(force: true);
      _checkingPreview = false;
      if (mounted && !_opened && _requestId == id && _request?['status'] == 'pending') {
        _previewRetry = Timer(const Duration(seconds: 30), () => _checkPreview(id));
      }
    }
  }

  Future<void> _submitRequest() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError('Сессия истекла. Войдите снова.');
      return;
    }

    final odometer = int.tryParse(_odometerController.text.trim());
    if (odometer == null || odometer <= 0) {
      _showError('Введите корректное показание одометра');
      return;
    }

    setState(() => _isSubmitting = true);

    String s(String key) {
      final v = widget.driverData[key];
      return v == null ? '' : v.toString();
    }

    final now = DateTime.now();
    final msk = _moscowNow();
    // Номер листа: время с точностью до 0,1 с — совпадения между водителями практически исключены.
    final waybillNumber = '${now.millisecondsSinceEpoch ~/ 100}';

    final waybillData = <String, dynamic>{
      'waybillNumber': waybillNumber,
      // Дата запроса; при выпуске листа заменяется датой допуска.
      'date': DateFormat('dd.MM.yyyy').format(msk),
      'dateFormatted': '«${DateFormat('dd').format(msk)}» ${_months[msk.month]} ${msk.year} г.',
      'driverId': widget.driverDocId,
      'authUid': user.uid,
      'driverName': s('fullName'),
      'driverPhone': s('phone'),
      'carModel': s('carModel'),
      'plateNumber': s('plateNumber'),
      'license': s('license'),
      'licenseClass': s('licenseClass'),
      'licenseIssued': s('licenseIssued'),
      'licenseExpires': s('licenseExpires'),
      'driverIdNumber': s('driverIdNumber'),
      'osgop': s('osgop'),
      'garageNumber': s('garageNumber'),
      'tabNumber': s('tabNumber'),
      'snils': s('snils'),
      'driverInn': s('inn'),
      'transportType': s('transportType'),
      'commType': s('commType'),
      'orgName': s('orgName'),
      'orgAddress': s('orgAddress'),
      'ogrn': s('orgOgrn'),
      'orgInn': s('orgInn'),
      'orgPhone': s('orgPhone'),
      'okud': s('okud').isEmpty ? '0345001' : s('okud'),
      'okpo': s('okpo'),
      'permitNumber': s('permit'),
      'mintransOrder': s('mintrans').isEmpty ? '390 ОТ 28.09.2022' : s('mintrans'),
      'medCert': s('medCert'),
      'techCert': s('techCert'),
      'odometerStart': odometer.toString(),
      'status': 'pending',
      'createdAt': FieldValue.serverTimestamp(),
    };
    if (_signatureImage != null) {
      waybillData['signatureData'] = 'data:image/png;base64,${base64Encode(_signatureImage!)}';
    }

    final db = FirebaseFirestore.instance;
    final ref = db.collection('waybills').doc();
    // Лист и счётчик лимита пишем одной пачкой: либо оба, либо ничего.
    final batch = db.batch()
      ..set(ref, waybillData)
      ..set(
        db.collection('driverCounters').doc(user.uid),
        {'count': FieldValue.increment(1)},
        SetOptions(merge: true),
      );

    try {
      await batch.commit().timeout(const Duration(seconds: 20));
    } on TimeoutException {
      // Нет связи: запрос сохранён на телефоне и уйдёт сам, когда появится интернет.
      _showError('Нет связи с сервером. Запрос отправится, когда появится интернет.');
    } on FirebaseException catch (e) {
      _showError('Ошибка Firebase: ${e.message ?? e.code}');
      if (mounted) setState(() => _isSubmitting = false);
      return;
    } catch (e) {
      _showError('Не удалось отправить запрос: $e');
      if (mounted) setState(() => _isSubmitting = false);
      return;
    }
    if (!mounted) return;
    setState(() {
      _isSubmitting = false;
      _requestId = ref.id;
    });
    _listen(ref.id);
  }

  Future<void> _cancelRequest() async {
    final id = _requestId;
    if (id == null) return;
    setState(() => _isCancelling = true);
    try {
      await FirebaseFirestore.instance.collection('waybills').doc(id).update({
        'status': 'cancelled',
        'closedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _showError('Не удалось отменить: $e');
      if (mounted) setState(() => _isCancelling = false);
    }
  }

  Future<void> _openPdf(Map<String, dynamic> data) async {
    if (_opened || _isCancelling) return;
    _opened = true;
    try {
      final merged = <String, dynamic>{...data, 'docId': _requestId};
      if (_signatureImage != null) merged['_signatureBytes'] = _signatureImage;
      final pdfBytes = await WaybillPdfService.generateBytes(merged);
      if (!mounted) return;
      if (_isCancelling || _request?['status'] != data['status']) {
        _opened = false;
        if (!_isCancelling && _request?['status'] == 'active') await _openPdf(_request!);
        return;
      }
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
