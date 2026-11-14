import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

enum AuthStatus { loading, signedOut, signedIn, blocked, missing }

/// Вход водителя и его профиль. Заменяет FirebaseAuth + подписку на drivers/{uid}.
///
/// Токен хранится на телефоне; профиль кэшируется, чтобы приложение
/// открывалось и без интернета. Раз в минуту профиль перечитывается —
/// так доходят правки администратора и отключение аккаунта.
class Session extends ChangeNotifier {
  Session._() {
    Api.onSessionLost = _onSessionLost;
  }
  static final Session instance = Session._();

  static const _kToken = 'asempro_token';
  static const _kMe = 'asempro_me';

  AuthStatus status = AuthStatus.loading;
  Map<String, dynamic>? user;
  Map<String, dynamic>? driver;

  late final Poller _poller = Poller(_refreshMe, const Duration(seconds: 60));

  String get userId => (user?['id'] ?? '').toString();
  String get phone => (user?['phone'] ?? '').toString();

  /// При запуске: восстановить вход из сохранённого токена.
  Future<void> restore() async {
    final p = await SharedPreferences.getInstance();
    final token = p.getString(_kToken);
    if (token == null || token.isEmpty) {
      _set(AuthStatus.signedOut);
      return;
    }
    Api.token = token;
    try {
      await _loadMe();
    } on ApiException catch (e) {
      // unauthorized/blocked уже обработаны в _onSessionLost.
      if (e.code == 'unauthorized' || e.code == 'blocked') return;
      if (e.code == 'not-found') {
        _set(AuthStatus.missing);
        return;
      }
      // Нет связи или сбой сервера — открываем по сохранённому профилю, обновим позже.
      if (!_applyCached(p.getString(_kMe))) {
        _set(AuthStatus.signedOut);
        return;
      }
    }
    _poller.start();
  }

  Future<void> signIn(String phone, String password) async {
    final r = await Api.post('/api/auth/login', {
      'phone': phone,
      'password': password,
      'scope': 'driver',
    });
    final token = (r['token'] ?? '').toString();
    if (token.isEmpty) throw const ApiException('bad-response', 'Сервер не вернул токен', 500);
    Api.token = token;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kToken, token);
    try {
      await _loadMe();
    } on ApiException catch (e) {
      if (e.code == 'not-found') {
        _set(AuthStatus.missing);
        return;
      }
      rethrow;
    }
    _poller.start();
  }

  Future<void> signOut() async {
    final hadToken = Api.token != null;
    if (hadToken) {
      // Закрываем сессию на сервере; без связи — просто забываем токен.
      try {
        await Api.post('/api/auth/logout');
      } catch (_) {}
    }
    await _clear();
    _set(AuthStatus.signedOut);
  }

  /// Сервер уже отключил вход (удаление аккаунта) — просто забываем токен.
  Future<void> forget() async {
    await _clear();
    _set(AuthStatus.signedOut);
  }

  Future<void> _refreshMe() async {
    if (Api.token == null) return;
    try {
      await _loadMe();
    } on ApiException catch (e) {
      if (e.code == 'not-found') _set(AuthStatus.missing);
    }
  }

  Future<void> _loadMe() async {
    final r = await Api.get('/api/me');
    final u = r['user'];
    final d = r['driver'];
    if (u is! Map<String, dynamic> || u['role'] != 'driver' || d is! Map<String, dynamic>) {
      throw const ApiException('not-found', 'Профиль водителя не найден', 404);
    }
    final changed = jsonEncode(r) != jsonEncode({'user': user, 'driver': driver});
    user = u;
    driver = d;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kMe, jsonEncode(r));
    final next = d['active'] == false ? AuthStatus.blocked : AuthStatus.signedIn;
    if (changed || status != next) _set(next);
  }

  bool _applyCached(String? raw) {
    if (raw == null) return false;
    try {
      final r = jsonDecode(raw) as Map<String, dynamic>;
      user = r['user'] as Map<String, dynamic>;
      driver = r['driver'] as Map<String, dynamic>;
      _set(AuthStatus.signedIn);
      return true;
    } catch (_) {
      return false;
    }
  }

  void _onSessionLost(ApiException e) {
    // Не ждём: экран входа/блокировки должен появиться сразу.
    _poller.stop();
    Api.token = null;
    SharedPreferences.getInstance().then((p) {
      p.remove(_kToken);
      p.remove(_kMe);
    });
    _set(e.code == 'blocked' ? AuthStatus.blocked : AuthStatus.signedOut);
  }

  Future<void> _clear() async {
    _poller.stop();
    Api.token = null;
    user = null;
    driver = null;
    final p = await SharedPreferences.getInstance();
    await p.remove(_kToken);
    await p.remove(_kMe);
  }

  void _set(AuthStatus s) {
    status = s;
    notifyListeners();
  }
}
