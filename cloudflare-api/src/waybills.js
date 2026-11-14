// Путевые листы: запрос допуска водителем, отметки медика и мастера, выпуск.
import { fail, now, str, newId, msk, parseJson } from './lib.js';

const SHIFT_MS = 12 * 3600 * 1000;   // лист действует 12 часов
const MAX_SIGNATURE = 400 * 1024;    // подпись (data URL) — не больше 400 КБ

// Строка из БД → объект с теми же полями, что были в документе Firestore.
export function waybillOut(row, { withSignature = true } = {}) {
  const d = parseJson(row.data);
  const out = {
    ...d,
    id: row.id,
    waybillNumber: row.number,
    status: row.status,
    driverId: row.driver_id,
    authUid: row.driver_id,
    createdAt: row.created_at,
    expiresAt: row.expires_at,
    closedAt: row.closed_at,
    medStatus: row.med_status,
    medConfirmedAt: row.med_at,
    techStatus: row.tech_status,
    techConfirmedAt: row.tech_at,
  };
  if (withSignature && row.signature) out.signatureData = row.signature;
  return out;
}

// Колонки без подписи — для списков (подпись тяжёлая).
export const LIST_COLUMNS = 'id, number, driver_id, status, created_at, expires_at, closed_at, ' +
  'med_status, med_by, med_at, tech_status, tech_by, tech_at, data';

function isCurrent(row, t) {
  return row.status === 'pending' || (row.status === 'active' && (!row.expires_at || row.expires_at > t));
}

// Текущий лист водителя: ожидающий допуска или действующий.
export async function currentWaybill(env, driverId) {
  const t = now();
  const { results } = await env.DB.prepare(
    `SELECT * FROM waybills WHERE driver_id = ? AND status IN ('pending', 'active')
     ORDER BY created_at DESC LIMIT 5`
  ).bind(driverId).all();
  const row = results.find(r => isCurrent(r, t));
  return row ? waybillOut(row) : null;
}

// POST /api/driver/waybills { odometer, signatureData }
// Данные листа берутся из профиля водителя на сервере — клиент их не подменит.
export async function requestWaybill(env, user, body) {
  const odometer = parseInt(String(body.odometer || '').replace(/\D/g, ''), 10);
  if (!odometer || odometer <= 0 || odometer > 9999999) {
    fail(400, 'bad-odometer', 'Введите корректное показание одометра');
  }
  let signature = null;
  if (body.signatureData) {
    signature = String(body.signatureData);
    if (!signature.startsWith('data:image/png;base64,') || signature.length > MAX_SIGNATURE) {
      fail(400, 'bad-signature', 'Некорректная подпись');
    }
  }

  const existing = await currentWaybill(env, user.id);
  if (existing) fail(409, 'already-exists', existing.status === 'pending'
    ? 'Запрос на допуск уже отправлен'
    : 'Есть действующий путевой лист');

  const profileRow = await env.DB.prepare('SELECT data FROM drivers WHERE user_id = ?').bind(user.id).first();
  if (!profileRow) fail(404, 'no-profile', 'Профиль водителя не найден');
  const p = parseJson(profileRow.data);
  const s = k => str(p[k], 300);

  const t = now();
  const m = msk(t);
  const data = {
    date: m.date,                      // при выпуске заменяется датой допуска
    dateFormatted: m.dateFormatted,
    driverName: user.full_name,
    driverPhone: user.phone,
    carModel: s('carModel'),
    plateNumber: s('plateNumber'),
    license: s('license'),
    licenseClass: s('licenseClass'),
    licenseIssued: s('licenseIssued'),
    licenseExpires: s('licenseExpires'),
    driverIdNumber: s('driverIdNumber'),
    osgop: s('osgop'),
    garageNumber: s('garageNumber'),
    tabNumber: s('tabNumber'),
    snils: s('snils'),
    driverInn: s('inn'),
    transportType: s('transportType'),
    commType: s('commType'),
    orgName: s('orgName'),
    orgAddress: s('orgAddress'),
    ogrn: s('orgOgrn'),
    orgInn: s('orgInn'),
    orgPhone: s('orgPhone'),
    okud: s('okud') || '0345001',
    okpo: s('okpo'),
    permitNumber: s('permit'),
    mintransOrder: s('mintrans') || '390 ОТ 28.09.2022',
    medCert: s('medCert'),
    techCert: s('techCert'),
    odometerStart: String(odometer),
  };
  const id = newId();
  // Номер листа: время с точностью до 0,1 с.
  const number = String(Math.floor(t / 100));
  try {
    await env.DB.prepare(
      `INSERT INTO waybills (id, number, driver_id, status, created_at, data, signature)
       VALUES (?, ?, ?, 'pending', ?, ?, ?)`
    ).bind(id, number, user.id, t, JSON.stringify(data), signature).run();
  } catch (e) {
    // Двойное нажатие: второй запрос упрётся в уникальный индекс.
    if (/UNIQUE/i.test(String(e && e.message))) fail(409, 'already-exists', 'Запрос на допуск уже отправлен');
    throw e;
  }

  const row = await env.DB.prepare('SELECT * FROM waybills WHERE id = ?').bind(id).first();
  return waybillOut(row);
}

