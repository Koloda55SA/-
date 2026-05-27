// Settings Module - Simplified (no med/tech fields)
const Settings = {
    FIELDS: [
        'org-name', 'ogrn', 'inn', 'phone', 'address'
    ],

    KEY_MAP: {
        'org-name': 'orgName',
        'ogrn': 'ogrn',
        'inn': 'inn',
        'phone': 'phone',
        'address': 'address'
    },

    async loadSettings() {
        try {
            const doc = await db.collection('settings').doc('company').get();
            if (!doc.exists) return;
            const data = doc.data();
            for (const field of Settings.FIELDS) {
                const el = document.getElementById('setting-' + field);
                if (el) el.value = data[Settings.KEY_MAP[field]] || '';
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
            const payload = {
                updatedAt: firebase.firestore.FieldValue.serverTimestamp()
            };
            for (const field of Settings.FIELDS) {
                const el = document.getElementById('setting-' + field);
                payload[Settings.KEY_MAP[field]] = el ? el.value : '';
            }
            await db.collection('settings').doc('company').set(payload, { merge: true });
            showToast('Настройки сохранены!', 'success');
        } catch (error) {
            console.error('Error saving settings:', error);
            showToast('Ошибка сохранения настроек', 'error');
        }
    }
};
