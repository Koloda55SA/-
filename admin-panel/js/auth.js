// Вход на сайт по телефону и паролю (сервер AsemPro API на Cloudflare).
// Роли: 'admin' — владелец/администратор; 'medic' и 'mechanic' — видят только «Допуск».
// Первого администратора создаёт POST /api/bootstrap (см. cloudflare-api/README.md),
// остальных сотрудников — администратор в разделе «Сотрудники».
const Auth = {
    currentUser: null,   // { id, role, phone, fullName, certSerial, ... }
    role: 'admin',
    profile: {},
    CACHE_KEY: 'asempro_admin',

    ROLE_LABELS: { admin: 'Администратор', medic: 'Медик', mechanic: 'Мастер' },

    isAdmin() { return Auth.role === 'admin'; },

    _applyRoleUI(role) {
        document.body.dataset.role = role;
    },

    _cache(value) {
        try {
            if (value) localStorage.setItem(Auth.CACHE_KEY, JSON.stringify(value));
            else localStorage.removeItem(Auth.CACHE_KEY);
        } catch (_) {}
    },

    init() {
        document.getElementById('login-form').addEventListener('submit', (e) => {
            e.preventDefault();
            Auth.handleLogin();
        });
        document.getElementById('logout-btn').addEventListener('click', () => Auth.logout());

        if (!Api.token) {
            Auth.showLogin();
            return;
        }
        // Пока проверяем сессию на сервере — сразу показываем оболочку из кэша.
        try {
            const cached = JSON.parse(localStorage.getItem(Auth.CACHE_KEY) || 'null');
            if (cached && cached.display) {
                Auth.role = cached.role || 'admin';
                Auth._applyRoleUI(Auth.role);
                Auth._showDashboardShell(cached.display);
            }
        } catch (_) {}
        Auth.restore();
    },

    async restore() {
        try {
            const me = await Api.get('/api/me');
            Auth._signedIn(me.user);
        } catch (e) {
            if (e.code === 'network') {
                Auth.showLogin();
                Auth.showError('Нет связи с сервером. Обновите страницу.');
            }
            // 401/blocked обрабатывает Api → onSessionLost.
        }
    },

    _signedIn(user) {
        if (!Auth.ROLE_LABELS[user.role]) {
            Api.setToken(null);
            Auth.showLogin();
            Auth.showError('У вас нет доступа к этому сайту');
            return;
        }
        Auth.currentUser = user;
        Auth.role = user.role;
        Auth.profile = user;
        const display = user.fullName || user.phone || 'Admin';
        Auth._cache({ id: user.id, display, role: user.role });
        Auth.showDashboard();
    },

    // Приводим номер телефона к виду "+79991234567"
    _formatPhone(raw) {
        let phone = String(raw || '').replace(/[\s\(\)\-]/g, '');
        if (phone.startsWith('8') && phone.length === 11) phone = '+7' + phone.substring(1);
        // 10 цифр без кода страны (9991234567) — российский номер.
        if (/^9\d{9}$/.test(phone)) phone = '+7' + phone;
        if (!phone.startsWith('+')) phone = '+' + phone;
        return phone;
    },

    async handleLogin() {
        const phone = Auth._formatPhone(document.getElementById('login-phone').value);
        const password = (document.getElementById('login-password').value || '').trim();
        if (phone.replace(/\D/g, '').length < 10) { Auth.showError('Введите корректный номер телефона'); return; }
        if (password.length < 6) { Auth.showError('Пароль должен быть не короче 6 символов'); return; }

        const btn = document.getElementById('login-btn');
        const originalContent = btn.innerHTML;
        btn.disabled = true;
        btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Вход...';
        try {
            const r = await Api.post('/api/auth/login', { phone, password, scope: 'staff' });
            Api.setToken(r.token);
            document.getElementById('login-password').value = '';
            Auth._signedIn(r.user);
        } catch (e) {
            Auth.showError(e.message || 'Ошибка входа');
        } finally {
            btn.disabled = false;
            btn.innerHTML = originalContent;
        }
    },

    async logout() {
        try { await Api.post('/api/auth/logout'); } catch (_) {}
        Api.setToken(null);
        Auth._cache(null);
        Auth.showLogin();
    },

    // Сервер ответил «не авторизован» / «аккаунт отключён».
    onSessionLost(err) {
        Auth._cache(null);
        Auth.showLogin();
        Auth.showError(err && err.code === 'blocked' ? 'Аккаунт отключён' : 'Сессия истекла — войдите снова');
    },

    _showDashboardShell(display) {
        document.getElementById('loading-page').classList.remove('active');
        document.getElementById('login-page').classList.remove('active');
        document.getElementById('dashboard-page').classList.add('active');
        document.getElementById('admin-email').textContent = display;
        const sidebarEl = document.getElementById('admin-email-sidebar');
        if (sidebarEl) sidebarEl.textContent = display;
        if (Auth.role !== 'admin' && typeof showSection === 'function') showSection('checks');
    },

    showDashboard() {
        Auth._applyRoleUI(Auth.role);
        let display = Auth.currentUser.fullName || Auth.currentUser.phone || 'Admin';
        if (!Auth.isAdmin()) display += ' · ' + Auth.ROLE_LABELS[Auth.role];
        Auth._showDashboardShell(display);

        // Очередь на допуск нужна всем ролям (бейдж в меню).
        Checks.load();
        if (!Auth.isAdmin()) {
            showSection('checks');
            return;
        }
        Drivers.loadDrivers();
        Settings.loadSettings();
        if (typeof Support !== 'undefined') Support.load();
        updateDashboard();
    },

    showLogin() {
        // Останавливаем все периодические обновления.
        [Drivers, Waybills,
         (typeof Support !== 'undefined' ? Support : null),
         (typeof Accounting !== 'undefined' ? Accounting : null),
         (typeof Checks !== 'undefined' ? Checks : null),
         (typeof Staff !== 'undefined' ? Staff : null)]
            .forEach(m => { if (m && typeof m.stopRealtime === 'function') m.stopRealtime(); });
        Auth.currentUser = null;
        Auth.role = 'admin';
        Auth.profile = {};
        document.getElementById('loading-page').classList.remove('active');
        document.getElementById('login-page').classList.add('active');
        document.getElementById('dashboard-page').classList.remove('active');
    },

    showError(message) {
        const el = document.getElementById('login-error');
        el.textContent = message;
        setTimeout(() => { el.textContent = ''; }, 5000);
    }
};
