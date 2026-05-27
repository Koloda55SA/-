import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';

import '../theme/app_theme.dart';
import '../services/waybill_pdf_service.dart';
import 'waybill_preview_screen.dart';
import 'signature_screen.dart';

/// Возвращает текущее время в МСК (UTC+3), независимо от часового пояса устройства.
DateTime _moscowNow() => DateTime.now().toUtc().add(const Duration(hours: 3));

/// Экран создания путевого листа. Водитель НЕ видит и НЕ редактирует
/// служебные времена (медосмотр / техконтроль / выезд и т.п.) — они
/// расставляются автоматически в момент генерации.
class WaybillScreen extends StatefulWidget {
  final Map<String, dynamic> driverData;
  final String driverDocId;

  const WaybillScreen({super.key, required this.driverData, required this.driverDocId});

  @override
  State<WaybillScreen> createState() => _WaybillScreenState();
}

class _WaybillScreenState extends State<WaybillScreen> {
  bool _isGenerating = false;
  final _odometerController = TextEditingController();
  Uint8List? _signatureImage;

  @override
  Widget build(BuildContext context) {
    final driver = widget.driverData;
    final today = DateFormat('dd.MM.yyyy').format(_moscowNow());

    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(title: const Text('Новый путевой лист')),
      body: SafeArea(
        child: ListView(
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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppTheme.info.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppTheme.info.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline, color: AppTheme.info, size: 14),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Лист действителен 12 часов после создания',
                            style: TextStyle(color: AppTheme.textMuted, fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
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
                      Text(
                        'Одометр',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
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
                          'В путевом листе будет указано на 10 км меньше',
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
                      Text(
                        'Подпись водителя',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_signatureImage != null)
                    Container(
                      width: double.infinity,
                      height: 110,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(_signatureImage!, fit: BoxFit.contain),
                      ),
                    )
                  else
                    Container(
                      width: double.infinity,
                      height: 110,
                      decoration: BoxDecoration(
                        color: AppTheme.bgSoft,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.gesture, color: AppTheme.textFaint, size: 32),
                            SizedBox(height: 6),
                            Text(
                              'Подпись не добавлена',
                              style: TextStyle(color: AppTheme.textFaint, fontSize: 12),
                            ),
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

            // ─── Сгенерировать
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isGenerating ? null : _generateWaybill,
                icon: _isGenerating
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                    : const Icon(Icons.picture_as_pdf, size: 22),
                label: Text(
                  _isGenerating ? 'Генерация...' : 'Сгенерировать путевой лист',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
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

  // ===== Генерация =====
  Future<void> _generateWaybill() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError('Сессия истекла. Войдите снова.');
      return;
    }

    final odometerInput = _odometerController.text.trim();
    if (odometerInput.isEmpty) {
      _showError('Введите показание одометра');
      return;
    }
    final odometerEntered = int.tryParse(odometerInput);
    if (odometerEntered == null || odometerEntered <= 0) {
      _showError('Введите корректное число для одометра');
      return;
    }
    final odometerAdjusted = odometerEntered - 10;

    setState(() => _isGenerating = true);

    try {
      // ВНУТРЕННЕЕ РАСЧЁТНОЕ ВРЕМЯ.
      // Водитель этого не видит — это служебные значения только для PDF.
      final now = _moscowNow();
      final medDt = now.subtract(const Duration(minutes: 30));
      final techDt = medDt.add(const Duration(minutes: 5));
      final shiftStartDt = techDt.add(const Duration(minutes: 7));
      final departureDt = shiftStartDt;
      final shiftEndDt = shiftStartDt.add(const Duration(hours: 12));
      final expiresAtDt = shiftEndDt;

      final waybillNumber = '${now.millisecondsSinceEpoch ~/ 1000}';

      String s(Map<String, dynamic> m, String key) {
        final v = m[key];
        return v == null ? '' : v.toString();
      }

      String fmtHms(DateTime dt) =>
          '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}:'
          '${dt.second.toString().padLeft(2, '0')}';

      String monthName(int m) {
        const months = [
          '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
          'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря',
        ];
        return months[m];
      }

      final driver = widget.driverData;
      final waybillData = <String, dynamic>{
        'waybillNumber': waybillNumber,
        'date': DateFormat('dd.MM.yyyy').format(now),
        'dateFormatted': '«${DateFormat('dd').format(now)}» ${monthName(now.month)} ${now.year} г.',
        'driverId': widget.driverDocId,
        'authUid': user.uid,
        'driverName': s(driver, 'fullName'),
        'driverPhone': s(driver, 'phone'),
        'carModel': s(driver, 'carModel'),
        'plateNumber': s(driver, 'plateNumber'),
        'license': s(driver, 'license'),
        'licenseClass': s(driver, 'licenseClass'),
        'licenseIssued': s(driver, 'licenseIssued'),
        'licenseExpires': s(driver, 'licenseExpires'),
        'driverIdNumber': s(driver, 'driverIdNumber'),
        'osgop': s(driver, 'osgop'),
        'garageNumber': s(driver, 'garageNumber'),
        'tabNumber': s(driver, 'tabNumber'),
        'snils': s(driver, 'snils'),
        'driverInn': s(driver, 'inn'),
        'transportType': s(driver, 'transportType'),
        'commType': s(driver, 'commType'),
        'orgName': s(driver, 'orgName'),
        'orgAddress': s(driver, 'orgAddress'),
        'ogrn': s(driver, 'orgOgrn'),
        'orgInn': s(driver, 'orgInn'),
        'orgPhone': s(driver, 'orgPhone'),
        'okud': s(driver, 'okud').isEmpty ? '0345001' : s(driver, 'okud'),
        'okpo': s(driver, 'okpo'),
        'permitNumber': s(driver, 'permit'),
        'mintransOrder': '390 ОТ 28.09.2022',
        'medName': s(driver, 'medName'),
        'medCert': s(driver, 'medCert'),
        'medIssued': s(driver, 'medIssued'),
        'medExpires': s(driver, 'medExpires'),
        'techName': s(driver, 'techName'),
        'techCert': s(driver, 'techCert'),
        'techIssued': s(driver, 'techIssued'),
        'techExpires': s(driver, 'techExpires'),
        'odometerStart': odometerAdjusted.toString(),
        // Времена служебные — водитель их не видит, они нужны только для печати
        'medTime': fmtHms(medDt),
        'techTime': fmtHms(techDt),
        'shiftStart': fmtHms(shiftStartDt),
        'departureTime': fmtHms(departureDt),
        'shiftEnd': fmtHms(shiftEndDt),
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        'expiresAt': Timestamp.fromDate(expiresAtDt.toUtc()),
      };

      if (_signatureImage != null) {
        waybillData['signatureData'] = 'data:image/png;base64,${base64Encode(_signatureImage!)}';
      }

      await FirebaseFirestore.instance.collection('waybills').add(waybillData);

      if (_signatureImage != null) {
        waybillData['_signatureBytes'] = _signatureImage;
      }

      final pdfBytes = await WaybillPdfService.generateBytes(waybillData);
      if (!mounted) return;

      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => WaybillPreviewScreen(pdfBytes: pdfBytes, waybillNumber: waybillNumber),
        ),
      );
    } on FirebaseException catch (e) {
      _showError('Ошибка Firebase: ${e.message ?? e.code}');
    } catch (e, st) {
      debugPrint('Waybill generation error: $e\n$st');
      _showError('Не удалось сгенерировать: $e');
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppTheme.danger),
    );
  }

  @override
  void dispose() {
    _odometerController.dispose();
    super.dispose();
  }
}
