// AsemPro API на Cloudflare Workers + D1.
// Заменяет Firebase Auth и Firestore: вход, водители, путевые листы,
// допуск (медик + мастер), сотрудники, техподдержка, бухгалтерия.
import { HttpError, fail, json, readJson, now } from './lib.js';
import {
  login, logout, getUser, requireUser, requireRole, publicUser, verifyPassword, revokeSessions,
} from './auth.js';
import {
  currentWaybill, requestWaybill, getOwnWaybill, driverSetStatus,
  pendingChecks, markCheck, publicWaybill,
} from './waybills.js';
import * as admin from './admin.js';
import * as support from './support.js';

// ── CORS: сайт админки ходит в API с другого домена ──
function corsHeaders(request, env) {
  const origin = request.headers.get('Origin');
  if (!origin) return {};
  const allowed = String(env.ALLOWED_ORIGINS || '').split(',').map(s => s.trim()).filter(Boolean);
  let ok = allowed.includes(origin);
  try {
    // Превью-деплои Pages того же проекта: <hash>.taxopark-admin.pages.dev
    if (!ok && new URL(origin).hostname.endsWith('.taxopark-admin.pages.dev')) ok = true;
  } catch (_) {}
  if (!ok) return {};
  return {
    'Access-Control-Allow-Origin': origin,
    'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type, Authorization',
    'Access-Control-Max-Age': '86400',
    'Vary': 'Origin',
  };
}

// ── Маршруты: [метод, шаблон пути, обработчик(ctx)] ──
const routes = [];
const route = (method, pattern, handler) => {
  const keys = [];
  const re = new RegExp('^' + pattern.replace(/:(\w+)/g, (_, k) => { keys.push(k); return '([^/]+)'; }) + '$');
  routes.push({ method, re, keys, handler });
};

// Публичные
route('GET', '/api/health', () => ({ ok: true, time: now() }));
route('POST', '/api/auth/login', ({ request, env }) => login(request, env));
route('POST', '/api/auth/logout', ({ request, env }) => logout(request, env));
route('GET', '/api/public/waybills/:id', ({ env, params }) => publicWaybill(env, params.id));

// Первый администратор (только если админов ещё нет и задан секрет BOOTSTRAP_SECRET).
route('POST', '/api/bootstrap', async ({ request, env }) => {
  const body = await readJson(request);
  if (!env.BOOTSTRAP_SECRET || body.secret !== env.BOOTSTRAP_SECRET) fail(403, 'forbidden', 'Неверный секрет');
  const exists = await env.DB.prepare("SELECT 1 FROM users WHERE role = 'admin'").first();
  if (exists) fail(409, 'already-bootstrapped', 'Администратор уже создан');
  return admin.createStaff(env, { ...body, role: 'admin' });
});

// Любой вошедший
route('GET', '/api/me', async ({ env, user }) => {
  requireUser(user);
  const out = { user: publicUser(user) };
  if (user.role === 'driver') out.driver = await admin.getDriver(env, user.id);
  return out;
});

// Водитель
const driver = (handler) => async (ctx) => handler({ ...ctx, user: requireRole(ctx.user, 'driver') });
route('GET', '/api/driver/waybills/current', driver(({ env, user }) => currentWaybill(env, user.id).then(w => ({ waybill: w }))));
route('POST', '/api/driver/waybills', driver(async ({ request, env, user }) => requestWaybill(env, user, await readJson(request))));
route('GET', '/api/driver/waybills/:id', driver(({ env, user, params }) => getOwnWaybill(env, user, params.id)));
route('POST', '/api/driver/waybills/:id/cancel', driver(({ env, user, params }) => driverSetStatus(env, user, params.id, 'cancel')));
route('POST', '/api/driver/waybills/:id/close', driver(({ env, user, params }) => driverSetStatus(env, user, params.id, 'close')));
route('GET', '/api/driver/stats', driver(async ({ env, user }) => {
  const r = await env.DB.prepare(
    "SELECT COUNT(*) AS n FROM waybills WHERE driver_id = ? AND status IN ('active', 'closed')"
  ).bind(user.id).first();
  return { issued: (r && r.n) || 0 };
}));
route('GET', '/api/driver/support', driver(({ env, user, url }) => support.driverMessages(env, user, url)));
route('POST', '/api/driver/support', driver(async ({ request, env, user }) => support.driverSend(env, user, await readJson(request))));
route('POST', '/api/driver/support/read', driver(({ env, user }) => support.driverRead(env, user)));
// Удаление аккаунта водителем: вход отключается сразу, данные удаляет администратор.
route('POST', '/api/driver/delete-account', async ({ request, env, user }) => {
  requireUser(user);
  if (user.role !== 'driver') fail(403, 'forbidden', 'Недостаточно прав');
  const body = await readJson(request);
  if (!(await verifyPassword(String(body.password || ''), user))) fail(401, 'invalid-credentials', 'Неверный пароль');
  await env.DB.batch([
    env.DB.prepare('INSERT INTO deletion_requests (user_id, phone, requested_at) VALUES (?, ?, ?)').bind(user.id, user.phone, now()),
    env.DB.prepare('UPDATE users SET active = 0, pass_hash = NULL, pass_salt = NULL, updated_at = ? WHERE id = ?').bind(now(), user.id),
  ]);
  await revokeSessions(env, user.id);
  return { ok: true };
});