export async function getOwnWaybill(env, user, id) {
  const row = await env.DB.prepare('SELECT * FROM waybills WHERE id = ? AND driver_id = ?').bind(id, user.id).first();
  if (!row) fail(404, 'not-found', 'Путевой лист не найден');
  return waybillOut(row);
}

// Водитель: отменить свой запрос (pending → cancelled) или закрыть смену (active → closed).
export async function driverSetStatus(env, user, id, action) {
  const from = action === 'cancel' ? 'pending' : 'active';
  const to = action === 'cancel' ? 'cancelled' : 'closed';
  const res = await env.DB.prepare(
    'UPDATE waybills SET status = ?, closed_at = ? WHERE id = ? AND driver_id = ? AND status = ?'
  ).bind(to, now(), id, user.id, from).run();
  if (!res.meta.changes) fail(409, 'wrong-status', 'Действие недоступно для этого листа');
  return getOwnWaybill(env, user, id);
}

// GET /api/checks — листы, ждущие допуска (без подписи — она не нужна медику).
export async function pendingChecks(env) {
  const { results } = await env.DB.prepare(
    `SELECT ${LIST_COLUMNS} FROM waybills WHERE status = 'pending' ORDER BY created_at LIMIT 200`
  ).all();
  return results.map(r => waybillOut(r, { withSignature: false }));
}

// POST /api/checks/:id/mark { ok, reason } — отметка медика или мастера.
// Отметку ставит только сам медик/мастер своей учётной записью; время — серверное.
// Обновление условное (оптимистическая блокировка), поэтому две одновременные
// отметки не потеряют друг друга, а вторая отметка выпускает лист.
export async function markCheck(env, user, id, body) {
  const prefix = user.role === 'medic' ? 'med' : user.role === 'mechanic' ? 'tech' : null;
  if (!prefix) fail(403, 'forbidden', 'Отметку ставит только медик или мастер');
  const other = prefix === 'med' ? 'tech' : 'med';
  const ok = body.ok === true;
  const reason = str(body.reason, 300);

  for (let attempt = 0; attempt < 3; attempt++) {
    const row = await env.DB.prepare('SELECT * FROM waybills WHERE id = ?').bind(id).first();
    if (!row) fail(404, 'not-found', 'Путевой лист не найден');
    if (row.status !== 'pending') fail(409, 'already-processed', 'Запрос уже обработан');
    if (row[`${prefix}_status`]) fail(409, 'already-marked', 'Вы уже отметили этот запрос');
    const otherStatus = row[`${other}_status`];

    const t = now();
    const m = msk(t);
    const data = parseJson(row.data);
    data[`${prefix}Name`] = user.full_name;
    data[`${prefix}CertSerial`] = user.cert_serial;
    data[`${prefix}Issued`] = user.cert_issued;
    data[`${prefix}Expires`] = user.cert_expires;
    data[`${prefix}Time`] = m.time;

    let status = 'pending';
    let expiresAt = null;
    if (!ok) {
      status = 'rejected';
      data.rejectReason = reason;
      data.rejectedRole = user.role;
      data.rejectedAt = t;
    } else if (otherStatus === 'ok') {
      // Вторая отметка — выпускаем ЭПЛ. Смена начинается сейчас.
      const end = msk(t + SHIFT_MS);
      status = 'active';
      expiresAt = t + SHIFT_MS;
      data.date = m.date;
      data.dateFormatted = m.dateFormatted;
      data.shiftStart = m.time;
      data.departureTime = m.time;
      data.shiftEnd = end.time;
      data.shiftEndDate = end.date;
      data.activatedAt = t;
    }

    const res = await env.DB.prepare(
      `UPDATE waybills
         SET status = ?, data = ?, ${prefix}_status = ?, ${prefix}_by = ?, ${prefix}_at = ?,
             expires_at = COALESCE(?, expires_at)
       WHERE id = ? AND status = 'pending' AND ${prefix}_status IS NULL AND ${other}_status IS ?`
    ).bind(status, JSON.stringify(data), ok ? 'ok' : 'rejected', user.id, t, expiresAt,
      id, otherStatus ?? null).run();
    if (res.meta.changes === 1) return { status };
    // Кто-то успел отметить одновременно — перечитываем и пробуем снова.
  }
  fail(409, 'conflict', 'Не удалось сохранить отметку, попробуйте ещё раз');
}

// GET /api/public/waybills/:id — страница по QR-коду.
// Невыпущенный лист не показываем как документ.
export async function publicWaybill(env, id) {
  const row = await env.DB.prepare('SELECT * FROM waybills WHERE id = ?').bind(id).first();
  if (!row) fail(404, 'not-found', 'Путевой лист не найден');
  if (row.status !== 'active' && row.status !== 'closed') {
    return { id: row.id, status: row.status };
  }
  return waybillOut(row);
}
