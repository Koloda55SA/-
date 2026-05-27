import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/waybill_pdf_service.dart';
import 'waybill_preview_screen.dart';
import 'signature_screen.dart';

/// Возвращает текущее время в МСК (UTC+3), независимо от часового пояса устройства.
DateTime _moscowNow() => DateTime.now().toUtc().add(const Duration(hours: 3));

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

  // Все времена в МСК. Фиксированные отступы по требованию заказчика:
  //   Медосмотр   = сейчас - 30 минут
  //   Техконтроль = медосмотр + 5 минут
  //   Начало смены / выезд = техконтроль + 7 минут (т.е. медосмотр + 12 минут)
  //   Окончание смены = начало смены + 12 часов
  late DateTime _now;
  late DateTime _medDt;
  late DateTime _techDt;
  late DateTime _shiftStartDt;
  late DateTime _departureDt;
  late DateTime _shiftEndDt;
  late DateTime _expiresAtDt;

  @override
  void initState() {
    super.initState();
    _computeTimes();
  }

  void _computeTimes() {
    _now = _moscowNow();
    _medDt = _now.subtract(const Duration(minutes: 30));
    _techDt = _medDt.add(const Duration(minutes: 5));
    _shiftStartDt = _techDt.add(const Duration(minutes: 7));
    _departureDt = _shiftStartDt;
    _shiftEndDt = _shiftStartDt.add(const Duration(hours: 12));
    _expiresAtDt = _shiftEndDt;
  }

  @override
  Widget build(BuildContext context) {
    final driver = widget.driverData;
    return Scaffold(
      appBar: AppBar(title: const Text('Новый путевой лист')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Driver info card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Данные для путевого листа', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  _infoRow('Дата', DateFormat('dd.MM.yyyy').format(_now)),
                  _infoRow('Водитель', driver['fullName']?.toString() ?? ''),
                  _infoRow('Автомобиль', '${driver['carModel'] ?? ''} (${driver['plateNumber'] ?? ''})'),
                  _infoRow('Организация', driver['orgName']?.toString() ?? ''),
                  const SizedBox(height: 8),
                  _infoRow(
                    'Действует до',
                    '${DateFormat('dd.MM.yyyy').format(_expiresAtDt)} ${_formatHms(_expiresAtDt).substring(0, 5)}',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Odometer input
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Заполните данные', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _odometerController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Показание одометра (км)',
                      helperText: 'В путевом листе будет записано на 10 км меньше',
                      helperStyle: TextStyle(color: Color(0xFF8A8A8A), fontSize: 11),
                      prefixIcon: Icon(Icons.speed, color: Color(0xFFFF8C00)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Signature
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF2A2A2A)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Подпись водителя', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 12),
                  if (_signatureImage != null)
                    Container(
                      width: double.infinity,
                      height: 100,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Image.memory(_signatureImage!, fit: BoxFit.contain),
                    )
                  else
                    Container(
                      width: double.infinity,
                      height: 100,
                      decoration: BoxDecoration(
                        color: const Color(0xFF111111),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: const Color(0xFF2A2A2A)),
                      ),
                      child: const Center(
                        child: Text('Подпись не добавлена', style: TextStyle(color: Color(0xFF8A8A8A))),
                      ),
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final result = await Navigator.push<Uint8List>(
                          context,
                          MaterialPageRoute(builder: (_) => const SignatureScreen()),
                        );
                        if (result != null && mounted) {
                          setState(() => _signatureImage = result);
                        }
                      },
                      icon: const Icon(Icons.draw, color: Color(0xFFFF8C00)),
                      label: Text(_signatureImage != null ? 'Изменить подпись' : 'Добавить подпись'),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFFFF8C00)),
                        foregroundColor: const Color(0xFFFF8C00),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Generate button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isGenerating ? null : _generateWaybill,
                icon: _isGenerating
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.picture_as_pdf, size: 28),
                label: Text(_isGenerating ? 'Генерация...' : 'Сгенерировать путевой лист', style: const TextStyle(fontSize: 16)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF8C00),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF8A8A8A), fontSize: 14)),
          Flexible(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w500), textAlign: TextAlign.right, overflow: TextOverflow.ellipsis)),
        ],
      ),
    );
  }

  String _formatHms(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}';

  Future<void> _generateWaybill() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { _showError('Сессия истекла. Войдите снова.'); return; }

    final odometerInput = _odometerController.text.trim();
    if (odometerInput.isEmpty) { _showError('Введите показание одометра'); return; }
    final odometerEntered = int.tryParse(odometerInput);
    if (odometerEntered == null || odometerEntered <= 0) {
      _showError('Введите корректное число для одометра');
      return;
    }
    // Заказчик: автоматически "откатить" одометр на 10 км назад.
    final odometerAdjusted = odometerEntered - 10;

    setState(() => _isGenerating = true);

    try {
      // Пересчитываем времена на момент генерации, чтобы они не "устарели",
      // если экран был открыт долго.
      _computeTimes();
      final waybillNumber = '${_now.millisecondsSinceEpoch ~/ 1000}';

      String s(Map<String, dynamic> m, String key) {
        final v = m[key];
        return v == null ? '' : v.toString();
      }

      final driver = widget.driverData;

      // Use per-driver organization data (set during admin registration)
      final waybillData = <String, dynamic>{
        'waybillNumber': waybillNumber,
        'date': DateFormat('dd.MM.yyyy').format(_now),
        'dateFormatted': '«${DateFormat('dd').format(_now)}» ${_getMonthName(_now.month)} ${_now.year} г.',
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
        // Per-driver organization data
        'orgName': s(driver, 'orgName'),
        'orgAddress': s(driver, 'orgAddress'),
        'ogrn': s(driver, 'orgOgrn'),
        'orgInn': s(driver, 'orgInn'),
        'orgPhone': s(driver, 'orgPhone'),
        'okud': s(driver, 'okud').isEmpty ? '0345001' : s(driver, 'okud'),
        'okpo': s(driver, 'okpo'),
        'permitNumber': s(driver, 'permit'),
        'mintransOrder': '390 ОТ 28.09.2022',
        // Electronic signatures from driver org data
        'medName': s(driver, 'medName'),
        'medCert': s(driver, 'medCert'),
        'medIssued': s(driver, 'medIssued'),
        'medExpires': s(driver, 'medExpires'),
        'techName': s(driver, 'techName'),
        'techCert': s(driver, 'techCert'),
        'techIssued': s(driver, 'techIssued'),
        'techExpires': s(driver, 'techExpires'),
        // Одометр (с автоматическим откатом -10 км по требованию заказчика)
        'odometerStart': odometerAdjusted.toString(),
        // Времена в МСК с фиксированными отступами
        'medTime': _formatHms(_medDt),
        'techTime': _formatHms(_techDt),
        'shiftStart': _formatHms(_shiftStartDt),
        'departureTime': _formatHms(_departureDt),
        'shiftEnd': _formatHms(_shiftEndDt),
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
        // Путевой лист действителен 12 часов от начала смены
        'expiresAt': Timestamp.fromDate(_expiresAtDt.toUtc()),
      };

      // Подпись водителя сохраняем как base64 data URL (совместимо с веб-печатью).
      if (_signatureImage != null) {
        final b64 = base64Encode(_signatureImage!);
        waybillData['signatureData'] = 'data:image/png;base64,$b64';
      }

      // Сохраняем в Firestore (без локальных служебных полей)
      await FirebaseFirestore.instance.collection('waybills').add(waybillData);

      // Для PDF добавляем bytes напрямую, чтобы не декодировать base64 заново
      if (_signatureImage != null) {
        waybillData['_signatureBytes'] = _signatureImage;
      }

      // Generate PDF
      final pdfBytes = await WaybillPdfService.generateBytes(waybillData);

      if (!mounted) return;

      await Navigator.push(context, MaterialPageRoute(
        builder: (_) => WaybillPreviewScreen(pdfBytes: pdfBytes, waybillNumber: waybillNumber),
      ));

      if (mounted) {
        Navigator.pop(context); // Return to home
      }
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
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  String _getMonthName(int month) {
    const months = ['', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'];
    return months[month];
  }

  @override
  void dispose() {
    _odometerController.dispose();
    super.dispose();
  }
}
