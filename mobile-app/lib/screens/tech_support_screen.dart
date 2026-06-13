import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../theme/app_theme.dart';

/// Чат водителя с техподдержкой (администратором).
/// Сообщения хранятся в supportChats/{driverId}/messages и видны админу
/// в реальном времени в веб-панели. Переписка сохраняется.
class TechSupportScreen extends StatefulWidget {
  final Map<String, dynamic> driverData;
  final String driverDocId;

  const TechSupportScreen({
    super.key,
    required this.driverData,
    required this.driverDocId,
  });

  @override
  State<TechSupportScreen> createState() => _TechSupportScreenState();
}

class _TechSupportScreenState extends State<TechSupportScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;

  DocumentReference<Map<String, dynamic>> get _chatRef =>
      FirebaseFirestore.instance.collection('supportChats').doc(widget.driverDocId);

  @override
  void initState() {
    super.initState();
    // Сбрасываем счётчик непрочитанных водителем при открытии чата.
    _chatRef.set({'unreadForDriver': 0}, SetOptions(merge: true)).catchError((_) {});
  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _sending = true);
    _controller.clear();
    try {
      final driverName = (widget.driverData['fullName'] ?? '').toString();
      await _chatRef.collection('messages').add({
        'sender': 'driver',
        'text': text,
        'senderName': driverName,
        'createdAt': FieldValue.serverTimestamp(),
      });
      // Мета диалога: последнее сообщение + счётчик непрочитанных админом.
      await _chatRef.set({
        'driverId': widget.driverDocId,
        'driverName': driverName,
        'phone': (widget.driverData['phone'] ?? '').toString(),
        'orgName': (widget.driverData['orgName'] ?? '').toString(),
        'lastMessage': text,
        'lastSender': 'driver',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'unreadForAdmin': FieldValue.increment(1),
        'unreadForDriver': 0,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
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
    if (ts is! Timestamp) return '';
    final d = ts.toDate();
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
              child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _chatRef
                    .collection('messages')
                    .orderBy('createdAt', descending: false)
                    .snapshots(),
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
                    return const Center(child: CircularProgressIndicator(color: AppTheme.primary));
                  }
                  final docs = snap.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return _emptyState();
                  }
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scroll.hasClients) {
                      _scroll.jumpTo(_scroll.position.maxScrollExtent);
                    }
                  });
                  return ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    itemCount: docs.length,
                    itemBuilder: (context, i) {
                      final m = docs[i].data();
                      final mine = m['sender'] == 'driver';
                      return _Bubble(
                        text: (m['text'] ?? '').toString(),
                        time: _time(m['createdAt']),
                        mine: mine,
                      );
                    },
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
