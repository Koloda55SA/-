const FIRESTORE = 'https://firestore.googleapis.com/v1';
const QUEUE = 'waybillInspections';
const SHIFT_MS = 12 * 60 * 60 * 1000;
const RETRY_MS = 60 * 1000;
const ROLES = { med: 'medic', tech: 'mechanic' };
const PAPER_CERTIFICATE_PROFILES = 'waybillCertificateProfiles';
const CRON_BATCH_SIZE = 4;
const MONTHS = ['января', 'февраля', 'марта', 'апреля', 'мая', 'июня',
  'июля', 'августа', 'сентября', 'октября', 'ноября', 'декабря'];

const str = (value) => ({ stringValue: value });
const time = (date) => ({ timestampValue: date.toISOString() });
const field = (doc, key) => doc?.fields?.[key]?.stringValue || '';
export const policyId = (role) => 'autoIssue-' + role;

export function autoIssueEnabled(profile, policy) {
  if (!profile) return false;
  const revision = field(policy, 'revision');
  if (revision && field(profile, 'autoIssueRevision') !== revision) {
    return policy.fields.enabled?.booleanValue === true;
  }
  return profile.fields?.autoIssueEnabled?.booleanValue === true;
}

const docId = (doc) => doc.name.split('/').at(-1);
const validId = (id) => typeof id === 'string' && /^[A-Za-z0-9_-]{1,128}$/.test(id);

function plate(value) {
  return value.replace(/[\s-]/g, '').toUpperCase();
}

function condition(fieldPath, op, value) {
  return { fieldFilter: { field: { fieldPath }, op, value } };
}

