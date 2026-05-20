// Settings Module
const Settings = {
    async loadSettings() {
        try {
            const doc = await db.collection('settings').doc('company').get();
            if (doc.exists) {
                const data = doc.data();
                document.getElementById('setting-org-name').value = data.orgName || '';
                document.getElementById('setting-ogrn').value = data.ogrn || '';
                document.getElementById('setting-inn').value = data.inn || '';
                document.getElementById('setting-phone').value = data.phone || '';
                document.getElementById('setting-address').value = data.address || '';
                document.getElementById('setting-okud').value = data.okud || '';
                document.getElementById('setting-okpo').value = data.okpo || '';
                document.getElementById('setting-permit').value = data.permit || '';
                document.getElementById('setting-mintrans').value = data.mintrans || '';
            }
        } catch (error) {
            console.error('Error loading settings:', error);
        }
    },

    init() {
        document.getElementById('settings-form').addEventListener('submit', (e) => {
            e.preventDefault();
            Settings.saveSettings();
        });
    },

    async saveSettings() {
        try {
            await db.collection('settings').doc('company').set({
                orgName: document.getElementById('setting-org-name').value,
                ogrn: document.getElementById('setting-ogrn').value,
                inn: document.getElementById('setting-inn').value,
                phone: document.getElementById('setting-phone').value,
                address: document.getElementById('setting-address').value,
                okud: document.getElementById('setting-okud').value,
                okpo: document.getElementById('setting-okpo').value,
                permit: document.getElementById('setting-permit').value,
                mintrans: document.getElementById('setting-mintrans').value,
                updatedAt: firebase.firestore.FieldValue.serverTimestamp()
            });
            showToast('Настройки сохранены!', 'success');
        } catch (error) {
            console.error('Error saving settings:', error);
            showToast('Ошибка сохранения настроек', 'error');
        }
    }
};
