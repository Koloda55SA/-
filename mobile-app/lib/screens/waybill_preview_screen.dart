import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

class WaybillPreviewScreen extends StatelessWidget {
  final Uint8List pdfBytes;
  final String waybillNumber;

  const WaybillPreviewScreen({
    super.key,
    required this.pdfBytes,
    required this.waybillNumber,
  });

  String get _fileName => 'waybill_$waybillNumber.pdf';

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
      appBar: AppBar(
        title: Text('АП №$waybillNumber'),
        backgroundColor: const Color(0xFF0F172A),
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          // PDF preview
          Expanded(
            child: PdfPreview(
              build: (format) => pdfBytes,
              canChangePageFormat: false,
              canChangeOrientation: false,
              canDebug: false,
              allowPrinting: false,
              allowSharing: false,
              pdfFileName: _fileName,
              previewPageMargin: const EdgeInsets.all(8),
              loadingWidget: const Center(child: CircularProgressIndicator()),
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
