// Quota Requests Module
// Заявки водителей на дополнительные путевые листы (ЭПЛ).
// Водитель отправляет заявку из приложения, когда исчерпал лимит (по умолчанию 60).
// Админ подтверждает (+60 к лимиту) или отклоняет.
const Requests = {
    QUOTA_STEP: 60,
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

    _statusBadge(status) {
        if (status === 'approved') {
            return '<span class="status-badge status-active">Подтверждена</span>';
        }
        if (status === 'rejected') {
            return '<span class="status-badge status-inactive">Отклонена</span>';
        }
        return '<span class="status-badge" style="background:#f59e0b22;color:#f59e0b;">Ожидает</span>';
    },

    // Живая подписка на заявки: новая заявка от водителя и смена статуса
    // отображаются мгновенно. Подписка ставится один раз.
    load() {
        const tbody = document.getElementById('requests-tbody');
        if (!tbody) return;
        if (Requests._unsub) return;
        tbody.innerHTML = '<tr><td colspan="6" style="text-align:center;color:var(--text-light);padding:24px;">Загрузка…</td></tr>';
        Requests._unsub = db.collection('quotaRequests')
            .orderBy('requestedAt', 'desc')
            .onSnapshot(snapshot => {
                const tb = document.getElementById('requests-tbody');
                if (!tb) return;
                tb.innerHTML = '';
                if (snapshot.empty) {
                    tb.innerHTML = '<tr><td colspan="6" style="text-align:center;color:var(--text-light);padding:32px;">Заявок пока нет</td></tr>';
                    return;
                }
                snapshot.forEach(doc => {
                    tb.insertAdjacentHTML('beforeend', Requests.renderRow(doc.id, doc.data() || {}));
                });
            }, e => {
                console.error('Error loading quota requests:', e);
                const tb = document.getElementById('requests-tbody');
                if (tb) tb.innerHTML = '<tr><td colspan="6" style="text-align:center;color:#ef4444;padding:24px;">Ошибка загрузки заявок</td></tr>';
            });
    },

    // Отписка от realtime (при выходе из аккаунта).
    stopRealtime() {
        if (Requests._unsub) { Requests._unsub(); Requests._unsub = null; }
    },

    renderRow(reqId, r) {
        const e = Requests._esc;
        const id = e(reqId);
        const status = r.status || 'pending';
        const limitInfo = `${e(r.used != null ? r.used : '—')} / ${e(r.currentLimit != null ? r.currentLimit : '—')}`;
        let actions = '<span style="color:var(--text-light)">—</span>';
        if (status === 'pending') {
            actions = `
                <button class="btn btn-sm btn-primary" onclick="Requests.approve('${id}')" title="Подтвердить (+${Requests.QUOTA_STEP})">
                    <i class="fas fa-check"></i> Подтвердить
                </button>
                <button class="btn btn-sm btn-danger" onclick="Requests.reject('${id}')" title="Отклонить">
                    <i class="fas fa-xmark"></i>
                </button>`;
        }
        return `
            <tr>
                <td data-label="Водитель"><strong>${e(r.driverName) || '—'}</strong></td>
                <td data-label="Телефон">${e(r.phone) || '—'}</td>
                <td data-label="Организация">${e(r.orgName) || '—'}</td>
                <td data-label="Лимит">${limitInfo}</td>
                <td data-label="Статус">${Requests._statusBadge(status)}</td>
                <td data-label="Действия">${actions}</td>
            </tr>
        `;
    },

    async approve(reqId) {
        try {
            const reqRef = db.collection('quotaRequests').doc(reqId);
            const reqSnap = await reqRef.get();
            if (!reqSnap.exists) { showToast('Заявка не найдена', 'error'); return; }
            const r = reqSnap.data() || {};
            if (r.status !== 'pending') { showToast('Заявка уже обработана', 'error'); Requests.load(); return; }

            const driverId = r.driverId || r.authUid;
            if (!driverId) { showToast('В заявке нет водителя', 'error'); return; }

            // Увеличиваем лимит водителя на QUOTA_STEP (по умолчанию +60).
            const driverRef = db.collection('drivers').doc(driverId);
            const driverSnap = await driverRef.get();
            const current = (driverSnap.exists && typeof driverSnap.data().waybillLimit === 'number')
                ? driverSnap.data().waybillLimit
                : (typeof r.currentLimit === 'number' ? r.currentLimit : 60);
            const newLimit = current + Requests.QUOTA_STEP;

            await driverRef.update({ waybillLimit: newLimit });
            await reqRef.update({
                status: 'approved',
                newLimit: newLimit,
                reviewedBy: Auth.currentUser.uid,
                reviewedAt: firebase.firestore.FieldValue.serverTimestamp()
            });
            showToast(`Заявка подтверждена. Новый лимит: ${newLimit} ЭПЛ`, 'success');
            Requests.load();
        } catch (e) {
            console.error('Approve request error:', e);
            showToast('Ошибка подтверждения: ' + (e.message || e.code), 'error');
        }
    },

    async reject(reqId) {
        if (!confirm('Отклонить заявку на дополнительные ЭПЛ?')) return;
        try {
            await db.collection('quotaRequests').doc(reqId).update({
                status: 'rejected',
                reviewedBy: Auth.currentUser.uid,
                reviewedAt: firebase.firestore.FieldValue.serverTimestamp()
            });
            showToast('Заявка отклонена', 'success');
            Requests.load();
        } catch (e) {
            console.error('Reject request error:', e);
            showToast('Ошибка: ' + (e.message || e.code), 'error');
        }
    }
};
