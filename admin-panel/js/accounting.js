// Бухгалтерия — ежемесячная оплата водителей (₽), отметка вручную.
// Модель: payments/{driverId}_{YYYY-MM} = { driverId, driverName, period, amount, paid, paidAt, markedBy }
// Тариф водителя — поле monthlyPrice в документе drivers/{id}.
// Итоги (ожидается / собрано / долг) считаются по активным водителям.
const Accounting = {
    _unsub: null,
    _period: null,        // 'YYYY-MM'
    _payments: {},        // driverId -> payment data за выбранный период

    init() {
        // период по умолчанию — текущий месяц
        const now = new Date();
        Accounting._period = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
    },

    _esc(value) {
        const s = value == null ? '' : String(value);
        return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
                .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
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
        Accounting._subscribe();
    },

    stopRealtime() {
        if (Accounting._unsub) { Accounting._unsub(); Accounting._unsub = null; }
    },

    setMonth(value) {
        if (!value) return;
        Accounting._period = value;
        Accounting._subscribe();
    },

    _shiftMonth(delta) {
        const [y, m] = Accounting._period.split('-').map(Number);
        const d = new Date(y, (m - 1) + delta, 1);
        Accounting._period = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
        const input = document.getElementById('accounting-month-input');
        if (input) input.value = Accounting._period;
        Accounting._subscribe();
    },
    prevMonth() { Accounting._shiftMonth(-1); },
    nextMonth() { Accounting._shiftMonth(1); },

    // Подписка на платежи выбранного периода (realtime).
    _subscribe() {
        if (Accounting._unsub) { Accounting._unsub(); Accounting._unsub = null; }
        Accounting._unsub = db.collection('payments')
            .where('period', '==', Accounting._period)
            .onSnapshot(snap => {
                Accounting._payments = {};
                snap.forEach(doc => {
                    const p = doc.data() || {};
                    if (p.driverId) Accounting._payments[p.driverId] = p;
                });
                Accounting.render();
            }, err => {
                console.error('Accounting onSnapshot error:', err);
            });
    },

    render() {
        const tbody = document.getElementById('accounting-tbody');
        if (!tbody) return;
        const e = Accounting._esc;
        // Источник водителей — живой кэш Drivers (realtime). Активные = active !== false.
        const drivers = (typeof Drivers !== 'undefined' ? Drivers.drivers : [])
            .filter(d => d.active !== false);

        let expected = 0, collected = 0, unpaid = 0;

        if (drivers.length === 0) {
            tbody.innerHTML = '<tr><td colspan="5" style="text-align:center;color:var(--text-light);padding:32px;">Нет активных водителей</td></tr>';
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
        const driver = (typeof Drivers !== 'undefined' ? Drivers.drivers : []).find(d => d.id === driverId);
        if (!driver) { showToast('Водитель не найден', 'error'); return; }
        const price = Accounting._price(driver);
        const docId = `${driverId}_${Accounting._period}`;
        try {
            await db.collection('payments').doc(docId).set({
                driverId,
                driverName: driver.fullName || '',
                period: Accounting._period,
                amount: price,
                paid: !!paid,
                paidAt: paid ? firebase.firestore.FieldValue.serverTimestamp() : null,
                markedBy: Auth.currentUser ? Auth.currentUser.uid : null,
                updatedAt: firebase.firestore.FieldValue.serverTimestamp()
            }, { merge: true });
            showToast(paid ? 'Оплата отмечена' : 'Отметка снята', 'success');
        } catch (e) {
            console.error('Payment toggle error:', e);
            showToast('Ошибка: ' + (e.message || e.code), 'error');
        }
    }
};
