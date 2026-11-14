// Клиент API: токен входа, запросы, периодическое обновление данных.
const Api = {
    TOKEN_KEY: 'asempro_token',
    token: null,

    _load() {
        try { Api.token = localStorage.getItem(Api.TOKEN_KEY); } catch (_) { Api.token = null; }
    },

    setToken(token) {
        Api.token = token || null;
        try {
            if (token) localStorage.setItem(Api.TOKEN_KEY, token);
            else localStorage.removeItem(Api.TOKEN_KEY);
        } catch (_) {}
    },

    async request(method, path, body) {
        const headers = { 'Content-Type': 'application/json' };
        if (Api.token) headers.Authorization = 'Bearer ' + Api.token;
        let res;
        try {
            res = await fetch(API_BASE + path, {
                method,
                headers,
                body: body === undefined ? undefined : JSON.stringify(body),
            });
        } catch (_) {
            const err = new Error('Нет связи с сервером');
            err.code = 'network';
            throw err;
        }
        let data = null;
        try { data = await res.json(); } catch (_) {}
        if (!res.ok) {
            const err = new Error((data && data.message) || ('Ошибка ' + res.status));
            err.code = data && data.error;
            err.status = res.status;
            // Сессия истекла или аккаунт отключён — возвращаем на страницу входа.
            if ((res.status === 401 || err.code === 'blocked') && path !== '/api/auth/login') {
                Api.setToken(null);
                if (typeof Auth !== 'undefined') Auth.onSessionLost(err);
            }
            throw err;
        }
        return data;
    },

    get(path) { return Api.request('GET', path); },
    post(path, body) { return Api.request('POST', path, body || {}); },
    put(path, body) { return Api.request('PUT', path, body || {}); },
    del(path) { return Api.request('DELETE', path); },
};
Api._load();

// Периодически вызывает fn (вместо realtime-подписок Firestore).
// Первая загрузка — всегда сразу. Пока вкладка скрыта, повторные запросы
// не делаются; при возврате на вкладку данные обновляются немедленно.
// Возвращает функцию остановки.
function poll(fn, intervalMs) {
    let stopped = false;
    let timer = null;
    let running = false;
    const run = async () => {
        if (stopped || running) return;
        running = true;
        try { await fn(); } catch (e) { console.warn('poll:', e.message || e); }
        running = false;
    };
    const tick = async () => {
        if (stopped) return;
        if (!document.hidden) await run();
        if (!stopped) timer = setTimeout(tick, intervalMs);
    };
    const onVisible = () => { if (!document.hidden) run(); };
    document.addEventListener('visibilitychange', onVisible);
    run().then(() => { if (!stopped) timer = setTimeout(tick, intervalMs); });
    return () => {
        stopped = true;
        clearTimeout(timer);
        document.removeEventListener('visibilitychange', onVisible);
    };
}

// Общий HTML-escape для всех модулей.
function escHtml(value) {
    const s = value == null ? '' : String(value);
    return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}
