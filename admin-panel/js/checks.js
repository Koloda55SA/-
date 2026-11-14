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
