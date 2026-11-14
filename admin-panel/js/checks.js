// Допуск на линию: медосмотр и техконтроль.
//
// Водитель в приложении нажимает «Запросить допуск». Медик и мастер входят на
// сайт под своими учётными записями и каждый отмечает свою часть. Сервер
// записывает, кто и когда отметил, и выпускает лист после обеих отметок.
// Администратор видит очередь, но отмечать за медика и мастера не может.
const Checks = {
    _stop: null,
    _items: [],
    _busy: {},

    _tsText(ms) {
        if (!ms) return '';
        return new Date(ms).toLocaleTimeString('ru-RU', { hour: '2-digit', minute: '2-digit', timeZone: 'Europe/Moscow' });
    },

    // Очередь обновляется каждые 5 секунд (вместо realtime-подписки).
    load() {
        if (Checks._stop) return;
        const tbody = document.getElementById('checks-tbody');
        if (tbody && !Checks._items.length) tbody.innerHTML = '<tr><td colspan="5" class="table-empty">Загрузка…</td></tr>';
        Checks._stop = poll(async () => {
            try {
                const r = await Api.get('/api/checks');
                const items = r.items || [];
                // Перерисовываем только при изменениях: иначе кнопка заменяется
                // прямо во время нажатия и клик теряется.
                const sig = JSON.stringify(items);
                if (sig === Checks._sig) return;
                Checks._sig = sig;
                Checks._items = items;
                Checks.render();
            } catch (e) {
                const tb = document.getElementById('checks-tbody');
                if (tb && !Checks._items.length) tb.innerHTML = `<tr><td colspan="5" class="table-empty" style="color:var(--danger)">${escHtml(e.message)}</td></tr>`;
                throw e;
            }
        }, 5000);
    },

    stopRealtime() {
        if (Checks._stop) { Checks._stop(); Checks._stop = null; }
        Checks._items = [];
        Checks._sig = null;
    },

    _updateBadge() {
        const badge = document.getElementById('checks-badge');
        if (!badge) return;
        const prefix = Auth.role === 'medic' ? 'med' : Auth.role === 'mechanic' ? 'tech' : null;
        // Медику/мастеру — сколько ждут именно его; админу — сколько всего в очереди.
        const n = prefix ? Checks._items.filter(w => !w[prefix + 'Status']).length : Checks._items.length;
        badge.textContent = n > 99 ? '99+' : String(n);
        badge.style.display = n > 0 ? '' : 'none';
    },

    _cell(w, prefix) {
        const e = escHtml;
        if (w[prefix + 'Status'] === 'ok') {
            return `<span class="status-badge status-active"><i class="fas fa-check"></i> Допущен</span>
                    <div class="check-meta">${e(w[prefix + 'Name'])} · ${e(w[prefix + 'Time'] || Checks._tsText(w[prefix + 'ConfirmedAt']))}</div>`;
        }
        const myRole = prefix === 'med' ? 'medic' : 'mechanic';
        if (Auth.role === myRole) {
            const busy = Checks._busy[w.id] ? 'disabled' : '';
            const id = e(w.id);
            return `<div class="check-actions">
                        <button class="btn btn-sm btn-primary" ${busy} onclick="Checks.mark('${id}', true)"><i class="fas fa-check"></i> Допустить</button>
                        <button class="btn btn-sm btn-danger" ${busy} onclick="Checks.mark('${id}', false)" title="Не допустить"><i class="fas fa-xmark"></i></button>
                    </div>`;
        }
        return '<span class="status-badge status-open"><i class="fas fa-hourglass-half"></i> Ожидает</span>';
    },

    render() {
        Checks._updateBadge();
        const tbody = document.getElementById('checks-tbody');
        if (!tbody) return;
        const e = escHtml;
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

    // Отметка ставится от имени вошедшего медика/мастера; время — серверное.
    async mark(waybillId, ok) {
        if (Auth.role !== 'medic' && Auth.role !== 'mechanic') {
            showToast('Отметку ставит только сам медик или мастер', 'error');
            return;
        }
        let reason = '';
        if (!ok) {
            const r = prompt('Причина отказа (водитель увидит её в приложении):', '');
            if (r === null) return;
            reason = r.trim().slice(0, 300);
        }
        Checks._busy[waybillId] = true;
        Checks.render();
        try {
            const r = await Api.post(`/api/checks/${encodeURIComponent(waybillId)}/mark`, { ok, reason });
            if (r.status === 'active') showToast('Допущен. Путевой лист выпущен', 'success');
            else if (r.status === 'rejected') showToast('Отказ сохранён', 'success');
            else showToast('Допуск отмечен. Ждём вторую отметку', 'success');
            const fresh = await Api.get('/api/checks');
            Checks._items = fresh.items || [];
            Checks._sig = JSON.stringify(Checks._items);
        } catch (e) {
            showToast('Ошибка: ' + e.message, 'error');
        } finally {
            delete Checks._busy[waybillId];
            Checks.render();
        }
    }
};
