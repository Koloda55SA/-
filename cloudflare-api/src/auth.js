// Вход по телефону и паролю, сессии, проверка ролей.
import { fail, now, str, bytesToB64, b64ToBytes, sha256Hex, normalizePhone, readJson } from './lib.js';

// 100 000 — максимум итераций PBKDF2 в Cloudflare Workers.
const PBKDF2_ITER = 100000;
const SESSION_TTL = 60 * 24 * 3600 * 1000;   // 60 дней
const MAX_FAILS = 10;                         // попыток входа …
const FAIL_WINDOW = 15 * 60 * 1000;           // … за 15 минут

async function pbkdf2(password, salt, iterations) {
  const key = await crypto.subtle.importKey(
    'raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', hash: 'SHA-256', salt, iterations }, key, 256);
  return new Uint8Array(bits);
}

export async function hashPassword(password) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const hash = await pbkdf2(password, salt, PBKDF2_ITER);
  return { pass_hash: bytesToB64(hash), pass_salt: bytesToB64(salt), pass_iter: PBKDF2_ITER };
}

function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

export async function verifyPassword(password, user) {
  if (!user || !user.pass_hash || !user.pass_salt) return false;
  const hash = await pbkdf2(password, b64ToBytes(user.pass_salt), user.pass_iter || PBKDF2_ITER);
  return timingSafeEqual(hash, b64ToBytes(user.pass_hash));
}

export function validatePassword(password) {
  const p = String(password || '');
  if (p.length < 6) fail(400, 'weak-password', 'Пароль — минимум 6 символов');
  if (p.length > 128) fail(400, 'weak-password', 'Слишком длинный пароль');
  return p;
}

export async function createSession(env, userId) {
  const raw = crypto.getRandomValues(new Uint8Array(32));
  const token = bytesToB64(raw).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  const t = now();
  await env.DB.prepare(
    'INSERT INTO sessions (token_hash, user_id, created_at, expires_at) VALUES (?, ?, ?, ?)'
  ).bind(await sha256Hex(token), userId, t, t + SESSION_TTL).run();
  return token;
}

function bearer(request) {
  const h = request.headers.get('Authorization') || '';
  const m = h.match(/^Bearer\s+(\S+)$/i);
  return m ? m[1] : null;
}

// Текущий пользователь по токену или null.
export async function getUser(request, env) {
  const token = bearer(request);
  if (!token) return null;
  const row = await env.DB.prepare(
    `SELECT u.* FROM sessions s JOIN users u ON u.id = s.user_id
     WHERE s.token_hash = ? AND s.expires_at > ?`
  ).bind(await sha256Hex(token), now()).first();
  return row || null;
}

export function requireUser(user) {
  if (!user) fail(401, 'unauthorized', 'Войдите заново');
  return user;
}

export function requireRole(user, ...roles) {
  requireUser(user);
  if (!roles.includes(user.role)) fail(403, 'forbidden', 'Недостаточно прав');
  if (!user.active) fail(403, 'blocked', 'Аккаунт отключён');
  return user;
}

export function publicUser(u) {
  return {
    id: u.id, role: u.role, phone: u.phone, fullName: u.full_name, active: !!u.active,
    certSerial: u.cert_serial, certIssued: u.cert_issued, certExpires: u.cert_expires,
  };
}

async function tooManyFails(env, key) {
  const row = await env.DB.prepare('SELECT fails, first_at FROM login_attempts WHERE key = ?').bind(key).first();
  return !!row && row.fails >= MAX_FAILS && now() - row.first_at < FAIL_WINDOW;
}

async function registerFail(env, key) {
  const t = now();
  await env.DB.prepare(
    `INSERT INTO login_attempts (key, fails, first_at) VALUES (?, 1, ?)
     ON CONFLICT(key) DO UPDATE SET
       fails = CASE WHEN ? - first_at > ? THEN 1 ELSE fails + 1 END,
       first_at = CASE WHEN ? - first_at > ? THEN ? ELSE first_at END`
  ).bind(key, t, t, FAIL_WINDOW, t, FAIL_WINDOW, t).run();
}

// POST /api/auth/login { phone, password, scope: 'driver' | 'staff' }
export async function login(request, env) {
  const body = await readJson(request);
  const scope = body.scope === 'staff' ? 'staff' : 'driver';
  const phone = normalizePhone(body.phone);
  const password = String(body.password || '');
  const ip = request.headers.get('CF-Connecting-IP') || 'local';

  const keys = [`p:${scope}:${phone}`, `ip:${ip}`];
  for (const k of keys) {
    if (await tooManyFails(env, k)) fail(429, 'too-many-attempts', 'Слишком много попыток. Попробуйте через 15 минут');
  }

  const user = await env.DB.prepare('SELECT * FROM users WHERE phone = ? AND scope = ?')
    .bind(phone, scope).first();
  const ok = user && await verifyPassword(password, user);
  if (!ok) {
    for (const k of keys) await registerFail(env, k);
    fail(401, 'invalid-credentials', 'Неверный номер или пароль');
  }
  if (!user.active) fail(403, 'blocked', 'Аккаунт отключён');

  await env.DB.prepare('DELETE FROM login_attempts WHERE key = ?').bind(keys[0]).run();
  const token = await createSession(env, user.id);
  return { token, user: publicUser(user) };
}

// POST /api/auth/logout
export async function logout(request, env) {
  const token = bearer(request);
  if (token) {
    await env.DB.prepare('DELETE FROM sessions WHERE token_hash = ?').bind(await sha256Hex(token)).run();
  }
  return { ok: true };
}

export async function revokeSessions(env, userId) {
  await env.DB.prepare('DELETE FROM sessions WHERE user_id = ?').bind(userId).run();
}

export { str };
