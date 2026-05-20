import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

class WaybillPdfService {
  static Future<void> generateAndPrint(Map<String, dynamic> data) async {
    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(20),
        build: (context) => _buildWaybill(data),
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Путевой лист АП №${data['waybillNumber']}',
    );
  }

  static pw.Widget _buildWaybill(Map<String, dynamic> data) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // Header
        pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'ПУТЕВОЙ ЛИСТ АП № ${data['waybillNumber']}',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                ),
                pw.Text('легкового такси', style: const pw.TextStyle(fontSize: 10)),
                pw.SizedBox(height: 4),
                pw.Text(data['dateFormatted'] ?? '', style: const pw.TextStyle(fontSize: 10)),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  'ФОРМА ПУТЕВОГО ЛИСТА РАЗРАБОТАНА',
                  style: const pw.TextStyle(fontSize: 7),
                ),
                pw.Text(
                  'В СООТВЕТСТВИИ С ПРИКАЗОМ МИНТРАНСА',
                  style: const pw.TextStyle(fontSize: 7),
                ),
                pw.Text(
                  'РОССИИ №390 ОТ 28.09.2022 г.',
                  style: const pw.TextStyle(fontSize: 7),
                ),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 10),

        // Organization info with codes table
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 3,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _labelValue('Организация', '${data['orgName']}'),
                  pw.Text(data['orgAddress'] ?? '', style: const pw.TextStyle(fontSize: 8)),
                  _labelValue('ОГРН(ИП)', '${data['ogrn']}  ИНН: ${data['orgInn']}  Тел.: ${data['orgPhone']}'),
                ],
              ),
            ),
            pw.Expanded(
              flex: 2,
              child: pw.Table(
                border: pw.TableBorder.all(width: 0.5),
                children: [
                  _tableRow('Форма по ОКУД', data['okud'] ?? '0345001'),
                  _tableRow('Форма по ОКПО', data['okpo'] ?? ''),
                  _tableRow('Телефон (вод.)', data['driverPhone'] ?? ''),
                  _tableRow('СНИЛС (вод.)', data['snils'] ?? ''),
                  _tableRow('ИНН (вод.)', data['driverInn'] ?? ''),
                  _tableRow('Гаражный номер', data['garageNumber'] ?? ''),
                  _tableRow('Табельный номер', data['tabNumber'] ?? ''),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),

        // Vehicle and driver info
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          children: [
            _tableRow('Марка автомобиля', data['carModel'] ?? ''),
            _tableRow('Государственный номерной знак', data['plateNumber'] ?? ''),
            _tableRow('Водитель', data['driverName'] ?? ''),
            _tableRow('Удостоверение №', '${data['license']}  Класс: ${data['licenseClass']}'),
            _tableRow('Дата выдачи', '${data['licenseIssued']}  окончание: ${data['licenseExpires']}'),
            _tableRow('ID ВОДИТЕЛЯ', '${data['driverIdNumber']}  ОСГОП: ${data['osgop']}  Разрешение №: ${data['permitNumber']}'),
            _tableRow('Перевозка', data['transportType'] ?? ''),
            _tableRow('Вид сообщения', data['commType'] ?? ''),
          ],
        ),
        pw.SizedBox(height: 8),

        // Medical exam
        _sectionHeader('ПРОШЕЛ ПРЕДРЕЙСОВЫЙ МЕДИЦИНСКИЙ ОСМОТР К ИСПОЛНЕНИЮ ТРУДОВЫХ ОБЯЗАННОСТЕЙ ДОПУЩЕН'),
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          children: [
            pw.TableRow(
              children: [
                _cell(data['date'] ?? ''),
                _cell(data['medTime'] ?? ''),
                _cell('Медицинский работник: _______________'),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 6),

        // Technical control
        _sectionHeader('КОНТРОЛЬ ТЕХНИЧЕСКОГО СОСТОЯНИЯ ТРАНСПОРТНОГО СРЕДСТВА ПРОЙДЕН'),
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          children: [
            pw.TableRow(
              children: [
                _cell(data['date'] ?? ''),
                _cell(data['techTime'] ?? ''),
                _cell('Контролёр тех.сост. ТС: _______________'),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 6),

        // Shift times
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          children: [
            _tableRow('Начало смены', '${data['date']}  ${data['shiftStart']}'),
            _tableRow('Выезд с парковки', '${data['date']}  ${data['departureTime']}'),
            _tableRow('Показание одометра км', data['odometerStart'] ?? ''),
          ],
        ),
        pw.SizedBox(height: 8),

        // Release permission
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(border: pw.Border.all(width: 1.5)),
          child: pw.Center(
            child: pw.Text(
              'ВЫПУСК НА ЛИНИЮ РАЗРЕШЕН',
              style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ),
        pw.SizedBox(height: 6),

        // Driver memo
        pw.Text(
          'ПАМЯТКА ВОДИТЕЛЮ На основании приказа Минтранса №424 от 16.10.2020г., длительность ежедневного отдыха НЕ МЕНЕЕ 11 часов. Перерыв для отдыха и питания не более 5-ти часов, но не позже 5-ти часов после начала работы.',
          style: const pw.TextStyle(fontSize: 7),
        ),
        pw.SizedBox(height: 6),

        // Driver signature
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          children: [
            pw.TableRow(
              children: [
                _cell('ВОДИТЕЛЬ:'),
                _cell(data['driverName'] ?? ''),
                _cell('ПОДПИСЬ:'),
                _cell(''),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 8),

        // Work schedule section
        pw.Center(
          child: pw.Text(
            'РАЗДЕЛЕНИЕ РАБОЧЕГО ДНЯ (СМЕНЫ)',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          children: [
            pw.TableRow(
              children: [
                _cellBold('ПЕРЕРЫВ НАЧАТ'),
                _cellBold('ПЕРЕРЫВ ОКОНЧЕН'),
                _cellBold('ОБЕД НАЧАТ'),
                _cellBold('ОБЕД ОКОНЧЕН'),
              ],
            ),
            pw.TableRow(
              children: [_cell(''), _cell(''), _cell(''), _cell('')],
            ),
          ],
        ),
        pw.SizedBox(height: 6),

        // Post-trip sections
        _sectionHeader('ПРОШЕЛ ПОСЛЕРЕЙСОВЫЙ МЕДИЦИНСКИЙ ОСМОТР'),
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          children: [
            pw.TableRow(
              children: [_cell(''), _cell(''), _cell('Медицинский работник: _______________')],
            ),
          ],
        ),
        pw.SizedBox(height: 4),
        _sectionHeader('ПРОШЕЛ ПОСЛЕРЕЙСОВЫЙ ТЕХНИЧЕСКИЙ ОСМОТР'),
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          children: [
            pw.TableRow(
              children: [_cell(''), _cell(''), _cell('Контролёр тех.сост. ТС: _______________')],
            ),
          ],
        ),
        pw.SizedBox(height: 4),

        // End of shift
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          children: [
            _tableRow('Возвращение на парковку', ''),
            _tableRow('Окончание смены', '${data['date']}  ${data['shiftEnd']}'),
            _tableRow('Показание одометра км', ''),
          ],
        ),
        pw.SizedBox(height: 10),

        // Footer
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(data['orgName'] ?? '', style: const pw.TextStyle(fontSize: 9)),
              pw.Text(data['mintransOrder'] ?? '', style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _labelValue(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.RichText(
        text: pw.TextSpan(
          children: [
            pw.TextSpan(
              text: '$label: ',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
            pw.TextSpan(text: value, style: const pw.TextStyle(fontSize: 9)),
          ],
        ),
      ),
    );
  }

  static pw.TableRow _tableRow(String label, String value) {
    return pw.TableRow(
      children: [
        pw.Padding(
          padding: const pw.EdgeInsets.all(3),
          child: pw.Text(label, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
        ),
        pw.Padding(
          padding: const pw.EdgeInsets.all(3),
          child: pw.Text(value, style: const pw.TextStyle(fontSize: 8)),
        ),
      ],
    );
  }

  static pw.Widget _sectionHeader(String text) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.all(4),
      color: PdfColor.fromHex('#e8f4e8'),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  static pw.Widget _cell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 8)),
    );
  }

  static pw.Widget _cellBold(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
    );
  }
}
