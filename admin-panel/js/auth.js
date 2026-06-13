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
    _bootDone: false,

    init() {
        const cachedAdmin = localStorage.getItem('asempro_admin');
        if (cachedAdmin) {
            try {
                const cached = JSON.parse(cachedAdmin);
                if (cached && cached.phone) {
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
                        const display = adminData.phone || user.email || 'Admin';
                        localStorage.setItem('asempro_admin', JSON.stringify({
                            uid: user.uid,
                            phone: display
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
        if (!phone.startsWith('+')) phone = '+' + phone;
        return phone;
    },

    // "+79991234567" -> "79991234567@asempro.admin"
    _phoneToAdminEmail(normalizedPhone) {
        const digits = normalizedPhone.replace(/\D/g, '');
        return `${digits}@asempro.admin`;
    },

    async handleLogin() {
        const phoneRaw = document.getElementById('login-phone').value;
        const password = (document.getElementById('login-password').value || '').trim();
        const phone = Auth._formatPhone(phoneRaw);

        if (phone.replace(/\D/g, '').length < 10) {
            Auth.showError('Введите корректный номер телефона');
            return;
        }
        if (password.length < 6) {
            Auth.showError('Пароль должен быть не короче 6 символов');
            return;
        }

        const btn = document.getElementById('login-btn');
        const originalContent = btn.innerHTML;
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
                    msg = 'Слишком много попыток. Попробуйте позже';
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
    },

    showDashboard() {
        document.getElementById('loading-page').classList.remove('active');
        document.getElementById('login-page').classList.remove('active');
        document.getElementById('dashboard-page').classList.add('active');
        // Подпись в шапке/сайдбаре: пытаемся достать phone из admins-документа,
        // иначе показываем email (без @asempro.admin) или просто "Admin".
        let display = 'Admin';
        try {
            const cached = JSON.parse(localStorage.getItem('asempro_admin') || '{}');
            if (cached && cached.phone) display = cached.phone;
        } catch (_) {}
        if (display === 'Admin' && Auth.currentUser?.email) {
            display = Auth.currentUser.email.split('@')[0];
        }
        document.getElementById('admin-email').textContent = display;
        const sidebarEl = document.getElementById('admin-email-sidebar');
        if (sidebarEl) sidebarEl.textContent = display;
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
         (typeof Accounting !== 'undefined' ? Accounting : null)]
            .forEach(m => { if (m && typeof m.stopRealtime === 'function') m.stopRealtime(); });
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
