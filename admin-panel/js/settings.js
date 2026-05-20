// Settings Module
const Settings = {
    FIELDS: [
        'org-name', 'ogrn', 'inn', 'phone', 'address',
        'okud', 'okpo', 'permit', 'mintrans',
        'med-name', 'med-cert', 'med-issued', 'med-expires',
        'tech-name', 'tech-cert', 'tech-issued', 'tech-expires'
    ],

    KEY_MAP: {
        'org-name': 'orgName',
        'ogrn': 'ogrn',
        'inn': 'inn',
        'phone': 'phone',
        'address': 'address',
        'okud': 'okud',
        'okpo': 'okpo',
        'permit': 'permit',
        'mintrans': 'mintrans',
        'med-name': 'medName',
        'med-cert': 'medCert',
        'med-issued': 'medIssued',
        'med-expires': 'medExpires',
        'tech-name': 'techName',
        'tech-cert': 'techCert',
        'tech-issued': 'techIssued',
        'tech-expires': 'techExpires'
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
