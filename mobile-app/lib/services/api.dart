import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

/// Адрес сервера AsemPro (Cloudflare Workers + D1).
/// Для отладки можно подменить: flutter run --dart-define=API_BASE=http://10.0.2.2:8787
const String apiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'https://asem-pro-api.oon66517.workers.dev',
);

/// Ошибка от сервера (или отсутствие связи — code == 'network').
class ApiException implements Exception {
  final String code;
  final String message;
  final int status;
  const ApiException(this.code, this.message, this.status);

  bool get isNetwork => code == 'network';

  @override
  String toString() => message;
}

/// Тонкий HTTP-клиент: токен входа в заголовке, JSON туда и обратно.
class Api {
  Api._();

  static String? token;

  /// Вызывается, когда сервер сообщает, что сессия недействительна
  /// (истекла, вход с другого устройства после смены пароля, аккаунт отключён).
  static void Function(ApiException e)? onSessionLost;

  static final http.Client _client = http.Client();
  static const _timeout = Duration(seconds: 20);

  static Future<Map<String, dynamic>> get(String path) => _request('GET', path);
  static Future<Map<String, dynamic>> post(String path, [Map<String, dynamic>? body]) =>
      _request('POST', path, body ?? const {});

  static Future<Map<String, dynamic>> _request(String method, String path,
      [Map<String, dynamic>? body]) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    final t = token;
    if (t != null) headers['Authorization'] = 'Bearer $t';
    final uri = Uri.parse('$apiBase$path');

    http.Response res;
    try {
      final req = http.Request(method, uri)..headers.addAll(headers);
      if (body != null) req.body = jsonEncode(body);
      res = await http.Response.fromStream(await _client.send(req).timeout(_timeout))
          .timeout(_timeout);
    } on TimeoutException {
      throw const ApiException('network', 'Сервер не отвечает. Проверьте интернет', 0);
    } catch (_) {
      throw const ApiException('network', 'Нет соединения с интернетом', 0);
    }

    Map<String, dynamic> data = const {};
    try {
      final decoded = jsonDecode(utf8.decode(res.bodyBytes));
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {}

    if (res.statusCode < 200 || res.statusCode >= 300) {
      final e = ApiException(
        (data['error'] ?? 'http-${res.statusCode}').toString(),
        (data['message'] ?? 'Ошибка сервера (${res.statusCode})').toString(),
        res.statusCode,
      );
      // Сессия недействительна или аккаунт отключён — возвращаем на вход.
      // (Неверный пароль при подтверждении действия — другой код, сюда не попадает.)
      if (t != null && (e.code == 'unauthorized' || e.code == 'blocked')) {
        onSessionLost?.call(e);
      }
      throw e;
    }
    return data;
  }
}

/// Время с сервера (миллисекунды) → DateTime.
DateTime? apiTime(dynamic v) {
  if (v is num && v > 0) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
  return null;
}

/// Периодический опрос сервера вместо realtime-подписок Firestore.
/// Пока приложение свёрнуто, запросы не делаются; при возврате — сразу обновляет.
class Poller with WidgetsBindingObserver {
  Poller(this._task, this.interval);

  final Future<void> Function() _task;
  Duration interval;

  Timer? _timer;
  bool _enabled = false;
  bool _running = false;
  bool _foreground = true;
  int _gen = 0;

  bool get isRunning => _enabled;

  void start() {
    if (_enabled) return;
    _enabled = true;
    WidgetsBinding.instance.addObserver(this);
    _schedule(now: true);
  }

  void stop() {
    if (!_enabled) return;
    _enabled = false;
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  /// Обновить прямо сейчас (например, после действия пользователя).
  Future<void> refresh() async {
    if (_running) return;
    _running = true;
    try {
      await _task();
    } catch (e) {
      debugPrint('poll: $e');
    } finally {
      _running = false;
    }
  }

  void _schedule({bool now = false}) {
    _timer?.cancel();
    final g = ++_gen;
    _timer = Timer(now ? Duration.zero : interval, () async {
      if (!_enabled || g != _gen) return;
      if (_foreground) await refresh();
      if (_enabled && g == _gen) _schedule();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    final wasBackground = !_foreground;
    _foreground = fg;
    if (fg && wasBackground && _enabled) _schedule(now: true);
  }
}
