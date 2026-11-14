// Администрирование: водители, сотрудники, путевые листы, настройки,
// бухгалтерия, CRM-заметки, статистика.
import { fail, now, str, newId, normalizePhone, isValidPhone, parseJson, mskDayStart } from './lib.js';
import { hashPassword, validatePassword, revokeSessions, publicUser } from './auth.js';
import { waybillOut, LIST_COLUMNS } from './waybills.js';

// Поля профиля водителя (как в документе Firestore drivers/{uid}).
export const DRIVER_FIELDS = [
  'carModel', 'plateNumber', 'garageNumber', 'tabNumber', 'license', 'licenseClass',
  'licenseIssued', 'licenseExpires', 'driverIdNumber', 'osgop', 'snils', 'inn',
  'transportType', 'commType', 'orgName', 'orgOgrn', 'orgInn', 'orgPhone', 'orgAddress',
  'okud', 'okpo', 'permit', 'mintrans', 'medCert', 'techCert', 'crmStatus', 'monthlyPrice',
];
const CRM_STATUSES = ['active', 'lead', 'paused', 'debtor'];
const STAFF_ROLES = ['admin', 'medic', 'mechanic'];

function pickProfile(body, base = {}) {
  const out = { ...base };
  for (const k of DRIVER_FIELDS) {
    if (!(k in body)) continue;
    if (k === 'monthlyPrice') {
      const n = parseFloat(body[k]);
      out[k] = Number.isFinite(n) && n >= 0 ? n : 0;
    } else if (k === 'crmStatus') {
      out[k] = CRM_STATUSES.includes(body[k]) ? body[k] : 'active';
    } else {
      out[k] = str(body[k], 300);
    }
  }
  if (!out.okud) out.okud = '0345001';
  if (!out.mintrans) out.mintrans = '390 ОТ 28.09.2022';
  return out;
}

function driverOut(row) {
  const data = parseJson(row.data);
  return {
    ...data,
    id: row.id,
    authUid: row.id,
    phone: row.phone,
    fullName: row.full_name,
    active: !!row.active,
    createdAt: row.created_at,
  };
}

async function phoneTaken(env, phone, scope) {
  return !!(await env.DB.prepare('SELECT 1 FROM users WHERE phone = ? AND scope = ?').bind(phone, scope).first());
}

// ── Водители ───────────────────────────────────────────────

export async function listDrivers(env) {
  const { results } = await env.DB.prepare(
    `SELECT u.id, u.phone, u.full_name, u.active, u.created_at, d.data
       FROM users u JOIN drivers d ON d.user_id = u.id
      WHERE u.role = 'driver' ORDER BY u.full_name COLLATE NOCASE`
  ).all();
  return results.map(driverOut);
}

export async function getDriver(env, id) {
  const row = await env.DB.prepare(
    `SELECT u.id, u.phone, u.full_name, u.active, u.created_at, d.data
       FROM users u JOIN drivers d ON d.user_id = u.id WHERE u.id = ? AND u.role = 'driver'`
  ).bind(id).first();
  if (!row) fail(404, 'not-found', 'Водитель не найден');
  return driverOut(row);
}

