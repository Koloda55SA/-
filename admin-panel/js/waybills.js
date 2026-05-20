// Waybills Management Module
const Waybills = {
    waybills: [],

    async loadWaybills() {
        try {
            const snapshot = await db.collection('waybills')
                .orderBy('createdAt', 'desc')
                .limit(50)
                .get();
            
            Waybills.waybills = [];
            const tbody = document.getElementById('waybills-tbody');
            tbody.innerHTML = '';

            snapshot.forEach(doc => {
                const waybill = { id: doc.id, ...doc.data() };
                Waybills.waybills.push(waybill);
                tbody.innerHTML += Waybills.renderRow(waybill);
            });

            if (Waybills.waybills.length === 0) {
                tbody.innerHTML = '<tr><td colspan="5" style="text-align:center;color:#64748b;padding:32px;">Нет путевых листов</td></tr>';
            }
        } catch (error) {
            console.error('Error loading waybills:', error);
        }
    },

    renderRow(waybill) {
        const date = waybill.createdAt ? new Date(waybill.createdAt.seconds * 1000).toLocaleDateString('ru-RU') : '';
        const status = waybill.status === 'completed' ? 
            '<span class="status-badge status-active">Завершён</span>' : 
            '<span class="status-badge" style="background:#fef3c7;color:#d97706;">Активен</span>';
        
        return `
            <tr>
                <td><strong>АП №${waybill.waybillNumber || ''}</strong></td>
                <td>${waybill.driverName || ''}</td>
                <td>${date}</td>
                <td>${status}</td>
                <td>
                    <button class="btn btn-sm btn-primary" onclick="Waybills.viewWaybill('${waybill.id}')">
                        <i class="fas fa-eye"></i> Просмотр
                    </button>
                </td>
            </tr>
        `;
    },

    async viewWaybill(waybillId) {
        const waybill = Waybills.waybills.find(w => w.id === waybillId);
        if (!waybill) return;
        
        // Open waybill in new window for printing
        const printWindow = window.open('', '_blank');
        printWindow.document.write(Waybills.generateWaybillHTML(waybill));
        printWindow.document.close();
    },

    generateWaybillHTML(waybill) {
        return `
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <title>Путевой лист АП №${waybill.waybillNumber}</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: 'Times New Roman', serif; font-size: 11px; padding: 20px; }
        .header { text-align: center; margin-bottom: 10px; }
        .header h1 { font-size: 14px; font-weight: bold; }
        .waybill-table { width: 100%; border-collapse: collapse; margin-bottom: 10px; }
        .waybill-table td, .waybill-table th { border: 1px solid #000; padding: 4px 6px; font-size: 10px; }
        .no-border td { border: none; }
        .section-title { background: #e8f4e8; font-weight: bold; padding: 6px; border: 1px solid #000; margin: 8px 0 4px; }
        .right-block { float: right; width: 200px; border: 1px solid #000; padding: 8px; text-align: center; }
        .stamp-block { border: 2px solid #4a90d9; padding: 10px; margin: 5px 0; background: #f0f7ff; }
        .clearfix::after { content: ''; display: table; clear: both; }
        @media print { body { padding: 10px; } }
    </style>
</head>
<body>
    <div class="header">
        <p style="font-size:9px;text-align:right;">ФОРМА ПУТЕВОГО ЛИСТА РАЗРАБОТАНА В СООТВЕТСТВИИ<br>С ПРИКАЗОМ МИНТРАНСА РОССИИ №390 ОТ 28.09.2022 г.</p>
        <h1>ПУТЕВОЙ ЛИСТ АП № ${waybill.waybillNumber}</h1>
        <p>легкового такси</p>
        <p>«${waybill.date || ''}»</p>
    </div>

    <table class="waybill-table">
        <tr>
            <td style="width:60%">
                <strong>Организация:</strong> ${waybill.orgName || ''}<br>
                ${waybill.orgAddress || ''}<br>
                <strong>ОГРН(ИП):</strong> ${waybill.ogrn || ''} <strong>ИНН:</strong> ${waybill.orgInn || ''} Тел.: ${waybill.orgPhone || ''}
            </td>
            <td>
                <table class="no-border" style="width:100%">
                    <tr><td>Форма по ОКУД</td><td>${waybill.okud || '0345001'}</td></tr>
                    <tr><td>Форма по ОКПО</td><td>${waybill.okpo || ''}</td></tr>
                    <tr><td>Телефон (вод.)</td><td>${waybill.driverPhone || ''}</td></tr>
                    <tr><td>СНИЛС (вод.)</td><td>${waybill.snils || ''}</td></tr>
                    <tr><td>ИНН (вод.)</td><td>${waybill.driverInn || ''}</td></tr>
                    <tr><td>Гаражный номер</td><td>${waybill.garageNumber || ''}</td></tr>
                    <tr><td>Табельный номер</td><td>${waybill.tabNumber || ''}</td></tr>
                </table>
            </td>
        </tr>
    </table>

    <table class="waybill-table">
        <tr><td><strong>Марка автомобиля:</strong> ${waybill.carModel || ''}</td></tr>
        <tr><td><strong>Государственный номерной знак:</strong> ${waybill.plateNumber || ''}</td></tr>
        <tr><td><strong>Водитель:</strong> ${waybill.driverName || ''}</td></tr>
        <tr><td><strong>Удостоверение №:</strong> ${waybill.license || ''} <strong>Класс:</strong> ${waybill.licenseClass || ''}</td></tr>
        <tr><td><strong>Дата выдачи:</strong> ${waybill.licenseIssued || ''} <strong>окончание:</strong> ${waybill.licenseExpires || ''}</td></tr>
        <tr><td><strong>Перевозка:</strong> ${waybill.transportType || ''}</td></tr>
        <tr><td><strong>Вид сообщения:</strong> ${waybill.commType || ''}</td></tr>
        <tr><td><strong>ID ВОДИТЕЛЯ:</strong> ${waybill.driverIdNumber || ''} <strong>ОСГОП:</strong> ${waybill.osgop || ''} <strong>Разрешение №:</strong> ${waybill.permitNumber || ''}</td></tr>
    </table>

    <div class="section-title">ПРОШЕЛ ПРЕДРЕЙСОВЫЙ МЕДИЦИНСКИЙ ОСМОТР К ИСПОЛНЕНИЮ ТРУДОВЫХ ОБЯЗАННОСТЕЙ ДОПУЩЕН</div>
    <table class="waybill-table">
        <tr><td>${waybill.date || ''}</td><td>${waybill.medTime || ''}</td><td>Медицинский работник: _______________</td></tr>
    </table>

    <div class="section-title">КОНТРОЛЬ ТЕХНИЧЕСКОГО СОСТОЯНИЯ ТРАНСПОРТНОГО СРЕДСТВА ПРОЙДЕН</div>
    <table class="waybill-table">
        <tr><td>${waybill.date || ''}</td><td>${waybill.techTime || ''}</td><td>Контролёр тех.сост. ТС: _______________</td></tr>
    </table>

    <table class="waybill-table">
        <tr><td><strong>Начало смены:</strong></td><td>${waybill.date || ''}</td><td>${waybill.shiftStart || ''}</td></tr>
        <tr><td><strong>Выезд с парковки:</strong></td><td>${waybill.date || ''}</td><td>${waybill.departureTime || ''}</td></tr>
        <tr><td><strong>Показание одометра км:</strong></td><td colspan="2">${waybill.odometerStart || ''}</td></tr>
    </table>

    <div style="border:2px solid #000;padding:10px;text-align:center;margin:10px 0;">
        <strong>ВЫПУСК НА ЛИНИЮ РАЗРЕШЕН</strong>
    </div>

    <p style="font-size:9px;margin:8px 0;"><strong>ПАМЯТКА ВОДИТЕЛЮ</strong> На основании приказа Минтранса №424 от 16.10.2020г., длительность ежедневного отдыха НЕ МЕНЕЕ 11 часов. Перерыв для отдыха и питания не более 5-ти часов, но не позже 5-ти часов после начала работы.</p>

    <table class="waybill-table">
        <tr><td><strong>ВОДИТЕЛЬ:</strong></td><td>${waybill.driverName || ''}</td><td><strong>ПОДПИСЬ:</strong></td><td></td></tr>
    </table>

    <h3 style="text-align:center;margin:10px 0;">РАЗДЕЛЕНИЕ РАБОЧЕГО ДНЯ (СМЕНЫ)</h3>
    <table class="waybill-table">
        <tr><th>ПЕРЕРЫВ НАЧАТ</th><th>ПЕРЕРЫВ ОКОНЧЕН</th><th>ОБЕД НАЧАТ</th><th>ОБЕД ОКОНЧЕН</th></tr>
        <tr><td>&nbsp;</td><td></td><td></td><td></td></tr>
    </table>

    <div class="section-title">ПРОШЕЛ ПОСЛЕРЕЙСОВЫЙ МЕДИЦИНСКИЙ ОСМОТР</div>
    <table class="waybill-table">
        <tr><td>&nbsp;</td><td></td><td>Медицинский работник: _______________</td></tr>
    </table>

    <div class="section-title">ПРОШЕЛ ПОСЛЕРЕЙСОВЫЙ ТЕХНИЧЕСКИЙ ОСМОТР</div>
    <table class="waybill-table">
        <tr><td>&nbsp;</td><td></td><td>Контролёр тех.сост. ТС: _______________</td></tr>
    </table>

    <table class="waybill-table">
        <tr><td><strong>Возвращение на парковку:</strong></td><td></td><td></td></tr>
        <tr><td><strong>Окончание смены:</strong></td><td>${waybill.date || ''}</td><td>${waybill.shiftEnd || ''}</td></tr>
        <tr><td><strong>Показание одометра км:</strong></td><td colspan="2"></td></tr>
    </table>

    <p style="text-align:right;margin-top:20px;">${waybill.orgName || ''}<br>${waybill.mintransOrder || ''}</p>

    <script>window.print();</script>
</body>
</html>`;
    }
};
