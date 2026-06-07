#!/usr/bin/env python3
"""
Публикация APK в RuStore через Public API.

Поток (по документации RuStore):
  1) POST /public/auth/         -> получаем JWE-токен (заголовок Public-Token)
  2) POST .../version           -> создаём черновик версии (получаем versionId)
  3) POST .../version/{id}/apk  -> заливаем APK (multipart, поле file)
  4) POST .../version/{id}/commit -> отправляем на модерацию

ВАЖНО: создание черновика через API возможно только если у приложения уже есть
активная версия, а versionCode новой сборки строго больше текущей. Первую
публикацию делают вручную через консоль RuStore.

Подпись авторизации: SHA512withRSA от строки (keyId + timestamp), без разделителя,
результат в Base64. Приватный ключ — Base64 PKCS#8 (как в консоли RuStore).

Переменные окружения:
  RUSTORE_KEY_ID        — Key ID из консоли RuStore (обязательно)
  RUSTORE_PRIVATE_KEY   — приватный ключ, Base64 PKCS#8 (обязательно)
  RUSTORE_APK_PATH      — путь к .apk (обязательно)
  RUSTORE_PACKAGE       — package name (по умолчанию com.taxopark.driver)
  RUSTORE_WHATS_NEW     — текст «Что нового» (необязательно)
  RUSTORE_PUBLISH_TYPE  — MANUAL | INSTANTLY | DELAYED (по умолчанию INSTANTLY)
  RUSTORE_PRIORITY      — приоритет обновления 0..5 (по умолчанию 0)
"""
import base64
import os
import sys
from datetime import datetime, timezone

import requests
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import padding

BASE = "https://public-api.rustore.ru"


def _fail(msg):
    print(f"::error::{msg}", file=sys.stderr)
    sys.exit(1)


def _env(name, default=None, required=False):
    v = os.environ.get(name, default)
    if required and not v:
        _fail(f"Не задана переменная окружения {name}")
    return v


def _timestamp():
    # ISO 8601 с миллисекундами и смещением, например 2023-08-11T13:31:17.580+00:00
    now = datetime.now(timezone.utc)
    return now.strftime("%Y-%m-%dT%H:%M:%S.") + f"{now.microsecond // 1000:03d}+00:00"


def _sign(key_id, timestamp, private_key_b64):
    der = base64.b64decode(private_key_b64)
    private_key = serialization.load_der_private_key(der, password=None)
    message = (key_id + timestamp).encode("utf-8")
    signature = private_key.sign(message, padding.PKCS1v15(), hashes.SHA512())
    return base64.b64encode(signature).decode("ascii")


def _check(resp, step):
    try:
        data = resp.json()
    except Exception:
        _fail(f"[{step}] HTTP {resp.status_code}, не JSON: {resp.text[:500]}")
    if resp.status_code >= 400 or data.get("code") != "OK":
        _fail(f"[{step}] HTTP {resp.status_code}: {data}")
    return data


def main():
    key_id = _env("RUSTORE_KEY_ID", required=True)
    private_key_b64 = _env("RUSTORE_PRIVATE_KEY", required=True).strip().replace("\n", "")
    apk_path = _env("RUSTORE_APK_PATH", required=True)
    package = _env("RUSTORE_PACKAGE", "com.taxopark.driver")
    whats_new = _env("RUSTORE_WHATS_NEW", "")
    publish_type = _env("RUSTORE_PUBLISH_TYPE", "INSTANTLY")
    priority = _env("RUSTORE_PRIORITY", "0")

    if not os.path.isfile(apk_path):
        _fail(f"APK не найден: {apk_path}")

    # 1) Авторизация
    ts = _timestamp()
    signature = _sign(key_id, ts, private_key_b64)
    r = requests.post(
        f"{BASE}/public/auth/",
        json={"keyId": key_id, "timestamp": ts, "signature": signature},
        headers={"Content-Type": "application/json"},
        timeout=60,
    )
    token = _check(r, "auth")["body"]["jwe"]
    headers = {"Public-Token": token}
    print("✓ Авторизация: токен получен")

    # 2) Черновик версии
    body = {"publishType": publish_type}
    if whats_new:
        body["whatsNew"] = whats_new
    r = requests.post(
        f"{BASE}/public/v1/application/{package}/version",
        json=body,
        headers=headers,
        timeout=60,
    )
    data = _check(r, "create-draft")
    version_id = data.get("body")
    if isinstance(version_id, dict):
        version_id = version_id.get("versionId")
    if not version_id:
        _fail(f"Не получен versionId: {data}")
    print(f"✓ Черновик версии создан: versionId={version_id}")

    # 3) Загрузка APK
    with open(apk_path, "rb") as f:
        r = requests.post(
            f"{BASE}/public/v1/application/{package}/version/{version_id}/apk",
            params={"isMainApk": "true", "servicesType": "Unknown"},
            headers=headers,
            files={"file": (os.path.basename(apk_path), f, "application/vnd.android.package-archive")},
            timeout=600,
        )
    _check(r, "upload-apk")
    print("✓ APK загружен")

    # 4) Отправка на модерацию
    r = requests.post(
        f"{BASE}/public/v1/application/{package}/version/{version_id}/commit",
        params={"priorityUpdate": priority},
        headers=headers,
        timeout=120,
    )
    _check(r, "commit")
    print(f"✓ Версия {version_id} отправлена на модерацию (publishType={publish_type})")
    print("Готово. Статус проверяйте в консоли RuStore.")


if __name__ == "__main__":
    main()