// POST /api/admin/drivers { fullName, phone, password?, ...профиль }
export async function createDriver(env, body) {
  const fullName = str(body.fullName, 200);
  if (!fullName) fail(400, 'no-name', 'Укажите ФИО водителя');
  const phone = normalizePhone(body.phone);
  if (!isValidPhone(phone)) fail(400, 'bad-phone', 'Некорректный номер телефона');
  if (await phoneTaken(env, phone, 'driver')) fail(409, 'phone-taken', 'Водитель с таким номером уже зарегистрирован');
  // Пароль по умолчанию — последние 6 цифр номера (как раньше).
  const password = validatePassword(str(body.password, 128) || phone.replace(/\D/g, '').slice(-6));

  const id = newId(28);
  const t = now();
  const h = await hashPassword(password);
  const profile = pickProfile(body);
  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO users (id, scope, role, phone, full_name, pass_hash, pass_salt, pass_iter, active, created_at)
       VALUES (?, 'driver', 'driver', ?, ?, ?, ?, ?, 1, ?)`
    ).bind(id, phone, fullName, h.pass_hash, h.pass_salt, h.pass_iter, t),
    env.DB.prepare('INSERT INTO drivers (user_id, data, created_at) VALUES (?, ?, ?)')
      .bind(id, JSON.stringify(profile), t),
  ]);
  return { driver: await getDriver(env, id), password };
}

// PUT /api/admin/drivers/:id — профиль и ФИО (телефон = логин, не меняем).
export async function updateDriver(env, id, body) {
  const current = await env.DB.prepare('SELECT data FROM drivers WHERE user_id = ?').bind(id).first();
  if (!current) fail(404, 'not-found', 'Водитель не найден');
  const profile = pickProfile(body, parseJson(current.data));
  const t = now();
  const stmts = [
    env.DB.prepare('UPDATE drivers SET data = ?, updated_at = ? WHERE user_id = ?').bind(JSON.stringify(profile), t, id),
  ];
  const fullName = str(body.fullName, 200);
  if (fullName) {
    stmts.push(env.DB.prepare('UPDATE users SET full_name = ?, updated_at = ? WHERE id = ?').bind(fullName, t, id));
  }
  await env.DB.batch(stmts);
  return getDriver(env, id);
}

// POST /api/admin/drivers/:id/active { active }
export async function setDriverActive(env, id, body) {
  const active = body.active ? 1 : 0;
  const res = await env.DB.prepare("UPDATE users SET active = ?, updated_at = ? WHERE id = ? AND role = 'driver'")
    .bind(active, now(), id).run();
  if (!res.meta.changes) fail(404, 'not-found', 'Водитель не найден');
  // Отключённого водителя сразу разлогиниваем.
  if (!active) await revokeSessions(env, id);
  return getDriver(env, id);
}

// POST /api/admin/users/:id/password { password } — водитель или сотрудник.
export async function setPassword(env, id, body) {
  const user = await env.DB.prepare('SELECT id, phone FROM users WHERE id = ?').bind(id).first();
  if (!user) fail(404, 'not-found', 'Пользователь не найден');
  const password = validatePassword(str(body.password, 128) || user.phone.replace(/\D/g, '').slice(-6));
  const h = await hashPassword(password);
  await env.DB.prepare('UPDATE users SET pass_hash = ?, pass_salt = ?, pass_iter = ?, updated_at = ? WHERE id = ?')
    .bind(h.pass_hash, h.pass_salt, h.pass_iter, now(), id).run();
  await revokeSessions(env, id);
  return { ok: true, password };
}

// DELETE /api/admin/drivers/:id — удаляет вход и профиль. Путевые листы остаются в архиве.
export async function deleteDriver(env, id) {
  const res = await env.DB.prepare("DELETE FROM users WHERE id = ? AND role = 'driver'").bind(id).run();
  if (!res.meta.changes) fail(404, 'not-found', 'Водитель не найден');
  await env.DB.batch([
    env.DB.prepare('DELETE FROM driver_notes WHERE driver_id = ?').bind(id),
    env.DB.prepare('DELETE FROM support_messages WHERE driver_id = ?').bind(id),
    env.DB.prepare('DELETE FROM support_chats WHERE driver_id = ?').bind(id),
    env.DB.prepare("UPDATE deletion_requests SET status = 'done' WHERE user_id = ?").bind(id),
  ]);
  return { ok: true };
}

// ── CRM-заметки ────────────────────────────────────────────

export async function listNotes(env, driverId) {
  const { results } = await env.DB.prepare(
    'SELECT id, text, created_at AS createdAt, created_by AS createdBy FROM driver_notes WHERE driver_id = ? ORDER BY id DESC LIMIT 200'
  ).bind(driverId).all();
  return results;
}

export async function addNote(env, admin, driverId, body) {
  const text = str(body.text, 2000);
  if (!text) fail(400, 'empty', 'Пустая заметка');
  await env.DB.prepare('INSERT INTO driver_notes (driver_id, text, created_at, created_by) VALUES (?, ?, ?, ?)')
    .bind(driverId, text, now(), admin.id).run();
  return listNotes(env, driverId);
}

// ── Сотрудники (админ, медик, мастер) ─────────────────────

export async function listStaff(env) {
  const { results } = await env.DB.prepare(
    "SELECT * FROM users WHERE scope = 'staff' ORDER BY full_name COLLATE NOCASE"
  ).all();
  return results.map(publicUser);
}

function certFields(body) {
  return {
    cert_serial: str(body.certSerial, 64).replace(/[^0-9a-fA-F]/g, '').toLowerCase(),
    cert_issued: /^\d{2}\.\d{2}\.\d{4}$/.test(str(body.certIssued)) ? str(body.certIssued) : '',
    cert_expires: /^\d{2}\.\d{2}\.\d{4}$/.test(str(body.certExpires)) ? str(body.certExpires) : '',
  };
}

// POST /api/admin/staff { fullName, phone, password, role, certSerial, certIssued, certExpires }
export async function createStaff(env, body) {
  const fullName = str(body.fullName, 200);
  if (!fullName) fail(400, 'no-name', 'Укажите ФИО сотрудника');
  const role = STAFF_ROLES.includes(body.role) ? body.role : fail(400, 'bad-role', 'Выберите роль');
  const phone = normalizePhone(body.phone);
  if (!isValidPhone(phone)) fail(400, 'bad-phone', 'Некорректный номер телефона');
  if (await phoneTaken(env, phone, 'staff')) fail(409, 'phone-taken', 'Сотрудник с таким телефоном уже есть');
  const password = validatePassword(body.password);
  const h = await hashPassword(password);
  const c = certFields(body);
  const id = newId(28);
  await env.DB.prepare(
    `INSERT INTO users (id, scope, role, phone, full_name, pass_hash, pass_salt, pass_iter, active,
                        cert_serial, cert_issued, cert_expires, created_at)
     VALUES (?, 'staff', ?, ?, ?, ?, ?, ?, 1, ?, ?, ?, ?)`
  ).bind(id, role, phone, fullName, h.pass_hash, h.pass_salt, h.pass_iter,
    c.cert_serial, c.cert_issued, c.cert_expires, now()).run();
  return publicUser(await env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(id).first());
}

// PUT /api/admin/staff/:id { fullName, role, certSerial, certIssued, certExpires }
export async function updateStaff(env, admin, id, body) {
  const u = await env.DB.prepare("SELECT * FROM users WHERE id = ? AND scope = 'staff'").bind(id).first();
  if (!u) fail(404, 'not-found', 'Сотрудник не найден');
  const role = STAFF_ROLES.includes(body.role) ? body.role : u.role;
  if (id === admin.id && role !== 'admin') fail(400, 'self-demote', 'Нельзя снять с себя роль администратора');
  // Поля, которых нет в запросе, не трогаем.
  const c = certFields(body);
  const pick = (key, col) => (key in body ? c[col] : u[col]);
  await env.DB.prepare(
    `UPDATE users SET full_name = ?, role = ?, cert_serial = ?, cert_issued = ?, cert_expires = ?, updated_at = ?
     WHERE id = ?`
  ).bind(str(body.fullName, 200) || u.full_name, role,
    pick('certSerial', 'cert_serial'), pick('certIssued', 'cert_issued'), pick('certExpires', 'cert_expires'),
    now(), id).run();
  return publicUser(await env.DB.prepare('SELECT * FROM users WHERE id = ?').bind(id).first());
}

export async function deleteStaff(env, admin, id) {
  if (id === admin.id) fail(400, 'self-delete', 'Нельзя удалить самого себя');
  const res = await env.DB.prepare("DELETE FROM users WHERE id = ? AND scope = 'staff'").bind(id).run();
  if (!res.meta.changes) fail(404, 'not-found', 'Сотрудник не найден');
  return { ok: true };
}

// ── Путевые листы (список для админа) ─────────────────────

export async function listWaybills(env, url) {
  const limit = Math.min(Math.max(parseInt(url.searchParams.get('limit') || '50', 10) || 50, 1), 200);
  const { results } = await env.DB.prepare(
    `SELECT ${LIST_COLUMNS} FROM waybills ORDER BY created_at DESC LIMIT ?`
  ).bind(limit).all();
  return results.map(r => waybillOut(r, { withSignature: false }));
}

// ── Статистика для «Меню» ──────────────────────────────────

export async function dashboard(env) {
  const t = now();
  const [drivers, active, waybills, today] = await env.DB.batch([
    env.DB.prepare("SELECT COUNT(*) AS n FROM users WHERE role = 'driver'"),
    env.DB.prepare("SELECT COUNT(*) AS n FROM users WHERE role = 'driver' AND active = 1"),
    env.DB.prepare("SELECT COUNT(*) AS n FROM waybills WHERE status IN ('active', 'closed')"),
    env.DB.prepare("SELECT COUNT(*) AS n FROM waybills WHERE status IN ('active', 'closed') AND created_at >= ?")
      .bind(mskDayStart(t)),
  ]);
  const n = r => (r.results[0] && r.results[0].n) || 0;
  return { drivers: n(drivers), activeDrivers: n(active), waybills: n(waybills), today: n(today) };
}

// ── Настройки ─────────────────────────────────────────────

const COMPANY_FIELDS = ['orgName', 'ogrn', 'inn', 'phone', 'address'];

export async function getSettings(env) {
  const row = await env.DB.prepare("SELECT value FROM settings WHERE key = 'company'").first();
  return row ? parseJson(row.value) : {};
}

export async function saveSettings(env, body) {
  const value = {};
  for (const k of COMPANY_FIELDS) value[k] = str(body[k], 300);
  await env.DB.prepare(
    "INSERT INTO settings (key, value) VALUES ('company', ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value"
  ).bind(JSON.stringify(value)).run();
  return value;
}

// ── Бухгалтерия ───────────────────────────────────────────

function period(value) {
  const p = str(value, 7);
  if (!/^\d{4}-\d{2}$/.test(p)) fail(400, 'bad-period', 'Период в формате ГГГГ-ММ');
  return p;
}

export async function listPayments(env, url) {
  const p = period(url.searchParams.get('period'));
  const { results } = await env.DB.prepare(
    'SELECT driver_id AS driverId, period, amount, paid, paid_at AS paidAt FROM payments WHERE period = ?'
  ).bind(p).all();
  return results.map(r => ({ ...r, paid: !!r.paid }));
}

// PUT /api/admin/payments { driverId, period, paid }
export async function setPayment(env, admin, body) {
  const p = period(body.period);
  const driver = await getDriver(env, str(body.driverId, 64));
  const amount = typeof driver.monthlyPrice === 'number' ? driver.monthlyPrice : parseFloat(driver.monthlyPrice) || 0;
  const paid = body.paid ? 1 : 0;
  const t = now();
  await env.DB.prepare(
    `INSERT INTO payments (driver_id, period, amount, paid, paid_at, marked_by, updated_at)
     VALUES (?, ?, ?, ?, ?, ?, ?)
     ON CONFLICT(driver_id, period) DO UPDATE SET
       amount = excluded.amount, paid = excluded.paid, paid_at = excluded.paid_at,
       marked_by = excluded.marked_by, updated_at = excluded.updated_at`
  ).bind(driver.id, p, amount, paid, paid ? t : null, admin.id, t).run();
  return { ok: true };
}

// ── Заявки на удаление аккаунта ───────────────────────────

export async function listDeletionRequests(env) {
  const { results } = await env.DB.prepare(
    'SELECT id, user_id AS userId, phone, requested_at AS requestedAt, status FROM deletion_requests ORDER BY id DESC LIMIT 200'
  ).all();
  return results;
}
