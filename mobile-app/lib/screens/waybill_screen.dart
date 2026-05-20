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

  // DateTime objects with full hour:min:sec precision
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

  /// Build times based on the phone's current time so that
  /// the медосмотр looks like it was passed ~20–30 minutes ago,
  /// then everything cascades realistically.
  void _generateRealisticTimes() {
    final now = DateTime.now();
    final r = Random();

    // Медосмотр: 25–35 минут назад от сейчас
    _medDt = now.subtract(Duration(
      minutes: 25 + r.nextInt(11),
      seconds: r.nextInt(60),
    ));

    // Техконтроль: через 3–7 минут после медика
    _techDt = _medDt.add(Duration(
      minutes: 3 + r.nextInt(5),
      seconds: r.nextInt(60),
    ));

    // Начало смены: через 0–2 мин после техконтроля
    _shiftStartDt = _techDt.add(Duration(
      minutes: r.nextInt(3),
      seconds: r.nextInt(60),
    ));

    // Выезд с парковки: через 5–15 мин после начала смены
    _departureDt = _shiftStartDt.add(Duration(
      minutes: 5 + r.nextInt(11),
      seconds: r.nextInt(60),
    ));

    // Окончание смены: 11–13 часов после начала
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
                      'Водитель: ${widget.driverData['fullName']}',
                      style: const TextStyle(fontSize: 15),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Авто: ${widget.driverData['carModel']} (${widget.driverData['plateNumber']})',
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
                        onPressed: () => setState(() => _generateRealisticTimes()),
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
            // Keep seconds, only change hour/minute
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
    if (_odometerController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Введите показание одометра')),
      );
      return;
    }

    setState(() => _isGenerating = true);

    try {
      // Get company settings
      final settingsDoc = await FirebaseFirestore.instance
          .collection('settings')
          .doc('company')
          .get();
      final settings = settingsDoc.data() ?? {};

      // Generate waybill number
      final now = DateTime.now();
      final waybillNumber = '${now.millisecondsSinceEpoch ~/ 1000}';

      // Prepare waybill data
      final waybillData = <String, dynamic>{
        'waybillNumber': waybillNumber,
        'date': DateFormat('dd.MM.yyyy').format(now),
        'dateFormatted': '«${DateFormat('dd').format(now)}» ${_getMonthName(now.month)} ${now.year} г.',
        'driverId': FirebaseAuth.instance.currentUser!.uid,
        'driverName': widget.driverData['fullName'] ?? '',
        'driverPhone': widget.driverData['phone'] ?? '',
        'carModel': widget.driverData['carModel'] ?? '',
        'plateNumber': widget.driverData['plateNumber'] ?? '',
        'license': widget.driverData['license'] ?? '',
        'licenseClass': widget.driverData['licenseClass'] ?? '',
        'licenseIssued': widget.driverData['licenseIssued'] ?? '',
        'licenseExpires': widget.driverData['licenseExpires'] ?? '',
        'driverIdNumber': widget.driverData['driverIdNumber'] ?? '',
        'osgop': widget.driverData['osgop'] ?? '',
        'garageNumber': widget.driverData['garageNumber'] ?? '',
        'tabNumber': widget.driverData['tabNumber'] ?? '',
        'snils': widget.driverData['snils'] ?? '',
        'driverInn': widget.driverData['inn'] ?? '',
        'transportType': widget.driverData['transportType'] ?? '',
        'commType': widget.driverData['commType'] ?? '',
        'orgName': settings['orgName'] ?? '',
        'orgAddress': settings['address'] ?? '',
        'ogrn': settings['ogrn'] ?? '',
        'orgInn': settings['inn'] ?? '',
        'orgPhone': settings['phone'] ?? '',
        'okud': settings['okud'] ?? '0345001',
        'okpo': settings['okpo'] ?? '',
        'permitNumber': settings['permit'] ?? '',
        'mintransOrder': settings['mintrans'] ?? '',
        'odometerStart': _odometerController.text,
        'medTime': _formatHms(_medDt),
        'techTime': _formatHms(_techDt),
        'shiftStart': _formatHms(_shiftStartDt),
        'departureTime': _formatHms(_departureDt),
        'shiftEnd': _formatHms(_shiftEndDt),
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      };

      // Save to Firestore
      await FirebaseFirestore.instance.collection('waybills').add(waybillData);

      // Generate PDF bytes (without auto-print)
      final pdfBytes = await WaybillPdfService.generateBytes(waybillData);

      if (!mounted) return;

      // Open preview screen — user picks: view, save, share or print
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
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
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
