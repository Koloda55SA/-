// Адрес API (Cloudflare Worker + D1). При локальной разработке — wrangler dev.
const API_BASE = (location.hostname === 'localhost' || location.hostname === '127.0.0.1')
    ? 'http://127.0.0.1:8787'
    : 'https://asem-pro-api.oon66517.workers.dev';