// Допуск: медик и мастер отмечают, админ только смотрит.
route('GET', '/api/checks', ({ env, user }) => {
  requireRole(user, 'medic', 'mechanic', 'admin');
  return pendingChecks(env).then(items => ({ items }));
});
route('POST', '/api/checks/:id/mark', async ({ request, env, user, params }) => {
  requireRole(user, 'medic', 'mechanic');
  return markCheck(env, user, params.id, await readJson(request));
});

// Администратор
const adm = (handler) => async (ctx) => handler({ ...ctx, user: requireRole(ctx.user, 'admin') });
route('GET', '/api/admin/dashboard', adm(({ env }) => admin.dashboard(env)));
route('GET', '/api/admin/drivers', adm(({ env }) => admin.listDrivers(env).then(items => ({ items }))));
route('POST', '/api/admin/drivers', adm(async ({ request, env }) => admin.createDriver(env, await readJson(request))));
route('GET', '/api/admin/drivers/:id', adm(({ env, params }) => admin.getDriver(env, params.id)));
route('PUT', '/api/admin/drivers/:id', adm(async ({ request, env, params }) => admin.updateDriver(env, params.id, await readJson(request))));
route('DELETE', '/api/admin/drivers/:id', adm(({ env, params }) => admin.deleteDriver(env, params.id)));
route('POST', '/api/admin/drivers/:id/active', adm(async ({ request, env, params }) => admin.setDriverActive(env, params.id, await readJson(request))));
route('GET', '/api/admin/drivers/:id/notes', adm(({ env, params }) => admin.listNotes(env, params.id).then(items => ({ items }))));
route('POST', '/api/admin/drivers/:id/notes', adm(async ({ request, env, user, params }) => admin.addNote(env, user, params.id, await readJson(request)).then(items => ({ items }))));
route('POST', '/api/admin/users/:id/password', adm(async ({ request, env, params }) => admin.setPassword(env, params.id, await readJson(request))));
route('GET', '/api/admin/staff', adm(({ env }) => admin.listStaff(env).then(items => ({ items }))));
route('POST', '/api/admin/staff', adm(async ({ request, env }) => admin.createStaff(env, await readJson(request))));
route('PUT', '/api/admin/staff/:id', adm(async ({ request, env, user, params }) => admin.updateStaff(env, user, params.id, await readJson(request))));
route('DELETE', '/api/admin/staff/:id', adm(({ env, user, params }) => admin.deleteStaff(env, user, params.id)));
route('GET', '/api/admin/waybills', adm(({ env, url }) => admin.listWaybills(env, url).then(items => ({ items }))));
route('GET', '/api/admin/settings', adm(({ env }) => admin.getSettings(env)));
route('PUT', '/api/admin/settings', adm(async ({ request, env }) => admin.saveSettings(env, await readJson(request))));
route('GET', '/api/admin/payments', adm(({ env, url }) => admin.listPayments(env, url).then(items => ({ items }))));
route('PUT', '/api/admin/payments', adm(async ({ request, env, user }) => admin.setPayment(env, user, await readJson(request))));
route('GET', '/api/admin/support', adm(({ env }) => support.adminChats(env).then(items => ({ items }))));
route('GET', '/api/admin/support/:driverId', adm(({ env, params, url }) => support.adminMessages(env, params.driverId, url)));
route('POST', '/api/admin/support/:driverId', adm(async ({ request, env, params }) => support.adminSend(env, params.driverId, await readJson(request))));
route('GET', '/api/admin/deletion-requests', adm(({ env }) => admin.listDeletionRequests(env).then(items => ({ items }))));

// Настройки организации нужны и форме нового водителя, и приложению (только чтение).
route('GET', '/api/settings', ({ env, user }) => { requireUser(user); return admin.getSettings(env); });

async function handle(request, env) {
  const url = new URL(request.url);
  const method = request.method.toUpperCase();
  let pathMatched = false;
  for (const r of routes) {
    const m = url.pathname.match(r.re);
    if (!m) continue;
    pathMatched = true;
    if (r.method !== method) continue;
    const params = {};
    r.keys.forEach((k, i) => { params[k] = decodeURIComponent(m[i + 1]); });
    const user = await getUser(request, env);
    const result = await r.handler({ request, env, url, params, user });
    return result instanceof Response ? result : json(result);
  }
  if (pathMatched) fail(405, 'method-not-allowed', 'Метод не поддерживается');
  fail(404, 'not-found', 'Нет такого адреса API');
}

export default {
  async fetch(request, env) {
    const cors = corsHeaders(request, env);
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    let response;
    try {
      response = await handle(request, env);
    } catch (e) {
      if (e instanceof HttpError) {
        response = json({ error: e.code, message: e.message }, e.status);
      } else {
        console.error('Unhandled error:', e && e.stack || e);
        response = json({ error: 'internal', message: 'Внутренняя ошибка сервера' }, 500);
      }
    }
    const headers = new Headers(response.headers);
    for (const [k, v] of Object.entries(cors)) headers.set(k, v);
    headers.set('Cache-Control', 'no-store');
    return new Response(response.body, { status: response.status, headers });
  },
};
