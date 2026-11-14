// Перенос выгрузки из Firebase в базу D1 нового сервера (см. README.md).
//
//   node migration/import.mjs <папка выгрузки> --dry
//       только проверить и показать, что будет перенесено;
//   MIGRATION_SECRET=... node migration/import.mjs <папка выгрузки> --api https://asem-pro-api....workers.dev
//       очистить базу D1 и записать всё заново (можно повторять).
//
// Пароли: администратор, выгрузивший данные, входит со своим прежним паролем;
// водители — с последними 6 цифрами номера (как при регистрации);
// медикам и мастерам создаются новые пароли — список в <папка>/staff-passwords.txt.
// При повторном переносе (в день переключения) передайте прежний список:
//   --passwords <путь к staff-passwords.txt> — у этих сотрудников пароли не изменятся.
import fs from 'node:fs';
import path from 'node:path';
import { webcrypto as crypto } from 'node:crypto';

const args = process.argv.slice(2);
const opt = name => (args.indexOf(name) >= 0 ? args[args.indexOf(name) + 1] : null);
const dir = args.find((a, i) => !a.startsWith('--') && !['--api', '--passwords'].includes(args[i - 1]));
const dry = args.includes('--dry');
const API = opt('--api');
const passwordsFile = opt('--passwords') || (dir ? path.join(dir, 'staff-passwords.txt') : null);
const SECRET = process.env.MIGRATION_SECRET || '';

if (!dir || (!dry && (!API || !SECRET))) {
  console.error('Использование: node migration/import.mjs <папка> --dry');
  console.error('           или MIGRATION_SECRET=... node migration/import.mjs <папка> --api <адрес API>');
  process.exit(2);
}

const read = name => JSON.parse(fs.readFileSync(path.join(dir, name + '.json'), 'utf8'));
const meta = read('meta');
if (!meta.finishedAt) throw new Error('Выгрузка не завершена (нет meta.finishedAt)');

// ── Общие правила (как на сервере) ─────────────────────────────────────────
const PBKDF2_ITER = 100000;
const SHIFT_MS = 12 * 3600 * 1000;
const DRIVER_FIELDS = [
  'carModel', 'plateNumber', 'garageNumber', 'tabNumber', 'license', 'licenseClass',
  'licenseIssued', 'licenseExpires', 'driverIdNumber', 'osgop', 'snils', 'inn',
  'transportType', 'commType', 'orgName', 'orgOgrn', 'orgInn', 'orgPhone', 'orgAddress',
  'okud', 'okpo', 'permit', 'mintrans', 'medCert', 'techCert', 'crmStatus', 'monthlyPrice',
];
const CRM_STATUSES = ['active', 'lead', 'paused', 'debtor'];
const WAYBILL_STATUSES = ['pending', 'active', 'closed', 'rejected', 'cancelled'];

function normalizePhone(raw) {
  let phone = String(raw || '').replace(/[\s()\-]/g, '');
  if (phone.startsWith('8') && phone.length === 11) phone = '+7' + phone.slice(1);
  if (/^9\d{9}$/.test(phone)) phone = '+7' + phone;
  if (!phone.startsWith('+')) phone = '+' + phone;
  return phone;
}
const isValidPhone = p => /^\+\d{10,15}$/.test(p);
const s = (v, max = 500) => (v == null ? '' : String(v).trim().slice(0, max));
const ms = v => (typeof v === 'number' && v > 0 ? Math.round(v) : null);
const b64 = bytes => Buffer.from(bytes).toString('base64');

async function hashPassword(password) {
  const salt = crypto.getRandomValues(new Uint8Array(16));
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(password), 'PBKDF2', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations: PBKDF2_ITER }, key, 256);
  return { pass_hash: b64(new Uint8Array(bits)), pass_salt: b64(salt), pass_iter: PBKDF2_ITER };
}

function randomPassword() {
  const abc = 'abcdefghjkmnpqrstuvwxyz23456789';
  const bytes = crypto.getRandomValues(new Uint8Array(10));
  return Array.from(bytes, b => abc[b % abc.length]).join('');
}

// «дд.мм.гггг» → полночь по Москве, мс.
function ruDate(v) {
  const m = /^(\d{2})\.(\d{2})\.(\d{4})$/.exec(s(v));
  return m ? Date.UTC(+m[3], +m[2] - 1, +m[1]) - 3 * 3600 * 1000 : null;
}

const warnings = [];
const warn = text => warnings.push(text);
const t0 = Date.now();

