// AsemPro - Main Application Logic

function showSection(sectionName) {
    document.querySelectorAll('.section').forEach(s => s.classList.remove('active'));
    document.getElementById(`section-${sectionName}`).classList.add('active');
    document.querySelectorAll('.sidebar-menu li').forEach(li => {
        li.classList.toggle('active', li.dataset.section === sectionName);
    });
    const titles = {
        'dashboard': 'Дашборд',
        'drivers': 'Водители',
        'add-driver': 'Новый водитель',
        'waybills': 'Путевые листы',
        'settings': 'Настройки'
    };
    document.getElementById('page-title').textContent = titles[sectionName] || '';
    // Auto-close sidebar on mobile after navigation
    if (window.innerWidth <= 1024) closeSidebar();
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

        // Recent activity
        const activity = document.getElementById('recent-activity');
        const recent = [];
        waybillsSnap.forEach(doc => {
            const d = doc.data();
            if (d.createdAt) recent.push(d);
        });
        recent.sort((a, b) => (b.createdAt?.seconds || 0) - (a.createdAt?.seconds || 0));

        if (recent.length === 0) {
            activity.innerHTML = '<p class="empty-text">Нет активности</p>';
        } else {
            activity.innerHTML = recent.slice(0, 5).map(w => `
                <div style="display:flex;align-items:center;gap:12px;padding:10px 0;border-bottom:1px solid var(--border)">
                    <div style="width:36px;height:36px;border-radius:10px;background:rgba(99,102,241,0.15);display:flex;align-items:center;justify-content:center">
                        <i class="fas fa-file-lines" style="color:var(--primary-light);font-size:14px"></i>
                    </div>
                    <div>
                        <div style="font-size:13px;font-weight:500">Путевой лист АП №${w.waybillNumber || ''}</div>
                        <div style="font-size:11px;color:var(--text-light)">${w.driverName || ''} - ${w.date || ''}</div>
                    </div>
                </div>
            `).join('');
        }
    } catch (e) {
        console.error('Dashboard update error:', e);
    }
}

document.addEventListener('DOMContentLoaded', () => {
    Auth.init();
    Drivers.init();
    Settings.init();

    document.querySelectorAll('.sidebar-menu li').forEach(item => {
        item.addEventListener('click', () => showSection(item.dataset.section));
    });
});
