#!/usr/bin/env python3
"""
Статус версий приложения в RuStore (только чтение, ничего не меняет).

Показывает последние версии: номер, статус (модерация, опубликована,
отклонена и т. п.), тип публикации, даты. Удобно проверить, прошла ли
модерацию версия, отправленная workflow «Publish to RuStore».

Переменные окружения те же, что у publish.py:
  RUSTORE_KEY_ID, RUSTORE_PRIVATE_KEY, RUSTORE_PACKAGE (по умолчанию com.taxopark.driver)
"""
import json

import requests

from publish import BASE, _check, _env, _sign, _timestamp

# Поля версии, которые выводим первыми (остальные — следом, как есть).
MAIN_FIELDS = [
    "versionId", "versionName", "versionCode", "versionStatus", "publishType",
    "sendDateForModer", "publishDateTime", "whatsNew",
]


def main():
    key_id = _env("RUSTORE_KEY_ID", required=True)
    private_key_b64 = _env("RUSTORE_PRIVATE_KEY", required=True).strip().replace("\n", "")
    package = _env("RUSTORE_PACKAGE", "com.taxopark.driver")

    ts = _timestamp()
    r = requests.post(
        f"{BASE}/public/auth/",
        json={"keyId": key_id, "timestamp": ts, "signature": _sign(key_id, ts, private_key_b64)},
        headers={"Content-Type": "application/json"},
        timeout=60,
    )
    headers = {"Public-Token": _check(r, "auth")["body"]["jwe"]}

    r = requests.get(
        f"{BASE}/public/v1/application/{package}/version",
        params={"page": 0, "size": 5},
        headers=headers,
        timeout=60,
    )
    body = _check(r, "versions")["body"]
    versions = body.get("content", body) if isinstance(body, dict) else body
    if not versions:
        print("Версий не найдено")
        return

    for v in versions:
        print("─" * 60)
        for k in MAIN_FIELDS:
            if k in v:
                print(f"{k:18} {v[k]}")
        rest = {k: x for k, x in v.items() if k not in MAIN_FIELDS}
        if rest:
            print("прочее:", json.dumps(rest, ensure_ascii=False)[:1500])


if __name__ == "__main__":
    main()
