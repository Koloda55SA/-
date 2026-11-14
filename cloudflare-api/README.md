# AsemPro API (Cloudflare Workers + D1)

Сервер вместо Firebase: вход по телефону и паролю, водители, путевые листы,
допуск на линию (медик + мастер), сотрудники, техподдержка, бухгалтерия.

## Локальный запуск и проверка

```bash
npm i -g wrangler            # или npx wrangler
cd cloudflare-api
echo BOOTSTRAP_SECRET=local-test-secret > .dev.vars
wrangler d1 migrations apply asem-pro --local
wrangler dev --local --port 8787
node test/smoke.mjs http://127.0.0.1:8787   # 56 сквозных проверок
```

## Выкладка

```bash
wrangler d1 create asem-pro                 # id вписать в wrangler.toml
wrangler d1 migrations apply asem-pro --remote
wrangler secret put BOOTSTRAP_SECRET
wrangler deploy
```

## Роли и доступ

| Роль | Вход | Что может |
|---|---|---|
| `driver` | приложение (`scope: driver`) | свой профиль, запрос допуска, свои листы, чат |
| `medic` | сайт (`scope: staff`) | очередь допуска, отметка «Медосмотр» |
| `mechanic` | сайт (`scope: staff`) | очередь допуска, отметка «Техконтроль» |
| `admin` | сайт (`scope: staff`) | всё, кроме отметок медика и мастера |

Путевой лист: `pending` → (медик `ok` + мастер `ok`) → `active` (12 часов) → `closed`.
Любой отказ → `rejected`, отмена водителем → `cancelled`. Время отметок — серверное.

## Основные адреса

- `POST /api/auth/login` `{phone, password, scope}` → `{token, user}`; далее заголовок `Authorization: Bearer <token>`
- `GET /api/me`, `GET /api/settings`
- Водитель: `GET /api/driver/waybills/current`, `POST /api/driver/waybills` `{odometer, signatureData}`,
  `GET /api/driver/waybills/:id`, `POST …/:id/cancel`, `POST …/:id/close`, `GET /api/driver/stats`,
  `GET|POST /api/driver/support`, `POST /api/driver/support/read`, `POST /api/driver/delete-account`
- Допуск: `GET /api/checks`, `POST /api/checks/:id/mark` `{ok, reason}`
- Админ: `/api/admin/dashboard`, `/api/admin/drivers[/:id[/active|/notes]]`, `/api/admin/users/:id/password`,
  `/api/admin/staff[/:id]`, `/api/admin/waybills`, `/api/admin/settings`, `/api/admin/payments`,
  `/api/admin/support[/:driverId]`, `/api/admin/deletion-requests`
- Публично (QR): `GET /api/public/waybills/:id`