// ── Сотрудники ─────────────────────────────────────────────────────────────
const rows = {
  users: [], drivers: [], waybills: [], support_chats: [], support_messages: [],
  payments: [], driver_notes: [], settings: [], deletion_requests: [],
};
const staffPasswords = [];
const staffPhones = new Set();
// Пароли, выданные при прошлом переносе: телефон → пароль.
const previous = new Map();
if (passwordsFile && fs.existsSync(passwordsFile)) {
  for (const line of fs.readFileSync(passwordsFile, 'utf8').split(/\r?\n/).slice(1)) {
    const [phone, , , pass] = line.split('\t');
    if (phone && pass) previous.set(phone, pass);
  }
}
let reusedPasswords = 0;

for (const { id, data: a } of read('admins').docs) {
  const role = ['admin', 'medic', 'mechanic'].includes(a.role) ? a.role : 'admin';
  let phone = normalizePhone(a.phone);
  if (!isValidPhone(phone) && id === meta.adminUid) phone = meta.adminPhone;
  if (!isValidPhone(phone)) { warn(`сотрудник ${id} (${s(a.fullName) || 'без имени'}): нет номера телефона — пропущен`); continue; }
  if (staffPhones.has(phone)) { warn(`сотрудник ${id}: номер ${phone} уже занят другим сотрудником — пропущен`); continue; }
  staffPhones.add(phone);

  let pass;
  if (id === meta.adminUid) {
    pass = { pass_hash: meta.passHash, pass_salt: meta.passSalt, pass_iter: meta.passIter };
  } else {
    const p = previous.get(phone) || randomPassword();
    if (previous.has(phone)) reusedPasswords++;
    pass = await hashPassword(p);
    staffPasswords.push(`${phone}\t${s(a.fullName) || '—'}\t${role}\t${p}`);
  }
  rows.users.push({
    id, scope: 'staff', role, phone, full_name: s(a.fullName, 200), ...pass,
    active: a.active === false ? 0 : 1,
    cert_serial: s(a.certSerial, 100), cert_issued: s(a.certIssued, 20), cert_expires: s(a.certExpires, 20),
    created_at: ms(a.createdAt) || meta.exportedAt, updated_at: ms(a.updatedAt),
  });
}
if (!rows.users.some(u => u.id === meta.adminUid)) {
  throw new Error('Администратор, сделавший выгрузку, не попал в список сотрудников — перенос остановлен');
}

// ── Водители ───────────────────────────────────────────────────────────────
const driversExport = read('drivers').docs;
const docToUser = {};                 // id документа drivers → id учётной записи
for (const d of driversExport) docToUser[d.id] = s(d.data.authUid) || d.id;

// Один номер — одна учётная запись водителя: при повторе оставляем активную и более новую.
const byPhone = new Map();
// Номер из профиля, а если его нет — из служебного email входа (<цифры>@asempro.driver).
const driverPhone = x => {
  const p = normalizePhone(x.phone);
  if (isValidPhone(p)) return p;
  const digits = s(x.authEmail).split('@')[0].replace(/\D/g, '');
  return digits ? '+' + digits : p;
};
for (const d of driversExport) {
  const phone = driverPhone(d.data);
  const prev = byPhone.get(phone);
  const score = x => [x.data.active === false ? 0 : 1, ms(x.data.createdAt) || 0];
  if (!prev) { byPhone.set(phone, d); continue; }
  const [a1, c1] = score(d), [a2, c2] = score(prev);
  const keepNew = a1 > a2 || (a1 === a2 && c1 > c2);
  const dropped = keepNew ? prev : d;
  warn(`водитель ${dropped.id} (${s(dropped.data.fullName)}): номер ${phone} повторяется — профиль не перенесён, его листы сохранены`);
  if (keepNew) byPhone.set(phone, d);
}

const userIds = new Set(rows.users.map(u => u.id));
let driverCount = 0;
for (const [phone, d] of byPhone) {
  const x = d.data;
  const id = docToUser[d.id];
  if (userIds.has(id)) { warn(`водитель ${d.id}: id ${id} совпадает с сотрудником — пропущен`); continue; }
  if (!isValidPhone(phone)) warn(`водитель ${s(x.fullName)} (${d.id}): некорректный номер «${s(x.phone)}» — войти не сможет`);
  userIds.add(id);
  const digits = phone.replace(/\D/g, '');
  const pass = digits.length >= 6 ? await hashPassword(digits.slice(-6)) : { pass_hash: null, pass_salt: null, pass_iter: null };
  const created = ms(x.createdAt) || meta.exportedAt;
  rows.users.push({
    id, scope: 'driver', role: 'driver', phone, full_name: s(x.fullName, 200), ...pass,
    active: x.active === false ? 0 : 1, cert_serial: '', cert_issued: '', cert_expires: '',
    created_at: created, updated_at: ms(x.updatedAt),
  });
  const profile = {};
  for (const k of DRIVER_FIELDS) {
    if (!(k in x)) continue;
    if (k === 'monthlyPrice') {
      const n = parseFloat(x[k]);
      profile[k] = Number.isFinite(n) && n >= 0 ? n : 0;
    } else if (k === 'crmStatus') {
      profile[k] = CRM_STATUSES.includes(x[k]) ? x[k] : 'active';
    } else {
      profile[k] = s(x[k], 300);
    }
  }
  rows.drivers.push({ user_id: id, data: JSON.stringify(profile), created_at: created, updated_at: ms(x.updatedAt) });
  driverCount++;

  for (const n of d.notes || []) {
    const text = s(n.data.text, 2000);
    if (!text) continue;
    rows.driver_notes.push({ driver_id: id, text, created_at: ms(n.data.createdAt) || created, created_by: s(n.data.createdBy) || null });
  }
}
rows.driver_notes.sort((a, b) => a.created_at - b.created_at);

