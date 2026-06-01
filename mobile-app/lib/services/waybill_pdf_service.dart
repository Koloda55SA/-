import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Сервис генерации PDF путевого листа в формате ЭПЛ
/// (электронный путевой лист, форма по приказу Минтранса №390 от 28.09.2022).
/// Точное соответствие шаблону — компактный, без лишних подписей.
class WaybillPdfService {
  static pw.Font? _regular;
  static pw.Font? _bold;

  // Цвета шаблона
  static const PdfColor _green = PdfColor.fromInt(0xFFD9EAD3);
  static const PdfColor _blueBorder = PdfColor.fromInt(0xFF4A90D9);
  static const PdfColor _blueLight = PdfColor.fromInt(0xFFE8F0FE);
  // Подписи полей делаем почти чёрными, чтобы хорошо читались на печати/скане.
  static const PdfColor _grey = PdfColor.fromInt(0xFF1A1A1A);
  static const PdfColor _greyLight = PdfColor.fromInt(0xFF555555);
  static const PdfColor _signBlue = PdfColor.fromInt(0xFF1A4E8E);

  static Future<void> _loadFonts() async {
    if (_regular != null && _bold != null) return;
    final regularData = await rootBundle.load('assets/fonts/Roboto-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Roboto-Bold.ttf');
    _regular = pw.Font.ttf(regularData);
    _bold = pw.Font.ttf(boldData);
  }

