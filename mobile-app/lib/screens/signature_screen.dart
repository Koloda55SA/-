import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class SignatureScreen extends StatefulWidget {
  const SignatureScreen({super.key});

  @override
  State<SignatureScreen> createState() => _SignatureScreenState();
}

class _SignatureScreenState extends State<SignatureScreen> {
  final List<List<Offset>> _strokes = [];
  List<Offset> _currentStroke = [];
  final GlobalKey _repaintKey = GlobalKey();

  void _clear() {
    setState(() {
      _strokes.clear();
      _currentStroke = [];
    });
  }

  Future<void> _save() async {
    if (_strokes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Нарисуйте подпись'), backgroundColor: Color(0xFFFF8C00)),
      );
      return;
    }

    try {
      final boundary = _repaintKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final pngBytes = byteData!.buffer.asUint8List();
      if (mounted) Navigator.pop(context, pngBytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Подпись водителя'),
        actions: [
          IconButton(icon: const Icon(Icons.delete_outline), onPressed: _clear, tooltip: 'Очистить'),
        ],
      ),
      body: Column(
        children: [
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Нарисуйте подпись в поле ниже',
              style: TextStyle(color: Color(0xFF8A8A8A), fontSize: 14),
            ),
          ),
          const SizedBox(height: 16),

          // Drawing area
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFF2A2A2A), width: 2),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: RepaintBoundary(
                    key: _repaintKey,
                    child: GestureDetector(
                      onPanStart: (details) {
                        setState(() {
                          _currentStroke = [details.localPosition];
                          _strokes.add(_currentStroke);
                        });
                      },
                      onPanUpdate: (details) {
                        setState(() {
                          _currentStroke.add(details.localPosition);
                        });
                      },
                      onPanEnd: (details) {
                        _currentStroke = [];
                      },
                      child: CustomPaint(
                        painter: _SignaturePainter(strokes: _strokes),
                        size: Size.infinite,
                        child: Container(color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _clear,
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFF2A2A2A)),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: const Text('Очистить'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8C00),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Сохранить', style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  final List<List<Offset>> strokes;

  _SignaturePainter({required this.strokes});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF1A4E8E)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    for (final stroke in strokes) {
      if (stroke.length < 2) continue;
      final path = Path();
      path.moveTo(stroke[0].dx, stroke[0].dy);
      for (int i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}
