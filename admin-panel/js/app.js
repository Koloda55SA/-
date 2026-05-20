// Main Application Logic

// Navigation
function showSection(sectionName) {
    // Hide all sections
    document.querySelectorAll('.section').forEach(s => s.classList.remove('active'));
    // Show selected section
    document.getElementById(`section-${sectionName}`).classList.add('active');
    
    // Update sidebar
    document.querySelectorAll('.sidebar-menu li').forEach(li => {
        li.classList.toggle('active', li.dataset.section === sectionName);
    });
    
    // Update title
    const titles = {
        'drivers': 'Водители',
        'add-driver': 'Добавить водителя',
        'waybills': 'Путевые листы',
        'settings': 'Настройки'
    };
    document.getElementById('page-title').textContent = titles[sectionName] || '';
}

// Toast notifications
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

// Initialize everything when DOM is ready
document.addEventListener('DOMContentLoaded', () => {
    Auth.init();
    Drivers.init();
    Settings.init();

    // Sidebar navigation
    document.querySelectorAll('.sidebar-menu li').forEach(item => {
        item.addEventListener('click', () => {
            showSection(item.dataset.section);
        });
    });
});
