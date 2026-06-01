// Waybills Management Module - Updated for per-driver org
const Waybills = {
    waybills: [],

    // HTML-escape для безопасной вставки в innerHTML
    _esc(value) {
        const s = value == null ? '' : String(value);
        return s
            .replace(/&/g, '&amp;')
            .replace(/</g, '&lt;')
            .replace(/>/g, '&gt;')
            .replace(/"/g, '&quot;')
            .replace(/'/g, '&#39;');
    },

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
                tbody.insertAdjacentHTML('beforeend', Waybills.renderRow(waybill));
            });

            if (Waybills.waybills.length === 0) {
                tbody.innerHTML = '<tr><td colspan="6" style="text-align:center;color:var(--text-light);padding:32px;">Нет путевых листов</td></tr>';
            }
        } catch (error) {
            console.error('Error loading waybills:', error);
        }
    },

    renderRow(waybill) {
        const e = Waybills._esc;
        const date = waybill.createdAt ? new Date(waybill.createdAt.seconds * 1000).toLocaleDateString('ru-RU') : '';
        let status;
        if (waybill.status === 'closed') {
            status = '<span class="status-badge status-active">Закрыт</span>';
        } else {
            status = '<span class="status-badge status-open">Открыт</span>';
        }

        return `
            <tr>
                <td data-label="Номер"><strong>АП №${e(waybill.waybillNumber)}</strong></td>
                <td data-label="Водитель">${e(waybill.driverName)}</td>
                <td data-label="Организация">${e(waybill.orgName) || '—'}</td>
                <td data-label="Дата">${e(date)}</td>
                <td data-label="Статус">${status}</td>
                <td data-label="Действия">
                    <button class="btn btn-sm btn-primary" onclick="Waybills.viewWaybill('${e(waybill.id)}')">
                        <i class="fas fa-eye"></i> Просмотр
                    </button>
                </td>
            </tr>
        `;
    },

    async viewWaybill(waybillId) {
        const waybill = Waybills.waybills.find(w => w.id === waybillId);
        if (!waybill) return;
        
        const printWindow = window.open('', '_blank');
        printWindow.document.write(Waybills.generateWaybillHTML(waybill));
        printWindow.document.close();
    },

    formatShortDate(s) {
        if (!s) return '';
        const m = String(s).match(/^(\d{4})-(\d{2})-(\d{2})/);
        if (!m) return s;
        return `${m[3]}.${m[2]}.${m[1]}`;
    },

    signatureScribble(name) {
        if (!name) return '~';
        const parts = String(name).trim().split(/\s+/);
        const first = parts[0]?.[0] || '';
        const last = parts.length > 1 ? parts[parts.length - 1][0] : '';
        return `${first}.${last}~~`;
    },

    // Базовый адрес публичной страницы просмотра ЭПЛ (Cloudflare Pages).
    viewerBaseUrl: 'https://taxopark-admin.pages.dev',

    generateWaybillHTML(w) {
        // QR ведёт на публичную страницу просмотра конкретного ЭПЛ (по id документа).
        // Если id почему-то нет — кодируем краткую сводку (обратная совместимость).
        const qrPayload = w.id
            ? `${Waybills.viewerBaseUrl}/waybill.html?id=${encodeURIComponent(w.id)}`
            : btoa(unescape(encodeURIComponent(
                `n:${w.waybillNumber}|d:${w.date}|org:${w.orgName||''}|drv:${w.driverName||''}|p:${w.plateNumber||''}`
            )));
        const qrUrl = `https://api.qrserver.com/v1/create-qr-code/?size=120x120&data=${encodeURIComponent(qrPayload)}`;
        const sig = w.signatureData ? `<img src="${w.signatureData}" style="height:40px;max-width:200px;" alt="Подпись">` : `<span class="signature">${Waybills.signatureScribble(w.driverName)}</span>`;

        return `
<!DOCTYPE html>
<html lang="ru">
<head>
    <meta charset="UTF-8">
    <title>ЭПЛ АП №${w.waybillNumber}</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body { font-family: Arial, sans-serif; font-size: 10px; padding: 16px; color: #000; background: #fff; }
        .epl-title { text-align: center; font-size: 18px; font-weight: bold; color: #666; margin-bottom: 4px; }
        .header-row { display: flex; gap: 12px; margin-bottom: 6px; }
        .title-block { flex: 4; }
        .title-block .pl-line { display: flex; align-items: baseline; gap: 6px; }
        .title-block .pl-line .label { font-size: 9px; }
        .title-block .pl-line .number { font-size: 12px; font-weight: bold; }
        .title-block .subtitle { font-size: 8px; color: #666; margin-left: 10px; }
        .title-block .date-line { font-size: 9px; margin-top: 3px; }
        .mintrans-ref { flex: 3; text-align: right; font-size: 7px; }
        table { width: 100%; border-collapse: collapse; }
        td { border: 1px solid #000; padding: 3px 5px; font-size: 9px; vertical-align: top; }
        .lbl { font-size: 7px; color: #666; }
        .val { font-size: 9px; font-weight: bold; }
        .org-table td { vertical-align: top; }
        .codes-header { background: #f3f3f3; text-align: center; font-weight: bold; font-size: 8px; padding: 2px; }
        .codes-row { display: flex; justify-content: space-between; padding: 1px 4px; border-bottom: 1px solid #ccc; font-size: 7px; }
        .codes-row .v { font-weight: bold; }
        .green-bg { background: #d9ead3; }
        .release { border: 2px solid #000; padding: 8px; text-align: center; height: 100%; display: flex; flex-direction: column; justify-content: center; }
        .release .small { font-size: 10px; font-weight: bold; }
        .release .big { font-size: 16px; font-weight: bold; }
        .memo { font-size: 7px; margin: 6px 0; }
        .memo b { font-size: 7px; }
        .signature { font-family: 'Brush Script MT', cursive; font-size: 18px; color: #1a4e8e; font-style: italic; }
        .work-split { text-align: center; font-weight: bold; font-size: 9px; margin: 4px 0; }
        .footer { display: flex; justify-content: space-between; align-items: flex-end; margin-top: 8px; }
        .footer .right { text-align: right; }
        .footer .org { font-size: 10px; font-weight: bold; }
        .footer .ord { font-size: 8px; }
        @media print { body { padding: 10px; } @page { size: A4; margin: 8mm; } }
    </style>
</head>
<body>
    <div class="epl-title">ЭПЛ</div>

    <div class="header-row">
        <div class="title-block">
            <div class="pl-line">
                <span class="label">путевой лист</span>
                <span class="number">АП</span>
                <span class="label">№</span>
                <span class="number">${w.waybillNumber || ''}</span>
                <span class="subtitle" style="margin-left:30px">серия</span>
            </div>
            <div class="subtitle">легкового такси</div>
            <div class="date-line">${w.dateFormatted || ('«' + (w.date || '') + '»')}</div>
        </div>
        <div class="mintrans-ref">
            ФОРМА ПУТЕВОГО ЛИСТА РАЗРАБОТАНА В СООТВЕТСТВИИ<br>
            С ПРИКАЗОМ МИНТРАНСА РОССИИ № ${w.mintransOrder || '390 ОТ 28.09.2022'} г.
        </div>
    </div>

    <table class="org-table">
        <tr>
            <td style="width:57%">
                <div class="lbl">Организация</div>
                <div class="val">${w.orgName || ''}</div>
                <div style="font-size:8px">${w.orgAddress || ''}</div>
                <div style="font-size:8px">ОГРН(ИП): ${w.ogrn || w.orgOgrn || ''}&nbsp;&nbsp;ИНН: ${w.orgInn || ''}&nbsp;&nbsp;Тел.: ${w.orgPhone || ''}</div>
                <div style="font-size:6px;color:#666">наименование, адрес, ОГРН(ИП), ИНН, номер телефона</div>
            </td>
            <td style="padding:0">
                <div class="codes-header">Коды</div>
                <div class="codes-row"><span>Форма по ОКУД</span><span class="v">${w.okud || '0345001'}</span></div>
                <div class="codes-row"><span>Форма по ОКПО</span><span class="v">${w.okpo || ''}</span></div>
                <div class="codes-row"><span>Телефон (вод.)</span><span class="v">${w.driverPhone || ''}</span></div>
                <div class="codes-row"><span>СНИЛС (вод.)</span><span class="v">${w.snils || ''}</span></div>
                <div class="codes-row"><span>ИНН (вод.)</span><span class="v">${w.driverInn || ''}</span></div>
                <div class="codes-row"><span>Гаражный номер</span><span class="v">${w.garageNumber || ''}</span></div>
                <div class="codes-row"><span>Табельный номер</span><span class="v">${w.tabNumber || ''}</span></div>
            </td>
        </tr>
    </table>

    <table style="margin-top:3px">
        <tr>
            <td><div class="lbl">Марка автомобиля</div><div class="val">${w.carModel || ''}</div></td>
            <td><div class="lbl">Перевозка</div><div class="val">${w.transportType || ''}</div></td>
        </tr>
        <tr>
            <td><div class="lbl">Государственный номерной знак</div><div class="val">${w.plateNumber || ''}</div></td>
            <td><div class="lbl">Вид сообщения</div><div class="val">${w.commType || ''}</div></td>
        </tr>
        <tr>
            <td><div class="lbl">Водитель</div><div class="val">${w.driverName || ''}</div><div style="font-size:6px;color:#666">фамилия, имя, отчество</div></td>
            <td><div class="lbl">Дата выдачи / окончание</div><div class="val">${Waybills.formatShortDate(w.licenseIssued)} / ${Waybills.formatShortDate(w.licenseExpires)}</div></td>
        </tr>
        <tr>
            <td><div class="lbl">Удостоверение №</div><div class="val">${w.license || ''} &nbsp; Класс: ${w.licenseClass || ''}</div></td>
            <td><div class="lbl">ID ВОДИТЕЛЯ</div><div class="val">${w.driverIdNumber || ''}</div></td>
        </tr>
        <tr>
            <td><div class="lbl">ОСГОП</div><div class="val">${w.osgop || ''}</div></td>
            <td><div class="lbl">Разрешение №</div><div class="val">${w.permitNumber || w.permit || ''}</div></td>
        </tr>
    </table>

    <table style="margin-top:3px">
        <tr>
            <td style="width:70%;padding:0">
                <table>
                    <tr><td style="width:50%"><b>Начало смены</b></td><td>${w.date || ''}</td><td><b>${w.shiftStart || ''}</b></td></tr>
                    <tr><td><b>Выезд с парковки</b></td><td>${w.date || ''}</td><td><b>${w.departureTime || ''}</b></td></tr>
                    <tr><td><b>Показание одометра км</b></td><td colspan="2"><b>${w.odometerStart || ''}</b></td></tr>
                </table>
            </td>
            <td style="width:30%"><div class="release"><div class="small">ВЫПУСК НА ЛИНИЮ</div><div class="big">РАЗРЕШЕН</div></div></td>
        </tr>
    </table>

    <div class="memo"><b>ПАМЯТКА ВОДИТЕЛЮ</b> На основании приказа Минтранса №424 от 16.10.2020г., длительность ежедневного отдыха НЕ МЕНЕЕ 11 часов. Перерыв для отдыха и питания не более 5-ти часов, но не позже 5-ти часов после начала работы.</div>

    <table>
        <tr>
            <td style="width:15%"><b>ВОДИТЕЛЬ:</b></td>
            <td style="width:50%"><b>${w.driverName || ''}</b></td>
            <td style="width:15%"><b>ПОДПИСЬ:</b></td>
            <td style="width:20%">${sig}</td>
        </tr>
    </table>

    <div class="work-split">РАЗДЕЛЕНИЕ РАБОЧЕГО ДНЯ (СМЕНЫ)</div>
    <table>
        <tr>
            <td class="green-bg" style="text-align:center"><b>ПЕРЕРЫВ НАЧАТ</b></td>
            <td class="green-bg" style="text-align:center"><b>ПЕРЕРЫВ ОКОНЧЕН</b></td>
            <td class="green-bg" style="text-align:center"><b>ОБЕД НАЧАТ</b></td>
            <td class="green-bg" style="text-align:center"><b>ОБЕД ОКОНЧЕН</b></td>
        </tr>
        <tr><td style="height:18px"></td><td></td><td></td><td></td></tr>
    </table>

    <table style="margin-top:3px">
        <tr><td style="width:50%"><b>Возвращение на парковку</b></td><td style="width:25%"></td><td style="width:25%"></td></tr>
        <tr><td><b>Окончание смены</b></td><td>${w.date || ''}</td><td><b>${w.shiftEnd || ''}</b></td></tr>
        <tr><td><b>Показание одометра км</b></td><td colspan="2"></td></tr>
    </table>

    <div class="footer">
        <img src="${qrUrl}" alt="QR" width="100" height="100">
        <div class="right">
            <div class="org">${w.orgName || ''}</div>
            <div class="ord">${w.mintransOrder || '390 ОТ 28.09.2022'}</div>
        </div>
    </div>
</body>
</html>`;
    }
};
