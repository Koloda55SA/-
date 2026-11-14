// Общие помощники API.

export class HttpError extends Error {
  constructor(status, code, message) {
    super(message || code);
    this.status = status;
    this.code = code;
  }
}

export function fail(status, code, message) {
  throw new HttpError(status, code, message);
}

export function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8' },
  });
}

export async function readJson(request) {
  try {
    const body = await request.json();
    return body && typeof body === 'object' ? body : {};
  } catch (_) {
    fail(400, 'bad-json', 'Некорректный JSON');
  }
}

export const now = () => Date.now();

// Строка без лишних пробелов и с ограничением длины.
export function str(value, max = 500) {
  if (value == null) return '';
  return String(value).trim().slice(0, max);
}

// Случайный id в стиле Firestore (20 символов base62).
export function newId(length = 20) {
  const abc = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  const bytes = crypto.getRandomValues(new Uint8Array(length));
  let s = '';
  for (const b of bytes) s += abc[b % 62];
  return s;
}

export function bytesToB64(bytes) {
  let bin = '';
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}

export function b64ToBytes(b64) {
  const bin = atob(b64);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export async function sha256Hex(text) {
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map(b => b.toString(16).padStart(2, '0')).join('');
}

// Приводим номер к виду +79991234567 (как раньше в приложении и на сайте).
export function normalizePhone(raw) {
  let phone = String(raw || '').replace(/[\s()\-]/g, '');
  if (phone.startsWith('8') && phone.length === 11) phone = '+7' + phone.slice(1);
  if (/^9\d{9}$/.test(phone)) phone = '+7' + phone;
  if (!phone.startsWith('+')) phone = '+' + phone;
  return phone;
}

export function isValidPhone(phone) {
  return /^\+\d{10,15}$/.test(phone);
}

const MONTHS = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'];

// Московское время (UTC+3, без летнего времени) для печати на ЭПЛ.
export function msk(ms) {
  const d = new Date(ms + 3 * 3600 * 1000);
  const two = x => String(x).padStart(2, '0');
  return {
    date: `${two(d.getUTCDate())}.${two(d.getUTCMonth() + 1)}.${d.getUTCFullYear()}`,
    dateFormatted: `«${two(d.getUTCDate())}» ${MONTHS[d.getUTCMonth()]} ${d.getUTCFullYear()} г.`,
    time: `${two(d.getUTCHours())}:${two(d.getUTCMinutes())}:${two(d.getUTCSeconds())}`,
  };
}

// Начало текущих суток по Москве (для статистики «сегодня»).
export function mskDayStart(ms) {
  const shifted = ms + 3 * 3600 * 1000;
  return shifted - (shifted % 86400000) - 3 * 3600 * 1000;
}

export function parseJson(text, fallback = {}) {
  try {
    const v = JSON.parse(text);
    return v && typeof v === 'object' ? v : fallback;
  } catch (_) {
    return fallback;
  }
}
