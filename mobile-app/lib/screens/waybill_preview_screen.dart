import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../theme/app_theme.dart';

class WaybillPreviewScreen extends StatefulWidget {
  final Uint8List pdfBytes;
  final String waybillNumber;

  const WaybillPreviewScreen({
    super.key,
    required this.pdfBytes,
    required this.waybillNumber,
  });

  @override
  State<WaybillPreviewScreen> createState() => _WaybillPreviewScreenState();
}

class _WaybillPreviewScreenState extends State<WaybillPreviewScreen> {
  late final Future<List<Uint8List>> _pagesFuture;

  Uint8List get pdfBytes => widget.pdfBytes;
  String get waybillNumber => widget.waybillNumber;

  String get _fileName => 'waybill_$waybillNumber.pdf';

  @override
  void initState() {
    super.initState();
    _pagesFuture = _renderPages();
  }

  /// Рендерим страницы PDF в изображения, чтобы можно было свободно
  /// масштабировать (pinch-to-zoom) через InteractiveViewer.
  Future<List<Uint8List>> _renderPages() async {
    final pages = <Uint8List>[];
    await for (final page in Printing.raster(pdfBytes, dpi: 200)) {
      pages.add(await page.toPng());
    }
    return pages;
  }

  Future<void> _saveToDownloads(BuildContext context) async {
    try {
      // On Android we save into the app's Documents directory which the
      // user can open via the system file picker. Public Downloads requires
      // SAF / extra permissions, so we use the share sheet for that.
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$_fileName');
      await file.writeAsBytes(pdfBytes);

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Сохранено: ${file.path}'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка сохранения: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _share(BuildContext context) async {
    try {
      await Printing.sharePdf(bytes: pdfBytes, filename: _fileName);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _print(BuildContext context) async {
    try {
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdfBytes,
        name: 'Путевой лист АП №$waybillNumber',
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка печати: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        title: Text('АП №$waybillNumber'),
      ),
      body: Column(
        children: [
          // PDF preview с возможностью масштабирования (pinch-to-zoom)
          Expanded(
            child: FutureBuilder<List<Uint8List>>(
              future: _pagesFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError ||
                    !snapshot.hasData ||
                    snapshot.data!.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Не удалось отобразить документ',
                        style: TextStyle(color: AppTheme.textMuted),
                      ),
                    ),
                  );
                }
                final pages = snapshot.data!;
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 6,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(8),
                    child: Column(
                      children: [
                        for (final page in pages)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black26,
                                  blurRadius: 6,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Image.memory(page, fit: BoxFit.fitWidth),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          // Action buttons
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).cardColor,
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black12,
                    blurRadius: 8,
                    offset: Offset(0, -2),
                  ),
                ],
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _actionButton(
                    icon: Icons.download_rounded,
                    label: 'Сохранить',
                    color: const Color(0xFF6366F1),
                    onTap: () => _saveToDownloads(context),
                  ),
                  _actionButton(
                    icon: Icons.share_rounded,
                    label: 'Поделиться',
                    color: const Color(0xFF10B981),
                    onTap: () => _share(context),
                  ),
                  _actionButton(
                    icon: Icons.print_rounded,
                    label: 'Печать',
                    color: const Color(0xFF8B5CF6),
                    onTap: () => _print(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        elevation: 0,
      ),
    );
  }
}
