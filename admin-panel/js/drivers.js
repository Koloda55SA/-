// Водители: список, регистрация, редактирование, пароль, статус, CRM-заметки.
const Drivers = {
    drivers: [],
    _editingId: null,
    _loaded: false,

    // Соответствие «id поля формы» → «ключ профиля».
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

    CRM_STATUSES: {
        active: { label: 'Активен',     cls: 'status-active' },
        lead:   { label: 'Лид',         cls: 'status-open' },
        paused: { label: 'На паузе',    cls: 'status-inactive' },
        debtor: { label: 'Должник',     cls: 'status-debtor' },
    },

    _esc: escHtml,

    init() {
        document.getElementById('add-driver-form').addEventListener('submit', (e) => {
            e.preventDefault();
            if (Drivers._editingId) Drivers.updateDriver(Drivers._editingId);
            else Drivers.addDriver();
        });
    },

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

    newDriver() {
        Drivers._resetFormToCreate();
        showSection('add-driver');
    },

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
        const ph = document.getElementById('driver-phone');
        if (ph) ph.readOnly = true;
        showSection('add-driver');
    },

    // Собирает данные формы в объект профиля.
    _formData() {
        const data = {};
        for (const [elId, key] of Object.entries(Drivers._fieldMap)) {
            const el = document.getElementById(elId);
            if (!el) continue;
            data[key] = typeof el.value === 'string' ? el.value.trim() : el.value;
        }
        data.okud = data.okud || '0345001';
        data.mintrans = data.mintrans || '390 ОТ 28.09.2022';
        data.monthlyPrice = parseFloat(data.monthlyPrice) || 0;
        data.crmStatus = data.crmStatus || 'active';
        return data;
    },

    async updateDriver(driverId) {
        const btn = document.querySelector('#add-driver-form button[type="submit"]');
        const orig = btn.innerHTML;
        btn.disabled = true;
        btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Сохранение...';
        try {
            const data = Drivers._formData();
            delete data.phone; // телефон = логин, не меняем
            await Api.put('/api/admin/drivers/' + encodeURIComponent(driverId), data);
            showToast('Данные водителя обновлены', 'success');
            Drivers._resetFormToCreate();
            await Drivers.loadDrivers();
            showSection('drivers');
        } catch (e) {
            showToast('Ошибка сохранения: ' + e.message, 'error');
        } finally {
            btn.disabled = false;
            btn.innerHTML = orig;
        }
    },

    // Подставляет организацию по умолчанию из настроек в пустые поля формы.
    async _prefillOrgFromSettings() {
        try {
            const data = await Api.get('/api/admin/settings');
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
            console.warn('Cannot prefill org from settings:', e.message);
        }
    },

    _normalizePhone(raw) {
        return Auth._formatPhone(raw);
    },

    async loadDrivers() {
        try {
            const r = await Api.get('/api/admin/drivers');
            Drivers.drivers = r.items || [];
            Drivers._loaded = true;
            Drivers.renderList();
            if (typeof Accounting !== 'undefined') Accounting.render();
            if (typeof updateDashboard === 'function') updateDashboard();
        } catch (e) {
            console.error('Load drivers error:', e);
            const tbody = document.getElementById('drivers-tbody');
            if (tbody && !Drivers._loaded) {
                tbody.innerHTML = `<tr><td colspan="7" class="table-empty" style="color:var(--danger)">Ошибка загрузки: ${escHtml(e.message)}</td></tr>`;
            }
        }
    },

    stopRealtime() {
        Drivers.drivers = [];
        Drivers._loaded = false;
    },

    // Нормализация строки для поиска: нижний регистр, ё→е, схлопывание пробелов
    _norm(value) {
        return (value == null ? '' : String(value)).toLowerCase().replace(/ё/g, 'е').replace(/\s+/g, ' ').trim();
    },

    // Умный поиск: каждое слово запроса должно найтись в любом из полей.
    _matches(driver, query) {
        const q = Drivers._norm(query);
        if (!q) return true;
        const hay = Drivers._norm([
            driver.fullName, driver.phone, driver.carModel,
            driver.plateNumber, driver.orgName, driver.driverIdNumber,
        ].join(' '));
        const haySquished = hay.replace(/[\s+()\-.]/g, '');
        return q.split(' ').every(token => {
            const t = token.replace(/[\s+()\-.]/g, '');
            return hay.includes(token) || (t && haySquished.includes(t));
        });
    },

    _filterTimer: null,
    filterDrivers(query) {
        Drivers._searchQuery = query || '';
        clearTimeout(Drivers._filterTimer);
        Drivers._filterTimer = setTimeout(Drivers.renderList, 120);
    },

    renderList() {
        const tbody = document.getElementById('drivers-tbody');
        if (!tbody) return;
        const query = Drivers._searchQuery || '';
        const list = Drivers.drivers.filter(d => Drivers._matches(d, query));

        if (Drivers.drivers.length === 0) {
            tbody.innerHTML = '<tr><td colspan="7" class="table-empty">Нет зарегистрированных водителей</td></tr>';
        } else if (list.length === 0) {
            tbody.innerHTML = `<tr><td colspan="7" class="table-empty">Ничего не найдено по запросу «${escHtml(query)}»</td></tr>`;
        } else {
            tbody.innerHTML = list.map(Drivers.renderRow).join('');
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
        const e = escHtml;
        const status = driver.active !== false
            ? '<span class="status-badge status-active">Активен</span>'
            : '<span class="status-badge status-inactive">Неактивен</span>';
        const price = typeof driver.monthlyPrice === 'number' ? driver.monthlyPrice : parseFloat(driver.monthlyPrice) || 0;
        const priceStr = price ? price.toLocaleString('ru-RU') + ' ₽/мес' : '';
        const id = e(driver.id);
        return `
            <tr>
                <td data-label="Водитель"><strong>${e(driver.fullName)}</strong>${priceStr ? `<div class="check-meta">${priceStr}</div>` : ''}</td>
                <td data-label="Телефон">${e(driver.phone)}</td>
                <td data-label="Авто">${e(driver.carModel)}</td>
                <td data-label="Гос. номер">${e(driver.plateNumber)}</td>
                <td data-label="Организация">${e(driver.orgName) || '—'}</td>
                <td data-label="Статус">${status}<div style="margin-top:4px;">${Drivers._crmBadge(driver)}</div></td>
                <td data-label="Действия">
                    <button class="btn btn-sm btn-outline" onclick="Drivers.openCrm('${id}')" title="CRM: статус и заметки"><i class="fas fa-user-tag"></i></button>
                    <button class="btn btn-sm btn-outline" onclick="Drivers.editDriver('${id}')" title="Редактировать"><i class="fas fa-pen"></i></button>
                    <button class="btn btn-sm btn-outline" onclick="Drivers.resetPassword('${id}')" title="Сбросить пароль"><i class="fas fa-key"></i></button>
                    <button class="btn btn-sm btn-primary" onclick="Drivers.toggleStatus('${id}', ${driver.active !== false})">
                        <i class="fas fa-power-off"></i> ${driver.active !== false ? 'Деактив.' : 'Активир.'}
                    </button>
                    <button class="btn btn-sm btn-danger" onclick="Drivers.deleteDriver('${id}')"><i class="fas fa-trash"></i></button>
                </td>
            </tr>`;
    },

    // ===== CRM: статус и заметки по водителю =====
    openCrm(driverId) {
        const driver = Drivers.drivers.find(d => d.id === driverId);
        if (!driver) { showToast('Водитель не найден', 'error'); return; }
        const e = escHtml;
        const statusOptions = Object.entries(Drivers.CRM_STATUSES).map(([key, v]) =>
            `<option value="${key}" ${(driver.crmStatus || 'active') === key ? 'selected' : ''}>${v.label}</option>`
        ).join('');

        const overlay = document.createElement('div');
        overlay.className = 'crm-modal-overlay';
        overlay.id = 'crm-modal-overlay';
        overlay.innerHTML = `
            <div class="crm-modal">
                <div class="crm-modal-header">
                    <div>
                        <h3>${e(driver.fullName)}</h3>
                        <p>${e(driver.phone)}</p>
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
        Api.get(`/api/admin/drivers/${encodeURIComponent(driverId)}/notes`)
            .then(r => Drivers._renderNotes(r.items))
            .catch(err => Drivers._renderNotes(null, err));
    },

    _renderNotes(items, err) {
        const box = document.getElementById('crm-notes');
        if (!box) return;
        if (err) { box.innerHTML = `<div style="color:var(--danger);padding:8px;">${escHtml(err.message)}</div>`; return; }
        if (!items || !items.length) { box.innerHTML = '<div style="color:var(--text-light);padding:8px;">Заметок пока нет</div>'; return; }
        box.innerHTML = items.map(n => {
            const t = n.createdAt ? new Date(n.createdAt).toLocaleString('ru-RU', {
                day: '2-digit', month: '2-digit', year: '2-digit', hour: '2-digit', minute: '2-digit',
            }) : '';
            return `<div class="crm-note"><div class="crm-note-text">${escHtml(n.text)}</div><div class="crm-note-time">${t}</div></div>`;
        }).join('');
    },

    closeCrm() {
        const ov = document.getElementById('crm-modal-overlay');
        if (ov) ov.remove();
    },

    async saveCrmStatus(driverId) {
        const sel = document.getElementById('crm-status-select');
        if (!sel) return;
        try {
            await Api.put('/api/admin/drivers/' + encodeURIComponent(driverId), { crmStatus: sel.value });
            showToast('Статус обновлён', 'success');
            Drivers.loadDrivers();
        } catch (e) {
            showToast('Ошибка: ' + e.message, 'error');
        }
    },

    async addNote(driverId) {
        const input = document.getElementById('crm-note-input');
        const text = (input.value || '').trim();
        if (!text) return;
        input.value = '';
        try {
            const r = await Api.post(`/api/admin/drivers/${encodeURIComponent(driverId)}/notes`, { text });
            Drivers._renderNotes(r.items);
        } catch (e) {
            showToast('Ошибка добавления заметки: ' + e.message, 'error');
            input.value = text;
        }
    },

    async addDriver() {
        const data = Drivers._formData();
        const passwordRaw = document.getElementById('driver-password').value.trim();
        if (passwordRaw && passwordRaw.length < 6) {
            showToast('Пароль должен быть не короче 6 символов', 'error');
            return;
        }
        const btn = document.querySelector('#add-driver-form button[type="submit"]');
        const originalContent = btn.innerHTML;
        btn.disabled = true;
        btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Регистрация...';
        try {
            // Пароль пустой → сервер поставит последние 6 цифр номера.
            const r = await Api.post('/api/admin/drivers', { ...data, password: passwordRaw });
            showToast(`Водитель зарегистрирован. Пароль: ${r.password}`, 'success');
            Drivers._resetFormToCreate();
            await Drivers.loadDrivers();
            showSection('drivers');
        } catch (e) {
            showToast('Ошибка регистрации: ' + e.message, 'error');
        } finally {
            btn.disabled = false;
            btn.innerHTML = originalContent;
        }
    },

    async resetPassword(driverId) {
        const driver = Drivers.drivers.find(d => d.id === driverId);
        if (!driver) return;
        const newPwd = prompt(`Новый пароль для ${driver.fullName} (минимум 6 символов).\nОставьте пустым для использования последних 6 цифр номера:`);
        if (newPwd === null) return;
        if (newPwd.trim() && newPwd.trim().length < 6) {
            showToast('Пароль должен быть не короче 6 символов', 'error');
            return;
        }
        try {
            const r = await Api.post(`/api/admin/users/${encodeURIComponent(driverId)}/password`, { password: newPwd.trim() });
            showToast(`Пароль изменён. Сообщите водителю: ${r.password}`, 'success');
        } catch (e) {
            showToast('Ошибка смены пароля: ' + e.message, 'error');
        }
    },

    async toggleStatus(driverId, currentStatus) {
        try {
            await Api.post(`/api/admin/drivers/${encodeURIComponent(driverId)}/active`, { active: !currentStatus });
            await Drivers.loadDrivers();
            showToast('Статус обновлён', 'success');
        } catch (e) {
            showToast('Ошибка обновления статуса: ' + e.message, 'error');
        }
    },

    async deleteDriver(driverId) {
        if (!confirm('Удалить водителя? Его вход будет удалён; путевые листы останутся в архиве.')) return;
        try {
            await Api.del('/api/admin/drivers/' + encodeURIComponent(driverId));
            await Drivers.loadDrivers();
            showToast('Водитель удалён', 'success');
        } catch (e) {
            showToast('Ошибка удаления: ' + e.message, 'error');
        }
    }
};
