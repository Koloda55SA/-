// Authentication Module
const Auth = {
    currentUser: null,

    init() {
        auth.onAuthStateChanged(async (user) => {
            if (user) {
                // Check if user is admin
                const adminDoc = await db.collection('admins').doc(user.uid).get();
                if (adminDoc.exists) {
                    Auth.currentUser = user;
                    Auth.showDashboard();
                } else {
                    auth.signOut();
                    Auth.showError('У вас нет прав администратора');
                }
            } else {
                Auth.showLogin();
            }
        });

        document.getElementById('login-form').addEventListener('submit', (e) => {
            e.preventDefault();
            Auth.login();
        });

        document.getElementById('logout-btn').addEventListener('click', () => {
            auth.signOut();
        });
    },

    async login() {
        const email = document.getElementById('login-email').value;
        const password = document.getElementById('login-password').value;

        try {
            const result = await auth.signInWithEmailAndPassword(email, password);
            // Check admin role
            const adminDoc = await db.collection('admins').doc(result.user.uid).get();
            if (!adminDoc.exists) {
                await auth.signOut();
                Auth.showError('У вас нет прав администратора');
                return;
            }
        } catch (error) {
            let message = 'Ошибка входа';
            switch (error.code) {
                case 'auth/user-not-found':
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
            }
            Auth.showError(message);
        }
    },

    showDashboard() {
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
        document.getElementById('login-page').classList.add('active');
        document.getElementById('dashboard-page').classList.remove('active');
    },

    showError(message) {
        const el = document.getElementById('login-error');
        el.textContent = message;
        setTimeout(() => { el.textContent = ''; }, 5000);
    }
};
