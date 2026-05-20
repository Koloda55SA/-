# Таксопарк

Приложение для управления таксопарком: админ-панель + мобильное приложение для водителей.

## Структура проекта

```
├── admin-panel/          # Веб-панель администратора
│   ├── index.html        # Главная страница
│   ├── css/style.css     # Стили
│   └── js/               # JavaScript модули
│       ├── config.js     # Firebase конфигурация
│       ├── auth.js       # Авторизация
│       ├── drivers.js    # Управление водителями
│       ├── waybills.js   # Путевые листы
│       ├── settings.js   # Настройки компании
│       └── app.js        # Главный модуль
├── mobile-app/           # Flutter мобильное приложение
│   ├── lib/              # Исходный код
│   │   ├── main.dart     # Точка входа
│   │   ├── screens/      # Экраны
│   │   └── services/     # Сервисы (PDF генерация)
│   └── android/          # Android конфигурация
├── firebase/             # Firebase правила и индексы
├── .github/workflows/    # GitHub Actions (сборка APK)
└── .firebaserc           # Firebase проект
```

## Функционал

### Админ-панель (admin-panel)
- Авторизация администратора
- Регистрация новых водителей (создание аккаунта + профиля)
- Управление водителями (активация/деактивация/удаление)
- Просмотр путевых листов
- Настройки компании

### Мобильное приложение (mobile-app)
- Вход водителя по email/паролю
- Просмотр профиля
- Генерация путевого листа (PDF)
- История путевых листов

## Технологии
- **Frontend:** HTML/CSS/JS + Firebase SDK
- **Mobile:** Flutter + Firebase
- **Backend:** Firebase (Firestore + Authentication)
- **Hosting:** Cloudflare Pages (админ-панель)
- **CI/CD:** GitHub Actions (сборка APK)

## Деплой

### Админ-панель
Хостится на Cloudflare Pages: https://taxopark-admin.pages.dev/

### APK
Собирается автоматически через GitHub Actions при пуше в main.
Скачать APK можно в разделе Releases.

## Настройка

1. Включить Firestore API в Google Cloud Console
2. Включить Email/Password Authentication в Firebase Console
3. Создать первого администратора через Firebase Console
4. Заполнить настройки компании в админ-панели
