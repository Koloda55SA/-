import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../theme/app_theme.dart';
import '../services/waybill_pdf_service.dart';
import 'waybill_preview_screen.dart';

/// Показывает нижний лист «Путевой лист» с QR-кодом (ведёт на публичный
/// просмотр ЭПЛ на сайте) и кнопками «Скачать ЭПЛ» / «Открыть ЭПЛ».
Future<void> showWaybillQrSheet(
  BuildContext context, {
  required Map<String, dynamic> data,
  required String docId,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _WaybillQrSheet(data: data, docId: docId),
  );
}

class _WaybillQrSheet extends StatefulWidget {
  final Map<String, dynamic> data;
  final String docId;

  const _WaybillQrSheet({required this.data, required this.docId});

  @override
  State<_WaybillQrSheet> createState() => _WaybillQrSheetState();
}

class _WaybillQrSheetState extends State<_WaybillQrSheet> {
  bool _busy = false;

  String get _waybillNumber => (widget.data['waybillNumber'] ?? '').toString();

  /// Ссылка на публичный просмотр ЭПЛ на сайте (то, что кодируется в QR).
  String get _viewerUrl =>
      '${WaybillPdfService.viewerBaseUrl}/waybill.html?id=${widget.docId}';

  Future<Uint8List> _buildPdf() {
    // Прокидываем docId, чтобы QR в самом PDF тоже вёл на нужный ЭПЛ.
    final merged = <String, dynamic>{...widget.data, 'docId': widget.docId};
    return WaybillPdfService.generateBytes(merged);
  }

  Future<void> _openPdf() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _buildPdf();
      if (!mounted) return;
      Navigator.pop(context);
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => WaybillPreviewScreen(
            pdfBytes: bytes,
            waybillNumber: _waybillNumber,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  Future<void> _downloadPdf() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _buildPdf();
      await Printing.sharePdf(bytes: bytes, filename: 'waybill_$_waybillNumber.pdf');
      if (!mounted) return;
      setState(() => _busy = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: AppTheme.danger),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        decoration: const BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 44,
              height: 5,
              decoration: BoxDecoration(
                color: AppTheme.border,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Путевой лист',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 24),
            // QR на белом фоне для надёжного сканирования
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: QrImageView(
                data: _viewerUrl,
                version: QrVersions.auto,
                size: 220,
                gapless: false,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Отсканируйте QR-код для просмотра\nпутевого листа',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _downloadPdf,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Скачать ЭПЛ'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: const BorderSide(color: AppTheme.border),
                      foregroundColor: AppTheme.text,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _busy ? null : _openPdf,
                    icon: const Icon(Icons.open_in_new_rounded, size: 18),
                    label: const Text('Открыть ЭПЛ'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ],
            ),
            if (_busy) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(color: AppTheme.primary),
            ],
          ],
        ),
      ),
    );
  }
}
