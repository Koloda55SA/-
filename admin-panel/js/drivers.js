// Drivers Management Module
const Drivers = {
    drivers: [],

    init() {
        document.getElementById('add-driver-form').addEventListener('submit', (e) => {
            e.preventDefault();
            Drivers.addDriver();
        });
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
                tbody.innerHTML += Drivers.renderRow(driver);
            });

            if (Drivers.drivers.length === 0) {
                tbody.innerHTML = '<tr><td colspan="6" style="text-align:center;color:#64748b;padding:32px;">Нет зарегистрированных водителей</td></tr>';
            }
        } catch (error) {
            console.error('Error loading drivers:', error);
        }
    },

    renderRow(driver) {
        const status = driver.active !== false ? 
            '<span class="status-badge status-active">Активен</span>' : 
            '<span class="status-badge status-inactive">Неактивен</span>';
        
        return `
            <tr>
                <td><strong>${driver.fullName || ''}</strong></td>
                <td>${driver.phone || ''}</td>
                <td>${driver.carModel || ''}</td>
                <td>${driver.plateNumber || ''}</td>
                <td>${status}</td>
                <td>
                    <button class="btn btn-sm btn-primary" onclick="Drivers.toggleStatus('${driver.id}', ${driver.active !== false})">
                        ${driver.active !== false ? 'Деактивировать' : 'Активировать'}
                    </button>
                    <button class="btn btn-sm btn-danger" onclick="Drivers.deleteDriver('${driver.id}')">
                        <i class="fas fa-trash"></i>
                    </button>
                </td>
            </tr>
        `;
    },

    async addDriver() {
        const fullName = document.getElementById('driver-fullname').value;
        const phone = document.getElementById('driver-phone').value;
        const email = document.getElementById('driver-email').value;
        const password = document.getElementById('driver-password').value;
        const carModel = document.getElementById('driver-car').value;
        const plateNumber = document.getElementById('driver-plate').value;
        const license = document.getElementById('driver-license').value;
        const licenseClass = document.getElementById('driver-class').value;
        const licenseIssued = document.getElementById('driver-license-issued').value;
        const licenseExpires = document.getElementById('driver-license-expires').value;
        const driverIdNumber = document.getElementById('driver-id-number').value;
        const osgop = document.getElementById('driver-osgop').value;
        const garageNumber = document.getElementById('driver-garage').value;
        const tabNumber = document.getElementById('driver-tab').value;
        const snils = document.getElementById('driver-snils').value;
        const inn = document.getElementById('driver-inn').value;
        const transportType = document.getElementById('driver-transport-type').value;
        const commType = document.getElementById('driver-comm-type').value;

        try {
            // Create driver account using secondary Firebase app
            // This prevents signing out the current admin
            const secondaryApp = firebase.initializeApp(firebaseConfig, 'secondary_' + Date.now());
            const secondaryAuth = secondaryApp.auth();

            const userCredential = await secondaryAuth.createUserWithEmailAndPassword(email, password);
            const driverUid = userCredential.user.uid;

            // Sign out from secondary and delete it
            await secondaryAuth.signOut();
            await secondaryApp.delete();

            // Save driver data to Firestore (using main app's db)
            await db.collection('drivers').doc(driverUid).set({
                fullName,
                phone,
                email,
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
                active: true,
                createdAt: firebase.firestore.FieldValue.serverTimestamp(),
                createdBy: Auth.currentUser.uid
            });

            showToast('Водитель успешно зарегистрирован!', 'success');
            document.getElementById('add-driver-form').reset();
            Drivers.loadDrivers();
            showSection('drivers');
        } catch (error) {
            console.error('Error adding driver:', error);
            let msg = 'Ошибка при регистрации водителя';
            if (error.code === 'auth/email-already-in-use') {
                msg = 'Этот email уже используется';
            } else if (error.code === 'auth/weak-password') {
                msg = 'Слишком простой пароль (мин. 6 символов)';
            } else if (error.code === 'auth/invalid-email') {
                msg = 'Некорректный email';
            }
            showToast(msg, 'error');
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
            await db.collection('drivers').doc(driverId).delete();
            Drivers.loadDrivers();
            showToast('Водитель удалён', 'success');
        } catch (error) {
            showToast('Ошибка удаления', 'error');
        }
    }
};
