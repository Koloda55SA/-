// Техподдержка — чат админа с водителями.
// Модель данных:
//   supportChats/{driverId}                — мета диалога (последнее сообщение, непрочитанные)
//   supportChats/{driverId}/messages/{id}  — сообщения { sender: 'driver'|'admin', text, createdAt }
// Водитель пишет из приложения; админ отвечает здесь. Всё в реальном времени.
const Support = {
    _listUnsub: null,
    _chatUnsub: null,
    _activeId: null,
    _chats: [],

    init() {
        const form = document.getElementById('support-reply-form');
        if (form) {
            form.addEventListener('submit', (e) => {
                e.preventDefault();
                Support.sendReply();
            });
        }
    },

    _esc(value) {
        const s = value == null ? '' : String(value);
        return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
                .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
    },

    _time(ts) {
        if (!ts || !ts.seconds) return '';
        const d = new Date(ts.seconds * 1000);
        return d.toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
    },

    // Живая подписка на список диалогов (по дате последнего сообщения).
    load() {
        if (Support._listUnsub) return;
        Support._listUnsub = db.collection('supportChats')
            .orderBy('lastMessageAt', 'desc')
            .onSnapshot(snapshot => {
                Support._chats = [];
                snapshot.forEach(doc => Support._chats.push({ id: doc.id, ...doc.data() }));
                Support.renderList();
                Support.updateUnreadBadge();
            }, err => {
                console.error('Support list onSnapshot error:', err);
                const list = document.getElementById('support-list');
                if (list) list.innerHTML = '<div class="support-empty" style="padding:24px;text-align:center;color:#ef4444;">Ошибка загрузки</div>';
            });
    },

    stopRealtime() {
        if (Support._listUnsub) { Support._listUnsub(); Support._listUnsub = null; }
        if (Support._chatUnsub) { Support._chatUnsub(); Support._chatUnsub = null; }
        Support._activeId = null;
    },

    // Сумма непрочитанных админом — для бейджа в меню.
    updateUnreadBadge() {
        const total = Support._chats.reduce((s, c) => s + (c.unreadForAdmin || 0), 0);
        const badge = document.getElementById('support-unread-badge');
        if (!badge) return;
        if (total > 0) {
            badge.textContent = total > 99 ? '99+' : String(total);
            badge.style.display = '';
        } else {
            badge.style.display = 'none';
        }
    },

    renderList() {
        const list = document.getElementById('support-list');
        if (!list) return;
        const e = Support._esc;
        if (Support._chats.length === 0) {
            list.innerHTML = '<div class="support-empty" style="padding:24px;text-align:center;color:var(--text-light);">Обращений пока нет</div>';
            return;
        }
        list.innerHTML = Support._chats.map(c => {
            const unread = c.unreadForAdmin || 0;
            const active = c.id === Support._activeId ? ' active' : '';
            const badge = unread > 0 ? `<span class="support-item-badge">${unread > 99 ? '99+' : unread}</span>` : '';
            return `
                <div class="support-item${active}" onclick="Support.openChat('${e(c.id)}')">
                    <div class="support-item-top">
                        <span class="support-item-name">${e(c.driverName) || 'Водитель'}</span>
                        <span class="support-item-time">${Support._time(c.lastMessageAt)}</span>
                    </div>
                    <div class="support-item-bottom">
                        <span class="support-item-last">${(c.lastSender === 'admin' ? 'Вы: ' : '') + (e(c.lastMessage) || '—')}</span>
                        ${badge}
                    </div>
                </div>`;
        }).join('');
    },

    openChat(driverId) {
        Support._activeId = driverId;
        Support.renderList();

        document.getElementById('support-chat-placeholder').style.display = 'none';
        document.getElementById('support-chat-active').style.display = 'flex';

        const chat = Support._chats.find(c => c.id === driverId) || {};
        const e = Support._esc;
        document.getElementById('support-chat-header').innerHTML = `
            <div class="support-chat-title">${e(chat.driverName) || 'Водитель'}</div>
            <div class="support-chat-sub">${e(chat.phone) || ''} ${chat.orgName ? '· ' + e(chat.orgName) : ''}</div>`;

        // Сбрасываем счётчик непрочитанных админом.
        db.collection('supportChats').doc(driverId)
            .set({ unreadForAdmin: 0 }, { merge: true })
            .catch(err => console.warn('reset unread failed', err));

        // Подписка на сообщения активного диалога.
        if (Support._chatUnsub) { Support._chatUnsub(); Support._chatUnsub = null; }
        const box = document.getElementById('support-messages');
        box.innerHTML = '<div style="text-align:center;color:var(--text-light);padding:16px;">Загрузка…</div>';
        Support._chatUnsub = db.collection('supportChats').doc(driverId)
            .collection('messages').orderBy('createdAt', 'asc')
            .onSnapshot(snap => {
                if (snap.empty) { box.innerHTML = '<div style="text-align:center;color:var(--text-light);padding:16px;">Сообщений нет</div>'; return; }
                box.innerHTML = snap.docs.map(d => {
                    const m = d.data() || {};
                    const mine = m.sender === 'admin';
                    return `
                        <div class="msg ${mine ? 'msg-out' : 'msg-in'}">
                            <div class="msg-bubble">${e(m.text)}</div>
                            <div class="msg-time">${Support._time(m.createdAt)}</div>
                        </div>`;
                }).join('');
                box.scrollTop = box.scrollHeight;
            }, err => {
                console.error('Support chat onSnapshot error:', err);
                box.innerHTML = '<div style="text-align:center;color:#ef4444;padding:16px;">Ошибка загрузки сообщений</div>';
            });
    },

    async sendReply() {
        const input = document.getElementById('support-reply-input');
        const text = (input.value || '').trim();
        if (!text || !Support._activeId) return;
        input.value = '';
        const driverId = Support._activeId;
        try {
            await db.collection('supportChats').doc(driverId)
                .collection('messages').add({
                    sender: 'admin',
                    text,
                    senderName: 'Поддержка',
                    createdAt: firebase.firestore.FieldValue.serverTimestamp()
                });
            await db.collection('supportChats').doc(driverId).set({
                lastMessage: text,
                lastSender: 'admin',
                lastMessageAt: firebase.firestore.FieldValue.serverTimestamp(),
                unreadForAdmin: 0,
                unreadForDriver: firebase.firestore.FieldValue.increment(1),
                updatedAt: firebase.firestore.FieldValue.serverTimestamp()
            }, { merge: true });
        } catch (e) {
            console.error('Support reply error:', e);
            showToast('Ошибка отправки: ' + (e.message || e.code), 'error');
            input.value = text;
        }
    }
};
