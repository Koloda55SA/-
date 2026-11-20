// Cloudflare Worker для Asem Pro: серверная смена пароля / удаление аккаунта
// водителя через Firebase Identity Toolkit (Admin REST). Бесплатно, без Blaze.
//
// Эндпоинты (POST, JSON):
//   /reset-password { idToken, driverUid, newPassword }
//   /delete-driver  { idToken, driverUid }
//   /auto-issue-preference { idToken, enabled }
//
// Безопасность:
//   - idToken — токен входа администратора (получаем в админке через getIdToken()).
//   - Worker проверяет, что владелец idToken есть в коллекции admins/{uid}.
//   - Реальное изменение делает служебный ключ (секрет SERVICE_ACCOUNT_JSON),
//     который хранится только в зашифрованных секретах Worker.

import { findInspectionDriver, firestore, issueReadyWaybills, recordInspection } from './auto-issue.js';

let _tokenCache = { token: null, exp: 0 };

function corsHeaders(env, request) {
  const origin = request.headers.get('Origin') || '';
  const allowed = env.ALLOWED_ORIGIN || '';
  // Разрешаем основной домен и его preview-поддомены *.pages.dev того же проекта.
  let allow = allowed;
  try {
    const { protocol, hostname } = new URL(origin);
    if (origin === allowed || (protocol === 'https:' &&
        (hostname === 'taxopark-admin.pages.dev' || hostname.endsWith('.taxopark-admin.pages.dev')))) {
      allow = origin;
    }
  } catch (_) {}
  return {
    'Access-Control-Allow-Origin': allow || allowed,
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Max-Age': '86400',
  };
}

function json(data, status, headers) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json', ...headers },
  });
}

// ── base64url helpers ─────────────────────────────────────────────
function b64urlFromBytes(bytes) {
  let bin = '';
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function b64urlFromString(str) {
  return b64urlFromBytes(new TextEncoder().encode(str));
}
function pemToArrayBuffer(pem) {
  const body = pem
    .replace(/-----BEGIN [^-]+-----/, '')
    .replace(/-----END [^-]+-----/, '')
    .replace(/\s+/g, '');
  const raw = atob(body);
  const buf = new Uint8Array(raw.length);
  for (let i = 0; i < raw.length; i++) buf[i] = raw.charCodeAt(i);
  return buf.buffer;
}

// ── Получить OAuth2 access token сервис-аккаунта (scope cloud-platform) ──
async function getAccessToken(env) {
  const now = Math.floor(Date.now() / 1000);
  if (_tokenCache.token && _tokenCache.exp - 60 > now) return _tokenCache.token;

  const sa = JSON.parse(env.SERVICE_ACCOUNT_JSON);
  const header = { alg: 'RS256', typ: 'JWT' };
  const claim = {
    iss: sa.client_email,
    scope: 'https://www.googleapis.com/auth/cloud-platform',
    aud: 'https://oauth2.googleapis.com/token',
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${b64urlFromString(JSON.stringify(header))}.${b64urlFromString(JSON.stringify(claim))}`;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(sa.private_key),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign']
  );
  const sig = await crypto.subtle.sign(
    'RSASSA-PKCS1-v1_5',
    key,
    new TextEncoder().encode(unsigned)
  );
  const jwt = `${unsigned}.${b64urlFromBytes(new Uint8Array(sig))}`;

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body:
      'grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=' +
      encodeURIComponent(jwt),
  });
  const data = await res.json();
  if (!res.ok || !data.access_token) {
    throw new Error('oauth: ' + JSON.stringify(data));
  }
  _tokenCache = { token: data.access_token, exp: now + (data.expires_in || 3600) };
  return data.access_token;
}

// Проверяем токен Firebase и читаем профиль сотрудника, которому он выдан.
async function getStaff(env, idToken) {
  // 1) Узнаём uid по idToken (публичный web API key).
  const lookup = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:lookup?key=${env.FIREBASE_API_KEY}`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ idToken }),
    }
  );
  const lj = await lookup.json();
  const uid = lj.users && lj.users[0] && lj.users[0].localId;
  if (!uid) throw new Error('bad-token');

  // 2) Проверяем admins/{uid} через Firestore REST с тем же idToken
  //    (правила разрешают читать свой admin-документ).
  const sa = JSON.parse(env.SERVICE_ACCOUNT_JSON);
  const projectId = sa.project_id;
  const profileUrl = `https://firestore.googleapis.com/v1/projects/${projectId}/databases/(default)/documents/admins/${encodeURIComponent(uid)}`;
  const fs = await fetch(profileUrl, { headers: { Authorization: 'Bearer ' + idToken } });
  if (fs.status !== 200) throw new Error('not-staff');
  const profile = await fs.json();
  const role = profile.fields?.role?.stringValue || 'admin';
  return { uid, role, profile, projectId };
}

