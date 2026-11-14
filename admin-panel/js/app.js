// AsemPro - Main Application Logic

// Разделы, доступные медику и мастеру. Остальное — только администратору.
const STAFF_SECTIONS = ['checks'];

function showSection(sectionName) {
    if (typeof Auth !== 'undefined' && Auth.role !== 'admin' && !STAFF_SECTIONS.includes(sectionName)) {
        sectionName = 'checks';
    }
    document.querySelectorAll('.section').forEach(s => s.classList.remove('active'));
    const target = document.getElementById(`section-${sectionName}`);
    if (target) target.classList.add('active');
    document.querySelectorAll('.sidebar-menu li').forEach(li => {
        li.classList.toggle('active', li.dataset.section === sectionName);
    });
    const titles = {
        'menu': 'Меню',
        'checks': 'Допуск на линию',
        'staff': 'Сотрудники',
        'drivers': 'Водители',
        'add-driver': 'Новый водитель',
        'waybills': 'Путевые листы',
        'requests': 'Заявки',
        'support': 'Техподдержка',
        'accounting': 'Бухгалтерия',
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

    // Подгружаем заявки на дополнительные ЭПЛ
    if (sectionName === 'requests' && typeof Requests !== 'undefined') {
        Requests.load();
    }

    // Техподдержка — список чатов с водителями
    if (sectionName === 'support' && typeof Support !== 'undefined') {
        Support.load();
    }

    // Бухгалтерия — таблица оплат за выбранный месяц
    if (sectionName === 'accounting' && typeof Accounting !== 'undefined') {
        Accounting.load();
    }

    if (sectionName === 'checks' && typeof Checks !== 'undefined') {
        Checks.load();
    }

    if (sectionName === 'staff' && typeof Staff !== 'undefined') {
        Staff.load();
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

// Обновление статистики на «Меню». Вызывается из realtime-подписок водителей
// и путевых листов, поэтому:
//   - считаем только когда «Меню» открыто (иначе — при следующем заходе);
//   - схлопываем частые вызовы в один (debounce), чтобы не долбить сервер
//     агрегатами count() на каждое изменение.
let _dashboardTimer = null;
function updateDashboard() {
    const menu = document.getElementById('section-menu');
    if (!menu || !menu.classList.contains('active')) return;
    if (typeof Auth !== 'undefined' && Auth.role !== 'admin') return;
    clearTimeout(_dashboardTimer);
    _dashboardTimer = setTimeout(_updateDashboardNow, 400);
}

// Водителей считаем из живого кэша (Drivers.drivers держится в реальном
// времени), путевые листы — дешёвым серверным агрегатом count().
async function _updateDashboardNow() {
    try {
        const today = new Date().toLocaleDateString('ru-RU');
        const setStat = (id, v) => { const el = document.getElementById(id); if (el) el.textContent = v; };

        // Водители — из realtime-кэша, если он уже наполнен.
        if (typeof Drivers !== 'undefined' && Drivers._unsub) {
            setStat('stat-drivers', Drivers.drivers.length);
            setStat('stat-active', Drivers.drivers.filter(d => d.active !== false).length);
        } else {
            const driversSnap = await db.collection('drivers').get();
            let activeCount = 0;
            driversSnap.forEach(doc => { if (doc.data().active !== false) activeCount++; });
            setStat('stat-drivers', driversSnap.size);
            setStat('stat-active', activeCount);
        }

        // Путевые листы — серверный агрегат (1 чтение вместо всей коллекции).
        try {
            const totalAgg = await db.collection('waybills').count().get();
            setStat('stat-waybills', totalAgg.data().count);
            const todayAgg = await db.collection('waybills').where('date', '==', today).count().get();
            setStat('stat-today', todayAgg.data().count);
        } catch (_) {
            // Если агрегаты недоступны — считаем из загруженных (до 50) листов.
            if (typeof Waybills !== 'undefined') {
                setStat('stat-waybills', Waybills.waybills.length);
                setStat('stat-today', Waybills.waybills.filter(w => w.date === today).length);
            }
        }
    } catch (e) {
        console.error('Dashboard update error:', e);
    }
}

document.addEventListener('DOMContentLoaded', () => {
    initTheme();
    Auth.init();
    Drivers.init();
    Settings.init();
    if (typeof Support !== 'undefined') Support.init();
    if (typeof Accounting !== 'undefined') Accounting.init();
    if (typeof Staff !== 'undefined') Staff.init();

    document.querySelectorAll('.sidebar-menu li').forEach(item => {
        item.addEventListener('click', () => {
            const section = item.dataset.section;
            // «Новый водитель» всегда открывает пустую форму (сбрасывает режим редактирования).
            if (section === 'add-driver' && typeof Drivers !== 'undefined') {
                Drivers.newDriver();
            } else {
                showSection(section);
            }
        });
    });
});