// ── Путевые листы ──────────────────────────────────────────────────────────
const waybillFiles = fs.readdirSync(dir).filter(f => /^waybills-\d+\.json$/.test(f)).sort();
if (waybillFiles.length !== (meta.waybillPages || 0)) {
  throw new Error(`Не хватает частей выгрузки листов: ${waybillFiles.length} из ${meta.waybillPages}`);
}
const pendingByDriver = new Map();
for (const f of waybillFiles) {
  for (const { id, data: w } of read(f.replace(/\.json$/, '')).docs) {
    const driverId = s(w.authUid) || docToUser[s(w.driverId)] || s(w.driverId);
    if (!driverId) { warn(`лист ${id}: не указан водитель — пропущен`); continue; }
    let status = WAYBILL_STATUSES.includes(w.status) ? w.status : 'closed';
    if (!WAYBILL_STATUSES.includes(w.status)) warn(`лист ${id}: статус «${s(w.status)}» записан как closed`);
    const created = ms(w.createdAt) || ms(w.activatedAt) || ruDate(w.date) || 0;
    if (!created) warn(`лист ${id}: нет даты создания`);
    let expires = ms(w.expiresAt);
    // Старые листы без срока: действуют 12 часов с момента создания.
    if (status === 'active' && !expires) expires = created + SHIFT_MS;
    const mark = p => (['ok', 'rejected'].includes(w[p + 'Status']) ? w[p + 'Status'] : null);
    const data = { ...w };
    delete data.signatureData;
    const signature = typeof w.signatureData === 'string' && w.signatureData.startsWith('data:image') ? w.signatureData : null;
    const row = {
      id, number: s(w.waybillNumber, 40) || id, driver_id: driverId, status,
      created_at: created, expires_at: expires, closed_at: ms(w.closedAt),
      med_status: mark('med'), med_by: s(w.medConfirmedBy || w.medBy) || null, med_at: ms(w.medConfirmedAt) || ms(w.medAt),
      tech_status: mark('tech'), tech_by: s(w.techConfirmedBy || w.techBy) || null, tech_at: ms(w.techConfirmedAt) || ms(w.techAt),
      data: JSON.stringify(data), signature,
    };
    rows.waybills.push(row);
    if (status === 'pending') {
      const list = pendingByDriver.get(driverId) || [];
      list.push(row);
      pendingByDriver.set(driverId, list);
    }
  }
}
// У водителя может быть только один запрос на допуск — лишние (старые) отменяем.
for (const list of pendingByDriver.values()) {
  list.sort((a, b) => b.created_at - a.created_at);
  for (const extra of list.slice(1)) {
    extra.status = 'cancelled';
    extra.closed_at = extra.closed_at || meta.exportedAt;
    warn(`лист ${extra.id}: второй запрос на допуск у водителя — отменён`);
  }
}

// ── Техподдержка ───────────────────────────────────────────────────────────
for (const { id, data: c, messages } of read('support').docs) {
  const driverId = docToUser[id] || id;
  const msgs = (messages || [])
    .map(m => ({ sender: m.data.sender, text: s(m.data.text, 2000), created_at: ms(m.data.createdAt) || 0 }))
    .filter(m => (m.sender === 'driver' || m.sender === 'admin') && m.text)
    .sort((a, b) => a.created_at - b.created_at);
  const last = msgs[msgs.length - 1];
  rows.support_chats.push({
    driver_id: driverId,
    last_message: s(c.lastMessage, 200) || (last ? last.text.slice(0, 200) : ''),
    last_sender: s(c.lastSender) || (last ? last.sender : ''),
    last_at: ms(c.lastMessageAt) || ms(c.updatedAt) || (last ? last.created_at : meta.exportedAt),
    unread_admin: Number(c.unreadForAdmin) > 0 ? Math.floor(Number(c.unreadForAdmin)) : 0,
    unread_driver: Number(c.unreadForDriver) > 0 ? Math.floor(Number(c.unreadForDriver)) : 0,
  });
  for (const m of msgs) rows.support_messages.push({ driver_id: driverId, ...m });
}
// id сообщений растут по времени — клиенты забирают «новее последнего id».
rows.support_messages.sort((a, b) => a.created_at - b.created_at);