async function saveAutoIssuePreference(env, staff, body, cors) {
  if (typeof body.enabled !== 'boolean') {
    return json({ error: 'bad-preference' }, 400, cors);
  }
  const store = firestore(staff.projectId, await getAccessToken(env));
  await store.commit([{
    update: {
      name: staff.profile.name,
      fields: { autoIssueEnabled: { booleanValue: body.enabled } },
    },
    updateMask: { fieldPaths: ['autoIssueEnabled'] },
    currentDocument: { updateTime: staff.profile.updateTime },
  }]);
  return json({ ok: true }, 200, cors);
}

const inspectionRoutes = new Set(['/auto-issue-preference', '/inspection-driver', '/inspection-result']);

async function handleInspection(path, env, body, cors) {
  if (typeof body?.idToken !== 'string' || !body.idToken) {
    return json({ error: 'missing-params' }, 400, cors);
  }
  let staff;
  try {
    staff = await getStaff(env, body.idToken);
  } catch {
    return json({ error: 'unauthorized' }, 401, cors);
  }
  if (staff.role !== 'medic' && staff.role !== 'mechanic') {
    return json({ error: 'staff-role-required' }, 403, cors);
  }
  if (path === '/auto-issue-preference') {
    return saveAutoIssuePreference(env, staff, body, cors);
  }
  if (staff.profile.fields?.autoIssueEnabled?.booleanValue !== true) {
    return json({ error: 'auto-issue-disabled' }, 403, cors);
  }
  const store = firestore(staff.projectId, await getAccessToken(env));
  if (path === '/inspection-driver') {
    const { status = 200, ...result } = await findInspectionDriver(store, body.phone);
    return json(result, status, cors);
  }
  const { status = 200, ready, ...result } = await recordInspection(store, staff, body);
  if (ready) {
    // Запись уже сохранена. Если немедленный выпуск сорвётся, очередь обработает Cron.
    const activation = await issueReadyWaybills(store, new Date(), body.driverId)
      .catch(() => ({ issued: 0 }));
    result.issued = activation.issued > 0;
  }
  return json(result, status, cors);
}

async function handle(request, env) {
  const url = new URL(request.url);
  const cors = corsHeaders(env, request);

  if (request.method === 'OPTIONS') {
    return new Response(null, { status: 204, headers: cors });
  }
  if (request.method !== 'POST') {
    return json({ error: 'method-not-allowed' }, 405, cors);
  }

  let body;
  try {
    body = await request.json();
  } catch (_) {
    return json({ error: 'bad-json' }, 400, cors);
  }
  if (inspectionRoutes.has(url.pathname)) {
    return handleInspection(url.pathname, env, body, cors);
  }
  const { idToken, driverUid } = body || {};
  if (!idToken || !driverUid) {
    return json({ error: 'missing-params' }, 400, cors);
  }

  // Авторизация: проверяем, что вызывает админ.
  try {
    const { role } = await getStaff(env, idToken);
    if (role !== 'admin') throw new Error('not-admin');
  } catch (e) {
    return json({ error: 'unauthorized', detail: String(e.message || e) }, 401, cors);
  }

  const accessToken = await getAccessToken(env);

  if (url.pathname === '/reset-password') {
    const newPassword = body.newPassword;
    if (typeof newPassword !== 'string' || newPassword.length < 6) {
      return json({ error: 'weak-password' }, 400, cors);
    }
    const r = await fetch('https://identitytoolkit.googleapis.com/v1/accounts:update', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + accessToken,
      },
      body: JSON.stringify({ localId: driverUid, password: newPassword }),
    });
    const rj = await r.json();
    if (!r.ok) return json({ error: 'update-failed', detail: rj }, 502, cors);
    return json({ ok: true }, 200, cors);
  }

  if (url.pathname === '/delete-driver') {
    const r = await fetch('https://identitytoolkit.googleapis.com/v1/accounts:delete', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Bearer ' + accessToken,
      },
      body: JSON.stringify({ localId: driverUid }),
    });
    const rj = await r.json();
    if (!r.ok) return json({ error: 'delete-failed', detail: rj }, 502, cors);
    return json({ ok: true }, 200, cors);
  }

  return json({ error: 'not-found' }, 404, cors);
}

export default {
  async scheduled(_controller, env) {
    const { project_id: projectId } = JSON.parse(env.SERVICE_ACCOUNT_JSON);
    const store = firestore(projectId, await getAccessToken(env));
    const result = await issueReadyWaybills(store);
    console.log('Automatic waybill issuance', result);
  },

  async fetch(request, env) {
    try {
      return await handle(request, env);
    } catch (e) {
      if (inspectionRoutes.has(new URL(request.url).pathname)) {
        console.error('Inspection request:', e.message);
        return json({ error: 'internal' }, 500, corsHeaders(env, request));
      }
      return json(
        { error: 'internal', detail: String(e && e.message ? e.message : e) },
        500,
        corsHeaders(env, request)
      );
    }
  },
};
