// AsemPro - Main Application Logic

function showSection(sectionName) {
    document.querySelectorAll('.section').forEach(s => s.classList.remove('active'));
    const target = document.getElementById(`section-${sectionName}`);
    if (target) target.classList.add('active');
    document.querySelectorAll('.sidebar-menu li').forEach(li => {
        li.classList.toggle('active', li.dataset.section === sectionName);
    });
    const titles = {
        'menu': 'Меню',
        'drivers': 'Водители',
        'add-driver': 'Новый водитель',
        'waybills': 'Путевые листы',
        'settings': 'Настройки'
    };
    document.getElementById('page-title').textContent = titles[sectionName] || '';
    if (window.innerWidth <= 1024) closeSidebar();

    // При переходе на форму нового водителя подтягиваем данные организации из настроек
    if (sectionName === 'add-driver' && typeof Drivers !== 'undefined') {
        Drivers._prefillOrgFromSettings();
    }

    // Обновляем статистику при заходе в "Меню"
    if (sectionName === 'menu') {
        updateDashboard();
    }
}

function toggleSidebar() {
    const sidebar = document.getElementById('sidebar');
    const overlay = document.getElementById('sidebar-overlay');
    const isOpen = sidebar.classList.contains('sidebar-open');
    if (isOpen) {
        closeSidebar();
    } else {
        sidebar.classList.add('sidebar-open');
        overlay.classList.add('active');
        document.body.style.overflow = 'hidden';
    }
}

function closeSidebar() {
    const sidebar = document.getElementById('sidebar');
    const overlay = document.getElementById('sidebar-overlay');
    sidebar.classList.remove('sidebar-open');
    overlay.classList.remove('active');
    document.body.style.overflow = '';
}

function showToast(message, type = 'success') {
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;
    toast.textContent = message;
    document.body.appendChild(toast);
    setTimeout(() => {
        toast.style.opacity = '0';
        toast.style.transform = 'translateX(100%)';
        setTimeout(() => toast.remove(), 300);
    }, 3000);
}

// Theme toggle
function toggleTheme() {
    const html = document.documentElement;
    const current = html.getAttribute('data-theme');
    const next = current === 'light' ? 'dark' : 'light';
    html.setAttribute('data-theme', next);
    localStorage.setItem('asempro_theme', next);
    updateThemeUI(next);
}

function updateThemeUI(theme) {
    const icon = document.getElementById('theme-icon');
    const label = document.getElementById('theme-label');
    if (theme === 'light') {
        icon.className = 'fas fa-sun';
        label.textContent = 'Светлая тема';
    } else {
        icon.className = 'fas fa-moon';
        label.textContent = 'Тёмная тема';
    }
}

function initTheme() {
    const saved = localStorage.getItem('asempro_theme') || 'dark';
    document.documentElement.setAttribute('data-theme', saved);
    updateThemeUI(saved);
}

async function updateDashboard() {
    try {
        const driversSnap = await db.collection('drivers').get();
        const waybillsSnap = await db.collection('waybills').get();
        const today = new Date().toLocaleDateString('ru-RU');

        let activeCount = 0;
        let todayCount = 0;
        driversSnap.forEach(doc => { if (doc.data().active !== false) activeCount++; });
        waybillsSnap.forEach(doc => { if (doc.data().date === today) todayCount++; });

        document.getElementById('stat-drivers').textContent = driversSnap.size;
        document.getElementById('stat-active').textContent = activeCount;
        document.getElementById('stat-waybills').textContent = waybillsSnap.size;
        document.getElementById('stat-today').textContent = todayCount;
    } catch (e) {
        console.error('Dashboard update error:', e);
    }
}

document.addEventListener('DOMContentLoaded', () => {
    initTheme();
    Auth.init();
    Drivers.init();
    Settings.init();

    document.querySelectorAll('.sidebar-menu li').forEach(item => {
        item.addEventListener('click', () => showSection(item.dataset.section));
    });
});
