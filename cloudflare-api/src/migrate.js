// Разовый перенос данных из Firebase (см. migration/README.md).
// Работает, только пока задан секрет MIGRATION_SECRET; после переноса
// секрет удаляется (wrangler secret delete MIGRATION_SECRET) и адреса
// /api/migrate/* перестают существовать.
//
// Строки приходят уже в виде таблиц D1 (их готовит migration/import.mjs),
// здесь только проверка секрета, белый список колонок и запись пачками.
import { fail, readJson, sha256Hex } from './lib.js';

const TABLES = {
  users: ['id', 'scope', 'role', 'phone', 'full_name', 'pass_hash', 'pass_salt', 'pass_iter',
    'active', 'cert_serial', 'cert_issued', 'cert_expires', 'created_at', 'updated_at'],
  drivers: ['user_id', 'data', 'created_at', 'updated_at'],
  waybills: ['id', 'number', 'driver_id', 'status', 'created_at', 'expires_at', 'closed_at',
    'med_status', 'med_by', 'med_at', 'tech_status', 'tech_by', 'tech_at', 'data', 'signature'],
  support_chats: ['driver_id', 'last_message', 'last_sender', 'last_at', 'unread_admin', 'unread_driver'],
  support_messages: ['driver_id', 'sender', 'text', 'created_at'],
  payments: ['driver_id', 'period', 'amount', 'paid', 'paid_at', 'marked_by', 'updated_at'],
  driver_notes: ['driver_id', 'text', 'created_at', 'created_by'],
  settings: ['key', 'value'],
  deletion_requests: ['user_id', 'phone', 'requested_at', 'status'],
};

// Порядок очистки: сначала зависимые таблицы.
const WIPE_ORDER = ['sessions', 'login_attempts', 'waybills', 'support_messages', 'support_chats',
  'payments', 'driver_notes', 'settings', 'deletion_requests', 'drivers', 'users'];

const MAX_ROWS = 40;   // запросов к D1 за один вызов воркера — не больше 50 (бесплатный тариф)

async function checkSecret(request, env) {
  if (!env.MIGRATION_SECRET) fail(404, 'not-found', 'Нет такого адреса API');
  const given = request.headers.get('X-Migration-Secret') || '';
  // Сравниваем хэши: время сравнения не зависит от совпадающих символов.
  if (await sha256Hex(given) !== await sha256Hex(env.MIGRATION_SECRET)) {
    fail(403, 'forbidden', 'Неверный секрет переноса');
  }
}

export async function migrate(request, env, action) {
  await checkSecret(request, env);

  if (action === 'reset') {
    await env.DB.batch(WIPE_ORDER.map(t => env.DB.prepare(`DELETE FROM ${t}`)));
    return { ok: true };
  }

  if (action === 'counts') {
    const tables = Object.keys(TABLES);
    const res = await env.DB.batch(tables.map(t => env.DB.prepare(`SELECT COUNT(*) AS n FROM ${t}`)));
    const out = {};
    tables.forEach((t, i) => { out[t] = res[i].results[0].n; });
    return out;
  }

  if (action === 'rows') {
    const body = await readJson(request);
    const cols = TABLES[body.table];
    if (!cols) fail(400, 'bad-table', 'Неизвестная таблица');
    const rows = Array.isArray(body.rows) ? body.rows : [];
    if (!rows.length) return { inserted: 0 };
    if (rows.length > MAX_ROWS) fail(400, 'too-many', `Не больше ${MAX_ROWS} строк за раз`);
    const sql = `INSERT INTO ${body.table} (${cols.join(', ')}) VALUES (${cols.map(() => '?').join(', ')})`;
    const stmts = rows.map(r => env.DB.prepare(sql).bind(...cols.map(c => (r[c] === undefined ? null : r[c]))));
    await env.DB.batch(stmts);
    return { inserted: rows.length };
  }

  fail(404, 'not-found', 'Нет такого адреса API');
}
