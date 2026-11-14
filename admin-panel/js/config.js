// Firebase Configuration
const firebaseConfig = {
    apiKey: "AIzaSyDCZolgkxYj6fBvJ_OT1v6o5qVVmVKpuy8",
    authDomain: "project-3077643193540297838.firebaseapp.com",
    projectId: "project-3077643193540297838",
    storageBucket: "project-3077643193540297838.firebasestorage.app",
    messagingSenderId: "126719829029",
    appId: "1:126719829029:web:1314a91c649d4746f44bcc",
    measurementId: "G-M3RTF80GN1"
};

// Initialize Firebase
firebase.initializeApp(firebaseConfig);
const auth = firebase.auth();
const db = firebase.firestore();
// Локальный кэш Firestore (IndexedDB): при повторном открытии сайта списки
// показываются сразу из кэша, а с сервера докачиваются только изменения.
// Если браузер не поддерживает (приватный режим и т.п.) — работаем без кэша.
try {
    db.enablePersistence({ synchronizeTabs: true }).catch(() => {});
} catch (_) {}
// URL бесплатного Cloudflare Worker для серверных операций (смена пароля / удаление).
// Заполняется после деплоя воркера: https://asem-pro-auth.<subdomain>.workers.dev
const AUTH_WORKER_URL = "https://asem-pro-auth.oon66517.workers.dev";
