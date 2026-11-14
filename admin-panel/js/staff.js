// Сотрудники: медики, мастера и администраторы.
// Каждый входит на этот сайт по своему телефону и паролю. Данные сертификата
// вносятся из сертификата самого сотрудника и печатаются в отметке о допуске.
const Staff = {
    _list: [],
    _editingId: null,

    ROLES: {
        medic:    { label: 'Медик',                cls: 'status-active' },
        mechanic: { label: 'Мастер (техконтроль)', cls: 'status-open' },
        admin:    { label: 'Администратор',        cls: 'status-debtor' },
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
        if (form) form.addEventListener('submit', (e) => { e.preventDefault(); Staff.save(); });
    },

    async load() {
        try {
            const r = await Api.get('/api/admin/staff');
            Staff._list = r.items || [];
            Staff.render();
        } catch (e) {
            showToast('Ошибка загрузки сотрудников: ' + e.message, 'error');
        }
    },

    stopRealtime() { Staff._list = []; },

    render() {
        const tbody = document.getElementById('staff-tbody');
        if (!tbody) return;
        const e = escHtml;
        if (Staff._list.length === 0) {
            tbody.innerHTML = '<tr><td colspan="5" class="table-empty">Сотрудников пока нет</td></tr>';
            return;
        }
        tbody.innerHTML = Staff._list.map(s => {
            const r = Staff.ROLES[s.role] || Staff.ROLES.admin;
            const cert = s.certSerial
                ? `${e(s.certSerial)}<div class="check-meta">${e(s.certIssued)} — ${e(s.certExpires)}</div>`
                : '<span style="color:var(--text-light)">—</span>';
            const isMe = Auth.currentUser && Auth.currentUser.id === s.id;
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
        setV('staff-role', s.role);
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
        const body = {
            fullName: Staff._val('staff-fullname'),
            role: Staff._val('staff-role') || 'medic',
            certSerial: Staff._val('staff-cert-serial'),
            certIssued: Staff._toRu(Staff._val('staff-cert-issued')),
            certExpires: Staff._toRu(Staff._val('staff-cert-expires')),
        };
        if (!body.fullName) { showToast('Укажите ФИО сотрудника', 'error'); return; }

        const btn = document.querySelector('#staff-form button[type="submit"]');
        const orig = btn.innerHTML;
        btn.disabled = true;
        btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Сохранение...';
        try {
            if (Staff._editingId) {
                await Api.put('/api/admin/staff/' + encodeURIComponent(Staff._editingId), body);
                showToast('Данные сотрудника сохранены', 'success');
            } else {
                body.phone = Auth._formatPhone(Staff._val('staff-phone'));
                body.password = Staff._val('staff-password');
                if (body.password.length < 6) throw new Error('Пароль — минимум 6 символов');
                await Api.post('/api/admin/staff', body);
                showToast(`Сотрудник создан. Вход: ${body.phone}, пароль: ${body.password}`, 'success');
            }
            Staff.resetForm();
            await Staff.load();
        } catch (e) {
            showToast('Ошибка: ' + e.message, 'error');
        } finally {
            btn.disabled = false;
            btn.innerHTML = orig;
        }
    },

    async resetPassword(id) {
        const s = Staff._list.find(x => x.id === id);
        if (!s) return;
        const pwd = prompt(`Новый пароль для ${s.fullName || s.phone} (минимум 6 символов):`);
        if (pwd === null) return;
        if (pwd.trim().length < 6) { showToast('Пароль — минимум 6 символов', 'error'); return; }
        try {
            await Api.post(`/api/admin/users/${encodeURIComponent(id)}/password`, { password: pwd.trim() });
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
            await Api.del('/api/admin/staff/' + encodeURIComponent(id));
            showToast('Сотрудник удалён', 'success');
            await Staff.load();
        } catch (e) {
            showToast('Ошибка удаления: ' + e.message, 'error');
        }
    }
};
