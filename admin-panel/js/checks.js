// Допуск на линию: медосмотр и техконтроль.
//
// Водитель в приложении нажимает «Запросить допуск» — создаётся путевой лист
// со статусом 'pending'. Медик и мастер входят на сайт под СВОИМИ учётными
// записями (роль 'medic' / 'mechanic' в admins/{uid}) и каждый отмечает свою
// часть: «Допустить» или «Не допустить». В лист записывается, кто и когда
// отметил, и данные его сертификата из профиля сотрудника.
// Когда обе отметки «Допущен» — лист становится 'active' и водитель получает ЭПЛ.
// Администратор видит статусы, но отмечать за медика и мастера не может
// (это же запрещено правилами Firestore).
const Checks = {
    _unsub: null,
    _items: [],
    _busy: {},
    _subscriptions: [],
    _policies: {},
    _staff: [],
    _saving: new Set(),

    init() {
        for (const group of document.querySelectorAll('[data-issue-role]')) {
            group.querySelector('input').addEventListener('change', Checks.saveAutoIssue);
            group.querySelector('select').addEventListener('change', () => Checks.renderRole(group));
        }
    },

    renderAutoIssue() {
        const settings = document.getElementById('auto-issue-settings');
        const user = Auth.currentUser;
        for (const unsubscribe of Checks._subscriptions) unsubscribe();
        Checks._subscriptions = [];
        Checks._policies = {};
        Checks._staff = [];
        Checks._saving = new Set();
        settings.hidden = !user;
        const feedback = document.getElementById('auto-issue-feedback');
        feedback.textContent = '';
        delete feedback.dataset.error;
        const groups = document.querySelectorAll('[data-issue-role]');
        for (const group of groups) {
            group.querySelector('select').replaceChildren();
            Checks.renderRole(group);
        }
        if (!user) return;
        const staff = db.collection('admins');
        const isAdmin = Auth.role === 'admin';
        const refresh = () => {
            for (const group of groups) Checks.renderRole(group);
        };
        const failed = message => {
            refresh();
            feedback.textContent = message + ' Обновите страницу.';
            feedback.dataset.error = '';
        };
        for (const group of groups) {
            const role = group.dataset.issueRole;
            if (!isAdmin && Auth.role !== role) continue;
            Checks._subscriptions.push(Checks.policyRef(role).onSnapshot(snapshot => {
                if (Auth.currentUser !== user) return;
                Checks._policies[role] = snapshot.data() || {};
                refresh();
            }, () => {
                if (Auth.currentUser !== user) return;
                delete Checks._policies[role];
                failed('Не удалось загрузить настройку автодопуска.');
            }));
        }
        const source = isAdmin ? staff.where('role', 'in', ['medic', 'mechanic']) : staff.doc(user.uid);
        Checks._subscriptions.push(source.onSnapshot(snapshot => {
            if (Auth.currentUser !== user) return;
            Checks._staff = (isAdmin ? snapshot.docs : (snapshot.exists ? [snapshot] : []))
                .map(doc => ({ ...doc.data(), id: doc.id }))
                .sort((a, b) => (a.fullName || a.id).localeCompare(b.fullName || b.id, 'ru'));
            refresh();
        }, () => {
            if (Auth.currentUser !== user) return;
            Checks._staff = [];
            failed('Не удалось загрузить список сотрудников.');
        }));
    },

    policyRef(role) {
        return db.collection('settings').doc('autoIssue-' + role);
    },

    enabledFor(employee) {
        const policy = Checks._policies[employee?.role];
        if (!policy || !employee) return false;
        if (policy.revision && employee.autoIssueRevision !== policy.revision) return policy.enabled === true;
        return employee.autoIssueEnabled === true;
    },

    renderRole(group) {
        const role = group.dataset.issueRole;
        const staff = Checks._staff.filter(s => s.role === role);
        const input = group.querySelector('input');
        const select = group.querySelector('select');
        const note = group.querySelector('small');
        const isAdmin = Auth.role === 'admin';
        const otherRole = !isAdmin && Auth.role !== role;
        const policy = Checks._policies[role];
        const selected = isAdmin ? staff.find(s => s.id === select.value) : staff[0];
        const all = role === 'medic' ? 'Все медики' : 'Все мастера';
        const options = staff.map(s => new Option(s.fullName || s.phone || s.id, s.id));
        if (isAdmin) options.unshift(new Option(all, ''));
        select.replaceChildren(...options);
        select.value = selected?.id || '';
        select.hidden = !isAdmin || !staff.length;
        select.disabled = Checks._saving.has(role);
        input.checked = selected ? Checks.enabledFor(selected) : policy?.enabled === true;
        input.indeterminate = otherRole || !policy;
        input.disabled = otherRole || !policy || (!isAdmin && !selected) || Checks._saving.has(role);
        note.textContent = otherRole ? 'Настройка в кабинете сотрудника' :
            !policy ? 'Настройка ещё не загружена' :
            selected ? (selected.fullName || selected.phone || '') :
            isAdmin ? 'Выбор применяется ко всем действующим и новым сотрудникам этой роли.' : 'Сотрудник не найден';
    },

    async saveAutoIssue(event) {
        const input = event.target;
        const role = input.dataset.autoIssue;
        const group = input.closest('[data-issue-role]');
        const id = group.querySelector('select').value;
        const enabled = input.checked;
        const user = Auth.currentUser;
        if (!user || input.disabled || (Auth.role !== 'admin' && (user.uid !== id || Auth.role !== role))) return;
        const profile = Auth.profile;
        const saving = Checks._saving;
        saving.add(role);
        group.querySelector('select').disabled = true;
        const feedback = document.getElementById('auto-issue-feedback');
        input.disabled = true;
        delete feedback.dataset.error;
        feedback.textContent = 'Сохранение…';

        try {
            if (Auth.role === 'admin') {
                const policy = Checks.policyRef(role);
                await db.runTransaction(async tx => {
                    if (!id) {
                        // A new revision supersedes all earlier individual choices in this role.
                        tx.set(policy, { enabled, revision: crypto.randomUUID() });
                        return;
                    }
                    const ref = db.collection('admins').doc(id);
                    const snapshot = await tx.get(ref);
                    if (!snapshot.exists || snapshot.data().role !== role) throw new Error('Роль изменилась');
                    const current = await tx.get(policy);
                    tx.update(ref, { autoIssueEnabled: enabled, autoIssueRevision: current.data()?.revision || '' });
                });
            } else {
                const idToken = await user.getIdToken();
                const response = await fetch('/api/inspections/auto-issue-preference', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ idToken, enabled }),
                });
                if (!response.ok) throw new Error('Не удалось сохранить настройку');
            }
            if (Auth.profile !== profile) return;
            feedback.textContent = enabled ? 'Автодопуск включён.' : 'Автодопуск выключен.';
        } catch (error) {
            if (Auth.profile !== profile) return;
            feedback.dataset.error = '';
            feedback.textContent = 'Не удалось сохранить настройку. Попробуйте ещё раз.';
        } finally {
            saving.delete(role);
            if (Auth.profile === profile) Checks.renderRole(group);
        }
    },

    MONTHS: ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
             'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'],

    _esc(value) {
        const s = value == null ? '' : String(value);
        return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
                .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    },

    // Московское время (UTC+3, без перехода на летнее время).
    _msk(date) {
        const m = new Date(date.getTime() + 3 * 3600 * 1000);
        const two = (x) => String(x).padStart(2, '0');
        return {
            date: `${two(m.getUTCDate())}.${two(m.getUTCMonth() + 1)}.${m.getUTCFullYear()}`,
            dateFormatted: `«${two(m.getUTCDate())}» ${Checks.MONTHS[m.getUTCMonth()]} ${m.getUTCFullYear()} г.`,
            time: `${two(m.getUTCHours())}:${two(m.getUTCMinutes())}:${two(m.getUTCSeconds())}`,
        };
    },

    _tsText(ts) {
        if (!ts || !ts.seconds) return '';
        return Checks._msk(new Date(ts.seconds * 1000)).time.slice(0, 5);
    },

    // Подписка на листы, ожидающие допуска. Сортировка — на клиенте,
    // чтобы не требовался составной индекс.
    load() {
        if (Checks._unsub) return;
        const tbody = document.getElementById('checks-tbody');
        if (tbody) tbody.innerHTML = '<tr><td colspan="5" class="table-empty">Загрузка…</td></tr>';
        Checks._unsub = db.collection('waybills')
            .where('status', '==', 'pending')
            .limit(200)
            .onSnapshot(snap => {
                Checks._items = snap.docs.map(d => ({ id: d.id, ...d.data() }));
                Checks._items.sort((a, b) => ((a.createdAt && a.createdAt.seconds) || 0) - ((b.createdAt && b.createdAt.seconds) || 0));
                Checks.render();
            }, err => {
                console.error('Checks onSnapshot error:', err);
                const tb = document.getElementById('checks-tbody');
                if (tb) tb.innerHTML = '<tr><td colspan="5" class="table-empty" style="color:var(--danger)">Ошибка загрузки. Проверьте права доступа.</td></tr>';
            });
    },

    stopRealtime() {
        if (Checks._unsub) { Checks._unsub(); Checks._unsub = null; }
        Checks._items = [];
    },

    _updateBadge() {
        const badge = document.getElementById('checks-badge');
        if (!badge) return;
        const role = Auth.role;
        const prefix = role === 'medic' ? 'med' : role === 'mechanic' ? 'tech' : null;
        // Медику/мастеру — сколько ждут именно его; админу — сколько всего в очереди.
        const n = prefix ? Checks._items.filter(w => !w[prefix + 'Status']).length : Checks._items.length;
        badge.textContent = n > 99 ? '99+' : String(n);
        badge.style.display = n > 0 ? '' : 'none';
    },

    _cell(w, prefix) {
        const e = Checks._esc;
        const st = w[prefix + 'Status'];
        if (st === 'ok') {
            return `<span class="status-badge status-active"><i class="fas fa-check"></i> Допущен</span>
                    <div class="check-meta">${e(w[prefix + 'Name'])} · ${e(w[prefix + 'Time'] || Checks._tsText(w[prefix + 'ConfirmedAt']))}</div>`;
        }
        const myRole = prefix === 'med' ? 'medic' : 'mechanic';
        if (Auth.role === myRole) {
            const busy = Checks._busy[w.id] ? 'disabled' : '';
            const id = e(w.id);
            return `<div class="check-actions">
                        <button class="btn btn-sm btn-primary" ${busy} onclick="Checks.mark('${id}', '${prefix}', true)"><i class="fas fa-check"></i> Допустить</button>
                        <button class="btn btn-sm btn-danger" ${busy} onclick="Checks.mark('${id}', '${prefix}', false)" title="Не допустить"><i class="fas fa-xmark"></i></button>
                    </div>`;
        }
        return '<span class="status-badge status-open"><i class="fas fa-hourglass-half"></i> Ожидает</span>';
    },

    render() {
        Checks._updateBadge();
        const tbody = document.getElementById('checks-tbody');
        if (!tbody) return;
        const e = Checks._esc;
        if (Checks._items.length === 0) {
            tbody.innerHTML = '<tr><td colspan="5" class="table-empty">Нет водителей, ожидающих допуска</td></tr>';
            return;
        }
        tbody.innerHTML = Checks._items.map(w => `
            <tr>
                <td data-label="Водитель"><strong>${e(w.driverName)}</strong><div class="check-meta">${e(w.driverPhone)}</div></td>
                <td data-label="Автомобиль">${e(w.carModel)}<div class="check-meta">${e(w.plateNumber)} · одометр ${e(w.odometerStart) || '—'} км</div></td>
                <td data-label="Запрос">${Checks._tsText(w.createdAt) || '—'}</td>
                <td data-label="Медосмотр">${Checks._cell(w, 'med')}</td>
                <td data-label="Техконтроль">${Checks._cell(w, 'tech')}</td>
            </tr>`).join('');
    },

    // Отметка медика (prefix='med') или мастера (prefix='tech').
    async mark(waybillId, prefix, ok) {
        const myRole = prefix === 'med' ? 'medic' : 'mechanic';
        if (Auth.role !== myRole || !Auth.currentUser) {
            showToast('Отметку ставит только сам ' + (prefix === 'med' ? 'медик' : 'мастер'), 'error');
            return;
        }
        let reason = '';
        if (!ok) {
            const r = prompt('Причина отказа (водитель увидит её в приложении):', '');
            if (r === null) return;
            reason = r.trim().slice(0, 300);
        }

        const profile = Auth.profile || {};
        const other = prefix === 'med' ? 'tech' : 'med';
        const ref = db.collection('waybills').doc(waybillId);
        const ts = firebase.firestore.FieldValue.serverTimestamp;
        Checks._busy[waybillId] = true;
        Checks.render();
        try {
            const result = await db.runTransaction(async tx => {
                const snap = await tx.get(ref);
                if (!snap.exists) throw new Error('Путевой лист не найден');
                const w = snap.data() || {};
                if (w.status !== 'pending') throw new Error('Запрос уже обработан');
                if (w[prefix + 'Status']) throw new Error('Вы уже отметили этот запрос');

                const now = new Date();
                const msk = Checks._msk(now);
                const upd = {
                    [prefix + 'Status']: ok ? 'ok' : 'rejected',
                    [prefix + 'ConfirmedAt']: ts(),
                    [prefix + 'ConfirmedBy']: Auth.currentUser.uid,
                    [prefix + 'Name']: profile.fullName || '',
                    [prefix + 'CertSerial']: profile.certSerial || '',
                    [prefix + 'Issued']: profile.certIssued || '',
                    [prefix + 'Expires']: profile.certExpires || '',
                    [prefix + 'Time']: msk.time,
                };
                if (!ok) {
                    upd.status = 'rejected';
                    upd.rejectedAt = ts();
                    upd.rejectedBy = Auth.currentUser.uid;
                    upd.rejectedRole = myRole;
                    upd.rejectReason = reason;
                } else if (w[other + 'Status'] === 'ok') {
                    // Вторая отметка — выпускаем ЭПЛ. Смена начинается сейчас, лист действует 12 часов.
                    const end = new Date(now.getTime() + 12 * 3600 * 1000);
                    const mskEnd = Checks._msk(end);
                    upd.status = 'active';
                    upd.date = msk.date;
                    upd.dateFormatted = msk.dateFormatted;
                    upd.shiftStart = msk.time;
                    upd.departureTime = msk.time;
                    upd.shiftEnd = mskEnd.time;
                    upd.shiftEndDate = mskEnd.date;
                    upd.expiresAt = firebase.firestore.Timestamp.fromDate(end);
                    upd.activatedAt = ts();
                }
                tx.update(ref, upd);
                return upd.status || 'pending';
            });
            if (result === 'active') showToast('Допущен. Путевой лист выпущен', 'success');
            else if (result === 'rejected') showToast('Отказ сохранён', 'success');
            else showToast('Допуск отмечен. Ждём вторую отметку', 'success');
        } catch (e) {
            console.error('Check mark error:', e);
            showToast('Ошибка: ' + (e.message || e.code), 'error');
        } finally {
            delete Checks._busy[waybillId];
            Checks.render();
        }
    }
};
