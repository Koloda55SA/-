import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Сервис генерации PDF путевого листа в формате ЭПЛ
/// (электронный путевой лист, форма по приказу Минтранса №390 от 28.09.2022).
class WaybillPdfService {
  static pw.Font? _regular;
  static pw.Font? _bold;

  static const PdfColor _green = PdfColor.fromInt(0xFFD9EAD3);
  static const PdfColor _blueBorder = PdfColor.fromInt(0xFF4A90D9);
  static const PdfColor _blueLight = PdfColor.fromInt(0xFFE8F0FE);
  static const PdfColor _grey = PdfColor.fromInt(0xFF666666);

  static Future<void> _loadFonts() async {
    if (_regular != null && _bold != null) return;
    final regularData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    _regular = pw.Font.ttf(regularData);
    _bold = pw.Font.ttf(boldData);
  }

  /// Сгенерировать PDF и вернуть байты.
  static Future<Uint8List> generateBytes(Map<String, dynamic> data) async {
    await _loadFonts();

    final pdf = pw.Document();
    final theme = pw.ThemeData.withFont(base: _regular!, bold: _bold!);

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(20, 16, 20, 16),
        theme: theme,
        build: (context) => _buildWaybill(data),
      ),
    );

    return pdf.save();
  }

  static String _s(Map<String, dynamic> data, String key, [String fallback = '']) {
    final v = data[key];
    if (v == null) return fallback;
    return v.toString();
  }

  static pw.Widget _buildWaybill(Map<String, dynamic> d) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        // Top: "ЭПЛ"
        pw.Center(
          child: pw.Text(
            'ЭПЛ',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold, color: _grey),
          ),
        ),
        pw.SizedBox(height: 4),

        // Header row: title (left) + mintrans reference (right)
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              flex: 4,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('путевой лист ',
                          style: pw.TextStyle(fontSize: 9)),
                      pw.Text('АП ',
                          style: pw.TextStyle(
                              fontSize: 11, fontWeight: pw.FontWeight.bold)),
                      pw.Text('№ ',
                          style: pw.TextStyle(fontSize: 9)),
                      pw.Text(_s(d, 'waybillNumber'),
                          style: pw.TextStyle(
                              fontSize: 11, fontWeight: pw.FontWeight.bold)),
                      pw.SizedBox(width: 30),
                      pw.Text('серия',
                          style: const pw.TextStyle(fontSize: 8, color: _grey)),
                    ],
                  ),
                  pw.SizedBox(height: 1),
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(left: 12),
                    child: pw.Text('легкового такси',
                        style: const pw.TextStyle(fontSize: 8, color: _grey)),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(_s(d, 'dateFormatted'),
                      style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ),
            pw.Expanded(
              flex: 3,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text('ФОРМА ПУТЕВОГО ЛИСТА РАЗРАБОТАНА В СООТВЕТСТВИИ',
                      style: const pw.TextStyle(fontSize: 6.5)),
                  pw.Text(
                      'С ПРИКАЗОМ МИНТРАНСА РОССИИ № ${_s(d, 'mintransOrder', '390 ОТ 28.09.2022')} г.',
                      style: const pw.TextStyle(fontSize: 6.5)),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),

        // Organization block + Codes table
        pw.Table(
          border: pw.TableBorder.all(width: 0.6),
          columnWidths: const {
            0: pw.FlexColumnWidth(4),
            1: pw.FlexColumnWidth(3),
          },
          children: [
            pw.TableRow(children: [
              // Left: organization
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Организация', style: const pw.TextStyle(fontSize: 7, color: _grey)),
                    pw.Text(_s(d, 'orgName'),
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.Text(_s(d, 'orgAddress'), style: const pw.TextStyle(fontSize: 7)),
                    pw.SizedBox(height: 2),
                    pw.Wrap(
                      spacing: 6,
                      children: [
                        pw.Text('ОГРН(ИП): ${_s(d, 'ogrn')}', style: const pw.TextStyle(fontSize: 7)),
                        pw.Text('ИНН: ${_s(d, 'orgInn')}', style: const pw.TextStyle(fontSize: 7)),
                        pw.Text('Тел.: ${_s(d, 'orgPhone')}', style: const pw.TextStyle(fontSize: 7)),
                      ],
                    ),
                    pw.Text('наименование, адрес, ОГРН(ИП), ИНН, номер телефона',
                        style: const pw.TextStyle(fontSize: 5.5, color: _grey)),
                  ],
                ),
              ),
              // Right: codes
              pw.Column(
                children: [
                  pw.Container(
                    width: double.infinity,
                    padding: const pw.EdgeInsets.symmetric(vertical: 2, horizontal: 4),
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(bottom: pw.BorderSide(width: 0.6)),
                    ),
                    child: pw.Center(
                      child: pw.Text('Коды',
                          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
                    ),
                  ),
                  _codeRow('Форма по ОКУД', _s(d, 'okud', '0345001')),
                  _codeRow('Форма по ОКПО', _s(d, 'okpo')),
                  _codeRow('Телефон (вод.)', _s(d, 'driverPhone')),
                  _codeRow('СНИЛС (вод.)', _s(d, 'snils')),
                  _codeRow('ИНН (вод.)', _s(d, 'driverInn')),
                  _codeRow('Гаражный номер', _s(d, 'garageNumber')),
                  _codeRow('Табельный номер', _s(d, 'tabNumber')),
                ],
              ),
            ]),
          ],
        ),
        pw.SizedBox(height: 4),

        // Vehicle & driver info table
        pw.Table(
          border: pw.TableBorder.all(width: 0.6),
          columnWidths: const {
            0: pw.FlexColumnWidth(2),
            1: pw.FlexColumnWidth(4),
            2: pw.FlexColumnWidth(2),
            3: pw.FlexColumnWidth(3),
          },
          children: [
            pw.TableRow(children: [
              _labelCell('Марка автомобиля'),
              _valueCell(_s(d, 'carModel'), bold: true),
              _labelCell('Перевозка'),
              _valueCell(_s(d, 'transportType')),
            ]),
            pw.TableRow(children: [
              _labelCell('Государственный номерной знак'),
              _valueCell(_s(d, 'plateNumber'), bold: true),
              _labelCell('Вид сообщения'),
              _valueCell(_s(d, 'commType')),
            ]),
            pw.TableRow(children: [
              _labelCell('Водитель'),
              _valueCellMulti(_s(d, 'driverName'), 'фамилия, имя, отчество'),
              _labelCell('Дата выдачи / окончание'),
              _valueCell('${_s(d, 'licenseIssued')}  /  ${_s(d, 'licenseExpires')}'),
            ]),
            pw.TableRow(children: [
              _labelCell('Удостоверение №'),
              _valueCell('${_s(d, 'license')}     Класс: ${_s(d, 'licenseClass')}'),
              _labelCell('ID ВОДИТЕЛЯ'),
              _valueCell(_s(d, 'driverIdNumber'), bold: true),
            ]),
          ],
        ),
        pw.SizedBox(height: 3),
        pw.Table(
          border: pw.TableBorder.all(width: 0.6),
          columnWidths: const {
            0: pw.FlexColumnWidth(1),
            1: pw.FlexColumnWidth(2),
            2: pw.FlexColumnWidth(1),
            3: pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(children: [
              _labelCell('ОСГОП'),
              _valueCell(_s(d, 'osgop')),
              _labelCell('Разрешение №'),
              _valueCell(_s(d, 'permitNumber'), bold: true),
            ]),
          ],
        ),
        pw.SizedBox(height: 4),

        // PRE-TRIP MEDICAL EXAM with electronic signature
        _examBlock(
          title: 'ПРОШЕЛ ПРЕДРЕЙСОВЫЙ\nМЕДИЦИНСКИЙ ОСМОТР К\nИСПОЛНЕНИЮ ТРУДОВЫХ\nОБЯЗАННОСТЕЙ ДОПУЩЕН',
          subtitle: _s(d, 'medCert'),
          date: _s(d, 'date'),
          time: _s(d, 'medTime'),
          signerLabel: 'Медицинский работник',
          signerName: _s(d, 'medName'),
          signerIssued: _s(d, 'medIssued'),
          signerExpires: _s(d, 'medExpires'),
        ),
        pw.SizedBox(height: 3),

        // PRE-TRIP TECH CONTROL with electronic signature
        _examBlock(
          title: 'КОНТРОЛЬ ТЕХНИЧЕСКОГО\nСОСТОЯНИЯ ТРАНСПОРТНОГО\nСРЕДСТВА ПРОЙДЕН',
          subtitle: _s(d, 'techCert'),
          date: _s(d, 'date'),
          time: _s(d, 'techTime'),
          signerLabel: 'Контролёр тех.сост. ТС',
          signerName: _s(d, 'techName'),
          signerIssued: _s(d, 'techIssued'),
          signerExpires: _s(d, 'techExpires'),
        ),
        pw.SizedBox(height: 4),

        // Shift start + release permission (side by side)
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Expanded(
              flex: 5,
              child: pw.Table(
                border: pw.TableBorder.all(width: 0.6),
                columnWidths: const {
                  0: pw.FlexColumnWidth(3),
                  1: pw.FlexColumnWidth(2),
                  2: pw.FlexColumnWidth(2),
                },
                children: [
                  pw.TableRow(children: [
                    _labelCell('Начало смены'),
                    _valueCell(_s(d, 'date')),
                    _valueCell(_s(d, 'shiftStart'), bold: true),
                  ]),
                  pw.TableRow(children: [
                    _labelCell('Выезд с парковки'),
                    _valueCell(_s(d, 'date')),
                    _valueCell(_s(d, 'departureTime'), bold: true),
                  ]),
                  pw.TableRow(children: [
                    _labelCell('Показание одометра км'),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(3),
                      child: pw.Text(_s(d, 'odometerStart'),
                          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                    ),
                    _valueCell(''),
                  ]),
                ],
              ),
            ),
            pw.SizedBox(width: 4),
            pw.Expanded(
              flex: 2,
              child: pw.Container(
                padding: const pw.EdgeInsets.all(6),
                decoration: pw.BoxDecoration(border: pw.Border.all(width: 1.2)),
                child: pw.Column(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: [
                    pw.Text('ВЫПУСК НА ЛИНИЮ',
                        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 4),
                    pw.Text('РАЗРЕШЕН',
                        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 4),

        // Driver memo (small text)
        pw.RichText(
          text: pw.TextSpan(
            children: [
              pw.TextSpan(
                text: 'ПАМЯТКА ВОДИТЕЛЮ ',
                style: pw.TextStyle(fontSize: 6, fontWeight: pw.FontWeight.bold),
              ),
              const pw.TextSpan(
                text:
                    'На основании приказа Минтранса №424 от 16.10.2020г., длительность ежедневного отдыха НЕ МЕНЕЕ 11 часов. Перерыв для отдыха и питания не более 5-ти часов, но не позже 5-ти часов после начала работы. При неисправностях (поломках, неработающих фонарях, повреждении колёс/шин, отсутствии документов) установить табличку «В ПАРК», прекратить заказы, вернуться в автопарк и сообщить мастеру. Это поможет избежать штрафы и обеспечит безопасность!',
                style: pw.TextStyle(fontSize: 6),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 4),

        // Driver signature row
        pw.Table(
          border: pw.TableBorder.all(width: 0.6),
          columnWidths: const {
            0: pw.FlexColumnWidth(1),
            1: pw.FlexColumnWidth(3),
            2: pw.FlexColumnWidth(1),
            3: pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(children: [
              _labelCell('ВОДИТЕЛЬ:'),
              _valueCell(_s(d, 'driverName'), bold: true),
              _labelCell('ПОДПИСЬ:'),
              pw.Container(
                padding: const pw.EdgeInsets.all(3),
                child: pw.Text(_signatureScribble(_s(d, 'driverName')),
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      fontStyle: pw.FontStyle.italic,
                      color: const PdfColor.fromInt(0xFF1A4E8E),
                    )),
              ),
            ]),
          ],
        ),
        pw.SizedBox(height: 4),

        // Work day split
        pw.Center(
          child: pw.Text('РАЗДЕЛЕНИЕ РАБОЧЕГО ДНЯ (СМЕНЫ)',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
        ),
        pw.SizedBox(height: 2),
        pw.Table(
          border: pw.TableBorder.all(width: 0.6),
          children: [
            pw.TableRow(children: [
              _hCell('ПЕРЕРЫВ НАЧАТ'),
              _hCell('ПЕРЕРЫВ ОКОНЧЕН'),
              _hCell('ОБЕД НАЧАТ'),
              _hCell('ОБЕД ОКОНЧЕН'),
            ]),
            pw.TableRow(children: [
              _emptyCell(), _emptyCell(), _emptyCell(), _emptyCell(),
            ]),
          ],
        ),
        pw.SizedBox(height: 4),

        // POST-trip medical (empty)
        _postTripBlock('ПРОШЕЛ ПОСЛЕРЕЙСОВЫЙ\nМЕДИЦИНСКИЙ ОСМОТР'),
        pw.SizedBox(height: 3),
        // POST-trip tech (empty)
        _postTripBlock('ПРОШЕЛ ПОСЛЕРЕЙСОВЫЙ\nТЕХНИЧЕСКИЙ ОСМОТР'),
        pw.SizedBox(height: 4),

        // Return to parking + shift end + odometer end
        pw.Table(
          border: pw.TableBorder.all(width: 0.6),
          columnWidths: const {
            0: pw.FlexColumnWidth(3),
            1: pw.FlexColumnWidth(2),
            2: pw.FlexColumnWidth(2),
          },
          children: [
            pw.TableRow(children: [
              _labelCell('Возвращение на парковку'),
              _emptyCell(), _emptyCell(),
            ]),
            pw.TableRow(children: [
              _labelCell('Окончание смены'),
              _valueCell(_s(d, 'date')),
              _valueCell(_s(d, 'shiftEnd'), bold: true),
            ]),
            pw.TableRow(children: [
              _labelCell('Показание одометра км'),
              _emptyCell(), _emptyCell(),
            ]),
          ],
        ),
        pw.SizedBox(height: 8),

        // Footer: QR code (left) + organization name (right)
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 70,
                    height: 70,
                    child: pw.BarcodeWidget(
                      barcode: pw.Barcode.qrCode(),
                      data: _buildQrPayload(d),
                      drawText: false,
                    ),
                  ),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(_s(d, 'orgName'),
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.Text(_s(d, 'mintransOrder', '390 ОТ 28.09.2022'),
                    style: const pw.TextStyle(fontSize: 7)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  // ============ Helper widgets ============

  static pw.Widget _codeRow(String label, String value) {
    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(width: 0.4, color: _grey)),
      ),
      child: pw.Row(
        children: [
          pw.Expanded(
            flex: 3,
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
              child: pw.Text(label, style: const pw.TextStyle(fontSize: 7)),
            ),
          ),
          pw.Container(width: 0.4, color: _grey),
          pw.Expanded(
            flex: 2,
            child: pw.Padding(
              padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
              child: pw.Text(value,
                  style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _labelCell(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(text, style: const pw.TextStyle(fontSize: 7, color: _grey)),
    );
  }

  static pw.Widget _valueCell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  static pw.Widget _valueCellMulti(String value, String sub) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(value, style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.Text(sub, style: const pw.TextStyle(fontSize: 5.5, color: _grey)),
        ],
      ),
    );
  }

  static pw.Widget _hCell(String text) {
    return pw.Container(
      color: _green,
      padding: const pw.EdgeInsets.all(3),
      child: pw.Center(
        child: pw.Text(text,
            style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
      ),
    );
  }

  static pw.Widget _emptyCell() {
    return pw.SizedBox(height: 18);
  }

  /// Block for pre-trip exam: left description (green), middle date/time, right e-signature.
  static pw.Widget _examBlock({
    required String title,
    required String subtitle,
    required String date,
    required String time,
    required String signerLabel,
    required String signerName,
    required String signerIssued,
    required String signerExpires,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(width: 0.6),
      columnWidths: const {
        0: pw.FlexColumnWidth(3),
        1: pw.FlexColumnWidth(1.2),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(3.5),
      },
      children: [
        pw.TableRow(children: [
          pw.Container(
            color: _green,
            padding: const pw.EdgeInsets.all(4),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(title,
                    style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                if (subtitle.isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 4),
                    child: pw.Text(subtitle,
                        style: const pw.TextStyle(fontSize: 6, color: _grey)),
                  ),
              ],
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Center(
              child: pw.Text(date,
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Center(
              child: pw.Text(time,
                  style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ),
          ),
          // Electronic signature
          pw.Container(
            margin: const pw.EdgeInsets.all(2),
            padding: const pw.EdgeInsets.all(3),
            decoration: pw.BoxDecoration(
              color: _blueLight,
              border: pw.Border.all(width: 0.6, color: _blueBorder),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                  children: [
                    pw.Container(
                      width: 8,
                      height: 8,
                      decoration: pw.BoxDecoration(
                        shape: pw.BoxShape.circle,
                        color: _blueBorder,
                      ),
                    ),
                    pw.SizedBox(width: 3),
                    pw.Text('Документ подписан',
                        style: pw.TextStyle(
                            fontSize: 6,
                            fontWeight: pw.FontWeight.bold,
                            color: _blueBorder)),
                  ],
                ),
                pw.Text('электронной подписью',
                    style: pw.TextStyle(
                        fontSize: 6,
                        fontWeight: pw.FontWeight.bold,
                        color: _blueBorder)),
                pw.SizedBox(height: 1),
                pw.Text('$signerLabel:',
                    style: const pw.TextStyle(fontSize: 5.5, color: _grey)),
                pw.Text(signerName,
                    style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                pw.Text(
                    'Дата подписи: $date $time',
                    style: const pw.TextStyle(fontSize: 5)),
                if (signerIssued.isNotEmpty || signerExpires.isNotEmpty)
                  pw.Text(
                      'Действителен: ${_formatShortDate(signerIssued)} - ${_formatShortDate(signerExpires)}',
                      style: const pw.TextStyle(fontSize: 5, color: _grey)),
              ],
            ),
          ),
        ]),
      ],
    );
  }

  static pw.Widget _postTripBlock(String title) {
    return pw.Table(
      border: pw.TableBorder.all(width: 0.6),
      columnWidths: const {
        0: pw.FlexColumnWidth(3),
        1: pw.FlexColumnWidth(1.2),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(3.5),
      },
      children: [
        pw.TableRow(children: [
          pw.Container(
            color: _green,
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text(title,
                style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
          ),
          _emptyCell(),
          _emptyCell(),
          _emptyCell(),
        ]),
      ],
    );
  }

  /// Convert ISO date (yyyy-MM-dd) to dd.MM.yyyy if possible
  static String _formatShortDate(String s) {
    if (s.isEmpty) return '';
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
    if (m == null) return s;
    return '${m.group(3)}.${m.group(2)}.${m.group(1)}';
  }

  /// Generate a fake signature scribble based on name initials
  static String _signatureScribble(String fullName) {
    if (fullName.trim().isEmpty) return '~';
    final parts = fullName.trim().split(RegExp(r'\s+'));
    final first = parts.isNotEmpty ? parts[0][0] : '';
    final last = parts.length > 1 ? parts.last[0] : '';
    return '$first.$last~~';
  }

  /// Build QR payload (base64 of waybill metadata)
  static String _buildQrPayload(Map<String, dynamic> d) {
    final payload = {
      'n': _s(d, 'waybillNumber'),
      'd': _s(d, 'date'),
      'org': _s(d, 'orgName'),
      'drv': _s(d, 'driverName'),
      'p': _s(d, 'plateNumber'),
      'mt': _s(d, 'medTime'),
      'tt': _s(d, 'techTime'),
    };
    final json = payload.entries.map((e) => '${e.key}:${e.value}').join('|');
    return base64Encode(utf8.encode(json));
  }
}
