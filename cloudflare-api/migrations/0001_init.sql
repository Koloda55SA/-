-- AsemPro: база данных на Cloudflare D1 (замена Firestore + Firebase Auth).
-- Время везде — миллисекунды Unix (UTC). Московское время считается при выводе.

-- Учётные записи. scope разделяет «пространства входа»:
--   driver — водители (приложение), staff — админ/медик/мастер (сайт).
-- Один телефон может быть и водителем, и сотрудником.
CREATE TABLE users (
  id           TEXT PRIMARY KEY,          -- при переносе сохраняем Firebase UID
  scope        TEXT NOT NULL CHECK (scope IN ('driver', 'staff')),
  role         TEXT NOT NULL CHECK (role IN ('driver', 'admin', 'medic', 'mechanic')),
  phone        TEXT NOT NULL,             -- +79991234567
  full_name    TEXT NOT NULL DEFAULT '',
  pass_hash    TEXT,                      -- PBKDF2-SHA256, base64
  pass_salt    TEXT,
  pass_iter    INTEGER,
  active       INTEGER NOT NULL DEFAULT 1,
  -- Сотрудники: данные сертификата для отметки о допуске на ЭПЛ
  cert_serial  TEXT NOT NULL DEFAULT '',
  cert_issued  TEXT NOT NULL DEFAULT '',  -- дд.мм.гггг
  cert_expires TEXT NOT NULL DEFAULT '',
  created_at   INTEGER NOT NULL,
  updated_at   INTEGER,
  UNIQUE (phone, scope)
);

-- Профиль водителя (авто, документы, организация, тариф) — JSON.
CREATE TABLE drivers (
  user_id    TEXT PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  data       TEXT NOT NULL DEFAULT '{}',
  created_at INTEGER NOT NULL,
  updated_at INTEGER
);

-- Сессии входа: храним только SHA-256 от токена.
CREATE TABLE sessions (
  token_hash TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL
);
CREATE INDEX idx_sessions_user ON sessions(user_id);

-- Защита от подбора пароля.
CREATE TABLE login_attempts (
  key      TEXT PRIMARY KEY,
  fails    INTEGER NOT NULL,
  first_at INTEGER NOT NULL
);

-- Путевые листы. Статусы: pending (ждёт допуска), active (выпущен),
-- closed, rejected (не допущен), cancelled (водитель отменил).
-- Отметки медика/мастера — отдельными колонками, чтобы обновлять их атомарно.
CREATE TABLE waybills (
  id          TEXT PRIMARY KEY,
  number      TEXT NOT NULL,
  driver_id   TEXT NOT NULL,
  status      TEXT NOT NULL CHECK (status IN ('pending', 'active', 'closed', 'rejected', 'cancelled')),
  created_at  INTEGER NOT NULL,
  expires_at  INTEGER,
  closed_at   INTEGER,
  med_status  TEXT CHECK (med_status IN ('ok', 'rejected')),
  med_by      TEXT,
  med_at      INTEGER,
  tech_status TEXT CHECK (tech_status IN ('ok', 'rejected')),
  tech_by     TEXT,
  tech_at     INTEGER,
  data        TEXT NOT NULL,              -- все поля листа (как в документе Firestore)
  signature   TEXT                        -- data:image/png;base64,...
);
CREATE INDEX idx_waybills_driver  ON waybills(driver_id, created_at DESC);
CREATE INDEX idx_waybills_status  ON waybills(status, created_at);
CREATE INDEX idx_waybills_created ON waybills(created_at DESC);
-- У водителя не может быть двух запросов на допуск одновременно.
CREATE UNIQUE INDEX idx_waybills_one_pending ON waybills(driver_id) WHERE status = 'pending';

-- Техподдержка: диалог водителя с администратором.
CREATE TABLE support_chats (
  driver_id     TEXT PRIMARY KEY,
  last_message  TEXT NOT NULL DEFAULT '',
  last_sender   TEXT NOT NULL DEFAULT '',
  last_at       INTEGER NOT NULL,
  unread_admin  INTEGER NOT NULL DEFAULT 0,
  unread_driver INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE support_messages (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  driver_id  TEXT NOT NULL,
  sender     TEXT NOT NULL CHECK (sender IN ('driver', 'admin')),
  text       TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE INDEX idx_support_messages ON support_messages(driver_id, id);

-- Бухгалтерия: оплата водителя за месяц.
CREATE TABLE payments (
  driver_id  TEXT NOT NULL,
  period     TEXT NOT NULL,               -- ГГГГ-ММ
  amount     REAL NOT NULL DEFAULT 0,
  paid       INTEGER NOT NULL DEFAULT 0,
  paid_at    INTEGER,
  marked_by  TEXT,
  updated_at INTEGER,
  PRIMARY KEY (driver_id, period)
);

-- CRM-заметки по водителю.
CREATE TABLE driver_notes (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  driver_id  TEXT NOT NULL,
  text       TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  created_by TEXT
);
CREATE INDEX idx_driver_notes ON driver_notes(driver_id, id);

-- Настройки (организация по умолчанию и т.п.), значение — JSON.
CREATE TABLE settings (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

-- Заявки водителей на удаление аккаунта (данные удаляет администратор).
CREATE TABLE deletion_requests (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  user_id      TEXT NOT NULL,
  phone        TEXT NOT NULL,
  requested_at INTEGER NOT NULL,
  status       TEXT NOT NULL DEFAULT 'pending'
);