  static Future<Uint8List> generateBytes(Map<String, dynamic> data) async {
    await _loadFonts();
    final theme = pw.ThemeData.withFont(base: _regular!, bold: _bold!);

    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(18, 14, 18, 14),
        theme: theme,
        build: (context) => _build(data),
      ),
    );
    return pdf.save();
  }

  static String _v(Map<String, dynamic> d, String key, [String fallback = '']) {
    final v = d[key];
    if (v == null) return fallback;
    return v.toString();
  }

  static pw.Widget _build(Map<String, dynamic> d) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _headerEpl(),
        pw.SizedBox(height: 2),
        _titleRow(d),
        pw.SizedBox(height: 4),
        _orgAndCodes(d),
        pw.SizedBox(height: 2),
        _vehicleAndTransport(d),
        pw.SizedBox(height: 2),
        _idOsgopPermit(d),
        pw.SizedBox(height: 3),
        _examBlock(
          title: 'ПРОШЕЛ ПРЕДРЕЙСОВЫЙ\nМЕДИЦИНСКИЙ ОСМОТР К\nИСПОЛНЕНИЮ ТРУДОВЫХ\nОБЯЗАННОСТЕЙ ДОПУЩЕН',
          subText: _v(d, 'medCert'),
          date: _v(d, 'date'),
          time: _v(d, 'medTime'),
          signerLabel: 'Медицинский работник',
          signerName: _v(d, 'medName'),
          signerIssued: _v(d, 'medIssued'),
          signerExpires: _v(d, 'medExpires'),
        ),
        pw.SizedBox(height: 2),
        _examBlock(
          title: 'КОНТРОЛЬ ТЕХНИЧЕСКОГО\nСОСТОЯНИЯ ТРАНСПОРТНОГО\nСРЕДСТВА ПРОЙДЕН',
          subText: _v(d, 'techCert'),
          date: _v(d, 'date'),
          time: _v(d, 'techTime'),
          signerLabel: 'Контролёр тех.сост. ТС',
          signerName: _v(d, 'techName'),
          signerIssued: _v(d, 'techIssued'),
          signerExpires: _v(d, 'techExpires'),
        ),
        pw.SizedBox(height: 3),
        _shiftStartAndRelease(d),
        pw.SizedBox(height: 4),
        _memo(),
        pw.SizedBox(height: 4),
        _driverSignatureRow(d),
        pw.SizedBox(height: 4),
        _workSplitTable(),
        pw.SizedBox(height: 3),
        _postTripExam('ПРОШЕЛ ПОСЛЕРЕЙСОВЫЙ\nМЕДИЦИНСКИЙ ОСМОТР'),
        pw.SizedBox(height: 2),
        _postTripExam('ПРОШЕЛ ПОСЛЕРЕЙСОВЫЙ\nТЕХНИЧЕСКИЙ ОСМОТР'),
        pw.SizedBox(height: 3),
        _shiftEndTable(d),
        pw.SizedBox(height: 8),
        _footer(d),
      ],
    );
  }

  // ============== 1. "ЭПЛ" в шапке ==============
  static pw.Widget _headerEpl() {
    return pw.Center(
      child: pw.Text(
        'ЭПЛ',
        style: pw.TextStyle(
          fontSize: 16,
          fontWeight: pw.FontWeight.bold,
          color: _grey,
        ),
      ),
    );
  }

  // ============== 2. Заголовок ПЛ + ссылка на Минтранс ==============
  static pw.Widget _titleRow(Map<String, dynamic> d) {
    return pw.Row(
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
                      style: const pw.TextStyle(fontSize: 8.5)),
                  pw.Text('АП ',
                      style: pw.TextStyle(
                          fontSize: 11.5, fontWeight: pw.FontWeight.bold)),
                  pw.Text('№ ',
                      style: const pw.TextStyle(fontSize: 8.5)),
                  pw.Text(_v(d, 'waybillNumber'),
                      style: pw.TextStyle(
                          fontSize: 11.5, fontWeight: pw.FontWeight.bold)),
                  pw.SizedBox(width: 36),
                  pw.Text('серия',
                      style: const pw.TextStyle(fontSize: 7.5, color: _greyLight)),
                ],
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 28),
                child: pw.Text('легкового такси',
                    style: const pw.TextStyle(fontSize: 7.5, color: _grey)),
              ),
              pw.SizedBox(height: 4),
              pw.Text(_v(d, 'dateFormatted'),
                  style: const pw.TextStyle(fontSize: 9)),
            ],
          ),
        ),
        pw.Expanded(
          flex: 3,
          child: pw.Padding(
            padding: const pw.EdgeInsets.only(top: 4),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('ФОРМА ПУТЕВОГО ЛИСТА РАЗРАБОТАНА В СООТВЕТСТВИИ',
                    style: const pw.TextStyle(fontSize: 6.5)),
                pw.Text(
                    'С ПРИКАЗОМ МИНТРАНСА РОССИИ № ${_v(d, 'mintransOrder', '390 ОТ 28.09.2022')} г.',
                    style: const pw.TextStyle(fontSize: 6.5)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ============== 3. Организация + Коды ==============
  static pw.Widget _orgAndCodes(Map<String, dynamic> d) {
    return pw.Table(
      border: pw.TableBorder.all(width: 0.6),
      columnWidths: const {
        0: pw.FlexColumnWidth(4),
        1: pw.FlexColumnWidth(3),
      },
      children: [
        pw.TableRow(children: [
          // Левая часть — организация
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Верх: ОГРН/ИНН/Тел
                pw.Text(
                  'ОГРН(ИП): ${_v(d, 'ogrn')}   ИНН: ${_v(d, 'orgInn')}   Тел.: ${_v(d, 'orgPhone')}',
                  style: const pw.TextStyle(fontSize: 7),
                ),
                pw.SizedBox(height: 3),
                pw.Text('Организация',
                    style: const pw.TextStyle(fontSize: 7, color: _grey)),
                pw.Text(_v(d, 'orgName'),
                    style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 1),
                pw.Text(_v(d, 'orgAddress'),
                    style: const pw.TextStyle(fontSize: 7)),
              ],
            ),
          ),
          // Правая часть — Коды
          pw.Column(
            children: [
              pw.Container(
                width: double.infinity,
                padding: const pw.EdgeInsets.symmetric(vertical: 2),
                decoration: const pw.BoxDecoration(
                  border: pw.Border(bottom: pw.BorderSide(width: 0.6)),
                ),
                child: pw.Center(
                  child: pw.Text('Коды',
                      style: pw.TextStyle(
                          fontSize: 8, fontWeight: pw.FontWeight.bold)),
                ),
              ),
              _codeRow('Форма по ОКУД',
                  _v(d, 'okud').isEmpty ? '0345001' : _v(d, 'okud')),
              _codeRow('Форма по ОКПО', _v(d, 'okpo')),
              _codeRow('Телефон (вод.)', _v(d, 'driverPhone')),
              _codeRow('СНИЛС (вод.)', _v(d, 'snils')),
              _codeRow('ИНН (вод.)', _v(d, 'driverInn')),
              _codeRow('Гаражный номер', _v(d, 'garageNumber')),
              _codeRow('Табельный номер', _v(d, 'tabNumber')),
            ],
          ),
        ]),
      ],
    );
  }

  static pw.Widget _codeRow(String label, String value) {
    return pw.Container(
      decoration: const pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(width: 0.4, color: _greyLight)),
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
          pw.Container(width: 0.4, height: 14, color: _greyLight),
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

  // ============== 4. Машина + Перевозка ==============
  static pw.Widget _vehicleAndTransport(Map<String, dynamic> d) {
    return pw.Table(
      border: pw.TableBorder.all(width: 0.6),
      columnWidths: const {
        0: pw.FlexColumnWidth(4),
        1: pw.FlexColumnWidth(3),
      },
      children: [
        pw.TableRow(children: [
          // Левая: машина и водитель
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                _lblValue('Марка автомобиля', _v(d, 'carModel'), 12),
                pw.SizedBox(height: 2),
                _lblValue('Государственный номерной знак', _v(d, 'plateNumber'), 12),
                pw.SizedBox(height: 2),
                _lblValue('Водитель', _v(d, 'driverName'), 10),
                pw.SizedBox(height: 2),
                pw.RichText(
                  text: pw.TextSpan(
                    style: const pw.TextStyle(fontSize: 8),
                    children: [
                      const pw.TextSpan(
                          text: 'Удостоверение № ',
                          style: pw.TextStyle(color: _grey, fontSize: 7)),
                      pw.TextSpan(
                          text: _v(d, 'license'),
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      const pw.TextSpan(
                          text: '   Класс ', style: pw.TextStyle(color: _grey, fontSize: 7)),
                      pw.TextSpan(
                          text: _v(d, 'licenseClass'),
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ),
                pw.SizedBox(height: 2),
                pw.RichText(
                  text: pw.TextSpan(
                    style: const pw.TextStyle(fontSize: 8),
                    children: [
                      const pw.TextSpan(
                          text: 'Дата выдачи: ', style: pw.TextStyle(color: _grey, fontSize: 7)),
                      pw.TextSpan(
                          text: _fmtDate(_v(d, 'licenseIssued')),
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                      const pw.TextSpan(
                          text: '   окончание: ', style: pw.TextStyle(color: _grey, fontSize: 7)),
                      pw.TextSpan(
                          text: _fmtDate(_v(d, 'licenseExpires')),
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Правая: тип перевозки + вид сообщения
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  _v(d, 'transportType'),
                  style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 8),
                pw.Text(_v(d, 'commType'),
                    style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
        ]),
      ],
    );
  }

  static pw.Widget _lblValue(String label, String value, double valueSize) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.SizedBox(
          width: 100,
          child: pw.Text(label,
              style: const pw.TextStyle(fontSize: 7, color: _grey)),
        ),
        pw.Expanded(
          child: pw.Text(value,
              style: pw.TextStyle(fontSize: valueSize, fontWeight: pw.FontWeight.bold)),
        ),
      ],
    );
  }

  // ============== 5. ID/ОСГОП/Разрешение ==============
  static pw.Widget _idOsgopPermit(Map<String, dynamic> d) {
    return pw.Container(
      decoration: pw.BoxDecoration(border: pw.Border.all(width: 0.6)),
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.RichText(
              text: pw.TextSpan(
                style: const pw.TextStyle(fontSize: 8),
                children: [
                  const pw.TextSpan(
                      text: 'ID ВОДИТЕЛЯ: ', style: pw.TextStyle(color: _grey)),
                  pw.TextSpan(
                      text: _v(d, 'driverIdNumber'),
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
          ),
          pw.Expanded(
            child: pw.RichText(
              text: pw.TextSpan(
                style: const pw.TextStyle(fontSize: 8),
                children: [
                  const pw.TextSpan(
                      text: 'ОСГОП: ', style: pw.TextStyle(color: _grey)),
                  pw.TextSpan(
                      text: _v(d, 'osgop'),
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
          ),
          pw.Expanded(
            child: pw.RichText(
              text: pw.TextSpan(
                style: const pw.TextStyle(fontSize: 8),
                children: [
                  const pw.TextSpan(
                      text: 'Разрешение № ', style: pw.TextStyle(color: _grey)),
                  pw.TextSpan(
                      text: _v(d, 'permitNumber'),
                      style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============== 6. Медосмотр / Тех.контроль с электронной подписью ==============
  static pw.Widget _examBlock({
    required String title,
    required String subText,
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
        0: pw.FlexColumnWidth(28),
        1: pw.FlexColumnWidth(11),
        2: pw.FlexColumnWidth(11),
        3: pw.FlexColumnWidth(35),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        pw.TableRow(children: [
          // Левая: зеленый фон с описанием
          pw.Container(
            color: _green,
            padding: const pw.EdgeInsets.all(4),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(title,
                    style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
                if (subText.isNotEmpty)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 4),
                    child: pw.Text(subText,
                        style: const pw.TextStyle(fontSize: 6, color: _grey)),
                  ),
              ],
            ),
          ),
          // Дата
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Center(
              child: pw.Text(date,
                  style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
            ),
          ),
          // Время
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.Center(
              child: pw.Text(time,
                  style: pw.TextStyle(fontSize: 8.5, fontWeight: pw.FontWeight.bold)),
            ),
          ),
          // Электронная подпись
          pw.Padding(
            padding: const pw.EdgeInsets.all(3),
            child: _eSignBox(
              label: signerLabel,
              name: signerName,
              date: date,
              time: time,
              issued: signerIssued,
              expires: signerExpires,
            ),
          ),
        ]),
      ],
    );
  }

  /// Блок электронной подписи (синяя рамка)
  static pw.Widget _eSignBox({
    required String label,
    required String name,
    required String date,
    required String time,
    required String issued,
    required String expires,
  }) {
    return pw.Container(
      decoration: pw.BoxDecoration(
        color: _blueLight,
        border: pw.Border.all(width: 0.7, color: _blueBorder),
      ),
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          // Голубой кружок (имитация герба)
          pw.Container(
            width: 14,
            height: 14,
            decoration: const pw.BoxDecoration(
              shape: pw.BoxShape.circle,
              color: _blueBorder,
            ),
            child: pw.Center(
              child: pw.Text('₽',
                  style: pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.white,
                      fontWeight: pw.FontWeight.bold)),
            ),
          ),
          pw.SizedBox(width: 4),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('Документ подписан',
                    style: pw.TextStyle(
                        fontSize: 6.5,
                        fontWeight: pw.FontWeight.bold,
                        color: _blueBorder)),
                pw.Text('электронной подписью',
                    style: pw.TextStyle(
                        fontSize: 6.5,
                        fontWeight: pw.FontWeight.bold,
                        color: _blueBorder)),
                pw.SizedBox(height: 1.5),
                pw.Text('$label:',
                    style: const pw.TextStyle(fontSize: 5.5, color: _grey)),
                pw.Text(name.isEmpty ? '—' : name,
                    style: pw.TextStyle(
                        fontSize: 6.8, fontWeight: pw.FontWeight.bold)),
                if (issued.isNotEmpty || expires.isNotEmpty) ...[
                  pw.SizedBox(height: 1.5),
                  pw.Text(
                      'Зам/н: ${_fmtDate(issued)} по ${_fmtDate(expires)}',
                      style: const pw.TextStyle(fontSize: 5.2)),
                  pw.Text(
                      'Действителен: ${_fmtDate(issued)} по ${_fmtDate(expires)}',
                      style: const pw.TextStyle(fontSize: 5.2, color: _grey)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============== 7. Начало смены + "ВЫПУСК НА ЛИНИЮ РАЗРЕШЕН" ==============
  static pw.Widget _shiftStartAndRelease(Map<String, dynamic> d) {
    return pw.Table(
      columnWidths: const {
        0: pw.FlexColumnWidth(5),
        1: pw.FixedColumnWidth(4),
        2: pw.FlexColumnWidth(2),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        pw.TableRow(children: [
          // Левая часть — таблица смены
          pw.Table(
            border: pw.TableBorder.all(width: 0.6),
            columnWidths: const {
              0: pw.FlexColumnWidth(3),
              1: pw.FlexColumnWidth(2),
              2: pw.FlexColumnWidth(2),
            },
            children: [
              pw.TableRow(children: [
                _cellLabel('Начало смены'),
                _cellValue(_v(d, 'date')),
                _cellValue(_v(d, 'shiftStart'), bold: true),
              ]),
              pw.TableRow(children: [
                _cellLabel('Выезд с парковки'),
                _cellValue(_v(d, 'date')),
                _cellValue(_v(d, 'departureTime'), bold: true),
              ]),
              pw.TableRow(children: [
                _cellLabel('Показание одометра км'),
                pw.Padding(
                  padding: const pw.EdgeInsets.all(3),
                  child: pw.Text(_v(d, 'odometerStart'),
                      style: pw.TextStyle(
                          fontSize: 11, fontWeight: pw.FontWeight.bold)),
                ),
                _cellValue(''),
              ]),
            ],
          ),
          // Разделитель
          pw.SizedBox(),
          // Правая часть — "ВЫПУСК НА ЛИНИЮ РАЗРЕШЕН" (без рамки, только текст)
          pw.Container(
            padding: const pw.EdgeInsets.all(8),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.Text('ВЫПУСК НА ЛИНИЮ',
                    style: pw.TextStyle(
                        fontSize: 10.5, fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 4),
                pw.Text('РАЗРЕШЕН',
                    style: pw.TextStyle(
                        fontSize: 16, fontWeight: pw.FontWeight.bold)),
              ],
            ),
          ),
        ]),
      ],
    );
  }

  // ============== 8. Памятка водителю ==============
  static pw.Widget _memo() {
    return pw.RichText(
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
    );
  }

  // ============== 9. Подпись водителя ==============
  static pw.Widget _driverSignatureRow(Map<String, dynamic> d) {
    // Получаем подпись водителя: либо из локальных bytes, либо из base64 data URL
    Uint8List? signatureBytes;
    final localBytes = d['_signatureBytes'];
    if (localBytes is Uint8List) {
      signatureBytes = localBytes;
    } else if (localBytes is List<int>) {
      signatureBytes = Uint8List.fromList(localBytes);
    } else {
      final dataUrl = _v(d, 'signatureData');
      if (dataUrl.startsWith('data:image')) {
        final commaIdx = dataUrl.indexOf(',');
        if (commaIdx > 0) {
          try {
            signatureBytes = base64Decode(dataUrl.substring(commaIdx + 1));
          } catch (_) {}
        }
      }
    }

    pw.Widget signatureWidget;
    if (signatureBytes != null) {
      signatureWidget = pw.Container(
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: pw.Image(
          pw.MemoryImage(signatureBytes),
          height: 48,
          fit: pw.BoxFit.contain,
        ),
      );
    } else {
      // Fallback — стилизованная имитация подписи
      signatureWidget = pw.Container(
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: pw.Text(
          _signature(_v(d, 'driverName')),
          style: pw.TextStyle(
            fontSize: 26,
            fontWeight: pw.FontWeight.bold,
            color: _signBlue,
          ),
        ),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(width: 0.6),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.4),
        1: pw.FlexColumnWidth(3.6),
        2: pw.FlexColumnWidth(1.4),
        3: pw.FlexColumnWidth(3),
      },
      children: [
        pw.TableRow(children: [
          _cellLabel('ВОДИТЕЛЬ:', bold: true),
          _cellValue(_v(d, 'driverName'), bold: true),
          _cellLabel('ПОДПИСЬ:', bold: true),
          signatureWidget,
        ]),
      ],
    );
  }

  // ============== 10. РАЗДЕЛЕНИЕ РАБОЧЕГО ДНЯ ==============
  static pw.Widget _workSplitTable() {
    return pw.Column(
      children: [
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
              _cellValue(''), _cellValue(''), _cellValue(''), _cellValue(''),
            ]),
          ],
        ),
      ],
    );
  }

  // ============== 11. Послерейсовый осмотр ==============
  static pw.Widget _postTripExam(String title) {
    return pw.Table(
      border: pw.TableBorder.all(width: 0.6),
      columnWidths: const {
        0: pw.FlexColumnWidth(28),
        1: pw.FlexColumnWidth(11),
        2: pw.FlexColumnWidth(11),
        3: pw.FlexColumnWidth(35),
      },
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        pw.TableRow(children: [
          pw.Container(
            color: _green,
            padding: const pw.EdgeInsets.all(4),
            child: pw.Text(title,
                style: pw.TextStyle(fontSize: 7, fontWeight: pw.FontWeight.bold)),
          ),
          pw.Container(
            padding: const pw.EdgeInsets.all(4),
            child: pw.SizedBox(height: 26),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.SizedBox(),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(4),
            child: pw.SizedBox(),
          ),
        ]),
      ],
    );
  }

  // ============== 12. Возвращение / Окончание / Одометр ==============
  static pw.Widget _shiftEndTable(Map<String, dynamic> d) {
    return pw.Table(
      border: pw.TableBorder.all(width: 0.6),
      columnWidths: const {
        0: pw.FlexColumnWidth(3),
        1: pw.FlexColumnWidth(2),
        2: pw.FlexColumnWidth(2),
      },
      children: [
        pw.TableRow(children: [
          _cellLabel('Возвращение на парковку'),
          _cellValue(''),
          _cellValue(''),
        ]),
        pw.TableRow(children: [
          _cellLabel('Окончание смены'),
          _cellValue(_v(d, 'date')),
          _cellValue(_v(d, 'shiftEnd'), bold: true),
        ]),
        pw.TableRow(children: [
          _cellLabel('Показание одометра км'),
          _cellValue(''),
          _cellValue(''),
        ]),
      ],
    );
  }

  // ============== 13. Подвал: QR + название организации ==============
  static pw.Widget _footer(Map<String, dynamic> d) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        // QR-код через встроенный barcode
        pw.SizedBox(
          width: 70,
          height: 70,
          child: pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: _qrPayload(d),
            drawText: false,
          ),
        ),
        pw.Spacer(),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(_v(d, 'orgName'),
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            pw.Text(_v(d, 'mintransOrder', '390 ОТ 28.09.2022'),
                style: const pw.TextStyle(fontSize: 7)),
          ],
        ),
      ],
    );
  }

  // ============== Хелперы ==============

  static pw.Widget _cellLabel(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(text,
          style: pw.TextStyle(
              fontSize: 7,
              color: _grey,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
    );
  }

  static pw.Widget _cellValue(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(3),
      child: pw.Text(text,
          style: pw.TextStyle(
              fontSize: 9,
              fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
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

  /// Перевод даты yyyy-MM-dd в dd.MM.yyyy
  static String _fmtDate(String s) {
    if (s.isEmpty) return '';
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(s);
    if (m == null) return s;
    return '${m.group(3)}.${m.group(2)}.${m.group(1)}';
  }

  /// Имитация подписи водителя — инициалы + чёрточка
  static String _signature(String fullName) {
    final t = fullName.trim();
    if (t.isEmpty) return '~';
    final parts = t.split(RegExp(r'\s+'));
    final firstInitial = parts.isNotEmpty && parts[0].isNotEmpty ? parts[0][0] : '';
    final secondInitial = parts.length > 1 && parts[1].isNotEmpty ? parts[1][0] : '';
    return '$firstInitial.$secondInitial.~';
  }

  /// Базовый адрес публичной страницы просмотра ЭПЛ (Cloudflare Pages).
  static const String viewerBaseUrl = 'https://taxopark-admin.pages.dev';

  /// Данные для QR-кода. Если известен ID документа — ведём на публичную
  /// страницу просмотра конкретного ЭПЛ; иначе кодируем краткую сводку.
  static String _qrPayload(Map<String, dynamic> d) {
    final docId = _v(d, 'docId');
    if (docId.isNotEmpty) {
      return '$viewerBaseUrl/waybill.html?id=$docId';
    }
    final s = StringBuffer();
    s.write('AsemPro|');
    s.write('n:${_v(d, 'waybillNumber')}|');
    s.write('d:${_v(d, 'date')}|');
    s.write('drv:${_v(d, 'driverName')}|');
    s.write('p:${_v(d, 'plateNumber')}');
    return base64Encode(utf8.encode(s.toString()));
  }
}
