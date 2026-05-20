import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

class WaybillPdfService {
  static pw.Font? _regular;
  static pw.Font? _bold;

  static Future<void> _loadFonts() async {
    if (_regular != null && _bold != null) return;
    final regularData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    _regular = pw.Font.ttf(regularData);
    _bold = pw.Font.ttf(boldData);
  }

  /// Build PDF and return raw bytes (no auto-print).
  /// Caller decides what to do — preview, save, share, print.
  static Future<Uint8List> generateBytes(Map<String, dynamic> data) async {
    await _loadFonts();

    final pdf = pw.Document();

    final theme = pw.ThemeData.withFont(
      base: _regular!,
      bold: _bold!,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(16),
        theme: theme,
        build: (context) => _buildWaybill(data),
      ),
    );

    return pdf.save();
  }

  static pw.Widget _buildWaybill(Map<String, dynamic> data) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        // ЭПЛ Header
        pw.Center(
          child: pw.Text(
            'ЭПЛ',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 8),

        // Title + Mintrans reference
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 3,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.RichText(
                    text: pw.TextSpan(
                      children: [
                        pw.TextSpan(
                          text: 'ПУТЕВОЙ ЛИСТ ',
                          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.TextSpan(
                          text: 'АП ',
                          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.TextSpan(
                          text: '№ ${data['waybillNumber']}',
                          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  pw.Text('легкового такси', style: const pw.TextStyle(fontSize: 9)),
                  pw.SizedBox(height: 2),
                  pw.Text(data['dateFormatted'] ?? '', style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ),
            pw.Expanded(
              flex: 2,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'ФОРМА ПУТЕВОГО ЛИСТА РАЗРАБОТАНА В СООТВЕТСТВИИ',
                    style: const pw.TextStyle(fontSize: 6),
                  ),
                  pw.Text(
                    'С ПРИКАЗОМ МИНТРАНСА РОССИИ №390 ОТ 28.09.2022 г.',
                    style: const pw.TextStyle(fontSize: 6),
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),

        // Organization info + codes table
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 3,
              child: pw.Container(
                padding: const pw.EdgeInsets.all(4),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.5)),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    _labelValue('Организация', data['orgName'] ?? ''),
                    pw.Text(
                      data['orgAddress'] ?? '',
                      style: const pw.TextStyle(fontSize: 7),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'ОГРН(ИП): ${data['ogrn'] ?? ''}   ИНН: ${data['orgInn'] ?? ''}   Тел.: ${data['orgPhone'] ?? ''}',
                      style: const pw.TextStyle(fontSize: 7),
                    ),
                    pw.Text(
                      'наименование, адрес, ОГРН(ИП), ИНН, номер телефона',
                      style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600),
                    ),
                  ],
                ),
              ),
            ),
            pw.SizedBox(width: 6),
            pw.Expanded(
              flex: 2,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text('Коды', style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                  pw.Table(
                    border: pw.TableBorder.all(width: 0.5),
                    children: [
                      _codeRow('Форма по ОКУД', data['okud'] ?? '0345001'),
                      _codeRow('Форма по ОКПО', data['okpo'] ?? ''),
                      _codeRow('Телефон (вод.)', data['driverPhone'] ?? ''),
                      _codeRow('СНИЛС (вод.)', data['snils'] ?? ''),
                      _codeRow('ИНН (вод.)', data['driverInn'] ?? ''),
                      _codeRow('Гаражный номер', data['garageNumber'] ?? ''),
                      _codeRow('Табельный номер', data['tabNumber'] ?? ''),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),

        // Vehicle and driver info
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          children: [
            _dataRow('Марка автомобиля', data['carModel'] ?? ''),
            _dataRow('Государственный номерной знак', data['plateNumber'] ?? ''),
            _dataRow('Водитель', data['driverName'] ?? '', sub: 'фамилия, имя, отчество'),
            _dataRow('Удостоверение №', '${data['license'] ?? ''}   Класс: ${data['licenseClass'] ?? ''}'),
            _dataRow('Дата выдачи', '${data['licenseIssued'] ?? ''}   окончание: ${data['licenseExpires'] ?? ''}'),
            _dataRow('Перевозка', data['transportType'] ?? ''),
            _dataRow('Вид сообщения', data['commType'] ?? ''),
          ],
        ),
        pw.SizedBox(height: 3),
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          children: [
            pw.TableRow(children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(3),
                child: pw.Text(
                  'ID ВОДИТЕЛЯ: ${data['driverIdNumber'] ?? ''}      ОСГОП: ${data['osgop'] ?? ''}      Разрешение №: ${data['permitNumber'] ?? ''}',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ),
            ]),
          ],
        ),
        pw.SizedBox(height: 6),

        // Medical exam section
        _sectionGreen('ПРОШЕЛ ПРЕДРЕЙСОВЫЙ МЕДИЦИНСКИЙ ОСМОТР К ИСПОЛНЕНИЮ ТРУДОВЫХ ОБЯЗАННОСТЕЙ ДОПУЩЕН'),
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          children: [
            pw.TableRow(children: [
              _cellPad(data['date'] ?? ''),
              _cellPad(data['medTime'] ?? ''),
              _cellPad('Медицинский работник: _______________'),
            ]),
          ],
        ),
        pw.SizedBox(height: 5),

        // Tech control section
        _sectionGreen('КОНТРОЛЬ ТЕХНИЧЕСКОГО СОСТОЯНИЯ ТРАНСПОРТНОГО СРЕДСТВА ПРОЙДЕН'),
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          children: [
            pw.TableRow(children: [
              _cellPad(data['date'] ?? ''),
              _cellPad(data['techTime'] ?? ''),
              _cellPad('Контролёр тех.сост. ТС: _______________'),
            ]),
          ],
        ),
        pw.SizedBox(height: 5),

        // Shift times + Release permission side by side
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 3,
              child: pw.Table(
                border: pw.TableBorder.all(width: 0.5),
                children: [
                  _dataRow('Начало смены', '${data['date'] ?? ''}   ${data['shiftStart'] ?? ''}'),
                  _dataRow('Выезд с парковки', '${data['date'] ?? ''}   ${data['departureTime'] ?? ''}'),
                  _dataRow('Показание одометра км', data['odometerStart'] ?? ''),
                ],
              ),
            ),
            pw.SizedBox(width: 6),
            pw.Expanded(
              flex: 2,
              child: pw.Container(
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 2),
                ),
                child: pw.Column(
                  children: [
                    pw.Text(
                      'ВЫПУСК НА ЛИНИЮ',
                      style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                    ),
                    pw.Text(
                      'РАЗРЕШЕН',
                      style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 5),

        // Driver memo
        pw.Container(
          padding: const pw.EdgeInsets.all(3),
          child: pw.Text(
            'ПАМЯТКА ВОДИТЕЛЮ На основании приказа Минтранса №424 от 16.10.2020г., длительность ежедневного отдыха НЕ МЕНЕЕ 11 часов. Перерыв для отдыха и питания не более 5-ти часов, но не позже 5-ти часов после начала работы. При неисправностях (поломках, неработающих фонарях, повреждении колёс/шин, отсутствии документов) установить табличку «В ПАРК», прекратить заказ, вернуться в автопарк и сообщить на линию. Это поможет избежать штрафы и обеспечит безопасность!',
            style: const pw.TextStyle(fontSize: 6),
          ),
        ),
        pw.SizedBox(height: 4),

        // Driver signature
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          children: [
            pw.TableRow(children: [
              _cellPad('ВОДИТЕЛЬ:'),
              _cellPad(data['driverName'] ?? ''),
              _cellPad('ПОДПИСЬ:'),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.SizedBox(width: 60),
              ),
            ]),
          ],
        ),
        pw.SizedBox(height: 5),

        // Work schedule
        pw.Center(
          child: pw.Text(
            'РАЗДЕЛЕНИЕ РАБОЧЕГО ДНЯ (СМЕНЫ)',
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          children: [
            pw.TableRow(children: [
              _cellBold('ПЕРЕРЫВ НАЧАТ'),
              _cellBold('ПЕРЕРЫВ ОКОНЧЕН'),
              _cellBold('ОБЕД НАЧАТ'),
              _cellBold('ОБЕД ОКОНЧЕН'),
            ]),
            pw.TableRow(children: [
              _cellPad(''), _cellPad(''), _cellPad(''), _cellPad(''),
            ]),
          ],
        ),
        pw.SizedBox(height: 5),

        // Post-trip medical
        _sectionGreen('ПРОШЕЛ ПОСЛЕРЕЙСОВЫЙ МЕДИЦИНСКИЙ ОСМОТР'),
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          children: [
            pw.TableRow(children: [
              _cellPad(''), _cellPad(''), _cellPad('Медицинский работник: _______________'),
            ]),
          ],
        ),
        pw.SizedBox(height: 4),

        // Post-trip tech
        _sectionGreen('ПРОШЕЛ ПОСЛЕРЕЙСОВЫЙ ТЕХНИЧЕСКИЙ ОСМОТР'),
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          children: [
            pw.TableRow(children: [
              _cellPad(''), _cellPad(''), _cellPad('Контролёр тех.сост. ТС: _______________'),
            ]),
          ],
        ),
        pw.SizedBox(height: 4),

        // End of shift
        pw.Table(
          border: pw.TableBorder.all(width: 0.5),
          children: [
            _dataRow('Возвращение на парковку', ''),
            _dataRow('Окончание смены', '${data['date'] ?? ''}   ${data['shiftEnd'] ?? ''}'),
            _dataRow('Показание одометра км', ''),
          ],
        ),
        pw.SizedBox(height: 8),

        // Footer
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(data['orgName'] ?? '', style: const pw.TextStyle(fontSize: 8)),
              pw.Text(data['mintransOrder'] ?? '', style: const pw.TextStyle(fontSize: 8)),
            ],
          ),
        ),
      ],
    );
  }

  // Helper widgets

  static pw.Widget _labelValue(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 1),
      child: pw.RichText(
        text: pw.TextSpan(children: [
          pw.TextSpan(
            text: '$label: ',
            style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
          ),
          pw.TextSpan(text: value, style: const pw.TextStyle(fontSize: 8)),
        ]),
      ),
    );
  }

  static pw.TableRow _codeRow(String label, String value) {
    return pw.TableRow(children: [
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: pw.Text(label, style: const pw.TextStyle(fontSize: 7)),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 3, vertical: 2),
        child: pw.Text(value, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
      ),
    ]);
  }

  static pw.TableRow _dataRow(String label, String value, {String? sub}) {
    return pw.TableRow(children: [
      pw.Padding(
        padding: const pw.EdgeInsets.all(3),
        child: pw.Text(label, style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.all(3),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(value, style: const pw.TextStyle(fontSize: 8)),
            if (sub != null)
              pw.Text(sub, style: const pw.TextStyle(fontSize: 6, color: PdfColors.grey600)),
          ],
        ),
      ),
    ]);
  }

  static pw.Widget _sectionGreen(String text) {
    return pw.Container(
      width: double.infinity,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: pw.BoxDecoration(
        color: PdfColor.fromHex('#e8f4e8'),
        border: pw.Border.all(width: 0.5),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  static pw.Widget _cellPad(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 8)),
    );
  }

  static pw.Widget _cellBold(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(4),
      child: pw.Text(text, style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
    );
  }
}
