// Drivers Management Module
// - Phone+Password (через Email Auth с синтетическим email)
// - Per-driver Organization
// - Создание Firebase Auth user через secondary app, чтобы не разлогинить админа
const Drivers = {
    drivers: [],
    _secondaryApp: null,
    _editingId: null,
    _unsub: null,

    // Соответствие «id поля формы» → «ключ в Firestore». Используется и для заполнения,
    // и для сохранения при редактировании.
    _fieldMap: {
        'driver-fullname': 'fullName',
        'driver-phone': 'phone',
        'driver-snils': 'snils',
        'driver-inn': 'inn',
        'driver-org-name': 'orgName',
        'driver-org-ogrn': 'orgOgrn',
        'driver-org-inn': 'orgInn',
        'driver-org-phone': 'orgPhone',
        'driver-org-address': 'orgAddress',
        'driver-car': 'carModel',
        'driver-plate': 'plateNumber',
        'driver-garage': 'garageNumber',
        'driver-tab': 'tabNumber',
        'driver-license': 'license',
        'driver-class': 'licenseClass',
        'driver-license-issued': 'licenseIssued',
        'driver-license-expires': 'licenseExpires',
        'driver-id-number': 'driverIdNumber',
        'driver-osgop': 'osgop',
        'driver-transport-type': 'transportType',
        'driver-comm-type': 'commType',
        'driver-okud': 'okud',
        'driver-okpo': 'okpo',
        'driver-permit': 'permit',
        'driver-mintrans': 'mintrans',
        'driver-monthly-price': 'monthlyPrice',
        'driver-crm-status': 'crmStatus',
    },

    // Подписи и цвета CRM-статусов водителя.
    CRM_STATUSES: {
        active: { label: 'Активен',     cls: 'status-active' },
        lead:   { label: 'Лид',         cls: 'status-open' },
        paused: { label: 'На паузе',    cls: 'status-inactive' },
        debtor: { label: 'Должник',     cls: 'status-debtor' },
    },

    init() {
        document.getElementById('add-driver-form').addEventListener('submit', (e) => {
            e.preventDefault();
            if (Drivers._editingId) {
                Drivers.updateDriver(Drivers._editingId);
            } else {
                Drivers.addDriver();
            }
        });
        // Автозаполнение организации из настроек по умолчанию
        Drivers._prefillOrgFromSettings();
    },

    // Переводит форму в режим создания нового водителя.
    _resetFormToCreate() {
        Drivers._editingId = null;
        const form = document.getElementById('add-driver-form');
        if (form) form.reset();
        const setText = (id, text) => { const el = document.getElementById(id); if (el) el.textContent = text; };
        const setVal = (id, v) => { const el = document.getElementById(id); if (el) el.value = v; };
        setVal('driver-okud', '0345001');
        setVal('driver-mintrans', '390 ОТ 28.09.2022');
        setText('add-driver-title', 'Регистрация водителя');
        setText('add-driver-subtitle', 'Заполните данные нового водителя. Поля «Организация» подставляются из настроек.');
        setText('add-driver-submit-text', 'Зарегистрировать водителя');
        const pg = document.getElementById('driver-password-group');
        if (pg) pg.style.display = '';
        const ph = document.getElementById('driver-phone');
        if (ph) ph.readOnly = false;
    },

    // Открыть форму для создания нового водителя.
    newDriver() {
        Drivers._resetFormToCreate();
        Drivers._prefillOrgFromSettings();
        showSection('add-driver');
    },

    // Открыть форму в режиме редактирования данных водителя.
    editDriver(driverId) {
        const driver = Drivers.drivers.find(d => d.id === driverId);
        if (!driver) { showToast('Водитель не найден', 'error'); return; }
        Drivers._editingId = driverId;
        const setText = (id, text) => { const el = document.getElementById(id); if (el) el.textContent = text; };
        setText('add-driver-title', 'Редактирование водителя');
        setText('add-driver-subtitle', 'Измените данные водителя. Телефон (логин) и пароль меняются отдельно.');
        setText('add-driver-submit-text', 'Сохранить изменения');
        const pg = document.getElementById('driver-password-group');
        if (pg) pg.style.display = 'none';
        for (const [elId, key] of Object.entries(Drivers._fieldMap)) {
            const el = document.getElementById(elId);
            if (el) el.value = driver[key] != null ? driver[key] : '';
        }
        // Телефон привязан к логину (Firebase Auth) — в этой форме не редактируем.
        const ph = document.getElementById('driver-phone');
        if (ph) ph.readOnly = true;
        showSection('add-driver');
    },

    // Сохранить изменённые данные водителя (без изменения телефона/пароля).
    async updateDriver(driverId) {
        const btn = document.querySelector('#add-driver-form button[type="submit"]');
        const orig = btn.innerHTML;
        btn.disabled = true;
        btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Сохранение...';
        try {
            const update = {};
            for (const [elId, key] of Object.entries(Drivers._fieldMap)) {
                if (key === 'phone') continue; // телефон не меняем
                const el = document.getElementById(elId);
                if (!el) continue;
                let v = el.value;
                if (typeof v === 'string') v = v.trim();
                update[key] = v;
            }
            update.okud = update.okud || '0345001';
            update.mintrans = update.mintrans || '390 ОТ 28.09.2022';
            update.monthlyPrice = parseFloat(update.monthlyPrice) || 0;
            update.crmStatus = update.crmStatus || 'active';
            update.updatedAt = firebase.firestore.FieldValue.serverTimestamp();
            update.updatedBy = Auth.currentUser.uid;
            await db.collection('drivers').doc(driverId).update(update);
            showToast('Данные водителя обновлены', 'success');
            Drivers._resetFormToCreate();
            Drivers.loadDrivers();
            showSection('drivers');
        } catch (e) {
            console.error('Update driver error:', e);
            showToast('Ошибка сохранения: ' + (e.message || e.code), 'error');
        } finally {
            btn.disabled = false;
            btn.innerHTML = orig;
        }
    },

    // Подставляет данные организации в форму "Новый водитель" из settings/company,
    // если поля пустые. Так админу не нужно каждый раз вбивать одну и ту же организацию.
    async _prefillOrgFromSettings() {
        try {
            const doc = await db.collection('settings').doc('company').get();
            if (!doc.exists) return;
            const data = doc.data() || {};
            const map = {
                'driver-org-name':    data.orgName,
                'driver-org-ogrn':    data.ogrn,
                'driver-org-inn':     data.inn,
                'driver-org-phone':   data.phone,
                'driver-org-address': data.address,
            };
            for (const [id, value] of Object.entries(map)) {
                const el = document.getElementById(id);
                if (el && !el.value && value) el.value = value;
            }
        } catch (e) {
            console.warn('Cannot prefill org from settings:', e);
        }
    },

    // Нормализуем номер телефона к формату "+79991234567"
    _normalizePhone(raw) {
        let phone = String(raw || '').replace(/[\s\(\)\-]/g, '');
        if (phone.startsWith('8') && phone.length === 11) phone = '+7' + phone.substring(1);
        if (!phone.startsWith('+')) phone = '+' + phone;
        return phone;
    },

    // Email для Firebase Auth: "+79991234567" -> "79991234567@asempro.driver"
    _phoneToEmail(phoneNormalized) {
        const digits = phoneNormalized.replace(/\D/g, '');
        return `${digits}@asempro.driver`;
    },

    // Дефолтный пароль = последние 6 цифр номера
    _defaultPassword(phoneNormalized) {
        const digits = phoneNormalized.replace(/\D/g, '');
        return digits.length >= 6 ? digits.slice(-6) : digits;
    },

    // Получаем secondary Firebase app (чтобы createUser не разлогинил админа)
    _getSecondaryAuth() {
        if (!Drivers._secondaryApp) {
            Drivers._secondaryApp = firebase.initializeApp(firebaseConfig, 'driver-creator');
        }
        return Drivers._secondaryApp.auth();
    },

    // HTML-escape для безопасной вставки в innerHTML
    _esc(value) {
        const s = value == null ? '' : String(value);
        return s
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    },

    // Живая подписка на коллекцию водителей: данные появляются мгновенно и
    // обновляются в реальном времени (без перезагрузки страницы и задержек).
    // Подписка ставится один раз; повторные вызовы (после добавления/удаления) — no-op.
    loadDrivers() {
        if (Drivers._unsub) return;
        Drivers._unsub = db.collection('drivers').orderBy('fullName')
            .onSnapshot(snapshot => {
                Drivers.drivers = [];
                snapshot.forEach(doc => {
                    Drivers.drivers.push({ id: doc.id, ...doc.data() });
                });
                Drivers.renderList();
                if (typeof updateDashboard === 'function') updateDashboard();
            }, error => {
                console.error('Drivers onSnapshot error:', error);
            });
    },

    // Отписка от realtime (при выходе из аккаунта).
    stopRealtime() {
        if (Drivers._unsub) { Drivers._unsub(); Drivers._unsub = null; }
    },

    // Нормализация строки для поиска: нижний регистр, ё→е, схлопывание пробелов
    _norm(value) {
        return (value == null ? '' : String(value))
            .toLowerCase()
            .replace(/ё/g, 'е')
            .replace(/\s+/g, ' ')
            .trim();
    },

    // Умный поиск: каждое слово запроса должно найтись в любом из полей.
    // Телефон/гос. номер сравниваются также без пробелов и спецсимволов.
    _matches(driver, query) {
        const q = Drivers._norm(query);
        if (!q) return true;
        const fields = [
            driver.fullName, driver.phone, driver.carModel,
            driver.plateNumber, driver.orgName, driver.driverIdNumber,
        ];
        const hay = Drivers._norm(fields.join(' '));
        const haySquished = hay.replace(/[\s+()\-.]/g, '');
        return q.split(' ').every(token => {
            const t = token.replace(/[\s+()\-.]/g, '');
            return hay.includes(token) || (t && haySquished.includes(t));
        });
    },

    filterDrivers(query) {
        Drivers._searchQuery = query || '';
        Drivers.renderList();
    },

    renderList() {
        const tbody = document.getElementById('drivers-tbody');
        if (!tbody) return;
        const query = Drivers._searchQuery || '';
        const list = Drivers.drivers.filter(d => Drivers._matches(d, query));

        tbody.innerHTML = '';
        if (Drivers.drivers.length === 0) {
            tbody.innerHTML = '<tr><td colspan="7" style="text-align:center;color:var(--text-light);padding:32px;">Нет зарегистрированных водителей</td></tr>';
        } else if (list.length === 0) {
            tbody.innerHTML = `<tr><td colspan="7" style="text-align:center;color:var(--text-light);padding:32px;">Ничего не найдено по запросу «${Drivers._esc(query)}»</td></tr>`;
        } else {
            list.forEach(driver => {
                tbody.insertAdjacentHTML('beforeend', Drivers.renderRow(driver));
            });
        }

        const countEl = document.getElementById('drivers-search-count');
        if (countEl) {
            countEl.textContent = query
                ? `Найдено: ${list.length} из ${Drivers.drivers.length}`
                : `Всего: ${Drivers.drivers.length}`;
        }
        const clearEl = document.getElementById('drivers-search-clear');
        if (clearEl) clearEl.style.display = query ? 'flex' : 'none';
    },

    _crmBadge(driver) {
        const st = Drivers.CRM_STATUSES[driver.crmStatus] || Drivers.CRM_STATUSES.active;
        return `<span class="status-badge ${st.cls}">${st.label}</span>`;
    },

    renderRow(driver) {
        const e = Drivers._esc;
        const status = driver.active !== false ?
            '<span class="status-badge status-active">Активен</span>' :
            '<span class="status-badge status-inactive">Неактивен</span>';
        const price = (typeof driver.monthlyPrice === 'number' ? driver.monthlyPrice : parseFloat(driver.monthlyPrice) || 0);
        const priceStr = price ? price.toLocaleString('ru-RU') + ' ₽/мес' : '';

        const id = e(driver.id);
        return `
            <tr>
                <td data-label="Водитель"><strong>${e(driver.fullName)}</strong>${priceStr ? `<div style="font-size:11px;color:var(--text-light);margin-top:2px;">${priceStr}</div>` : ''}</td>
                <td data-label="Телефон">${e(driver.phone)}</td>
                <td data-label="Авто">${e(driver.carModel)}</td>
                <td data-label="Гос. номер">${e(driver.plateNumber)}</td>
                <td data-label="Организация">${e(driver.orgName) || '—'}</td>
                <td data-label="Статус">${status}<div style="margin-top:4px;">${Drivers._crmBadge(driver)}</div></td>
                <td data-label="Действия">
                    <button class="btn btn-sm btn-outline" onclick="Drivers.openCrm('${id}')" title="CRM: статус и заметки">
                        <i class="fas fa-user-tag"></i>
                    </button>
                    <button class="btn btn-sm btn-outline" onclick="Drivers.editDriver('${id}')" title="Редактировать">
                        <i class="fas fa-pen"></i>
                    </button>
                    <button class="btn btn-sm btn-outline" onclick="Drivers.resetPassword('${id}')" title="Сбросить пароль">
                        <i class="fas fa-key"></i>
                    </button>
                    <button class="btn btn-sm btn-primary" onclick="Drivers.toggleStatus('${id}', ${driver.active !== false})">
                        <i class="fas fa-power-off"></i> ${driver.active !== false ? 'Деактив.' : 'Активир.'}
                    </button>
                    <button class="btn btn-sm btn-danger" onclick="Drivers.deleteDriver('${id}')">
                        <i class="fas fa-trash"></i>
                    </button>
                </td>
            </tr>
        `;
    },

    // ===== CRM: модалка со статусом и заметками по водителю =====
    _crmUnsub: null,

    openCrm(driverId) {
        const driver = Drivers.drivers.find(d => d.id === driverId);
        if (!driver) { showToast('Водитель не найден', 'error'); return; }
        const e = Drivers._esc;

        const statusOptions = Object.entries(Drivers.CRM_STATUSES).map(([key, v]) =>
            `<option value="${key}" ${ (driver.crmStatus || 'active') === key ? 'selected' : ''}>${v.label}</option>`
        ).join('');

        const overlay = document.createElement('div');
        overlay.className = 'crm-modal-overlay';
        overlay.id = 'crm-modal-overlay';
        overlay.innerHTML = `
            <div class="crm-modal">
                <div class="crm-modal-header">
                    <div>
                        <h3>${e(driver.fullName)}</h3>
                        <p>${e(driver.phone) || ''}</p>
                    </div>
                    <button class="crm-modal-close" onclick="Drivers.closeCrm()"><i class="fas fa-times"></i></button>
                </div>
                <div class="crm-modal-body">
                    <label class="crm-label">Статус (CRM)</label>
                    <div class="crm-status-row">
                        <select id="crm-status-select">${statusOptions}</select>
                        <button class="btn btn-sm btn-primary" onclick="Drivers.saveCrmStatus('${e(driverId)}')">Сохранить</button>
                    </div>

                    <label class="crm-label" style="margin-top:18px;">Заметки</label>
                    <div class="crm-notes" id="crm-notes"><div style="color:var(--text-light);padding:8px;">Загрузка…</div></div>
                    <form class="crm-note-add" id="crm-note-form" autocomplete="off">
                        <input type="text" id="crm-note-input" placeholder="Добавить заметку…" autocomplete="off">
                        <button type="submit" class="btn btn-primary btn-sm"><i class="fas fa-plus"></i></button>
                    </form>
                </div>
            </div>`;
        document.body.appendChild(overlay);
        overlay.addEventListener('click', (ev) => { if (ev.target === overlay) Drivers.closeCrm(); });

        document.getElementById('crm-note-form').addEventListener('submit', (ev) => {
            ev.preventDefault();
            Drivers.addNote(driverId);
        });

        // Realtime-подписка на заметки.
        Drivers._crmUnsub = db.collection('drivers').doc(driverId)
            .collection('notes').orderBy('createdAt', 'desc')
            .onSnapshot(snap => {
                const box = document.getElementById('crm-notes');
                if (!box) return;
                if (snap.empty) { box.innerHTML = '<div style="color:var(--text-light);padding:8px;">Заметок пока нет</div>'; return; }
                box.innerHTML = snap.docs.map(d => {
                    const n = d.data() || {};
                    const t = n.createdAt && n.createdAt.seconds
                        ? new Date(n.createdAt.seconds * 1000).toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit' })
                        : '';
                    return `<div class="crm-note"><div class="crm-note-text">${e(n.text)}</div><div class="crm-note-time">${t}</div></div>`;
                }).join('');
            }, err => console.error('CRM notes onSnapshot error:', err));
    },

    closeCrm() {
        if (Drivers._crmUnsub) { Drivers._crmUnsub(); Drivers._crmUnsub = null; }
        const ov = document.getElementById('crm-modal-overlay');
        if (ov) ov.remove();
    },

    async saveCrmStatus(driverId) {
        const sel = document.getElementById('crm-status-select');
        if (!sel) return;
        try {
            await db.collection('drivers').doc(driverId).update({
                crmStatus: sel.value,
                updatedAt: firebase.firestore.FieldValue.serverTimestamp()
            });
            showToast('Статус обновлён', 'success');
        } catch (e) {
            console.error('Save CRM status error:', e);
            showToast('Ошибка: ' + (e.message || e.code), 'error');
        }
    },

    async addNote(driverId) {
        const input = document.getElementById('crm-note-input');
        const text = (input.value || '').trim();
        if (!text) return;
        input.value = '';
        try {
            await db.collection('drivers').doc(driverId).collection('notes').add({
                text,
                createdAt: firebase.firestore.FieldValue.serverTimestamp(),
                createdBy: Auth.currentUser ? Auth.currentUser.uid : null
            });
        } catch (e) {
            console.error('Add note error:', e);
            showToast('Ошибка добавления заметки: ' + (e.message || e.code), 'error');
            input.value = text;
        }
    },

    async addDriver() {
        const fullName = document.getElementById('driver-fullname').value.trim();
        const phoneRaw = document.getElementById('driver-phone').value.trim();
        const passwordRaw = document.getElementById('driver-password').value.trim();
        const carModel = document.getElementById('driver-car').value.trim();
        const plateNumber = document.getElementById('driver-plate').value.trim();
        const license = document.getElementById('driver-license').value.trim();
        const licenseClass = document.getElementById('driver-class').value.trim();
        const licenseIssued = document.getElementById('driver-license-issued').value;
        const licenseExpires = document.getElementById('driver-license-expires').value;
        const driverIdNumber = document.getElementById('driver-id-number').value.trim();
        const osgop = document.getElementById('driver-osgop').value.trim();
        const garageNumber = document.getElementById('driver-garage').value.trim();
        const tabNumber = document.getElementById('driver-tab').value.trim();
        const snils = document.getElementById('driver-snils').value.trim();
        const inn = document.getElementById('driver-inn').value.trim();
        const transportType = document.getElementById('driver-transport-type').value;
        const commType = document.getElementById('driver-comm-type').value;
        const orgName = document.getElementById('driver-org-name').value.trim();
        const orgOgrn = document.getElementById('driver-org-ogrn').value.trim();
        const orgInn = document.getElementById('driver-org-inn').value.trim();
        const orgPhone = document.getElementById('driver-org-phone').value.trim();
        const orgAddress = document.getElementById('driver-org-address').value.trim();
        const okud = document.getElementById('driver-okud').value.trim();
        const okpo = document.getElementById('driver-okpo').value.trim();
        const permit = document.getElementById('driver-permit').value.trim();
        const mintrans = document.getElementById('driver-mintrans').value.trim();
        const monthlyPrice = parseFloat(document.getElementById('driver-monthly-price').value) || 0;
        const crmStatus = document.getElementById('driver-crm-status').value || 'active';

        const phone = Drivers._normalizePhone(phoneRaw);
        const password = passwordRaw || Drivers._defaultPassword(phone);

        if (password.length < 6) {
            showToast('Пароль должен быть не короче 6 символов', 'error');
            return;
        }
        if (phone.replace(/\D/g, '').length < 10) {
            showToast('Некорректный номер телефона', 'error');
            return;
        }

        const btn = document.querySelector('#add-driver-form button[type="submit"]');
        const originalContent = btn.innerHTML;
        btn.disabled = true;
        btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Регистрация...';

        const email = Drivers._phoneToEmail(phone);
        const secondaryAuth = Drivers._getSecondaryAuth();

        let createdAuthUid = null;
        try {
            // 1. Создаём Firebase Auth аккаунт через secondary app (админ остаётся залогинен)
            const userCred = await secondaryAuth.createUserWithEmailAndPassword(email, password);
            createdAuthUid = userCred.user.uid;
            await secondaryAuth.signOut();

            // 2. Сохраняем профиль водителя в Firestore с тем же uid (для лёгкого lookup)
            await db.collection('drivers').doc(createdAuthUid).set({
                authUid: createdAuthUid,
                fullName,
                phone,
                authEmail: email,
                carModel,
                plateNumber,
                license,
                licenseClass,
                licenseIssued,
                licenseExpires,
                driverIdNumber,
                osgop,
                garageNumber,
                tabNumber,
                snils,
                inn,
                transportType,
                commType,
                orgName,
                orgOgrn,
                orgInn,
                orgPhone,
                orgAddress,
                okud: okud || '0345001',
                okpo,
                permit,
                mintrans: mintrans || '390 ОТ 28.09.2022',
                monthlyPrice,
                crmStatus,
                active: true,
                createdAt: firebase.firestore.FieldValue.serverTimestamp(),
                createdBy: Auth.currentUser.uid
            });

            showToast(`Водитель зарегистрирован. Пароль: ${password}`, 'success');
            document.getElementById('add-driver-form').reset();
            document.getElementById('driver-okud').value = '0345001';
            document.getElementById('driver-mintrans').value = '390 ОТ 28.09.2022';
            Drivers.loadDrivers();
            showSection('drivers');
        } catch (error) {
            console.error('Error adding driver:', error);
            // Откат: если Auth аккаунт создался, но Firestore-запись упала — пытаемся удалить аккаунт
            if (createdAuthUid) {
                try {
                    await secondaryAuth.signInWithEmailAndPassword(email, password);
                    await secondaryAuth.currentUser.delete();
                } catch (cleanupError) {
                    console.error('Auth cleanup failed:', cleanupError);
                }
            }
            let msg = 'Ошибка регистрации: ' + (error.message || error.code);
            if (error.code === 'auth/email-already-in-use') {
                msg = 'Водитель с таким номером телефона уже зарегистрирован';
            } else if (error.code === 'auth/weak-password') {
                msg = 'Слишком слабый пароль (минимум 6 символов)';
            } else if (error.code === 'auth/operation-not-allowed') {
                msg = 'В Firebase Console не включён Email/Password Authentication';
            }
            showToast(msg, 'error');
        } finally {
            btn.disabled = false;
            btn.innerHTML = originalContent;
        }
    },

    async resetPassword(driverId) {
        const driver = Drivers.drivers.find(d => d.id === driverId);
        if (!driver) return;
        const newPwd = prompt(`Новый пароль для ${driver.fullName} (минимум 6 символов).\nОставьте пустым для использования последних 6 цифр номера:`);
        if (newPwd === null) return; // Отмена
        const phone = Drivers._normalizePhone(driver.phone);
        const password = newPwd.trim() || Drivers._defaultPassword(phone);
        if (password.length < 6) {
            showToast('Пароль должен быть не короче 6 символов', 'error');
            return;
        }
        // 1) Основной путь: бесплатный Cloudflare Worker реально меняет пароль в Firebase Auth.
        //    driverId = Auth UID водителя (документ создаётся с этим id).
        if (typeof AUTH_WORKER_URL === 'string' && AUTH_WORKER_URL) {
            try {
                const idToken = await auth.currentUser.getIdToken();
                const res = await fetch(AUTH_WORKER_URL.replace(/\/+$/, '') + '/reset-password', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ idToken, driverUid: driver.id, newPassword: password }),
                });
                const data = await res.json().catch(() => ({}));
                if (res.ok && data.ok) {
                    showToast(`Пароль изменён. Сообщите водителю: ${password}`, 'success');
                    return;
                }
                showToast('Ошибка смены пароля: ' + (data.error || res.status), 'error');
                return;
            } catch (e) {
                console.error('worker reset-password failed:', e);
                // Сеть/воркер недоступны — переходим к запасному варианту ниже.
            }
        }

        // 2) Запасной путь (если сервер смены пароля ещё не подключён):
        //    создаём заявку без открытого пароля; пароль показываем один раз в UI.
        try {
            await db.collection('passwordResets').add({
                driverId: driver.id,
                authEmail: driver.authEmail || Drivers._phoneToEmail(phone),
                phone: phone,
                requestedBy: Auth.currentUser.uid,
                requestedAt: firebase.firestore.FieldValue.serverTimestamp(),
                status: 'pending'
            });
            showToast(
                `Сервер смены пароля не подключён. Новый пароль (${password}) задайте вручную ` +
                `в Firebase Console → Authentication, либо задеплойте Cloud Functions.`,
                'error'
            );
        } catch (e) {
            console.error('Reset password fallback error:', e);
            showToast('Ошибка: ' + e.message, 'error');
        }
    },

    async toggleStatus(driverId, currentStatus) {
        try {
            await db.collection('drivers').doc(driverId).update({
                active: !currentStatus
            });
            Drivers.loadDrivers();
            showToast('Статус обновлён', 'success');
        } catch (error) {
            showToast('Ошибка обновления статуса', 'error');
        }
    },

    async deleteDriver(driverId) {
        if (!confirm('Удалить водителя? Это действие нельзя отменить.')) return;

        // Основной путь: Worker удаляет и Auth-аккаунт, и документ Firestore.
        if (typeof AUTH_WORKER_URL === 'string' && AUTH_WORKER_URL) {
            try {
                const idToken = await auth.currentUser.getIdToken();
                const res = await fetch(AUTH_WORKER_URL.replace(/\/+$/, '') + '/delete-driver', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ idToken, driverUid: driverId }),
                });
                const data = await res.json().catch(() => ({}));
                if (res.ok && data.ok) {
                    Drivers.loadDrivers();
                    showToast('Водитель удалён (вместе с аккаунтом входа)', 'success');
                    return;
                }
            } catch (e) {
                console.error('worker delete-driver failed:', e);
            }
        }

        // Запасной путь: помечаем для удаления и убираем документ водителя.
        try {
            await db.collection('driverDeletions').add({
                driverId,
                authUid: driverId,
                requestedBy: Auth.currentUser.uid,
                requestedAt: firebase.firestore.FieldValue.serverTimestamp()
            });
            await db.collection('drivers').doc(driverId).delete();
            Drivers.loadDrivers();
            showToast('Водитель удалён', 'success');
        } catch (error) {
            showToast('Ошибка удаления: ' + error.message, 'error');
        }
    }
};