export function firestore(projectId, token) {
  const root = 'projects/' + projectId + '/databases/(default)/documents';
  async function request(path, body) {
    const response = await fetch(FIRESTORE + '/' + root + path, {
      method: body ? 'POST' : 'GET',
      headers: { Authorization: 'Bearer ' + token, 'Content-Type': 'application/json' },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (response.ok) return response.json();
    const status = (await response.json().catch(() => null))?.error?.status;
    if (response.status === 404 && !body) return null;
    if (response.status === 409 || (path === ':commit' && status === 'FAILED_PRECONDITION')) {
      throw new Conflict(status);
    }
    throw new Error('Firestore ' + (status || response.status));
  }

  function client(transaction) {
    return {
      get: (collection, id) => request('/' + collection + '/' + encodeURIComponent(id)),
      async query(collectionId, where, limit, options = {}) {
        const rows = await request(':runQuery', {
          structuredQuery: { from: [{ collectionId }], where, limit, ...options },
          transaction,
        });
        return rows.flatMap((row) => row.document ? [row.document] : []);
      },
      async read(names) {
        const rows = await request(':batchGet', { documents: names, transaction });
        return new Map(rows.flatMap((row) => row.found ? [[row.found.name, row.found]] : []));
      },
      name: (collection, id) => root + '/' + collection + '/' + id,
    };
  }

  return {
    ...client(),
    commit: (writes) => request(':commit', { writes }),
    async transaction(operation) {
      const { transaction } = await request(':beginTransaction', { options: { readWrite: {} } });
      try {
        const { result, writes } = await operation(client(transaction));
        if (writes) await request(':commit', { writes, transaction });
        else await request(':rollback', { transaction });
        return result;
      } catch (error) {
        await request(':rollback', { transaction }).catch(() => {});
        throw error;
      }
    },
  };
}

class Conflict extends Error {}

const remove = (doc) => ({ delete: doc.name, currentDocument: { updateTime: doc.updateTime } });

function save(name, fields, current) {
  return {
    update: { name, fields },
    currentDocument: current ? { updateTime: current.updateTime } : { exists: false },
  };
}

function moscow(date) {
  const iso = new Date(date.getTime() + 3 * 3600 * 1000).toISOString();
  const isoDate = iso.slice(0, 10);
  const [year, month, day] = isoDate.split('-');
  return {
    date: [day, month, year].join('.'),
    label: '«' + day + '» ' + MONTHS[Number(month) - 1] + ' ' + year + ' г.',
    time: iso.slice(11, 19),
    isoDate,
  };
}

function isoCertificateDate(value) {
  const parts = /^(\d{2})\.(\d{2})\.(\d{4})$/.exec(value);
  if (!parts) return '';
  const [, day, month, year] = parts;
  const iso = [year, month, day].join('-');
  const stamp = Date.parse(iso);
  return Number.isFinite(stamp) && new Date(stamp).toISOString().slice(0, 10) === iso ? iso : '';
}

function certificate(profile, date) {
  const name = field(profile, 'fullName').trim();
  const serial = field(profile, 'certSerial').trim();
  const issued = field(profile, 'certIssued');
  const expires = field(profile, 'certExpires');
  const from = isoCertificateDate(issued);
  const until = isoCertificateDate(expires);
  const { isoDate } = moscow(date);
  if (!name || !serial || !from || !until || isoDate < from || isoDate > until) return null;
  return { name: str(name), serial: str(serial), issued: str(issued), expires: str(expires) };
}

function certificateFields(prefix, cert) {
  return {
    [prefix + 'Name']: cert.name,
    [prefix + 'CertSerial']: cert.serial,
    [prefix + 'Issued']: cert.issued,
    [prefix + 'Expires']: cert.expires,
  };
}

function usableDriver(doc) {
  return doc && doc.fields?.active?.booleanValue !== false && plate(field(doc, 'plateNumber'));
}

async function paperIssueSettings(store, now) {
  const roles = Object.values(ROLES);
  const profileSettings = store.name('settings', PAPER_CERTIFICATE_PROFILES);
  const settings = await store.read([profileSettings, ...roles.map(role => store.name('settings', policyId(role)))]);
  const staff = await store.query('admins', condition('role', 'IN', {
    arrayValue: { values: roles.map(str) },
  }), undefined, {
    select: { fields: ['role', 'autoIssueEnabled', 'autoIssueRevision', 'fullName', 'certSerial', 'certIssued', 'certExpires']
      .map(fieldPath => ({ fieldPath })) },
  });
  const configuredProfiles = settings.get(profileSettings);
  const certificates = {};
  const namesByPrefix = {};
  for (const [prefix, role] of Object.entries(ROLES)) {
    const policy = settings.get(store.name('settings', policyId(role)));
    const employees = staff.filter(doc => field(doc, 'role') === role);
    const enabled = employees.filter(doc => autoIssueEnabled(doc, policy));
    if (employees.length ? !enabled.length : policy?.fields?.enabled?.booleanValue !== true) return null;
    const profileId = field(configuredProfiles, role);
    if (validId(profileId)) {
      namesByPrefix[prefix] = store.name('admins', profileId);
    } else {
      certificates[prefix] = enabled.map(profile => certificate(profile, now)).find(Boolean);
    }
  }

  const configuredNames = Object.entries(namesByPrefix);
  if (configuredNames.length) {
    const profiles = await store.read(configuredNames.map(([, name]) => name));
    for (const [prefix, name] of configuredNames) {
      certificates[prefix] = certificate(profiles.get(name), now);
    }
  }
  return certificates;
}

function canIssuePending(doc, now) {
  if (field(doc, 'status') !== 'pending') return false;
  const createdAt = Date.parse(doc.fields?.createdAt?.timestampValue);
  return createdAt <= now.getTime() && createdAt > now.getTime() - SHIFT_MS &&
    Object.keys(ROLES).every(prefix => ['', 'ok'].includes(field(doc, prefix + 'Status')));
}

function updateWaybill(pending, fields) {
  return {
    update: { name: pending.name, fields },
    updateMask: { fieldPaths: Object.keys(fields) },
    currentDocument: { updateTime: pending.updateTime },
  };
}

export async function issuePaperWaybill(store, waybillId, expectedUid, now = new Date()) {
  try {
    return await store.transaction(async tx => {
      const billName = tx.name('waybills', waybillId);
      const bill = (await tx.read([billName])).get(billName);
      const uid = field(bill, 'authUid');
      if (!uid || (expectedUid && uid !== expectedUid)) return { result: 'not-found' };
      if (!canIssuePending(bill, now)) return { result: 'unchanged' };

      const certificates = await paperIssueSettings(tx, now);
      if (!certificates) return { result: 'unchanged' };
      const driverId = field(bill, 'driverId');
      if (!validId(driverId)) return { result: 'unchanged' };
      const driverName = tx.name('drivers', driverId);
      const driver = (await tx.read([driverName])).get(driverName);
      if (!usableDriver(driver) || (field(driver, 'authUid') || driverId) !== uid ||
          plate(field(bill, 'plateNumber')) !== plate(field(driver, 'plateNumber'))) {
        return { result: 'unchanged' };
      }
      const waybills = await driverWaybills(tx, uid);
      if (waybills.some(doc => isActive(doc, now)) ||
          waybills.find(doc => field(doc, 'status') === 'pending')?.name !== billName) {
        return { result: 'unchanged' };
      }

      const fields = activation(now);
      for (const prefix of Object.keys(ROLES)) {
        if (field(bill, prefix + 'Status') === 'ok') continue;
        // Реквизиты сертификата печатаются рядом с бумажной отметкой.
        fields[prefix + 'Status'] = str('paper');
        const cert = certificates[prefix];
        if (cert) Object.assign(fields, certificateFields(prefix, cert));
      }
      return { result: 'issued', writes: [updateWaybill(bill, fields)] };
    });
  } catch (error) {
    if (error instanceof Conflict) return 'unchanged';
    throw error;
  }
}

export async function issuePendingPaperWaybills(store, now = new Date()) {
  if (!await paperIssueSettings(store, now)) return 0;
  const requests = await store.query('waybills', condition('status', 'EQUAL', str('pending')), undefined, {
    select: { fields: ['status', 'authUid', 'createdAt', 'medStatus', 'techStatus'].map(fieldPath => ({ fieldPath })) },
  });
  const pending = requests.filter(doc => field(doc, 'authUid') && canIssuePending(doc, now))
    .sort((a, b) => Date.parse(b.fields.createdAt.timestampValue) - Date.parse(a.fields.createdAt.timestampValue));
  const latest = [];
  const seen = new Set();
  for (const bill of pending) {
    const uid = field(bill, 'authUid');
    if (seen.has(uid)) continue;
    seen.add(uid);
    latest.push(bill);
  }
  // Обходим заявки по кругу, чтобы необрабатываемый запрос не задерживал остальных.
  const start = Math.floor(now.getTime() / RETRY_MS) * CRON_BATCH_SIZE % (latest.length || 1);
  const batch = latest.slice(start).concat(latest.slice(0, start)).slice(0, CRON_BATCH_SIZE);
  const results = await Promise.allSettled(batch.map(bill => issuePaperWaybill(store, docId(bill), field(bill, 'authUid'), now)));
  for (const result of results) {
    if (result.status === 'rejected') console.error('Automatic paper waybill issuance:', result.reason.message);
  }
  return results.filter(result => result.status === 'fulfilled' && result.value === 'issued').length;
}

function resultOf(queue, prefix) {
  return queue?.fields?.[prefix]?.mapValue?.fields;
}

function observedAt(result) {
  return Date.parse(result?.observedAt?.timestampValue);
}

function fresh(result, now) {
  const observed = observedAt(result);
  return Number.isFinite(observed) && observed <= now.getTime() && observed > now.getTime() - SHIFT_MS &&
    moscow(new Date(observed)).isoDate === moscow(now).isoDate;
}

export async function findInspectionDriver(store, phone) {
  if (typeof phone !== 'string' || !/^\+\d{10,15}$/.test(phone)) return { error: 'bad-phone', status: 400 };
  const drivers = await store.query('drivers', condition('phone', 'EQUAL', str(phone)), 2, {
    select: { fields: ['fullName', 'plateNumber', 'active'].map((fieldPath) => ({ fieldPath })) },
  });
  if (drivers.length > 1) return { error: 'duplicate-phone', status: 409 };
  const driver = drivers[0];
  if (!usableDriver(driver)) return { error: 'driver-unavailable', status: 404 };
  return { driver: { id: docId(driver), name: field(driver, 'fullName'), plate: field(driver, 'plateNumber') } };
}

export async function recordInspection(store, staff, body, now = new Date()) {
  if (!validId(body.driverId) || typeof body.plate !== 'string' || typeof body.passed !== 'boolean') {
    return { error: 'bad-inspection', status: 400 };
  }
  try {
    return await store.transaction((tx) => writeInspection(tx, staff, body, now));
  } catch (error) {
    if (error instanceof Conflict) return { error: 'inspection-conflict', status: 409 };
    throw error;
  }
}

async function writeInspection(tx, staff, body, now) {
  const driverName = tx.name('drivers', body.driverId);
  const queueName = tx.name(QUEUE, body.driverId);
  const staffName = tx.name('admins', staff.uid);
  const policyName = tx.name('settings', policyId(staff.role));
  const docs = await tx.read([driverName, queueName, staffName, policyName]);
  const driver = docs.get(driverName);
  const previous = docs.get(queueName);
  const profile = docs.get(staffName);
  if (field(profile, 'role') !== staff.role || !autoIssueEnabled(profile, docs.get(policyName))) {
    return { result: { error: 'auto-issue-disabled', status: 403 } };
  }
  const currentPlate = plate(field(driver, 'plateNumber'));
  if (!usableDriver(driver) || currentPlate !== plate(body.plate)) {
    return { result: { error: 'driver-changed', status: 409 } };
  }
  const cert = body.passed ? certificate(profile, now) : null;
  if (body.passed && !cert) return { result: { error: 'certificate-required', status: 409 } };

  const prefix = staff.role === 'medic' ? 'med' : 'tech';
  const fields = {};
  for (const key of Object.keys(ROLES)) {
    const result = resultOf(previous, key);
    if (key !== prefix && fresh(result, now) && result.plate?.stringValue === currentPlate) {
      fields[key] = { mapValue: { fields: result } };
    }
  }
  if (body.passed) {
    fields[prefix] = { mapValue: { fields: {
      ...cert, uid: str(staff.uid), plate: str(currentPlate), observedAt: time(now),
    } } };
  }
  if (!fields.med && !fields.tech) {
    return { result: { ok: true }, writes: previous ? [remove(previous)] : undefined };
  }
  const ready = Boolean(fields.med && fields.tech);
  const observed = observedAt((fields.med || fields.tech).mapValue.fields);
  fields.nextAttemptAt = time(ready ? now : new Date(observed + SHIFT_MS));
  return { result: { ok: true, ready }, writes: [save(queueName, fields, previous)] };
}

function nextAttempt(queue, now) {
  return {
    update: { name: queue.name, fields: { nextAttemptAt: time(new Date(now.getTime() + RETRY_MS)) } },
    updateMask: { fieldPaths: ['nextAttemptAt'] },
    currentDocument: { updateTime: queue.updateTime },
  };
}

function activation(now) {
  const start = moscow(now);
  const expires = new Date(now.getTime() + SHIFT_MS);
  const end = moscow(expires);
  return {
    status: str('active'),
    date: str(start.date),
    dateFormatted: str(start.label),
    shiftStart: str(start.time),
    departureTime: str(start.time),
    shiftEnd: str(end.time),
    shiftEndDate: str(end.date),
    expiresAt: time(expires),
    activatedAt: time(now),
  };
}

function inspectionFields(result, prefix) {
  const observed = new Date(observedAt(result));
  return {
    [prefix + 'Status']: str('ok'),
    [prefix + 'ConfirmedAt']: time(observed),
    [prefix + 'ConfirmedBy']: result.uid,
    ...certificateFields(prefix, result),
    [prefix + 'Time']: str(moscow(observed).time),
  };
}

async function issueForDriver(store, queue, now) {
  return store.transaction((tx) => prepareIssuance(tx, queue, now));
}

async function prepareIssuance(store, queue, now) {
  const med = resultOf(queue, 'med');
  const tech = resultOf(queue, 'tech');
  if (!fresh(med, now) || !fresh(tech, now) || !validId(med.uid?.stringValue) || !validId(tech.uid?.stringValue)) {
    return { result: false, writes: [remove(queue)] };
  }
  const driverId = docId(queue);
  const driverName = store.name('drivers', driverId);
  const medName = store.name('admins', med.uid.stringValue);
  const techName = store.name('admins', tech.uid.stringValue);
  const medPolicy = store.name('settings', policyId(ROLES.med));
  const techPolicy = store.name('settings', policyId(ROLES.tech));
  const docs = await store.read([driverName, medName, techName, medPolicy, techPolicy]);
  const driver = docs.get(driverName);
  const medic = docs.get(medName);
  const mechanic = docs.get(techName);
  const currentPlate = plate(field(driver, 'plateNumber'));
  if (!usableDriver(driver) || med.plate?.stringValue !== currentPlate || tech.plate?.stringValue !== currentPlate ||
      field(medic, 'role') !== ROLES.med || field(mechanic, 'role') !== ROLES.tech ||
      !autoIssueEnabled(medic, docs.get(medPolicy)) || !autoIssueEnabled(mechanic, docs.get(techPolicy))) {
    return { result: false, writes: [remove(queue)] };
  }

  const uid = field(driver, 'authUid') || driverId;
  const waybills = await driverWaybills(store, uid);
  const active = waybills.some(doc => isActive(doc, now));
  const pending = waybills.find((doc) => field(doc, 'status') === 'pending');
  const requestedAt = Date.parse(pending?.fields?.createdAt?.timestampValue);
  if (active || !Number.isFinite(requestedAt) || requestedAt <= now.getTime() - SHIFT_MS ||
      field(pending, 'driverId') !== driverId || plate(field(pending, 'plateNumber')) !== currentPlate ||
      [field(pending, 'medStatus'), field(pending, 'techStatus')].some((status) => status && status !== 'ok')) {
    return { result: false, writes: [nextAttempt(queue, now)] };
  }

  const fields = activation(now);
  // Сохраняем уже записанные ручные результаты.
  if (!field(pending, 'medStatus')) Object.assign(fields, inspectionFields(med, 'med'));
  if (!field(pending, 'techStatus')) Object.assign(fields, inspectionFields(tech, 'tech'));
  return { result: true, writes: [remove(queue), updateWaybill(pending, fields)] };
}

function driverWaybills(store, uid) {
  return store.query('waybills', {
    compositeFilter: { op: 'AND', filters: [
      condition('authUid', 'EQUAL', str(uid)),
      condition('status', 'IN', { arrayValue: { values: [str('pending'), str('active')] } }),
    ] },
  }, undefined, {
    orderBy: [{ field: { fieldPath: 'createdAt' }, direction: 'DESCENDING' }],
    select: { fields: ['status', 'driverId', 'plateNumber', 'createdAt', 'expiresAt', 'medStatus', 'techStatus']
      .map(fieldPath => ({ fieldPath })) },
  });
}

function isActive(doc, now) {
  return field(doc, 'status') === 'active' &&
    Date.parse(doc.fields?.expiresAt?.timestampValue) > now.getTime();
}

export async function issueReadyWaybills(store, now = new Date(), onlyDriver = null, limit = 8) {
  const queue = onlyDriver
    ? [await store.get(QUEUE, onlyDriver)].filter((doc) => resultOf(doc, 'med') && resultOf(doc, 'tech'))
    : await store.query(QUEUE, condition('nextAttemptAt', 'LESS_THAN_OR_EQUAL', time(now)), limit);
  const results = await Promise.allSettled(queue.map((item) => issueForDriver(store, item, now)));
  let issued = 0;
  let failures = 0;
  for (const result of results) {
    if (result.status === 'fulfilled') issued += Number(result.value);
    else if (!(result.reason instanceof Conflict)) {
      failures += 1;
      console.error('Automatic waybill issuance:', result.reason.message);
    }
  }
  return { reviewed: queue.length, issued, failures };
}
