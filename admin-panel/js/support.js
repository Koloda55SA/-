// Техподдержка — чат администратора с водителями.
// Список диалогов обновляется каждые 10 с, открытый диалог — каждые 4 с
// (забираются только новые сообщения).
const Support = {
    _listStop: null,
    _chatStop: null,
    _activeId: null,
    _chats: [],
    _messages: [],
    _lastId: 0,

    init() {
        const form = document.getElementById('support-reply-form');
        if (form) form.addEventListener('submit', (e) => { e.preventDefault(); Support.sendReply(); });
    },

    _time(ms) {
        if (!ms) return '';
        return new Date(ms).toLocaleString('ru-RU', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
    },

    load() {
        if (Support._listStop) return;
        Support._listStop = poll(async () => {
            const r = await Api.get('/api/admin/support');
            const sig = JSON.stringify(r.items || []);
            if (sig === Support._sig) return;   // без изменений — не перерисовываем
            Support._sig = sig;
            Support._chats = r.items || [];
            Support.renderList();
            Support.updateUnreadBadge();
        }, 10000);
    },

    stopRealtime() {
        if (Support._listStop) { Support._listStop(); Support._listStop = null; }
        if (Support._chatStop) { Support._chatStop(); Support._chatStop = null; }
        Support._activeId = null;
        Support._chats = [];
        Support._sig = null;
    },

    updateUnreadBadge() {
        const total = Support._chats.reduce((s, c) => s + (c.id === Support._activeId ? 0 : (c.unreadForAdmin || 0)), 0);
        const badge = document.getElementById('support-unread-badge');
        if (!badge) return;
        badge.textContent = total > 99 ? '99+' : String(total);
        badge.style.display = total > 0 ? '' : 'none';
    },

    renderList() {
        const list = document.getElementById('support-list');
        if (!list) return;
        const e = escHtml;
        if (Support._chats.length === 0) {
            list.innerHTML = '<div class="support-empty" style="padding:24px;text-align:center;color:var(--text-light);">Обращений пока нет</div>';
            return;
        }
        list.innerHTML = Support._chats.map(c => {
            const unread = c.id === Support._activeId ? 0 : (c.unreadForAdmin || 0);
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
        Support._messages = [];
        Support._lastId = 0;
        Support.renderList();
        Support.updateUnreadBadge();

        document.getElementById('support-chat-placeholder').style.display = 'none';
        document.getElementById('support-chat-active').style.display = 'flex';
        const chat = Support._chats.find(c => c.id === driverId) || {};
        const e = escHtml;
        document.getElementById('support-chat-header').innerHTML = `
            <div class="support-chat-title">${e(chat.driverName) || 'Водитель'}</div>
            <div class="support-chat-sub">${e(chat.phone)} ${chat.orgName ? '· ' + e(chat.orgName) : ''}</div>`;
        document.getElementById('support-messages').innerHTML =
            '<div style="text-align:center;color:var(--text-light);padding:16px;">Загрузка…</div>';

        if (Support._chatStop) Support._chatStop();
        Support._chatStop = poll(() => Support._fetchNew(driverId), 4000);
    },

    async _fetchNew(driverId) {
        const r = await Api.get(`/api/admin/support/${encodeURIComponent(driverId)}?after=${Support._lastId}`);
        if (Support._activeId !== driverId) return;
        const fresh = r.messages || [];
        if (!fresh.length && Support._messages.length) return;
        Support._messages = Support._messages.concat(fresh);
        if (fresh.length) Support._lastId = fresh[fresh.length - 1].id;
        Support.renderMessages();
    },

    renderMessages() {
        const box = document.getElementById('support-messages');
        if (!box) return;
        if (!Support._messages.length) {
            box.innerHTML = '<div style="text-align:center;color:var(--text-light);padding:16px;">Сообщений нет</div>';
            return;
        }
        box.innerHTML = Support._messages.map(m => `
            <div class="msg ${m.sender === 'admin' ? 'msg-out' : 'msg-in'}">
                <div class="msg-bubble">${escHtml(m.text)}</div>
                <div class="msg-time">${Support._time(m.createdAt)}</div>
            </div>`).join('');
        box.scrollTop = box.scrollHeight;
    },

    async sendReply() {
        const input = document.getElementById('support-reply-input');
        const text = (input.value || '').trim();
        const driverId = Support._activeId;
        if (!text || !driverId) return;
        input.value = '';
        try {
            await Api.post('/api/admin/support/' + encodeURIComponent(driverId), { text });
            await Support._fetchNew(driverId);
        } catch (e) {
            showToast('Ошибка отправки: ' + e.message, 'error');
            input.value = text;
        }
    }
};
