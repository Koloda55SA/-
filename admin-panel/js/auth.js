// Authentication Module - Phone Auth
const Auth = {
    currentUser: null,
    _bootDone: false,
    _confirmationResult: null,
    _recaptchaVerifier: null,
    _recaptchaRendered: false,

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
                        localStorage.setItem('asempro_admin', JSON.stringify({
                            uid: user.uid,
                            phone: user.phoneNumber || user.email || 'Admin'
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

        setTimeout(() => {
            if (!Auth._bootDone && !Auth.currentUser) {
                Auth.showLogin();
            }
        }, 6000);
    },

    _ensureRecaptcha() {
        if (Auth._recaptchaVerifier) return;
        Auth._recaptchaVerifier = new firebase.auth.RecaptchaVerifier('recaptcha-container-login', {
            size: 'invisible',
            callback: () => {}
        });
    },

    async handleLogin() {
        const codeInput = document.getElementById('login-code');
        if (Auth._confirmationResult && codeInput.value.trim()) {
            await Auth.verifyCode();
        } else {
            await Auth.sendSms();
        }
    },

    _formatPhone(raw) {
        let phone = raw.replace(/[\s\(\)\-]/g, '');
        if (phone.startsWith('8') && phone.length === 11) {
            phone = '+7' + phone.substring(1);
        }
        if (!phone.startsWith('+')) phone = '+' + phone;
        return phone;
    },

    async sendSms() {
        const phoneRaw = document.getElementById('login-phone').value;
        const phone = Auth._formatPhone(phoneRaw);
        const btn = document.getElementById('login-btn');
        const originalContent = btn.innerHTML;
        btn.disabled = true;
        btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Отправка...';

        try {
            Auth._ensureRecaptcha();
            Auth._confirmationResult = await auth.signInWithPhoneNumber(phone, Auth._recaptchaVerifier);
            document.getElementById('sms-code-group').style.display = 'block';
            document.getElementById('login-btn-text').textContent = 'Подтвердить код';
            document.getElementById('login-code').focus();
        } catch (error) {
            console.error('SMS error:', error);
            let message = 'Ошибка отправки SMS';
            if (error.code === 'auth/invalid-phone-number') {
                message = 'Некорректный номер телефона';
            } else if (error.code === 'auth/too-many-requests') {
                message = 'Слишком много попыток. Попробуйте позже';
            } else if (error.code === 'auth/captcha-check-failed') {
                message = 'Ошибка проверки. Обновите страницу';
            }
            Auth.showError(message);
            Auth._recaptchaVerifier = null;
        } finally {
            btn.disabled = false;
            btn.innerHTML = originalContent;
        }
    },

    async verifyCode() {
        const code = document.getElementById('login-code').value.trim();
        if (!code || code.length < 6) {
            Auth.showError('Введите 6-значный код из SMS');
            return;
        }
        const btn = document.getElementById('login-btn');
        const originalContent = btn.innerHTML;
        btn.disabled = true;
        btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Проверка...';

        try {
            const result = await Auth._confirmationResult.confirm(code);
            const adminDoc = await db.collection('admins').doc(result.user.uid).get();
            if (!adminDoc.exists) {
                await auth.signOut();
                Auth.showError('У вас нет прав администратора. Обратитесь к владельцу.');
                Auth._confirmationResult = null;
                document.getElementById('sms-code-group').style.display = 'none';
                document.getElementById('login-btn-text').textContent = 'Отправить SMS';
                return;
            }
        } catch (error) {
            console.error('Code verify error:', error);
            let message = 'Неверный код';
            if (error.code === 'auth/invalid-verification-code') {
                message = 'Неверный код из SMS';
            } else if (error.code === 'auth/code-expired') {
                message = 'Код истёк. Отправьте SMS заново';
                Auth._confirmationResult = null;
                document.getElementById('sms-code-group').style.display = 'none';
                document.getElementById('login-btn-text').textContent = 'Отправить SMS';
            }
            Auth.showError(message);
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
        const display = Auth.currentUser.phoneNumber || Auth.currentUser.email || 'Admin';
        document.getElementById('admin-email').textContent = display;
        const sidebarEl = document.getElementById('admin-email-sidebar');
        if (sidebarEl) sidebarEl.textContent = display;
        Drivers.loadDrivers();
        Waybills.loadWaybills();
        Settings.loadSettings();
        updateDashboard();
    },

    showLogin() {
        document.getElementById('loading-page').classList.remove('active');
        document.getElementById('login-page').classList.add('active');
        document.getElementById('dashboard-page').classList.remove('active');
        Auth._confirmationResult = null;
        document.getElementById('sms-code-group').style.display = 'none';
        document.getElementById('login-btn-text').textContent = 'Отправить SMS';
    },

    showError(message) {
        const el = document.getElementById('login-error');
        el.textContent = message;
        setTimeout(() => { el.textContent = ''; }, 5000);
    }
};
