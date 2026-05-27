// Drivers Management Module
// - Phone+Password (через Email Auth с синтетическим email)
// - Per-driver Organization
// - Создание Firebase Auth user через secondary app, чтобы не разлогинить админа
const Drivers = {
    drivers: [],
    _secondaryApp: null,

    init() {
        document.getElementById('add-driver-form').addEventListener('submit', (e) => {
            e.preventDefault();
            Drivers.addDriver();
        });
    },

    // Нормализуем номер телефона к формату "+79991234567"
    _normalizePhone(raw) {
        let phone = String(raw || '').replace(/[\s\(\)\-]/g, '');
        if (phone.startsWith('8') && phone.length === 11) phone = '+7' + phone.substring(1);
        if (!phone.startsWith('+')) phone = '+' + phone;
        return phone;
    },

    // Email для Firebase Auth: "+79991234567" -> "79991234567@asempro.driver"
    _phoneToEmail(phoneNormalized) {
        const digits = phoneNormalized.replace(/\D/g, '');
        return `${digits}@asempro.driver`;
    },

    // Дефолтный пароль = последние 6 цифр номера
    _defaultPassword(phoneNormalized) {
        const digits = phoneNormalized.replace(/\D/g, '');
        return digits.length >= 6 ? digits.slice(-6) : digits;
    },

    // Получаем secondary Firebase app (чтобы createUser не разлогинил админа)
    _getSecondaryAuth() {
        if (!Drivers._secondaryApp) {
            Drivers._secondaryApp = firebase.initializeApp(firebaseConfig, 'driver-creator');
        }
        return Drivers._secondaryApp.auth();
    },

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

    async loadDrivers() {
        try {
            const snapshot = await db.collection('drivers').orderBy('fullName').get();
            Drivers.drivers = [];
            const tbody = document.getElementById('drivers-tbody');
            tbody.innerHTML = '';

            snapshot.forEach(doc => {
                const driver = { id: doc.id, ...doc.data() };
                Drivers.drivers.push(driver);
                tbody.insertAdjacentHTML('beforeend', Drivers.renderRow(driver));
            });

            if (Drivers.drivers.length === 0) {
                tbody.innerHTML = '<tr><td colspan="7" style="text-align:center;color:var(--text-light);padding:32px;">Нет зарегистрированных водителей</td></tr>';
            }
        } catch (error) {
            console.error('Error loading drivers:', error);
        }
    },

    renderRow(driver) {
        const e = Drivers._esc;
        const status = driver.active !== false ?
            '<span class="status-badge status-active">Активен</span>' :
            '<span class="status-badge status-inactive">Неактивен</span>';

        const id = e(driver.id);
        return `
            <tr>
                <td data-label="Водитель"><strong>${e(driver.fullName)}</strong></td>
                <td data-label="Телефон">${e(driver.phone)}</td>
                <td data-label="Авто">${e(driver.carModel)}</td>
                <td data-label="Гос. номер">${e(driver.plateNumber)}</td>
                <td data-label="Организация">${e(driver.orgName) || '—'}</td>
                <td data-label="Статус">${status}</td>
                <td data-label="Действия">
                    <button class="btn btn-sm btn-outline" onclick="Drivers.resetPassword('${id}')" title="Сбросить пароль">
                        <i class="fas fa-key"></i>
                    </button>
                    <button class="btn btn-sm btn-primary" onclick="Drivers.toggleStatus('${id}', ${driver.active !== false})">
                        <i class="fas fa-power-off"></i> ${driver.active !== false ? 'Деактив.' : 'Активир.'}
                    </button>
                    <button class="btn btn-sm btn-danger" onclick="Drivers.deleteDriver('${id}')">
                        <i class="fas fa-trash"></i>
                    </button>
                </td>
            </tr>
        `;
    },

    async addDriver() {
        const fullName = document.getElementById('driver-fullname').value.trim();
        const phoneRaw = document.getElementById('driver-phone').value.trim();
        const passwordRaw = document.getElementById('driver-password').value.trim();
        const carModel = document.getElementById('driver-car').value.trim();
        const plateNumber = document.getElementById('driver-plate').value.trim();
        const license = document.getElementById('driver-license').value.trim();
        const licenseClass = document.getElementById('driver-class').value.trim();
        const licenseIssued = document.getElementById('driver-license-issued').value;
        const licenseExpires = document.getElementById('driver-license-expires').value;
        const driverIdNumber = document.getElementById('driver-id-number').value.trim();
        const osgop = document.getElementById('driver-osgop').value.trim();
        const garageNumber = document.getElementById('driver-garage').value.trim();
        const tabNumber = document.getElementById('driver-tab').value.trim();
        const snils = document.getElementById('driver-snils').value.trim();
        const inn = document.getElementById('driver-inn').value.trim();
        const transportType = document.getElementById('driver-transport-type').value;
        const commType = document.getElementById('driver-comm-type').value;
        const orgName = document.getElementById('driver-org-name').value.trim();
        const orgOgrn = document.getElementById('driver-org-ogrn').value.trim();
        const orgInn = document.getElementById('driver-org-inn').value.trim();
        const orgPhone = document.getElementById('driver-org-phone').value.trim();
        const orgAddress = document.getElementById('driver-org-address').value.trim();
        const okud = document.getElementById('driver-okud').value.trim();
        const okpo = document.getElementById('driver-okpo').value.trim();
        const permit = document.getElementById('driver-permit').value.trim();
        const mintrans = document.getElementById('driver-mintrans').value.trim();

        const phone = Drivers._normalizePhone(phoneRaw);
        const password = passwordRaw || Drivers._defaultPassword(phone);

        if (password.length < 6) {
            showToast('Пароль должен быть не короче 6 символов', 'error');
            return;
        }
        if (phone.replace(/\D/g, '').length < 10) {
            showToast('Некорректный номер телефона', 'error');
            return;
        }

        const btn = document.querySelector('#add-driver-form button[type="submit"]');
        const originalContent = btn.innerHTML;
        btn.disabled = true;
        btn.innerHTML = '<i class="fas fa-spinner fa-spin"></i> Регистрация...';

        const email = Drivers._phoneToEmail(phone);
        const secondaryAuth = Drivers._getSecondaryAuth();

        let createdAuthUid = null;
        try {
            // 1. Создаём Firebase Auth аккаунт через secondary app (админ остаётся залогинен)
            const userCred = await secondaryAuth.createUserWithEmailAndPassword(email, password);
            createdAuthUid = userCred.user.uid;
            await secondaryAuth.signOut();

            // 2. Сохраняем профиль водителя в Firestore с тем же uid (для лёгкого lookup)
            await db.collection('drivers').doc(createdAuthUid).set({
                authUid: createdAuthUid,
                fullName,
                phone,
                authEmail: email,
                carModel,
                plateNumber,
                license,
                licenseClass,
                licenseIssued,
                licenseExpires,
                driverIdNumber,
                osgop,
                garageNumber,
                tabNumber,
                snils,
                inn,
                transportType,
                commType,
                orgName,
                orgOgrn,
                orgInn,
                orgPhone,
                orgAddress,
                okud: okud || '0345001',
                okpo,
                permit,
                mintrans: mintrans || '390 ОТ 28.09.2022',
                active: true,
                createdAt: firebase.firestore.FieldValue.serverTimestamp(),
                createdBy: Auth.currentUser.uid
            });

            showToast(`Водитель зарегистрирован. Пароль: ${password}`, 'success');
            document.getElementById('add-driver-form').reset();
            document.getElementById('driver-okud').value = '0345001';
            document.getElementById('driver-mintrans').value = '390 ОТ 28.09.2022';
            Drivers.loadDrivers();
            showSection('drivers');
        } catch (error) {
            console.error('Error adding driver:', error);
            // Откат: если Auth аккаунт создался, но Firestore-запись упала — пытаемся удалить аккаунт
            if (createdAuthUid) {
                try {
                    await secondaryAuth.signInWithEmailAndPassword(email, password);
                    await secondaryAuth.currentUser.delete();
                } catch (cleanupError) {
                    console.error('Auth cleanup failed:', cleanupError);
                }
            }
            let msg = 'Ошибка регистрации: ' + (error.message || error.code);
            if (error.code === 'auth/email-already-in-use') {
                msg = 'Водитель с таким номером телефона уже зарегистрирован';
            } else if (error.code === 'auth/weak-password') {
                msg = 'Слишком слабый пароль (минимум 6 символов)';
            } else if (error.code === 'auth/operation-not-allowed') {
                msg = 'В Firebase Console не включён Email/Password Authentication';
            }
            showToast(msg, 'error');
        } finally {
            btn.disabled = false;
            btn.innerHTML = originalContent;
        }
    },

    async resetPassword(driverId) {
        const driver = Drivers.drivers.find(d => d.id === driverId);
        if (!driver) return;
        const newPwd = prompt(`Новый пароль для ${driver.fullName} (минимум 6 символов).\nОставьте пустым для использования последних 6 цифр номера:`);
        if (newPwd === null) return; // Отмена
        const phone = Drivers._normalizePhone(driver.phone);
        const password = newPwd.trim() || Drivers._defaultPassword(phone);
        if (password.length < 6) {
            showToast('Пароль должен быть не короче 6 символов', 'error');
            return;
        }
        try {
            // Через secondary app: входим со старым паролем не получится (мы его не знаем).
            // Поэтому пишем заявку на сброс, которую обработает Cloud Function (или вручную через Firebase Console).
            await db.collection('passwordResets').add({
                driverId: driver.id,
                authEmail: driver.authEmail || Drivers._phoneToEmail(phone),
                newPassword: password,
                requestedBy: Auth.currentUser.uid,
                requestedAt: firebase.firestore.FieldValue.serverTimestamp(),
                status: 'pending'
            });
            showToast(`Заявка на смену пароля создана. Новый пароль: ${password}\n(Применит Cloud Function или админ вручную)`, 'success');
        } catch (e) {
            console.error('Reset password error:', e);
            showToast('Ошибка: ' + e.message, 'error');
        }
    },

    async toggleStatus(driverId, currentStatus) {
        try {
            await db.collection('drivers').doc(driverId).update({
                active: !currentStatus
            });
            Drivers.loadDrivers();
            showToast('Статус обновлён', 'success');
        } catch (error) {
            showToast('Ошибка обновления статуса', 'error');
        }
    },

    async deleteDriver(driverId) {
        if (!confirm('Удалить водителя? Это действие нельзя отменить.')) return;

        try {
            // Помечаем для удаления Auth-аккаунта (Cloud Function подхватит)
            await db.collection('driverDeletions').add({
                driverId,
                authUid: driverId,
                requestedBy: Auth.currentUser.uid,
                requestedAt: firebase.firestore.FieldValue.serverTimestamp()
            });
            await db.collection('drivers').doc(driverId).delete();
            Drivers.loadDrivers();
            showToast('Водитель удалён', 'success');
        } catch (error) {
            showToast('Ошибка удаления: ' + error.message, 'error');
        }
    }
};
