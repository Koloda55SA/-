// Техподдержка: чат водителя с администратором.
// Новые сообщения клиенты забирают запросом ?after=<последний id> (опрос раз в несколько секунд).
import { fail, now, str } from './lib.js';

const MAX_TEXT = 2000;

async function messages(env, driverId, after) {
  const { results } = await env.DB.prepare(
    `SELECT id, sender, text, created_at AS createdAt FROM support_messages
      WHERE driver_id = ? AND id > ? ORDER BY id LIMIT 500`
  ).bind(driverId, after).all();
  return results;
}

function afterParam(url) {
  return Math.max(parseInt(url.searchParams.get('after') || '0', 10) || 0, 0);
}

async function send(env, driverId, sender, text) {
  const t = now();
  const unreadCol = sender === 'driver' ? 'unread_admin' : 'unread_driver';
  await env.DB.batch([
    env.DB.prepare('INSERT INTO support_messages (driver_id, sender, text, created_at) VALUES (?, ?, ?, ?)')
      .bind(driverId, sender, text, t),
    env.DB.prepare(
      `INSERT INTO support_chats (driver_id, last_message, last_sender, last_at, ${unreadCol})
       VALUES (?, ?, ?, ?, 1)
       ON CONFLICT(driver_id) DO UPDATE SET
         last_message = excluded.last_message, last_sender = excluded.last_sender,
         last_at = excluded.last_at, ${unreadCol} = ${unreadCol} + 1`
    ).bind(driverId, text.slice(0, 200), sender, t),
  ]);
}

// ── Водитель ──────────────────────────────────────────────

export async function driverMessages(env, user, url) {
  const list = await messages(env, user.id, afterParam(url));
  const chat = await env.DB.prepare('SELECT unread_driver FROM support_chats WHERE driver_id = ?').bind(user.id).first();
  return { messages: list, unread: chat ? chat.unread_driver : 0 };
}

export async function driverSend(env, user, body) {
  const text = str(body.text, MAX_TEXT);
  if (!text) fail(400, 'empty', 'Пустое сообщение');
  await send(env, user.id, 'driver', text);
  return { ok: true };
}

export async function driverRead(env, user) {
  await env.DB.prepare('UPDATE support_chats SET unread_driver = 0 WHERE driver_id = ?').bind(user.id).run();
  return { ok: true };
}

// ── Администратор ─────────────────────────────────────────

export async function adminChats(env) {
  const { results } = await env.DB.prepare(
    `SELECT c.driver_id AS driverId, c.last_message AS lastMessage, c.last_sender AS lastSender,
            c.last_at AS lastMessageAt, c.unread_admin AS unreadForAdmin,
            u.full_name AS driverName, u.phone, d.data
       FROM support_chats c
       LEFT JOIN users u ON u.id = c.driver_id
       LEFT JOIN drivers d ON d.user_id = c.driver_id
      ORDER BY c.last_at DESC LIMIT 200`
  ).all();
  return results.map(r => {
    let orgName = '';
    try { orgName = JSON.parse(r.data || '{}').orgName || ''; } catch (_) {}
    const { data, ...rest } = r;
    return { ...rest, id: r.driverId, orgName };
  });
}

export async function adminMessages(env, driverId, url) {
  const list = await messages(env, driverId, afterParam(url));
  await env.DB.prepare('UPDATE support_chats SET unread_admin = 0 WHERE driver_id = ?').bind(driverId).run();
  return { messages: list };
}

export async function adminSend(env, driverId, body) {
  const text = str(body.text, MAX_TEXT);
  if (!text) fail(400, 'empty', 'Пустое сообщение');
  const exists = await env.DB.prepare("SELECT 1 FROM users WHERE id = ? AND role = 'driver'").bind(driverId).first();
  if (!exists) fail(404, 'not-found', 'Водитель не найден');
  await send(env, driverId, 'admin', text);
  return { ok: true };
}
