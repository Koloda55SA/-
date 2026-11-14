// Waybills Management Module
const Waybills = {
    waybills: [],
    _unsub: null,

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

    STATUSES: {
        pending:   { label: 'Ждёт допуска', cls: 'status-debtor' },
        active:    { label: 'Открыт',       cls: 'status-open' },
        closed:    { label: 'Закрыт',       cls: 'status-active' },
        rejected:  { label: 'Не допущен',   cls: 'status-inactive' },
        cancelled: { label: 'Отменён',      cls: 'status-inactive' },
    },

    // Живая подписка на последние 50 путевых листов: новые ЭПЛ и смена статуса
    // отображаются мгновенно, без перезагрузки. Таблица перерисовывается одним
    // присваиванием innerHTML (а не построчно), чтобы не было лишних перерисовок.
    loadWaybills() {
        if (Waybills._unsub) return;
        Waybills._unsub = db.collection('waybills')
            .orderBy('createdAt', 'desc')
            .limit(50)
            .onSnapshot(snapshot => {
                Waybills.waybills = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
                const tbody = document.getElementById('waybills-tbody');
                if (tbody) {
                    tbody.innerHTML = Waybills.waybills.length
                        ? Waybills.waybills.map(Waybills.renderRow).join('')
                        : '<tr><td colspan="6" class="table-empty">Нет путевых листов</td></tr>';
                }
                if (typeof updateDashboard === 'function') updateDashboard();
            }, error => {
                console.error('Waybills onSnapshot error:', error);
            });
    },

    // Отписка от realtime (при выходе из аккаунта).
    stopRealtime() {
        if (Waybills._unsub) { Waybills._unsub(); Waybills._unsub = null; }
    },

    renderRow(waybill) {
        const e = Waybills._esc;
        const date = waybill.createdAt ? new Date(waybill.createdAt.seconds * 1000).toLocaleDateString('ru-RU') : '';
        const st = Waybills.STATUSES[waybill.status] || Waybills.STATUSES.active;
        const reason = waybill.status === 'rejected' && waybill.rejectReason
            ? `<div class="check-meta">${e(waybill.rejectReason)}</div>` : '';

        return `
            <tr>
                <td data-label="Номер"><strong>АП №${e(waybill.waybillNumber)}</strong></td>
                <td data-label="Водитель">${e(waybill.driverName)}</td>
                <td data-label="Организация">${e(waybill.orgName) || '—'}</td>
                <td data-label="Дата">${e(date)}</td>
                <td data-label="Статус"><span class="status-badge ${st.cls}">${st.label}</span>${reason}</td>
                <td data-label="Действия">
                    <button class="btn btn-sm btn-primary" onclick="Waybills.viewWaybill('${e(waybill.id)}')">
                        <i class="fas fa-eye"></i> Просмотр
                    </button>
                </td>
            </tr>
        `;
    },

    // Открывает ту же страницу, что и QR-код на листе, — один шаблон ЭПЛ на всё.
    viewWaybill(waybillId) {
        window.open(`waybill.html?id=${encodeURIComponent(waybillId)}`, '_blank', 'noopener');
    }
};
