// Проверка переноса на локальном сервере (wrangler dev с MIGRATION_SECRET в .dev.vars):
//   node migration/test/roundtrip.mjs http://127.0.0.1:8787
// Собирает выгрузку «как из Firestore» с трудными случаями, переносит её
// через import.mjs и проверяет вход и данные через обычный API.
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { webcrypto as crypto } from 'node:crypto';

const BASE = process.argv[2] || 'http://127.0.0.1:8787';
const SECRET = process.env.MIGRATION_SECRET || 'local-migration-secret';
const here = path.dirname(fileURLToPath(import.meta.url));
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'asempro-export-'));

let passed = 0, failed = 0;
const check = (name, cond, extra) => {
  if (cond) { passed++; console.log('  ✓', name); } else { failed++; console.log('  ✗', name, extra !== undefined ? JSON.stringify(extra).slice(0, 400) : ''); }
};
async function api(method, p, { token, body } = {}) {
  const res = await fetch(BASE + p, {
    method, headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: 'Bearer ' + token } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  let data = null; try { data = await res.json(); } catch (_) {}
  return { status: res.status, data };
}
const login = async (phone, password, scope) => (await api('POST', '/api/auth/login', { body: { phone, password, scope } })).data?.token;

// ── Выгрузка-образец ─────────────────────────────────────────────────────
const H = 3600 * 1000;
const NOW = Date.now();
const SIG = 'data:image/png;base64,' + 'A'.repeat(150000);   // крупная подпись (150 КБ)
const save = (name, obj) => fs.writeFileSync(path.join(dir, name + '.json'), JSON.stringify(obj));

const salt = crypto.getRandomValues(new Uint8Array(16));
const key = await crypto.subtle.importKey('raw', new TextEncoder().encode('admin-pass-1'), 'PBKDF2', false, ['deriveBits']);
const bits = await crypto.subtle.deriveBits({ name: 'PBKDF2', hash: 'SHA-256', salt, iterations: 100000 }, key, 256);
const b64 = u => Buffer.from(u).toString('base64');

save('admins', { docs: [
  { id: 'uidAdmin', data: { role: 'admin', fullName: 'Главный Админ', createdAt: NOW - 400 * 24 * H } },   // без телефона
  { id: 'uidMedic', data: { role: 'medic', phone: '+7 900 000-00-11', fullName: 'Медик Иванова', certSerial: 'ab12', certIssued: '15.11.2026', certExpires: '15.11.2027' } },
  { id: 'uidMech', data: { role: 'mechanic', phone: '89000000012', fullName: 'Мастер Петров' } },
  { id: 'uidNoPhone', data: { role: 'medic', fullName: 'Без номера' } },
] });
save('settings', { company: { orgName: 'ООО Такси', orgInn: '7700000000', updatedAt: NOW } });
save('drivers', { docs: [
  { id: 'uidD1', data: { authUid: 'uidD1', fullName: 'Водитель Один', phone: '+79991110001', carModel: 'Kia Rio', plateNumber: 'А111АА77', monthlyPrice: '3500', crmStatus: 'active', active: true, createdAt: NOW - 100 * 24 * H },
    notes: [{ id: 'n2', data: { text: 'Вторая', createdAt: NOW - 1 * H } }, { id: 'n1', data: { text: 'Первая', createdAt: NOW - 2 * H } }] },
  // Старая запись: документ не совпадает с учётной записью, номер только в email.
  { id: 'legacyDoc', data: { authUid: 'uidD2', fullName: 'Водитель Два', authEmail: '79991110002@asempro.driver', carModel: 'Lada', active: true, createdAt: NOW - 200 * 24 * H } },
  // Повтор номера: неактивная копия водителя 1.
  { id: 'uidD1old', data: { authUid: 'uidD1old', fullName: 'Водитель Один (старый)', phone: '89991110001', active: false, createdAt: NOW - 300 * 24 * H } },
  { id: 'uidD3', data: { authUid: 'uidD3', fullName: 'Водитель Три', phone: '9991110003', active: false } },
] });
save('waybills-0001', { docs: [
  { id: 'wActive', data: { authUid: 'uidD1', waybillNumber: '111', status: 'active', createdAt: NOW - 2 * H, expiresAt: NOW + 10 * H, medStatus: 'ok', medConfirmedAt: NOW - 1.5 * H, medConfirmedBy: 'uidMedic', medName: 'Медик Иванова', techStatus: 'ok', techConfirmedAt: NOW - 1.4 * H, techConfirmedBy: 'uidMech', techName: 'Мастер Петров', driverName: 'Водитель Один', signatureData: SIG } },
  { id: 'wLegacy', data: { driverId: 'legacyDoc', waybillNumber: '222', status: 'active', date: '01.03.2026', odometerStart: '1000' } },   // без времени и срока
  { id: 'wPendOld', data: { authUid: 'uidD2', status: 'pending', createdAt: NOW - 30 * H } },
  { id: 'wPendNew', data: { authUid: 'uidD2', status: 'pending', createdAt: NOW - 1 * H } },
  { id: 'wWeird', data: { authUid: 'uidD3', status: 'completed', createdAt: NOW - 50 * H } },
] });
save('support', { docs: [
  { id: 'legacyDoc', data: { lastMessage: 'Ответ', lastSender: 'admin', lastMessageAt: NOW - H, unreadForAdmin: 0, unreadForDriver: 1 },
    messages: [{ id: 'm2', data: { sender: 'admin', text: 'Ответ', createdAt: NOW - H } }, { id: 'm1', data: { sender: 'driver', text: 'Вопрос', createdAt: NOW - 2 * H } }] },
] });
save('payments', { docs: [
  { id: 'uidD1_2026-10', data: { driverId: 'uidD1', period: '2026-10', amount: 3500, paid: true, paidAt: NOW - 20 * 24 * H, updatedAt: NOW - 20 * 24 * H } },
  { id: 'legacyDoc_2026-10', data: { driverId: 'legacyDoc', period: '2026-10', amount: 3000, paid: false } },
  { id: 'bad', data: { driverId: 'uidD1', period: 'октябрь' } },
] });
save('deletions', { docs: [{ id: 'r1', data: { uid: 'uidD3', email: '79991110003@asempro.driver', requestedAt: NOW - 5 * H, status: 'pending' } }] });
save('meta', {
  exportedAt: NOW, finishedAt: NOW, waybillPages: 1, adminUid: 'uidAdmin', adminPhone: '+79000000010',
  passHash: b64(new Uint8Array(bits)), passSalt: b64(salt), passIter: 100000,
  counts: { admins: 4, drivers: 4, waybills: 5, supportChats: 1, payments: 3, deletionRequests: 1 },
});

// ── Перенос ──────────────────────────────────────────────────────────────
const importer = path.join(here, '..', 'import.mjs');
const run = (...a) => execFileSync(process.execPath, [importer, dir, ...a], { env: { ...process.env, MIGRATION_SECRET: SECRET }, encoding: 'utf8' });
console.log('Выгрузка-образец:', dir);
const dryOut = run('--dry');
check('проверка без записи: замечания о трудных случаях', /повторяется/.test(dryOut) && /нет номера телефона/.test(dryOut) && /второй запрос/.test(dryOut) && /completed/.test(dryOut) && /оплата bad/.test(dryOut), dryOut);
check('без секрета перенос не идёт', (await fetch(BASE + '/api/migrate/counts', { method: 'POST' })).status === 403);
const out = run('--api', BASE);
check('перенос завершён, количество совпало', /Готово/.test(out), out);
const firstPw = fs.readFileSync(path.join(dir, 'staff-passwords.txt'), 'utf8');
// Повторный перенос (как в день переключения): база очищается, пароли сотрудников прежние.
const out2 = run('--api', BASE);
check('повторный перенос проходит, пароли сотрудников прежние',
  /Готово/.test(out2) && /прежних 2, новых 0/.test(out2) && fs.readFileSync(path.join(dir, 'staff-passwords.txt'), 'utf8') === firstPw, out2);
const pw = fs.readFileSync(path.join(dir, 'staff-passwords.txt'), 'utf8').trim().split('\n').slice(1).map(l => l.split('\t'));

// ── Проверка через обычный API ───────────────────────────────────────────
console.log('\n— Входы');
const adminT = await login('+7 900 000-00-10', 'admin-pass-1', 'staff');
check('админ входит со старым паролем', !!adminT);
const medPass = pw.find(r => r[0] === '+79000000011');
check('медику выдан новый пароль, он работает', !!medPass && !!(await login('+79000000011', medPass[3], 'staff')));
check('сотрудник без номера не перенесён', !pw.some(r => r[1] === 'Без номера'));
const d1T = await login('+79991110001', '110001', 'driver');
check('водитель входит с последними 6 цифрами', !!d1T);
const d2T = await login('89991110002', '110002', 'driver');
check('водитель со старой записью (номер из email) входит', !!d2T);
const r3 = await api('POST', '/api/auth/login', { body: { phone: '+79991110003', password: '110003', scope: 'driver' } });
check('отключённый водитель не входит', r3.status === 403 && r3.data.error === 'blocked', r3);

console.log('\n— Данные');
let r = await api('GET', '/api/me', { token: d1T });
check('профиль водителя перенесён (активная копия)', r.data.driver.carModel === 'Kia Rio' && r.data.driver.monthlyPrice === 3500 && r.data.user.fullName === 'Водитель Один', r.data);
r = await api('GET', '/api/driver/waybills/current', { token: d1T });
check('действующий лист с подписью и отметками', r.data.waybill?.id === 'wActive' && r.data.waybill.signatureData === SIG && r.data.waybill.medStatus === 'ok' && r.data.waybill.medName === 'Медик Иванова', r.data.waybill && { ...r.data.waybill, signatureData: (r.data.waybill.signatureData || '').length });
r = await api('GET', '/api/driver/waybills/current', { token: d2T });
check('из двух запросов остался новый', r.data.waybill?.id === 'wPendNew', r.data);
r = await api('GET', '/api/driver/waybills/wLegacy', { token: d2T });
check('старый лист без даты получил срок и остался у водителя', r.status === 200 && r.data.status === 'active' && r.data.expiresAt === r.data.createdAt + 12 * 3600 * 1000 && r.data.createdAt > 0, r.data);
r = await api('GET', '/api/driver/support?after=0', { token: d2T });
check('переписка по порядку, ответ не прочитан', r.data.messages.map(m => m.text).join('|') === 'Вопрос|Ответ' && r.data.unread === 1, r.data);
r = await api('GET', '/api/admin/drivers/uidD1/notes', { token: adminT });
check('заметки CRM', r.data.items.length === 2, r.data);
r = await api('GET', '/api/admin/payments?period=2026-10', { token: adminT });
check('оплаты (у старой записи — по учётной записи)', r.data.items.length === 2 && r.data.items.some(p => p.driverId === 'uidD2' && p.amount === 3000), r.data);
r = await api('GET', '/api/admin/settings', { token: adminT });
check('настройки организации', r.data.orgName === 'ООО Такси' && !('updatedAt' in r.data), r.data);
r = await api('GET', '/api/admin/deletion-requests', { token: adminT });
check('заявка на удаление', r.data.items.length === 1 && r.data.items[0].phone === '+79991110003', r.data);
r = await api('GET', '/api/admin/waybills?limit=50', { token: adminT });
check('все листы у админа, странный статус → closed', r.data.items.length === 5 && r.data.items.find(w => w.id === 'wWeird')?.status === 'closed' && r.data.items.find(w => w.id === 'wPendOld')?.status === 'cancelled', r.data.items.map(w => [w.id, w.status]));
r = await api('GET', '/api/public/waybills/wActive');
check('лист открывается по QR', r.status === 200 && r.data.techName === 'Мастер Петров', r.data);
r = await api('GET', '/api/admin/staff', { token: adminT });
check('сотрудники с сертификатами', r.data.items.length === 3 && r.data.items.find(u => u.role === 'medic')?.certExpires === '15.11.2027', r.data);

fs.rmSync(dir, { recursive: true, force: true });
console.log(`\nИтого: ${passed} ✓, ${failed} ✗`);
process.exit(failed ? 1 : 0);
