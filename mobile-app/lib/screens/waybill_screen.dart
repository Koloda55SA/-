import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import '../services/waybill_pdf_service.dart';

class WaybillScreen extends StatefulWidget {
  final Map<String, dynamic> driverData;

  const WaybillScreen({super.key, required this.driverData});

  @override
  State<WaybillScreen> createState() => _WaybillScreenState();
}

class _WaybillScreenState extends State<WaybillScreen> {
  bool _isGenerating = false;
  final _odometerController = TextEditingController();
  TimeOfDay _medTime = const TimeOfDay(hour: 6, minute: 10);
  TimeOfDay _techTime = const TimeOfDay(hour: 6, minute: 29);
  TimeOfDay _shiftStart = const TimeOfDay(hour: 6, minute: 29);
  TimeOfDay _departureTime = const TimeOfDay(hour: 6, minute: 42);
  TimeOfDay _shiftEnd = const TimeOfDay(hour: 18, minute: 10);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Путевой лист'),
        backgroundColor: const Color(0xFF1E293B),
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
                    _timePickerTile('Мед. осмотр', _medTime, (t) => setState(() => _medTime = t)),
                    _timePickerTile('Тех. контроль', _techTime, (t) => setState(() => _techTime = t)),
                    _timePickerTile('Начало смены', _shiftStart, (t) => setState(() => _shiftStart = t)),
                    _timePickerTile('Выезд с парковки', _departureTime, (t) => setState(() => _departureTime = t)),
                    _timePickerTile('Окончание смены', _shiftEnd, (t) => setState(() => _shiftEnd = t)),
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
                  backgroundColor: const Color(0xFF2563EB),
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

  Widget _timePickerTile(String label, TimeOfDay time, Function(TimeOfDay) onChanged) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: TextButton(
        onPressed: () async {
          final picked = await showTimePicker(
            context: context,
            initialTime: time,
          );
          if (picked != null) onChanged(picked);
        },
        child: Text(
          '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  String _formatTime(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

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
      final waybillData = {
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
        'medTime': _formatTime(_medTime),
        'techTime': _formatTime(_techTime),
        'shiftStart': _formatTime(_shiftStart),
        'departureTime': _formatTime(_departureTime),
        'shiftEnd': _formatTime(_shiftEnd),
        'status': 'active',
        'createdAt': FieldValue.serverTimestamp(),
      };

      // Save to Firestore
      await FirebaseFirestore.instance.collection('waybills').add(waybillData);

      // Generate and show PDF
      await WaybillPdfService.generateAndPrint(waybillData);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Путевой лист сгенерирован!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context);
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
