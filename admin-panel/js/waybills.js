// Путевые листы: последние 50, обновляются каждые 30 секунд, пока раздел открыт.
const Waybills = {
    waybills: [],
    _stop: null,

    STATUSES: {
        pending:   { label: 'Ждёт допуска', cls: 'status-debtor' },
        active:    { label: 'Открыт',       cls: 'status-open' },
        closed:    { label: 'Закрыт',       cls: 'status-active' },
        rejected:  { label: 'Не допущен',   cls: 'status-inactive' },
        cancelled: { label: 'Отменён',      cls: 'status-inactive' },
    },

    loadWaybills() {
        if (Waybills._stop) return;
        Waybills._stop = poll(async () => {
            const section = document.getElementById('section-waybills');
            // Обновляем только когда раздел открыт (и один раз при первом показе).
            if (Waybills.waybills.length && section && !section.classList.contains('active')) return;
            const r = await Api.get('/api/admin/waybills?limit=50');
            const sig = JSON.stringify(r.items || []);
            if (sig === Waybills._sig) return;   // без изменений — не перерисовываем
            Waybills._sig = sig;
            Waybills.waybills = r.items || [];
            Waybills.render();
        }, 30000);
    },

    refresh() {
        Waybills.stopRealtime();
        Waybills.waybills = [];
        Waybills._sig = null;
        Waybills.loadWaybills();
    },

    stopRealtime() {
        if (Waybills._stop) { Waybills._stop(); Waybills._stop = null; }
    },

    render() {
        const tbody = document.getElementById('waybills-tbody');
        if (!tbody) return;
        tbody.innerHTML = Waybills.waybills.length
            ? Waybills.waybills.map(Waybills.renderRow).join('')
            : '<tr><td colspan="6" class="table-empty">Нет путевых листов</td></tr>';
    },

    renderRow(waybill) {
        const e = escHtml;
        const date = waybill.createdAt ? new Date(waybill.createdAt).toLocaleDateString('ru-RU') : '';
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
            </tr>`;
    },

    // Та же страница, что открывается по QR-коду на листе.
    viewWaybill(waybillId) {
        window.open(`waybill.html?id=${encodeURIComponent(waybillId)}`, '_blank', 'noopener');
    }
};
