// Authentication Module
const Auth = {
    currentUser: null,
    _bootDone: false,

    init() {
        // Если знаем что юзер был админом — сразу показываем дашборд (без ожидания Firebase)
        const cachedAdmin = localStorage.getItem('asempro_admin');
        if (cachedAdmin) {
            try {
                const cached = JSON.parse(cachedAdmin);
                if (cached && cached.email) {
                    Auth._showDashboardShell(cached.email);
                }
            } catch (_) {}
        }

        auth.onAuthStateChanged(async (user) => {
            if (user) {
                try {
                    const adminDoc = await db.collection('admins').doc(user.uid).get();
                    if (adminDoc.exists) {
                        Auth.currentUser = user;
                        localStorage.setItem('asempro_admin', JSON.stringify({
                            uid: user.uid,
                            email: user.email
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
            Auth.login();
        });

        document.getElementById('logout-btn').addEventListener('click', async () => {
            localStorage.removeItem('asempro_admin');
            await auth.signOut();
        });

        // Если через 6 секунд Firebase не ответил — показываем логин (защита от зависания)
        setTimeout(() => {
            if (!Auth._bootDone && !Auth.currentUser) {
                Auth.showLogin();
            }
        }, 6000);
    },

    async login() {
        const email = document.getElementById('login-email').value;
        const password = document.getElementById('login-password').value;
        const btn = document.querySelector('#login-form button[type="submit"]');
        const originalContent = btn.innerHTML;
        btn.disabled = true;
        btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Вход...';

        try {
            const result = await auth.signInWithEmailAndPassword(email, password);
            const adminDoc = await db.collection('admins').doc(result.user.uid).get();
            if (!adminDoc.exists) {
                await auth.signOut();
                Auth.showError('У вас нет прав администратора');
                return;
            }
            // onAuthStateChanged покажет дашборд
        } catch (error) {
            let message = 'Ошибка входа';
            switch (error.code) {
                case 'auth/user-not-found':
                case 'auth/invalid-credential':
                    message = 'Пользователь не найден';
                    break;
                case 'auth/wrong-password':
                    message = 'Неверный пароль';
                    break;
                case 'auth/invalid-email':
                    message = 'Некорректный email';
                    break;
                case 'auth/too-many-requests':
                    message = 'Слишком много попыток. Попробуйте позже';
                    break;
                case 'auth/network-request-failed':
                    message = 'Нет соединения с интернетом';
                    break;
            }
            Auth.showError(message);
        } finally {
            btn.disabled = false;
            btn.innerHTML = originalContent;
        }
    },

    /** Быстрый показ оболочки дашборда из кэша до проверки Firebase */
    _showDashboardShell(email) {
        document.getElementById('loading-page').classList.remove('active');
        document.getElementById('login-page').classList.remove('active');
        document.getElementById('dashboard-page').classList.add('active');
        document.getElementById('admin-email').textContent = email;
        const sidebarEmail = document.getElementById('admin-email-sidebar');
        if (sidebarEmail) sidebarEmail.textContent = email;
    },

    showDashboard() {
        document.getElementById('loading-page').classList.remove('active');
        document.getElementById('login-page').classList.remove('active');
        document.getElementById('dashboard-page').classList.add('active');
        document.getElementById('admin-email').textContent = Auth.currentUser.email;
        const sidebarEmail = document.getElementById('admin-email-sidebar');
        if (sidebarEmail) sidebarEmail.textContent = Auth.currentUser.email;
        Drivers.loadDrivers();
        Waybills.loadWaybills();
        Settings.loadSettings();
        updateDashboard();
    },

    showLogin() {
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
