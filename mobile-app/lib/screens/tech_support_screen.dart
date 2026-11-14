import 'package:flutter/material.dart';

import '../services/api.dart';
import '../theme/app_theme.dart';

/// Чат водителя с техподдержкой (администратором).
/// Сообщения хранятся на сервере; администратор отвечает на сайте.
/// Пока чат открыт, новые сообщения подгружаются каждые 4 секунды.
class TechSupportScreen extends StatefulWidget {
  final Map<String, dynamic> driverData;
  final String driverDocId;
  /// Чат виден на экране (вкладка открыта) — тогда опрашиваем сервер.
  final bool active;

  const TechSupportScreen({
    super.key,
    required this.driverData,
    required this.driverDocId,
    this.active = true,
  });

  @override
  State<TechSupportScreen> createState() => _TechSupportScreenState();
}

class _TechSupportScreenState extends State<TechSupportScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;
  bool _loaded = false;
  final List<Map<String, dynamic>> _messages = [];
  int _lastId = 0;

  late final Poller _poller = Poller(_fetchNew, const Duration(seconds: 4));

  @override
  void initState() {
    super.initState();
    if (widget.active) _poller.start();
  }

  @override
  void didUpdateWidget(covariant TechSupportScreen old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      _poller.start();
    } else if (!widget.active && old.active) {
      _poller.stop();
    }
  }

  @override
  void dispose() {
    _poller.stop();
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Забираем только сообщения новее последнего полученного.
  Future<void> _fetchNew() async {
    final r = await Api.get('/api/driver/support?after=$_lastId');
    final fresh = (r['messages'] as List?)?.whereType<Map<String, dynamic>>().toList() ?? const [];
    final unread = r['unread'];
    if (!mounted) return;
    if (fresh.isNotEmpty || !_loaded) {
      setState(() {
        _loaded = true;
        for (final m in fresh) {
          final id = m['id'];
          if (id is num && id.toInt() > _lastId) {
            _messages.add(m);
            _lastId = id.toInt();
          }
        }
      });
      _scrollToEnd();
    }
    // Чат открыт — ответы администратора прочитаны.
    if (unread is num && unread > 0) {
      Api.post('/api/driver/support/read').catchError((_) => const <String, dynamic>{});
    }
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);
    _controller.clear();
    try {
      await Api.post('/api/driver/support', {'text': text});
      await _poller.refresh();
    } catch (e) {
      if (mounted) {
        _controller.text = text;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка отправки: $e'), backgroundColor: AppTheme.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _time(dynamic ts) {
    final d = apiTime(ts);
    if (d == null) return '';
    String two(int x) => x.toString().padLeft(2, '0');
    return '${two(d.day)}.${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      appBar: AppBar(
        backgroundColor: AppTheme.surface,
        title: const Text('Техподдержка'),
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: !_loaded
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
                  : _messages.isEmpty
                      ? _emptyState()
                      : ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          itemCount: _messages.length,
                          itemBuilder: (context, i) {
                            final m = _messages[i];
                            return _Bubble(
                              text: (m['text'] ?? '').toString(),
                              time: _time(m['createdAt']),
                              mine: m['sender'] == 'driver',
                            );
                          },
                        ),
            ),
            _inputBar(),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppTheme.primary.withValues(alpha: 0.12),
              ),
              child: const Icon(Icons.support_agent, color: AppTheme.primary, size: 38),
            ),
            const SizedBox(height: 18),
            const Text(
              'Чат с поддержкой',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Опишите проблему или задайте вопрос — администратор ответит в этом чате.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.textMuted, fontSize: 14, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inputBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: const BoxDecoration(
        color: AppTheme.surface,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                hintText: 'Сообщение…',
                filled: true,
                fillColor: AppTheme.surfaceHigh,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _send(),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _send,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppTheme.primaryGradient,
              ),
              child: _sending
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final String text;
  final String time;
  final bool mine;

  const _Bubble({required this.text, required this.time, required this.mine});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.76),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: mine ? AppTheme.primary : AppTheme.surfaceHigh,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              text,
              style: TextStyle(
                color: mine ? Colors.white : AppTheme.text,
                fontSize: 14,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              time,
              style: TextStyle(
                color: mine ? Colors.white70 : AppTheme.textFaint,
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
