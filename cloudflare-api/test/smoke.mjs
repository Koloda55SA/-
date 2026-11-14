// Сквозная проверка API на локальном сервере (wrangler dev, локальная D1).
// Запуск: node test/smoke.mjs [http://127.0.0.1:8787]
const BASE = process.argv[2] || 'http://127.0.0.1:8787';
const SECRET = process.env.BOOTSTRAP_SECRET || 'local-test-secret';

let passed = 0;
let failed = 0;
function check(name, cond, extra) {
  if (cond) { passed++; console.log('  ✓', name); }
  else { failed++; console.log('  ✗', name, extra !== undefined ? JSON.stringify(extra) : ''); }
}

async function api(method, path, { token, body } = {}) {
  const res = await fetch(BASE + path, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: 'Bearer ' + token } : {}),
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  let data = null;
  try { data = await res.json(); } catch (_) {}
  return { status: res.status, data };
}

const login = async (phone, password, scope) => {
  const r = await api('POST', '/api/auth/login', { body: { phone, password, scope } });
  return r.data && r.data.token;
};

const SIG = 'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

(async () => {
  console.log('API:', BASE);

  console.log('\n— Запуск и первый администратор');
  check('health', (await api('GET', '/api/health')).status === 200);
  let r = await api('POST', '/api/bootstrap', { body: { secret: 'wrong', phone: '+79990000001', password: 'admin123', fullName: 'Админ' } });
  check('bootstrap с неверным секретом → 403', r.status === 403, r);
  r = await api('POST', '/api/bootstrap', { body: { secret: SECRET, phone: '+79990000001', password: 'admin123', fullName: 'Админ' } });
  check('bootstrap создаёт админа', r.status === 200 && r.data.role === 'admin', r);
  r = await api('POST', '/api/bootstrap', { body: { secret: SECRET, phone: '+79990000009', password: 'admin123', fullName: 'Второй' } });
  check('повторный bootstrap → 409', r.status === 409, r);

  const adminT = await login('8 999 000-00-01', 'admin123', 'staff');
  check('вход админа (номер с 8 и пробелами)', !!adminT);
  check('админ не входит как водитель', !(await login('+79990000001', 'admin123', 'driver')));

  console.log('\n— Сотрудники и водитель');
  r = await api('POST', '/api/admin/staff', { token: adminT, body: {
    fullName: 'Медик Тест', phone: '+79990000002', password: 'medic123', role: 'medic',
    certSerial: 'AA BB 11', certIssued: '15.11.2026', certExpires: '15.11.2027' } });
  check('админ создаёт медика', r.status === 200 && r.data.role === 'medic' && r.data.certSerial === 'aabb11', r);
  r = await api('POST', '/api/admin/staff', { token: adminT, body: {
    fullName: 'Мастер Тест', phone: '+79990000003', password: 'mech123', role: 'mechanic' } });
  check('админ создаёт мастера', r.status === 200 && r.data.role === 'mechanic', r);
  r = await api('POST', '/api/admin/drivers', { token: adminT, body: {
    fullName: 'Водитель Тест', phone: '9991112233', carModel: 'Kia Rio', plateNumber: 'А001АА77',
    orgName: 'ООО Тест', monthlyPrice: '3000', crmStatus: 'active', snils: '000-000-000 00' } });
  check('админ создаёт водителя, пароль по умолчанию = 6 цифр', r.status === 200 && r.data.password === '112233' && r.data.driver.phone === '+79991112233', r);
  const driverId = r.data && r.data.driver && r.data.driver.id;
  r = await api('POST', '/api/admin/drivers', { token: adminT, body: { fullName: 'Дубль', phone: '+79991112233' } });
  check('второй водитель с тем же номером → 409', r.status === 409, r);

  const medT = await login('+79990000002', 'medic123', 'staff');
  const mechT = await login('+79990000003', 'mech123', 'staff');
  const drvT = await login('+79991112233', '112233', 'driver');
  check('вход медика, мастера и водителя', !!medT && !!mechT && !!drvT);
  check('неверный пароль не пускает', !(await login('+79991112233', 'wrong1', 'driver')));

  r = await api('GET', '/api/me', { token: drvT });
  check('водитель видит свой профиль', r.status === 200 && r.data.driver.carModel === 'Kia Rio', r);

  console.log('\n— Права доступа');
  check('водитель → админка: 403', (await api('GET', '/api/admin/drivers', { token: drvT })).status === 403);
  check('медик → админка: 403', (await api('GET', '/api/admin/drivers', { token: medT })).status === 403);
  check('без входа → 401', (await api('GET', '/api/admin/drivers')).status === 401);
  check('админ → API водителя: 403', (await api('GET', '/api/driver/waybills/current', { token: adminT })).status === 403);

  console.log('\n— Запрос допуска и отметки');
  r = await api('GET', '/api/driver/waybills/current', { token: drvT });
  check('текущего листа нет', r.status === 200 && r.data.waybill === null, r);
  r = await api('POST', '/api/driver/waybills', { token: drvT, body: { odometer: '152340', signatureData: SIG } });
  check('водитель запрашивает допуск → pending', r.status === 200 && r.data.status === 'pending' && r.data.odometerStart === '152340' && r.data.orgName === 'ООО Тест', r);
  const w1 = r.data.id;
  check('лист собран из профиля на сервере', r.data.driverName === 'Водитель Тест' && r.data.plateNumber === 'А001АА77');
  r = await api('POST', '/api/driver/waybills', { token: drvT, body: { odometer: '152340' } });
  check('второй запрос, пока первый ждёт → 409', r.status === 409, r);

  check('водитель не может поставить отметку', (await api('POST', `/api/checks/${w1}/mark`, { token: drvT, body: { ok: true } })).status === 403);
  check('админ не может поставить отметку', (await api('POST', `/api/checks/${w1}/mark`, { token: adminT, body: { ok: true } })).status === 403);
  r = await api('GET', '/api/public/waybills/' + w1);
  check('по QR невыпущенный лист не показывается', r.status === 200 && r.data.status === 'pending' && !r.data.driverName, r);

  r = await api('GET', '/api/checks', { token: medT });
  check('медик видит очередь (без подписи)', r.status === 200 && r.data.items.some(w => w.id === w1 && !w.signatureData), r);
  r = await api('POST', `/api/checks/${w1}/mark`, { token: medT, body: { ok: true } });
  check('медик допускает → ещё pending', r.status === 200 && r.data.status === 'pending', r);
  r = await api('POST', `/api/checks/${w1}/mark`, { token: medT, body: { ok: true } });
  check('повторная отметка медика → 409', r.status === 409, r);
  r = await api('POST', `/api/checks/${w1}/mark`, { token: mechT, body: { ok: true } });
  check('мастер допускает → active', r.status === 200 && r.data.status === 'active', r);

  r = await api('GET', '/api/driver/waybills/current', { token: drvT });
  const w = r.data.waybill || {};
  check('водитель получает выпущенный лист', w.id === w1 && w.status === 'active', r);
  check('в листе: медик, сертификат, время отметок', w.medName === 'Медик Тест' && w.medCertSerial === 'aabb11' && w.medExpires === '15.11.2027' && /^\d\d:\d\d:\d\d$/.test(w.medTime) && w.techName === 'Мастер Тест' && !!w.techTime, w);
  check('смена 12 часов', Math.abs(w.expiresAt - w.techConfirmedAt - 12 * 3600 * 1000) < 2000 && !!w.shiftStart && !!w.shiftEnd, w);
  check('подпись водителя сохранена', w.signatureData === SIG);
  r = await api('GET', '/api/public/waybills/' + w1);
  check('по QR выпущенный лист виден полностью', r.status === 200 && r.data.medName === 'Медик Тест' && r.data.status === 'active', r);
  r = await api('POST', `/api/driver/waybills/${w1}/close`, { token: drvT });
  check('водитель закрывает смену', r.status === 200 && r.data.status === 'closed', r);

  console.log('\n— Отказ и отмена');
  r = await api('POST', '/api/driver/waybills', { token: drvT, body: { odometer: '152500' } });
  const w2 = r.data.id;
  r = await api('POST', `/api/checks/${w2}/mark`, { token: mechT, body: { ok: false, reason: 'Не горит фара' } });
  check('мастер не допускает → rejected', r.status === 200 && r.data.status === 'rejected', r);
  r = await api('POST', `/api/checks/${w2}/mark`, { token: medT, body: { ok: true } });
  check('после отказа отметка медика → 409', r.status === 409, r);
  r = await api('GET', `/api/driver/waybills/${w2}`, { token: drvT });
  check('водитель видит причину отказа', r.data.rejectReason === 'Не горит фара', r);
  r = await api('POST', '/api/driver/waybills', { token: drvT, body: { odometer: '152600' } });
  const w3 = r.data.id;
  r = await api('POST', `/api/driver/waybills/${w3}/cancel`, { token: drvT });
  check('водитель отменяет запрос', r.status === 200 && r.data.status === 'cancelled', r);

  console.log('\n— Одновременные отметки');
  r = await api('POST', '/api/driver/waybills', { token: drvT, body: { odometer: '152700' } });
  const w4 = r.data.id;
  const [a, b] = await Promise.all([
    api('POST', `/api/checks/${w4}/mark`, { token: medT, body: { ok: true } }),
    api('POST', `/api/checks/${w4}/mark`, { token: mechT, body: { ok: true } }),
  ]);
  r = await api('GET', `/api/driver/waybills/${w4}`, { token: drvT });
  check('обе отметки сохранились, лист выпущен', a.status === 200 && b.status === 200 && r.data.status === 'active' && r.data.medStatus === 'ok' && r.data.techStatus === 'ok', { a: a.data, b: b.data, w: r.data.status });

  console.log('\n— Админка');
  r = await api('GET', '/api/admin/dashboard', { token: adminT });
  check('статистика', r.status === 200 && r.data.drivers === 1 && r.data.waybills === 2, r);
  r = await api('GET', '/api/admin/waybills', { token: adminT });
  check('список листов без подписей', r.status === 200 && r.data.items.length === 4 && r.data.items.every(x => !x.signatureData), r.data && r.data.items && r.data.items.length);
  r = await api('PUT', `/api/admin/drivers/${driverId}`, { token: adminT, body: { carModel: 'Kia K5', fullName: 'Водитель Тестов' } });
  check('редактирование водителя', r.status === 200 && r.data.carModel === 'Kia K5' && r.data.fullName === 'Водитель Тестов' && r.data.orgName === 'ООО Тест', r);
  r = await api('PUT', '/api/admin/settings', { token: adminT, body: { orgName: 'ООО Пример', inn: '7700000000' } });
  check('настройки сохраняются', r.status === 200 && r.data.orgName === 'ООО Пример', r);
  check('водитель читает настройки', (await api('GET', '/api/settings', { token: drvT })).data.orgName === 'ООО Пример');
  r = await api('PUT', '/api/admin/payments', { token: adminT, body: { driverId, period: '2026-11', paid: true } });
  r = await api('GET', '/api/admin/payments?period=2026-11', { token: adminT });
  check('оплата отмечена', r.status === 200 && r.data.items[0] && r.data.items[0].paid === true && r.data.items[0].amount === 3000, r);
  r = await api('POST', `/api/admin/drivers/${driverId}/notes`, { token: adminT, body: { text: 'Позвонить' } });
  check('CRM-заметка', r.status === 200 && r.data.items[0].text === 'Позвонить', r);

  console.log('\n— Техподдержка');
  await api('POST', '/api/driver/support', { token: drvT, body: { text: 'Здравствуйте' } });
  r = await api('GET', '/api/admin/support', { token: adminT });
  check('админ видит диалог и непрочитанное', r.data.items[0] && r.data.items[0].unreadForAdmin === 1 && r.data.items[0].driverName === 'Водитель Тестов', r);
  r = await api('GET', `/api/admin/support/${driverId}`, { token: adminT });
  check('админ читает сообщения', r.data.messages.length === 1 && r.data.messages[0].sender === 'driver', r);
  await api('POST', `/api/admin/support/${driverId}`, { token: adminT, body: { text: 'Добрый день' } });
  r = await api('GET', '/api/driver/support?after=1', { token: drvT });
  check('водитель получает ответ (только новые)', r.data.messages.length === 1 && r.data.messages[0].text === 'Добрый день' && r.data.unread === 1, r);

  console.log('\n— Запросы приложения водителя');
  r = await api('POST', '/api/admin/drivers', { token: adminT, body: { fullName: 'Водитель Второй', phone: '89995556677', carModel: 'Lada Vesta', plateNumber: 'В002ВВ77' } });
  const d2 = r.data && r.data.driver && r.data.driver.id;
  const d2Pass = r.data && r.data.password;
  const d2T = await login('9995556677', d2Pass, 'driver');
  check('вход по 10 цифрам номера', !!d2T);
  r = await api('GET', '/api/me', { token: d2T });
  check('/api/me: роль водителя и профиль', r.status === 200 && r.data.user.role === 'driver' && r.data.driver.id === d2 && r.data.driver.phone === '+79995556677' && r.data.driver.active === true && r.data.driver.carModel === 'Lada Vesta', r);
  r = await api('POST', '/api/driver/waybills', { token: d2T, body: { odometer: 1000, signatureData: SIG } });
  const wApp = r.data.id;
  check('запрос допуска: время числом (мс)', r.status === 200 && typeof r.data.createdAt === 'number' && r.data.expiresAt === null, r);
  r = await api('GET', `/api/driver/waybills/${wApp}`, { token: d2T });
  check('опрос своего листа по id', r.status === 200 && r.data.status === 'pending' && r.data.signatureData === SIG, r);
  check('чужой лист не виден → 404', (await api('GET', `/api/driver/waybills/${w1}`, { token: d2T })).status === 404);
  await api('POST', `/api/checks/${wApp}/mark`, { token: mechT, body: { ok: false, reason: 'Шины' } });
  r = await api('POST', `/api/driver/waybills/${wApp}/cancel`, { token: d2T });
  check('отмена после решения → 409 wrong-status', r.status === 409 && r.data.error === 'wrong-status', r);
  r = await api('GET', '/api/driver/waybills/current', { token: d2T });
  check('после отказа текущего листа нет', r.status === 200 && r.data.waybill === null, r);
  r = await api('GET', '/api/driver/stats', { token: d2T });
  check('отказ не считается выпущенным', r.status === 200 && r.data.issued === 0, r);
  await api('POST', '/api/driver/support', { token: d2T, body: { text: 'Вопрос' } });
  r = await api('GET', '/api/driver/support?after=0', { token: d2T });
  check('водитель видит своё сообщение', r.status === 200 && r.data.messages.length === 1 && typeof r.data.messages[0].createdAt === 'number', r);
  check('отметка «прочитано»', (await api('POST', '/api/driver/support/read', { token: d2T })).status === 200);
  r = await api('POST', '/api/driver/delete-account', { token: d2T, body: { password: 'wrong1' } });
  check('удаление с неверным паролем → 401 invalid-credentials', r.status === 401 && r.data.error === 'invalid-credentials', r);
  check('после неверного пароля сессия жива', (await api('GET', '/api/me', { token: d2T })).status === 200);
  r = await api('POST', '/api/driver/delete-account', { token: d2T, body: { password: d2Pass } });
  check('водитель удаляет аккаунт', r.status === 200, r);
  r = await api('GET', '/api/me', { token: d2T });
  check('после удаления сессия → 401 unauthorized', r.status === 401 && r.data.error === 'unauthorized', r);
  check('после удаления вход закрыт', !(await login('+79995556677', d2Pass, 'driver')));
  r = await api('GET', '/api/admin/deletion-requests', { token: adminT });
  check('заявка на удаление у админа', r.status === 200 && r.data.items.some(x => x.userId === d2), r);
  check('админ удаляет водителя', (await api('DELETE', `/api/admin/drivers/${d2}`, { token: adminT })).status === 200);
  r = await api('GET', '/api/admin/support', { token: adminT });
  check('переписка удалённого водителя удалена', r.status === 200 && !r.data.items.some(c => c.driverId === d2), r);

  console.log('\n— Пароли, блокировка, подбор');
  r = await api('POST', `/api/admin/users/${driverId}/password`, { token: adminT, body: { password: 'newpass1' } });
  check('смена пароля водителю', r.status === 200);
  check('старая сессия водителя сброшена', (await api('GET', '/api/me', { token: drvT })).status === 401);
  const drvT2 = await login('+79991112233', 'newpass1', 'driver');
  check('вход с новым паролем', !!drvT2);
  r = await api('POST', `/api/admin/drivers/${driverId}/active`, { token: adminT, body: { active: false } });
  check('админ отключает водителя', r.status === 200 && r.data.active === false, r);
  check('отключённый водитель выкинут', (await api('GET', '/api/me', { token: drvT2 })).status === 401);
  r = await api('POST', '/api/auth/login', { body: { phone: '+79991112233', password: 'newpass1', scope: 'driver' } });
  check('отключённый водитель не входит → 403', r.status === 403 && r.data.error === 'blocked', r);
  let last;
  for (let i = 0; i < 11; i++) last = await api('POST', '/api/auth/login', { body: { phone: '+79990000002', password: 'bad' + i, scope: 'staff' } });
  check('подбор пароля упирается в лимит → 429', last.status === 429, last);

  console.log(`\nИтого: ${passed} ✓, ${failed} ✗`);
  process.exit(failed ? 1 : 0);
})().catch(e => { console.error(e); process.exit(1); });
