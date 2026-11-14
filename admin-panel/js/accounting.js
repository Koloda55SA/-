// Бухгалтерия — ежемесячная оплата водителей (₽), отметка вручную.
// Тариф водителя — monthlyPrice в профиле. Итоги считаются по активным водителям.
const Accounting = {
    _period: null,        // 'YYYY-MM'
    _payments: {},        // driverId -> { paid, amount }

    init() {
        const now = new Date();
        Accounting._period = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
    },

    _fmt(n) {
        return (Number(n) || 0).toLocaleString('ru-RU') + ' ₽';
    },

    _price(driver) {
        const v = driver.monthlyPrice;
        return typeof v === 'number' ? v : (parseFloat(v) || 0);
    },

    load() {
        if (!Accounting._period) Accounting.init();
        const input = document.getElementById('accounting-month-input');
        if (input && !input.value) input.value = Accounting._period;
        Accounting._fetch();
    },

    stopRealtime() { Accounting._payments = {}; },

    setMonth(value) {
        if (!value) return;
        Accounting._period = value;
        Accounting._fetch();
    },

    _shiftMonth(delta) {
        const [y, m] = Accounting._period.split('-').map(Number);
        const d = new Date(y, (m - 1) + delta, 1);
        Accounting._period = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
        const input = document.getElementById('accounting-month-input');
        if (input) input.value = Accounting._period;
        Accounting._fetch();
    },
    prevMonth() { Accounting._shiftMonth(-1); },
    nextMonth() { Accounting._shiftMonth(1); },

    async _fetch() {
        const period = Accounting._period;
        try {
            const r = await Api.get('/api/admin/payments?period=' + encodeURIComponent(period));
            if (period !== Accounting._period) return;
            Accounting._payments = {};
            (r.items || []).forEach(p => { Accounting._payments[p.driverId] = p; });
            Accounting.render();
        } catch (e) {
            showToast('Ошибка загрузки оплат: ' + e.message, 'error');
        }
    },

    render() {
        const tbody = document.getElementById('accounting-tbody');
        if (!tbody) return;
        const e = escHtml;
        const drivers = (typeof Drivers !== 'undefined' ? Drivers.drivers : []).filter(d => d.active !== false);
        let expected = 0, collected = 0, unpaid = 0;

        if (drivers.length === 0) {
            tbody.innerHTML = '<tr><td colspan="5" class="table-empty">Нет активных водителей</td></tr>';
        } else {
            tbody.innerHTML = drivers.map(d => {
                const price = Accounting._price(d);
                expected += price;
                const pay = Accounting._payments[d.id];
                const paid = pay && pay.paid === true;
                if (paid) collected += (typeof pay.amount === 'number' ? pay.amount : price);
                else unpaid++;
                const statusBadge = paid
                    ? '<span class="status-badge status-active">Оплачено</span>'
                    : '<span class="status-badge status-inactive">Не оплачено</span>';
                const btn = paid
                    ? `<button class="btn btn-sm btn-outline" onclick="Accounting.toggle('${e(d.id)}', false)"><i class="fas fa-rotate-left"></i> Снять отметку</button>`
                    : `<button class="btn btn-sm btn-primary" onclick="Accounting.toggle('${e(d.id)}', true)"><i class="fas fa-check"></i> Отметить оплату</button>`;
                return `
                    <tr>
                        <td data-label="Водитель"><strong>${e(d.fullName)}</strong></td>
                        <td data-label="Телефон">${e(d.phone) || '—'}</td>
                        <td data-label="Тариф">${Accounting._fmt(price)}</td>
                        <td data-label="Статус оплаты">${statusBadge}</td>
                        <td data-label="Действия">${btn}</td>
                    </tr>`;
            }).join('');
        }

        const set = (id, v) => { const el = document.getElementById(id); if (el) el.textContent = v; };
        set('acc-expected', Accounting._fmt(expected));
        set('acc-collected', Accounting._fmt(collected));
        set('acc-debt', Accounting._fmt(Math.max(0, expected - collected)));
        set('acc-unpaid-count', unpaid);
    },

    async toggle(driverId, paid) {
        try {
            await Api.put('/api/admin/payments', { driverId, period: Accounting._period, paid: !!paid });
            showToast(paid ? 'Оплата отмечена' : 'Отметка снята', 'success');
            await Accounting._fetch();
        } catch (e) {
            showToast('Ошибка: ' + e.message, 'error');
        }
    }
};
