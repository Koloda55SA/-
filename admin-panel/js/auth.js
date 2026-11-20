// Authentication Module — Phone + Password (БЕЗ SMS)
//
// Админ входит по номеру телефона и паролю, который он сам себе задал
// в Firebase Console. Под капотом, как и у водителей, используется
// Firebase Email Auth с синтетическим email:
//
//     <digits>@asempro.admin       (например, 79153955383@asempro.admin)
//
// Чтобы создать первого администратора:
//   1. Firebase Console → Authentication → Users → Add user
//      Email:    <digits>@asempro.admin   (цифры номера без + и пробелов)
//      Password: любой ≥ 6 символов
//   2. Скопируйте UID созданного пользователя
//   3. Firestore → admins → создайте документ с ID = этот UID:
//      {
//        phone:     "+7...",
//        role:      "admin",
//        createdAt: <timestamp>
//      }
//
// После этого администратор входит по своему номеру + паролю.
const Auth = {
    currentUser: null,
    // Роль из admins/{uid}.role: 'admin' (по умолчанию) | 'medic' | 'mechanic'.
    role: 'admin',
    // Профиль сотрудника (ФИО и данные сертификата — для отметки допуска).
    profile: {},
    _bootDone: false,

    ROLE_LABELS: { admin: 'Администратор', medic: 'Медик', mechanic: 'Мастер' },

    isAdmin() { return Auth.role === 'admin'; },

    // Показывает только разрешённые роли разделы меню.
    _applyRoleUI(role) {
        document.body.dataset.role = role;
    },

    init() {
        const cachedAdmin = localStorage.getItem('asempro_admin');
        if (cachedAdmin) {
            try {
                const cached = JSON.parse(cachedAdmin);
                if (cached && cached.phone) {
                    Auth.role = cached.role || 'admin';
                    Auth._applyRoleUI(Auth.role);
                    Auth._showDashboardShell(cached.phone);
                }
            } catch (_) {}
        }

        auth.onAuthStateChanged(async (user) => {
            if (user) {
                try {
                    const adminDoc = await db.collection('admins').doc(user.uid).get();
                    if (adminDoc.exists) {
                        Auth.currentUser = user;
                        const adminData = adminDoc.data() || {};
                        Auth.role = Auth.ROLE_LABELS[adminData.role] ? adminData.role : 'admin';
                        Auth.profile = adminData;
                        const display = adminData.fullName || adminData.phone || user.email || 'Admin';
                        localStorage.setItem('asempro_admin', JSON.stringify({
                            uid: user.uid,
                            phone: display,
                            role: Auth.role
                        }));
                        Auth.showDashboard();
                    } else {
                        localStorage.removeItem('asempro_admin');
                        await auth.signOut();
                        Auth.showLogin();
                        Auth.showError('У вас нет прав администратора');
                    }
                } catch (e) {
                    console.error('Auth check error:', e);
                    Auth.showLogin();
                }
            } else {
                localStorage.removeItem('asempro_admin');
                Auth.showLogin();
            }
            Auth._bootDone = true;
        });

        document.getElementById('login-form').addEventListener('submit', (e) => {
            e.preventDefault();
            Auth.handleLogin();
        });
        document.getElementById('login-form').addEventListener('input', () => {
            Auth.showError('');
        });

        document.getElementById('logout-btn').addEventListener('click', async () => {
            localStorage.removeItem('asempro_admin');
            await auth.signOut();
        });

        // Если за 6 секунд auth не успел инициализироваться — показываем форму
        setTimeout(() => {
            if (!Auth._bootDone && !Auth.currentUser) {
                Auth.showLogin();
            }
        }, 6000);
    },

    // Приводим номер телефона к виду "+79991234567"
    _formatPhone(raw) {
        let phone = String(raw || '').replace(/[\s\(\)\-]/g, '');
        if (phone.startsWith('8') && phone.length === 11) {
            phone = '+7' + phone.substring(1);
        }
        // 10 цифр без кода страны (9991234567) — российский номер.
        if (/^9\d{9}$/.test(phone)) phone = '+7' + phone;
        if (!phone.startsWith('+')) phone = '+' + phone;
        return phone;
    },

    // "+79991234567" -> "79991234567@asempro.admin"
    _phoneToAdminEmail(normalizedPhone) {
        const digits = normalizedPhone.replace(/\D/g, '');
        return `${digits}@asempro.admin`;
    },

    async handleLogin() {
        const btn = document.getElementById('login-btn');
        if (btn.disabled) return;
        const phoneRaw = document.getElementById('login-phone').value;
        const password = document.getElementById('login-password').value;
        const phone = Auth._formatPhone(phoneRaw);

        if (!/^\+\d{10,15}$/.test(phone)) {
            Auth.showError('Введите корректный номер телефона');
            return;
        }
        if (!password) {
            Auth.showError('Введите пароль');
            return;
        }

        const originalContent = btn.innerHTML;
        Auth.showError('');
        btn.disabled = true;
        btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Вход...';

        try {
            const email = Auth._phoneToAdminEmail(phone);
            await auth.signInWithEmailAndPassword(email, password);
            // onAuthStateChanged выше проверит /admins/<uid> и переключит на dashboard
        } catch (error) {
            console.error('Admin login error:', error);
            let msg = 'Ошибка входа';
            switch (error.code) {
                case 'auth/invalid-credential':
                case 'auth/wrong-password':
                case 'auth/user-not-found':
                    msg = 'Неверный номер или пароль';
                    break;
                case 'auth/invalid-email':
                    msg = 'Некорректный номер телефона';
                    break;
                case 'auth/user-disabled':
                    msg = 'Аккаунт отключён';
                    break;
                case 'auth/too-many-requests':
                    msg = 'Firebase временно ограничил вход после нескольких попыток. Попробуйте позже. Если пароль забыт, обратитесь к администратору.';
                    break;
                case 'auth/network-request-failed':
                    msg = 'Нет соединения с интернетом';
                    break;
                case 'auth/operation-not-allowed':
                    msg = 'В Firebase Console не включён Email/Password Authentication';
                    break;
            }
            Auth.showError(msg);
        } finally {
            btn.disabled = false;
            btn.innerHTML = originalContent;
        }
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
        document.getElementById('loading-page').classList.remove('active');
        document.getElementById('login-page').classList.remove('active');
        document.getElementById('dashboard-page').classList.add('active');
        Auth._applyRoleUI(Auth.role);
        // Подпись в шапке/сайдбаре: ФИО или телефон из admins-документа,
        // иначе email (без @asempro.admin) или просто "Admin".
        let display = 'Admin';
        try {
            const cached = JSON.parse(localStorage.getItem('asempro_admin') || '{}');
            if (cached && cached.phone) display = cached.phone;
        } catch (_) {}
        if (display === 'Admin' && Auth.currentUser?.email) {
            display = Auth.currentUser.email.split('@')[0];
        }
        if (!Auth.isAdmin()) display += ' · ' + Auth.ROLE_LABELS[Auth.role];
        document.getElementById('admin-email').textContent = display;
        const sidebarEl = document.getElementById('admin-email-sidebar');
        if (sidebarEl) sidebarEl.textContent = display;

        // Очередь на допуск нужна всем ролям (бейдж в меню).
        Checks.renderAutoIssue();
        Checks.load();
        if (!Auth.isAdmin()) {
            // Медик/мастер видят только раздел «Допуск».
            showSection('checks');
            return;
        }
        Drivers.loadDrivers();
        Waybills.loadWaybills();
        Settings.loadSettings();
        updateDashboard();
    },

    showLogin() {
        // Снимаем все realtime-подписки, чтобы после выхода не сыпались
        // ошибки прав доступа (permission-denied).
        [Drivers, Waybills, Requests,
         (typeof Support !== 'undefined' ? Support : null),
         (typeof Accounting !== 'undefined' ? Accounting : null),
         (typeof Checks !== 'undefined' ? Checks : null),
         (typeof Staff !== 'undefined' ? Staff : null)]
            .forEach(m => { if (m && typeof m.stopRealtime === 'function') m.stopRealtime(); });
        Auth.role = 'admin';
        Auth.currentUser = null;
        Auth.profile = {};
        if (typeof Checks !== 'undefined') Checks.renderAutoIssue();
        document.getElementById('loading-page').classList.remove('active');
        document.getElementById('login-page').classList.add('active');
        document.getElementById('dashboard-page').classList.remove('active');
    },

    showError(message) {
        document.getElementById('login-error').textContent = message;
    }
};