// ── Оплаты, настройки, заявки на удаление ─────────────────────────────────
const payKey = new Map();
for (const { id, data: p } of read('payments').docs) {
  const driverId = docToUser[s(p.driverId)] || s(p.driverId);
  const period = s(p.period, 7);
  if (!driverId || !/^\d{4}-\d{2}$/.test(period)) { warn(`оплата ${id}: нет водителя или периода — пропущена`); continue; }
  const row = {
    driver_id: driverId, period, amount: Number(p.amount) || 0, paid: p.paid ? 1 : 0,
    paid_at: ms(p.paidAt), marked_by: s(p.markedBy) || null, updated_at: ms(p.updatedAt),
  };
  const k = driverId + '|' + period;
  const prev = payKey.get(k);
  if (!prev || (row.updated_at || 0) > (prev.updated_at || 0)) payKey.set(k, row);
}
rows.payments = [...payKey.values()];

const company = read('settings').company;
if (company) {
  const value = {};
  for (const [k, v] of Object.entries(company)) if (typeof v === 'string') value[k] = s(v, 300);
  rows.settings.push({ key: 'company', value: JSON.stringify(value) });
}

for (const { data: r } of read('deletions').docs) {
  const userId = s(r.uid);
  if (!userId) continue;
  const digits = s(r.email).split('@')[0].replace(/\D/g, '');
  rows.deletion_requests.push({
    user_id: userId, phone: digits ? '+' + digits : '', requested_at: ms(r.requestedAt) || meta.exportedAt,
    status: s(r.status, 20) || 'pending',
  });
}

// ── Итог ───────────────────────────────────────────────────────────────────
const staffCount = rows.users.filter(u => u.scope === 'staff').length;
console.log(`Выгрузка от ${new Date(meta.exportedAt).toLocaleString('ru-RU')} (подготовка ${Math.round((Date.now() - t0) / 1000)} с)`);
console.log(`  в Firebase: ${Object.entries(meta.counts).map(([k, v]) => `${k} ${v}`).join(', ')}`);
console.log(`  к переносу: сотрудники ${staffCount}, водители ${driverCount}, листы ${rows.waybills.length}, ` +
  `диалоги ${rows.support_chats.length} (сообщений ${rows.support_messages.length}), оплаты ${rows.payments.length}, ` +
  `заметки ${rows.driver_notes.length}, заявки на удаление ${rows.deletion_requests.length}`);
if (warnings.length) {
  console.log(`\nЗамечания (${warnings.length}):`);
  for (const w of warnings) console.log('  • ' + w);
}

if (dry) {
  if (staffPasswords.length) console.log(`\nПароли сотрудников: ${staffPasswords.length}, из них прежних ${reusedPasswords} (файл появится после записи)`);
  console.log('\nПроверка без записи (--dry): в базу ничего не отправлено.');
  process.exit(0);
}

// ── Запись в D1 через API ──────────────────────────────────────────────────
async function call(action, body) {
  const res = await fetch(`${API}/api/migrate/${action}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'X-Migration-Secret': SECRET },
    body: JSON.stringify(body || {}),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error(`${action}: ${res.status} ${data.message || ''}`);
  return data;
}

console.log(`\nЗапись в ${API}…`);
await call('reset');
const ORDER = ['users', 'drivers', 'waybills', 'support_chats', 'support_messages', 'payments', 'driver_notes', 'settings', 'deletion_requests'];
for (const table of ORDER) {
  const list = rows[table];
  // Листы с подписями тяжёлые — шлём их пачками поменьше.
  const size = table === 'waybills' ? 20 : 40;
  for (let i = 0; i < list.length; i += size) {
    await call('rows', { table, rows: list.slice(i, i + size) });
  }
  if (list.length) console.log(`  ${table}: ${list.length}`);
}
const counts = await call('counts');
const mismatch = ORDER.filter(t => counts[t] !== rows[t].length);
if (mismatch.length) {
  console.log('\nРасхождение после записи:', mismatch.map(t => `${t} ${counts[t]}≠${rows[t].length}`).join(', '));
  process.exit(1);
}
// Пароли сохраняем только после успешной записи — именно они теперь действуют.
if (staffPasswords.length) {
  const file = path.join(dir, 'staff-passwords.txt');
  fs.writeFileSync(file, 'Телефон\tФИО\tРоль\tПароль\n' + staffPasswords.join('\n') + '\n');
  console.log(`\nПароли медиков и мастеров (прежних ${reusedPasswords}, новых ${staffPasswords.length - reusedPasswords}): ${file}`);
}
console.log('\nГотово: все строки записаны, количество совпадает.');
