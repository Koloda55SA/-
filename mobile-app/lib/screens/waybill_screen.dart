import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/waybill_pdf_service.dart';
import 'waybill_preview_screen.dart';

class WaybillScreen extends StatefulWidget {
  final Map<String, dynamic> driverData;

  const WaybillScreen({super.key, required this.driverData});

  @override
  State<WaybillScreen> createState() => _WaybillScreenState();
}

class _WaybillScreenState extends State<WaybillScreen> {
  bool _isGenerating = false;
  final _odometerController = TextEditingController();

  // DateTime объекты с полной precision (час:мин:сек)
  late DateTime _medDt;
  late DateTime _techDt;
  late DateTime _shiftStartDt;
  late DateTime _departureDt;
  late DateTime _shiftEndDt;

  @override
  void initState() {
    super.initState();
    _generateRealisticTimes();
  }

  /// Строим времена от текущего момента телефона:
  /// медосмотр прошёл ~25-35 мин назад, дальше всё каскадом реалистично.
  void _generateRealisticTimes() {
    final now = DateTime.now();
    final r = Random();

    _medDt = now.subtract(Duration(
      minutes: 25 + r.nextInt(11),
      seconds: r.nextInt(60),
    ));
    _techDt = _medDt.add(Duration(
      minutes: 3 + r.nextInt(5),
      seconds: r.nextInt(60),
    ));
    _shiftStartDt = _techDt.add(Duration(
      minutes: r.nextInt(3),
      seconds: r.nextInt(60),
    ));
    _departureDt = _shiftStartDt.add(Duration(
      minutes: 5 + r.nextInt(11),
      seconds: r.nextInt(60),
    ));
    _shiftEndDt = _shiftStartDt.add(Duration(
      hours: 11 + r.nextInt(3),
      minutes: r.nextInt(60),
      seconds: r.nextInt(60),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Путевой лист'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Данные для путевого листа',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Дата: ${DateFormat('dd.MM.yyyy').format(DateTime.now())}',
                      style: const TextStyle(fontSize: 15),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Водитель: ${widget.driverData['fullName'] ?? ''}',
                      style: const TextStyle(fontSize: 15),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Авто: ${widget.driverData['carModel'] ?? ''} (${widget.driverData['plateNumber'] ?? ''})',
                      style: const TextStyle(fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Заполните данные',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _odometerController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Показание одометра (км)',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.speed),
                      ),
                    ),
                    const SizedBox(height: 16),
                    _timeRow('Мед. осмотр', _medDt, (dt) => setState(() => _medDt = dt)),
                    _timeRow('Тех. контроль', _techDt, (dt) => setState(() => _techDt = dt)),
                    _timeRow('Начало смены', _shiftStartDt, (dt) => setState(() => _shiftStartDt = dt)),
                    _timeRow('Выезд с парковки', _departureDt, (dt) => setState(() => _departureDt = dt)),
                    _timeRow('Окончание смены', _shiftEndDt, (dt) => setState(() => _shiftEndDt = dt)),
                    const SizedBox(height: 8),
                    Center(
                      child: TextButton.icon(
                        onPressed: () => setState(_generateRealisticTimes),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('Пересчитать времена от текущего'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: _isGenerating ? null : _generateWaybill,
                icon: _isGenerating
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.picture_as_pdf, size: 28),
                label: Text(
                  _isGenerating ? 'Генерация...' : 'Сгенерировать путевой лист',
                  style: const TextStyle(fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6366F1),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeRow(String label, DateTime dt, Function(DateTime) onChanged) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: TextButton(
        onPressed: () async {
          final picked = await showTimePicker(
            context: context,
            initialTime: TimeOfDay(hour: dt.hour, minute: dt.minute),
          );
          if (picked != null) {
            final r = Random();
            final newDt = DateTime(
              dt.year, dt.month, dt.day,
              picked.hour, picked.minute,
              r.nextInt(60),
            );
            onChanged(newDt);
          }
        },
        child: Text(
          _formatHms(dt),
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  static String _formatHms(DateTime dt) =>
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}';

  Future<void> _generateWaybill() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError('Сессия истекла. Войдите снова.');
      return;
    }
    if (_odometerController.text.trim().isEmpty) {
      _showError('Введите показание одометра');
      return;
    }

    setState(() => _isGenerating = true);

    try {
      // Получаем настройки компании
      final settingsDoc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('company')
          .get();
      final settings = settingsDoc.data() ?? <String, dynamic>{};

      // Генерируем уникальный номер путевого листа
      final now = DateTime.now();
      final waybillNumber = '${now.millisecondsSinceEpoch ~/ 1000}';

      // Помощник: безопасно достать строку
      String s(Map<String, dynamic> m, String key) {
        final v = m[key];
        return v == null ? '' : v.toString();
      }

      final driver = widget.driverData;

      final waybillData = <String, dynamic>{
        'waybillNumber': waybillNumber,
        'date': DateFormat('dd.MM.yyyy').format(now),
        'dateFormatted':
            '«${DateFormat('dd').format(now)}» ${_getMonthName(now.month)} ${now.year} г.',
        'driverId': user.uid,
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
        // Из настроек компании
        'orgName': s(settings, 'orgName'),
        'orgAddress': s(settings, 'address'),
        'ogrn': s(settings, 'ogrn'),
        'orgInn': s(settings, 'inn'),
        'orgPhone': s(settings, 'phone'),
        'okud': s(settings, 'okud').isEmpty ? '0345001' : s(settings, 'okud'),
        'okpo': s(settings, 'okpo'),
        'permitNumber': s(settings, 'permit'),
        'mintransOrder': s(settings, 'mintrans').isEmpty
            ? '390 ОТ 28.09.2022'
            : s(settings, 'mintrans'),
        // Электронные подписи
        'medName': s(settings, 'medName'),
        'medCert': s(settings, 'medCert'),
        'medIssued': s(settings, 'medIssued'),
        'medExpires': s(settings, 'medExpires'),
        'techName': s(settings, 'techName'),
        'techCert': s(settings, 'techCert'),
        'techIssued': s(settings, 'techIssued'),
        'techExpires': s(settings, 'techExpires'),
        // Времена
        'odometerStart': _odometerController.text.trim(),
        'medTime': _formatHms(_medDt),
        'techTime': _formatHms(_techDt),
        'shiftStart': _formatHms(_shiftStartDt),
        'departureTime': _formatHms(_departureDt),
        'shiftEnd': _formatHms(_shiftEndDt),
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      };

      // Сохраняем в Firestore
      await FirebaseFirestore.instance.collection('waybills').add(waybillData);

      // Генерируем PDF
      final pdfBytes = await WaybillPdfService.generateBytes(waybillData);

      if (!mounted) return;

      // Открываем превью с кнопками
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WaybillPreviewScreen(
            pdfBytes: pdfBytes,
            waybillNumber: waybillNumber,
          ),
        ),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Путевой лист сгенерирован!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } on FirebaseException catch (e) {
      _showError('Ошибка Firebase: ${e.message ?? e.code}');
    } catch (e, st) {
      debugPrint('Ошибка генерации путевого листа: $e\n$st');
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
    const months = [
      '', 'января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
      'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'
    ];
    return months[month];
  }

  @override
  void dispose() {
    _odometerController.dispose();
    super.dispose();
  }
}
