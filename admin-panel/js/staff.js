// Сотрудники: медики и мастера (контролёры тех. состояния ТС).
// Каждый получает свою учётную запись (вход на этот же сайт по телефону и паролю)
// и сам ставит отметки допуска в разделе «Допуск».
// Модель: admins/{uid} = { role: 'medic'|'mechanic'|'admin', fullName, phone,
//                           certSerial, certIssued, certExpires }
// Данные сертификата вносятся из сертификата самого сотрудника и печатаются
// в отметке о допуске на ЭПЛ.
const Staff = {
    _unsub: null,
    _list: [],
    _editingId: null,

    ROLES: {
        medic:    { label: 'Медик',          cls: 'status-active' },
        mechanic: { label: 'Мастер (техконтроль)', cls: 'status-open' },
        admin:    { label: 'Администратор',  cls: 'status-debtor' },
    },

    _esc(value) {
        const s = value == null ? '' : String(value);
        return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
                .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    },

    // "2026-11-15" (input type=date) <-> "15.11.2026" (как печатается на ЭПЛ)
    _toRu(iso) {
        const m = String(iso || '').match(/^(\d{4})-(\d{2})-(\d{2})$/);
        return m ? `${m[3]}.${m[2]}.${m[1]}` : '';
    },
    _toIso(ru) {
        const m = String(ru || '').match(/^(\d{2})\.(\d{2})\.(\d{4})$/);
        return m ? `${m[3]}-${m[2]}-${m[1]}` : '';
    },

    init() {
        const form = document.getElementById('staff-form');
        if (form) {
            form.addEventListener('submit', (e) => {
                e.preventDefault();
                Staff.save();
            });
        }
    },

    load() {
        if (Staff._unsub) return;
        Staff._unsub = db.collection('admins').onSnapshot(snap => {
            Staff._list = snap.docs.map(d => ({ id: d.id, ...d.data() }));
            Staff._list.sort((a, b) => String(a.fullName || a.phone || '').localeCompare(String(b.fullName || b.phone || ''), 'ru'));
            Staff.render();
        }, err => console.error('Staff onSnapshot error:', err));
    },

    stopRealtime() {
        if (Staff._unsub) { Staff._unsub(); Staff._unsub = null; }
    },

    render() {
        const tbody = document.getElementById('staff-tbody');
        if (!tbody) return;
        const e = Staff._esc;
        if (Staff._list.length === 0) {
            tbody.innerHTML = '<tr><td colspan="5" class="table-empty">Сотрудников пока нет</td></tr>';
            return;
        }
        tbody.innerHTML = Staff._list.map(s => {
            const r = Staff.ROLES[s.role || 'admin'] || Staff.ROLES.admin;
            const cert = s.certSerial
                ? `${e(s.certSerial)}<div class="check-meta">${e(s.certIssued)} — ${e(s.certExpires)}</div>`
                : '<span style="color:var(--text-light)">—</span>';
            const isMe = Auth.currentUser && Auth.currentUser.uid === s.id;
            const id = e(s.id);
            return `
                <tr>
                    <td data-label="Сотрудник"><strong>${e(s.fullName) || '—'}</strong>${isMe ? ' <span class="check-meta">(вы)</span>' : ''}</td>
                    <td data-label="Телефон">${e(s.phone) || '—'}</td>
                    <td data-label="Роль"><span class="status-badge ${r.cls}">${r.label}</span></td>
                    <td data-label="Сертификат">${cert}</td>
                    <td data-label="Действия">
                        <button class="btn btn-sm btn-outline" onclick="Staff.edit('${id}')" title="Редактировать"><i class="fas fa-pen"></i></button>
                        <button class="btn btn-sm btn-outline" onclick="Staff.resetPassword('${id}')" title="Сменить пароль"><i class="fas fa-key"></i></button>
                        ${isMe ? '' : `<button class="btn btn-sm btn-danger" onclick="Staff.remove('${id}')" title="Удалить сотрудника"><i class="fas fa-trash"></i></button>`}
                    </td>
                </tr>`;
        }).join('');
    },

    _val(id) {
        const el = document.getElementById(id);
        return el ? String(el.value || '').trim() : '';
    },

    resetForm() {
        Staff._editingId = null;
        const form = document.getElementById('staff-form');
        if (form) form.reset();
        const set = (id, t) => { const el = document.getElementById(id); if (el) el.textContent = t; };
        set('staff-form-title', 'Новый сотрудник');
        set('staff-submit-text', 'Создать учётную запись');
        const pg = document.getElementById('staff-password-group');
        if (pg) pg.style.display = '';
        const ph = document.getElementById('staff-phone');
        if (ph) ph.readOnly = false;
        const cancel = document.getElementById('staff-cancel-btn');
        if (cancel) cancel.style.display = 'none';
    },

    edit(id) {
        const s = Staff._list.find(x => x.id === id);
        if (!s) return;
        Staff._editingId = id;
        const setV = (elId, v) => { const el = document.getElementById(elId); if (el) el.value = v || ''; };
        setV('staff-fullname', s.fullName);
        setV('staff-phone', s.phone);
        setV('staff-role', s.role || 'admin');
        setV('staff-cert-serial', s.certSerial);
        setV('staff-cert-issued', Staff._toIso(s.certIssued));
        setV('staff-cert-expires', Staff._toIso(s.certExpires));
        const set = (elId, t) => { const el = document.getElementById(elId); if (el) el.textContent = t; };
        set('staff-form-title', 'Редактирование сотрудника');
        set('staff-submit-text', 'Сохранить');
        const pg = document.getElementById('staff-password-group');
        if (pg) pg.style.display = 'none';
        const ph = document.getElementById('staff-phone');
        if (ph) ph.readOnly = true;
        const cancel = document.getElementById('staff-cancel-btn');
        if (cancel) cancel.style.display = '';
        document.getElementById('staff-form').scrollIntoView({ behavior: 'smooth', block: 'start' });
    },

    async save() {
        const fullName = Staff._val('staff-fullname');
        const role = Staff._val('staff-role') || 'medic';
        const certSerial = Staff._val('staff-cert-serial').replace(/[^0-9a-fA-F]/g, '').toLowerCase();
        const certIssued = Staff._toRu(Staff._val('staff-cert-issued'));
        const certExpires = Staff._toRu(Staff._val('staff-cert-expires'));

        if (!fullName) { showToast('Укажите ФИО сотрудника', 'error'); return; }
        if (!Staff.ROLES[role]) { showToast('Выберите роль', 'error'); return; }

        const btn = document.querySelector('#staff-form button[type="submit"]');
        const orig = btn.innerHTML;
        btn.disabled = true;
        btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Сохранение...';
        try {
            const data = {
                fullName, role, certSerial, certIssued, certExpires,
                updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
            };
            if (Staff._editingId) {
                await db.collection('admins').doc(Staff._editingId).update(data);
                showToast('Данные сотрудника сохранены', 'success');
            } else {
                const phone = Drivers._normalizePhone(Staff._val('staff-phone'));
                if (phone.replace(/\D/g, '').length < 10) throw new Error('Некорректный номер телефона');
                const password = Staff._val('staff-password');
                if (password.length < 6) throw new Error('Пароль — минимум 6 символов');
                const email = `${phone.replace(/\D/g, '')}@asempro.admin`;

                // Создаём аккаунт через вторичное приложение, чтобы админ не разлогинился.
                const secondaryAuth = Drivers._getSecondaryAuth();
                const cred = await secondaryAuth.createUserWithEmailAndPassword(email, password);
                const uid = cred.user.uid;
                await secondaryAuth.signOut();
                await db.collection('admins').doc(uid).set({
                    ...data,
                    phone,
                    createdAt: firebase.firestore.FieldValue.serverTimestamp(),
                    createdBy: Auth.currentUser.uid,
                });
                showToast(`Сотрудник создан. Вход: ${phone}, пароль: ${password}`, 'success');
            }
            Staff.resetForm();
        } catch (e) {
            console.error('Staff save error:', e);
            let msg = e.message || e.code;
            if (e.code === 'auth/email-already-in-use') msg = 'Сотрудник с таким телефоном уже есть';
            showToast('Ошибка: ' + msg, 'error');
        } finally {
            btn.disabled = false;
            btn.innerHTML = orig;
        }
    },

    async _callWorker(path, body) {
        if (typeof AUTH_WORKER_URL !== 'string' || !AUTH_WORKER_URL) throw new Error('Сервер смены пароля не подключён');
        const idToken = await auth.currentUser.getIdToken();
        const res = await fetch(AUTH_WORKER_URL.replace(/\/+$/, '') + path, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json' },
            body: JSON.stringify({ idToken, ...body }),
        });
        const data = await res.json().catch(() => ({}));
        if (!res.ok || !data.ok) throw new Error(data.error || ('HTTP ' + res.status));
    },

    async resetPassword(id) {
        const s = Staff._list.find(x => x.id === id);
        if (!s) return;
        const pwd = prompt(`Новый пароль для ${s.fullName || s.phone} (минимум 6 символов):`);
        if (pwd === null) return;
        if (pwd.trim().length < 6) { showToast('Пароль — минимум 6 символов', 'error'); return; }
        try {
            await Staff._callWorker('/reset-password', { driverUid: id, newPassword: pwd.trim() });
            showToast('Пароль изменён', 'success');
        } catch (e) {
            showToast('Ошибка смены пароля: ' + e.message, 'error');
        }
    },

    async remove(id) {
        const s = Staff._list.find(x => x.id === id);
        if (!s) return;
        if (!confirm(`Удалить сотрудника ${s.fullName || s.phone}? Он больше не сможет войти и ставить отметки.`)) return;
        try {
            // Сначала убираем доступ (документ роли), затем — сам аккаунт входа.
            await db.collection('admins').doc(id).delete();
            try {
                await Staff._callWorker('/delete-driver', { driverUid: id });
            } catch (e) {
                console.warn('Auth account delete failed (доступ уже снят):', e);
            }
            showToast('Сотрудник удалён', 'success');
        } catch (e) {
            showToast('Ошибка удаления: ' + (e.message || e.code), 'error');
        }
    }
};
