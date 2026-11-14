// Настройки: организация по умолчанию для новых водителей.
const Settings = {
    FIELDS: { 'org-name': 'orgName', 'ogrn': 'ogrn', 'inn': 'inn', 'phone': 'phone', 'address': 'address' },

    init() {
        document.getElementById('settings-form').addEventListener('submit', (e) => {
            e.preventDefault();
            Settings.saveSettings();
        });
    },

    async loadSettings() {
        try {
            const data = await Api.get('/api/admin/settings');
            for (const [field, key] of Object.entries(Settings.FIELDS)) {
                const el = document.getElementById('setting-' + field);
                if (el) el.value = data[key] || '';
            }
        } catch (e) {
            console.error('Error loading settings:', e);
        }
    },

    async saveSettings() {
        const payload = {};
        for (const [field, key] of Object.entries(Settings.FIELDS)) {
            const el = document.getElementById('setting-' + field);
            payload[key] = el ? el.value : '';
        }
        try {
            await Api.put('/api/admin/settings', payload);
            showToast('Настройки сохранены!', 'success');
        } catch (e) {
            showToast('Ошибка сохранения настроек: ' + e.message, 'error');
        }
    }
};
